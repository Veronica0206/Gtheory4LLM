# Run from the project directory with Rscript tests/test_discrete_sparse_validity.R.
#
# Regression for the SPARSE conditional-solve validity invariants, the twin of
# tests/test_discrete_solve_validity.R. The dense solver refuses a Newton step
# that does not solve its own system and a final factor that fails two fixed
# probes (issue #14). Before this file existed the sparse solver had neither
# check, so a CHOLMOD factor returned without error but wrong would have gone
# straight into the Laplace objective. Every check here is the same invariant,
# the same bound and the same refusal as on the dense side; only the storage
# form differs.
#
# Every corruption below is deterministic and injected through the private
# sparse helpers this solver calls by name, never through the RNG.
source(file.path("validation-studies", "discrete-sparse-reference", "cases.R"))
source(file.path("R", "discrete_sparse.R"))
source(file.path("R", "discrete_sparse_mode.R"))
suppressMessages(library(Matrix))

fails <- 0L
ok <- function(condition, label) {
  if (!isTRUE(condition)) { fails <<- fails + 1L; cat("FAIL: ", label, "\n", sep = "") }
}
close <- function(a, b, tol = 1e-12) isTRUE(max(abs(a - b)) <= tol)

prepare <- function(case) {
  control <- .gt_d_control(case$control)
  prep <- .gt_d_prepare(case$data, case$outcomes, case$families)
  groups <- lapply(case$design$term_members, function(m) .gt_d_group(case$data, m))
  setup <- .gt_d_covariance_setup(groups, prep$q, case$covariance, control, prep$dimensions)
  parameters <- c(prep$start + case$offset, setup$start * case$scale)
  factors <- .gt_d_covariance_factors(parameters[-seq_along(prep$start)], setup)
  list(parameters = parameters, prep = prep, control = control, groups = groups,
       setup = setup, factors = factors,
       dense_backend = .gt_d_dense_backend(groups, factors, prep$n, prep$q),
       sparse_backend = .gt_d_sparse_backend(groups, factors, prep$n, prep$q))
}
# A crossed binary case: two sources, so the fill-reducing permutation is not
# the identity and the probe solves genuinely pass through it.
case <- cases[[which(vapply(cases, function(x) identical(x$key, "binary_probit_crossed"), logical(1)))]]
at <- prepare(case)

# ---- the invariant applies to sparse storage without densifying -------------
eta0 <- .gt_d_baseline(at$parameters, at$prep)
kernel <- .gt_d_response_kernel(eta0, at$parameters, at$prep)
ok(isTRUE(kernel$valid), "the response kernel is valid at the baseline")
W <- at$sparse_backend$W
H <- .gt_d_sparse_hessian(kernel$curvature, W, at$prep$n)
ok(methods::is(H, "sparseMatrix"), "the conditional Hessian under test is sparse")
b <- as.numeric(Matrix::crossprod(W, kernel$gradient))
factorization <- .gt_d_sparse_factor(H)
x <- .gt_d_sparse_solve(factorization, b)

sparse_check <- .gt_d_solve_check(H, b, x)
dense_check <- .gt_d_solve_check(as.matrix(H), b, x)
ok(isTRUE(sparse_check$valid), "a healthy sparse solve passes the invariant")
ok(sparse_check$solve_backward_error >= 0 &&
     sparse_check$solve_backward_error <= 4 * .Machine$double.eps,
   "a healthy sparse solve is at machine precision")
ok(identical(sparse_check$solve_validity_bound, dense_check$solve_validity_bound),
   "the sparse check applies the dense bound, 32 * random_dimension * eps")
ok(identical(sparse_check$random_dimension, ncol(W)),
   "the sparse check reports the random dimension")
ok(abs(sparse_check$solve_backward_error - dense_check$solve_backward_error) <= 1e-14,
   "the backward error agrees with the same quantity on the densified matrix")
# Computed against an independent hand evaluation of the definition.
manual <- max(abs(as.numeric(H %*% x) - b)) /
  (max(Matrix::rowSums(abs(H))) * max(abs(x)) + max(abs(b)))
ok(close(sparse_check$solve_backward_error, manual),
   "the sparse backward error matches the definition computed independently")

