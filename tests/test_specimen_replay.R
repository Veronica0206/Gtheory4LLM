# Run from the project directory with Rscript tests/test_specimen_replay.R.
#
# The specimen replay tool, scripts/replay_specimen.R, must read back what the
# engine writes and separate the three questions it answers: does the stored
# step still fail the stored system, does the stored factor still fail here,
# and does a fresh factorization here fail too. Specimens are produced through
# the real refusal site, with the failure injected through the private
# evaluator seam so the stored operation is a real matrix and a deliberately
# wrong factor, on both storage forms.
source(file.path("scripts", "replay_specimen.R"))
source(file.path("validation-studies", "discrete-sparse-reference", "cases.R"))
source(file.path("R", "discrete_sparse_mode.R"))
suppressMessages(library(Matrix))

fails <- 0L
ok <- function(condition, label) {
  if (!isTRUE(condition)) { fails <<- fails + 1L; cat("FAIL: ", label, "\n", sep = "") }
}
directory <- tempfile("gt-specimen-test-")
Sys.setenv(GTHEORY_DISCRETE_SPECIMEN_DIR = directory)
on.exit({ Sys.unsetenv("GTHEORY_DISCRETE_SPECIMEN_DIR"); unlink(directory, recursive = TRUE) },
        add = TRUE)

# A real conditional system from a frozen reference case, dense and sparse.
case <- cases[[which(vapply(cases, function(x) identical(x$key, "binary_probit_crossed"), logical(1)))]]
control <- .gt_d_control(case$control)
prep <- .gt_d_prepare(case$data, case$outcomes, case$families)
groups <- lapply(case$design$term_members, function(m) .gt_d_group(case$data, m))
setup <- .gt_d_covariance_setup(groups, prep$q, case$covariance, control, prep$dimensions)
parameters <- c(prep$start + case$offset, setup$start * case$scale)
factors <- .gt_d_covariance_factors(parameters[-seq_along(prep$start)], setup)
eta <- .gt_d_baseline(parameters, prep)
kernel <- .gt_d_response_kernel(eta, parameters, prep)
W_dense <- .gt_d_dense_backend(groups, factors, prep$n, prep$q)$W
H_dense <- .gt_d_dense_hessian(kernel$curvature, W_dense, prep$n)
b_dense <- as.vector(crossprod(W_dense, kernel$gradient))
W_sparse <- .gt_d_sparse_backend(groups, factors, prep$n, prep$q)$W
H_sparse <- .gt_d_sparse_hessian(kernel$curvature, W_sparse, prep$n)
b_sparse <- as.numeric(Matrix::crossprod(W_sparse, kernel$gradient))

# A wrong factor of the #14 shape: a valid factor of some OTHER matrix.
wrong_dense <- chol({ o <- H_dense; o[1L, 1L] <- o[1L, 1L] * 1.09; o })
step_dense <- backsolve(wrong_dense, forwardsolve(t(wrong_dense), b_dense))
wrong_sparse <- .gt_d_sparse_factor({ o <- H_sparse; o[1L, 1L] <- o[1L, 1L] * 1.09; o })$factor
step_sparse <- as.numeric(Matrix::solve(wrong_sparse, b_sparse, system = "A"))

injected <- function(H, b, x, factor, reason) {
  check <- .gt_d_solve_check(H, b, x)
  function(parameters, prep, groups, setup, control, details = FALSE, ...) {
    if (!details) return(1e100)
    c(list(valid = FALSE, reason = reason), check[.GT_D_SOLVE_DETAIL],
      list(specimen = list(hessian = H, right_hand_side = b, step = x, factor = factor)))
  }
}
refuse <- function(evaluator) tryCatch(
  .gt_fit_discrete(case$data, case$outcomes, case$design, case$families, control = case$control,
                   .laplace = evaluator), error = function(e) conditionMessage(e))

written_after <- function(expr) {
  before <- list.files(directory, full.names = TRUE)
  force(expr)
  setdiff(list.files(directory, full.names = TRUE), before)
}

