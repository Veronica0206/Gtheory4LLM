"""Compare live branch protection with the declared repository policy.

This reads the GitHub API through `gh` and changes nothing: no settings are
written, no branch is touched, no release is published. Applying the policy is
a maintainer action documented in docs/REPOSITORY_POLICY.md.

What this cannot do matters as much as what it can. Without `gh`, without
authentication, or without admin rights on the repository, the protection
endpoint is unavailable and this reports `unverified`. An unverified report is
not a passing report, and --require treats it as a failure.
"""
from __future__ import annotations

import argparse
import json
from itertools import product
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "docs/branch-protection.json"
WORKFLOWS = ROOT / ".github/workflows"


def repository_slug(root: Path) -> str | None:
    """Read owner/name from the origin remote without contacting it."""
    try:
        url = subprocess.check_output(["git", "-C", str(root), "remote", "get-url", "origin"],
                                      text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    match = re.search(r"[/:]([^/:]+)/([^/]+?)(?:\.git)?$", url)
    return f"{match[1]}/{match[2]}" if match else None


class WorkflowInventoryError(ValueError):
    """A workflow cannot be inventoried without guessing its check names."""


def _scalar(value: str) -> str:
    """Read a literal matrix scalar, rejecting expressions and YAML features."""
    value = value.strip()
    if re.fullmatch(r"'(?:[^']|'')*'", value):
        return value[1:-1].replace("''", "'")
    if value.startswith('"'):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError as failure:
            raise WorkflowInventoryError(f"unsupported quoted scalar: {value}") from failure
        if isinstance(parsed, str):
            return parsed
    # Do not mistake YAML's implicit null/number conversion for literal text.
    # Versions and numeric-looking labels can always be quoted explicitly.
    if value.lower() == "null" or (value.lower() in {"true", "false"} and value not in {"true", "false"}):
        raise WorkflowInventoryError(f"matrix scalar must be quoted: {value}")
    if re.match(r"[+-]?[0-9]", value) and not re.fullmatch(r"-?(?:0|[1-9][0-9]*)", value):
        raise WorkflowInventoryError(f"numeric-looking matrix scalar must be quoted: {value}")
    if re.fullmatch(r"[A-Za-z0-9_./+ -]+", value):
        return value
    raise WorkflowInventoryError(f"unsupported matrix scalar: {value}")


def _matrix_rows(body: str) -> list[dict[str, str]] | None:
    """Expand literal axes or include-only rows; refuse every other form.

    Supported axes use a one-line flow sequence or an indented scalar list.
    Include/exclude combinations, expressions, nested values and YAML aliases
    must be implemented explicitly before they can become a merge gate.
    """
    strategy = re.search(r"(?ms)^    strategy:(.*?)(?=^ {0,4}\S|\Z)", body)
    if strategy is None:
        return None
    strategy_lines = [line for line in strategy[1].splitlines()
                      if line.strip() and not line.lstrip().startswith("#")]
    if not strategy_lines or not re.match(r"^      \S", strategy_lines[0]):
        raise WorkflowInventoryError("strategy must use a literal block with two-space indentation")
    seen_strategy: set[str] = set()
    for line in strategy_lines:
        if re.match(r"^ {0,6}\S", line):
            field = re.fullmatch(r"      (fail-fast|max-parallel|matrix):\s*(.*?)\s*", line)
            if not field or field[1] in seen_strategy:
                raise WorkflowInventoryError("unsupported or duplicate strategy key")
            seen_strategy.add(field[1])
            if field[1] != "matrix":
                _scalar(field[2])
    matrix = re.search(r"(?ms)^      matrix:(.*?)(?=^ {0,6}\S|\Z)", strategy[1])
    if matrix is None:
        # A strategy with only fail-fast/max-parallel is not a matrix job.
        if any(re.match(r"^ {7,}\S", line) for line in strategy_lines):
            raise WorkflowInventoryError("unsupported nested strategy mapping")
        return None
    lines = [line for line in matrix.group(1).splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    if not lines:
        raise WorkflowInventoryError("empty matrix")
    # The matrix key must introduce a block, not an expression or inline map.
    if not lines[0].startswith("        "):
        raise WorkflowInventoryError("matrix must be a literal block mapping")
    fields: dict[str, list[str]] = {}
    includes: list[dict[str, str]] = []
    axis = None
    seen: set[str] = set()
    inline_axes: set[str] = set()
    for line in lines:
        field = re.fullmatch(r"        ([A-Za-z_][A-Za-z0-9_-]*):\s*(.*?)\s*", line)
        if field:
            axis, value = field.groups()
            if axis == "exclude":
                raise WorkflowInventoryError("matrix exclude is not supported by the inventory")
            if axis in seen:
                raise WorkflowInventoryError(f"duplicate matrix field: {axis}")
            seen.add(axis)
            if axis == "include":
                if value or fields:
                    raise WorkflowInventoryError("only block include-only matrices are supported")
                continue
            if "include" in seen:
                raise WorkflowInventoryError("combining matrix axes and include is not supported")
            fields[axis] = []
            if value:
                if not (value.startswith("[") and value.endswith("]")):
                    raise WorkflowInventoryError(f"matrix axis {axis} must be a literal sequence")
                # Commas inside scalar values are outside this constrained form.
                fields[axis] = [_scalar(part) for part in value[1:-1].split(",")]
                inline_axes.add(axis)
            continue
        if axis == "include":
            entry = re.fullmatch(r"          - ([A-Za-z_][A-Za-z0-9_-]*):\s*(.+)", line)
            if entry:
                includes.append({entry[1]: _scalar(entry[2])})
                continue
            entry = re.fullmatch(r"            ([A-Za-z_][A-Za-z0-9_-]*):\s*(.+)", line)
            if entry and includes:
                if entry[1] in includes[-1]:
                    raise WorkflowInventoryError(f"duplicate matrix include field: {entry[1]}")
                includes[-1][entry[1]] = _scalar(entry[2])
                continue
        elif axis is not None:
            entry = re.fullmatch(r"          - (.+)", line)
            if entry:
                if axis in inline_axes:
                    raise WorkflowInventoryError("axis cannot mix inline and block sequences")
                fields[axis].append(_scalar(entry[1]))
                continue
        raise WorkflowInventoryError(f"unsupported matrix line: {line.strip()}")
    if includes:
        return includes
    if not fields or any(not values for values in fields.values()):
        raise WorkflowInventoryError("matrix has no complete literal combinations")
    return [dict(zip(fields, values)) for values in product(*fields.values())]


def workflow_job_names(root: Path) -> set[str]:
    """Inventory every job context from this repository's static YAML subset.

    This has no YAML dependency, so unsupported syntax fails explicitly rather
    than silently dropping jobs. Both literal matrix axes and include-only
    rows are supported. Matrix jobs must have an explicit, resolvable name.
    """
    contexts: set[str] = set()
    workflows = root / ".github/workflows"
    paths = sorted([*workflows.glob("*.yml"), *workflows.glob("*.yaml")])
    if not paths:
        raise WorkflowInventoryError("no workflow files found")
    for path in paths:
        text = path.read_text(encoding="utf-8")
        # YAML comment-only lines have no indentation boundary. Remove them
        # before finding any jobs/strategy/matrix block, including comments
        # at column zero inside an otherwise indented mapping. Quoted values
        # containing '#' remain untouched.
        text = "\n".join(line for line in text.splitlines()
                         if not line.lstrip().startswith("#")) + "\n"
        jobs = re.search(r"(?ms)^jobs:\s*\n(.*?)(?=^\S|\Z)", text)
        if jobs is None:
            raise WorkflowInventoryError(f"{path.name}: jobs must be a block mapping")
        entries = re.findall(r"(?ms)^  ([A-Za-z0-9_-]+):\s*\n(.*?)(?=^  \S|\Z)", jobs[1])
        declared = [line for line in jobs[1].splitlines()
                    if re.match(r"^  \S", line) and not line.lstrip().startswith("#")]
        if not entries or len(entries) != len(declared):
            raise WorkflowInventoryError(f"{path.name}: unsupported job mapping")
        for job_id, body in entries:
            try:
                body_lines = [line for line in body.splitlines()
                              if line.strip() and not line.lstrip().startswith("#")]
                if not body_lines or not re.match(r"^    \S", body_lines[0]):
                    raise WorkflowInventoryError("job fields must use two-space indentation")
                for line in body_lines:
                    if re.match(r"^ {0,4}\S", line) and not re.match(r"^    [A-Za-z0-9_-]+:", line):
                        raise WorkflowInventoryError("unsupported job field mapping")
                rows = _matrix_rows(body)
                name = re.search(r"(?m)^    name:\s*(.+?)\s*$", body)
                if name is None:
                    if rows is not None:
                        raise WorkflowInventoryError("matrix jobs must have an explicit name")
                    contexts.add(job_id)
                    continue
                template = name[1]
                if template.startswith(("'", '"')):
                    template = _scalar(template)
                fields = re.findall(r"\$\{\{\s*matrix\.([A-Za-z0-9_-]+)\s*\}\}", template)
                if rows is None and fields:
                    raise WorkflowInventoryError("job name references a missing matrix")
                if rows is not None and not fields:
                    raise WorkflowInventoryError("matrix job name must identify its matrix entries")
                expanded: set[str] = set()
                for values in rows if rows is not None else [{}]:
                    missing = set(fields) - values.keys()
                    if missing:
                        raise WorkflowInventoryError("job name fields missing from matrix: " +
                                                     ", ".join(sorted(missing)))
                    resolved = re.sub(r"\$\{\{\s*matrix\.([A-Za-z0-9_-]+)\s*\}\}",
                                      lambda match: values[match[1]], template)
                    if "${{" in resolved or resolved in ("|", ">"):
                        raise WorkflowInventoryError("job name is not a supported literal template")
                    if resolved in expanded:
                        raise WorkflowInventoryError("matrix entries produce duplicate job names")
                    expanded.add(resolved)
                    contexts.add(resolved)
            except WorkflowInventoryError as failure:
                raise WorkflowInventoryError(f"{path.name}, job {job_id}: {failure}") from failure
    return contexts


def live_protection(slug: str) -> tuple[dict | None, str | None]:
    try:
        result = subprocess.run(["gh", "api", f"repos/{slug}/branches/main/protection"],
                                capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        return None, "gh is not installed; install the GitHub CLI to verify protection"
    except (OSError, subprocess.SubprocessError) as failure:
        return None, f"gh invocation failed: {failure}"
    if result.returncode:
        detail = (result.stderr or result.stdout).strip().splitlines()
        return None, "gh could not read branch protection: " + (detail[-1] if detail else "no detail")
    try:
        return json.loads(result.stdout), None
    except json.JSONDecodeError:
        return None, "gh returned output that is not JSON"


def compare(policy: dict, live: dict) -> list[str]:
    """Report every requirement the live settings do not meet."""
    problems: list[str] = []
    checks = live.get("required_status_checks") or {}
    required = set(policy["required_status_checks"]["contexts"])
    present = set(checks.get("contexts") or [context["context"] for context in checks.get("checks", [])])
    missing = sorted(required - present)
    if missing:
        problems.append("required status checks missing: " + ", ".join(missing))
    if policy["required_status_checks"]["strict"] and not checks.get("strict"):
        problems.append("required status checks are not strict: a stale branch can merge")
    reviews = live.get("required_pull_request_reviews") or {}
    wanted_reviews = policy["required_pull_request_reviews"]
    if reviews.get("required_approving_review_count", 0) < wanted_reviews["required_approving_review_count"]:
        problems.append("required approving reviews below policy")
    if wanted_reviews["dismiss_stale_reviews"] and not reviews.get("dismiss_stale_reviews"):
        problems.append("stale reviews are not dismissed")
    for field, label in (("enforce_admins", "administrators are not covered"),
                         ("required_linear_history", "linear history is not required"),
                         ("required_conversation_resolution", "conversation resolution is not required")):
        if policy.get(field) and not (live.get(field) or {}).get("enabled"):
            problems.append(label)
    for field, label in (("allow_force_pushes", "force pushes are allowed"),
                         ("allow_deletions", "branch deletion is allowed")):
        if not policy.get(field) and (live.get(field) or {}).get("enabled"):
            problems.append(label)
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repository", help="owner/name; defaults to the origin remote")
    parser.add_argument("--require", action="store_true",
                        help="exit non-zero unless protection was verified and matches the policy")
    options = parser.parse_args(argv)

    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    report = {"policy": str(POLICY.relative_to(ROOT)), "verified": False, "matches": None,
              "problems": [], "unverified_reason": None}

    # A context no job produces blocks every merge, so check that first: it is
    # a defect in the policy itself and needs no network access to find.
    declared = set(policy["required_status_checks"]["contexts"])
    try:
        produced = workflow_job_names(ROOT)
    except WorkflowInventoryError as failure:
        report["problems"].append("workflow context inventory failed: " + str(failure))
        print(json.dumps(report, indent=2))
        return 1
    unproduced = sorted(declared - produced)
    if unproduced:
        report["problems"].append(
            "policy requires contexts no workflow job produces: " + ", ".join(unproduced))
    unrequired = sorted(produced - declared)
    if unrequired:
        report["problems"].append(
            "workflow jobs absent from required contexts: " + ", ".join(unrequired))
    report["workflow_contexts"] = sorted(produced)

    slug = options.repository or repository_slug(ROOT)
    if slug is None:
        report["unverified_reason"] = "no origin remote to identify the repository"
    else:
        report["repository"] = slug
        live, reason = live_protection(slug)
        if live is None:
            report["unverified_reason"] = reason
        else:
            report["verified"] = True
            report["problems"].extend(compare(policy, live))
            report["matches"] = not report["problems"]

    print(json.dumps(report, indent=2))
    if not options.require:
        return 0
    return 0 if report["verified"] and report["matches"] else 1


if __name__ == "__main__":
    sys.exit(main())
