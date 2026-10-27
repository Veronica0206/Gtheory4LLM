# Run from the project directory with Rscript tests/test_discrete_equivalence_amendment2.R.
#
# Regression checks for Amendment 2's stage 4 judgment
# (validation-studies/discrete-sparse-equivalence/amendment-2-impl.R), on the
# non-scoring calibration case K02 and on constructed fits, never on a
# qualification case:
#
#   * when both fits are accepted, the dispositions differ, or both fits are
#     refused, the amended stage 4 records exactly what the merged one does;
#   * when both fits are rejected for the same reasons and agree, the case
#     passes stage 4 through the rejected-fit comparisons, where the merged
#     stage 4 fails it;
#   * different acceptance failures, or rejected fits that differ beyond the
#     frozen fitted tolerances, fail;
#   * the latent G/Phi part of the amended stage 4 is the merged one, verbatim;
#   * the entry point and the launcher refuse a changed tolerance file,
#     implementation or manifest and a modified in-memory table, and a refused
#     rerun leaves an existing record unchanged.
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode",
            "discrete_sparse", "discrete_sparse_mode", "discrete", "diagnostics_stages"))
  source(file.path("R", paste0(f, ".R")))
source(file.path(STUDY, "equivalence-runner-impl.R"))
source(file.path(STUDY, "amendment-1-impl.R"))
source(file.path(STUDY, "amendment-2-impl.R"))
tolerances <- read.csv(file.path(STUDY, "tolerances.csv"), stringsAsFactors = FALSE)

fails <- 0L
ok <- function(condition, label) {
  if (!isTRUE(condition)) { fails <<- fails + 1L; cat("FAIL: ", label, "\n", sep = "") }
}
tables <- .eqr_exercise_tables()
run_k02 <- function() {
  out <- tempfile("eq-amendment2-test-")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  capture.output(result <- .eqr_run(STUDY, tolerances, tables$cases[tables$cases$case == "K02", ],
                                    EQ_CALIBRATION_GEOMETRY, "amendment2_test", tables$transforms[0, ],
                                    tables$overlays[0, ], tables$references[0, ], out))
  result
}
stage4 <- function(result) result$record[result$record$stage == 4L, ]
verdict <- function(result) result$summary$verdict[result$summary$id == "K02"]
gating <- function(result, quantity) {
  r <- stage4(result)
  r$disposition[r$row_kind == "quantity" & r$quantity == quantity]
}
original_fit <- .eqr_fit
amended <- .eqr_stage4
# One run of K02 with a stage 4 judgment and a fit wrapper, restored afterwards.
under <- function(stage, fit = original_fit) {
  assign(".eqr_stage4", stage, envir = globalenv())
  assign(".eqr_fit", fit, envir = globalenv())
  on.exit({ assign(".eqr_stage4", amended, envir = globalenv())
            assign(".eqr_fit", original_fit, envir = globalenv()) }, add = TRUE)
  run_k02()
}
# A one-iteration optimizer budget leaves K02's fit rejected by both backends,
# for the same reasons, at closely agreeing estimates.
capped <- function(row, map, backend, control = .eq_control_for(row$covariance)) {
  control$maxit <- 1L
  original_fit(row, map, backend, control)
}
altered <- function(change) function(row, map, backend, control = .eq_control_for(row$covariance)) {
  f <- capped(row, map, backend, control)
  if (identical(backend, "sparse")) f <- change(f)
  f
}

# ---- outside rule B the merged stage 4 decides, unchanged --------------------------------
scenarios <- list(
  "both fits accepted" = original_fit,
  "the dispositions differ" = function(row, map, backend, control = .eq_control_for(row$covariance))
    if (identical(backend, "sparse")) capped(row, map, backend, control) else original_fit(row, map, backend, control),
  "both fits refused" = function(row, map, backend, control = .eq_control_for(row$covariance))
    list(disposition = "refused", message = "constructed refusal", elapsed = 0))
for (name in names(scenarios)) {
  merged <- under(.eqr2_frozen_stage4, scenarios[[name]])
  now <- under(amended, scenarios[[name]])
  ok(identical(stage4(now), stage4(merged)) && identical(verdict(now), verdict(merged)),
     paste0(name, ": the amended stage 4 records exactly what the merged one does"))
}
ok(identical(verdict(under(amended)), "pass"), "K02 passes when both fits are accepted")