# ---- dense: the stored factor is wrong, a fresh one here is right -----------
message <- NULL
files <- written_after(message <- refuse(injected(H_dense, b_dense, step_dense, wrong_dense,
                                                  "dense_newton_solve_invalid")))
ok(grepl("reason=dense_newton_solve_invalid", message, fixed = TRUE), "the dense refusal names its reason")
ok(length(files) == 1L, "the dense refusal wrote one specimen")
dense_result <- gt_replay_specimen(files[[1L]])
dense_path <- files[[1L]]
ok(isTRUE(dense_result$replayable), "the dense specimen carries a replayable operation")
ok(isTRUE(dense_result$original_reproduces_record),
   "the stored step's backward error reproduces the recorded measurement")
ok(identical(dense_result$original_step$valid, FALSE), "the stored step still fails the stored system")
ok(identical(dense_result$original_factor_here$valid, FALSE), "the stored wrong factor still fails here")
ok(identical(dense_result$fresh_factor_here$valid, TRUE), "a fresh dense factorization here is valid")
ok(grepl("stored factor: fails", dense_result$verdict, fixed = TRUE) &&
     grepl("fresh factor: passes", dense_result$verdict, fixed = TRUE),
   "the verdict states the observed factor checks")
printed <- capture.output(gt_print_specimen_replay(dense_result))
ok(any(grepl("verdict:", printed, fixed = TRUE)) && any(grepl("1. original step", printed, fixed = TRUE)),
   "the printed replay reports the three questions and the verdict")

# ---- sparse: the same, on sparse storage and a CHOLMOD factor ---------------
files <- written_after(message <- refuse(injected(H_sparse, b_sparse, step_sparse, wrong_sparse,
                                                  "sparse_newton_solve_invalid")))
ok(length(files) == 1L, "the sparse refusal wrote one specimen")
sparse_result <- gt_replay_specimen(files[[1L]])
ok(isTRUE(sparse_result$replayable), "the sparse specimen carries a replayable operation")
ok(isTRUE(sparse_result$original_reproduces_record),
   "the stored sparse step's backward error reproduces the recorded measurement")
ok(identical(sparse_result$original_factor_here$valid, FALSE), "the stored wrong CHOLMOD factor still fails here")
ok(identical(sparse_result$fresh_factor_here$valid, TRUE), "a fresh sparse factorization here is valid")
ok(grepl("stored factor: fails", sparse_result$verdict, fixed = TRUE) &&
     grepl("fresh factor: passes", sparse_result$verdict, fixed = TRUE),
   "the sparse verdict states the observed factor checks")

# ---- an unavailable fresh factor is an observation, not a diagnosis --------
# This fixture is indefinite, but the replay only observes factorization
# failure; the same observation can arise from a numerical-library failure.
indefinite <- H_dense
indefinite[1L, 1L] <- -abs(indefinite[1L, 1L]) - 1
files <- written_after(message <- refuse(injected(indefinite, b_dense, step_dense, wrong_dense,
                                                  "dense_newton_solve_invalid")))
indefinite_result <- gt_replay_specimen(files[[1L]])
ok(isFALSE(indefinite_result$fresh_factor_available) || isFALSE(indefinite_result$fresh_factor_here$valid),
   "a fresh factorization of an indefinite stored matrix fails here too")
ok(grepl("fresh factor: unavailable", indefinite_result$verdict, fixed = TRUE),
   "the verdict reports that this host returned no fresh factor")

# Repeat a factorization defect on a healthy SPD system. Replaying on the same
# affected numerical library is not evidence that the matrix is defective or
# that the failure will occur on other hosts.
ok(min(eigen(H_dense, symmetric = TRUE, only.values = TRUE)$values) > 0 &&
     max(abs(crossprod(chol(H_dense)) - H_dense)) < 1e-12,
   "the repeated-fault fixture has a healthy positive-definite matrix")
fresh_factor <- gt_specimen_fresh_factor
gt_specimen_fresh_factor <- function(H) wrong_dense
repeated <- gt_replay_specimen(dense_path)
gt_specimen_fresh_factor <- function(H) NULL
unavailable <- gt_replay_specimen(dense_path)
gt_specimen_fresh_factor <- fresh_factor
ok(isFALSE(repeated$original_factor_here$valid) && isFALSE(repeated$fresh_factor_here$valid),
   "the injected recurring fault fails both factor checks")
