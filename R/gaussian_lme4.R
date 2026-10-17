# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# A second Gaussian engine: the declared random sources fitted as random
# intercepts by lme4.
#
# The exact balanced engine remains the default. This engine exists so that a
# user can fit the same model through the mixed-model package they already
# know, and so that the two likelihoods can be compared on one fit. It fits
# one outcome at a time, computes no standard errors for the source variances,
# and is checked rather than trusted: the exact balanced deviance is evaluated
# at its estimates, and a fit the two likelihoods disagree about is refused.
# lme4 is only suggested, so the engine says what to install when it is absent.

.GT_LME4_ONLY_EXACT <- c("optimizer", "max_iterations", "tolerance", "check_hessian",
                         "threads", "extra_tries", "start")

.gt_lme4_available <- function() requireNamespace("lme4", quietly = TRUE)

# Relative gradient at the optimum, lme4's own convergence measure, over the
# coordinates that are not resting on their boundary. A variance held at zero
# by its constraint has a gradient that need not vanish, and reading it as a
# failure to converge would refuse every fit with an empty source.
.gt_lme4_stationarity <- function(model, theta, tolerance = 2e-3) {
  derivs <- model@optinfo$derivs
  if (is.null(derivs) || is.null(derivs$gradient))
    return(list(stationary_within_tolerance = NA, tolerance = tolerance,
                covariance_scaled_norm = NA_real_, boundary = which(theta <= 0),
                error = "lme4 recorded no gradient at the optimum."))
  interior <- which(theta > 0)
  if (!length(interior))
    return(list(stationary_within_tolerance = TRUE, tolerance = tolerance,
                covariance_scaled_norm = 0, boundary = which(theta <= 0), error = NULL))
  gradient <- derivs$gradient[interior]
  hessian <- derivs$Hessian[interior, interior, drop = FALSE]
  scaled <- tryCatch(max(abs(solve(hessian, gradient))), error = function(e) max(abs(gradient)))
  list(stationary_within_tolerance = is.finite(scaled) && scaled <= tolerance,
       tolerance = tolerance, covariance_scaled_norm = scaled,
       boundary = which(theta <= 0), error = NULL)
}

