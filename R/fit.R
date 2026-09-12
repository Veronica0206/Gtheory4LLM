# Unified independent-function interface; no package namespace is required.

#' Fit one or multiple Gaussian or discrete G-theory outcomes
#' @param outcomes One or multiple outcome column names. Multiple discrete
#'   outcomes are modeled jointly through shared source covariance matrices.
#' @param estimator ML/REML for Gaussian; ML_Laplace for discrete outcomes.
#' @param residual Gaussian residual covariance structure. Discrete outcomes
#'   use their identified observation models, not a fitted Gaussian residual.
#' @export
gt_fit <- function(data, outcomes, design, family = gt_family("gaussian"),
                   estimator = NULL, covariance = "unstructured", residual = NULL,
                   control = gt_control()) {
  if (!inherits(design, "gt_design")) stop("Use gt_design() to declare the design.", call. = FALSE)
  if (!is.data.frame(data) || !nrow(data) || anyDuplicated(names(data)))
    stop("data must be a nonempty data frame with unique column names.", call. = FALSE)
  outcomes <- .gt_design_names(outcomes, "outcomes")
  variables <- c(design$object, design$facets)
  if (length(intersect(outcomes, variables))) stop("Outcome and design columns must differ.", call. = FALSE)
  if (!all(c(variables, outcomes) %in% names(data))) stop("Missing outcome or design columns.", call. = FALSE)
  if (!inherits(control, "gt_control")) stop("control must be created by gt_control().", call. = FALSE)
  for (v in variables) {
    x <- data[[v]]
    if (!is.atomic(x) || anyNA(x) || (is.numeric(x) && any(!is.finite(x))) ||
        length(unique(x)) < 2L) stop("Each design variable needs at least two finite, nonmissing levels: ", v, ".", call. = FALSE)
  }
  resolved <- .gt_resolve_families(data[c(variables, outcomes)], outcomes, family)
  families <- resolved$families
  kinds <- vapply(families, `[[`, character(1), "family")
  if (any(kinds == "gaussian") && !all(kinds == "gaussian"))
    stop("Joint Gaussian-discrete outcomes need an additional observation engine; use all Gaussian or jointly discrete outcomes in this first implementation.", call. = FALSE)
  design <- .gt_resolve_design(resolved$data, design, if (all(kinds == "gaussian")) "gaussian" else "discrete")
  if (all(kinds == "gaussian")) {
    if (is.null(estimator)) estimator <- "REML"
    if (is.null(residual)) residual <- "unstructured"
    result <- .gt_fit_gaussian(resolved$data, outcomes, design, estimator,
                               covariance, residual, control$gaussian)
  } else {
    if (is.null(estimator)) estimator <- "ML_Laplace"
    if (!identical(estimator, "ML_Laplace"))
      stop("Discrete fitting currently uses ML_Laplace; Gaussian REML does not apply.", call. = FALSE)
    if (!is.null(residual)) stop("Do not specify a Gaussian residual covariance for discrete outcomes.", call. = FALSE)
    result <- .gt_fit_discrete(resolved$data, outcomes, design, families,
                               covariance = covariance, control = control$discrete)
    if (isFALSE(result$converged))
      warning("Discrete fit did not converge under numerical acceptance checks. Inspect gt_diagnostics(fit); coefficients and D studies are unavailable until the fit is numerically accepted.", call. = FALSE)
  }
  if (is.null(result$numerically_accepted)) result$numerically_accepted <- isTRUE(result$converged)
  if (is.null(result$optimizer_completed))
    result$optimizer_completed <- if (!is.null(result$status)) identical(as.integer(result$status), 0L) else isTRUE(result$converged)
  if (is.null(result$approximation_adequacy)) result$approximation_adequacy <- "exact_balanced_gaussian_likelihood"
  if (is.null(result$engine)) result$engine <- result$backend
  if (is.null(result$nobs)) result$nobs <- nrow(data)
  if (is.null(result$npar)) result$npar <- result$n_model_parameters
  result$loglik <- -result$minus2loglik / 2
  if (is.null(result$coefficients)) result$coefficients <- result$means
  result$families <- families
  result$family <- families
  result$outcomes <- outcomes
  if (is.null(result$design)) result$design <- design
  result$estimator <- estimator
  result$data <- resolved$data
  result$call <- match.call()
  result$N <- nrow(data)
  result$D <- length(outcomes)
  result$control <- control
  class(result) <- unique(c("gt_fit", class(result)))
  result
}

