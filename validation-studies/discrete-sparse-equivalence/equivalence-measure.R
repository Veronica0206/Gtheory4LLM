# Measurement layer for the dense/sparse equivalence qualification.
#
# This file MEASURES and never JUDGES. It applies no tolerance, reads no
# tolerance table, assigns no disposition, classifies no case, and executes no
# case when sourced. It returns the quantities PROTOCOL.md names, computed the
# way cases.R freezes them, so that two later and separately reviewed changes
# can consume the same numbers:
#
#   calibration     measures the non-scoring EQ_CALIBRATION cases and reports
#                   observed maxima, from which tolerance VALUES are proposed
#   the runner      equivalence-runner-impl.R, sourced by the frozen launcher
#                   only once tolerances.csv exists, applies those values
#
# Neither may compute a quantity differently from the other, which is why the
# computation lives here rather than in either of them. The formulas are not
# chosen here either: .eq_difference(), EQ_METRIC, EQ_STAGE3_LATENT_POINT and
# EQ_VALIDITY_BOUND come from cases.R, which is pinned.
#
# The caller sources cases.R and the package R files first, exactly as
# run-equivalence.R does. Nothing here sources anything.
#
# Where cases.R fixes a formula but not an operand, the choice this file makes
# is named at the point it is made and listed in EQ_MEASUREMENT_CHOICES, so
# review can approve or reject it before any case is measured with it.

EQ_BACKENDS <- c("dense", "sparse")

EQ_MEASUREMENT_CHOICES <- c(
  solve_right_hand_sides = paste(
    "The solve backward-error witness is evaluated on the two fixed deterministic",
    "probes .gt_d_solve_probes() already frozen for final-factor validity in #34,",
    "solved through each backend's own factor. EQ_VALIDITY fixes the formula but",
    "not the right-hand side, and the converged gradient is unusable there: it is",
    "near zero at the mode, which makes the ratio delicate exactly where the",
    "witness must be trustworthy."),
  witness_system = paste(
    "Every stage 1 witness is evaluated on the final-mode system each backend",
    "produced, which is the factor whose log determinant enters that backend's",
    "objective and the place the #14 specimen's wrong value entered."),
  conditional_objective = paste(
    "The conditional objective is the response negative log likelihood, the",
    "quantity #30 qualified as conditional_nll. At the frozen latent point zero",
    "the mode penalty sum(u^2)/2 is exactly zero, so this and the penalized form",
    "coincide there."),
  log_determinant = paste(
    "The solved log determinant is the FULL log determinant of the final-mode",
    "Hessian, recomputed at the returned mode through the backend's own",
    "production operations. It is not recovered by subtracting terms from the",
    "marginal objective, which would cancel a large value against a small one.",
    "The Laplace identity that relates them is recorded separately."),
  design_identity = paste(
    "Prepared-design identity is measured on the random design W each backend",
    "builds from the shared preparation: its dimensions, the production random",
    "dimension, and the largest absolute entrywise difference."))

# ---- construction ---------------------------------------------------------------

# The frozen construction, not a second one. Preparation, grouping, covariance
# setup, start, bounds and zero coordinates all come from cases.R.
eq_case_map <- function(row, geometry) .eq_parameter_map(row, geometry)

# The three frozen stage 3 parameter points for a case.
eq_case_points <- function(map)
  .eq_fixed_points(map$start, map$lower, map$upper, map$zero_coordinates)

# The production marginal evaluator for a backend. The sparse evaluator retains
# design geometry across calls, so each case needs its own instance.
eq_evaluator <- function(backend)
  switch(.eq_backend_name(backend), dense = .gt_d_laplace,
         sparse = .gt_d_sparse_evaluator())

.eq_backend_name <- function(backend) {
  if (!is.character(backend) || length(backend) != 1L || !backend %in% EQ_BACKENDS)
    stop("backend must be one of: ", paste(EQ_BACKENDS, collapse = ", "), call. = FALSE)
  backend
}

.eq_factors <- function(map, parameters)
  .gt_d_covariance_factors(parameters[-seq_along(map$prep$start)], map$setup)

