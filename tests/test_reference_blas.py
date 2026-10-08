"""Exercise the reference-backend evidence gate with controlled runtime records."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / ".github/nold/check_reference_blas.R"
INPUTS = ROOT / ".github/nold/solve_probe_inputs.R"
RSCRIPT = shutil.which("Rscript")

# These synthetic paths represent observed mappings; they are not a claim that
# the machine executing this unit test has reference BLAS or lacks long double.
REFERENCE_RECORD = r'''
good <- list(system = c(sysname = "Linux"), long_double = FALSE,
  sizeof_longdouble = 0L, BLAS = "/reference/blas", LAPACK = "/reference/lapack",
  reference_BLAS = "/reference/blas", reference_LAPACK = "/reference/lapack",
  mapped_paths = c("/reference/blas", "/reference/lapack", "/runtime/R", "/runtime/libR"),
  process_maps = c("000-001 r-xp 0 0:0 1 /reference/blas",
                   "001-002 r-xp 0 0:0 2 /reference/lapack"),
  native_file_hashes = data.frame(role = c("BLAS", "LAPACK", "R_executable", "libR"),
    path = c("/reference/blas", "/reference/lapack", "/runtime/R", "/runtime/libR"),
    bytes = c(100, 200, 300, 400), md5 = rep(paste(rep("a", 32), collapse = ""), 4),
    stringsAsFactors = FALSE))
'''


@unittest.skipUnless(RSCRIPT, "Rscript is required to exercise the backend evidence gate")
class ReferenceBackendTests(unittest.TestCase):
    def run_r(self, code):
        with tempfile.TemporaryDirectory(prefix="gtheory-reference-test-") as temporary:
            root = Path(temporary)
            script = root / "exercise.R"
            script.write_text(
                "Sys.unsetenv('GTHEORY_REFERENCE_BASELINE')\n"
                "probe <- new.env(parent = globalenv())\n"
                f"sys.source({json.dumps(str(PROBE))}, probe)\n"
                f"fixture <- {json.dumps(str(INPUTS))}\n"
                f"scratch <- {json.dumps(str(root))}\n"
                + REFERENCE_RECORD + "\n" + code,
                encoding="utf-8")
            result = subprocess.run([RSCRIPT, "--vanilla", str(script)], cwd=ROOT,
                                    env=dict(os.environ), capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_reference_record_requires_both_libraries_maps_and_nold(self):
        self.run_r(r'''
stopifnot(length(probe$reference_failures(good)) == 0L)
cases <- list(
  function(x) { x$BLAS <- "/other/blas"; x },
  function(x) { x$LAPACK <- "/other/lapack"; x },
  function(x) { x$reference_BLAS <- NA_character_; x },
  function(x) { x$reference_LAPACK <- NA_character_; x },
  function(x) { x$process_maps <- character(); x },
  function(x) { x$mapped_paths <- setdiff(x$mapped_paths, x$BLAS); x },
  function(x) { x$process_maps <- c(x$process_maps, "loaded /other/libOpenBLAS.so"); x },
  function(x) { x$long_double <- TRUE; x },
  function(x) { x$sizeof_longdouble <- 16L; x },
  function(x) { x$system[["sysname"]] <- "Darwin"; x },
  function(x) { x$native_file_hashes <- x$native_file_hashes[-4, ]; x },
  function(x) { x$native_file_hashes$bytes[1] <- 0; x },
  function(x) { x$native_file_hashes$md5[1] <- "unknown"; x },
  function(x) { x$mapped_paths <- setdiff(x$mapped_paths, "/runtime/libR"); x })
for (change in cases) stopifnot(length(probe$reference_failures(change(good))) > 0L)
''')

    def test_baseline_identity_is_order_independent_but_rejects_changed_bytes(self):
        self.run_r(r'''
reordered <- good
reordered$native_file_hashes <- reordered$native_file_hashes[4:1, ]
stopifnot(length(probe$baseline_failures(reordered, good)) == 0L)
for (role in good$native_file_hashes$role) {
  changed <- good
  i <- match(role, changed$native_file_hashes$role)
  changed$native_file_hashes$md5[i] <- paste(rep("b", 32), collapse = "")
  stopifnot(length(probe$baseline_failures(changed, good)) > 0L)
}
bad_baseline <- good
bad_baseline$LAPACK <- "/other/lapack"
stopifnot(length(probe$baseline_failures(good, bad_baseline)) > 0L)
''')

    def test_success_keeps_original_bad_steps_and_all_planned_replays(self):
        self.run_r(r'''
probe$environment_record <- function() good
out <- file.path(scratch, "successful")
stopifnot(probe$probe_main(c("reference", out), fixture_file = fixture) == 0L)
e <- readRDS(file.path(out, "evidence.rds"))
stopifnot(e$reference_probe_pass, !e$package_qualification, e$native_total == 80L,
  e$native_invalid == 0L, length(e$operations) == 80L,
  identical(e$bound_formula, "32 * nrow(H) * .Machine$double.eps"),
  all(vapply(e$operations, function(x) x$row$bound == 32 * 28 * .Machine$double.eps, logical(1))),
  all(vapply(e$stored_steps, function(x) isTRUE(x$invalid) && x$error > x$bound, logical(1))),
  identical(readRDS(file.path(out, "runtime.rds")), good))
rows <- read.delim(file.path(out, "results.tsv"))
stopifnot(nrow(rows) == 80L, all(rows$valid),
  identical(sort(unique(rows$problem)), c("binary", "ordinal")),
  identical(sort(unique(rows$factor_source)), c("fresh_chol", "stored")))
''')

    def test_wrong_solve_is_retained_and_fails_reference_but_not_diagnostic_mode(self):
        self.run_r(r'''
probe$environment_record <- function() good
probe$backsolve <- function(...) rep(0, 28)
for (mode in c("reference", "snapshot")) {
  out <- file.path(scratch, mode)
  status <- probe$probe_main(c(mode, out), fixture_file = fixture)
  e <- readRDS(file.path(out, "evidence.rds"))
  stopifnot(status == if (mode == "reference") 1L else 0L,
    !e$reference_probe_pass, !e$package_qualification,
    e$native_invalid == 80L, length(e$operations) == 80L,
    all(vapply(e$operations, function(x) identical(x$step$value, rep(0, 28)), logical(1))))
  rows <- read.delim(file.path(out, "results.tsv"))
  stopifnot(nrow(rows) == 80L, !any(rows$valid), all(rows$solve_error > rows$bound))
  if (mode == "reference") stopifnot(grepl("Native solve regression", e$failure))
}
''')

    def test_dependency_loading_cannot_introduce_openblas(self):
        self.run_r(r'''
loaded <- FALSE
probe$loadNamespace <- function(package) { loaded <<- TRUE; invisible(NULL) }
probe$environment_record <- function() {
  info <- good
  if (loaded) info$process_maps <- c(info$process_maps, "loaded /other/libopenblas.so")
  info
}
out <- file.path(scratch, "after-load")
stopifnot(probe$probe_main(c("reference", out, "injected_dependency"), fixture_file = fixture) == 1L)
e <- readRDS(file.path(out, "evidence.rds"))
stopifnot(!e$reference_probe_pass, length(e$operations) == 0L,
  grepl("after_dependencies", e$failure), grepl("OpenBLAS", e$failure),
  identical(names(e$environments), c("before_dependencies", "after_dependencies")))
''')

    def test_baseline_drift_aborts_before_numerical_qualification(self):
        self.run_r(r'''
baseline <- file.path(scratch, "baseline.rds")
saveRDS(good, baseline)
Sys.setenv(GTHEORY_REFERENCE_BASELINE = baseline)
changed <- good
changed$native_file_hashes$md5[1] <- paste(rep("b", 32), collapse = "")
probe$environment_record <- function() changed
out <- file.path(scratch, "changed-runtime")
stopifnot(probe$probe_main(c("reference", out), fixture_file = fixture) == 1L)
e <- readRDS(file.path(out, "evidence.rds"))
stopifnot(!e$reference_probe_pass, length(e$operations) == 0L,
  grepl("differ from reference baseline", e$failure))
''')


if __name__ == "__main__":
    unittest.main()
