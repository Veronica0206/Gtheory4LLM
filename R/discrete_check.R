# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# A higher-accuracy evaluation of a discrete fit's marginal likelihood at its
# fitted parameters, to measure the first-order Laplace error on that fit.
#
# The Laplace objective is f(u) + u'u/2 + log det(R) at the conditional mode,
# where f is the conditional negative log likelihood of the standardized random
# effects u and R'R is the Hessian of f(u) + u'u/2 there. The marginal
# likelihood it approximates is the integral of exp(-f(u)) phi(u) du. That
# integral is re-evaluated here through the Gaussian the Laplace solution
# already provides, N(mode, (R'R)^-1): by adaptive Gauss-Hermite quadrature in
# few dimensions, and by importance sampling from that Gaussian otherwise, with
# the Monte Carlo error and the effective sample size reported. The check
# measures the error in the objective at fixed parameters; it is not a measure
# of bias in the estimates, and it is the in-package form of the repository's
# discrete-laplace validation study.

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
  x <- x[is.finite(x) | x == -Inf]
  if (!length(x)) return(-Inf)
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

gt_laplace_check <- function(fit, method = c("auto", "quadrature", "importance"), nodes = 20L,
                             draws = 4000L, seed = NULL, max_dimension = 60L, data = NULL) {
  if (!inherits(fit, "gt_fit")) stop("Expected a gt_fit object.", call. = FALSE)
  kinds <- vapply(fit$families, `[[`, character(1), "family")
  if (all(kinds == "gaussian"))
    stop("A Gaussian fit uses an exact likelihood; there is no Laplace approximation to check.", call. = FALSE)
  method <- match.arg(method)
  nodes <- .gt_check_count(nodes, "nodes", 5L, 80L)
  draws <- .gt_check_count(draws, "draws", 100L, 1000000L)
  max_dimension <- .gt_check_count(max_dimension, "max_dimension", 1L, 100000L)
  if (is.null(data)) data <- fit$data
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
  resolved <- .gt_resolve_families(data[columns], outcomes, fit$families)
  data <- resolved$data
  prep <- .gt_d_prepare(data, outcomes, resolved$families)
  groups <- lapply(design$term_members, function(members) .gt_d_group(data, members))
  dcontrol <- .gt_d_control(fit$control$discrete)
  setup <- .gt_d_covariance_setup(groups, prep$q, fit$covariance, dcontrol, prep$dimensions)
  if (length(parameters) != length(prep$start) + length(setup$start))
    stop("The fitted parameters do not match this data and design.", call. = FALSE)
  factors <- .gt_d_covariance_factors(parameters[-seq_len(length(prep$start))], setup)
  backend <- .gt_d_dense_backend(groups, factors, prep$n, prep$q)
  mode <- .gt_d_dense_mode(parameters, prep, backend, dcontrol, details = TRUE)
  if (!isTRUE(mode$valid))
    stop("The conditional mode could not be recomputed at the fitted parameters; the fit's own diagnostics apply.", call. = FALSE)
  dimension <- as.integer(mode$random_dimension)
  if (dimension > max_dimension)
    stop("The random-effect dimension (", dimension, ") exceeds max_dimension (", max_dimension,
         "). Raise max_dimension only with draws to match; the check is a Monte Carlo estimate there.", call. = FALSE)
  if (method == "auto") method <- if (dimension <= 3L) "quadrature" else "importance"
  if (method == "quadrature" && dimension > 4L)
    stop("Quadrature is limited to four random-effect dimensions (", nodes, "^", dimension,
         " evaluations here); use method = 'importance'.", call. = FALSE)
  if (method == "importance" && is.null(seed))
    stop("Importance sampling needs a seed so that the check can be reproduced.", call. = FALSE)
  W <- backend$W
  baseline <- .gt_d_baseline(parameters, prep)
  u0 <- mode$mode
  eta0 <- baseline + matrix(W %*% u0, prep$n, prep$q)
  H <- .gt_d_dense_evaluate(eta0, parameters, prep, backend)$H
  R <- tryCatch(chol(H), error = function(e) NULL)
  if (is.null(R))
    stop("The Hessian at the conditional mode is not positive definite, so no Gaussian proposal exists.", call. = FALSE)
  log_det_scale <- -sum(log(diag(R)))
  # log of the integrand divided by the proposal density, at the point the
  # standard normal draw z maps to: u = mode + R^-1 z.
  log_weight <- function(z) {
    u <- u0 + backsolve(R, z)
    response <- .gt_d_response_kernel(baseline + matrix(W %*% u, prep$n, prep$q), parameters, prep)
    if (!isTRUE(response$valid)) return(-Inf)
    -response$nll - sum(u^2) / 2 + sum(z^2) / 2 + log_det_scale
  }
  laplace_nll <- mode$nll
  mc_se <- NA_real_
  effective <- NA_real_
  refinement <- NA_real_
  evaluations <- NA_integer_
  if (method == "quadrature") {
    integrate_with <- function(order) {
      rule <- .gt_normal_quadrature(order)
      grid <- as.matrix(expand.grid(rep(list(seq_len(order)), dimension)))
      log_terms <- vapply(seq_len(nrow(grid)), function(i) {
        index <- grid[i, ]
        log_weight(rule$nodes[index]) + sum(log(rule$weights[index]))
      }, numeric(1))
      -.gt_log_sum_exp(log_terms)
    }
    reference_nll <- integrate_with(nodes)
    refinement <- integrate_with(nodes + 5L) - reference_nll
    evaluations <- as.integer(nodes^dimension + (nodes + 5L)^dimension)
  } else {
    z <- .gt_sim_rng(seed, matrix(stats::rnorm(draws * dimension), draws, dimension))
    log_terms <- vapply(seq_len(draws), function(i) log_weight(z[i, ]), numeric(1))
    top <- max(log_terms)
    weights <- exp(log_terms - top)
    reference_nll <- -(top + log(mean(weights)))
    mc_se <- stats::sd(weights) / (sqrt(draws) * mean(weights))
    effective <- sum(weights)^2 / sum(weights^2)
    evaluations <- draws
  }
  structure(list(
    laplace_minus2loglik = 2 * laplace_nll,
    reference_minus2loglik = 2 * reference_nll,
    difference = 2 * (laplace_nll - reference_nll),
    per_observation = 2 * (laplace_nll - reference_nll) / prep$n,
    method = method, random_dimension = dimension, observations = prep$n,
    nodes = if (method == "quadrature") nodes else NA_integer_,
    draws = if (method == "importance") draws else NA_integer_,
    evaluations = evaluations, seed = if (method == "importance") seed else NA,
    mc_se = 2 * mc_se, effective_sample_size = effective,
    refinement_difference = 2 * refinement,
    stored_minus2loglik = fit$minus2loglik,
    recomputed_agrees = is.numeric(fit$minus2loglik) &&
      abs(2 * laplace_nll - fit$minus2loglik) <= 1e-6 * max(1, abs(fit$minus2loglik)),
    numerically_accepted = isTRUE(fit$numerically_accepted),
    parameters = parameters,
    scope = paste("Marginal likelihood re-evaluated at the fitted parameters by a higher-accuracy method,",
      "through the Gaussian the Laplace solution provides. The difference measures the first-order",
      "Laplace error in the objective for this fit; it is not a measure of bias in the estimates.",
      "An importance-sampling value is a Monte Carlo estimate; read it with its standard error",
      "and effective sample size.")), class = "gt_laplace_check")
}

