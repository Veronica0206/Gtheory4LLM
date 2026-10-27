# Run from the project directory with Rscript tests/test_discrete_dense_roundoff.R.
#
# The dense conditional-mode search accepts a full Newton step that passes the
# bounded roundoff check the sparse search uses (.gt_d_roundoff_descent()),
# when the Armijo test is decided by the objective's rounding (issue #59):
#
#   * at two evaluations retained from the equivalence study's C13 fit, where
#     macOS's reference BLAS rounded the full step above the Armijo bound and
#     the search crawled to its budget, the dense solve converges in a few steps
#     and agrees with the sparse solve, on every platform;
#   * with each line-search objective raised by a rounding-sized amount, which
#     makes every platform reject that step, the search still converges, and it
#     does so through the safeguard;
#   * the safeguard relaxes neither the step budget nor the final tolerance,
#     and refuses a change beyond its function allowance.
source("load_functions.R")
source(file.path("validation-studies", "discrete-sparse-equivalence", "cases.R"))

fails <- 0L
ok <- function(condition, label) {
  if (!isTRUE(condition)) { fails <<- fails + 1L; cat("FAIL: ", label, "\n", sep = "") }
}
row <- EQ_CORE[EQ_CORE$case == "C13", ]
map <- .eq_parameter_map(row, EQ_GEOMETRY[[row$geometry]])
control <- .gt_d_control(.eq_control_for(row$covariance))
# The parameters as the macOS dense fit passed them to its evaluator, exactly
# (results-amendment-1/investigation/replay-dense-newton.R).
points <- list(
  evaluation_12 = c(-0x1.aef514fb8e9a9p-3, -0x1.f4c709db24bf1p-4, -0x1.d5240f0e0e077p-1,
                    -0x1.d5240f0e0e077p-1, -0x1.d5a7217ca594cp-1),
  evaluation_15 = c(-0x1.c7b81c6e599a2p-4, 0x1.26bb1bbb55516p+2, -0x1.4p+3, 0x1.61f67a585d03ap-1,
                    0x1.4p+2))
solve_at <- function(parameters, settings = control) {
  factors <- .gt_d_covariance_factors(parameters[-seq_along(map$prep$start)], map$setup)
  list(dense = .gt_d_dense_mode(parameters, map$prep,
                                .gt_d_dense_backend(map$groups, factors, map$prep$n, map$prep$q),
                                settings, details = TRUE),
       sparse = .gt_d_sparse_mode(parameters, map$prep,
                                  .gt_d_sparse_backend(map$groups, factors, map$prep$n, map$prep$q),
                                  settings, details = TRUE))
}

# ---- the retained C13 points ---------------------------------------------------------------
for (name in names(points)) {
  s <- solve_at(points[[name]])
  ok(isTRUE(s$dense$valid) && s$dense$inner_iterations <= 10L && s$dense$inner_gradient <= control$inner_tol &&
       is.integer(s$dense$inner_roundoff_steps),
     paste0(name, ": the dense solve converges within ten steps to the inner tolerance"))
  ok(isTRUE(s$sparse$valid) &&
       max(abs(s$dense$mode - s$sparse$mode)) <= 1e-8 &&
       abs(s$dense$nll - s$sparse$nll) <= 1e-12 * abs(s$sparse$nll),
     paste0(name, ": the dense and sparse solves agree"))
}

# ---- a rounding-sized raise of the line-search objective ---------------------------------
# The Newton loop's own objective comes from .gt_d_dense_evaluate(); each step
# it tries comes from .gt_d_response_kernel(). Raising only the latter by
# 1e-9 leaves the large early steps accepted, but the fifth step at evaluation
# 12 decreases the objective by about 1e-13, so its Armijo test now fails on
# every platform, as macOS's rounding made it fail.
kernel <- .gt_d_response_kernel
evaluate <- .gt_d_dense_evaluate
.gt_d_dense_evaluate <- function(eta, parameters, prep, backend) {
  response <- kernel(eta, parameters, prep)
  if (response$valid) response$H <- .gt_d_dense_hessian(response$curvature, backend$W, prep$n)
  response
}
raised <- function(raise) function(eta, parameters, prep) {
  response <- kernel(eta, parameters, prep)
  if (response$valid) response$nll <- response$nll + raise
  response
}
.gt_d_response_kernel <- raised(1e-9)
forced <- solve_at(points$evaluation_12)$dense
ok(isTRUE(forced$valid) && forced$inner_roundoff_steps >= 1L && forced$inner_iterations <= 10L &&
     forced$inner_gradient <= control$inner_tol,
   "a step rejected by rounding is accepted through the safeguard, and the solve converges")
budget <- control
budget$inner_maxit <- 4L
stopped <- solve_at(points$evaluation_12, budget)$dense
ok(!isTRUE(stopped$valid) && stopped$inner_gradient > control$inner_tol * 10,
   "the safeguard does not relax the step budget or the final tolerance")
.gt_d_response_kernel <- raised(2 * sqrt(.Machine$double.eps) * 1000)
refused <- solve_at(points$evaluation_12)$dense
ok(!isTRUE(refused$valid) && isTRUE(refused$inner_line_search_failed) && refused$inner_roundoff_steps == 0L,
   "a step whose objective rises beyond the function allowance is not accepted")
.gt_d_response_kernel <- kernel
.gt_d_dense_evaluate <- evaluate

if (fails) { cat("FAILURES: ", fails, "\n", sep = ""); quit(status = 1) }
cat("Dense roundoff safeguard verified: the retained C13 points converge and agree with the sparse solve; a ",
    "rounding-rejected step is accepted through the safeguard; the budget, the final tolerance and the ",
    "function allowance are kept.\n", sep = "")
