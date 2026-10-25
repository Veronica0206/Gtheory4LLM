# Escape from a singular source covariance after a tight optimizer attempt.
#
# In natural Cholesky coordinates a source covariance S = L L' becomes
# singular when a factor column reaches zero. Along that column the objective's
# first derivative in L is exactly zero, because S changes only to second
# order in it, so a gradient-based optimizer cannot leave the boundary even
# when the covariance-direction score says that adding variance in the missing
# direction improves the fit. The stationarity check measures that score in
# covariance coordinates and refuses such a point; this step acts on it.
#
# For each singular source whose projected score P = S_n - Proj_PSD(S_n - G_n)
# from the stationarity check exceeds the stationarity tolerance, the step
# moves the covariance to S(alpha) = S - alpha * scale * P, alpha chosen from a
# fixed grid in (0, 1] by the objective at cold conditional modes under the
# validation settings. For alpha in (0, 1] S(alpha) is a convex combination of
# S and scale * Proj_PSD(S_n - G_n), both positive semidefinite, so it stays
# positive semidefinite. It is written back into natural Cholesky coordinates
# with zero pivots kept at zero. The caller reruns the tight attempt from the
# new point. Nothing here decides acceptance: the stationarity check, restart
# stability and every other rule run on the final candidates as before.

# A lower-triangular factor of a positive semidefinite matrix whose
# nonpositive pivots are kept at zero; NULL when it does not reproduce S.
.gt_d_psd_cholesky <- function(S) {
  q <- nrow(S)
  L <- matrix(0, q, q)
  tolerance <- 1e-13 * max(1, max(abs(diag(S))))
  for (j in seq_len(q)) {
    before <- seq_len(j - 1L)
    pivot <- S[j, j] - sum(L[j, before]^2)
    if (pivot <= tolerance) next
    L[j, j] <- sqrt(pivot)
    if (j < q) for (i in (j + 1L):q)
      L[i, j] <- (S[i, j] - sum(L[i, before] * L[j, before])) / L[j, j]
  }
  if (!all(is.finite(L)) || max(abs(tcrossprod(L) - S)) > 1e-9 * max(1, max(abs(S)))) return(NULL)
  L
}

# The stored parameters with source `k`'s natural Cholesky coordinates set
# from the covariance S; NULL when S has no such factor.
.gt_d_cholesky_replace <- function(parameters, setup, fixed_length, k, S) {
  L <- .gt_d_psd_cholesky(S)
  if (is.null(L)) return(NULL)
  index <- fixed_length + (k - 1L) * setup$per + seq_len(setup$per)
  parameters[index] <- L[cbind(setup$positions[, 1L], setup$positions[, 2L])]
  parameters
}

.gt_d_boundary_escape_step <- function(parameters, prep, groups, setup, control, laplace, lower, upper,
                                       grid = c(1, 0.3, 0.1, 0.03, 0.01, 3e-3, 1e-3, 3e-4, 1e-4),
                                       singular_tolerance = 1e-6) {
  state <- new.env(parent = emptyenv())
  state$evaluations <- 0L
  # Every objective evaluation the step makes, the covariance-score probes
  # included, is counted in its record.
  counted <- function(...) {
    state$evaluations <- state$evaluations + 1L
    laplace(...)
  }
  evaluate <- function(p) {
    value <- counted(p, prep, groups, setup, control, details = TRUE)
    if (.gt_d_evaluation_usable(value) && isTRUE(value$inner_converged)) value else NULL
  }
  done <- function(reason, ...) list(moved = FALSE, parameters = parameters,
    record = c(list(reason = reason, evaluations = state$evaluations), list(...)))
  centre <- evaluate(parameters)
  if (is.null(centre) || is.null(centre$factors))
    return(done("the conditional mode at the attempt's point is not usable"))
  factors <- centre$factors
  # The fit's own boundary rule: a source is singular when its smallest
  # covariance eigenvalue is below 1e-6.
  smallest <- vapply(factors, function(L)
    min(eigen(tcrossprod(L), symmetric = TRUE, only.values = TRUE)$values), numeric(1))
  singular <- names(factors)[smallest < singular_tolerance]
  if (!length(singular)) return(done("no singular source", singular = character()))
  scores <- tryCatch(.gt_d_stationarity(parameters, prep, groups, setup, control, centre, laplace = counted,
                                        fixed_effects = FALSE, sources = singular), error = identity)
  if (inherits(scores, "error"))
    return(done(paste("covariance scores unavailable:", conditionMessage(scores)), singular = singular))
  size <- vapply(scores$covariance_projected_scores, function(x) max(abs(unlist(x))), numeric(1))
  failing <- names(size)[size > control$stationarity_tol]
  if (!length(failing))
    return(done("every singular source is stationary", singular = singular, scores = size))
  fixed_length <- length(prep$start)
  current <- parameters
  base <- centre$nll
  steps <- list()
  for (s in failing) {
    k <- match(s, names(factors))
    S <- tcrossprod(factors[[s]])
    scale <- max(1, max(diag(S)))
    direction <- scores$covariance_projected_scores[[s]]
    if (!is.matrix(direction)) direction <- diag(direction, nrow = nrow(S))
    candidate <- function(alpha) .gt_d_cholesky_replace(current, setup, fixed_length, k, S - alpha * scale * direction)
    values <- vapply(grid, function(alpha) {
      p <- candidate(alpha)
      if (is.null(p) || any(p < lower | p > upper)) return(Inf)
      value <- evaluate(p)
      if (is.null(value)) Inf else value$nll
    }, numeric(1))
    best <- which.min(values)
    improved <- is.finite(values[[best]]) && values[[best]] < base
    steps[[s]] <- list(score = size[[s]], alpha = grid[[best]], objective_change = values[[best]] - base,
                       taken = improved)
    if (improved) {
      current <- candidate(grid[[best]])
      base <- values[[best]]
    }
  }
  moved <- !identical(current, parameters)
  list(moved = moved, parameters = current,
       record = list(reason = if (moved) "stepped" else "no step lowered the objective",
                     evaluations = state$evaluations, singular = singular, scores = size, steps = steps,
                     objective_change = base - centre$nll))
}
