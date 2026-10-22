# Sparse conditional-mode solve and first-order Laplace evaluation.
#
# The dense solver's Newton system is evaluated in sparse storage at a fixed
# parameter vector. The final gradient tolerance, iteration budget and factor
# validity checks are unchanged. A full Newton step can additionally pass a
# bounded derivative check when rounded function values block an accurate
# mode. Outside the small plateau window the candidate must already satisfy
# the final score tolerance. Search-step acceptance does not certify convergence.
# An evaluation whose cold solve from zero modes is unavailable may be retried
# once from the evaluator's last valid mode; see .gt_d_sparse_evaluator().
#
# Seven algebra operations differ, in addition to the search safeguard above:
#
#   dense                                sparse
#   W %*% u                              sparse product, same W convention
#   crossprod(W, gradient)               sparse crossprod
#   .gt_d_dense_hessian(...)             .gt_d_sparse_hessian(...)
#   chol(H)                              .gt_d_sparse_factor(H)
#   backsolve(R, forwardsolve(t(R), g))  .gt_d_sparse_solve(factor, g)
#   sum(log(diag(R)))                    .gt_d_sparse_logdet(factor) / 2
#   .gt_d_final_factor_check(H, R)       .gt_d_sparse_final_factor_check(H, factor)
#
# The solve-validity check after the Newton step is the SAME function on both
# sides, .gt_d_solve_check(), applied to the sparse H without densifying it;
# only the final-factor probe solve differs, because it goes through the
# factor object rather than a triangular matrix. Neither factor nor solve
# invalidity can be rescued by the line search.
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
# The response arithmetic is shared code, not copied code: the
# likelihood, gradient and curvature all come from .gt_d_response_kernel(),
# which no backend touches.
#
# Binary, ordinal, and nominal blocks use the same response kernel, with full
# off-diagonal multinomial curvature retained by the sparse Hessian assembly.

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

