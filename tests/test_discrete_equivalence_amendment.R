# Run from the project directory with Rscript tests/test_discrete_equivalence_amendment.R.
#
# Regression checks for Amendment 1's stage 3 judgment
# (validation-studies/discrete-sparse-equivalence/amendment-1-impl.R), on the
# non-scoring calibration panels and on constructed inputs, never on a
# qualification case:
#
#   * a calibration case passes, with every amended quantity measured;
#   * two acceptable stopping points of the mode solve pass the amended rules,
#     although the original as-produced comparison exceeds its frozen tolerance;
#   * an arithmetic disagreement at a common mode still fails at the frozen
#     tolerance;
#   * a score difference beyond the summation bound fails A1, and a sparse
#     product of the same terms passes it;
#   * modes farther apart than their gradients allow fail A2a;
#   * an objective an evaluator returns off its own algebra fails A2c, although
#     every comparison at the common modes still agrees;
#   * the entry point and the launcher refuse a changed tolerance file, a
#     changed implementation or manifest, and a modified in-memory table.
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode",
            "discrete_sparse", "discrete_sparse_mode", "discrete", "diagnostics_stages"))
  source(file.path("R", paste0(f, ".R")))
source(file.path(STUDY, "equivalence-runner-impl.R"))
source(file.path(STUDY, "amendment-1-impl.R"))
tolerances <- read.csv(file.path(STUDY, "tolerances.csv"), stringsAsFactors = FALSE)

fails <- 0L
ok <- function(condition, label) {
  if (!isTRUE(condition)) { fails <<- fails + 1L; cat("FAIL: ", label, "\n", sep = "") }
}
tables <- .eqr_exercise_tables()
case <- function(id) tables$cases[tables$cases$case == id, ]
run <- function(cases) {
  out <- tempfile("eq-amendment-test-")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  capture.output(result <- .eqr_run(STUDY, tolerances, cases, EQ_CALIBRATION_GEOMETRY, "amendment_test",
                                    tables$transforms[0, ], tables$overlays[0, ], tables$references[0, ], out))
  result
}
stage3 <- function(result, verdict = NULL) {
  r <- result$record[result$record$stage == 3L & result$record$row_kind == "quantity", ]
  if (is.null(verdict)) r else r[r$disposition == verdict, ]
}
detail3 <- function(result, quantity)
  result$detail$measured[result$detail$stage == 3L & result$detail$quantity == quantity]
original <- list(evaluate = .eqr_evaluate, at = .eqr1_at)

# ---- a calibration case ----------------------------------------------------------------
baseline <- run(case("K02"))
ok(identical(baseline$summary$verdict[baseline$summary$id == "K02"], "pass") &&
     setequal(stage3(baseline)$quantity, c(.EQR1_GATING, .EQR1_RETURNED)) &&
     all(stage3(baseline)$disposition == "pass") &&
     setequal(stage3(baseline)$backend[stage3(baseline)$quantity %in% .EQR1_RETURNED], c("dense", "sparse")),
   "K02 passes with every amended stage 3 quantity measured and gating, A2c for each backend")
ok(all(c("conditional_mode", "log_determinant", "marginal_negative_log_likelihood") %in%
         baseline$detail$quantity[baseline$detail$status == "information"]),
   "the original as-produced comparisons are kept as information")

# ---- two acceptable stopping points -----------------------------------------------------
# The dense mode solve is stopped early by a loose inner tolerance, as on the
# macOS C13 point. Its mode and objective then differ from the sparse ones by
# far more than the frozen arithmetic tolerances, but within what both solves'
# gradients allow, and the two backends agree at each common mode.
.eqr_evaluate <- function(backend, theta, map, evaluator) {
  if (identical(backend, "dense")) map$control$inner_tol <- 1e-3
  original$evaluate(backend, theta, map, evaluator)
}
stopped <- run(case("K02"))
.eqr_evaluate <- original$evaluate
ok(max(detail3(stopped, "conditional_mode")) > 1e-13 && max(detail3(stopped, "marginal_negative_log_likelihood")) > 1e-10,
   "the early dense stop moves the as-produced mode and objective beyond their frozen tolerances")
