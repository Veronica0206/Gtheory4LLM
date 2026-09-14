# Dense conditional-mode solve and first-order Laplace evaluation.
# Keep Newton, line search, final-mode checks, and arithmetic in their original order.

.gt_d_dense_mode <- function(parameters, prep, backend, control, details = FALSE) {
  if (!inherits(backend, "gt_discrete_dense_backend") ||
      !identical(c(backend$n, backend$q), c(prep$n, prep$q)))
    .gt_d_stop("Dense mode inputs do not match the prepared response dimensions.")
  W <- backend$W
  if (!is.matrix(W) || !is.numeric(W) || nrow(W) != prep$n * prep$q ||
      ncol(W) < 1L || any(!is.finite(W)))
    .gt_d_stop("Invalid matrix supplied to the dense mode solver.")
  if (!is.numeric(parameters) || length(parameters) < length(prep$start) ||
      !is.list(control) || !is.numeric(control$inner_maxit) || length(control$inner_maxit) != 1L ||
      !is.finite(control$inner_maxit) || control$inner_maxit < 1 ||
      control$inner_maxit != floor(control$inner_maxit) ||
      !is.numeric(control$inner_tol) || length(control$inner_tol) != 1L ||
      !is.finite(control$inner_tol) || control$inner_tol <= 0)
    .gt_d_stop("Invalid parameters or controls supplied to the dense mode solver.")
  baseline <- .gt_d_baseline(parameters, prep)
  u <- numeric(ncol(W))
  converged <- FALSE
  last_gradient <- Inf
  for (iter in seq_len(control$inner_maxit)) {
    eta <- baseline + matrix(W %*% u, prep$n, prep$q)
    response <- .gt_d_dense_evaluate(eta, parameters, prep, backend)
    if (!response$valid) return(if (details) list(valid = FALSE) else 1e100)
    gradient <- as.vector(crossprod(W, response$gradient)) + u
    last_gradient <- max(abs(gradient))
    if (last_gradient <= control$inner_tol) { converged <- TRUE; break }
    R <- tryCatch(chol(response$H), error = function(e) NULL)
    if (is.null(R)) return(if (details) list(valid = FALSE) else 1e100)
    step <- backsolve(R, forwardsolve(t(R), gradient))
    objective <- response$nll + sum(u^2) / 2
    descent <- sum(gradient * step)
    multiplier <- 1
    accepted <- FALSE
    for (line in seq_len(30L)) {
      candidate <- u - multiplier * step
      next_eta <- baseline + matrix(W %*% candidate, prep$n, prep$q)
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
  eta <- baseline + matrix(W %*% u, prep$n, prep$q)
  response <- .gt_d_dense_evaluate(eta, parameters, prep, backend)
  if (!response$valid) return(if (details) list(valid = FALSE) else 1e100)
  last_gradient <- max(abs(as.vector(crossprod(W, response$gradient)) + u))
  converged <- is.finite(last_gradient) && last_gradient <= control$inner_tol * 10
  R <- tryCatch(chol(response$H), error = function(e) NULL)
  if (is.null(R) || !converged) return(if (details)
    list(valid = FALSE, inner_converged = converged, inner_gradient = last_gradient) else 1e100)
  value <- response$nll + sum(u^2) / 2 + sum(log(diag(R)))
  if (!details) return(value)
  list(valid = TRUE, nll = value, mode = u, eta = eta,
       conditional_nll = response$nll, inner_iterations = iter,
       inner_converged = converged, inner_gradient = last_gradient,
       random_dimension = length(u))
}

