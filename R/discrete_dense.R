# Dense matrix operations for the private discrete backend contract.
# Inputs come from response preparation and covariance setup. No fitted state,
# mode cache, source selection, or optimizer decisions live in this object.

.gt_d_dense_backend <- function(groups, factors, n, q) {
  dimensions <- c(n, q)
  if (!is.numeric(dimensions) || length(dimensions) != 2L ||
      any(!is.finite(dimensions)) || any(dimensions < 1) ||
      any(dimensions != floor(dimensions)) || !is.list(groups) ||
      !length(groups) || !is.list(factors) || length(factors) != length(groups))
    .gt_d_stop("Invalid dense backend dimensions or source factors.")
  n <- as.integer(n)
  q <- as.integer(q)
  for (s in seq_along(groups)) {
    group <- groups[[s]]
    L <- factors[[s]]
    if (!is.list(group) || !is.integer(group$nlevels) || length(group$nlevels) != 1L ||
        !is.finite(group$nlevels) || group$nlevels < 1 || group$nlevels != floor(group$nlevels) ||
        !is.numeric(group$index) || length(group$index) != n || anyNA(group$index) ||
        any(!is.finite(group$index)) || any(group$index != floor(group$index)) ||
        any(group$index < 1 | group$index > group$nlevels) ||
        !is.matrix(L) || !is.numeric(L) || !identical(dim(L), c(as.integer(q), as.integer(q))) ||
        any(!is.finite(L)))
      .gt_d_stop("Invalid dense backend group indices or covariance factor.")
  }
  structure(list(W = .gt_d_W(groups, factors, n, q), n = n, q = q),
            class = "gt_discrete_dense_backend")
}

.gt_d_W <- function(groups, factors, n, q) {
  dimension <- sum(vapply(groups, `[[`, integer(1), "nlevels")) * q
  W <- matrix(0, n * q, dimension)
  offset <- 0L
  for (s in seq_along(groups)) {
    group <- groups[[s]]
    L <- factors[[s]]
    for (a in seq_len(q)) for (b in seq_len(q)) if (L[a, b] != 0)
      W[cbind((a - 1L) * n + seq_len(n), offset + (b - 1L) * group$nlevels + group$index)] <- L[a, b]
    offset <- offset + q * group$nlevels
  }
  W
}

.gt_d_dense_hessian <- function(curvature, W, n) {
  H <- diag(ncol(W))
  for (curv in curvature) {
    if (!is.null(curv$diagonal)) {
      row <- (curv$dims - 1L) * n + seq_len(n)
      A <- W[row, , drop = FALSE]
      H <- H + crossprod(A, A * pmax(0, curv$diagonal))
    } else {
      p <- curv$probability
      for (a in seq_along(curv$dims)) {
        ia <- (curv$dims[[a]] - 1L) * n + seq_len(n)
        A <- W[ia, , drop = FALSE]
        for (bb in seq_along(curv$dims)) {
          ib <- (curv$dims[[bb]] - 1L) * n + seq_len(n)
          B <- W[ib, , drop = FALSE]
          weight <- (as.integer(a == bb) * p[, a]) - p[, a] * p[, bb]
          H <- H + crossprod(A, B * weight)
        }
      }
    }
  }
  (H + t(H)) / 2
}

# Solve-validity invariant for the dense conditional solve.
#
# A native Cholesky can return successfully and still hand back a factor that is
# not a factor of the matrix it was given. Issue #14 is a captured instance: on
# one hosted runner base chol() reported success while its factor missed R'R = H
# by about 9%, its step failed to solve the system by 0.387, and its log
# determinant contradicted the eigenvalues of that same matrix by 0.450. The
# matrix was not pathological -- the identical bytes factor correctly elsewhere.
#
# The package therefore cannot treat a returned factor as valid because no error
# was raised. What the algorithm actually depends on is that the proposed Newton
# step solves the stated system, so that is what is checked, rather than a
# property of the factor.
#
# This is a detection invariant, not a repair. Nothing here retries, perturbs,
# regularizes, widens a tolerance, adds iterations, or substitutes another
# factorization. A violation makes the dense conditional solve numerically
# unavailable and is propagated as such.

