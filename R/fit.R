# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Unified independent-function interface; no package namespace is required.

# Fit one or multiple Gaussian or discrete G-theory outcomes
# outcomes: One or multiple outcome column names. Multiple discrete
#   outcomes are modeled jointly through shared source covariance matrices.
# estimator: ML/REML for Gaussian; ML_Laplace for discrete outcomes.
# residual: Gaussian residual covariance structure. Discrete outcomes
#   use their identified observation models, not a fitted Gaussian residual.
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
    result$optimizer_completed <- if (!is.null(result$status))
      identical(as.integer(result$status), 0L) else isTRUE(result$converged)
  if (is.null(result$approximation_adequacy)) result$approximation_adequacy <- "exact_balanced_gaussian_likelihood"
  if (is.null(result$uncertainty)) result$uncertainty <- list(available = FALSE,
    reason = "Parameter standard errors are not implemented for this engine.",
    method = NA_character_, boundary_components = character())
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
  # A compact description of the fitted panel, so that reliability and decision
  # studies remain available after the modelled data is dropped. It records
  # what was observed; it never stands in for data that was checked.
  result$panel <- .gt_panel_summary(resolved$data, design)
  class(result) <- unique(c("gt_fit", class(result)))
  .gt_apply_retention(result, control$retain)
}

# Level counts, row count, and observed cell replication for the fitted panel.
.gt_panel_summary <- function(data, design) {
  dimensions <- c(design$object, design$facets)
  counts <- stats::setNames(vapply(data[dimensions],
    function(x) length(unique(x)), integer(1)), dimensions)
  cells <- table(.gt_tuple_key(data, dimensions))
  list(dimensions = dimensions, counts = counts, rows = nrow(data),
       observed_cells = length(cells),
       cell_replication = sort(unique(as.integer(cells))),
       replicates = design$replicates,
       source = "Recorded when the model was fitted.")
}

# Drop optional components a caller asked not to keep.
#
# Nothing dropped here is used to compute an estimate, a diagnostic decision, a
# coefficient, or a decision study: gt_reliability() and gt_dstudy() work from
# the fitted source covariances, the resolved design, and either the retained
# data or the panel summary recorded above. The record of what was dropped
# stays on the fit, so a later error can say which control removed a component
# rather than reporting it as missing.
.gt_apply_retention <- function(result, retain) {
  if (is.null(retain)) retain <- .gt_retention_defaults
  if (!retain[["data"]]) {
    result$data <- NULL
    # The Gaussian OpenMx model carries the raw outcomes only as summary
    # metadata; the algebra likelihood reads the fixed contrast cross-products
    # and nothing after fitting reads the observations. Dropping the data has
    # to drop those copies too, or a saved fit still holds every observation.
    result$model <- .gt_strip_observations(result$model)
    result$backend_fit <- .gt_strip_observations(result$backend_fit)
    # The recorded call carries whatever the data argument was. Through
    # do.call(), or with the data written inline, that is the whole data frame,
    # unused columns included. Nothing reads the call back, so the argument is
    # replaced by a marker that says what happened rather than a copy.
    if (is.call(result$call) && "data" %in% names(result$call))
      result$call$data <- as.name("<dropped>")
  }
  if (!retain[["session"]]) result$session <- NULL
  if (!retain[["model"]]) {
    result$model <- NULL
    result$backend_fit <- NULL
    # Keep the observed outcome scale: gt_components(correlation = TRUE) uses
    # it, and it is three numbers rather than the factorial cross-products.
    if (is.list(result[["prepared"]]))
      result$prepared <- result[["prepared"]][intersect(names(result[["prepared"]]),
        c("counts", "N", "D", "means", "outcomes", "facets", "observed_variances"))]
    result$conditional_eta <- NULL
    result$conditional_probabilities <- NULL
  }
  if (!retain[["retry_log"]]) {
    result$retry_log <- NULL
    # Drop the bulky per-attempt payloads, never the fields that say what an
    # attempt did: label, error, optimizer code and message, and objective.
    # Index exactly: `$` partial-matches, and a Gaussian fit has no top-level
    # optimizer element for `$optimizer` to reach for.
    strip <- function(attempt) attempt[setdiff(names(attempt),
      c("raw_result", "optimizer_control", "start", "parameters"))]
    if (is.list(result[["diagnostics"]][["attempts"]]))
      result$diagnostics$attempts <- lapply(result[["diagnostics"]][["attempts"]], strip)
    if (is.list(result[["optimizer"]]) && is.list(result[["optimizer"]][["attempt"]]))
      result$optimizer$attempt <- strip(result[["optimizer"]][["attempt"]])
    if (is.list(result[["diagnostics"]][["stability"]]))
      result$diagnostics$stability$tight_parameters <- NULL
  }
  result$retained <- retain
  result
}

.gt_strip_observations <- function(object) {
  if (methods::is(object, "MxModel") && !is.null(object@data)) object@data <- NULL
  object
}

# Extract model source covariance matrices without changing their scale
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

# Inspect engine-specific diagnostics without certifying identification
gt_diagnostics <- function(fit) {
  if (!inherits(fit, "gt_fit")) stop("Expected a gt_fit object.", call. = FALSE)
  status <- .gt_fit_status(fit)
  structure(list(estimator = fit$estimator, engine = if (!is.null(fit$engine)) fit$engine else fit$backend,
       optimizer_completed = fit$optimizer_completed, numerically_accepted = fit$numerically_accepted,
       approximation_adequacy = fit$approximation_adequacy,
       optimizer = status$optimizer, optimization_trials = status$optimization_trials,
       selected_attempt = status$selected_attempt,
       acceptance_failures = status$acceptance_failures,
       attempt_failures = status$attempt_failures,
       boundary_sources = status$boundary_sources, parameter_bounds = status$parameter_bounds,
       standard_errors_available = isTRUE(fit$uncertainty$available),
       standard_errors_unavailable_reason = fit$uncertainty$reason,
       component_standard_errors = fit$component_standard_errors,
       diagnostics = fit$diagnostics, declared_aliases = fit$design$aliased_terms,
       data_validation = fit$design$validation_scope,
       stages = .gt_staged_diagnostics(fit),
       notes = fit$design$notes), class = "gt_diagnostics")
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
  if (isFALSE(d$standard_errors_available) && length(d$standard_errors_unavailable_reason) &&
      !is.na(d$standard_errors_unavailable_reason))
    cat("Standard errors: unavailable -", d$standard_errors_unavailable_reason, "\n")
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
  errors <- object$component_standard_errors
  if (is.data.frame(errors) && nrow(errors) == nrow(variances)) {
    matched <- match(paste(variances$source, variances$trait),
                     paste(errors$component, errors$trait))
    variances$std_error <- errors$std_error[matched]
    variances$at_boundary <- errors$at_boundary[matched]
  }
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
    # An ordinal outcome's location is fixed at zero for identification. It
    # is not an estimate and is not printed as one; coef() already omits it.
    ordinal <- names(x$families)[vapply(x$families, function(f)
      identical(f$family, "ordinal"), logical(1))]
    fixed <- names(x$coefficients) %in% ordinal
    if (any(!fixed)) {
      cat("\nFixed location or contrast estimates:\n")
      print(x$coefficients[!fixed], digits = digits)
    }
    if (any(fixed))
      cat("\nOrdinal location fixed at zero for identification:",
          paste(names(x$coefficients)[fixed], collapse = ", "), "\n")
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