# The random design exactly as the backend's production path builds it. The
# sparse evaluator uses a retained context rather than .gt_d_sparse_backend();
# both call the same builder, and stage 2 is where any difference would show.
.eq_design_for <- function(backend, map, factors)
  switch(.eq_backend_name(backend),
         dense = .gt_d_dense_backend(map$groups, factors, map$prep$n, map$prep$q),
         sparse = .gt_d_sparse_backend(map$groups, factors, map$prep$n, map$prep$q))

.eq_crossprod <- function(backend, W, x)
  switch(backend, dense = as.numeric(crossprod(W, x)),
         sparse = as.numeric(Matrix::crossprod(W, x)))

.eq_hessian <- function(backend, curvature, W, n)
  switch(backend, dense = .gt_d_dense_hessian(curvature, W, n),
         sparse = .gt_d_sparse_hessian(curvature, W, n))

# ---- stage 2: prepared-design identity ---------------------------------------------

eq_measure_design <- function(map, parameters) {
  factors <- .eq_factors(map, parameters)
  dense <- .eq_design_for("dense", map, factors)$W
  sparse <- as.matrix(.eq_design_for("sparse", map, factors)$W)
  levels <- sum(vapply(map$groups, `[[`, integer(1), "nlevels"))
  list(
    random_dimension = c(dense = ncol(dense), sparse = ncol(sparse)),
    production_random_dimension = levels * map$prep$q,
    design_rows = c(dense = nrow(dense), sparse = nrow(sparse)),
    design_max_abs_difference = if (identical(dim(dense), dim(sparse)))
      max(abs(dense - sparse)) else Inf)
}

# ---- stage 3: quantities at the common latent point -----------------------------------
#
# Evaluated at the SAME latent point in both backends, EQ_STAGE3_LATENT_POINT,
# which cases.R freezes at zero. Evaluating each at its own conditional mode
# would compare two different problems.
eq_measure_common_latent <- function(map, parameters, backend) {
  backend <- .eq_backend_name(backend)
  W <- .eq_design_for(backend, map, .eq_factors(map, parameters))$W
  u <- rep(EQ_STAGE3_LATENT_POINT, ncol(W))
  eta <- .gt_d_baseline(parameters, map$prep) +
    matrix(as.numeric(W %*% u), map$prep$n, map$prep$q)
  kernel <- .gt_d_response_kernel(eta, parameters, map$prep)
  if (!isTRUE(kernel$valid))
    return(list(valid = FALSE, backend = backend, latent_point = u))
  list(valid = TRUE, backend = backend, latent_point = u,
       predictor = as.numeric(eta),
       conditional_objective = kernel$nll,
       mode_score = .eq_crossprod(backend, W, kernel$gradient) + u,
       hessian = as.matrix(.eq_hessian(backend, kernel$curvature, W, map$prep$n)))
}

# ---- stage 3 solved quantities and stage 1 validity witnesses --------------------------

# Factor the final-mode Hessian through the backend's own production operation,
# and return what a witness needs: the reconstruction in ORIGINAL coordinates,
# the full log determinant, and a solve through that factor.
.eq_factorize <- function(backend, H) {
  if (identical(backend, "dense")) {
    R <- tryCatch(chol(H), error = function(e) NULL)
    if (is.null(R)) return(NULL)
    return(list(reconstruction = crossprod(R),
                log_determinant = 2 * sum(log(diag(R))),
                solve = function(b) backsolve(R, forwardsolve(t(R), b))))
  }
  factorization <- tryCatch(.gt_d_sparse_factor(H), error = function(e) NULL)
  if (is.null(factorization)) return(NULL)
  # P' L L' P, with the permutation undone by the interface rather than by
  # indexing @perm by hand. This is EQ_VALIDITY$factor_reconstruction$sparse.
  parts <- Matrix::expand2(factorization$factor, LDL = FALSE)
  list(reconstruction = as.matrix(Reduce(`%*%`, parts)),
       log_determinant = .gt_d_sparse_logdet(factorization),
       solve = function(b) as.numeric(.gt_d_sparse_solve(factorization, b)))
}