.gt_fit_gaussian_lme4 <- function(data, outcomes, facets, spec, reml, covariance, residual,
                                  prepared, engine, control, call = NULL) {
  if (!.gt_lme4_available())
    stop("The lme4 engine needs the lme4 package: install.packages('lme4').", call. = FALSE)
  if (length(outcomes) != 1L)
    stop("The lme4 engine fits one Gaussian outcome at a time; joint multivariate outcomes use the exact engine (engine = 'openmx').", call. = FALSE)
  .gt_validate_residual_request(residual)
  .gt_validate_covariance_request(covariance, spec)
  component_names <- c(spec, "Residual")
  types <- if (is.null(names(covariance)))
    stats::setNames(rep(covariance, length(component_names)), component_names) else {
      overridden <- stats::setNames(rep("diagonal", length(component_names)), component_names)
      overridden[names(covariance)] <- covariance
      overridden
    }
  types[["Residual"]] <- residual
  # One grouping factor per source, coded from the observed tuples so that
  # user labels can neither collide nor be evaluated. The call source is the
  # batch under one condition: the batch column and every instrumentation facet.
  frame <- data.frame(.gt_y = as.numeric(data[[outcomes]]))
  groupings <- paste0(".gt_source_", seq_along(spec))
  for (k in seq_along(spec)) {
    members <- if (!is.null(call) && identical(spec[[k]], call$term))
      c(call$batch_column, unname(facets)[-seq_len(2L)]) else strsplit(spec[[k]], ":", fixed = TRUE)[[1L]]
    frame[[groupings[[k]]]] <- factor(.gt_tuple_key(data, members))
  }
  formula <- stats::as.formula(paste(".gt_y ~ 1 +", paste0("(1 | ", groupings, ")", collapse = " + ")),
                               env = environment())
  settings <- lme4::lmerControl(check.conv.singular = "ignore", calc.derivs = TRUE)
  attempt <- function(label, start) {
    warnings <- character()
    started <- proc.time()
    model <- withCallingHandlers(
      lme4::lmer(formula, data = frame, REML = reml, start = start, control = settings),
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      })
    theta <- as.numeric(lme4::getME(model, "theta"))
    list(label = label, model = model, theta = theta,
         objective = if (reml) lme4::REMLcrit(model) else as.numeric(-2 * stats::logLik(model)),
         optimizer_code = as.integer(model@optinfo$conv$opt),
         optimizer_message = paste(unlist(model@optinfo$conv$lme4$messages), collapse = "; "),
         warnings = warnings, seconds = unname((proc.time() - started)[["elapsed"]]),
         start = start, parameters = theta, error = NA_character_)
  }
  timing <- proc.time()
  primary <- attempt("primary", NULL)
  # One restart from a deliberately different point. Reproducing the objective
  # and the parameters is the evidence that the retained solution is not an
  # artefact of where the optimizer began.
  alternative <- attempt("restart", ifelse(primary$theta > 0, 2 * primary$theta, 0.5))
  objective_tolerance <- 1e-6
  parameter_tolerance <- 0.02
  relative_objective <- abs(alternative$objective - primary$objective) / max(1, abs(primary$objective))
  scaled_parameter <- max(abs(alternative$theta - primary$theta) / pmax(1, abs(primary$theta)))
  stable <- is.finite(relative_objective) && relative_objective <= objective_tolerance &&
    is.finite(scaled_parameter) && scaled_parameter <= parameter_tolerance
  model <- primary$model
  theta <- primary$theta
  variance_table <- as.data.frame(lme4::VarCorr(model))
  variances <- stats::setNames(variance_table$vcov, variance_table$grp)
  components <- lapply(component_names, function(name) {
    value <- if (name == "Residual") variances[["Residual"]] else
      variances[[groupings[[match(name, spec)]]]]
    matrix(value, 1L, 1L, dimnames = list(outcomes, outcomes))
  })
  names(components) <- component_names
  means <- stats::setNames(as.numeric(lme4::fixef(model))[1L], outcomes)
  # The exact balanced deviance at lme4's estimates. The two are the same
  # likelihood written two ways, so they must agree to rounding; a mismatch
  # means the sources were not mapped onto the same model and refuses the fit.
  exact <- engine$deviance(prepared, components, reml)
  likelihood_tolerance <- 1e-5 * max(1, abs(primary$objective))
  likelihood_difference <- abs(exact - primary$objective)
  likelihood_matches <- is.finite(likelihood_difference) && likelihood_difference <= likelihood_tolerance
  stationarity <- .gt_lme4_stationarity(model, theta)
  optimizer_completed <- identical(primary$optimizer_code, 0L)
  boundary <- stats::setNames(vapply(spec, function(name) components[[name]][1L, 1L] <= 0, logical(1)), spec)
  failures <- c(if (!optimizer_completed) "optimizer_incomplete",
                if (!isTRUE(stationarity$stationary_within_tolerance)) "covariance_stationarity_failed",
                if (!stable) "restart_or_tolerance_stability_failed",
                if (!likelihood_matches) "independent_likelihood_mismatch")
  converged <- !length(failures)
  N <- prepared$N
  n_variance_parameters <- length(component_names)
  total_parameters <- n_variance_parameters + 1L
  attempts <- lapply(list(primary, alternative), function(a)
    a[c("label", "optimizer_code", "optimizer_message", "warnings", "seconds", "start",
        "parameters", "objective", "error")])
  structure(list(
    spec = spec, groups = spec, outcomes = outcomes, facets = prepared$facets,
    counts = prepared$counts, N = N, D = 1L, means = means,
    reml = reml, covariance_types = types, covariance_components = components,
    correlations = lapply(components, engine$correlation, scale = prepared$observed_variances),
    estimates = list(theta = theta, intercept = means),
    minus2loglik = primary$objective, loglik = -primary$objective / 2,
    uncertainty = list(available = FALSE,
      reason = "The lme4 engine computes no standard errors for source variance components; refit with the exact engine (engine = 'openmx') for intervals.",
      method = NA_character_, boundary_components = names(boundary)[boundary]),
    component_standard_errors = NULL,
    n_variance_parameters = n_variance_parameters, n_parameters = total_parameters,
    n_profiled_means = 1L, n_model_parameters = total_parameters,
    n_likelihood_parameters = if (reml) n_variance_parameters else total_parameters,
    AIC = if (reml) NA_real_ else primary$objective + 2 * total_parameters,
    BIC = if (reml) NA_real_ else primary$objective + log(N) * total_parameters,
    ml_AIC = if (reml) NA_real_ else primary$objective + 2 * total_parameters,
    ml_BIC_response_vectors = if (reml) NA_real_ else primary$objective + log(N) * total_parameters,
    ml_BIC_scalar_scores = if (reml) NA_real_ else primary$objective + log(N) * total_parameters,
    legacy_AIC = NA_real_, legacy_BIC = NA_real_,
    reml_AIC_variance_parameters = if (reml) primary$objective + 2 * n_variance_parameters else NA_real_,
    reml_BIC_response_vectors_variance_parameters = if (reml)
      primary$objective + log(N) * n_variance_parameters else NA_real_,
    reml_BIC_scalar_scores_variance_parameters = if (reml)
      primary$objective + log(N) * n_variance_parameters else NA_real_,
    information_criteria = list(likelihood = if (reml) "REML" else "ML",
      generic = if (reml) "The AIC and BIC elements are NA for REML; AIC() and BIC() use the restricted likelihood with covariance parameters only" else
        "AIC counts covariance parameters and the intercept; BIC uses N response vectors",
      legacy = "Not recorded by the lme4 engine",
      bic_response_vectors = N, bic_scalar_scores = N,
      caution = "One outcome: response vectors and scalar scores coincide"),
    status = primary$optimizer_code, converged = converged,
    numerically_accepted = converged, optimizer_completed = optimizer_completed,
    approximation_adequacy = "exact_balanced_gaussian_likelihood",
    engine = "lme4_gaussian_mixed_model",
    diagnostics = list(issues = failures, boundary_components = boundary,
      hessian_checked = FALSE, standard_errors_available = FALSE,
      standard_errors_unavailable_reason = "The lme4 engine computes no standard errors for source variance components.",
      covariance_stationarity = stationarity,
      independent_likelihood_matches = likelihood_matches,
      independent_likelihood = list(exact_balanced_deviance = exact,
        lme4_criterion = primary$objective, difference = likelihood_difference,
        tolerance = likelihood_tolerance),
      stability = list(checked = TRUE, stable = stable, alternative_starts = 1L,
        objective_tolerance = objective_tolerance, parameter_tolerance = parameter_tolerance,
        relative_objective_differences = relative_objective,
        scaled_parameter_differences = scaled_parameter,
        optimizer_codes = c(primary$optimizer_code, alternative$optimizer_code)),
      attempts = attempts, selected_attempt = "primary",
      optimizer = paste0("lme4 ", model@optinfo$optimizer),
      optimizer_code = primary$optimizer_code, optimizer_message = primary$optimizer_message,
      optimization_trials = 2L, optimization_trial_budget = 2L,
      acceptance_failures = failures,
      acceptance = "Completed optimizer, lme4 relative gradient within tolerance over interior parameters, a restart reproducing objective and parameters, and agreement with the exact balanced deviance at the estimates.",
      approximation = "None: the Gaussian likelihood is exact; lme4 maximizes it by profiling the fixed intercept.",
      warnings = unique(c(primary$warnings, alternative$warnings))),
    optimization_trials = 2L,
    retry_settings = list(optimizer = paste0("lme4 ", model@optinfo$optimizer),
      extraTries = 1L, start = "lme4 default, then twice the fitted relative standard deviations",
      retry_seed = control$retry_seed, protocol = "single_restart_reproduction",
      acceptance = "optimizer0_stationarity_restart_exact_likelihood"),
    elapsed_seconds = unname((proc.time() - timing)[["elapsed"]]),
    model = model, session = utils::sessionInfo()), class = "lme4_gtheory_fit")
}