#' Extract model source covariance matrices without changing their scale
#' @export
gt_components <- function(fit, correlation = FALSE, tolerance = 1e-8) {
  if (!inherits(fit, "gt_fit")) stop("Expected a gt_fit object.", call. = FALSE)
  if (!is.logical(correlation) || length(correlation) != 1L || is.na(correlation))
    stop("correlation must be TRUE or FALSE.", call. = FALSE)
  result <- fit$covariance_components
  if (!is.numeric(tolerance) || length(tolerance) != 1L || !is.finite(tolerance) || tolerance < 0)
    stop("tolerance must be a nonnegative finite number.", call. = FALSE)
  if (correlation) {
    scale <- if (!is.null(fit$prepared$observed_variances)) fit$prepared$observed_variances else NULL
    result <- lapply(result, .gt_covariance_correlation, tolerance = tolerance, scale = scale)
    attr(result, "correlation_tolerance") <- tolerance
    attr(result, "boundary_policy") <- "Correlations involving a variance at or below tolerance times the reference variance scale are NA."
  }
  attr(result, "scale") <- if (all(vapply(fit$families, function(f) f$family == "gaussian", logical(1))))
    "Gaussian observed-score covariance" else "identified latent predictor/contrast covariance"
  attr(result, "interpretation") <- "Cross-category contrasts within one categorical outcome are not separate measured outcomes."
  result
}

#' Inspect engine-specific diagnostics without certifying identification
#' @export
gt_diagnostics <- function(fit) {
  if (!inherits(fit, "gt_fit")) stop("Expected a gt_fit object.", call. = FALSE)
  status <- .gt_fit_status(fit)
  list(estimator = fit$estimator, engine = if (!is.null(fit$engine)) fit$engine else fit$backend,
       optimizer_completed = fit$optimizer_completed, numerically_accepted = fit$numerically_accepted,
       approximation_adequacy = fit$approximation_adequacy,
       optimizer = status$optimizer, optimization_trials = status$optimization_trials,
       selected_attempt = status$selected_attempt,
       acceptance_failures = status$acceptance_failures,
       attempt_failures = status$attempt_failures,
       boundary_sources = status$boundary_sources, parameter_bounds = status$parameter_bounds,
       diagnostics = fit$diagnostics, declared_aliases = fit$design$aliased_terms,
       data_validation = fit$design$validation_scope,
       notes = fit$design$notes)
}

# Summarize existing engine decisions only. This never reruns or relaxes an
# acceptance check, nor interprets an unchecked trial as accepted/rejected.
.gt_fit_status <- function(fit) {
  d <- fit$diagnostics
  selected <- d$selected_attempt
  failures <- d$acceptance_failures
  attempts <- data.frame(attempt = character(), reason = character(), stringsAsFactors = FALSE)
  if (is.data.frame(fit$retry_attempts)) {
    history <- fit$retry_attempts
    selected <- as.character(history$attempt[which(history$returned_fit)])
    for (i in seq_len(nrow(history))) {
      reason <- c(history$error[i], history$external_rejection_reason[i])
      if (!is.na(history$status[i]) && history$status[i] != 0L)
        reason <- c(reason, paste("Optimizer status", history$status[i]))
      reason <- unique(reason[!is.na(reason) & nzchar(reason)])
      if (length(reason)) attempts[nrow(attempts) + 1L, ] <-
        list(as.character(history$attempt[i]), paste(reason, collapse = "; "))
    }
    if (isFALSE(fit$numerically_accepted)) {
      failures <- c(if (isFALSE(fit$optimizer_completed)) "optimizer_incomplete",
        if (isFALSE(d$covariance_stationarity$stationary_within_tolerance))
          "covariance_stationarity_failed",
        if (isFALSE(d$independent_likelihood_matches)) "independent_likelihood_mismatch")
    }
  } else if (length(d$attempts)) {
    for (attempt in d$attempts) {
      reason <- attempt$error
      if (!is.null(attempt$optimizer_code) && !is.na(attempt$optimizer_code) &&
          attempt$optimizer_code != 0L)
        reason <- c(reason, paste("Optimizer status", attempt$optimizer_code),
                    attempt$optimizer_message)
      reason <- unique(reason[!is.na(reason) & nzchar(reason)])
      if (length(reason)) attempts[nrow(attempts) + 1L, ] <-
        list(attempt$label, paste(reason, collapse = "; "))
    }
  }
  if (isFALSE(fit$numerically_accepted) && !length(failures))
    failures <- "numerical_acceptance_failed; inspect engine diagnostics"
  boundaries <- if (!is.null(d$boundary_components))
    names(d$boundary_components)[which(d$boundary_components)] else d$boundary_sources
  list(optimizer = if (!is.null(d$optimizer)) d$optimizer else fit$retry_settings$optimizer,
    optimization_trials = if (!is.null(d$optimization_trials)) d$optimization_trials else fit$optimization_trials,
    selected_attempt = if (length(selected)) selected else NA_character_,
    acceptance_failures = failures, attempt_failures = attempts,
    boundary_sources = boundaries, parameter_bounds = d$parameter_bounds)
}