# ---- deterministic corruption of the step ------------------------------------
for (scale in c(1e-6, 1e-3, 1e-1)) {
  bad <- x
  bad[[1L]] <- bad[[1L]] + scale
  ok(!isTRUE(.gt_d_solve_check(H, b, bad)$valid),
     paste0("sparse step perturbed by ", scale, " is refused"))
}
tiny <- x * (1 + 4 * .Machine$double.eps)
ok(isTRUE(.gt_d_solve_check(H, b, tiny)$valid),
   "sparse step perturbed at rounding level is accepted")

# ---- deterministic corruption of the factor ----------------------------------
# The #14 shape exactly: a factor object that is a valid Cholesky factor of some
# OTHER matrix, returned without any error.
ok(.gt_d_sparse_final_factor_valid(H, factorization),
   "an honest sparse factor passes the probe check")
other <- H
other[1L, 1L] <- other[1L, 1L] * 1.09
wrong <- .gt_d_sparse_factor(other)
ok(!.gt_d_sparse_final_factor_valid(H, wrong),
   "a factor of a diagonally perturbed matrix is refused")
ok(max(abs(as.matrix(other) - as.matrix(H))) / max(abs(as.matrix(H))) > 1e-6,
   "the perturbation genuinely changes the matrix")
probe_bad <- .gt_d_sparse_final_factor_check(H, wrong)
ok(identical(probe_bad$valid, FALSE), "the probe check refuses the wrong factor")
ok(identical(probe_bad$probe_index, 1L), "the probe check names which probe failed")
ok(probe_bad$solve_backward_error > probe_bad$solve_validity_bound,
   "the refusal reports a backward error above its bound")
off <- H
i <- 1L; j <- 2L
off[i, j] <- off[i, j] + 0.05; off[j, i] <- off[j, i] + 0.05
ok(!.gt_d_sparse_final_factor_valid(H, .gt_d_sparse_factor(off)),
   "a factor of an off-diagonally perturbed matrix is refused")
ok(is.na(.gt_d_sparse_final_factor_check(H, factorization)$probe_index),
   "a passing factor names no failing probe")
ok(identical(.gt_d_sparse_final_factor_check(H, factorization)$solve_validity_bound,
             .gt_d_final_factor_check(as.matrix(H), chol(as.matrix(H)))$solve_validity_bound),
   "the sparse probe check applies the dense bound")

# ---- the two reasons are distinguishable through the mode solver -------------
honest <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control, details = TRUE)
ok(isTRUE(honest$valid), "the honest sparse mode solve is valid")
reference <- .gt_d_dense_mode(at$parameters, at$prep, at$dense_backend, at$control, details = TRUE)
ok(isTRUE(reference$valid) && abs(honest$nll - reference$nll) <= 1e-10,
   "with the checks in place the sparse and dense marginal values still agree")

# Newton-step refusal: shadow the private solve so the step no longer solves
# the system it was computed from. The solver resolves the helper by name.
honest_solve <- .gt_d_sparse_solve
.gt_d_sparse_solve <- function(factorization, b) {
  step <- honest_solve(factorization, b)
  step[[1L]] <- step[[1L]] + 1e-3
  step
}
first <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control, details = TRUE)
scalar <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control)
.gt_d_sparse_solve <- honest_solve
ok(identical(first$valid, FALSE), "a corrupted step invalidates the sparse mode solve")
ok(identical(first$reason, "sparse_newton_solve_invalid"),
   "the Newton-step failure carries its own reason")
ok(is.numeric(first$solve_backward_error) && first$solve_backward_error > first$solve_validity_bound,
   "the Newton-step refusal retains the measurement and the bound")
ok(identical(first$random_dimension, ncol(W)), "the Newton-step refusal retains the dimension")
ok(identical(scalar, 1e100), "the scalar form returns the penalty, never a value")

# Final-factor refusal: corrupt exactly the LAST factorization of one
# evaluation, so every Newton step is honest and only the factor that feeds the
# log determinant is wrong. The count is taken from an honest run rather than
# assumed.
honest_factor <- .gt_d_sparse_factor
factor_calls <- 0L
.gt_d_sparse_factor <- function(H, permute = TRUE) {
  factor_calls <<- factor_calls + 1L
  honest_factor(H, permute)
}
invisible(.gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control, details = TRUE))
final_call <- factor_calls
ok(final_call >= 2L, "the honest solve factorizes at least twice, so the last one is distinct")
factor_calls <- 0L
.gt_d_sparse_factor <- function(H, permute = TRUE) {
  factor_calls <<- factor_calls + 1L
  if (factor_calls == final_call) {
    other <- H
    other[1L, 1L] <- other[1L, 1L] * 1.09
    return(honest_factor(other, permute))
  }
  honest_factor(H, permute)
}
last <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control, details = TRUE)
.gt_d_sparse_factor <- honest_factor
ok(identical(last$valid, FALSE), "a corrupted final factor invalidates the sparse mode solve")
ok(identical(last$reason, "sparse_final_factor_invalid"),
   "the final-factor failure carries its own reason")
