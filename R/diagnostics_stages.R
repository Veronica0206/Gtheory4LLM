# Staged numerical diagnostics.
#
# One summary shape for every engine, derived only from evidence a fit already
# retained. This never refits, never reads a pass from an absent field, and
# never changes an acceptance decision: a fit that was rejected stays rejected
# and reports which stage failed and why.
#
# The states are deliberately four rather than two. "not_assessed" covers a
# check that did not run or does not apply to this engine; "inconclusive"
# covers a check that ran and neither clearly passed nor clearly failed. A
# Boolean cannot express the difference, and the difference is what a reader
# needs in order to know whether to trust a number.

.GT_STAGE_STATES <- c("passed", "failed", "not_assessed", "inconclusive")

.gt_stage <- function(status, reason, measurements = list()) {
  if (!isTRUE(status %in% .GT_STAGE_STATES))
    stop("Unknown diagnostic stage state: ", status, call. = FALSE)
  measurements <- measurements[!vapply(measurements, is.null, logical(1))]
  structure(list(status = status, reason = reason, measurements = measurements),
            class = "gt_diagnostic_stage")
}

# A retained flag is only a flag when it is a single non-missing logical.
# Anything else is absent evidence, which is not a pass.
.gt_stage_flag <- function(value) {
  if (is.null(value) || length(value) != 1L || !is.logical(value) || is.na(value)) NULL
  else isTRUE(value)
}

.gt_stage_number <- function(value) {
  if (is.null(value) || length(value) != 1L || !is.numeric(value) || !is.finite(value)) NULL
  else as.numeric(value)
}

.gt_stage_selected <- function(diagnostics) {
  attempts <- diagnostics$attempts
  if (!length(attempts) || !is.list(attempts)) return(NULL)
  labels <- vapply(attempts, function(a) if (is.null(a$label)) NA_character_ else a$label,
                   character(1))
  chosen <- which(labels == diagnostics$selected_attempt)
  if (!length(chosen)) return(NULL)
  attempts[[chosen[[1L]]]]
}

.gt_stage_optimizer <- function(fit) {
  d <- fit$diagnostics
  reported <- .gt_stage_flag(fit$optimizer_completed)
  selected <- .gt_stage_selected(d)
  measurements <- list(
    reported_completed = reported,
    optimizer = d$optimizer, optimizer_code = d$optimizer_code,
    optimizer_message = d$optimizer_message,
    attempt_count = if (length(d$attempts)) length(d$attempts) else NULL,
    selected_attempt = d$selected_attempt,
    optimization_trials = d$optimization_trials,
    optimization_trial_budget = d$optimization_trial_budget)
  moved <- NULL
  if (!is.null(selected) && is.numeric(selected$start) && is.numeric(selected$parameters) &&
      length(selected$start) == length(selected$parameters)) {
    moved <- max(abs(selected$parameters - selected$start))
    measurements$max_abs_parameter_change <- moved
    measurements$objective_final <- .gt_stage_number(selected$objective)
  }
  if (is.null(reported))
    return(.gt_stage("not_assessed", "No optimizer completion was recorded.", measurements))
  if (!reported)
    return(.gt_stage("failed", "The optimizer did not report completion.", measurements))
  # Completion means the optimizer said so. A retained attempt that never left
  # its start is reported as a measurement, not by redefining the word: any
  # rejection belongs to the stages that actually test the solution.
  reason <- if (!is.null(moved) && moved == 0)
    "The optimizer reported completion without moving from its starting values."
  else "The optimizer reported completion."
  .gt_stage("passed", reason, measurements)
}

