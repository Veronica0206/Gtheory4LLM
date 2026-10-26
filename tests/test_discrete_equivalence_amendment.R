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
#   * modes farther apart than their gradients allow fail A2a.
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
     setequal(stage3(baseline)$quantity, .EQR1_GATING) && all(stage3(baseline)$disposition == "pass"),
   "K02 passes with every amended stage 3 quantity measured and gating")
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
ok(identical(planted$summary$verdict[planted$summary$id == "K02"], "fail") &&
     identical(stage3(planted, "fail")$quantity, "marginal_negative_log_likelihood_at_common_mode"),
   "a 1e-9 disagreement at a common mode fails at the frozen 1e-10")

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

if (fails) { cat("FAILURES: ", fails, "\n", sep = ""); quit(status = 1) }
cat("Equivalence Amendment 1 regressions verified: amended stage 3 on a calibration case, acceptable stopping ",
    "points, arithmetic at common modes, the summation bound and the convexity bound.\n", sep = "")