ok(identical(last$probe_index, 1L), "the final-factor refusal names the failing probe")
ok(isTRUE(last$inner_converged), "the final-factor refusal happens after an otherwise converged mode")

# ---- end to end through the private seam: never accepted ---------------------
# The dense end-to-end test corrupts chol() after two calls; here the sparse
# factorization is corrupted after two calls in the same way, and the fit is
# run through the private evaluator seam exactly as the fitted sparse study
# runs it. Either an explicit refusal or a completed, NOT accepted fit is
# containment; an accepted fit built on a wrong factor is the one outcome that
# must never happen.
d <- expand.grid(item = seq_len(10), rater = seq_len(3), rep = seq_len(3))
d <- d[order(d$item, d$rater, d$rep), ]
ones <- c(2L, 3L, 4L, 5L, 6L, 7L, 3L, 4L, 5L, 6L)
d$y <- as.integer(ave(seq_len(nrow(d)), d$item, FUN = seq_along) <= ones[d$item])
rownames(d) <- NULL
design <- list(object = "item", facets = "rater",
               term_members = list(item = "item", rater = "rater"))
family <- list(list(family = "binary", link = "probit", levels = c("0", "1")))
control_fit <- .gt_fit_discrete(d, "y", design, family, control = list(maxit = 60L),
                                .laplace = .gt_d_sparse_evaluator(),
                                .engine = "sparse_marginal_laplace")
ok(isTRUE(control_fit$numerically_accepted), "the uncorrupted sparse control fit is accepted")
# A fit produced through the seam says which backend produced it, in the
# public field, and keeps the dense label for the dense backend.
ok(identical(control_fit$engine, "sparse_joint_discrete_laplace"),
   "a sparse-backed fit describes itself as sparse in its public engine label")
ok(identical(control_fit$diagnostics$marginal_backend, "sparse_marginal_laplace"),
   "the private backend record agrees with the public label")
dense_fit <- .gt_fit_discrete(d, "y", design, family, control = list(maxit = 60L))
ok(identical(dense_fit$engine, "dense_joint_discrete_laplace"),
   "the dense engine label is unchanged")
ok(is.list(control_fit$diagnostics$evaluations) &&
     control_fit$diagnostics$evaluations$count > 0L,
   "a sparse-backed fit records its evaluation log")
factor_calls <- 0L
.gt_d_sparse_factor <- function(H, permute = TRUE) {
  factor_calls <<- factor_calls + 1L
  if (factor_calls > 2L) {
    other <- H
    other[1L, 1L] <- other[1L, 1L] * 1.09
    return(honest_factor(other, permute))
  }
  honest_factor(H, permute)
}
corrupted <- tryCatch(.gt_fit_discrete(d, "y", design, family, control = list(maxit = 60L),
                                       .laplace = .gt_d_sparse_evaluator(),
                                       .engine = "sparse_marginal_laplace"),
                      error = function(e) structure(list(error = conditionMessage(e)),
                                                    class = "refused"))
.gt_d_sparse_factor <- honest_factor
accepted <- !inherits(corrupted, "refused") && isTRUE(corrupted$numerically_accepted)
ok(!accepted, "a sparse fit built on a malformed factor is never numerically accepted")
if (inherits(corrupted, "refused"))
  ok(grepl("reason=sparse_", corrupted$error, fixed = TRUE),
     "a refusal at the starting values names the sparse invariant that failed")
if (!inherits(corrupted, "refused"))
  ok(length(corrupted$diagnostics$acceptance_failures) > 0L,
     "the refusal is recorded in acceptance_failures")

if (fails) { cat("FAILURES: ", fails, "\n", sep = ""); quit(status = 1) }
cat("Sparse solve-validity checks passed: the dense invariant and bound on sparse storage, ",
    "step and factor corruption, both reason codes through the mode solver, and ",
    "end-to-end refusal through the private evaluator seam.\n", sep = "")
