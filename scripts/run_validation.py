"""Validate public sources and the separately committed release artifact.

The default --scope all performs both checks. Use --scope source while preparing
new sources, or --scope artifact to check the committed bundle without rebuilding
it. Exact R/dependency versions are mandatory unless --compatibility explicitly
requests a cross-platform/current-dependency check. No private research archive is
required. Python >= 3.10 is required; no third-party Python packages are needed.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ("OpenMx", "lme4", "ordinal")
COMPACT_TESTS = {"test_design.R", "test_examples.R", "test_gaussian_review.R", "test_discrete.R"}


def tex_available() -> bool:
    """Whether a LaTeX engine is present to render the reference manual.

    R CMD check runs with --no-manual so the package check does not require TeX
    on every platform, and R CMD check would accept overfull boxes in any case.
    scripts/build_manual.R is the only gate that rejects them, so it runs here
    wherever it can rather than only by hand at release time.
    """
    return shutil.which("pdflatex") is not None


def manual_stage(root: Path, rscript: str) -> tuple[str, list[str]]:
    directory = os.environ.get("GTHEORY_MANUAL_CHECK_DIR")
    target = Path(directory) if directory else Path(tempfile.mkdtemp(prefix="gtheory-manual-"))
    return ("reference_manual", [rscript, "--vanilla", str(root / "scripts/build_manual.R"),
                                 str(target / "Gtheory4LLM-manual.pdf"), str(target / "work")])


def preflight_code(lock: dict, allow_version_drift: bool) -> str:
    required = ",".join(json.dumps(p) for p in REQUIRED)
    expected = ",".join(f"{json.dumps(p)}={json.dumps(info['Version'])}"
                        for p, info in sorted(lock["Packages"].items()))
    strict = "FALSE" if allow_version_drift else "TRUE"
    return f'''
required <- c({required})
cat("R dependency preflight started: ", R.version.string, "\\n", sep="")
flush.console()
if (getRversion() < "4.5.0") stop("Compatibility validation requires R >= 4.5.0")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly=TRUE)]
if (length(missing)) stop("Full validation requires: ", paste(missing, collapse=", "))
expected <- c({expected})
actual <- vapply(names(expected), function(p) {{
  if (!requireNamespace(p, quietly=TRUE)) return(NA_character_)
  packageDescription(p, fields="Version")
}}, character(1))
wrong <- is.na(actual) | actual != expected
strict <- {strict}
if (strict && as.character(getRversion()) != {json.dumps(lock['R']['Version'])})
  stop("R version does not match renv.lock")
if (strict && any(wrong)) {{
  print(data.frame(package=names(expected)[wrong], expected=expected[wrong], actual=actual[wrong]), row.names=FALSE)
  stop("Dependency versions do not match renv.lock")
}}
if (!strict) cat("Compatibility mode: installed versions are reported; this is not the locked-environment gate.\\n")
cat("Required independent comparisons: ", paste(required, collapse=", "), "\\n", sep="")
print(sessionInfo())
'''


def commands(root: Path, rscript: str, lock: dict, allow_version_drift: bool,
             scope: str = "all", compact: bool = False, as_cran: bool = False) -> list[tuple[str, list[str]]]:
    result = [("dependency_preflight", [rscript, "--vanilla", "-e", preflight_code(lock, allow_version_drift)])]
    if scope in {"source", "all"}:
        result.append(("python_regressions", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py", "-v"]))
        r_tests = sorted((root / "tests").glob("test_*.R"))
        if compact:
            r_tests = [path for path in r_tests if path.name in COMPACT_TESTS]
        if not r_tests:
            raise ValueError("No public R regression tests found")
        result.extend((str(p.relative_to(root)), [rscript, "--vanilla", str(p)]) for p in r_tests)
        if not compact:
            result.append(("standalone_example", [rscript, "--vanilla", str(root / "examples/standalone_usage.R")]))
        # Rendered documentation is source, so it is gated with the sources. The
        # stage is omitted rather than faked where no LaTeX engine exists; the
        # report says which happened so a skipped run is not read as a pass.
        if tex_available():
            result.append(manual_stage(root, rscript))
        package_command = [sys.executable, str(root / "scripts/check_package.py"), "--rscript", rscript]
        if as_cran: package_command.append("--as-cran")
        result.append(("package_build_install_check", package_command))
    if scope in {"artifact", "all"}:
        command = [sys.executable, str(root / "scripts/check_committed_artifact.py"), "--rscript", rscript]
        artifact_dir = os.environ.get("GTHEORY_ARTIFACT_CHECK_DIR")
        if artifact_dir:
            command.extend(["--output-dir", artifact_dir])
        result.append(("committed_artifact_integrity_install_smoke", command))
    return result


def launch(command: list[str], *, environment: dict, timeout: int):
    # Windows Rscript can crash on multiline/complex -e arguments before R
    # starts. Run generated code from a closed UTF-8 file on every platform.
    if len(command) >= 4 and command[1:3] == ["--vanilla", "-e"]:
        with tempfile.TemporaryDirectory(prefix="gtheory-r-invocation-") as directory:
            script = Path(directory) / "generated.R"
            script.write_bytes(command[3].encode("utf-8"))
            return subprocess.run([command[0], "--vanilla", str(script), *command[4:]],
                                  cwd=ROOT, env=environment, timeout=timeout, check=False)
    return subprocess.run(command, cwd=ROOT, env=environment, timeout=timeout, check=False)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--as-cran", action="store_true", help="Include CRAN incoming checks in the source package stage.")
    parser.add_argument("--library", type=Path, help="Restored library exposed to each clean R process.")
    parser.add_argument("--scope", choices=("source", "artifact", "all"), default="all")
    parser.add_argument("--compatibility", action="store_true", help="Validate supported current/older R and installed dependencies without asserting lock parity.")
    parser.add_argument("--allow-version-drift", action="store_true", help="Deprecated alias for --compatibility.")
    parser.add_argument("--compact", action="store_true", help="Compatibility source subset plus all installed-package tests; not the full source gate.")
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--timeout", type=int, default=1800, help="Maximum seconds per stage.")
    parser.add_argument("--output", type=Path, help="Explicit optional summary JSON destination.")
    options = parser.parse_args(argv)
    if options.timeout <= 0:
        parser.error("--timeout must be positive")
    compatibility = options.compatibility or options.allow_version_drift
    if options.compact and not compatibility:
        parser.error("--compact requires --compatibility")
    lock = json.loads((ROOT / "renv.lock").read_text())
    plan = commands(ROOT, options.rscript, lock, compatibility, options.scope, options.compact, options.as_cran)
    if options.preflight_only:
        plan = plan[:1]
    if options.list:
        print("\n".join(name for name, _ in plan))
        return 0
    resolved_rscript = shutil.which(options.rscript)
    if resolved_rscript is None:
        parser.error("Rscript was not found")
    env = os.environ.copy()
    env.update({"GTHEORY_FULL_VALIDATION": "true", "PYTHONDONTWRITEBYTECODE": "1",
                "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1"})
    if options.library:
        if not options.library.is_dir():
            parser.error("--library must name an existing restored R library")
        env["R_LIBS_USER"] = str(options.library.resolve())
    mode = "preflight_only" if options.preflight_only else "compatibility" if compatibility else "locked"
    report = {"started_utc": datetime.now(timezone.utc).isoformat(), "mode": mode,
              "scope": options.scope, "compact": options.compact, "as_cran": options.as_cran,
              "required_independent_comparisons": list(REQUIRED), "stages": []}
    passed = True
    print("Selected Rscript: " + resolved_rscript, flush=True)
    for name, command in plan:
        print(f"\n=== {name} ===", flush=True)
        start = time.monotonic()
        try:
            status = launch(command, environment=env, timeout=options.timeout).returncode
            detail = None
        except subprocess.TimeoutExpired:
            status, detail = 124, f"Stage exceeded {options.timeout} seconds"
        report["stages"].append({"name": name, "exit_code": status,
                                  "elapsed_seconds": round(time.monotonic() - start, 3), "detail": detail})
        if status != 0:
            print(f"FAILED: {name} (exit {status})", flush=True)
            passed = False
            break
    done = {step["name"] for step in report["stages"] if step["exit_code"] == 0}
    report.update({"finished_utc": datetime.now(timezone.utc).isoformat(), "success": passed,
                   "reference_manual_checked": "reference_manual" in done,
                   "reference_manual_skipped_reason": None if tex_available() else
                       "No LaTeX engine (pdflatex) on PATH; scripts/build_manual.R was not run.",
                   "source_validation_passed": "package_build_install_check" in done,
                   "committed_artifact_validation_passed": "committed_artifact_integrity_install_smoke" in done,
                   "full_locked_validation_passed": passed and mode == "locked" and options.scope == "all" and not options.compact})
    if options.output:
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
