# Dense conditional-mode solve and first-order Laplace evaluation.
# Keep Newton, line search, final-mode checks, and arithmetic in their original order.
#
# Near the conditional mode a Newton step's decrease can fall below the
# rounding of the objective, so whether the step passes the Armijo test is
# decided by the last bits of the objective, which differ between BLAS builds.
# A full step that fails the test can therefore pass the bounded derivative
# check below, the same check the sparse solver uses. Without it, such a step
# was halved repeatedly and the solve could stop at its iteration budget just
# short of the final tolerance, an unusable evaluation whose penalty then
# entered the outer finite-difference gradient (issue #59). The final score
# tolerance, the iteration budget and the solve and factor checks are
# unchanged: search-step acceptance does not certify convergence.

.gt_d_roundoff_descent <- function(objective, next_objective, descent, gradient, next_gradient,
                                  step = NULL, mode_tolerance = NULL) {
  if (any(!is.finite(c(objective, next_objective, descent, gradient, next_gradient)))) return(FALSE)
  slack <- 32 * .Machine$double.eps * max(1, abs(objective))
  if (descent <= 0 || length(next_gradient) != length(gradient) ||
      max(abs(next_gradient)) >= max(abs(gradient))) return(FALSE)
  if (descent <= slack && abs(next_objective - objective) <= slack) return(TRUE)
  # Summed log probabilities can lose more than a few ulps even when the
  # derivative still resolves the conditional minimum. Within a bounded
  # function-evaluation allowance, use the approximate-Wolfe directional
  # inequalities (Hager and Zhang, 2005, section 4, doi:10.1137/030601880).
  # This is a limited full-step safeguard, not their complete line search.
  # sqrt(eps) is a heuristic function-evaluation allowance, NOT an error bound
  # or a score tolerance. It bounds both the predicted decrement and function
  # difference. This wider branch requires an already stationary candidate
  # under the unchanged final mode tolerance.
  # Final stationarity, solve validity and factor validity are still required.
  allowance <- sqrt(.Machine$double.eps) * max(1, abs(objective))
  if (descent > allowance ||
      !is.numeric(step) || length(step) != length(gradient) || any(!is.finite(step)) ||
      !is.numeric(mode_tolerance) || length(mode_tolerance) != 1L ||
      !is.finite(mode_tolerance) || mode_tolerance <= 0 ||
      max(abs(next_gradient)) > mode_tolerance ||
      abs(next_objective - objective) > allowance)
    return(FALSE)
  initial_slope <- -descent
  next_slope <- -sum(next_gradient * step)
  is.finite(next_slope) && next_slope >= 0.9 * initial_slope &&
    next_slope <= (2 * 1e-4 - 1) * initial_slope
}

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
  accepted <- TRUE
  last_gradient <- Inf
  roundoff_steps <- 0L
  for (iter in seq_len(control$inner_maxit)) {
    eta <- baseline + matrix(W %*% u, prep$n, prep$q)
    response <- .gt_d_dense_evaluate(eta, parameters, prep, backend)
    if (!response$valid) return(if (details) list(valid = FALSE, inner_iterations = iter) else 1e100)
    gradient <- as.vector(crossprod(W, response$gradient)) + u
    last_gradient <- max(abs(gradient))
    if (last_gradient <= control$inner_tol) { converged <- TRUE; break }
    R <- tryCatch(chol(response$H), error = function(e) NULL)
    if (is.null(R)) return(if (details) list(valid = FALSE) else 1e100)
    step <- backsolve(R, forwardsolve(t(R), gradient))
    # Checked here, immediately after the solve and before the line search
    # consumes the step. A native factorization can report success and still
    # return a factor that does not solve its own system; see the helper in
    # discrete_dense.R and issue #14. There is no rescue: a violated invariant
    # makes the dense conditional solve unavailable.
    solve_check <- .gt_d_solve_check(response$H, gradient, step)
    if (!isTRUE(solve_check$valid))
      return(if (details) c(list(valid = FALSE, reason = "dense_newton_solve_invalid"),
                            solve_check[.GT_D_SOLVE_DETAIL],
                            # The failed operation itself, for a specimen file.
                            # Built only on failure; never retained in a fit.
                            list(inner_iterations = iter,
                                 specimen = list(hessian = response$H, right_hand_side = gradient,
                                                 step = step, factor = R))) else 1e100)
    objective <- response$nll + sum(u^2) / 2
    descent <- sum(gradient * step)
    multiplier <- 1
    accepted <- FALSE
    for (line in seq_len(30L)) {
      candidate <- u - multiplier * step
      next_eta <- baseline + matrix(W %*% candidate, prep$n, prep$q)
      next_response <- .gt_d_response_kernel(next_eta, parameters, prep)
      armijo <- next_response$valid && next_response$nll + sum(candidate^2) / 2 <=
        objective - 1e-4 * multiplier * descent + 1e-12
      roundoff <- FALSE
      if (!armijo && next_response$valid && multiplier == 1) {
        next_objective <- next_response$nll + sum(candidate^2) / 2
        next_gradient <- as.vector(crossprod(W, next_response$gradient)) + candidate
        roundoff <- .gt_d_roundoff_descent(objective, next_objective, descent,
                                          gradient, next_gradient, step, control$inner_tol * 10)
      }
      if (armijo || roundoff) {
        if (roundoff) roundoff_steps <- roundoff_steps + 1L
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
  if (!response$valid) return(if (details) list(valid = FALSE, inner_iterations = iter) else 1e100)
  last_gradient <- max(abs(as.vector(crossprod(W, response$gradient)) + u))
  converged <- is.finite(last_gradient) && last_gradient <= control$inner_tol * 10
  R <- tryCatch(chol(response$H), error = function(e) NULL)
  # A solve that did not converge says how it stopped: at the iteration budget,
  # or because the line search could not improve the penalised objective. The
  # two are different limitations and the record keeps them apart.
  if (is.null(R) || !converged) return(if (details)
    list(valid = FALSE, inner_converged = converged, inner_gradient = last_gradient,
         inner_iterations = iter, inner_line_search_failed = !accepted,
         inner_roundoff_steps = roundoff_steps, inner_factor_unavailable = is.null(R)) else 1e100)
  # The final factor feeds a log determinant rather than a solve, so the Newton
  # check above does not cover it. Validated with fixed deterministic probes
  # before its diagonal contributes to the Laplace objective, which is where the
  # captured issue #14 specimen's wrong value actually entered.
  factor_check <- .gt_d_final_factor_check(response$H, R)
  if (!isTRUE(factor_check$valid)) return(if (details)
    c(list(valid = FALSE, reason = "dense_final_factor_invalid",
           inner_converged = converged, inner_gradient = last_gradient,
           inner_iterations = iter),
      factor_check[c(.GT_D_SOLVE_DETAIL, "probe_index")],
      list(specimen = list(hessian = response$H, factor = R))) else 1e100)
  value <- response$nll + sum(u^2) / 2 + sum(log(diag(R)))
  if (!details) return(value)
  list(valid = TRUE, nll = value, mode = u, eta = eta,
       conditional_nll = response$nll, inner_iterations = iter,
       inner_converged = converged, inner_gradient = last_gradient,
       inner_roundoff_steps = roundoff_steps, random_dimension = length(u))
}

