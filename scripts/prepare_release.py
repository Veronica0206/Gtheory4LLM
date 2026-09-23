"""Prepare a release bundle from a clean checkout, and stop before publishing.

Every version in the bundle comes from DESCRIPTION: the archive name, the
manifest, the artifact README heading, and the tag this prints at the end. No
step writes a version anywhere it was typed by hand.

This script deliberately does not tag, push, create a GitHub release, or submit
to CRAN. It prepares and verifies; a person publishes. That separation is the
point: an automated publish would remove the only step where someone reads what
is about to become permanent. What it prints at the end is the exact tag and
asset names to use, and the checklist step to follow.

Usage:
    python3 scripts/prepare_release.py                 # prepare and verify
    python3 scripts/prepare_release.py --from-checked-candidate DIR
                                                       # adopt the archive CI checked
    python3 scripts/prepare_release.py --skip-validation   # re-bundle only
    python3 scripts/prepare_release.py --allow-dirty       # rehearsal only
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "artifacts"
RELEASE_STATES = ("prepared", "published")
CHECK_SPEC = importlib.util.spec_from_file_location(
    "release_checks", Path(__file__).with_name("check_committed_artifact.py"))
CHECKS = importlib.util.module_from_spec(CHECK_SPEC)
CHECK_SPEC.loader.exec_module(CHECKS)


def description_field(field: str) -> str:
    text = (ROOT / "DESCRIPTION").read_text(encoding="utf-8")
    match = re.search(rf"(?m)^{re.escape(field)}:[ \t]*(.*(?:\n[ \t]+.*)*)$", text)
    if match is None:
        raise SystemExit(f"DESCRIPTION has no {field} field")
    return " ".join(match.group(1).split())


def run(step: str, command: list[str], *, cwd: Path = ROOT) -> None:
    print(f"\n=== {step} ===", flush=True)
    print("  " + " ".join(command), flush=True)
    result = subprocess.run(command, cwd=cwd)
    if result.returncode:
        raise SystemExit(f"{step} failed (exit {result.returncode}); nothing was published")


def git(*arguments: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *arguments], text=True).strip()


def digest(path: Path) -> str:
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def require_clean_tree(allow_dirty: bool) -> str:
    dirty = git("status", "--porcelain")
    if dirty and not allow_dirty:
        raise SystemExit(
            "The working tree has uncommitted changes, so the archive could not be\n"
            "tied to a commit anyone else can check out:\n" + dirty +
            "\nCommit them, or pass --allow-dirty for a rehearsal whose bundle must not be published.")
    if dirty:
        print("WARNING: rehearsal on a dirty tree. The recorded source commit does not\n"
              "describe these files, so this bundle must not be published.", flush=True)
    return git("rev-parse", "HEAD")


def build_archive(package: str, version: str, work: Path) -> Path:
    r = Path(subprocess.check_output(
        ["Rscript", "--vanilla", "-e",
         'cat(file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R"))'],
        text=True).strip())
    run("Build the source archive", [str(r), "CMD", "build", str(ROOT)], cwd=work)
    archive = work / f"{package}_{version}.tar.gz"
    if not archive.is_file():
        raise SystemExit(f"R CMD build did not produce {archive.name}; check the version in DESCRIPTION")
    return archive


def adopt_checked_candidate(directory: Path, package: str, version: str, commit: str,
                            work: Path) -> tuple[Path, dict]:
    """Take the archive the candidate workflow checked, unchanged, instead of building one.

    A rebuilt archive has its own identity: the same sources packaged again
    differ in build metadata, and the R-devel check evidence belongs to the
    bytes that were checked. This reads a downloaded cran-candidate-checked
    directory, requires its manifest to name this package, this version and
    the checked-out commit, requires the archive bytes to match that manifest,
    and copies the file as is. Nothing here rebuilds, repackages or edits it.
    """
    manifest_path = directory / "candidate.json"
    if not manifest_path.is_file():
        raise SystemExit(f"{directory} has no candidate.json; download the cran-candidate-checked-<commit> artifact")
    candidate = json.loads(manifest_path.read_text(encoding="utf-8"))
    if candidate.get("schema_version") != 1:
        raise SystemExit("Unsupported candidate manifest schema.")
    if candidate.get("package") != package or candidate.get("version") != version:
        raise SystemExit("The checked candidate is not this package version; DESCRIPTION says "
                         f"{package} {version}.")
    if candidate.get("source_commit") != commit:
        raise SystemExit("The checked candidate was built from a different source commit than the one "
                         "checked out; prepare from the commit the workflow checked.")
    expected_name = f"{package}_{version}.tar.gz"
    if candidate.get("archive") != expected_name:
        raise SystemExit("The checked candidate must be the package archive " + expected_name)
    archive = directory / expected_name
    if archive.is_symlink() or not archive.is_file():
        raise SystemExit("The checked candidate archive must be a regular file next to candidate.json")
    if archive.stat().st_size != candidate.get("bytes") or digest(archive) != candidate.get("sha256"):
        raise SystemExit("The checked candidate archive does not match its own manifest's size or SHA-256.")
    # A build artifact alone is not a checked candidate. The downstream job
    # writes check_validation.json only after R CMD check ran; require it to
    # record a successful R-devel check of exactly these bytes.
    report_path = directory / "check_validation.json"
    if not report_path.is_file():
        raise SystemExit(f"{directory} has no check_validation.json; adopt only the cran-candidate-checked-<commit> "
                         "artifact, which carries the check report.")
    report = json.loads(report_path.read_text(encoding="utf-8"))
    check = report.get("r_cmd_check") if isinstance(report.get("r_cmd_check"), dict) else {}
    checked = report.get("candidate") if isinstance(report.get("candidate"), dict) else {}
    if not (report.get("success") is True and report.get("r_devel_checked") is True
            and report.get("exact_archive_checked") is True and report.get("pdf_manual_checked") is True
            and check.get("errors") == 0 and check.get("warnings") == 0):
        raise SystemExit("The candidate's check report does not record a successful R-devel check of the exact "
                         "archive with zero errors and warnings; nothing is adopted.")
    if checked.get("sha256") != candidate.get("sha256"):
        raise SystemExit("The candidate's check report describes a different archive than candidate.json; "
                         "nothing is adopted.")
    adopted = work / expected_name
    shutil.copy2(archive, adopted)
    # Nothing machine-specific goes into the committed manifest: the archive's
    # own size and digest already identify the candidate.
    provenance = {"origin": "checked_candidate",
                  "build_r_version": candidate.get("build_r_version"),
                  "checked_r_version": report.get("r_version"),
                  "expected_data_kind": candidate.get("expected_data_kind")}
    print(f"\n=== Adopt the checked candidate archive unchanged ===\n  {archive}\n"
          f"  sha256 {candidate.get('sha256')} ({candidate.get('bytes')} bytes)", flush=True)
    return adopted, provenance


def build_manual(package: str, work: Path) -> Path:
    manual = work / f"{package}-manual.pdf"
    run("Build the reference manual",
        ["Rscript", "--vanilla", str(ROOT / "scripts/build_manual.R"), str(manual), str(work / "manual")])
    if not manual.is_file():
        raise SystemExit("The manual build reported success but produced no PDF")
    return manual


def manifest_for(package: str, version: str, commit: str, state: str,
                 archive: Path, manual: Path) -> dict:
    return {
        "package": package, "version": version, "release_state": state,
        "source_commit": commit,
        "files": {path.name: {"bytes": path.stat().st_size, "sha256": digest(path)}
                  for path in (archive, manual)},
    }


def write_artifact_readme(package: str, version: str, state: str, destination: Path) -> None:
    """Publication status lives only in excluded repository metadata."""
    (destination / "README.md").write_text(
        f"# {package} {version} release\n\nRelease state: **{state}**.\n\n"
        "The [manifest](manifest.json) records the source commit, file sizes and SHA-256 hashes.\n"
        "Publish exactly those files; never rebuild an already published version.\n",
        encoding="utf-8")


def require_neutral_source_prose(version: str) -> None:
    """Validate committed source prose before building; never rewrite an archive."""
    try:
        CHECKS.verify_published_prose(ROOT, version, neutral_source=True)
    except ValueError as error:
        raise SystemExit(str(error)) from error
    for name in ("README.md", "NEWS.md"):
        text = (ROOT / name).read_text(encoding="utf-8")
        blocks = re.findall(r"<!-- release-identity:start -->(.*?)<!-- release-identity:end -->",
                            text, re.S)
        if (len(blocks) != 1 or
                re.findall(r"Source version: \*\*([^*]+)\*\*\.", blocks[0]) != [version] or
                re.search(r"(?:Release state|Current artifact bundle|Checkout version):", blocks[0]) or
                "artifacts/manifest.json" not in blocks[0] or "/releases" not in blocks[0]):
            raise SystemExit(f"{name}: commit a publication-neutral Source version summary matching "
                             "DESCRIPTION and linking repository release metadata before preparing.")


def refuse_published_version(version: str, state: str, destination: Path) -> None:
    """Refuse before any build, even for --allow-dirty and scratch rehearsals."""
    if state == "published":
        raise SystemExit("Preparation cannot use --state published; publish an unchanged prepared bundle.")
    tag_exists = subprocess.run(["git", "-C", str(ROOT), "show-ref", "--verify", "--quiet",
                                 f"refs/tags/v{version}"], check=False).returncode == 0
    published = False
    for path in {ARTIFACTS / "manifest.json", destination / "manifest.json"}:
        if path.exists():
            manifest = json.loads(path.read_text(encoding="utf-8"))
            published |= manifest.get("version") == version and manifest.get("release_state") == "published"
    if tag_exists or published:
        raise SystemExit(f"Version {version} is already tagged or published; prepare a new version "
                         "instead of rebuilding or replacing its files.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--skip-validation", action="store_true",
                        help="Rebuild the bundle without rerunning the source validation scope.")
    parser.add_argument("--allow-dirty", action="store_true",
                        help="Rehearse on an uncommitted tree. The result must not be published.")
    parser.add_argument("--state", choices=RELEASE_STATES, default="prepared",
                        help="Preparation only supports prepared; published is rejected to protect existing releases.")
    parser.add_argument("--from-checked-candidate", type=Path, metavar="DIR",
                        help="Adopt the archive the candidate workflow checked, unchanged, from a downloaded "
                             "cran-candidate-checked-<commit> directory built from this commit. "
                             "The manual is still built here.")
    parser.add_argument("--dry-run", type=Path, metavar="DIR",
                        help="Build the bundle into DIR and change no tracked file. "
                             "The staged manifest and archive are verified before copying.")
    options = parser.parse_args(argv)

    package = description_field("Package")
    version = description_field("Version")
    development = bool(re.fullmatch(r".*\.9[0-9]{3,}", version))
    if development:
        raise SystemExit(
            f"DESCRIPTION declares the development version {version}. A development checkout\n"
            "keeps the preceding release rather than bundling itself; set a release version first.")
    print(f"Preparing {package} {version} (release state: {options.state})")

    destination = options.dry_run.resolve() if options.dry_run else ARTIFACTS
    if options.dry_run and (destination == ROOT.resolve() or ROOT.resolve() in destination.parents):
        raise SystemExit("--dry-run DIR must be outside the checkout to avoid changing tracked files.")
    refuse_published_version(version, options.state, destination)
    require_neutral_source_prose(version)
    commit = require_clean_tree(options.allow_dirty)
    with tempfile.TemporaryDirectory(prefix="gtheory-release-") as directory:
        work = Path(directory)
        provenance = {"origin": "built_here"}
        if options.from_checked_candidate:
            archive, provenance = adopt_checked_candidate(
                options.from_checked_candidate.resolve(), package, version, commit, work)
        else:
            archive = build_archive(package, version, work)
        manual = build_manual(package, work)
        staging = work / "bundle"
        staging.mkdir()
        shutil.copy2(archive, staging / archive.name)
        shutil.copy2(manual, staging / manual.name)
        manifest = manifest_for(package, version, commit, options.state,
                                staging / archive.name, staging / manual.name)
        manifest["archive_provenance"] = provenance
        manifest_path = staging / "manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        write_artifact_readme(package, version, options.state, staging)
        run("Verify the bundle against its source commit and the release identity",
            [sys.executable, str(ROOT / "scripts/check_committed_artifact.py"),
             "--manifest", str(manifest_path), "--verify-only", "--check-release-identity"])
        if not options.skip_validation:
            run("Validate public sources",
                [sys.executable, str(ROOT / "scripts/run_validation.py"), "--scope", "source",
                 "--as-cran", "--release-manifest", str(manifest_path)])
        run("Audit public content",
            [sys.executable, str(ROOT / "scripts/check_public_contents.py"),
             "--working-tree", "--expected-data-kind", "public_llm_annotations"])
        destination.mkdir(parents=True, exist_ok=True)
        if not options.dry_run:
            for stale in destination.glob(f"{package}_*.tar.gz"):
                if stale.name != archive.name:
                    print(f"Removing superseded archive {stale.name}", flush=True)
                    stale.unlink()
        for path in staging.iterdir():
            shutil.copy2(path, destination / path.name)

    if options.dry_run:
        print(f"\nDry run: verified bundle written to {destination}. No tracked file was changed.")

    report = {
        "prepared_utc": datetime.now(timezone.utc).isoformat(),
        "package": package, "version": version, "release_state": options.state,
        "source_commit": commit, "tag": f"v{version}",
        "assets": sorted(manifest["files"]),
        "validation_run": not options.skip_validation,
        "archive_origin": provenance["origin"],
        "rehearsal_on_dirty_tree": bool(options.allow_dirty and git("status", "--porcelain")),
        "dry_run": bool(options.dry_run),
        "bundle_directory": str(destination),
        "published": False,
    }
    print("\n" + json.dumps(report, indent=2))
    print(f"""
Prepared, not published. Nothing has been tagged, pushed, or uploaded.

To publish, follow docs/RELEASE_CHECKLIST.md. In outline:
  1. Commit artifacts/; README.md and NEWS.md stay identical to the source commit.
  2. Set release_state to "published" in artifacts/manifest.json and update
     artifacts/README.md, then commit only that excluded repository metadata.
  3. Tag that commit:            git tag v{version}
  4. Verify the tag:             python3 scripts/check_committed_artifact.py \\
                                   --verify-only --check-release-identity --release-tag v{version}
  5. Upload exactly these assets, unchanged:
       {"  ".join(sorted(manifest["files"]) + ["manifest.json"])}
     Compare the hosting service's sizes and SHA-256 values with the manifest.

A passing check is not CRAN acceptance, and a prepared bundle is not a release.
""")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
