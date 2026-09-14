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


def workflow_job_names(root: Path) -> set[str]:
    """Job names the workflows would report as status-check contexts.

    A job with an explicit `name:` reports that name, expanding a matrix. This
    parses the deliberately simple YAML in this repository rather than adding a
    dependency; it exists to catch a policy naming a context no job produces.
    """
    contexts: set[str] = set()
    for path in sorted(WORKFLOWS.glob("*.yml")):
        text = path.read_text(encoding="utf-8")
        jobs = re.search(r"(?ms)^jobs:\n(.*)\Z", text)
        if jobs is None:
            continue
        for job_id, body in re.findall(r"(?ms)^  ([A-Za-z0-9_-]+):\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)",
                                       jobs.group(1)):
            name = re.search(r"(?m)^    name:\s*(.+?)\s*$", body)
            if name is None:
                contexts.add(job_id)
                continue
            template = name.group(1)
            fields = re.findall(r"\$\{\{\s*matrix\.([A-Za-z0-9_]+)\s*\}\}", template)
            if not fields:
                contexts.add(template)
                continue
            entries = re.findall(r"(?ms)^          - (.*?)(?=^          - |\Z)", body)
            for entry in entries:
                values = dict(re.findall(r"(?m)^\s*([A-Za-z0-9_]+):\s*'?\"?([^'\"\n]+?)'?\"?\s*$", entry))
                if not all(field in values for field in fields):
                    continue
                resolved = template
                for field in fields:
                    resolved = re.sub(rf"\$\{{\{{\s*matrix\.{field}\s*\}}\}}", values[field], resolved)
                contexts.add(resolved)
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
    produced = workflow_job_names(ROOT)
    unproduced = sorted(declared - produced)
    if unproduced:
        report["problems"].append(
            "policy requires contexts no workflow job produces: " + ", ".join(unproduced))
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
