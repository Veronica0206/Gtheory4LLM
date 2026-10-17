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
# and is checked rather than trusted. Acceptance has four parts, each recorded:
# lme4's optimizer completed and lme4 raised no convergence warning; the
# package's own stationarity check on lme4's deviance function passed; a
# restart from a different point reproduced the solution; and the exact
# balanced deviance evaluated at the estimates agrees with lme4's criterion,
# which verifies that the two engines fitted the same model and objective (it
# does not by itself show that the estimates maximize it; the other three
# parts are for that). lme4 is only suggested, so the engine says what to
# install when it is absent.

.GT_LME4_ONLY_EXACT <- c("optimizer", "max_iterations", "tolerance", "check_hessian",
                         "threads", "extra_tries", "start")
# lme4's own gradient tolerance (check.conv.grad), applied to the same statistic.
.GT_LME4_GRADIENT_TOL <- 2e-3
# lme4's singularity tolerance: a relative standard deviation this close to its
# lower bound of zero is a boundary parameter.
.GT_LME4_BOUNDARY_TOL <- 1e-4

.gt_lme4_available <- function() requireNamespace("lme4", quietly = TRUE)

# The statistic lme4's convergence check uses: with H = R'R, the largest
# coordinate of min(|R^-1 g|, |g|). NA when the gradient or Hessian is not
# finite or the Hessian has no Cholesky factor, so that a verdict is never
# manufactured from unusable curvature.
.gt_lme4_scaled_gradient <- function(gradient, hessian) {
  if (!is.numeric(gradient) || !length(gradient) || any(!is.finite(gradient)) ||
      !is.matrix(hessian) || !identical(dim(hessian), c(length(gradient), length(gradient))) ||
      any(!is.finite(hessian)))
    return(NA_real_)
  R <- tryCatch(chol(hessian), error = function(e) NULL)
  if (is.null(R)) return(NA_real_)
  scaled <- backsolve(R, gradient)
  if (any(!is.finite(scaled))) return(NA_real_)
  max(pmin(abs(scaled), abs(gradient)))
}

# Central-difference gradient and Hessian of lme4's profiled deviance over the
# interior parameters, and the one-sided derivative at each parameter resting
# on its lower bound of zero.
.gt_lme4_derivatives <- function(devfun, theta, interior, step = 1e-4) {
  k <- length(theta)
  h <- step * pmax(1, abs(theta))
  unit <- function(i) { e <- numeric(k); e[i] <- h[i]; e }
  value <- devfun(theta)
  gradient <- rep(NA_real_, k)
  one_sided <- rep(NA_real_, k)
  for (i in seq_len(k)) {
    if (interior[i]) gradient[i] <- (devfun(theta + unit(i)) - devfun(theta - unit(i))) / (2 * h[i])
    else one_sided[i] <- (devfun(theta + unit(i)) - value) / h[i]
  }
  index <- which(interior)
  hessian <- matrix(NA_real_, k, k)
  for (a in index) for (b in index[index >= a]) {
    hessian[a, b] <- hessian[b, a] <-
      (devfun(theta + unit(a) + unit(b)) - devfun(theta + unit(a) - unit(b)) -
         devfun(theta - unit(a) + unit(b)) + devfun(theta - unit(a) - unit(b))) / (4 * h[a] * h[b])
  }
  list(value = value, gradient = gradient, hessian = hessian, one_sided = one_sided, step = h)
}

# The stationarity verdict under an explicit constrained-optimum policy: the
# scaled gradient over the interior parameters is within lme4's tolerance, and
# no boundary parameter's one-sided derivative points inward, which would mean
# the deviance falls by moving off the bound and the optimizer stopped short.
# A verdict is NA, never TRUE, when the statistic cannot be computed.
.gt_lme4_stationarity <- function(derivatives, interior, tolerance = .GT_LME4_GRADIENT_TOL) {
  index <- which(interior)
  measure <- if (length(index))
    .gt_lme4_scaled_gradient(derivatives$gradient[index], derivatives$hessian[index, index, drop = FALSE])
  else 0
  inward <- derivatives$one_sided[!interior]
  boundary_ok <- !length(inward) || all(is.finite(inward) & inward >= -tolerance)
  verdict <- if (is.na(measure) || (length(inward) && any(!is.finite(inward)))) NA else
    measure <= tolerance && boundary_ok
  list(stationary_within_tolerance = verdict, tolerance = tolerance,
       covariance_scaled_norm = measure, boundary = which(!interior),
       boundary_one_sided_derivatives = inward,
       error = if (is.na(verdict)) "The scaled gradient could not be evaluated: the deviance derivatives are not finite or the interior Hessian has no Cholesky factor." else
         if (!boundary_ok) "A boundary parameter's one-sided derivative points inward; the deviance would fall by moving off the bound." else NULL)
}

