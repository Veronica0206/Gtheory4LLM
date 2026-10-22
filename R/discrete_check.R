# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# A refined numerical comparison for a discrete fit's marginal likelihood at
# its fitted parameters, to estimate the first-order Laplace error there.
#
# The Laplace objective is f(u) + u'u/2 + log det(R) at the conditional mode,
# where f is the conditional negative log likelihood of the standardized random
# effects u and R'R is the Hessian of f(u) + u'u/2 there. The marginal
# likelihood it approximates is the integral of exp(-f(u)) phi(u) du. That
# integral is re-estimated here through the Gaussian the Laplace solution
# already provides, N(mode, (R'R)^-1): by adaptive Gauss-Hermite quadrature in
# few dimensions, and by importance sampling from a defensive mixture otherwise:
# 90% that Gaussian and 10% the standard-normal random-effect prior. Every
# weight uses the full mixture density, whichever component generated its draw.
# Since a categorical likelihood is at most one, the unnormalised importance
# weights are bounded by 10. Their moments are finite; this does not guarantee
# useful relative precision or calibrated finite-sample Monte Carlo intervals.
#
# What it establishes is limited and stated: the estimate is at fixed
# parameters, so it measures the approximation error in the objective, not
# bias in the estimates; a stable quadrature refinement is evidence of
# numerical stability, not an error bound; and an importance-sampling estimate
# can miss tail mass its diagnostics do not reveal. Every new native solve the
# comparison introduces is checked, and a contribution that could not be
# evaluated is reported as unavailable, never as zero.

# Probabilists' Gauss-Hermite rule by the Golub-Welsch eigenvalue construction:
# nodes and weights integrate h(z) phi(z) dz exactly for polynomial h of degree
# below 2 * order.
.gt_normal_quadrature <- function(order) {
  jacobi <- matrix(0, order, order)
  off <- sqrt(seq_len(order - 1L))
  jacobi[cbind(seq_len(order - 1L), 2:order)] <- off
  jacobi[cbind(2:order, seq_len(order - 1L))] <- off
  decomposition <- eigen(jacobi, symmetric = TRUE)
  list(nodes = decomposition$values, weights = decomposition$vectors[1L, ]^2)
}

.gt_log_sum_exp <- function(x) {
  top <- max(x)
  if (!is.finite(top)) return(top)
  top + log(sum(exp(x - top)))
}

.gt_check_count <- function(value, label, minimum, maximum) {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) || !is.finite(value) ||
      value != floor(value) || value < minimum || value > maximum)
    stop(label, " must be one whole number from ", minimum, " to ", maximum, ".", call. = FALSE)
  as.integer(value)
}

# The log of the integrand divided by the proposal density at the point a
# standard normal draw z maps to, u = mode + R^-1 z, or NA when the point could
# not be evaluated: the triangular solve is verified against its own system,
# and a response the kernel cannot evaluate is unavailable, not zero.
.gt_laplace_log_weight <- function(z, u0, R, W, baseline, parameters, prep, log_det_scale) {
  delta <- tryCatch(backsolve(R, z), error = function(e) NA_real_)
  if (any(!is.finite(delta)) || length(delta) != length(z) ||
      max(abs(R %*% delta - z)) > sqrt(.Machine$double.eps) * max(1, max(abs(z))))
    return(NA_real_)
  u <- u0 + delta
  response <- .gt_d_response_kernel(baseline + matrix(W %*% u, prep$n, prep$q), parameters, prep)
  if (!isTRUE(response$valid)) return(NA_real_)
  -response$nll - sum(u^2) / 2 + sum(z^2) / 2 + log_det_scale
}

