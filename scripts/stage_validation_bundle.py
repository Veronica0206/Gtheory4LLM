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


def retained_manifest_applies(root: Path) -> bool:
    """Whether the retained manifest is the one to validate against.

    A development version keeps the preceding release, and a release version the
    retained manifest already records needs nothing built. Invalid matching or
    development metadata is not repaired by rebuilding it; the guards below
    report it instead.
    """
    source = read_dcf((root / "DESCRIPTION").read_bytes())
    manifest = json.loads((root / "artifacts/manifest.json").read_text(encoding="utf-8"))
    return (source["Version"] == manifest.get("version") or
            DEVELOPMENT_VERSION.fullmatch(source["Version"]) is not None)


def select_manifest(root: Path, destination: Path | None, *, rscript: str = "Rscript",
                    environment: dict | None = None, timeout: float | None = None) -> Path:
    """The manifest to validate against: the retained one, or a staged rehearsal.

    The destination is used only when a bundle has to be built; it is then
    required to be empty and outside the checkout. A retained manifest is
    selected without touching it, so a temporary base inside the checkout does
    not block a run that builds nothing. Building runs release preparation with
    the interpreter, environment and timeout of the validation run that asked.
    """
    root = root.resolve()
    if retained_manifest_applies(root):
        selected = root / "artifacts/manifest.json"
    else:
        if destination is None:
            raise ValueError("Staging a rehearsal bundle needs a destination outside the source checkout.")
        destination = destination.resolve()
        if destination == root or root in destination.parents:
            raise ValueError("Validation bundle must be outside the source checkout.")
        if destination.exists() and any(destination.iterdir()):
            raise ValueError("Staging directory must be empty; stale evidence is not reused.")
        subprocess.run([sys.executable, str(root / "scripts/prepare_release.py"), "--rscript", rscript,
                        "--skip-validation", "--dry-run", str(destination)],
                       cwd=root, check=True, env=environment, timeout=timeout)
        selected = destination / "manifest.json"
    verify_bundle(root, selected)
    verify_release_identity(root, selected)
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--rscript", default="Rscript",
                        help="Interpreter release preparation builds a rehearsal bundle with.")
    parser.add_argument("--timeout", type=float, help="Maximum seconds for building a rehearsal bundle.")
    parser.add_argument("--github-env", type=Path,
                        help="Append the verified manifest path for subsequent CI steps.")
    args = parser.parse_args()
    selected = select_manifest(ROOT, args.output_dir, rscript=args.rscript, timeout=args.timeout)
    if args.github_env:
        with args.github_env.open("a", encoding="utf-8") as stream:
            stream.write("GTHEORY_VALIDATION_MANIFEST=" + str(selected) + "\n")
    print(json.dumps({"validation_manifest": str(selected),
                      "published_artifacts_replaced": False,
                      "exact_candidate_qualification": False}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
