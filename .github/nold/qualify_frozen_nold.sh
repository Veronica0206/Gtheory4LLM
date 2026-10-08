#!/usr/bin/env bash
# Prototype for an isolated, unmerged qualification branch. Never builds a package.
# A fixed 24-runner panel is declared by the workflow; non-target hosts only record
# acquisition. Every matching host checks the same frozen published archive.
set -euo pipefail
root="${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
evidence="$root/frozen-nold-qualification-evidence"
mkdir -p "$evidence"
cd "$root"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0="$root"
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 OPENBLAS_VERBOSE=2
export RENV_CONFIG_AUTOLOADER_ENABLED=FALSE RENV_CONFIG_PPM_ENABLED=FALSE
export PYTHONDONTWRITEBYTECODE=1
unset OPENBLAS_CORETYPE GTHEORY_REFERENCE_BASELINE
stage=acquisition
target=false
archive="$root/artifacts/Gtheory4LLM_0.4.1.tar.gz"

finish() {
  local status=$?
  trap - EXIT
  set +e
  sha256sum artifacts/Gtheory4LLM_0.4.1.tar.gz artifacts/Gtheory4LLM-manual.pdf artifacts/manifest.json > "$evidence/release-after.sha256"
  local checksum_status=$?
  cmp "$evidence/release-before.sha256" "$evidence/release-after.sha256" > "$evidence/release-unchanged.txt" 2>&1
  local compare_status=$?
  git diff --exit-code HEAD -- > "$evidence/tracked-files-unchanged.txt" 2>&1
  local source_status=$?
  hostname > "$evidence/hostname-after.txt"
  cmp "$evidence/hostname-before.txt" "$evidence/hostname-after.txt" > "$evidence/same-container.txt" 2>&1
  local host_status=$?
  if (( checksum_status || compare_status || source_status || host_status )); then status=1; fi
  Rscript --vanilla - "$evidence" "$stage" "$status" "$target" <<'RS'
args <- commandArgs(TRUE)
out <- args[1]; stage <- args[2]; code <- as.integer(args[3]); target <- args[4] == "true"
q <- function(x) encodeString(as.character(x), quote = '"')
state <- if (code != 0L) "failed" else if (!target) "acquisition_not_target" else "qualified_reference"
writeLines(paste0('{\n  "schema_version": 1,\n  "fixed_panel_size": 24,\n  "replica": ',
  as.integer(Sys.getenv("GTHEORY_REPLICA")), ',\n  "run_id": ', q(Sys.getenv("GITHUB_RUN_ID")),
  ',\n  "run_attempt": ', q(Sys.getenv("GITHUB_RUN_ATTEMPT")),
  ',\n  "target_cpu_observed": ', tolower(as.character(target)),
  ',\n  "release_qualification": ', tolower(as.character(target && code == 0L && stage == "complete")),
  ',\n  "status": ', q(state), ',\n  "last_stage": ', q(stage), ',\n  "exit_code": ', code,
  ',\n  "archive_source_commit": "9b59788ad9bfc6068faea9115b62ea920d58e745",',
  '\n  "archive_sha256": "8261b2d8084a54fa69a4bb3b7ae0caac3eefcc75ba83969d09422d525460e554",',
  '\n  "checkout_commit": ', q(Sys.getenv("GTHEORY_QUALIFICATION_CHECKOUT")),
  ',\n  "interpretation": "Reference-backend qualification only; native default control is retained separately and is not made passing."\n}'),
  file.path(out, "qualification-status.json"))
RS
  local summary_status=$?
  if (( summary_status )); then status=1; fi
  exit "$status"
}
trap finish EXIT