# The defensive proposal is q(u) = 0.9 * N(u0, H^-1) + 0.1 * N(0, I),
# where H = R'R. A Bernoulli draw chooses the component and z is standard
# normal in either case. Evaluate BOTH densities for EVERY draw: dividing by
# only the sampled component would not be this mixture estimator. Normalising
# constants cancel in the density ratio below. The prior component guarantees
# q(u) >= 0.1 * phi(u), hence 0 <= L(u) * phi(u) / q(u) <= 10.
.gt_laplace_mixture_log_weight <- function(z, from_prior, u0, R, W, baseline,
                                            parameters, prep, log_det_scale) {
  if (from_prior) {
    u <- z
  } else {
    delta <- tryCatch(backsolve(R, z), error = function(e) NA_real_)
    if (any(!is.finite(delta)) || length(delta) != length(z) ||
        max(abs(R %*% delta - z)) > sqrt(.Machine$double.eps) * max(1, max(abs(z))))
      return(NA_real_)
    u <- u0 + delta
  }
  standardized <- as.numeric(R %*% (u - u0))
  if (any(!is.finite(u)) || any(!is.finite(standardized))) return(NA_real_)
  response <- .gt_d_response_kernel(baseline + matrix(W %*% u, prep$n, prep$q), parameters, prep)
  if (!isTRUE(response$valid)) return(NA_real_)
  log_gaussian_over_prior <- -log_det_scale - sum(standardized^2) / 2 + sum(u^2) / 2
  value <- -response$nll - .gt_log_sum_exp(c(log(.GT_LAPLACE_PRIOR_WEIGHT),
    log1p(-.GT_LAPLACE_PRIOR_WEIGHT) + log_gaussian_over_prior))
  if (is.na(value) || value > -log(.GT_LAPLACE_PRIOR_WEIGHT) + 1e-10) return(NA_real_)
  value
}

.GT_LAPLACE_PRIOR_WEIGHT <- 0.1

# Reconstruct the fitted Call source from retained item membership, not the
# current row order or an auxiliary call column that retention may have dropped.
# The shared batch validator still decides whether this layout is supported.
.gt_laplace_call_group <- function(data, design, components) {
  model <- design$batch_model
  if (!isTRUE(model$modelled)) {
    # Without a modelled batch, Call can be an ordinary declared column/source.
    # Only an additional virtual Call component requires retained batch layout.
    if (.GT_CALL_TERM %in% names(components) && !.GT_CALL_TERM %in% design$terms)
      stop("The fitted Call covariance has no retained modelled layout.", call. = FALSE)
    return(NULL)
  }
  items <- model$item_levels
  membership <- model$item_batches
  if (is.null(design$batch) || !is.atomic(items) || !length(items) ||
      !is.null(dim(items)) || anyNA(items) || anyDuplicated(items) ||
      (is.numeric(items) && any(!is.finite(items))) ||
      !is.atomic(membership) || length(membership) != length(items) || anyNA(membership))
    stop("The fitted Call source needs its retained item-to-batch layout.", call. = FALSE)
  keys <- .gt_batch_item_keys(items)
  index <- match(.gt_batch_item_keys(data[[design$object]]), keys)
  if (anyDuplicated(keys) || anyNA(index) || length(unique(index)) != length(items))
    stop("The supplied items do not match the fitted Call layout.", call. = FALSE)
  membership <- match(membership, unique(membership))
  if (!identical(as.integer(max(membership)), as.integer(model$batches)) ||
      !identical(as.integer(model$size), as.integer(design$batch$size)) ||
      any(tabulate(membership) != design$batch$size))
    stop("The retained Call membership does not match its equal batch size.", call. = FALSE)
  # Supply a stable order to the validator even for originally recorded calls.
  # Within-batch order has no effect on the fitted equal-coupling Call source.
  rebuilt <- data[c(design$object, design$facets)]
  order_column <- ".gt_laplace_call_order"
  while (order_column %in% names(rebuilt)) order_column <- paste0(".", order_column)
  item_order <- order(order(membership, seq_along(membership)))
  rebuilt[[order_column]] <- item_order[index]
  declaration <- design
  declaration$batch$id <- NULL
  declaration$batch$order <- order_column
  call <- .gt_batch_model(rebuilt, declaration)
  if (!isTRUE(call$modelled))
    stop("The fitted Call layout cannot be reconstructed: ", call$reason, ".", call. = FALSE)
  group <- .gt_d_call_group(rebuilt, declaration, call)
  # If supplied auxiliary columns describe a layout, do not silently discard
  # a contradiction. Missing auxiliary columns are allowed by data retention.
  supplied <- (!is.null(design$batch$id) && design$batch$id %in% names(data)) ||
    (is.null(design$batch$id) && !is.null(design$batch$order) && design$batch$order %in% names(data))
  if (supplied) {
    declaration <- design
    if (!is.null(declaration$batch$id) && !is.null(declaration$batch$order) &&
        !declaration$batch$order %in% names(data)) declaration$batch$order <- NULL
    recorded <- .gt_batch_model(data, declaration)
    if (!isTRUE(recorded$modelled))
      stop("The supplied Call layout is unsupported: ", recorded$reason, ".", call. = FALSE)
    recorded_group <- .gt_d_call_group(data, declaration, recorded)
    if (!identical(group$index, recorded_group$index))
      stop("The supplied call columns disagree with the fitted Call layout.", call. = FALSE)
  }
  group
}