.gt_stage_conditional_mode <- function(fit) {
  d <- fit$diagnostics
  converged <- .gt_stage_flag(d$inner_converged)
  gradient <- .gt_stage_number(d$inner_gradient)
  iterations <- .gt_stage_number(d$inner_iterations)
  # A tightened attempt is solved against min(inner_tol, validation_inner_tol),
  # so reading control$inner_tol alone would compare the retained gradient with
  # a tolerance that never governed it and call a missed solve strict.
  validation <- .gt_stage_number(d$stability$validation_inner_tol)
  tightened <- is.character(d$selected_attempt) && length(d$selected_attempt) == 1L &&
    grepl("_tight$", d$selected_attempt)
  requested <- if (tightened && !is.null(validation)) validation
    else .gt_stage_number(fit$control$inner_tol)
  budget <- .gt_stage_number(fit$control$inner_maxit)
  strict <- if (!is.null(gradient) && !is.null(requested)) gradient <= requested else NULL
  exhausted <- if (!is.null(iterations) && !is.null(budget)) iterations >= budget else NULL
  measurements <- list(
    inner_converged = converged, inner_gradient = gradient,
    inner_iterations = iterations, inner_iteration_budget = budget,
    inner_iteration_budget_exhausted = exhausted,
    inner_requested_tolerance = requested,
    inner_validation_tolerance = validation,
    inner_solve_tightened = tightened,
    # The loop stops at the requested tolerance, but the retained verdict
    # accepts ten times it. A solve can therefore miss what was asked for and
    # still be recorded as converged, which is why both appear here.
    inner_final_acceptance_tolerance = if (!is.null(requested)) requested * 10 else NULL,
    inner_strict_tolerance_met = strict,
    tight_final_mode = .gt_stage_flag(d$tight_final_mode))
  if (is.null(converged))
    return(.gt_stage("not_assessed", "No conditional mode was recorded for this fit.",
                     measurements))
  if (!converged)
    return(.gt_stage("failed", "The conditional mode did not converge.", measurements))
  if (isFALSE(strict) || isTRUE(exhausted)) {
    reason <- paste(c(
      if (isFALSE(strict)) "the final gradient missed the requested tolerance and met only the relaxed final criterion",
      if (isTRUE(exhausted)) "the solve used its entire iteration budget"),
      collapse = "; ")
    return(.gt_stage("inconclusive",
                     paste0("The conditional mode was recorded as converged, but ", reason, "."),
                     measurements))
  }
  .gt_stage("passed", "The conditional mode converged within the requested tolerance.",
            measurements)
}

.gt_stage_stationarity <- function(fit) {
  d <- fit$diagnostics
  record <- if (!is.null(d$outer_stationarity)) d$outer_stationarity else d$covariance_stationarity
  if (is.null(record))
    return(.gt_stage("not_assessed", "No independent stationarity check was recorded."))
  within <- .gt_stage_flag(record$stationary_within_tolerance)
  measurements <- list(
    stationary_within_tolerance = within, tolerance = .gt_stage_number(record$tolerance),
    fixed_effect_scaled_norm = .gt_stage_number(record$fixed_effect_scaled_norm),
    covariance_scaled_norm = .gt_stage_number(record$covariance_scaled_norm),
    finite_difference_disagreement = .gt_stage_number(record$finite_difference_disagreement),
    error = record$error)
  if (!is.null(record$error) && nzchar(record$error))
    return(.gt_stage("failed", record$error, measurements))
  if (is.null(within))
    return(.gt_stage("not_assessed", "Stationarity was not evaluated for this fit.",
                     measurements))
  if (!within)
    return(.gt_stage("failed", "The independent stationarity check exceeded its tolerance.",
                     measurements))
  .gt_stage("passed", "Independent stationarity held within tolerance.", measurements)
}

.gt_stage_restart_stability <- function(fit) {
  d <- fit$diagnostics
  stability <- d$stability
  if (is.null(stability) && is.data.frame(fit$retry_attempts))
    return(.gt_stage("not_assessed",
                     "This engine records restart evidence as retry attempts rather than a stability comparison.",
                     list(attempt_count = nrow(fit$retry_attempts))))
  if (is.null(stability))
    return(.gt_stage("not_assessed", "No restart or tolerance stability comparison was recorded."))
  checked <- .gt_stage_flag(stability$checked)
  stable <- .gt_stage_flag(stability$stable)
  measurements <- list(
    checked = checked, stable = stable,
    alternative_starts = .gt_stage_number(stability$alternative_starts),
    objective_tolerance = .gt_stage_number(stability$objective_tolerance),
    parameter_tolerance = .gt_stage_number(stability$parameter_tolerance),
    relative_objective_differences = stability$relative_objective_differences,
    scaled_parameter_differences = stability$scaled_parameter_differences,
    optimizer_codes = stability$optimizer_codes,
    tight_evaluation_error = stability$primary_tight_evaluation_error)
  # A disabled comparison is not a successful one.
  if (isFALSE(checked))
    return(.gt_stage("not_assessed", "Restart and tolerance stability was not checked.",
                     measurements))
  if (is.null(stable))
    return(.gt_stage("not_assessed", "No stability verdict was recorded.", measurements))
  if (!stable)
    return(.gt_stage("failed", "Restarts or tighter tolerances did not reproduce the retained solution.",
                     measurements))
  if (identical(.gt_stage_number(stability$alternative_starts), 0))
    return(.gt_stage("inconclusive",
                     "Stability was recorded as held, but no alternative start was available to disagree with it.",
                     measurements))
  .gt_stage("passed", "Restarts and tighter tolerances reproduced the retained solution.",
            measurements)
}