hostname > "$evidence/hostname-before.txt"
export GTHEORY_QUALIFICATION_CHECKOUT="$(git rev-parse HEAD)"
{
  date -u +%Y-%m-%dT%H:%M:%SZ
  printf 'checkout_commit=%s\n' "$GTHEORY_QUALIFICATION_CHECKOUT"
  printf 'release_tag_commit=%s\n' "$(git rev-parse 'refs/tags/v0.4.1^{commit}')"
  printf 'replica=%s\nrun_id=%s\nrun_attempt=%s\n' "${GTHEORY_REPLICA:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}"
  uname -a
  cat /etc/os-release
  cat /proc/cpuinfo
  R --version
} > "$evidence/acquisition-platform.txt"
sha256sum artifacts/Gtheory4LLM_0.4.1.tar.gz artifacts/Gtheory4LLM-manual.pdf artifacts/manifest.json > "$evidence/release-before.sha256"
cat > "$evidence/frozen-release-expected.sha256" <<'HASHES'
8261b2d8084a54fa69a4bb3b7ae0caac3eefcc75ba83969d09422d525460e554  artifacts/Gtheory4LLM_0.4.1.tar.gz
9c866b0876c1ac0575af2e9c2c670922b782138d41bdc7c4e1ff1e7efb0bc8c1  artifacts/Gtheory4LLM-manual.pdf
3292bf4d55f72917f336b3e01ad0e475494a20a8e2ba70296e4315da4a6eddc4  artifacts/manifest.json
HASHES
sha256sum -c "$evidence/frozen-release-expected.sha256"
test "$(git rev-parse 'refs/tags/v0.4.1^{commit}')" = 3562aeca3f85ae689a4a237066100b963a820e51

# Cheap acquisition runs before apt, compilation, or TeX. Record every CPU,
# including non-targets. Both model name and actual CPUID family/model must match.
Rscript --vanilla - "$evidence" <<'RS'
out <- commandArgs(TRUE)[1]
stopifnot(Sys.info()[["sysname"]] == "Linux", Sys.info()[["machine"]] %in% c("x86_64", "amd64"),
          isFALSE(unname(capabilities("long.double"))), .Machine$sizeof.longdouble == 0,
          grepl("Under development", R.version.string, fixed = TRUE))
lines <- readLines("/proc/cpuinfo")
field <- function(name) unique(trimws(sub("^[^:]*:", "", lines[grepl(paste0("^", name, "[[:space:]]*:"), lines)])))
model_name <- field("model name"); family <- field("cpu family"); model <- field("model")
stopifnot(length(model_name) == 1L, length(family) == 1L, length(model) == 1L)
replica <- as.integer(Sys.getenv("GTHEORY_REPLICA")); stopifnot(!is.na(replica), replica %in% 1:24)
target <- identical(model_name, "Intel(R) Xeon(R) 6973P-C") && identical(family, "6") && identical(model, "173")
q <- function(x) encodeString(as.character(x), quote = '"')
writeLines(paste0('{\n  "fixed_panel_size": 24,\n  "replica": ', replica,
  ',\n  "model_name": ', q(model_name), ',\n  "cpu_family": ', q(family), ',\n  "cpu_model": ', q(model),
  ',\n  "target_cpu_observed": ', tolower(as.character(target)), ',\n  "hostname": ', q(Sys.info()[["nodename"]]),
  ',\n  "r_version": ', q(R.version.string), ',\n  "long_double": false,\n  "sizeof_long_double": 0\n}'),
  file.path(out, "acquisition.json"))
writeLines(if (target) "true" else "false", file.path(out, "target-match.txt"))
RS
target="$(cat "$evidence/target-match.txt")"
if [ "$target" != true ]; then
  stage=acquisition_not_target
  echo 'Target CPU not observed. Acquisition recorded; no full qualification claimed.'
  exit 0
fi

run_logged() {
  local output="$1"
  shift
  set +e
  "$@" 2>&1 | tee "$output"
  local result=("${PIPESTATUS[@]}")
  set -e
  if [ "${result[1]}" -ne 0 ]; then return "${result[1]}"; fi
  return "${result[0]}"
}