# The diagnostic always uses dense conditional algebra, including for a sparse
# fitted model. Budget the dense reconstruction and integration workspace before
# building covariance factors, a dense design/Hessian, or a proposal/grid matrix.
.gt_laplace_resources <- function(n, q, dimension, method, nodes, draws) {
  dense <- .gt_d_dense_bytes(n, q, dimension)
  integration <- if (method == "importance") {
    2 * (8 * as.double(draws) * dimension + 4 * 8 * draws)
  } else {
    points <- (nodes + 5)^dimension
    2 * (8 * points * dimension + 3 * 8 * points + 2 * 8 * (nodes + 5)^2)
  }
  list(total = dense$total + integration, dense = dense, integration = integration,
    scope = "Conservative dense reconstruction and integration workspace estimate; not a measured peak allocation.")
}

gt_laplace_check <- function(fit, method = c("auto", "quadrature", "importance"), nodes = 20L,
                             draws = 4000L, seed = NULL, max_dimension = 60L,
                             max_evaluations = 1000000L, data = NULL) {
  if (!inherits(fit, "gt_fit")) stop("Expected a gt_fit object.", call. = FALSE)
  kinds <- vapply(fit$families, `[[`, character(1), "family")
  if (all(kinds == "gaussian"))
    stop("A Gaussian fit uses an exact likelihood; there is no Laplace approximation to check.", call. = FALSE)
  method <- match.arg(method)
  nodes <- .gt_check_count(nodes, "nodes", 5L, 80L)
  draws <- .gt_check_count(draws, "draws", 100L, 1000000L)
  max_dimension <- .gt_check_count(max_dimension, "max_dimension", 1L, 100000L)
  max_evaluations <- .gt_check_count(max_evaluations, "max_evaluations", 100L, 100000000L)
  retained <- is.null(data)
  if (retained) data <- fit$data
  if (!is.data.frame(data))
    stop("This fit was stored without its data (retain = list(data = FALSE)); supply data = the modelled data frame.", call. = FALSE)
  parameters <- fit$parameters
  if (!is.numeric(parameters) || !length(parameters))
    stop("This fit does not record its fitted parameters.", call. = FALSE)
  design <- fit$design
  outcomes <- fit$outcomes
  variables <- c(design$object, design$facets)
  columns <- c(variables, outcomes)
  if (!all(columns %in% names(data)))
    stop("data must contain the fitted object, facet and outcome columns.", call. = FALSE)
  # The same preparation the fit ran, from the same declarations, so that the
  # parameters are read in the coordinates they were estimated in.
  call_group <- .gt_laplace_call_group(data, design, fit$covariance_components)
  # The retained frame is the engine's own prepared input: each outcome is
  # already encoded by the fit's resolved families (binary as 0/1 integers,
  # ordinal and nominal as factors over the declared levels). Re-resolving it
  # would read those encodings as new user data and, for a binary outcome with
  # labels other than "0"/"1", refuse the fit's own responses. Data supplied by
  # the caller is new data and still passes the strict resolver.
  resolved <- if (retained) list(data = data[columns], families = fit$families) else
    .gt_resolve_families(data[columns], outcomes, fit$families)
  data <- resolved$data
  prep <- .gt_d_prepare(data, outcomes, resolved$families)
  groups <- lapply(design$term_members, function(members) .gt_d_group(data, members))
  if (!is.null(call_group)) groups[[.GT_CALL_TERM]] <- call_group
  # Limits are applied before anything dense is allocated or solved.
  dimension <- sum(vapply(groups, `[[`, integer(1), "nlevels")) * as.double(prep$q)
  if (dimension > max_dimension)
    stop("The random-effect dimension (", dimension, ") exceeds max_dimension (", max_dimension,
         "). Raise max_dimension only with draws to match; the comparison is a Monte Carlo estimate there.", call. = FALSE)
  dimension <- as.integer(dimension)
  if (method == "auto") method <- if (dimension <= 3L) "quadrature" else "importance"
  if (method == "quadrature" && dimension > 4L)
    stop("Quadrature is limited to four random-effect dimensions (", nodes, "^", dimension,
         " evaluations here); use method = 'importance'.", call. = FALSE)
  evaluations <- if (method == "quadrature") nodes^dimension + (nodes + 5L)^dimension else draws
  if (evaluations > max_evaluations)
    stop("The comparison would need ", format(evaluations, big.mark = ","), " evaluations, more than max_evaluations (",
         format(max_evaluations, big.mark = ","), "); reduce nodes or draws, or raise the budget deliberately.", call. = FALSE)
  if (method == "importance" && is.null(seed))
    stop("Importance sampling needs a seed so that the comparison can be reproduced.", call. = FALSE)
  dcontrol <- .gt_d_control(fit$control$discrete)
  resources <- .gt_laplace_resources(prep$n, prep$q, dimension, method, nodes, draws)
  resources$max_dense_bytes <- dcontrol$max_dense_bytes
  if (!is.finite(resources$total) || resources$total > dcontrol$max_dense_bytes)
    stop("The Laplace check needs an estimated ", .gt_d_format_bytes(resources$total),
      " of dense reconstruction and integration workspace, exceeding max_dense_bytes (",
      .gt_d_format_bytes(dcontrol$max_dense_bytes),
      "). Sparse fitting does not remove this diagnostic's dense memory requirement.", call. = FALSE)
  setup <- .gt_d_covariance_setup(groups, prep$q, fit$covariance, dcontrol, prep$dimensions, prep$blocks)
  if (length(parameters) != length(prep$start) + length(setup$start))
    stop("The fitted parameters do not match this data and design.", call. = FALSE)
  factors <- .gt_d_covariance_factors(parameters[-seq_len(length(prep$start))], setup)
  backend <- .gt_d_dense_backend(groups, factors, prep$n, prep$q)
  mode <- .gt_d_dense_mode(parameters, prep, backend, dcontrol, details = TRUE)
  if (!isTRUE(mode$valid))
    stop("The conditional mode could not be recomputed at the fitted parameters; the fit's own diagnostics apply.", call. = FALSE)
  if (!identical(as.integer(mode$random_dimension), dimension))
    stop("The recomputed random-effect dimension does not match the declared sources.", call. = FALSE)
  W <- backend$W
  baseline <- .gt_d_baseline(parameters, prep)
  u0 <- mode$mode
  eta0 <- baseline + matrix(W %*% u0, prep$n, prep$q)
  H <- .gt_d_dense_evaluate(eta0, parameters, prep, backend)$H
  R <- tryCatch(chol(H), error = function(e) NULL)
  laplace_nll <- mode$nll
  proposal <- if (method == "importance") "defensive_normal_mixture" else "laplace_gaussian_quadrature"
  prior_weight <- if (method == "importance") .GT_LAPLACE_PRIOR_WEIGHT else NA_real_
  proposal_draws <- NULL
  unavailable <- function(reason, count = NA_integer_) structure(list(
    available = FALSE, usable = FALSE, reason = reason,
    laplace_minus2loglik = 2 * laplace_nll, refined_minus2loglik = NA_real_,
    difference = NA_real_, per_observation = NA_real_,
    method = method, random_dimension = dimension, observations = prep$n,
    nodes = if (method == "quadrature") nodes else NA_integer_,
    draws = if (method == "importance") draws else NA_integer_,
    evaluations = evaluations, unavailable_evaluations = count, resources = resources,
    seed = if (method == "importance") seed else NA,
    proposal = proposal, prior_weight = prior_weight, proposal_draws = proposal_draws,
    weight_upper_bound = if (method == "importance") 1 / prior_weight else NA_real_,
    max_importance_weight = NA_real_,
    mc_se = NA_real_, effective_sample_size = NA_real_, refinement_difference = NA_real_,
    stored_minus2loglik = fit$minus2loglik,
    recomputed_agrees = is.numeric(fit$minus2loglik) &&
      abs(2 * laplace_nll - fit$minus2loglik) <= 1e-6 * max(1, abs(fit$minus2loglik)),
    numerically_accepted = isTRUE(fit$numerically_accepted), parameters = parameters,
    scope = .GT_LAPLACE_CHECK_SCOPE), class = "gt_laplace_check")
  if (is.null(R))
    return(unavailable("The Hessian at the conditional mode has no Cholesky factor, so no Gaussian proposal exists."))
  factor_check <- .gt_d_final_factor_check(H, R)
  if (!isTRUE(factor_check$valid))
    return(unavailable(paste0("The Cholesky factor of the Hessian did not solve its own system (backward error ",
      format(factor_check$solve_backward_error, digits = 3), " against bound ",
      format(factor_check$solve_validity_bound, digits = 3), "); no proposal can be trusted.")))
  log_det_scale <- -sum(log(diag(R)))
  weight <- function(z) .gt_laplace_log_weight(z, u0, R, W, baseline, parameters, prep, log_det_scale)
  mc_se <- NA_real_
  effective <- NA_real_
  refinement <- NA_real_
  maximum_weight <- NA_real_
  failed <- 0L
  if (method == "quadrature") {
    integrate_with <- function(order) {
      rule <- .gt_normal_quadrature(order)
      grid <- as.matrix(expand.grid(rep(list(seq_len(order)), dimension)))
      log_terms <- vapply(seq_len(nrow(grid)), function(i) {
        index <- grid[i, ]
        weight(rule$nodes[index]) + sum(log(rule$weights[index]))
      }, numeric(1))
      failed <<- failed + sum(is.na(log_terms))
      if (anyNA(log_terms)) NA_real_ else -.gt_log_sum_exp(log_terms)
    }
    refined_nll <- integrate_with(nodes)
    finer <- integrate_with(nodes + 5L)
    if (failed > 0L)
      return(unavailable(paste0(failed, " of ", evaluations, " quadrature points could not be evaluated."), failed))
    refinement <- finer - refined_nll
    usable <- is.finite(refinement) && abs(2 * refinement) <= 1e-6 * max(1, abs(2 * refined_nll))
    reason <- if (usable) "The refined grid reproduced the estimate." else
      "Refining the grid moved the estimate; increase nodes or use importance sampling."
  } else {
    sample <- .gt_sim_rng(seed, list(
      from_prior = stats::runif(draws) < prior_weight,
      z = matrix(stats::rnorm(draws * dimension), draws, dimension)))
    proposal_draws <- c(laplace_gaussian = sum(!sample$from_prior),
                        standard_normal_prior = sum(sample$from_prior))
    log_terms <- vapply(seq_len(draws), function(i)
      .gt_laplace_mixture_log_weight(sample$z[i, ], sample$from_prior[[i]],
        u0, R, W, baseline, parameters, prep, log_det_scale), numeric(1))
    failed <- sum(is.na(log_terms))
    if (failed > 0L)
      return(unavailable(paste0(failed, " of ", draws, " importance draws could not be evaluated."), failed))
    top <- max(log_terms)
    if (!is.finite(top))
      return(unavailable("No positive finite importance weight could be evaluated.", draws))
    weights <- exp(log_terms - top)
    maximum_weight <- exp(top)
    refined_nll <- -(top + log(mean(weights)))
    mc_se <- stats::sd(weights) / (sqrt(draws) * mean(weights))
    effective <- sum(weights)^2 / sum(weights^2)
    usable <- is.finite(effective) && effective >= max(200, 0.1 * draws)
    reason <- if (usable) "The empirical effective-sample-size screen passed; this is not an accuracy guarantee." else
      "The empirical effective sample size is below 10% of draws or below 200; the diagnostic precision screen failed."
  }
  structure(list(
    available = TRUE, usable = usable, reason = reason,
    laplace_minus2loglik = 2 * laplace_nll,
    refined_minus2loglik = 2 * refined_nll,
    difference = 2 * (laplace_nll - refined_nll),
    per_observation = 2 * (laplace_nll - refined_nll) / prep$n,
    method = method, random_dimension = dimension, observations = prep$n,
    nodes = if (method == "quadrature") nodes else NA_integer_,
    draws = if (method == "importance") draws else NA_integer_,
    evaluations = evaluations, unavailable_evaluations = 0L, resources = resources,
    seed = if (method == "importance") seed else NA,
    proposal = proposal, prior_weight = prior_weight, proposal_draws = proposal_draws,
    weight_upper_bound = if (method == "importance") 1 / prior_weight else NA_real_,
    max_importance_weight = maximum_weight,
    mc_se = 2 * mc_se, effective_sample_size = effective,
    refinement_difference = 2 * refinement,
    stored_minus2loglik = fit$minus2loglik,
    recomputed_agrees = is.numeric(fit$minus2loglik) &&
      abs(2 * laplace_nll - fit$minus2loglik) <= 1e-6 * max(1, abs(fit$minus2loglik)),
    numerically_accepted = isTRUE(fit$numerically_accepted),
    parameters = parameters, scope = .GT_LAPLACE_CHECK_SCOPE), class = "gt_laplace_check")
}

