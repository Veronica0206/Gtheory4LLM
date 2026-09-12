"""Build a public CRAN candidate, then check that exact archive without rebuilding.

This tool never uploads to CRAN or changes Git state. Build with current R release;
check with R-devel and TeX. GitHub Actions selects those runtimes explicitly.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import time

sys.dont_write_bytecode = True
from check_package import check_status, sanitize
from check_public_contents import PublicAudit

ROOT = Path(__file__).resolve().parents[1]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean_commit(root: Path) -> str:
    status = subprocess.check_output(
        ["git", "-C", str(root), "status", "--porcelain", "--untracked-files=all"], text=True)
    if status.strip():
        raise ValueError("CRAN candidates require clean, committed sources.")
    return subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()


def candidate_input(directory: Path, expected_commit: str) -> tuple[dict, Path]:
    manifest = json.loads((directory / "candidate.json").read_text())
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        raise ValueError("Unsupported candidate manifest schema.")
    package, version = manifest.get("package", ""), manifest.get("version", "")
    if (not isinstance(package, str) or not isinstance(version, str) or
            not re.fullmatch(r"[A-Za-z][A-Za-z0-9.]+", package) or not re.fullmatch(r"[0-9][0-9.-]*", version)):
        raise ValueError("Invalid candidate package name or version.")
    if manifest.get("archive") != f"{package}_{version}.tar.gz":
        raise ValueError("Candidate archive must be a package basename.")
    if manifest.get("source_commit") != expected_commit:
        raise ValueError("Downloaded candidate source commit differs from the checked-out source.")
    archive = directory / manifest["archive"]
    if archive.is_symlink() or not archive.is_file():
        raise ValueError("Candidate archive must be a regular file.")
    if archive.stat().st_size != manifest.get("bytes") or digest(archive) != manifest.get("sha256"):
        raise ValueError("Candidate archive size or SHA-256 differs from its build manifest.")
    return manifest, archive


def manual_checked(log: str) -> bool:
    return bool(re.search(r"^\* checking PDF version of manual \.\.\. (?:\[[^]]+\] )?OK\s*$", log, re.M))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("build", "check"))
    parser.add_argument("--output-dir", required=True, type=Path, help="New empty directory outside the source checkout.")
    parser.add_argument("--candidate-dir", type=Path, help="Downloaded build artifact containing candidate.json and its tarball.")
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--require-devel", action="store_true", help="Fail if the checker is not R-devel or a prerelease.")
    parser.add_argument("--expected-data-kind", choices=("synthetic", "public_llm_annotations"), default="public_llm_annotations")
    args = parser.parse_args()
    work = args.output_dir.resolve()
    if work == ROOT or ROOT in work.parents:
        parser.error("Output must be outside the source checkout.")
    if work.exists() and any(work.iterdir()):
        parser.error("Output directory must be empty to avoid retaining stale results.")
    work.mkdir(parents=True, exist_ok=True)
    report = {"mode": args.mode, "success": False, "steps": [], "submission_performed": False}
    environment = os.environ.copy()
    environment.update({"R_PROFILE_USER": os.devnull, "R_ENVIRON_USER": os.devnull,
                        "OMP_NUM_THREADS": "1", "OPENBLAS_NUM_THREADS": "1",
                        "_R_CHECK_CRAN_INCOMING_REMOTE_": "true", "_R_CHECK_FORCE_SUGGESTS_": "true"})

    def portable(value):
        value = sanitize(value, work)
        if isinstance(value, dict): return {k: portable(v) for k, v in value.items()}
        if isinstance(value, list): return [portable(v) for v in value]
        if isinstance(value, str) and args.candidate_dir:
            value = value.replace(str(args.candidate_dir.resolve()), "<downloaded-candidate>")
        return value

    def run(name, command, cwd=work):
        started = time.monotonic()
        result = subprocess.run(command, cwd=cwd, env=environment, capture_output=True, text=True)
        output = portable(result.stdout + result.stderr)
        (work / (name + ".log")).write_text(output)
        print(output, flush=True)
        report["steps"].append({"name": name, "exit_code": result.returncode,
                                "elapsed_seconds": round(time.monotonic() - started, 3)})
        if result.returncode:
            raise RuntimeError(name + " failed; inspect its retained log.")
        return result.stdout

    try:
        source_commit = clean_commit(ROOT)
        report["source_commit"] = source_commit
        runtime_script = work / "runtime.R"
        runtime_script.write_bytes(
            'cat(R.home("bin"), as.character(getRversion()), R.version$status, R.version.string, sep="\\n")'.encode("utf-8"))
        info = run("runtime", [args.rscript, "--vanilla", str(runtime_script)]).splitlines()
        r = str(Path(info[0]) / ("R.exe" if os.name == "nt" else "R"))
        report.update({"r_version": info[1], "r_status": info[2], "r_version_string": info[3]})
        if args.mode == "build":
            if info[2] not in ("", "Patched"):
                raise ValueError("Build the source candidate with released or patched R, not R-devel.")
            audit = PublicAudit(ROOT, args.expected_data_kind)
            audit.working_tree()
            audit.history()
            (work / "public_source_audit.json").write_text(json.dumps(portable(audit.report()), indent=2) + "\n")
            if audit.findings:
                raise ValueError("Source or Git history failed the public-content audit.")
            run("package_data", [args.rscript, "--vanilla", str(ROOT / "scripts/build_package_data.R"), "--verify-only"], ROOT)
            run("build", [r, "CMD", "build", str(ROOT)])
            archives = list(work.glob("*.tar.gz"))
            if len(archives) != 1:
                raise ValueError("Build must produce exactly one source tarball.")
            archive = archives[0]
            package, version = archive.name.removesuffix(".tar.gz").rsplit("_", 1)
            public_archive = PublicAudit(ROOT, args.expected_data_kind)
            public_archive.inspect_archive(archive.read_bytes(), archive.name)
            (work / "public_archive_audit.json").write_text(json.dumps(portable(public_archive.report()), indent=2) + "\n")
            if public_archive.findings:
                raise ValueError("Built source archive failed the public-content audit.")
            manifest = {"schema_version": 1, "package": package, "version": version,
                        "source_commit": source_commit, "archive": archive.name,
                        "sha256": digest(archive), "bytes": archive.stat().st_size,
                        "build_r_version": info[1], "build_r_status": info[2],
                        "expected_data_kind": args.expected_data_kind}
            (work / "candidate.json").write_text(json.dumps(manifest, indent=2) + "\n")
            report["candidate"] = manifest
        else:
            if not args.candidate_dir:
                raise ValueError("check requires --candidate-dir; it never rebuilds an archive.")
            devel = bool(re.search(r"development|alpha|beta|rc", info[2], re.I))
            if args.require_devel and not devel:
                raise ValueError("This readiness check requires R-devel or an R prerelease.")
            report["r_devel_checked"] = devel
            manifest, incoming = candidate_input(args.candidate_dir.resolve(), source_commit)
            if manifest.get("expected_data_kind") != args.expected_data_kind:
                raise ValueError("Candidate data kind differs from the explicitly selected public kind.")
            archive = work / incoming.name
            shutil.copyfile(incoming, archive)
            shutil.copyfile(args.candidate_dir / "candidate.json", work / "candidate.json")
            public_archive = PublicAudit(ROOT, args.expected_data_kind)
            public_archive.inspect_archive(archive.read_bytes(), archive.name)
            (work / "public_archive_audit.json").write_text(json.dumps(portable(public_archive.report()), indent=2) + "\n")
            if public_archive.findings:
                raise ValueError("Downloaded source archive failed the public-content audit.")
            session_script = work / "session.R"
            session_script.write_bytes("print(sessionInfo()); print(installed.packages()[, c('Package', 'Version')])".encode("utf-8"))
            run("session", [args.rscript, "--vanilla", str(session_script)])
            library = work / "library"
            library.mkdir()
            run("check", [r, "CMD", "check", "--as-cran", "--timings", "--library=" + str(library), str(archive)])
            log = (work / (manifest["package"] + ".Rcheck") / "00check.log").read_text()
            report["r_cmd_check"] = check_status(log, as_cran=True)
            if not manual_checked(log):
                raise ValueError("R CMD check did not confirm successful PDF manual generation.")
            if digest(archive) != manifest["sha256"] or digest(incoming) != manifest["sha256"]:
                raise ValueError("Candidate archive changed during checking.")
            report.update({"candidate": manifest, "pdf_manual_checked": True,
                           "exact_archive_checked": True, "as_cran": True})
        if clean_commit(ROOT) != source_commit:
            raise ValueError("Source checkout changed during candidate preparation/checking.")
        report["success"] = True
    except (ValueError, OSError, RuntimeError, subprocess.SubprocessError, tarfile.TarError, IndexError) as error:
        report["error"] = str(error)
    for pattern in ("*.log", "*.Rout", "*.Rout.fail"):
        for path in work.glob("*.Rcheck/**/" + pattern):
            path.write_text(portable(path.read_text(errors="replace")))
    rendered = json.dumps(portable(report), indent=2) + "\n"
    (work / (args.mode + "_validation.json")).write_text(rendered)
    print(rendered, end="")
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
