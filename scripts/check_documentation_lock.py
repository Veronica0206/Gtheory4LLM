"""Ensure the documentation environment preserves every numerical dependency."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC_LOCK = ROOT / "scripts" / "dependency-locks" / "documentation.lock"


def validate_locks(numerical: dict, documentation: dict) -> None:
    if numerical["R"] != documentation["R"]:
        raise ValueError("Documentation lock must use the numerical lock's R and repositories")
    packages = documentation["Packages"]
    if not {"knitr", "rmarkdown"}.issubset(packages):
        raise ValueError("Documentation lock must include knitr and rmarkdown")
    for name, record in numerical["Packages"].items():
        if packages.get(name) != record:
            raise ValueError(f"Documentation lock changes or omits numerical dependency: {name}")
    for name, record in packages.items():
        if (record.get("Package") != name or not record.get("Version") or
                record.get("Source") != "Repository" or record.get("Repository") != "CRAN"):
            raise ValueError(f"Invalid pinned CRAN dependency: {name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--numerical", type=Path, default=ROOT / "renv.lock")
    parser.add_argument("--documentation", type=Path, default=DOC_LOCK)
    args = parser.parse_args()
    numerical = json.loads(args.numerical.read_text())
    documentation = json.loads(args.documentation.read_text())
    validate_locks(numerical, documentation)
    print(f"Documentation lock preserves {len(numerical['Packages'])} numerical packages; "
          f"{len(documentation['Packages'])} total pinned R packages")


if __name__ == "__main__":
    main()