.gt_print_fit_status <- function(d) {
  show <- function(value, missing = "not recorded") {
    if (!length(value) || all(is.na(value))) missing else paste(value, collapse = ", ")
  }
  cat("Optimizer:", show(d$optimizer), "| Attempts:", show(d$optimization_trials),
      "| Selected attempt:", show(d$selected_attempt, "not identified"), "\n")
  cat("Optimizer completed:", show(d$optimizer_completed),
      "| Numerically accepted:", show(d$numerically_accepted), "\n")
  cat("Likelihood approximation:", show(d$approximation_adequacy), "\n")
  if (length(d$acceptance_failures))
    cat("Acceptance failures:", paste(d$acceptance_failures, collapse = "; "), "\n")
  cat("Boundary or nearly singular sources:", show(d$boundary_sources, "none recorded"), "\n")
  if (length(d$parameter_bounds))
    cat("Artificial parameter bounds:", paste(d$parameter_bounds, collapse = ", "), "\n")
  if (nrow(d$attempt_failures)) {
    cat("Attempt errors or rejections (including earlier attempts):\n")
    print(utils::head(d$attempt_failures, 6L), row.names = FALSE, right = FALSE)
    if (nrow(d$attempt_failures) > 6L)
      cat("Further attempt details are available from gt_diagnostics(fit).\n")
  }
  if (isFALSE(d$numerically_accepted))
    cat("Returned estimates are diagnostic only; reliability and D studies are unavailable.\n")
}

print.gt_fit <- function(x, ...) {
  cat("G-theory fit:", length(x$outcomes), "outcome(s),", x$N, "measurement rows\n")
  cat("Families:", paste(vapply(x$families, `[[`, character(1), "family"), collapse = ", "),
      "| Estimator:", x$estimator, "\n")
  cat("Random sources:", length(x$design$terms), "| Instrumentation facets:", length(x$design$facets), "\n")
  .gt_print_fit_status(gt_diagnostics(x))
  cat("Inspect gt_diagnostics(fit) for convergence and approximation details.\n")
  invisible(x)
}

summary.gt_fit <- function(object, ...) {
  components <- gt_components(object)
  variances <- do.call(rbind, lapply(names(components), function(source) {
    value <- components[[source]]
    traits <- rownames(value)
    if (is.null(traits)) traits <- seq_len(nrow(value))
    data.frame(source = source, trait = traits, variance = diag(value), row.names = NULL)
  }))
  structure(list(outcomes = object$outcomes, families = object$families,
       N = object$N, random_sources = length(object$design$terms),
       instrumentation_facets = length(object$design$facets),
       estimator = object$estimator, minus2loglik = object$minus2loglik,
       covariance_components = components, variances = variances,
       means = object$means, coefficients = object$coefficients,
       thresholds = object$thresholds, diagnostics = gt_diagnostics(object)),
    class = "summary.gt_fit")
}

print.summary.gt_fit <- function(x, ..., digits = max(3L, getOption("digits") - 3L)) {
  if (!is.numeric(digits) || length(digits) != 1L || is.na(digits) ||
      !is.finite(digits) || digits < 1 || digits > 22 || digits != as.integer(digits))
    stop("digits must be one integer from 1 to 22.", call. = FALSE)
  cat("G-theory fit summary:", length(x$outcomes), "outcome(s),", x$N, "measurement rows\n")
  cat("Outcomes:", paste(x$outcomes, collapse = ", "), "\n")
  cat("Families:", paste(vapply(x$families, `[[`, character(1), "family"), collapse = ", "),
      "| Estimator:", x$estimator, "\n")
  cat("Random sources:", x$random_sources,
      "| Instrumentation facets:", x$instrumentation_facets, "\n")
  .gt_print_fit_status(x$diagnostics)
  cat("-2 log likelihood:", format(x$minus2loglik, digits = digits), "\n")
  if (!is.null(x$variances) && nrow(x$variances)) {
    cat("\nSource variances (", attr(x$covariance_components, "scale"), "):\n", sep = "")
    print(utils::head(x$variances, 20L), row.names = FALSE, digits = digits)
    if (nrow(x$variances) > 20L)
      cat("Further source variances are available in summary(fit)$variances.\n")
  }
  if (length(x$coefficients)) {
    cat("\nFixed location or contrast estimates:\n")
    print(x$coefficients, digits = digits)
  }
  if (length(x$thresholds)) {
    cat("\nOrdered thresholds:\n")
    print(x$thresholds, digits = digits)
  }
  notes <- unique(c(x$diagnostics$diagnostics$issues, x$diagnostics$notes))
  if (length(notes)) cat("\nNotes:\n", paste(paste0("- ", notes), collapse = "\n"), "\n", sep = "")
  cat("\nUse gt_components(fit) for full covariance matrices and gt_diagnostics(fit) for details.\n")
  invisible(x)
}
