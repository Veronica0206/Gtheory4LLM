# Sparse conditional-mode solve and first-order Laplace evaluation.
#
# This is the dense solver's control flow carried out in sparse storage, at a
# fixed parameter vector. It is deliberately a line-for-line twin of
# .gt_d_dense_mode() rather than a second algorithm that reaches a similar
# answer: Newton step, line search, descent condition, acceptance test,
# iteration budget, final-mode recomputation and the relaxed final tolerance
# all stay in their original order, because the dense file records that order
# as a requirement and the frozen reference was produced by it.
#
# Only six operations differ, and each is a call into the sparse algebra that
# earlier steps already established:
#
#   dense                                sparse
#   W %*% u                              sparse product, same W convention
#   crossprod(W, gradient)               sparse crossprod
#   .gt_d_dense_hessian(...)             .gt_d_sparse_hessian(...)
#   chol(H)                              .gt_d_sparse_factor(H)
#   backsolve(R, forwardsolve(t(R), g))  .gt_d_sparse_solve(factor, g)
#   sum(log(diag(R)))                    .gt_d_sparse_logdet(factor) / 2
#
# The last line is the one to read twice. The dense value adds the log
# determinant of the Cholesky factor, which is half the log determinant of the
# Hessian; .gt_d_sparse_logdet() returns the whole one. Carrying the sparse
# value across unhalved would double the Laplace correction while leaving the
# mode, the gradient and every Hessian entry in exact agreement, so no test of
# the conditional problem would notice. The halving is asserted separately
# against the reference's own Laplace identity rather than left to this
# comment.
#
# Everything outside those six operations is shared code, not copied code: the
# likelihood, gradient and curvature all come from .gt_d_response_kernel(),
# which no backend touches.
#
# Binary and ordinal responses are the supported envelope, as in the Hessian
# assembly. Categorical blocks are refused here too, before any work is done,
# so the refusal names the dense backend instead of surfacing from underneath.

.gt_d_sparse_mode <- function(parameters, prep, backend, control, details = FALSE) {
  if (!inherits(backend, "gt_discrete_sparse_backend") ||
      !identical(c(backend$n, backend$q), c(prep$n, prep$q)))
    .gt_d_stop("Sparse mode inputs do not match the prepared response dimensions.")
  W <- backend$W
  if (!methods::is(W, "sparseMatrix") || nrow(W) != prep$n * prep$q || ncol(W) < 1L)
    .gt_d_stop("Invalid matrix supplied to the sparse mode solver.")
  stored <- tryCatch(methods::slot(W, "x"), error = function(e) NULL)
  if (!is.null(stored) && any(!is.finite(stored)))
    .gt_d_stop("Invalid matrix supplied to the sparse mode solver.")
  if (!is.numeric(parameters) || length(parameters) < length(prep$start) ||
      !is.list(control) || !is.numeric(control$inner_maxit) || length(control$inner_maxit) != 1L ||
      !is.finite(control$inner_maxit) || control$inner_maxit < 1 ||
      control$inner_maxit != floor(control$inner_maxit) ||
      !is.numeric(control$inner_tol) || length(control$inner_tol) != 1L ||
      !is.finite(control$inner_tol) || control$inner_tol <= 0)
    .gt_d_stop("Invalid parameters or controls supplied to the sparse mode solver.")
  families <- vapply(prep$blocks, `[[`, character(1), "family")
  if (any(families == "categorical"))
    .gt_d_stop("The sparse mode solver takes binary and ordinal responses; ",
               "the dense backend takes categorical ones.")
  baseline <- .gt_d_baseline(parameters, prep)
  u <- numeric(ncol(W))
  converged <- FALSE
  last_gradient <- Inf
  for (iter in seq_len(control$inner_maxit)) {
    eta <- baseline + matrix(as.numeric(W %*% u), prep$n, prep$q)
    response <- .gt_d_response_kernel(eta, parameters, prep)
    if (!response$valid) return(if (details) list(valid = FALSE) else 1e100)
    gradient <- as.numeric(Matrix::crossprod(W, response$gradient)) + u
    last_gradient <- max(abs(gradient))
    if (last_gradient <= control$inner_tol) { converged <- TRUE; break }
    H <- .gt_d_sparse_hessian(response$curvature, W, prep$n)
    # tryCatch, not a bare call: the dense solver treats a Hessian with no
    # Cholesky factor as an invalid evaluation and returns, and .gt_d_sparse_factor()
    # signals that condition by stopping. Letting the stop escape would turn a
    # value the dense path reports into an error the sparse path raises.
    factorization <- tryCatch(.gt_d_sparse_factor(H), error = function(e) NULL)
    if (is.null(factorization)) return(if (details) list(valid = FALSE) else 1e100)
    step <- .gt_d_sparse_solve(factorization, gradient)
    objective <- response$nll + sum(u^2) / 2
    descent <- sum(gradient * step)
    multiplier <- 1
    accepted <- FALSE
    for (line in seq_len(30L)) {
      candidate <- u - multiplier * step
      next_eta <- baseline + matrix(as.numeric(W %*% candidate), prep$n, prep$q)
      next_response <- .gt_d_response_kernel(next_eta, parameters, prep)
      if (next_response$valid && next_response$nll + sum(candidate^2) / 2 <=
          objective - 1e-4 * multiplier * descent + 1e-12) {
        u <- as.vector(candidate)
        accepted <- TRUE
        break
      }
      multiplier <- multiplier / 2
    }
    if (!accepted) break
  }
  # Always recompute at the final mode, including when max iterations was hit.
  eta <- baseline + matrix(as.numeric(W %*% u), prep$n, prep$q)
  response <- .gt_d_response_kernel(eta, parameters, prep)
  if (!response$valid) return(if (details) list(valid = FALSE) else 1e100)
  last_gradient <- max(abs(as.numeric(Matrix::crossprod(W, response$gradient)) + u))
  converged <- is.finite(last_gradient) && last_gradient <= control$inner_tol * 10
  H <- .gt_d_sparse_hessian(response$curvature, W, prep$n)
  factorization <- tryCatch(.gt_d_sparse_factor(H), error = function(e) NULL)
  if (is.null(factorization) || !converged) return(if (details)
    list(valid = FALSE, inner_converged = converged, inner_gradient = last_gradient) else 1e100)
  # Half the log determinant, matching sum(log(diag(R))) in the dense solver.
  value <- response$nll + sum(u^2) / 2 + .gt_d_sparse_logdet(factorization) / 2
  if (!details) return(value)
  list(valid = TRUE, nll = value, mode = u, eta = eta,
       conditional_nll = response$nll, inner_iterations = iter,
       inner_converged = converged, inner_gradient = last_gradient,
       random_dimension = length(u))
}
