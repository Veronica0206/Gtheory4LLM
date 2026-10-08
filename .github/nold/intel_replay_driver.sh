#!/usr/bin/env bash
# Diagnostic execution success is not a numerical pass or release qualification.
set -euo pipefail
root="$GITHUB_WORKSPACE"
evidence="$root/intel-replay-evidence"
mkdir -p "$evidence/specimens" "$evidence/build"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0="$root"
unset OPENBLAS_CORETYPE
{
  date -u +%Y-%m-%dT%H:%M:%SZ
  git rev-parse HEAD
  cat /etc/os-release
  cat /proc/cpuinfo
  uname -a
  R --version
  for var in CC CFLAGS FC FFLAGS BLAS_LIBS LAPACK_LIBS; do
    printf '%s = %s\n' "$var" "$(R CMD config "$var")"
  done
  env | sort | sed -n '/^GITHUB_RUN_/p; /^GTHEORY_/p; /^OMP_/p; /^OPENBLAS_/p'
} > "$evidence/platform.txt"

# These identities are checked before and after every arm. No package is built.
sha256sum artifacts/Gtheory4LLM_0.4.1.tar.gz artifacts/Gtheory4LLM-manual.pdf artifacts/manifest.json > "$evidence/release-before.sha256"
printf '%s  %s\n' 8261b2d8084a54fa69a4bb3b7ae0caac3eefcc75ba83969d09422d525460e554 artifacts/Gtheory4LLM_0.4.1.tar.gz | sha256sum -c -
Rscript --vanilla - "$evidence" <<'RS'
out <- commandArgs(TRUE)[1]
stopifnot(isFALSE(unname(capabilities("long.double"))),
          identical(.Machine$sizeof.longdouble, 0L),
          grepl("Under development", R.version.string, fixed=TRUE))
paths <- normalizePath(c(extSoftVersion()[["BLAS"]], La_library()), mustWork=TRUE)
stopifnot(all(grepl("openblas", paths, ignore.case=TRUE)))
writeLines(paths, file.path(out, "original-runtime.txt"))
writeLines(unlist(lapply(unique(paths), function(p) system2("sha256sum", shQuote(p), stdout=TRUE))), file.path(out, "original-native.sha256"))
RS
: > "$evidence/original-alternatives.tsv"
for group in libblas.so.3-x86_64-linux-gnu liblapack.so.3-x86_64-linux-gnu libblas.so-x86_64-linux-gnu liblapack.so-x86_64-linux-gnu; do
  if update-alternatives --query "$group" > "$evidence/alternative-query.txt" 2>/dev/null; then
    value=$(sed -n 's/^Value: //p' "$evidence/alternative-query.txt")
    test -n "$value"
    printf '%s\t%s\n' "$group" "$value" >> "$evidence/original-alternatives.tsv"
  fi
done
restore_original() {
  while IFS=$'\t' read -r group value; do update-alternatives --set "$group" "$value"; done < "$evidence/original-alternatives.tsv"
  ldconfig
}

# Python fetches the public, hash-pinned specimens. This does not upgrade BLAS.
apt-get update -qq
apt-get install -y -qq --no-install-recommends python3
sha256sum -c "$evidence/original-native.sha256"
python3 .github/nold/intel_replay_fetch.py "$evidence/specimens"
unset GH_TOKEN
cp .github/nold/intel_blas_metadata.c "$evidence/build/"
(cd "$evidence/build" && PKG_LIBS=-ldl R CMD SHLIB intel_blas_metadata.c) > "$evidence/build/compile.log" 2>&1
export GTHEORY_META_SO="$evidence/build/intel_blas_metadata.so"
export GTHEORY_ORIGINAL_RUNTIME="$evidence/original-runtime.txt"
: > "$evidence/process-exits.tsv"

run_arm() {
  local label="$1" backend="$2" core="$3"
  export GT_EXPECT_BACKEND="$backend" GT_EXPECT_CORE="$core"
  if [ -n "$core" ]; then export OPENBLAS_CORETYPE="${core^^}"; else unset OPENBLAS_CORETYPE; fi
  for replica in 1 2 3; do
    local out="$evidence/$label/process-$replica"
    mkdir -p "$(dirname "$out")"
    local code=0
    local specimens=("$evidence/specimens/binary.rds" "$evidence/specimens/ordinal.rds")
    if [ "$replica" -eq 2 ]; then specimens=("$evidence/specimens/ordinal.rds" "$evidence/specimens/binary.rds"); fi
    Rscript --vanilla .github/nold/intel_replay.R "$out" "${specimens[@]}" > "$out.log" 2>&1 || code=$?
    printf '%s\t%s\t%s\n' "$label" "$replica" "$code" >> "$evidence/process-exits.tsv"
  done
  sha256sum -c "$evidence/release-before.sha256"
  sha256sum -c "$evidence/original-native.sha256"
}

run_arm default-before openblas ''
run_arm portable-nehalem openblas Nehalem

unset OPENBLAS_CORETYPE
apt-get install -y -qq --no-install-recommends libblas3 liblapack3
sha256sum -c "$evidence/original-native.sha256"
dpkg-query -W libblas3 liblapack3 libopenblas0-pthread > "$evidence/native-package-versions.txt"
update-alternatives --set libblas.so.3-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/blas/libblas.so.3
update-alternatives --set liblapack.so.3-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/lapack/liblapack.so.3
ldconfig
run_arm reference reference ''

restore_original
run_arm default-restored openblas ''
sha256sum -c "$evidence/release-before.sha256"
python3 - "$evidence" <<'PY'
from pathlib import Path
import csv, json, os, sys
root = Path(sys.argv[1])
processes = [dict(arm=arm, process=int(process), exit_code=int(code))
             for arm, process, code in csv.reader((root/'process-exits.tsv').open(), delimiter='\t')]
report = dict(diagnostic_only=True, release_qualification=False,
              runner_replica=os.environ['GTHEORY_REPLICA'],
              fixed_runner_panel=12, fresh_processes_per_arm=3,
              repetitions_per_matrix_and_factor=20,
              predetermined_arms=['default-before', 'portable-nehalem', 'reference', 'default-restored'],
              processes=processes,
              protocol_completed=len(processes)==12 and all(p['exit_code']==0 for p in processes),
              numerical_results='See each process results.tsv; exit zero only means the diagnostic executed.')
(root/'protocol-summary.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
sys.exit(0 if report['protocol_completed'] else 1)
PY
