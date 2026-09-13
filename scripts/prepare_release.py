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
    python3 scripts/prepare_release.py --skip-validation   # re-bundle only
    python3 scripts/prepare_release.py --allow-dirty       # rehearsal only
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
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


def update_artifact_readme(package: str, version: str, state: str) -> None:
    """Keep only the machine-checked heading and state line in step."""
    path = ARTIFACTS / "README.md"
    heading = f"# {package} {version} release"
    if not path.is_file():
        raise SystemExit(f"{path} is missing; the release identity check requires it")
    lines = path.read_text(encoding="utf-8").splitlines()
    lines[0] = heading
    text = "\n".join(lines) + "\n"
    text = re.sub(r"Release state: \*\*(?:prepared|published)\*\*",
                  f"Release state: **{state}**", text)
    path.write_text(text, encoding="utf-8")


def update_release_blocks(version: str, source_version: str, state: str) -> None:
    """Rewrite the marked release-identity summaries from DESCRIPTION."""
    for name in ("README.md", "NEWS.md"):
        path = ROOT / name
        text = path.read_text(encoding="utf-8")
        block = re.search(r"<!-- release-identity:start -->(.*?)<!-- release-identity:end -->",
                          text, re.S)
        if block is None:
            raise SystemExit(f"{name} has no release-identity block to update")
        body = block.group(1)
        body = re.sub(r"Current artifact bundle: \*\*[^*]+\*\*\.",
                      f"Current artifact bundle: **{version}**.", body)
        body = re.sub(r"Release state: \*\*(?:prepared|published)\*\*\.",
                      f"Release state: **{state}**.", body)
        if name == "README.md":
            body = re.sub(r"Checkout version: \*\*[^*]+\*\*\.",
                          f"Checkout version: **{source_version}**.", body)
        path.write_text(text[:block.start(1)] + body + text[block.end(1):], encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--skip-validation", action="store_true",
                        help="Rebuild the bundle without rerunning the source validation scope.")
    parser.add_argument("--allow-dirty", action="store_true",
                        help="Rehearse on an uncommitted tree. The result must not be published.")
    parser.add_argument("--state", choices=RELEASE_STATES, default="prepared",
                        help="Declared release state. Use published only after the tag exists.")
    parser.add_argument("--dry-run", type=Path, metavar="DIR",
                        help="Build the bundle into DIR and change no tracked file. "
                             "Bundle verification needs the files in artifacts/, so a dry "
                             "run reports the manifest it would write without checking "
                             "release identity.")
    options = parser.parse_args(argv)

    package = description_field("Package")
    version = description_field("Version")
    development = bool(re.fullmatch(r".*\.9[0-9]{3,}", version))
    if development:
        raise SystemExit(
            f"DESCRIPTION declares the development version {version}. A development checkout\n"
            "keeps the preceding release rather than bundling itself; set a release version first.")
    print(f"Preparing {package} {version} (release state: {options.state})")

    commit = require_clean_tree(options.allow_dirty)
    if not options.skip_validation:
        run("Validate public sources",
            [sys.executable, str(ROOT / "scripts/run_validation.py"), "--scope", "source", "--as-cran"])

    destination = options.dry_run.resolve() if options.dry_run else ARTIFACTS
    with tempfile.TemporaryDirectory(prefix="gtheory-release-") as directory:
        work = Path(directory)
        archive = build_archive(package, version, work)
        manual = build_manual(package, work)
        destination.mkdir(parents=True, exist_ok=True)
        if not options.dry_run:
            for stale in destination.glob(f"{package}_*.tar.gz"):
                if stale.name != archive.name:
                    print(f"Removing superseded archive {stale.name}", flush=True)
                    stale.unlink()
        shutil.copy2(archive, destination / archive.name)
        shutil.copy2(manual, destination / manual.name)
        manifest = manifest_for(package, version, commit, options.state,
                                destination / archive.name, destination / manual.name)
        (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n",
                                                   encoding="utf-8")

    if options.dry_run:
        print(f"\nDry run: bundle written to {destination}. No tracked file was changed,\n"
              "and release identity was not checked because that reads artifacts/.")
    else:
        update_artifact_readme(package, version, options.state)
        update_release_blocks(version, version, options.state)
        run("Verify the bundle against its source commit and the release identity",
            [sys.executable, str(ROOT / "scripts/check_committed_artifact.py"),
             "--verify-only", "--check-release-identity"])
        run("Audit public content",
            [sys.executable, str(ROOT / "scripts/check_public_contents.py"),
             "--working-tree", "--expected-data-kind", "public_llm_annotations"])

    report = {
        "prepared_utc": datetime.now(timezone.utc).isoformat(),
        "package": package, "version": version, "release_state": options.state,
        "source_commit": commit, "tag": f"v{version}",
        "assets": sorted(manifest["files"]),
        "validation_run": not options.skip_validation,
        "rehearsal_on_dirty_tree": bool(options.allow_dirty and git("status", "--porcelain")),
        "dry_run": bool(options.dry_run),
        "bundle_directory": str(destination),
        "published": False,
    }
    print("\n" + json.dumps(report, indent=2))
    print(f"""
Prepared, not published. Nothing has been tagged, pushed, or uploaded.

To publish, follow docs/RELEASE_CHECKLIST.md. In outline:
  1. Commit artifacts/ together with the updated release blocks.
  2. Set release_state to "published" in artifacts/manifest.json and in the
     marked README.md and NEWS.md blocks, and commit that.
  3. Tag that commit:            git tag v{version}
  4. Verify the tag:             python3 scripts/check_committed_artifact.py \\
                                   --verify-only --check-release-identity --release-tag v{version}
  5. Upload exactly these assets, unchanged:
       {"  ".join(sorted(manifest["files"]))}
     Compare the hosting service's sizes and SHA-256 values with the manifest.

A passing check is not CRAN acceptance, and a prepared bundle is not a release.
""")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