stage=frozen_identity
apt-get update -qq
apt-get install -y -qq --no-install-recommends python3
python3 scripts/check_committed_artifact.py --verify-only --release-tag v0.4.1 --output-dir "$evidence/frozen-identity"
python3 - "$root" "$evidence" <<'PY'
from pathlib import Path
import hashlib, json, subprocess, sys
root, evidence = map(Path, sys.argv[1:])
sys.path.insert(0, str(root / 'scripts'))
import check_committed_artifact as artifact
manifest = json.loads((root / 'artifacts/manifest.json').read_text())
source = '9b59788ad9bfc6068faea9115b62ea920d58e745'
assert manifest['source_commit'] == source
assert manifest['package'] == 'Gtheory4LLM' and manifest['version'] == '0.4.1'
head = artifact.git(root, 'rev-parse', 'HEAD').decode().strip()
source_paths = artifact.package_source_paths(root, source)
assert source_paths == artifact.package_source_paths(root, head), 'Packaged file inventory changed'
changed = [name for name in sorted(source_paths)
           if artifact.git(root, 'show', source + ':' + name) != artifact.git(root, 'show', head + ':' + name)]
assert not changed, 'Packaged source bytes changed: ' + repr(changed)
(evidence/'packaged-source-identity.json').write_text(json.dumps(dict(
    unchanged=True, checkout_commit=head, archive_source_commit=source,
    packaged_files_compared=len(source_paths), files=sorted(source_paths)), indent=2)+'\n')
PY

# Snapshot reports the original provider and all captured-solve outcomes. A
# native numerical failure is evidence, not permission to relax any gate.
stage=original_native_snapshot
run_logged "$evidence/original-native.log" Rscript --vanilla .github/nold/check_reference_blas.R snapshot "$evidence/original-native"
stage=original_native_control
Rscript --vanilla - "$evidence" <<'RS'
out <- commandArgs(TRUE)[1]
probe <- readRDS(file.path(out, "original-native", "evidence.rds"))
info <- readRDS(file.path(out, "original-native", "runtime.rds"))
tab <- read.delim(file.path(out, "original-native", "results.tsv"))
native_log <- readLines(file.path(out, "original-native.log"), warn = FALSE)
sha <- function(path) {
  if (length(path) != 1L || is.na(path) || !file.exists(path)) return(NA_character_)
  value <- suppressWarnings(system2("sha256sum", shQuote(path), stdout = TRUE, stderr = TRUE))
  status <- attr(value, "status")
  if (!is.null(status) && status != 0L) return(NA_character_)
  if (length(value) != 1L) return(NA_character_)
  strsplit(value, "[[:space:]]+")[[1]][1]
}
hashes <- c(BLAS = sha(info$BLAS), LAPACK = sha(info$LAPACK))
checks <- list(
  original_snapshot_completed = identical(probe$exit_status, 0L) && is.null(probe$failure),
  actual_core_cooperlake = any(trimws(native_log) == "Core: Cooperlake"),
  exact_blas_stub = identical(unname(hashes["BLAS"]), "babdd0d2612d7bd2f0099ac8c82714702fb5bb47b1e2e6fdba819c97c79fc0fd"),
  exact_openblas_provider = identical(unname(hashes["LAPACK"]), "1dedc9fee9ca46eb73e1abc9d989093acbb5bf1bb474fe673af7f0591fa4b2d9"),
  both_providers_actually_mapped = all(c(info$BLAS, info$LAPACK) %in% info$mapped_paths),
  all_80_native_solves_invalid = nrow(tab) == 80L && all(!tab$valid) && probe$native_invalid == 80L,
  all_native_steps_equal_original = nrow(tab) == 80L && all(is.finite(tab$original_difference)) && all(tab$original_difference == 0),
  preserved_stored_negative_controls = length(probe$stored_steps) == 2L && all(vapply(probe$stored_steps, function(z) isTRUE(z$invalid), logical(1)))
)
checks <- vapply(checks, isTRUE, logical(1))
q <- function(x) encodeString(as.character(x), quote = '"')
report <- c('{', paste0('  "success": ', tolower(as.character(all(checks))), ','),
  paste0('  "blas_sha256": ', q(hashes["BLAS"]), ','),
  paste0('  "provider_sha256": ', q(hashes["LAPACK"]), ','),
  '  "checks": {', paste0('    ', q(names(checks)), ': ', tolower(as.character(checks)),
    ifelse(seq_along(checks) < length(checks), ',', '')), '  }', '}')