ok(identical(stopped$summary$verdict[stopped$summary$id == "K02"], "pass") && all(stage3(stopped)$disposition == "pass"),
   "the amended rules accept two acceptable stopping points")

# ---- arithmetic at a common mode ----------------------------------------------------------
.eqr1_at <- function(backend, map, theta, latent) {
  out <- original$at(backend, map, theta, latent)
  if (!is.null(out) && identical(backend, "sparse"))
    out$marginal_negative_log_likelihood <- out$marginal_negative_log_likelihood + 1e-9
  out
}
planted <- run(case("K02"))
.eqr1_at <- original$at
# The planted sparse algebra also disagrees with the objective its evaluator
# returned, so A2c fails for the sparse backend alone.
failed <- stage3(planted, "fail")
ok(identical(planted$summary$verdict[planted$summary$id == "K02"], "fail") &&
     setequal(failed$quantity, c("marginal_negative_log_likelihood_at_common_mode",
                                 "returned_marginal_negative_log_likelihood")) &&
     identical(failed$backend[failed$quantity == "returned_marginal_negative_log_likelihood"], "sparse"),
   "a 1e-9 disagreement at a common mode fails at the frozen 1e-10")

# ---- the objectives an evaluator returns ------------------------------------------------------
# A sparse evaluator that returns its objective 1e-8 off its own algebra. Every
# comparison at the common modes recomputes the objective and still agrees, so
# only A2c can catch it, and it must, for the sparse backend alone.
for (field in c("nll", "conditional_nll")) {
  .eqr_evaluate <- function(backend, theta, map, evaluator) {
    answer <- original$evaluate(backend, theta, map, evaluator)
    if (identical(backend, "sparse") && isTRUE(answer$valid)) answer[[field]] <- answer[[field]] + 1e-8
    answer
  }
  shifted <- run(case("K02"))
  .eqr_evaluate <- original$evaluate
  quantity <- if (identical(field, "nll")) "returned_marginal_negative_log_likelihood" else "returned_conditional_objective"
  failed <- stage3(shifted, "fail")
  ok(identical(shifted$summary$verdict[shifted$summary$id == "K02"], "fail") && identical(failed$quantity, quantity) &&
       identical(failed$backend, "sparse") &&
       all(stage3(shifted)$disposition[stage3(shifted)$quantity %in% .EQR1_GATING] == "pass"),
     paste0("a returned ", field, " 1e-8 off the evaluator's own algebra fails A2c alone"))
}

# ---- A1 on constructed inputs -------------------------------------------------------------
W <- matrix(c(0.4, 0, 0.7, 0.4, 0.2, 0, 0, 0.7, 0.2, 0.4, 0, 0.7), 6L, 2L)
g <- c(98.25, -113.5, 121.0625, -87.75, 145.875, -101.125)
eta <- matrix(1, 6L, 1L)
ok(isTRUE(.eqr1_score_ratio(W, Matrix::Matrix(W, sparse = TRUE), eta, eta, g) <= 1),
   "a sparse product of the same terms is within the summation bound")
shifted <- W; shifted[1L, 1L] <- shifted[1L, 1L] * (1 + 1e-9)
ok(isTRUE(.eqr1_score_ratio(W, Matrix::Matrix(shifted, sparse = TRUE), eta, eta, g) > 1),
   "a score difference beyond the summation bound fails A1")
ok(is.nan(.eqr1_score_ratio(W, Matrix::Matrix(W, sparse = TRUE), eta, eta + 1e-12, g)),
   "A1 is not measured unless the predictor is shared exactly")

# ---- A2a on constructed modes -------------------------------------------------------------
answers <- list(dense = list(mode = c(0.5, -0.25, 1), inner_gradient = 1e-12),
                sparse = list(mode = c(0.5, -0.25, 1 + 1e-3), inner_gradient = 1e-12))