ok(grepl("stored factor: fails", repeated$verdict, fixed = TRUE) &&
     grepl("fresh factor: fails", repeated$verdict, fixed = TRUE),
   "a recurring fault reports both observed failures")
ok(grepl("fresh factor: unavailable", unavailable$verdict, fixed = TRUE),
   "a healthy matrix with no returned factor reports unavailable")
for (result in list(dense_result, sparse_result, indefinite_result, repeated, unavailable))
  ok(!grepl("matrix is the problem|matrix, not|was at fault|failure is portable", result$verdict),
     "a replay verdict never asserts an unestablished matrix, host or portability cause")

# ---- measurement matching respects both precision and validity ------------
# With H = I, b = (1, 1), x = (1 + delta, 1), the backward error is
# delta / (2 + delta), rather than a quantity produced by the matcher itself.
measurement <- function(recorded, delta = 0, recorded_bound = .gt_d_solve_bound(2L)) {
  specimen <- readRDS(dense_path)
  specimen$record$solve_backward_error <- recorded
  specimen$record$solve_validity_bound <- recorded_bound
  specimen$record$random_dimension <- 2L
  specimen$specimen <- list(hessian = diag(2), right_hand_side = c(1, 1),
                            step = c(1 + delta, 1), factor = diag(2))
  path <- tempfile("measurement-", tmpdir = directory, fileext = ".rds")
  saveRDS(specimen, path)
  gt_replay_specimen(path)
}
ok(isFALSE(measurement(1e-8)$original_reproduces_record),
   "a recorded failure and a valid replay never reproduce the same record")
ok(isFALSE(measurement(0, 1e-8)$original_reproduces_record),
   "a recorded pass and a failed replay never reproduce the same record")
bound <- .gt_d_solve_bound(2L)
near <- measurement(bound * 1.001, 128 * .Machine$double.eps)
ok(isTRUE(near$original_step$valid) && isFALSE(near$original_reproduces_record),
   "opposite validity decisions still disagree within the roundoff tolerance")
near <- measurement(bound * .999, 129 * .Machine$double.eps)
ok(isFALSE(near$original_step$valid) && isFALSE(near$original_reproduces_record),
   "the reverse threshold crossing still disagrees within the roundoff tolerance")
delta <- 2^-25
expected_error <- delta / (2 + delta)
ok(isTRUE(measurement(expected_error, delta)$original_reproduces_record),
   "an intact small-error failure reproduces its measurement")
comparison <- measurement(expected_error, delta)$original_record_comparison
ok(is.numeric(comparison$difference) && is.numeric(comparison$tolerance) &&
     comparison$difference <= comparison$tolerance && comparison$tolerance < expected_error / 100 &&
     isFALSE(comparison$recorded_valid) && isFALSE(comparison$replayed_valid),
   "the comparison retains useful precision and validity evidence")
ok(isTRUE(measurement(expected_error * (1 + 1e-9), delta)$original_reproduces_record),
   "rounding-scale relative differences in a failed measurement are tolerated")
ok(isFALSE(measurement(expected_error * 2, delta)$original_reproduces_record),
   "a materially different small-error failure does not match")
ok(isTRUE(measurement(0, 2 * .Machine$double.eps)$original_reproduces_record),
   "healthy errors differing by machine roundoff match")
ok(isFALSE(measurement(expected_error, delta, 2 * expected_error)$original_reproduces_record),
   "the recorded and replayed validity decisions use their respective bounds")
ok(is.na(measurement(expected_error, delta, NULL)$original_reproduces_record),
   "without a recorded bound, agreement of the validity decisions is unknown")
ok(is.na(measurement(NULL, delta)$original_reproduces_record),
   "without a recorded measurement, agreement is unknown")

