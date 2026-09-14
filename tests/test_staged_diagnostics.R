# Run from the project directory with Rscript tests/test_staged_diagnostics.R.
#
# The staged summary must make an existing rejection legible without changing
# it. These checks therefore assert two things everywhere: that the reported
# stage matches the retained evidence, and that absent evidence never reads as
# a pass.
source(file.path("R", "design.R"))
source(file.path("R", "discrete_response.R"))
source(file.path("R", "discrete_dense.R"))
source(file.path("R", "discrete_mode.R"))
source(file.path("R", "discrete.R"))
source(file.path("R", "diagnostics_stages.R"))

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
status <- function(fit, stage) .gt_staged_diagnostics(fit)[[stage]]$status
measure <- function(fit, stage, name) .gt_staged_diagnostics(fit)[[stage]]$measurements[[name]]

base_fit <- function(...) {
  fit <- list(optimizer_completed = TRUE, numerically_accepted = TRUE,
              approximation_adequacy = "not_assessed_first_order_laplace",
              control = list(inner_tol = 1e-7, inner_maxit = 60L),
              diagnostics = list(
                inner_converged = TRUE, inner_gradient = 1e-12, inner_iterations = 7L,
                tight_final_mode = TRUE, selected_attempt = "primary",
                optimizer = "L-BFGS-B", optimizer_code = 0L,
                optimizer_message = "CONVERGENCE",
                attempts = list(list(label = "primary", start = c(1, 2),
                                     parameters = c(1.5, 2.5), objective = 10)),
                outer_stationarity = list(stationary_within_tolerance = TRUE, tolerance = 1e-3),
                stability = list(checked = TRUE, stable = TRUE, alternative_starts = 1L),
                acceptance_failures = NULL))
  modifyList(fit, list(...))
}

# --- Every stage passes when every check passed -------------------------------
healthy <- .gt_staged_diagnostics(base_fit())
for (stage in c("optimizer", "conditional_mode", "stationarity", "restart_stability",
                "numerical_acceptance"))
  expect(identical(healthy[[stage]]$status, "passed"), paste(stage, "passes on a clean fit"))
# First-order Laplace adequacy is never claimed from numerical success alone.
expect(identical(healthy$approximation_assessment$status, "not_assessed"),
       "approximation adequacy is not asserted by numerical success")

# --- The issue #14 pattern ----------------------------------------------------
# Reported completion, zero movement, rejected. The summary must convey all
# three without contradiction and without redefining optimizer completion.
stuck_diagnostics <- modifyList(base_fit()$diagnostics, list(
  inner_gradient = 8.94735337902963e-09, inner_iterations = 60L,
  outer_stationarity = list(stationary_within_tolerance = FALSE, tolerance = 1e-3,
                            error = "invalid conditional mode."),
  stability = list(checked = TRUE, stable = FALSE, alternative_starts = 1L),
  acceptance_failures = c("validation_computation_failed", "outer_stationarity_failed")))
stuck <- base_fit(numerically_accepted = FALSE,
                  control = list(inner_tol = 1e-7, inner_maxit = 60L),
                  diagnostics = stuck_diagnostics)
# Assigned after construction rather than through modifyList: attempts is an
# unnamed list, and modifyList iterates names, so every merge on the way here
# would silently keep the original attempt.
stuck$diagnostics$attempts <- list(list(label = "primary_tight", start = c(1, 2),
                                        parameters = c(1, 2), objective = 202.744))
stuck$diagnostics$selected_attempt <- "primary_tight"
stuck$diagnostics$stability$validation_inner_tol <- 1e-9
expect(identical(status(stuck, "optimizer"), "passed"),
       "optimizer completion is reported as the optimizer reported it")
expect(identical(measure(stuck, "optimizer", "max_abs_parameter_change"), 0),
       "zero movement is exposed as a measurement")
expect(grepl("without moving", .gt_staged_diagnostics(stuck)$optimizer$reason),
       "the reason says the retained attempt did not move")
expect(identical(status(stuck, "conditional_mode"), "inconclusive"),
       "a mode that missed its tolerance and used its whole budget is inconclusive")
expect(isFALSE(measure(stuck, "conditional_mode", "inner_strict_tolerance_met")),
       "the strict tolerance is reported as unmet")
expect(isTRUE(measure(stuck, "conditional_mode", "inner_iteration_budget_exhausted")),
       "budget exhaustion is reported")
expect(identical(status(stuck, "stationarity"), "failed"), "stationarity failure is reported")
expect(identical(status(stuck, "restart_stability"), "failed"), "instability is reported")
expect(identical(status(stuck, "numerical_acceptance"), "failed"), "rejection is reported")