.gt_d_sparse_mode <- function(parameters, prep, backend, control, details = FALSE,
                              start = NULL) {
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
  baseline <- .gt_d_baseline(parameters, prep)
  # An optional start replaces the zero modes and nothing else: the same Newton
  # system, line search, tolerances, budget and validity checks follow from it.
  warm <- !is.null(start)
  if (warm && (!is.numeric(start) || length(start) != ncol(W) || any(!is.finite(start))))
    .gt_d_stop("A sparse mode start must give one finite value per random coordinate.")
  u <- if (warm) as.numeric(start) else numeric(ncol(W))
  converged <- FALSE
  accepted <- TRUE
  last_gradient <- Inf
  roundoff_steps <- 0L
  for (iter in seq_len(control$inner_maxit)) {
    eta <- baseline + matrix(as.numeric(W %*% u), prep$n, prep$q)
    response <- .gt_d_response_kernel(eta, parameters, prep)
    if (!response$valid) return(if (details) list(valid = FALSE, inner_iterations = iter) else 1e100)
    gradient <- as.numeric(Matrix::crossprod(W, response$gradient)) + u
    last_gradient <- max(abs(gradient))
    if (last_gradient <= control$inner_tol) { converged <- TRUE; break }
    H <- .gt_d_sparse_hessian(response$curvature, W, prep$n)
    # tryCatch, not a bare call: the dense solver treats a Hessian with no
    # Cholesky factor as an invalid evaluation and returns, and .gt_d_sparse_factor()
    # signals that condition by stopping. Letting the stop escape would turn a
    # value the dense path reports into an error the sparse path raises.
    factorization <- tryCatch(.gt_d_sparse_factor(H, counts = FALSE), error = function(e) NULL)
    if (is.null(factorization)) return(if (details) list(valid = FALSE) else 1e100)
    step <- .gt_d_sparse_solve(factorization, gradient)
    # The same invariant, at the same point, as the dense solver: checked
    # immediately after the solve and before the line search consumes the
    # step. A sparse Cholesky can likewise return without error and still hand
    # back a factor of some other matrix (issue #14), and a violated invariant
    # makes the sparse conditional solve unavailable, with no rescue. The
    # backward error is taken against the sparse H directly, so nothing here
    # densifies the matrix.
    solve_check <- .gt_d_solve_check(H, gradient, step)
    if (!isTRUE(solve_check$valid))
      return(if (details) c(list(valid = FALSE, reason = "sparse_newton_solve_invalid"),
                            solve_check[.GT_D_SOLVE_DETAIL],
                            # The failed operation itself, for a specimen file.
                            # Built only on failure; never retained in a fit.
                            list(inner_iterations = iter,
                                 specimen = list(hessian = H, right_hand_side = gradient,
                                                 step = step, factor = factorization$factor))) else 1e100)
    objective <- response$nll + sum(u^2) / 2
    descent <- sum(gradient * step)
    multiplier <- 1
    accepted <- FALSE
    for (line in seq_len(30L)) {
      candidate <- u - multiplier * step
      next_eta <- baseline + matrix(as.numeric(W %*% candidate), prep$n, prep$q)
      next_response <- .gt_d_response_kernel(next_eta, parameters, prep)
      armijo <- next_response$valid && next_response$nll + sum(candidate^2) / 2 <=
        objective - 1e-4 * multiplier * descent + 1e-12
      roundoff <- FALSE
      if (!armijo && next_response$valid && multiplier == 1) {
        next_objective <- next_response$nll + sum(candidate^2) / 2
        # The alternative bounds the decrement and function discrepancy,
        # rechecking the score without changing final stationarity tolerances.
        next_gradient <- as.numeric(Matrix::crossprod(W, next_response$gradient)) + candidate
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
  eta <- baseline + matrix(as.numeric(W %*% u), prep$n, prep$q)
  response <- .gt_d_response_kernel(eta, parameters, prep)
  if (!response$valid) return(if (details) list(valid = FALSE, inner_iterations = iter) else 1e100)
  last_gradient <- max(abs(as.numeric(Matrix::crossprod(W, response$gradient)) + u))
  converged <- is.finite(last_gradient) && last_gradient <= control$inner_tol * 10
  H <- .gt_d_sparse_hessian(response$curvature, W, prep$n)
  factorization <- tryCatch(.gt_d_sparse_factor(H, counts = FALSE), error = function(e) NULL)
  # As in the dense solver: how a non-converged solve stopped is recorded.
  if (is.null(factorization) || !converged) return(if (details)
    list(valid = FALSE, inner_converged = converged, inner_gradient = last_gradient,
         inner_iterations = iter, inner_line_search_failed = !accepted,
         inner_roundoff_steps = roundoff_steps,
         inner_factor_unavailable = is.null(factorization)) else 1e100)
  # The final factor feeds a log determinant rather than a solve, so the Newton
  # check above does not cover it. Validated with the same fixed probes the
  # dense solver uses, through the factor object's own permutation-aware solve,
  # before its diagonal contributes to the Laplace objective.
  factor_check <- .gt_d_sparse_final_factor_check(H, factorization)
  if (!isTRUE(factor_check$valid)) return(if (details)
    c(list(valid = FALSE, reason = "sparse_final_factor_invalid",
           inner_converged = converged, inner_gradient = last_gradient,
           inner_iterations = iter),
      factor_check[c(.GT_D_SOLVE_DETAIL, "probe_index")],
      list(specimen = list(hessian = H, factor = factorization$factor))) else 1e100)
  # Half the log determinant, matching sum(log(diag(R))) in the dense solver.
  value <- response$nll + sum(u^2) / 2 + .gt_d_sparse_logdet(factorization) / 2
  if (!details) return(value)
  answer <- list(valid = TRUE, nll = value, mode = u, eta = eta,
       conditional_nll = response$nll, inner_iterations = iter,
       inner_converged = converged, inner_gradient = last_gradient,
       inner_roundoff_steps = roundoff_steps,
       random_dimension = length(u))
  if (warm) answer$inner_warm_started <- TRUE
  answer
}

# The sparse marginal evaluator, shaped to be substituted for .gt_d_laplace().
#
# Same signature, same return shape, same meaning. Everything outside the
# marginal evaluation stays with the caller: preparation, parameterization,
# bounds, starts, the optimizer, restarts, tight validation, stationarity and
# acceptance are the dense implementation's and are not duplicated here.
#
# Only the inner numerical path differs:
#
#   decode covariance factors   (shared)
#   build sparse W              (from retained geometry)
#   response kernel             (shared, backend-independent)
#   sparse conditional mode     (.gt_d_sparse_mode)
#   half the sparse log det     (.gt_d_sparse_logdet)
#
# The coordinate geometry is retained across calls because an outer optimizer
# evaluates this many times and the design does not change between them. The
# sparsity pattern is not retained; see .gt_d_sparse_context().
#
# There is no fallback. If the sparse path cannot evaluate, this returns what
# the dense path returns for an unevaluable point, and the caller's existing
# acceptance rules decide. A backend that quietly handed a failed evaluation to
# another implementation would make a rejection depend on which engine ran.
#
# A retry is not a fallback. When the cold solve from zero modes ends as a
# classified convergence failure, the same sparse solve is attempted once more
# from the last valid mode this evaluator produced, under the same rules; see
# the start argument of .gt_d_sparse_mode(). The cold solve runs first and is
# unchanged, so every evaluation it completes is identical with or without the
# retry. The two validity invariants are never rescued: a cold solve that
# failed one is not retried, and a retry that fails one is the recorded outcome.
.gt_d_retry_eligible <- function(value)
  is.list(value) && !isTRUE(value$valid) && is.null(value$reason) &&
    isFALSE(value$inner_converged) && !isTRUE(value$inner_factor_unavailable)

# Warm starts within an optimizer attempt.
#
# The conditional objective is strictly concave in the random effects for
# every supported family, so its mode is unique and a starting point changes
# only the path to it, never the point. When the caller sets
# control$inner_start to "warm", an evaluation starts from the mode of the
# attempt's current centre: the last evaluation that moved more than one
# coordinate. An evaluation that differs from the centre in exactly one
# coordinate is a finite-difference probe; both probes of a coordinate start
# from the same centre mode and neither replaces it, so a gradient is never
# formed from two solves seeded differently. The fit resets this state before
# every optimizer attempt, so restarts stay independent, and it leaves
# inner_start unset for the final checks, the stationarity probes and the
# information step, which therefore remain cold solves from zero modes.
#
# A warm solve that stops short of the mode without a validity event is not
# the recorded outcome: the cold solve from zero modes runs in its place, so
# no evaluation ends worse than it would have ended before warm starts
# existed. The two validity invariants are never rescued in either direction.
.gt_d_sparse_evaluator <- function() {
  context <- NULL
  last_mode <- NULL
  centre_parameters <- NULL
  centre_mode <- NULL
  evaluate <- function(parameters, prep, groups, setup, control, details = FALSE,
           factors_override = NULL) {
    if (is.null(context)) {
      context <<- .gt_d_sparse_context(groups, prep$n, prep$q)
    } else if (!identical(context$groups, groups) ||
               !identical(context$n, as.integer(prep$n)) ||
               !identical(context$q, as.integer(prep$q))) {
      # The retained geometry belongs to one design. Reusing it for another
      # would silently evaluate a different model.
      #
      # Compare the grouping itself, not its dimensions. Two designs can agree
      # on observation count, latent dimension, source count and every level
      # count while disagreeing on which observation belongs to which level,
      # and that difference is exactly what the retained geometry encodes. A
      # dimension-only check admits such a design and answers with the cached
      # coordinates: a finite, plausible value computed for a model that was
      # not asked about. identical() on the groups covers source order and
      # names, level counts, and every observation's index.
      .gt_d_stop("The sparse evaluator was reused across different designs.")
    }
    fixed_length <- length(prep$start)
    factors <- if (is.null(factors_override))
      .gt_d_covariance_factors(parameters[-seq_len(fixed_length)], setup) else factors_override
    backend <- .gt_d_sparse_backend_from(context, factors)
    warm_requested <- identical(control$inner_start, "warm")
    warm <- warm_requested && !is.null(centre_mode) && length(centre_mode) == ncol(backend$W)
    probe <- !is.null(centre_parameters) && length(centre_parameters) == length(parameters) &&
      sum(parameters != centre_parameters) == 1L
    if (warm) {
      answer <- .gt_d_sparse_mode(parameters, prep, backend, control, details = TRUE,
                                  start = centre_mode)
      if (!isTRUE(answer$valid) && is.null(answer$reason)) {
        cold <- .gt_d_sparse_mode(parameters, prep, backend, control, details = TRUE)
        cold$inner_warm_attempt <- .gt_d_failure_record(answer, list())
        answer <- cold
      }
    } else {
      answer <- .gt_d_sparse_mode(parameters, prep, backend, control, details = TRUE)
    }
    if (!warm && .gt_d_retry_eligible(answer) && !is.null(last_mode) &&
        length(last_mode) == ncol(backend$W)) {
      # One retry from the last valid conditional mode of this fit, within the
      # same backend and under the same tolerances, iteration budget, line
      # search, solve-validity and factor-validity rules. Only a classified
      # convergence failure with an available factor reaches here. A retry
      # that fails a solve- or factor-validity invariant is itself the
      # recorded outcome, with its specimen; a retry that merely does not
      # converge leaves the cold failure as the recorded outcome.
      retry <- .gt_d_sparse_mode(parameters, prep, backend, control, details = TRUE,
                                 start = last_mode)
      if (isTRUE(retry$valid) || .gt_d_validity_event(retry)) {
        retry$inner_warm_started <- TRUE
        retry$inner_cold_attempt <- .gt_d_failure_record(answer, list())
        answer <- retry
      }
    }
    if (isTRUE(answer$valid)) {
      last_mode <<- answer$mode
      if (warm_requested && !probe) {
        centre_parameters <<- parameters
        centre_mode <<- answer$mode
      }
    }
    if (!details) return(if (isTRUE(answer$valid)) answer$nll else 1e100)
    if (isTRUE(answer$valid))
      answer <- append(answer, list(factors = factors), after = 2L)
    answer
  }
  # Called by the fit before every optimizer attempt: the attempt's first solve
  # is cold, and nothing from an earlier attempt seeds it.
  attr(evaluate, "reset") <- function() {
    last_mode <<- NULL
    centre_parameters <<- NULL
    centre_mode <<- NULL
    invisible(NULL)
  }
  evaluate
}