# ---- rule B: both fits rejected ------------------------------------------------------------
merged <- under(.eqr2_frozen_stage4, capped)
now <- under(amended, capped)
ok(identical(verdict(merged), "fail") && identical(gating(merged, "fitted_objective_relative"), "not_measured"),
   "the merged stage 4 fails two agreeing rejected fits as not measured")
ok(identical(verdict(now), "pass") &&
     all(vapply(c("disposition_agreement", "rejection_reason_agreement", "rejected_fit_layout",
                  "rejected_fit_objective_relative", "rejected_fit_parameter_distance"),
                function(q) identical(gating(now, q), "pass"), logical(1))) &&
     all(vapply(c("fitted_layout", "fitted_objective_relative", "fitted_parameter_distance"),
                function(q) identical(gating(now, q), "not_applicable"), logical(1))),
   "two rejected fits with the same failures and agreeing estimates pass through B1 and B2")
ok(any(now$detail$quantity == "rejection_reasons" & grepl("optimizer_incomplete", now$detail$message, fixed = TRUE)),
   "both fits' acceptance failures are written to the detail record")
for (mutation in list(
  list(label = "different acceptance failures fail B1, and B2 is not measured",
       change = function(f) { f$message <- paste0(f$message, "|constructed_failure"); f },
       expect = c(rejection_reason_agreement = "fail", rejected_fit_objective_relative = "not_measured")),
  list(label = "a rejected-fit objective 1e-5 apart fails the frozen 1e-6",
       change = function(f) { f$nll <- f$nll * (1 + 1e-5); f },
       expect = c(rejection_reason_agreement = "pass", rejected_fit_objective_relative = "fail",
                  rejected_fit_parameter_distance = "pass")),
  list(label = "rejected-fit parameters far apart fail the frozen distance",
       change = function(f) { f$parameters <- f$parameters + 0.5; f },
       expect = c(rejection_reason_agreement = "pass", rejected_fit_objective_relative = "pass",
                  rejected_fit_parameter_distance = "fail")))) {
  result <- under(amended, altered(mutation$change))
  ok(identical(verdict(result), "fail") &&
       all(vapply(names(mutation$expect), function(q) identical(gating(result, q), mutation$expect[[q]]), logical(1))),
     mutation$label)
}

# ---- the latent G/Phi part is the merged one ----------------------------------------------
tail_from <- function(f) {
  statements <- as.list(body(f))[-1L]
  first <- which(vapply(statements, function(s) startsWith(paste(deparse(s), collapse = ""), "eligibility <-"),
                        logical(1)))
  lapply(statements[first:length(statements)], deparse)
}
ok(identical(tail_from(amended), tail_from(.eqr2_frozen_stage4)),
   "the amended stage 4's latent G/Phi part is the merged one, verbatim")

# ---- runtime pins ---------------------------------------------------------------------------
# The run itself is replaced, so a check that wrongly passes stops at once
# instead of starting the qualification.
frozen_run <- .eqr_run
.eqr_run <- function(...) stop("the run was reached", call. = FALSE)
outcome <- function(expr) tryCatch({ force(expr); "no error" }, error = conditionMessage)
Sys.setenv(EQ_RESULTS_DIR = file.path(tempdir(), "eq-amendment2-never-written"))
ok(identical(outcome(eq2_run_qualification(STUDY)), "the run was reached") &&
     identical(outcome(eq2_run_qualification(STUDY, tolerances = tolerances)), "the run was reached"),
   "the reviewed pins verify, and the reviewed table may be supplied")
modified <- tolerances
modified$tolerance[[1L]] <- modified$tolerance[[1L]] * 10
ok(grepl("supplied tolerance table is not the reviewed", outcome(eq2_run_qualification(STUDY, tolerances = modified))),
   "a modified in-memory tolerance table is refused")