writeLines(report, file.path(out, "original-native-control.json"))
if (!all(checks)) stop("Target native control did not match the previously affected configuration: ", paste(names(checks)[!checks], collapse = ", "))
RS
sha256sum -c "$evidence/frozen-release-expected.sha256"

stage=reference_selection
run_logged "$evidence/reference-selection.log" bash .github/nold/select_reference_blas.sh "$evidence/reference-selection"
# GITHUB_ENV affects later Actions steps, not this already-running shell.
export GTHEORY_REFERENCE_BASELINE="$evidence/reference-selection/probe/runtime.rds"
test -f "$GTHEORY_REFERENCE_BASELINE"

stage=dependencies
apt-get update -qq
apt-get install -y -qq cmake libnlopt-dev libcurl4-openssl-dev libssl-dev libxml2-dev libuv1-dev pandoc tidy qpdf
Rscript --vanilla -e 'options(repos = c(CRAN = "https://cloud.r-project.org")); install.packages("tinytex"); tinytex::install_tinytex(force = TRUE)'
texbin="$(Rscript --vanilla -e 'cat(tinytex::tinytex_root())')/bin/x86_64-linux"
"$texbin/tlmgr" update --self
"$texbin/tlmgr" install makeindex inconsolata helvetic times courier collection-latexrecommended
for executable in pdflatex makeindex; do test -x "$texbin/$executable"; done
export PATH="$texbin:$PATH"
Rscript --vanilla - "$evidence" <<'RS'
out <- commandArgs(TRUE)[1]
options(Ncpus = 4L, repos = c(CRAN = "https://cloud.r-project.org"))
wanted <- c("OpenMx", "Matrix", "lme4", "ordinal", "knitr", "rmarkdown")
need <- setdiff(wanted, rownames(installed.packages()))
if (length(need)) install.packages(need, type = "source")
stopifnot(all(vapply(wanted, requireNamespace, logical(1), quietly = TRUE)))
ip <- installed.packages()[, c("Package", "Version")]; ip <- ip[order(ip[, "Package"]), ]
write.csv(ip, file.path(out, "installed-packages.csv"), row.names = FALSE)
RS
run_logged "$evidence/reference-dependencies.log" Rscript --vanilla .github/nold/check_reference_blas.R reference "$evidence/reference-dependencies" Matrix OpenMx lme4 ordinal

stage=install_frozen_archive
library="$RUNNER_TEMP/frozen-reference-lib"
unpacked="$RUNNER_TEMP/frozen-reference-unpacked"
mkdir -p "$library" "$unpacked" "$evidence/check" "$evidence/specimens"
export R_LIBS="$library" GTHEORY_DISCRETE_SPECIMEN_DIR="$evidence/specimens"
sha256sum -c "$evidence/frozen-release-expected.sha256"
run_logged "$evidence/frozen-install.log" R CMD INSTALL --no-docs --library="$library" "$archive"
# The safe archive reader has already rejected links and unsafe member paths.
tar -xzf "$archive" -C "$unpacked"
run_logged "$evidence/reference-installed.log" Rscript --vanilla .github/nold/check_reference_blas.R reference "$evidence/reference-installed" Matrix OpenMx lme4 ordinal Gtheory4LLM