.gt_stage_numerical_acceptance <- function(fit) {
  accepted <- .gt_stage_flag(fit$numerically_accepted)
  failures <- fit$diagnostics$acceptance_failures
  measurements <- list(numerically_accepted = accepted,
                       acceptance_failures = if (length(failures)) failures else NULL,
                       parameter_bounds = if (length(fit$diagnostics$parameter_bounds))
                         fit$diagnostics$parameter_bounds else NULL,
                       boundary_sources = if (length(fit$diagnostics$boundary_sources))
                         fit$diagnostics$boundary_sources else NULL)
  if (is.null(accepted))
    return(.gt_stage("not_assessed", "No numerical acceptance decision was recorded.",
                     measurements))
  if (!accepted)
    return(.gt_stage("failed",
                     if (length(failures)) paste("Acceptance failed:", paste(failures, collapse = ", "))
                     else "The fit was not numerically accepted.",
                     measurements))
  .gt_stage("passed", "The fit met every numerical acceptance requirement.", measurements)
}

.gt_stage_approximation <- function(fit) {
  adequacy <- fit$approximation_adequacy
  measurements <- list(approximation_adequacy = adequacy,
                       approximation = fit$diagnostics$approximation)
  if (is.null(adequacy) || !length(adequacy))
    return(.gt_stage("not_assessed",
                     "No approximation assessment applies to this fit.", measurements))
  if (identical(as.character(adequacy), "exact"))
    return(.gt_stage("passed", "The likelihood is exact for this design.", measurements))
  .gt_stage("not_assessed",
            paste0("Approximation adequacy is not established for this fit (", adequacy, ")."),
            measurements)
}

# The staged summary. Numerical stages come first in the order a fit passes
# through them; approximation adequacy is separate because it is a statistical
# question rather than a numerical one, and a numerically perfect fit can still
# rest on an approximation nobody has justified.
.gt_staged_diagnostics <- function(fit) {
  structure(list(
    optimizer = .gt_stage_optimizer(fit),
    conditional_mode = .gt_stage_conditional_mode(fit),
    stationarity = .gt_stage_stationarity(fit),
    restart_stability = .gt_stage_restart_stability(fit),
    numerical_acceptance = .gt_stage_numerical_acceptance(fit),
    approximation_assessment = .gt_stage_approximation(fit)),
    class = "gt_diagnostic_stages")
}

#' @export
print.gt_diagnostic_stages <- function(x, ...) {
  label <- c(optimizer = "optimizer completion", conditional_mode = "conditional mode",
             stationarity = "independent stationarity",
             restart_stability = "restart/tolerance stability",
             numerical_acceptance = "numerical acceptance",
             approximation_assessment = "approximation assessment")
  width <- max(nchar(label))
  for (name in names(x)) {
    stage <- x[[name]]
    cat(sprintf("%-*s  %-12s %s\n", width, label[[name]], stage$status,
                if (is.null(stage$reason)) "" else stage$reason))
  }
  invisible(x)
}

#' @export
print.gt_diagnostic_stage <- function(x, ...) {
  cat(x$status, if (is.null(x$reason)) "" else paste0(" - ", x$reason), "\n", sep = "")
  for (name in names(x$measurements)) {
    value <- x$measurements[[name]]
    if (is.numeric(value) || is.character(value) || is.logical(value))
      cat("  ", name, ": ", paste(format(value, digits = 6), collapse = ", "), "\n", sep = "")
  }
  invisible(x)
}
