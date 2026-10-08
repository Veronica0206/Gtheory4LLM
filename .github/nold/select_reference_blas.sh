#!/usr/bin/env bash
# Configure an ephemeral Debian/Ubuntu noLD runner; never change package code.
set -euo pipefail
if [ "$#" -ne 1 ]; then
  echo 'Usage: select_reference_blas.sh EVIDENCE_DIRECTORY' >&2
  exit 2
fi
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
evidence="$1"
mkdir -p "$evidence"
evidence="$(cd -- "$evidence" && pwd)"
if [ -e "$evidence/selection-complete.txt" ]; then
  echo 'Refusing to replace an existing reference-backend setup record.' >&2
  exit 1
fi
unset OPENBLAS_CORETYPE
Rscript --vanilla - <<'RS'
stopifnot(Sys.info()[["sysname"]] == "Linux",
          Sys.info()[["machine"]] %in% c("x86_64", "amd64"),
          isFALSE(unname(capabilities("long.double"))),
          .Machine$sizeof.longdouble == 0)
RS
{
  date -u +%Y-%m-%dT%H:%M:%SZ
  cat /etc/os-release
  cat /proc/cpuinfo
  for group in libblas.so.3-x86_64-linux-gnu liblapack.so.3-x86_64-linux-gnu libblas.so-x86_64-linux-gnu liblapack.so-x86_64-linux-gnu; do
    update-alternatives --query "$group" || true
  done
} > "$evidence/platform-and-original-alternatives.txt" 2>&1

# Select both runtime and linker libraries before compiling any R dependency.
apt-get update -qq
apt-get install -y -qq --no-install-recommends libblas3 liblapack3 libblas-dev liblapack-dev
update-alternatives --set libblas.so.3-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/blas/libblas.so.3
update-alternatives --set liblapack.so.3-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/lapack/liblapack.so.3
update-alternatives --set libblas.so-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/blas/libblas.so
update-alternatives --set liblapack.so-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/lapack/liblapack.so
ldconfig
{
  dpkg-query -W libblas3 liblapack3 libblas-dev liblapack-dev
  for group in libblas.so.3-x86_64-linux-gnu liblapack.so.3-x86_64-linux-gnu libblas.so-x86_64-linux-gnu liblapack.so-x86_64-linux-gnu; do
    update-alternatives --query "$group"
  done
  sha256sum /usr/lib/x86_64-linux-gnu/blas/libblas.so.3 /usr/lib/x86_64-linux-gnu/lapack/liblapack.so.3
  ldd "$(R RHOME)/lib/libR.so"
} > "$evidence/reference-libraries.txt" 2>&1

# Probe actual loaded libraries and the two captured failing systems in a fresh
# R process. A selected alternative alone is insufficient evidence.
unset GTHEORY_REFERENCE_BASELINE
Rscript --vanilla "$root/.github/nold/check_reference_blas.R" reference "$evidence/probe"
test -f "$evidence/probe/runtime.rds"
if [ -n "${GITHUB_ENV:-}" ]; then
  printf 'GTHEORY_REFERENCE_BASELINE=%s\n' "$evidence/probe/runtime.rds" >> "$GITHUB_ENV"
fi
printf 'Verified reference BLAS/LAPACK with unchanged captured-solve bound.\n' > "$evidence/selection-complete.txt"