# --- A tight final mode retained under a coarse attempt label -----------------
# The engine can evaluate a coarse candidate under the validation controls and
# retain that candidate, so the selected attempt is named "primary" while the
# final mode really was solved at the validation tolerance. Reading the label
# would report the ordinary tolerance and call that solve loose.
coarse_label <- base_fit(diagnostics = modifyList(base_fit()$diagnostics, list(
  tight_final_mode = TRUE, selected_attempt = "primary",
  inner_gradient = 8.9e-09, inner_iterations = 60L,
  stability = list(checked = TRUE, stable = TRUE, alternative_starts = 1L,
                   validation_inner_tol = 1e-9, inner_tol = 1e-7, inner_maxit = 60L))))
expect(identical(measure(coarse_label, "conditional_mode", "inner_requested_tolerance"), 1e-9),
       "a tight final mode uses the validation tolerance even under a coarse attempt label")
expect(isTRUE(measure(coarse_label, "conditional_mode", "inner_solve_tightened")),
       "tightening is read from retained evidence, not from the attempt name")
expect(isFALSE(measure(coarse_label, "conditional_mode", "inner_strict_tolerance_met")),
       "against the validation tolerance that gradient is not strict")
# And an untightened solve keeps the ordinary tolerance.
loose <- base_fit(diagnostics = modifyList(base_fit()$diagnostics, list(
  tight_final_mode = FALSE, selected_attempt = "primary_tight",
  stability = list(checked = TRUE, stable = TRUE, alternative_starts = 1L,
                   validation_inner_tol = 1e-9, inner_tol = 1e-7, inner_maxit = 60L))))
expect(identical(measure(loose, "conditional_mode", "inner_requested_tolerance"), 1e-7),
       "a label ending in _tight does not override retained evidence to the contrary")

# --- Absent evidence is never a pass ------------------------------------------
for (field in c("inner_converged", "outer_stationarity", "stability")) {
  # Removed after construction: modifyList merges into the defaults, so
  # dropping a field on the way in would quietly restore it.
  bare <- base_fit()
  bare$diagnostics[[field]] <- NULL
  stage <- c(inner_converged = "conditional_mode", outer_stationarity = "stationarity",
             stability = "restart_stability")[[field]]
  expect(identical(status(bare, stage), "not_assessed"),
         paste("a missing", field, "reads as not_assessed, not passed"))
}
# An old fit object carrying none of these fields still summarizes.
old <- list(optimizer_completed = NULL, numerically_accepted = NULL, diagnostics = list())
summary_old <- .gt_staged_diagnostics(old)
expect(all(vapply(summary_old, function(s) s$status, character(1)) == "not_assessed"),
       "a fit with no retained diagnostics reports not_assessed throughout")

# --- A disabled check is not a successful one ---------------------------------
disabled <- base_fit(diagnostics = modifyList(base_fit()$diagnostics,
  list(stability = list(checked = FALSE, stable = TRUE, alternative_starts = 0L))))
expect(identical(status(disabled, "restart_stability"), "not_assessed"),
       "a disabled stability comparison is not reported as passed")
none <- base_fit(diagnostics = modifyList(base_fit()$diagnostics,
  list(stability = list(checked = TRUE, stable = TRUE, alternative_starts = 0L))))
expect(identical(status(none, "restart_stability"), "inconclusive"),
       "stability with no alternative start to disagree is inconclusive")

# --- Absent evidence is never a pass, including in the middle of a stage -----
# These three all reported "passed" once. Each is a case where the fit claims a
# result but the evidence needed to check that claim was not retained, which is
# exactly where a diagnostic summary is most tempted to flatter the fit.
converged_unverifiable <- base_fit()
converged_unverifiable$control <- list()
converged_unverifiable$diagnostics$inner_gradient <- NULL
converged_unverifiable$diagnostics$stability$inner_tol <- NULL
expect(identical(status(converged_unverifiable, "conditional_mode"), "inconclusive"),
       "a converged mode whose tolerance evidence is missing is inconclusive, not passed")

verdict_without_check <- base_fit()
verdict_without_check$diagnostics$stability <-
  list(stable = TRUE, alternative_starts = 1L)
expect(identical(status(verdict_without_check, "restart_stability"), "inconclusive"),
       "a stability verdict without evidence the comparison ran is inconclusive")

# --- The adequacy labels fits actually record --------------------------------
# Nothing in the package ever writes the bare string "exact", so matching only
# that reported every genuinely exact likelihood as unassessed.
for (label in c("exact_balanced_gaussian_likelihood", "exact_no_random_variation", "exact")) {
  exact <- list(approximation_adequacy = label, diagnostics = list())
  expect(identical(.gt_staged_diagnostics(exact)$approximation_assessment$status, "passed"),
         paste("an exact likelihood recorded as", label, "is reported as exact"))
}
approximate <- list(approximation_adequacy = "not_assessed_first_order_laplace",
                    diagnostics = list())