at <- list(dense = list(dense = list(gradient = rep(0, 6L))), sparse = list(dense = list(gradient = rep(0, 6L))))
ok(isTRUE(.eqr1_mode_ratio(answers, matrix(0.1, 6L, 3L), at) > 1),
   "modes 1e-3 apart with gradients of 1e-12 fail A2a")
answers$sparse$inner_gradient <- 1e-3
ok(isTRUE(.eqr1_mode_ratio(answers, matrix(0.1, 6L, 3L), at) <= 1),
   "the same modes pass when the reported gradients allow that distance")

# ---- runtime pins -------------------------------------------------------------------------
# The entry point verifies amendment-1-pins.csv and reads the tolerances from
# the verified file. The run itself is replaced here, so a check that wrongly
# passes stops at once instead of starting the qualification.
run_reached <- function(...) stop("the run was reached", call. = FALSE)
frozen_run <- .eqr_run
.eqr_run <- run_reached
outcome <- function(expr) tryCatch({ force(expr); "no error" }, error = conditionMessage)
Sys.setenv(EQ_RESULTS_DIR = file.path(tempdir(), "eq-amendment-never-written"))
ok(identical(outcome(eq1_run_qualification(STUDY)), "the run was reached") &&
     identical(outcome(eq1_run_qualification(STUDY, tolerances = tolerances)), "the run was reached"),
   "the reviewed pins verify, and the reviewed table may be supplied")
modified <- tolerances
modified$tolerance[[1L]] <- modified$tolerance[[1L]] * 10
ok(grepl("supplied tolerance table is not the reviewed", outcome(eq1_run_qualification(STUDY, tolerances = modified))),
   "a modified in-memory tolerance table is refused")
copy_study <- function() {
  root <- tempfile("eq-amendment-project-")
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
    c("--vanilla", file.path(STUDY, "run-equivalence-amendment-1.R")), stdout = TRUE, stderr = TRUE, timeout = 120))
}
edit_line <- function(path, from, to) {
  text <- readLines(path, warn = FALSE)
  writeLines(sub(from, to, text, fixed = TRUE), path)
}
changes <- list(
  "tolerances.csv" = function(study) edit_line(file.path(study, "tolerances.csv"), "1e-10", "1e-09"),
  "equivalence-runner-impl.R" = function(study) cat("# edited\n", file = file.path(study, "equivalence-runner-impl.R"), append = TRUE),
  # A tampered entry point that would skip its own check: only the launcher's
  # check, made before anything is sourced, can refuse it.
  "amendment-1-impl.R" = function(study) cat(".eqr1_verify_pins <- function(study) stop(\"tampered entry point reached\")\n",
                                             file = file.path(study, "amendment-1-impl.R"), append = TRUE))
for (name in names(changes)) {
  root <- copy_study()
  study <- file.path(root, STUDY)
  changes[[name]](study)
  ok(grepl(paste0("Refusing to run: ", name, " differ"), outcome(eq1_run_qualification(study)), fixed = TRUE),
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
pins <- read.csv(file.path(study, "amendment-1-pins.csv"), stringsAsFactors = FALSE)
pins$md5[pins$file == "tolerances.csv"] <- .eqr_content_digest(file.path(study, "tolerances.csv"))
write.csv(pins, file.path(study, "amendment-1-pins.csv"), row.names = FALSE)
launched <- launch(root)
ok(!is.null(attr(launched, "status")) && any(grepl("Refusing to launch: ", launched, fixed = TRUE)) &&
     any(grepl("is not the reviewed manifest", launched, fixed = TRUE)) &&
     !dir.exists(file.path(root, "never-written")),
   "the launcher refuses a re-pinned manifest")
unlink(root, recursive = TRUE)
.eqr_run <- frozen_run
Sys.unsetenv("EQ_RESULTS_DIR")

if (fails) { cat("FAILURES: ", fails, "\n", sep = ""); quit(status = 1) }
cat("Equivalence Amendment 1 regressions verified: amended stage 3 on a calibration case, acceptable stopping ",
    "points, arithmetic at common modes, returned objectives, the summation bound, the convexity bound and ",
    "the runtime pins.\n", sep = "")