# Normwise relative backward error (Rigal-Gaches): the smallest relative
# perturbation of (H, b) for which x is the exact solution.
#
#   eta = ||H x - b||_inf / ( ||H||_inf ||x||_inf + ||b||_inf )
#
# Costs one matrix-vector product and one row-sum norm, both O(random_dimension^2),
# against the O(random_dimension^3) factorization already performed at the same
# iteration.
.gt_d_backward_error <- function(H, b, x) {
  residual <- max(abs(as.numeric(H %*% x) - b))
  denominator <- norm(H, "I") * max(abs(x)) + max(abs(b))
  # Any non-finite quantity anywhere in the ratio is a failure, never a pass.
  if (!is.finite(residual) || !is.finite(denominator)) return(Inf)
  # An exactly zero residual on an exactly zero problem is exact, not undefined.
  # A zero denominator with a non-zero residual is a failure.
  if (residual == 0) return(0)
  if (denominator == 0) return(Inf)
  residual / denominator
}

# eta <= 32 * random_dimension * eps.
#
# The linear growth in the dimension is the standard backward-error bound for a
# symmetric positive definite solve, whose growth factor is bounded; the constant
# is fixed from measurement with margin. Across 53,770 healthy dense conditional
# solves spanning binary, ordinal and categorical responses, random dimension 11
# to 85, condition number to 2.0e5, and saturating intercepts, the worst observed
# value was 9.66e-16 = 4.35 eps = 0.116 * random_dimension * eps. The captured
# issue #14 specimen measured 4.83e-02 on this same quantity, which is 2.17e14
# eps: the two populations are separated by about 5e13, so the constant is not
# delicate.
#
# This is deliberately NOT the 1e-8 figure used by the diagnostic artifact
# retention trigger in the validation suite. That is an artifact-capture
# heuristic; this is a scale-aware numerical-validity condition.
.GT_D_SOLVE_VALIDITY_CONSTANT <- 32

.gt_d_solve_bound <- function(random_dimension)
  .GT_D_SOLVE_VALIDITY_CONSTANT * random_dimension * .Machine$double.eps

.gt_d_solve_valid <- function(H, b, x) {
  eta <- .gt_d_backward_error(H, b, x)
  is.finite(eta) && eta <= .gt_d_solve_bound(nrow(H))
}

# The final-mode factor feeds a log determinant, not a solve, so the Newton
# check above does not cover it -- and in the captured specimen that log
# determinant is exactly where the wrong number entered the Laplace objective.
#
# It is validated with fixed deterministic probes instead. The converged
# gradient is deliberately NOT used as a right-hand side: at convergence it is
# approximately zero, which makes the backward-error ratio numerically delicate
# in precisely the situation the check has to be trustworthy.
#
# Two probes rather than one. A malformed factor can in principle act correctly
# on a single fixed vector while being wrong elsewhere; two non-collinear
# directions do not prove R'R = H, but they cost only a few O(d^2) operations
# and close that blind spot far more cheaply than the O(d^3) reconstruction,
# which stays out of the objective loop and remains in validation.
#
# Both probes are already infinity-normalized. At random dimension one they
# coincide, which is harmless: every pair of vectors is collinear there.
.gt_d_solve_probes <- function(random_dimension)
  list(rep(1, random_dimension), rep(c(1, -1), length.out = random_dimension))

.gt_d_final_factor_valid <- function(H, R) {
  for (probe in .gt_d_solve_probes(nrow(H))) {
    y <- tryCatch(backsolve(R, forwardsolve(t(R), probe)), error = function(e) NULL)
    if (is.null(y) || !.gt_d_solve_valid(H, probe, y)) return(FALSE)
  }
  TRUE
}

.gt_d_dense_evaluate <- function(eta, parameters, prep, backend) {
  response <- .gt_d_response_kernel(eta, parameters, prep)
  if (response$valid)
    response$H <- .gt_d_dense_hessian(response$curvature, backend$W, prep$n)
  response
}

# Compatibility adapter for internal callers that previously requested W-based
# curvature through the response function. New mode code uses the split kernel.
.gt_d_response <- function(eta, parameters, prep, W = NULL) {
  response <- .gt_d_response_kernel(eta, parameters, prep)
  if (response$valid && !is.null(W)) {
    if (!is.matrix(W) || !is.numeric(W) || nrow(W) != prep$n * prep$q || any(!is.finite(W)))
      .gt_d_stop("Dense response matrix does not match the prepared response dimensions.")
    response$H <- .gt_d_dense_hessian(response$curvature, W, prep$n)
  }
  response
}