print.gt_laplace_check <- function(x, ..., digits = 6L) {
  if (!is.numeric(digits) || length(digits) != 1L || is.na(digits) || digits < 1 || digits > 22)
    stop("digits must be one integer from 1 to 22.", call. = FALSE)
  cat("Laplace approximation check |", x$method, "|", x$random_dimension, "random-effect dimension(s) |",
      x$observations, "observations\n")
  cat("-2 log likelihood: Laplace", format(x$laplace_minus2loglik, digits = digits),
      "| reference", format(x$reference_minus2loglik, digits = digits),
      "| difference", format(x$difference, digits = digits),
      "(", format(x$per_observation, digits = 3L), "per observation )\n")
  if (x$method == "quadrature")
    cat("Adaptive Gauss-Hermite with", x$nodes, "nodes per dimension; refining by 5 nodes moves the reference by",
        format(x$refinement_difference, digits = 3L), "\n")
  else
    cat("Importance sampling:", x$draws, "draws, seed", x$seed, "| Monte Carlo SE",
        format(x$mc_se, digits = 3L), "| effective sample size", format(x$effective_sample_size, digits = 4L), "\n")
  if (!isTRUE(x$recomputed_agrees))
    cat("The recomputed Laplace objective differs from the stored fit value; the parameters or data may not be the fitted ones.\n")
  if (!x$numerically_accepted)
    cat("The fit was not numerically accepted; this check describes its stopping point, not an estimate.\n")
  cat("The difference is the Laplace error in the objective at fixed parameters, not bias in the estimates.\n")
  invisible(x)
}