# Retain all three results even when a numerical gate fails. Operational setup
# and backend proof fail immediately; tests never retry or adjust tolerances.
stage=boundary_diagnosis
boundary_status=0
run_logged "$evidence/boundary-fit-diagnosis.txt" Rscript --vanilla .github/nold/diagnose.R "$library" || boundary_status=$?
sha256sum -c "$evidence/frozen-release-expected.sha256"
stage=full_check
check_status=0
cd "$evidence/check"
run_logged "$evidence/full-check-console.txt" R CMD check --no-stop-on-test-error "$archive" || check_status=$?
cd "$root"
sha256sum -c "$evidence/frozen-release-expected.sha256"
stage=installed_tests
tests_status=0
run_logged "$evidence/installed-tests-summary.txt" Rscript --vanilla .github/nold/run_tests.R "$library" "$unpacked/Gtheory4LLM/tests" "$evidence/installed-tests" || tests_status=$?
stage=final_reference_proof
run_logged "$evidence/reference-final.log" Rscript --vanilla .github/nold/check_reference_blas.R reference "$evidence/reference-final" Matrix OpenMx lme4 ordinal Gtheory4LLM
sha256sum -c "$evidence/frozen-release-expected.sha256"

stage=result_validation
python3 - "$evidence" "$unpacked/Gtheory4LLM/tests" "$boundary_status" "$check_status" "$tests_status" <<'PY'
from pathlib import Path
import csv, json, sys
out, source_tests = map(Path, sys.argv[1:3])
codes = dict(zip(('boundary_diagnosis', 'full_check', 'installed_tests'), map(int, sys.argv[3:])))
expected = sorted(p.name for p in source_tests.glob('package-*.R'))
logs = sorted((out/'check').glob('*.Rcheck/00check.log'))
check_text = logs[0].read_text(errors='replace') if len(logs) == 1 else ''
check_roots = sorted((out/'check').glob('*.Rcheck/tests'))
rout = sorted(p.name for p in check_roots[0].glob('*.Rout')) if len(check_roots) == 1 else []
failed_rout = sorted(str(p.relative_to(out)) for p in (out/'check').rglob('*.Rout.fail'))
status_path = out/'installed-tests/test-status.csv'
rows = list(csv.DictReader(status_path.open())) if status_path.is_file() else []
checks = dict(
    all_exit_codes_zero=all(code == 0 for code in codes.values()),
    exactly_27_source_tests=len(expected) == 27,
    exactly_one_check_log=len(logs) == 1,
    full_check_status_ok='Status: OK' in check_text.splitlines(),
    pdf_manual_checked='* checking PDF version of manual ... OK' in check_text.splitlines(),
    package_vignettes_checked='* checking package vignettes ... OK' in check_text.splitlines(),
    vignette_outputs_rebuilt='* checking re-building of vignette outputs ... OK' in check_text.splitlines(),
    examples_checked='* checking examples ... OK' in check_text.splitlines(),
    exactly_27_check_outputs=rout == sorted(name+'out' for name in expected),
    no_failed_check_outputs=not failed_rout,
    exactly_27_installed_test_rows=len(rows) == 27 and sorted(r.get('test', '') for r in rows) == expected,
    all_installed_test_exits_zero=bool(rows) and all(r.get('exit_code') == '0' for r in rows),
    exactly_27_installed_outputs=sorted(p.name for p in (out/'installed-tests').glob('*.Rout')) == sorted(name+'out' for name in expected),
)
report = dict(success=all(checks.values()), scope='frozen_published_archive_reference_backend',
              exit_codes=codes, checks=checks, check_log=str(logs[0].relative_to(out)) if logs else None,
              failed_rout=failed_rout, installed_test_status=rows)
(out/'full-qualification-results.json').write_text(json.dumps(report, indent=2)+'\n')
print(json.dumps(report, indent=2))
sys.exit(0 if report['success'] else 1)
PY
stage=complete
echo 'Same-machine target qualification complete for the unchanged published archive using verified reference BLAS/LAPACK.'
