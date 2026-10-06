#!/usr/bin/env bash
# Two predeclared arms on one runner. A pass is diagnostic, never qualification.
set -euo pipefail
root="$GITHUB_WORKSPACE"
# Trust only this checkout for Git reads inside the root-owned container.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0="$root"
evidence="$root/frozen-nold-evidence"
archive="$root/artifacts/Gtheory4LLM_0.4.0.tar.gz"
library="$RUNNER_TEMP/frozen-lib"
unpacked="$RUNNER_TEMP/frozen-unpacked"
mkdir -p "$evidence" "$library" "$unpacked"
export R_LIBS_USER="$library"

apt-get update -qq
apt-get install -y -qq python3
verify_archive() {
  python3 - "$archive" "$root/artifacts/manifest.json" "$evidence/archive-identity.json" <<'PY'
import hashlib, json, sys
from pathlib import Path
archive, manifest, output = map(Path, sys.argv[1:])
m = json.loads(manifest.read_text())
identity = {"archive": archive.name, "bytes": archive.stat().st_size,
            "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "source_commit": m["source_commit"], "version": m["version"],
            "diagnostic_only": True, "release_qualification": False}
assert identity["bytes"] == 479899
assert identity["sha256"] == "a43a4cccbf2cd363625f36bad692e57aa0bde113be0492f642194c9c50362d65"
assert identity["source_commit"] == "e054422554499a7da54820a5072bb79b798da46c"
assert identity["version"] == "0.4.0" and m["release_state"] == "published"
assert m["files"][archive.name]["sha256"] == identity["sha256"]
output.write_text(json.dumps(identity, indent=2) + "\n")
print(json.dumps(identity))
PY
}
verify_archive
python3 scripts/check_committed_artifact.py --verify-only --check-release-identity --release-tag v0.4.0 > "$evidence/release-identity.json"
{
  grep -m1 'model name' /proc/cpuinfo
  grep -m1 '^flags' /proc/cpuinfo
  cat /etc/os-release
  R CMD config BLAS_LIBS
  R CMD config LAPACK_LIBS
} > "$evidence/platform-before.txt"

# Save runtime targets before installing reference development packages.
: > "$evidence/original-alternatives.tsv"
for group in libblas.so.3-x86_64-linux-gnu liblapack.so.3-x86_64-linux-gnu; do
  value=$(update-alternatives --query "$group" | sed -n 's/^Value: //p')
  test -n "$value"
  printf '%s\t%s\n' "$group" "$value" >> "$evidence/original-alternatives.tsv"
done
for group in libblas.so-x86_64-linux-gnu liblapack.so-x86_64-linux-gnu; do
  if update-alternatives --query "$group" > "$evidence/optional-alternative.txt" 2>/dev/null; then
    value=$(sed -n 's/^Value: //p' "$evidence/optional-alternative.txt")
    test -n "$value"
    printf '%s\t%s\n' "$group" "$value" >> "$evidence/original-alternatives.tsv"
  fi
done
Rscript --vanilla - "$evidence/original-runtime.txt" <<'RS'
args <- commandArgs(TRUE)
stopifnot(isFALSE(unname(capabilities("long.double"))),
          grepl("Under development", R.version.string, fixed=TRUE))
paths <- normalizePath(c(extSoftVersion()[["BLAS"]], La_library()), mustWork=TRUE)
stopifnot(all(grepl("openblas", paths, ignore.case=TRUE)))
writeLines(paths, args[1])
RS

apt-get install -y -qq cmake libnlopt-dev libcurl4-openssl-dev libssl-dev libxml2-dev libuv1-dev libblas3 liblapack3 libblas-dev liblapack-dev
while IFS=$'\t' read -r group value; do
  update-alternatives --set "$group" "$value"
done < "$evidence/original-alternatives.tsv"
ldconfig
dpkg-query -W libblas3 liblapack3 libblas-dev liblapack-dev > "$evidence/reference-package-versions.txt"

# Same dependency request as the release noLD job, compiled only once.
Rscript --vanilla - "$evidence/installed-packages.csv" <<'RS'
options(Ncpus=4L, repos=c(CRAN="https://cloud.r-project.org"))
wanted <- c("OpenMx", "Matrix", "lme4", "ordinal", "knitr", "rmarkdown")
need <- setdiff(wanted, rownames(installed.packages()))
if (length(need)) install.packages(need, type="source")
stopifnot(all(vapply(wanted, requireNamespace, logical(1), quietly=TRUE)))
ip <- installed.packages()[, c("Package", "Version")]
write.csv(ip[order(ip[, "Package"]), ], commandArgs(TRUE)[1], row.names=FALSE)
RS
R CMD INSTALL --no-docs --library="$library" "$archive"
tar -xzf "$archive" -C "$unpacked"

