#!/usr/bin/env python3
"""Bounded, checkpointed orchestration; statistical generation/analysis use base R."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tarfile
import time
from datetime import datetime, timezone

STUDY = Path(__file__).resolve().parent
REPO = STUDY.parents[1]
TOTAL_SECONDS = 450
FIT_SECONDS = 10
RESERVE_SECONDS = 15


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def utc():
    return datetime.now(timezone.utc).isoformat()


def table(path, rows):
    with Path(path).open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    lib, archive, out = (p.resolve() for p in (args.library, args.archive, args.output))
    if out.exists() and any(out.iterdir()):
        parser.error("Output must be empty; preserve earlier runs.")
    if not (lib / "Gtheory4LLM" / "DESCRIPTION").is_file() or not archive.is_file():
        parser.error("An installed development library and its source archive are required.")
    out.mkdir(parents=True, exist_ok=True)
    for name in ("worker", "details", "logs"):
        (out / name).mkdir()
    start = time.monotonic()
    deadline = start + TOTAL_SECONDS
    provenance = {
        "started_utc": utc(), "source_archive_name": archive.name,
        "source_archive_sha256": sha(archive),
        "installed_package": "Gtheory4LLM", "required_version": "0.3.0.9000",
        "source_identity": "Explicit development archive paired with supplied installed library; not the Git base alone",
        "git_base": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip(),
        "checkout_dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=REPO, text=True).strip()),
        "execution_budget_seconds": TOTAL_SECONDS, "per_subprocess_fit_seconds": FIT_SECONDS,
        "summary_reserve_seconds": RESERVE_SECONDS,
    }
    source = []
    with tarfile.open(archive, "r:gz") as bundle:
        for member in bundle.getmembers():
            relative = member.name.split("/", 1)[-1]
            if member.isfile() and (relative.startswith("R/") or relative in ("DESCRIPTION", "NAMESPACE")):
                payload = bundle.extractfile(member).read()
                source.append({"file": relative, "sha256": hashlib.sha256(payload).hexdigest()})
    table(out / "archive-source-files.csv", sorted(source, key=lambda x: x["file"]))
    files = [p for p in (lib / "Gtheory4LLM").rglob("*") if p.is_file()]
    table(out / "installed-files.csv", [{"file": str(p.relative_to(lib)), "sha256": sha(p)} for p in sorted(files)])
    frozen_files = [STUDY / name for name in ("PROTOCOL.md", "config.csv", "prepare.R", "fit-one.R", "summarize.R", "run.py")]
    table(out / "study-source-files.csv", [{"file": p.name, "sha256": sha(p)} for p in frozen_files])
    checkout_files = [REPO / "DESCRIPTION", REPO / "NAMESPACE"] + sorted((REPO / "R").glob("*.R"))
    table(out / "checkout-source-files.csv", [{"file": str(p.relative_to(REPO)), "sha256": sha(p)} for p in checkout_files])
    env = os.environ.copy()
    env.pop("GTHEORY_DISCRETE_SPECIMEN_DIR", None)
    with (out / "logs" / "prepare.log").open("w") as log:
        subprocess.run(["Rscript", "--vanilla", str(STUDY / "prepare.R"), str(out), str(lib), str(STUDY)],
                       cwd=REPO, env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=20)
    plan = list(csv.DictReader((out / "plan.csv").open()))
    provenance.update({"frozen_before_first_fit_utc": utc(), "plan_sha256": sha(out / "plan.csv"),
                       "protocol_sha256": sha(STUDY / "PROTOCOL.md"),
                       "panels": {p.name: sha(p) for p in sorted((out / "panels").glob("*.csv"))}})
    (out / "prefit-freeze.json").write_text(json.dumps(provenance, indent=2) + "\n")
    rows = []
    for item in plan:
        panel = list(csv.DictReader((out / "panels" / f'{int(item["attempt"]):02d}.csv').open()))
        levels = ["0", "1"] if item["family"] == "binary" else ["low", "middle", "high"]
        row = dict(item)
        row.update(status="budget_not_started", accepted="FALSE", optimizer_completed="FALSE",
                   variance_estimate="NA", reliability_estimate="NA", boundary="NA",
                   observations=len(panel), category_counts=";".join(f"{level}:{sum(p['y'] == level for p in panel)}" for level in levels),
                   engine="", approximation_adequacy="", acceptance_failures="", invalid_evaluations="NA",
                   fit_seconds="NA", process_seconds="NA", warnings="", error="")
        rows.append(row)
    table(out / "attempts.csv", rows)
    print(f"Frozen {len(rows)} planned panels before fitting; budget {TOTAL_SECONDS}s, each fit <= {FIT_SECONDS}s.", flush=True)
    for row in rows:
        remaining = deadline - time.monotonic() - RESERVE_SECONDS
        if remaining <= 0:
            break
        attempt = int(row["attempt"])
        begun = time.monotonic()
        try:
            with (out / "logs" / f"fit-{attempt:02d}.log").open("w") as log:
                completed = subprocess.run(["Rscript", "--vanilla", str(STUDY / "fit-one.R"), str(out), str(lib), str(attempt)],
                                           cwd=REPO, env=env, stdout=log, stderr=subprocess.STDOUT,
                                           timeout=min(FIT_SECONDS, remaining))
            result_path = out / "worker" / f"{attempt:02d}.csv"
            if completed.returncode == 0 and result_path.is_file():
                row.update(next(csv.DictReader(result_path.open())))
            else:
                row.update(status="error", error=f"Worker exited {completed.returncode}; see logs/fit-{attempt:02d}.log")
        except subprocess.TimeoutExpired:
            row.update(status="timeout", error="External per-fit or remaining campaign wall-clock budget exhausted")
        row["process_seconds"] = round(time.monotonic() - begun, 6)
        table(out / "attempts.csv", rows)
        print(f'{attempt:02d}/40 {row["scenario"]} replicate {row["replicate"]}: {row["status"]} ({row["process_seconds"]:.2f}s)', flush=True)
    provenance.update({"fits_finished_utc": utc(), "planned": len(rows),
                       "attempted": sum(r["status"] != "budget_not_started" for r in rows),
                       "accepted": sum(r["status"] == "accepted" for r in rows)})
    summary_remaining = max(0.1, deadline - time.monotonic())
    try:
        with (out / "logs" / "summary.log").open("w") as log:
            subprocess.run(["Rscript", "--vanilla", str(STUDY / "summarize.R"), str(out)],
                           cwd=REPO, env=env, stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=min(10, summary_remaining))
        required = ("RESULTS.md", "acceptance.csv", "recovery.csv", "pilot.png", "pilot.pdf")
        if any(not (out / name).is_file() or (out / name).stat().st_size == 0 for name in required):
            raise RuntimeError("Summary output missing; inspect summary.log for device warnings")
        provenance["summary_completed"] = True
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, RuntimeError) as error:
        provenance["summary_completed"] = False
        provenance["summary_error"] = str(error)
    provenance.update(finished_utc=utc(), total_execution_seconds=round(time.monotonic() - start, 6))
    (out / "execution.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(json.dumps({key: provenance[key] for key in ("planned", "attempted", "accepted", "summary_completed", "total_execution_seconds")}), flush=True)


if __name__ == "__main__":
    main()
