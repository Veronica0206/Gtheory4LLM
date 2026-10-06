"""Select a valid release manifest for CI without replacing published artifacts.

Development checkouts use the retained release. An unbundled release version
gets a freshly built, verified rehearsal bundle outside the checkout. That is
validation evidence, not the exact candidate qualified by cran-readiness.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from check_committed_artifact import DEVELOPMENT_VERSION, read_dcf, verify_bundle, verify_release_identity

ROOT = Path(__file__).resolve().parents[1]


def select_manifest(root: Path, destination: Path) -> Path:
    root, destination = root.resolve(), destination.resolve()
    if destination == root or root in destination.parents:
        raise ValueError("Validation bundle must be outside the source checkout.")
    retained = root / "artifacts/manifest.json"
    source = read_dcf((root / "DESCRIPTION").read_bytes())
    manifest = json.loads(retained.read_text(encoding="utf-8"))
    # Do not repair invalid matching/development metadata by rebuilding it.
    if (source["Version"] == manifest.get("version") or
            DEVELOPMENT_VERSION.fullmatch(source["Version"])):
        selected = retained
    else:
        if destination.exists() and any(destination.iterdir()):
            raise ValueError("Staging directory must be empty; stale evidence is not reused.")
        subprocess.run([sys.executable, str(root / "scripts/prepare_release.py"),
                        "--skip-validation", "--dry-run", str(destination)],
                       cwd=root, check=True)
        selected = destination / "manifest.json"
    verify_bundle(root, selected)
    verify_release_identity(root, selected)
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--github-env", type=Path,
                        help="Append the verified manifest path for subsequent CI steps.")
    args = parser.parse_args()
    selected = select_manifest(ROOT, args.output_dir)
    if args.github_env:
        with args.github_env.open("a", encoding="utf-8") as stream:
            stream.write("GTHEORY_VALIDATION_MANIFEST=" + str(selected) + "\n")
    print(json.dumps({"validation_manifest": str(selected),
                      "published_artifacts_replaced": False,
                      "exact_candidate_qualification": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
