"""Verify the same candidate contract used by the ordinary R-devel job."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from cran_readiness import candidate_input
from check_committed_artifact import read_archive, read_dcf


def verify_candidate(directory: Path, expected_commit: str) -> tuple[dict, Path]:
    """Check bytes and source identity, then inspect package metadata safely."""
    manifest, archive = candidate_input(directory.resolve(), expected_commit)
    files = read_archive(archive, manifest["package"])
    if "DESCRIPTION" not in files:
        raise ValueError("Candidate archive is missing DESCRIPTION.")
    description = read_dcf(files["DESCRIPTION"])
    if (description.get("Package") != manifest["package"] or
            description.get("Version") != manifest["version"]):
        raise ValueError("Candidate archive package/version differs from its build manifest.")
    return manifest, archive


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate_directory", type=Path)
    arguments = parser.parse_args(argv)
    # The checkout is a runner-owned bind mount in a root-owned container.
    # Trust only this action checkout for this read, without changing Git config.
    commit = subprocess.check_output(["git", "-c", "safe.directory=" + str(ROOT),
                                      "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    # No evidence files or environment exports exist until every check passes.
    manifest, archive = verify_candidate(arguments.candidate_directory, commit)
    evidence = ROOT / "nold-evidence"
    evidence.mkdir(exist_ok=True)
    (evidence / "candidate.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (evidence / "archive-identity.json").write_text(json.dumps({
        "verified": True, "source_commit": commit, "sha256": manifest["sha256"],
        "bytes": manifest["bytes"], "archive": archive.name,
        "package": manifest["package"], "version": manifest["version"],
        "workflow_run": os.environ["GITHUB_RUN_ID"],
    }, indent=2) + "\n")
    with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as stream:
        stream.write("ARCHIVE=" + str(archive) + "\n")
        stream.write("GTHEORY_DISCRETE_SPECIMEN_DIR=" + str(evidence / "specimens") + "\n")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