eq_validity_witnesses <- function(backend, H, mode, objective, factor) {
  backend <- .eq_backend_name(backend)
  dense_H <- as.matrix(H)
  random_dimension <- nrow(dense_H)
  unavailable <- is.null(factor)
  backward <- if (unavailable) Inf else max(vapply(
    .gt_d_solve_probes(random_dimension),
    function(b) .gt_d_backward_error(dense_H, b, factor$solve(b)), numeric(1)))
  reconstruction <- if (unavailable) Inf else
    max(abs(factor$reconstruction - dense_H)) / max(abs(dense_H))
  eigenvalues <- eigen((dense_H + t(dense_H)) / 2, symmetric = TRUE, only.values = TRUE)$values
  log_determinant <- if (unavailable || any(eigenvalues <= 0)) Inf else
    abs(factor$log_determinant - sum(log(eigenvalues)))
  list(backend = backend, random_dimension = random_dimension,
       bound = EQ_VALIDITY_BOUND(random_dimension),
       factor_available = !unavailable,
       solve_backward_error = backward,
       factor_reconstruction = reconstruction,
       log_determinant_witness = log_determinant,
       finite_mode = length(mode) > 0L && all(is.finite(mode)),
       finite_objective = is.numeric(objective) && length(objective) == 1L &&
         is.finite(objective) && objective < 1e99)
}

eq_measure_solved <- function(map, parameters, backend, evaluator = eq_evaluator(backend)) {
  backend <- .eq_backend_name(backend)
  answer <- evaluator(parameters, map$prep, map$groups, map$setup, map$control,
                      details = TRUE)
  if (!is.list(answer)) answer <- list(valid = FALSE)
  diagnostic <- list(inner_iterations = answer$inner_iterations,
                     inner_converged = answer$inner_converged,
                     inner_gradient = answer$inner_gradient)
  if (!isTRUE(answer$valid))
    # An invalid evaluation carries no inner_iterations, so it is reported as
    # invalid rather than as a solve that ended at its budget.
    return(c(list(valid = FALSE, backend = backend,
                  reason = if (is.null(answer$reason)) NA_character_ else answer$reason),
             diagnostic))
  W <- .eq_design_for(backend, map, answer$factors)$W
  kernel <- .gt_d_response_kernel(answer$eta, parameters, map$prep)
  if (!isTRUE(kernel$valid))
    return(c(list(valid = FALSE, backend = backend,
                  reason = "final_mode_response_invalid"), diagnostic))
  H <- .eq_hessian(backend, kernel$curvature, W, map$prep$n)
  factor <- .eq_factorize(backend, H)
  log_determinant <- if (is.null(factor)) NA_real_ else factor$log_determinant
  c(list(valid = TRUE, backend = backend,
         conditional_mode = answer$mode,
         log_determinant = log_determinant,
         marginal_negative_log_likelihood = answer$nll,
         laplace_identity_residual = answer$nll -
           (answer$conditional_nll + sum(answer$mode^2) / 2 + log_determinant / 2),
         random_dimension = answer$random_dimension,
         witnesses = eq_validity_witnesses(backend, H, answer$mode, answer$nll, factor)),
    diagnostic)
}

# ---- differences through the frozen ruler ---------------------------------------------

# Differences only, through .eq_difference(). No tolerance is attached, and a
# quantity missing from either side is reported as Inf rather than skipped.
eq_stage3_differences <- function(dense_common, sparse_common, dense_solved, sparse_solved) {
  pick <- function(x, name) if (isTRUE(x$valid) && !is.null(x[[name]])) x[[name]] else numeric(0)
  common <- vapply(EQ_STAGE3_AT_COMMON_LATENT, function(q)
    .eq_difference(pick(dense_common, q), pick(sparse_common, q), q), numeric(1))
  solved <- vapply(EQ_STAGE3_SOLVED, function(q)
    .eq_difference(pick(dense_solved, q), pick(sparse_solved, q), q), numeric(1))
  c(common, solved)
}