run_arm() {
  label="$1"
  arm="$evidence/$label"
  mkdir -p "$arm/specimens"
  export GTHEORY_DISCRETE_SPECIMEN_DIR="$arm/specimens"
  {
    for group in libblas.so.3-x86_64-linux-gnu liblapack.so.3-x86_64-linux-gnu libblas.so-x86_64-linux-gnu liblapack.so-x86_64-linux-gnu; do
      update-alternatives --query "$group"
    done
    ldd "$(R RHOME)/lib/libR.so"
  } > "$arm/linker.txt"
  Rscript --vanilla - "$label" "$arm" "$evidence/original-runtime.txt" <<'RS'
args <- commandArgs(TRUE)
label <- args[1]; out <- args[2]
library(Gtheory4LLM); library(Matrix); library(OpenMx)
invisible(crossprod(matrix(seq_len(16), 4)))
invisible(La.svd(matrix(seq_len(16), 4)))
paths <- normalizePath(c(extSoftVersion()[["BLAS"]], La_library()), mustWork=TRUE)
expected <- if (label == "openblas") readLines(args[3]) else
  normalizePath(c("/usr/lib/x86_64-linux-gnu/blas/libblas.so.3",
                  "/usr/lib/x86_64-linux-gnu/lapack/liblapack.so.3"), mustWork=TRUE)
maps <- readLines("/proc/self/maps")
writeLines(maps, file.path(out, "loaded-maps.txt"))
writeLines(capture.output(sessionInfo(), print(paths), print(La_version())),
           file.path(out, "runtime.txt"))
stopifnot(identical(unname(paths), unname(expected)),
          isFALSE(unname(capabilities("long.double"))))
if (label == "reference" && any(grepl("openblas", maps, ignore.case=TRUE)))
  stop("Reference arm still maps OpenBLAS; no backend comparison is established.")
dlls <- vapply(getLoadedDLLs(), function(d) d[["path"]], character(1))
dlls <- dlls[file.exists(dlls)]
write.csv(data.frame(path=dlls, md5=unname(tools::md5sum(dlls))),
          file.path(out, "loaded-dll-hashes.csv"), row.names=FALSE)
for (dll in dlls) {
  cat(dll, "\n")
  system2("ldd", shQuote(dll))
}
RS
  status=0
  Rscript --vanilla "$unpacked/Gtheory4LLM/tests/package-characterization.R" > "$arm/original-characterization.Rout" 2>&1 || status=$?
  printf '%s\n' "$status" > "$arm/original-characterization.exit"
  status=0
  Rscript --vanilla .github/nold/characterization_diagnose.R --archive "$archive" --library "$library" --output-dir "$arm/harness" --backend-label "$label" > "$arm/harness.log" 2>&1 || status=$?
  printf '%s\n' "$status" > "$arm/harness.exit"
}

# Run once in each arm, in a fixed order, even if the first original test fails.
run_arm openblas
update-alternatives --set libblas.so.3-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/blas/libblas.so.3
update-alternatives --set liblapack.so.3-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/lapack/liblapack.so.3
update-alternatives --set libblas.so-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/blas/libblas.so
update-alternatives --set liblapack.so-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/lapack/liblapack.so
ldconfig
run_arm reference
verify_archive
python3 - "$evidence" <<'PY'
from pathlib import Path
import csv, json, sys
root = Path(sys.argv[1])
arms = {}
dlls = {}
for backend in ("openblas", "reference"):
    with (root/backend/"loaded-dll-hashes.csv").open() as stream:
        dlls[backend] = {row["path"]: row["md5"] for row in csv.DictReader(stream)}
    arms[backend] = {name: int((root/backend/(name+".exit")).read_text())
                     for name in ("original-characterization", "harness")}
report = {"diagnostic_only": True, "release_qualification": False,
          "predetermined_arms": ["openblas", "reference"], "exit_statuses": arms,
          "original_failure_remains_unresolved": True,
          "same_R_and_package_binaries": dlls["openblas"] == dlls["reference"]}
(root/"paired-summary.json").write_text(json.dumps(report, indent=2)+"\n")
print(json.dumps(report, indent=2))
sys.exit(0 if report["same_R_and_package_binaries"] and
         all(code == 0 for arm in arms.values() for code in arm.values()) else 1)
PY