# ---- a final-factor specimen is judged by the probes -------------------------
final <- function(parameters, prep, groups, setup, control, details = FALSE, ...) {
  if (!details) return(1e100)
  c(list(valid = FALSE, reason = "dense_final_factor_invalid",
         solve_backward_error = 0.05, solve_validity_bound = .gt_d_solve_bound(nrow(H_dense)),
         random_dimension = nrow(H_dense), probe_index = 1L),
    list(specimen = list(hessian = H_dense, factor = wrong_dense)))
}
files <- written_after(message <- refuse(final))
final_result <- gt_replay_specimen(files[[1L]])
final_path <- files[[1L]]
ok(identical(final_result$kind, "final_factor"), "a specimen without a right-hand side is a final-factor specimen")
ok(identical(final_result$original_factor_here$valid, FALSE) &&
     identical(final_result$original_factor_here$probe_index, 1L),
   "the stored wrong factor fails the first probe here")
ok(identical(final_result$fresh_factor_here$valid, TRUE), "a fresh factor passes both probes here")

# Missing evidence must neither masquerade as a passed factor nor prevent an
# independent fresh factorization from being tested.
missing <- readRDS(final_path)
missing$specimen$factor <- NULL
missing_path <- tempfile("missing-factor-", tmpdir = directory, fileext = ".rds")
saveRDS(missing, missing_path)
missing_factor <- gt_replay_specimen(missing_path)
ok(is.null(missing_factor$original_factor_here) &&
     isTRUE(missing_factor$fresh_factor_here$valid),
   "an absent stored factor does not prevent the independent fresh probe check")
ok(grepl("stored factor: unavailable", missing_factor$verdict, fixed = TRUE) &&
     grepl("fresh factor: passes", missing_factor$verdict, fixed = TRUE),
   "an absent stored factor is reported as unavailable")
missing <- readRDS(dense_path)
missing$specimen$step <- NULL
saveRDS(missing, missing_path)
missing_step <- gt_replay_specimen(missing_path)
ok(is.null(missing_step$original_step) &&
     identical(missing_step$factor_check, "stored right-hand side"),
   "a missing step leaves the recorded right-hand side usable for factor checks")
ok(grepl("stored step: unavailable", missing_step$verdict, fixed = TRUE),
   "a missing step is reported as unavailable")
missing <- readRDS(dense_path)
missing$specimen$right_hand_side <- NULL
saveRDS(missing, missing_path)
missing_rhs <- gt_replay_specimen(missing_path)
ok(is.null(missing_rhs$original_step) && identical(missing_rhs$factor_check, "fixed probes") &&
     isTRUE(missing_rhs$fresh_factor_here$valid),
   "without a stored right-hand side, independent factor probes are identified explicitly")

# ---- a non-convergence specimen has nothing to replay ------------------------
truncated <- tryCatch(.gt_fit_discrete(case$data, case$outcomes, case$design, case$families,
                                       control = utils::modifyList(case$control, list(inner_maxit = 1L))),
                      error = function(e) conditionMessage(e))
files <- list.files(directory, pattern = "start", full.names = TRUE)
newest <- files[[which.max(file.info(files)$mtime)]]
plain <- gt_replay_specimen(newest)
ok(isFALSE(plain$replayable), "a non-convergence specimen is reported as having no operation to replay")
ok(grepl("no operation to replay", plain$verdict, fixed = TRUE), "and says so in its verdict")
ok(is.numeric(plain$record$inner_iterations) && identical(plain$record$phase, "start"),
   "the non-convergence record still carries the iteration count and phase")

# ---- a foreign file is refused ----------------------------------------------
other <- file.path(directory, "other.rds")
saveRDS(list(schema = "something-else"), other)
ok(inherits(tryCatch(gt_replay_specimen(other), error = function(e) e), "error"),
   "a file that is not a specimen is refused, not interpreted")

if (fails) { cat("FAILURES: ", fails, "\n", sep = ""); quit(status = 1) }
cat("Specimen replay checks passed: dense and sparse specimens reproduce their recorded ",
    "measurement with matching validity decisions, stored and fresh factors are judged ",
    "separately without causal claims, and missing evidence is reported as such.\n",
    sep = "")