copy_study <- function() {
  root <- tempfile("eq-amendment2-project-")
  dir.create(file.path(root, "validation-studies"), recursive = TRUE)
  file.copy(STUDY, file.path(root, "validation-studies"), recursive = TRUE)
  file.copy("R", root, recursive = TRUE)
  root
}
# The launcher runs in its own process from the copied project, with its record
# directed to a directory that must never appear.
launch <- function(root) {
  home <- setwd(root)
  on.exit(setwd(home), add = TRUE)
  Sys.setenv(EQ_RESULTS_DIR = file.path(root, "never-written"))
  suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", file.path(STUDY, "run-equivalence-amendment-2.R")), stdout = TRUE, stderr = TRUE, timeout = 120))
}
edit_line <- function(path, from, to) writeLines(sub(from, to, readLines(path, warn = FALSE), fixed = TRUE), path)
changes <- list(
  "tolerances.csv" = function(study) edit_line(file.path(study, "tolerances.csv"), "1e-10", "1e-09"),
  "equivalence-runner-impl.R" = function(study) cat("# edited\n", file = file.path(study, "equivalence-runner-impl.R"), append = TRUE),
  "amendment-1-impl.R" = function(study) cat("# edited\n", file = file.path(study, "amendment-1-impl.R"), append = TRUE),
  # A tampered entry point that would skip its own check: only the launcher's
  # check, made before anything is sourced, can refuse it.
  "amendment-2-impl.R" = function(study) cat(".eqr2_verify_pins <- function(study) stop(\"tampered entry point reached\")\n",
                                             file = file.path(study, "amendment-2-impl.R"), append = TRUE))
for (name in names(changes)) {
  root <- copy_study()
  study <- file.path(root, STUDY)
  changes[[name]](study)
  ok(grepl(paste0("Refusing to run: ", name, " differ"), outcome(eq2_run_qualification(study)), fixed = TRUE),
     paste0("the entry point refuses a changed ", name))
  launched <- launch(root)
  ok(!is.null(attr(launched, "status")) && any(grepl(paste0("Refusing to launch: ", name, " differ"), launched, fixed = TRUE)) &&
       !dir.exists(file.path(root, "never-written")),
     paste0("the launcher refuses a changed ", name, " before sourcing anything"))
  unlink(root, recursive = TRUE)
}
# A manifest re-pinned to match a changed file is not the reviewed manifest.
root <- copy_study()
study <- file.path(root, STUDY)
changes[["tolerances.csv"]](study)
pins <- read.csv(file.path(study, "amendment-2-pins.csv"), stringsAsFactors = FALSE)
pins$md5[pins$file == "tolerances.csv"] <- .eqr_content_digest(file.path(study, "tolerances.csv"))
write.csv(pins, file.path(study, "amendment-2-pins.csv"), row.names = FALSE)
launched <- launch(root)
ok(!is.null(attr(launched, "status")) && any(grepl("Refusing to launch: ", launched, fixed = TRUE)) &&
     any(grepl("is not the reviewed manifest", launched, fixed = TRUE)) &&
     !dir.exists(file.path(root, "never-written")),
   "the launcher refuses a re-pinned manifest")
unlink(root, recursive = TRUE)
.eqr_run <- frozen_run
# With the real runner in place, a rerun into an existing record is refused
# and leaves the record's environment file byte for byte as it was.
existing <- tempfile("eq-amendment2-existing-")
dir.create(existing)
writeLines(c("source_commit: an earlier run", "tolerances: a0f24f254d0733ff22d158e53390d782"),
           file.path(existing, "environment.txt"))
before <- readBin(file.path(existing, "environment.txt"), "raw", 4096L)
Sys.setenv(EQ_RESULTS_DIR = existing)
ok(grepl("Refusing to overwrite an existing record", outcome(eq2_run_qualification(STUDY)), fixed = TRUE) &&
     identical(readBin(file.path(existing, "environment.txt"), "raw", 4096L), before) &&
     identical(list.files(existing, all.files = TRUE, no.. = TRUE), "environment.txt"),
   "a refused rerun leaves an existing record unchanged")
unlink(existing, recursive = TRUE)
Sys.unsetenv("EQ_RESULTS_DIR")

if (fails) { cat("FAILURES: ", fails, "\n", sep = ""); quit(status = 1) }
cat("Equivalence Amendment 2 regressions verified: the merged stage 4 outside rule B, agreeing rejected fits ",
    "passing B1 and B2, differing failures, objectives and parameters failing, the verbatim latent G/Phi part, ",
    "the runtime pins and an existing record left unchanged.\n", sep = "")