# Every acceptance failure, from the recorded facts alone.
.gt_lme4_acceptance <- function(optimizer_code, warnings, stationarity, stable, likelihood_matches) {
  as.character(c(if (!identical(as.integer(optimizer_code), 0L)) "optimizer_incomplete",
    if (length(warnings)) "lme4_convergence_warning",
    if (is.na(stationarity$stationary_within_tolerance)) "stationarity_unavailable" else
      if (!stationarity$stationary_within_tolerance) "covariance_stationarity_failed",
    if (!isTRUE(stable)) "restart_or_tolerance_stability_failed",
    if (!isTRUE(likelihood_matches)) "independent_likelihood_mismatch"))
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
  # lme4's singular-fit message is suppressed on purpose: a source variance of
  # zero is a legitimate boundary estimate, as it is in the exact engine, and
  # the boundary is handled by the stationarity policy below. Every other
  # lme4 warning is recorded and refuses the fit.
  settings <- lme4::lmerControl(check.conv.singular = "ignore")
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
         warnings = unique(warnings), seconds = unname((proc.time() - started)[["elapsed"]]),
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
  # The package's own stationarity check on the function lme4 minimized.
  devfun <- lme4::lmer(formula, data = frame, REML = reml, devFunOnly = TRUE)
  interior <- theta > .GT_LME4_BOUNDARY_TOL
  derivatives <- tryCatch(.gt_lme4_derivatives(devfun, theta, interior), error = function(e)
    list(value = NA_real_, gradient = rep(NA_real_, length(theta)),
         hessian = matrix(NA_real_, length(theta), length(theta)),
         one_sided = rep(NA_real_, length(theta)), error = conditionMessage(e)))
  stationarity <- .gt_lme4_stationarity(derivatives, interior)
  variance_table <- as.data.frame(lme4::VarCorr(model))
  variances <- stats::setNames(variance_table$vcov, variance_table$grp)
  components <- lapply(component_names, function(name) {
    value <- if (name == "Residual") variances[["Residual"]] else
      variances[[groupings[[match(name, spec)]]]]
    matrix(value, 1L, 1L, dimnames = list(outcomes, outcomes))
  })
  names(components) <- component_names
  means <- stats::setNames(as.numeric(lme4::fixef(model))[1L], outcomes)
  # The exact balanced deviance at lme4's estimates: the same likelihood
  # written two ways must agree to rounding. Agreement verifies that the sources
  # were mapped onto the same model and objective; it is not evidence that the
  # estimates maximize it, which is what the three checks above are for.
  exact <- engine$deviance(prepared, components, reml)
  likelihood_tolerance <- 1e-5 * max(1, abs(primary$objective))
  likelihood_difference <- abs(exact - primary$objective)
  likelihood_matches <- is.finite(likelihood_difference) && likelihood_difference <= likelihood_tolerance
  failures <- .gt_lme4_acceptance(primary$optimizer_code, primary$warnings, stationarity, stable,
                                  likelihood_matches)
  converged <- !length(failures)
  optimizer_completed <- identical(primary$optimizer_code, 0L)
  boundary <- stats::setNames(!interior, spec)
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
    bic_source = if (reml) NA_character_ else "ML deviance + log(N) * (covariance parameters + intercept)",
    bic_nobs = if (reml) NA_real_ else N,
    status = primary$optimizer_code, converged = converged,
    numerically_accepted = converged, optimizer_completed = optimizer_completed,
    approximation_adequacy = "exact_balanced_gaussian_likelihood",
    engine = "lme4_gaussian_mixed_model",
    diagnostics = list(issues = failures, boundary_components = boundary,
      hessian_checked = FALSE, standard_errors_available = FALSE,
      standard_errors_unavailable_reason = "The lme4 engine computes no standard errors for source variance components.",
      covariance_stationarity = stationarity,
      deviance_derivatives = derivatives[c("value", "gradient", "hessian", "one_sided", "step", "error")],
      lme4_messages = primary$optimizer_message, lme4_warnings = primary$warnings,
      independent_likelihood_matches = likelihood_matches,
      independent_likelihood = list(exact_balanced_deviance = exact,
        lme4_criterion = primary$objective, difference = likelihood_difference,
        tolerance = likelihood_tolerance,
        scope = "Agreement at the same parameters verifies the model mapping and the objective; it is not evidence that the parameters maximize it."),
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
      acceptance = "Completed lme4 optimizer with no lme4 convergence warning; the package's Cholesky-scaled gradient of lme4's deviance within lme4's tolerance over interior parameters and no inward one-sided derivative at a boundary parameter; a restart reproducing objective and parameters; and agreement of the exact balanced deviance with lme4's criterion at the estimates.",
      approximation = "None: the Gaussian likelihood is exact; lme4 maximizes it by profiling the fixed intercept.",
      warnings = unique(c(primary$warnings, alternative$warnings))),
    optimization_trials = 2L,
    retry_settings = list(optimizer = paste0("lme4 ", model@optinfo$optimizer),
      extraTries = 1L, start = "lme4 default, then twice the fitted relative standard deviations",
      retry_seed = control$retry_seed, protocol = "single_restart_reproduction",
      acceptance = "optimizer0_no_warning_scaled_gradient_restart_exact_likelihood"),
    elapsed_seconds = unname((proc.time() - timing)[["elapsed"]]),
    model = model, session = utils::sessionInfo()), class = "lme4_gtheory_fit")
}