expect(identical(.gt_staged_diagnostics(approximate)$approximation_assessment$status,
                 "not_assessed"),
       "first-order Laplace adequacy is still never claimed")

# --- Acceptance is reported, never decided ------------------------------------
# The summary reads numerically_accepted; it must not compute its own verdict.
for (accepted in c(TRUE, FALSE)) {
  fit <- base_fit(numerically_accepted = accepted,
                  diagnostics = modifyList(base_fit()$diagnostics,
                    list(acceptance_failures = if (accepted) NULL else "outer_stationarity_failed")))
  expect(identical(status(fit, "numerical_acceptance"), if (accepted) "passed" else "failed"),
         "the acceptance stage mirrors the retained decision")
  expect(identical(fit$numerically_accepted, accepted),
         "building the summary does not alter the fit's acceptance")
}
# A rejected fit whose every other stage passed is still rejected.
contradiction <- base_fit(numerically_accepted = FALSE,
  diagnostics = modifyList(base_fit()$diagnostics, list(acceptance_failures = "stability_failed")))
expect(identical(status(contradiction, "numerical_acceptance"), "failed"),
       "no combination of passing stages promotes a rejected fit")

# --- Gaussian fits use the same schema ----------------------------------------
gaussian <- list(optimizer_completed = TRUE, numerically_accepted = TRUE,
                 approximation_adequacy = "exact",
                 retry_attempts = data.frame(attempt = 1L, returned_fit = TRUE),
                 diagnostics = list(covariance_stationarity =
                                      list(stationary_within_tolerance = TRUE, tolerance = 1e-3)))
gs <- .gt_staged_diagnostics(gaussian)
expect(identical(names(gs), names(healthy)), "both engines report the same stage names")
expect(identical(gs$stationarity$status, "passed"), "Gaussian stationarity is read from its own record")
expect(identical(gs$approximation_assessment$status, "passed"),
       "an exact likelihood needs no approximation allowance")
expect(identical(gs$conditional_mode$status, "not_assessed"),
       "an exact Gaussian fit has no conditional mode to assess")

# --- A real discrete fit ------------------------------------------------------
set.seed(404)
panel <- expand.grid(item = seq_len(12), rater = seq_len(3))
panel$y <- rbinom(nrow(panel), 1L, plogis(rnorm(12, sd = .8)[panel$item]))
design <- list(object = "item", facets = "rater", term_members = list(item = "item", rater = "rater"))
real <- .gt_fit_discrete(panel, "y", design,
                         list(list(family = "binary", link = "logit", levels = c("0", "1"),
                                   reference = NULL)),
                         covariance = "diagonal", control = list(maxit = 120L))
live <- .gt_staged_diagnostics(real)
expect(all(vapply(live, function(s) s$status %in% .GT_STAGE_STATES, logical(1))),
       "every stage of a real fit reports a recognized state")
expect(identical(live$numerical_acceptance$measurements$numerically_accepted,
                 isTRUE(real$numerically_accepted)),
       "the real fit's acceptance is mirrored exactly")
if (isFALSE(real$numerically_accepted))
  expect(any(vapply(live, function(s) identical(s$status, "failed"), logical(1))),
         "a rejected real fit names at least one failed stage")

# --- A public fit, not only a direct engine call ------------------------------
# gt_fit() stores the gt_control object, whose discrete settings are empty
# unless the caller set one. Exercising only .gt_fit_discrete() would leave the
# public path untested, and it is the path where these values were being lost.
source("load_functions.R")
set.seed(808)
public <- expand.grid(item = seq_len(10), rater = seq_len(3))
public$y <- rbinom(nrow(public), 1L, plogis(rnorm(10, sd = 0.8)[public$item]))
public_fit <- gt_fit(public, "y", gt_design("item", "rater", full_cell = FALSE),
                     gt_family("binary"))
expect(is.null(public_fit$control$inner_tol),
       "the public fit really does not expose inner_tol on its control")
public_stages <- gt_diagnostics(public_fit)$stages
mode_measurements <- public_stages$conditional_mode$measurements
for (name in c("inner_requested_tolerance", "inner_final_acceptance_tolerance",
               "inner_iteration_budget", "inner_iterations",
               "inner_strict_tolerance_met", "inner_iteration_budget_exhausted"))
  expect(!is.null(mode_measurements[[name]]),
         paste0("a public discrete fit still reports ", name))
expect(identical(mode_measurements$inner_final_acceptance_tolerance,
                 mode_measurements$inner_requested_tolerance * 10),
       "the relaxed final criterion is reported relative to the governing tolerance")
expect(public_stages$conditional_mode$status %in% .GT_STAGE_STATES,
       "the public fit reports a recognized conditional-mode state")

cat("PASS: staged diagnostics report retained evidence without changing any acceptance decision.\n")