.GT_LAPLACE_CHECK_SCOPE <- paste(
  "The difference estimates the objective's Laplace error at fixed parameters, not bias in the estimates.",
  "Stable quadrature refinement is not an error bound. Defensive-mixture importance weights have",
  "finite moments, but this does not guarantee useful relative precision or calibrated finite-sample",
  "Monte Carlo intervals. The Monte Carlo SE is a delta-method estimate; empirical ESS can miss",
  "poorly sampled regions. Check independent seeds and increasing draw budgets.")

print.gt_laplace_check <- function(x, ..., digits = 6L) {
  if (!is.numeric(digits) || length(digits) != 1L || is.na(digits) || digits < 1 || digits > 22)
    stop("digits must be one integer from 1 to 22.", call. = FALSE)
  .gt_cat_wrap("Laplace approximation check:",
      if (x$method == "quadrature") "adaptive Gauss-Hermite quadrature" else
        if (identical(x$proposal, "defensive_normal_mixture")) "defensive-mixture importance sampling" else "importance sampling")
  cat("Random-effect dimension:", x$random_dimension, "| observations:", x$observations, "\n")
  if (!isTRUE(x$available)) {
    .gt_cat_wrap("Refined estimate unavailable:", x$reason)
    cat("Laplace -2 log likelihood:", format(x$laplace_minus2loglik, digits = digits), "\n")
    .gt_cat_wrap(x$scope)
    return(invisible(x))
  }
  cat("-2 log likelihood: Laplace", format(x$laplace_minus2loglik, digits = digits),
      "| refined", format(x$refined_minus2loglik, digits = digits), "\n")
  cat("Difference (Laplace - refined):", format(x$difference, digits = digits),
      "| per observation:", format(x$per_observation, digits = 3L), "\n")
  if (x$method == "quadrature") {
    cat("Nodes per dimension:", x$nodes, "| refining by 5 nodes moves the estimate by",
        format(x$refinement_difference, digits = 3L), "\n")
  } else {
    if (identical(x$proposal, "defensive_normal_mixture"))
      .gt_cat_wrap("Proposal: 90% Laplace Gaussian and 10% standard-normal prior;",
        "unnormalised weights are bounded by 10.")
    .gt_cat_wrap("Draws:", x$draws, "| seed:", x$seed, "| estimated Monte Carlo SE:", format(x$mc_se, digits = 3L),
        "| empirical effective sample size:", format(x$effective_sample_size, digits = 4L))
  }
  .gt_cat_wrap(if (isTRUE(x$usable)) "Usable:" else "Not usable:", x$reason)
  if (!isTRUE(x$recomputed_agrees))
    .gt_cat_wrap("The recomputed Laplace objective differs from the stored fit value;",
                 "the parameters or data may not be the fitted ones.")
  if (!x$numerically_accepted)
    .gt_cat_wrap("The fit was not numerically accepted; this comparison describes its",
                 "stopping point, not an estimate.")
  .gt_cat_wrap(x$scope)
  invisible(x)
}
