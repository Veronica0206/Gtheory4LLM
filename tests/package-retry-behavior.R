# Characterization of the Gaussian optimizer-retry contract.
#
# This pins what a caller can currently observe about retrying: how many trials
# a budget consumes, which trial is reported as the one that produced the fit,
# how an optimizer failure and an external rejection are distinguished, and
# that a seeded retry is reproducible and leaves the caller's RNG alone.
#
# It exists so that replacing the retry accounting can be judged against
# behaviour rather than against an implementation. Nothing here asserts that
# the current accounting is ideal; one check deliberately records a known
# weakness, and its comment says what a replacement should do instead.
library(Gtheory4LLM)

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
quiet <- function(expr) suppressWarnings(force(expr))

set.seed(31)
panel <- expand.grid(rater = factor(1:4), item = factor(1:20))
panel$score <- rnorm(20, sd = 1.2)[panel$item] + rnorm(4, sd = .5)[panel$rater] +
  rnorm(nrow(panel), sd = .8)
design <- gt_design("item", "rater")
components <- c("item", "rater", "Residual")
# A start six orders of magnitude above the data's scale. Combined with a
# one-iteration budget the optimizer cannot recover from it, which is how this
# test reaches a failing trial without depending on a pathological dataset.
hopeless <- setNames(lapply(components, function(x) matrix(1e6, 1, 1)), components)

fit_with <- function(...) quiet(gt_fit(panel, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, ...))))

RETRY_COLUMNS <- c("attempt", "optimizer", "start_type", "status",
                   "optimizer_success", "minus2loglik", "external_accepted",
                   "external_rejection_reason", "error", "returned_fit")

check_record <- function(fit, label) {
  history <- fit$retry_attempts
  expect(is.data.frame(history), paste(label, "retry history is a data frame"))
  expect(identical(names(history), RETRY_COLUMNS), paste(label, "retry columns"))
  expect(identical(history$attempt, seq_len(nrow(history))),
         paste(label, "attempts are numbered consecutively from one"))
  expect(all(history$optimizer == fit$retry_settings$optimizer),
         paste(label, "one optimizer is used for every trial"))
  expect(nrow(history) == fit$optimization_trials,
         paste(label, "reported trial count matches the recorded trials"))
  expect(nrow(history) <= fit$retry_settings$total_trial_budget,
         paste(label, "trials never exceed the budget"))
  expect(sum(history$returned_fit) <= 1L,
         paste(label, "at most one trial is reported as the returned fit"))
  expect(identical(fit$returned_trial_identified, any(history$returned_fit)),
         paste(label, "returned-trial flag matches the history"))
  expect(identical(gt_diagnostics(fit)$optimization_trials, nrow(history)),
         paste(label, "diagnostics report the recorded trial count"))
  selected <- as.character(history$attempt[which(history$returned_fit)])
  expect(identical(gt_diagnostics(fit)$selected_attempt,
                   if (length(selected)) selected else NA_character_),
         paste(label, "diagnostics name the selected trial"))
  invisible(history)
}

# --- 1. First attempt succeeds: the budget is not spent ----------------------
for (budget in c(0L, 3L, 9L)) {
  fit <- fit_with(extra_tries = budget, retry_seed = 7L)
  history <- check_record(fit, paste0("first-attempt success (extra_tries=", budget, ")"))
  expect(nrow(history) == 1L, "a successful first attempt consumes exactly one trial")
  expect(fit$numerically_accepted && fit$status == 0L, "first-attempt success is accepted")
  expect(identical(history$start_type, "sample_MoM"), "the first trial uses the moment start")
  expect(isTRUE(history$external_accepted[1L]), "the first trial passes external acceptance")
  expect(!nzchar(history$external_rejection_reason[1L]), "an accepted trial records no rejection")
  expect(fit$retry_settings$total_trial_budget == budget + 1L, "budget is extra_tries plus one")
  expect(fit$retry_settings$optimizer_runs == 1L, "success needs one optimizer run")
}

# A supplied start is labelled as such and does not change the accepted answer.
supplied <- fit_with(extra_tries = 2L, retry_seed = 7L,
                     start = setNames(lapply(components, function(x) matrix(.5, 1, 1)), components))
expect(identical(supplied$retry_attempts$start_type[1L], "provided_components"),
       "a supplied start is labelled provided_components")
expect(supplied$numerically_accepted, "a reasonable supplied start is still accepted")

# --- 2. Every attempt fails: the budget is spent and nothing is accepted -----
exhausted <- fit_with(extra_tries = 3L, retry_seed = 7L, max_iterations = 1L, start = hopeless)
history <- check_record(exhausted, "exhausted budget")
expect(nrow(history) == exhausted$retry_settings$total_trial_budget,
       "a rejected fit spends its whole trial budget")
expect(!exhausted$numerically_accepted, "no trial was accepted")
expect(exhausted$status != 0L, "the returned trial carries a nonzero optimizer status")
expect(!any(history$external_accepted), "no trial passed external acceptance")
expect(all(grepl("optimizer status", history$external_rejection_reason)),
       "every rejection names the optimizer status")
expect(!any(history$optimizer_success), "no trial reported optimizer success")
expect(any(grepl("optimizer_incomplete", gt_diagnostics(exhausted)$acceptance_failures)),
       "an incomplete optimizer is reported as an acceptance failure")
expect(nrow(gt_diagnostics(exhausted)$attempt_failures) >= 1L,
       "the failure is visible in the attempt-failure table")

# A single trial reaches the same rejected state without any retrying.
single <- fit_with(extra_tries = 0L, retry_seed = 7L, max_iterations = 1L, start = hopeless)
check_record(single, "single rejected trial")
expect(nrow(single$retry_attempts) == 1L, "extra_tries = 0 permits exactly one trial")
expect(!single$numerically_accepted, "a rejected single trial is not accepted")

# --- 3. Every optimizer run accounts for itself ------------------------------
# Until 0.1.1 the per-trial account was reconstructed from OpenMx's printed
# messages, and a trial whose message block carried no status line was recorded
# with an NA status: the run happened, but what the optimizer returned for it
# was lost. The retry loop now calls the optimizer itself, so a missing status
# would mean the run genuinely produced no fit, and that case also records an
# error. Do not relax this check: an NA status is missing information, not a
# valid status.
history <- exhausted$retry_attempts
expect(nrow(history) > 1L, "the exhausted budget ran more than one optimizer attempt")
expect(is.integer(history$status), "status is stored as an integer column")
expect(all(!is.na(history$status) | nzchar(history$error)),
       "a trial without a status must record why it produced no fit")
expect(all(is.finite(history$minus2loglik[!is.na(history$status)])),
       "every completed run records the objective it reached")
expect(is.logical(history$optimizer_success) && !anyNA(history$optimizer_success),
       "optimizer success is recorded for every attempt")
expect(identical(history$optimizer_success, !is.na(history$status) & history$status == 0L),
       "optimizer success is exactly a zero optimizer status")
expect(identical(history$start_type, c("provided_components",
                                       rep("uniform_perturbation", nrow(history) - 1L))),
       "the first attempt uses the declared start and later attempts are perturbations")

# --- 4. Nearly identical objectives must not create a false selection --------
# Text output can round distinct trials to the same objective. An ambiguous tie
# is left unresolved rather than attributed to an arbitrary member of it.
ambiguous <- exhausted
ambiguous$retry_attempts$minus2loglik[] <- as.numeric(ambiguous$minus2loglik)
ambiguous$retry_attempts$returned_fit[] <- FALSE
expect(is.na(gt_diagnostics(ambiguous)$selected_attempt),
       "an unresolved tie reports no selected attempt")
expect(any(grepl("Selected attempt: not identified",
                 capture.output(print(ambiguous)), fixed = TRUE)),
       "printing says the selected attempt was not identified")

# --- 5. A boundary solution is accepted and reported as a boundary -----------
set.seed(505)
flat <- expand.grid(rater = factor(1:4), item = factor(1:24))
flat$score <- rnorm(24, sd = sqrt(1.4))[flat$item] + rnorm(nrow(flat), sd = sqrt(.55))
boundary <- quiet(gt_fit(flat, "score", gt_design("item", "rater"),
  control = gt_control(gaussian = list(check_hessian = TRUE, retry_seed = 7L))))
check_record(boundary, "boundary solution")
expect(boundary$numerically_accepted, "a boundary optimum is a valid accepted solution")
expect("rater" %in% gt_diagnostics(boundary)$boundary_sources,
       "the zero-variance source is reported as a boundary source")
expect(is.na(boundary$component_standard_errors$std_error[
  boundary$component_standard_errors$component == "rater"]),
  "a boundary component reports no standard error")

# --- 6. Retrying is reproducible and leaves the caller's RNG alone -----------
first <- fit_with(extra_tries = 3L, retry_seed = 11L, max_iterations = 1L, start = hopeless)
again <- fit_with(extra_tries = 3L, retry_seed = 11L, max_iterations = 1L, start = hopeless)
expect(identical(first$retry_attempts, again$retry_attempts),
       "the same seed reproduces the whole retry history")
expect(identical(first$minus2loglik, again$minus2loglik), "the same seed reproduces the likelihood")
expect(identical(first$covariance_components, again$covariance_components),
       "the same seed reproduces the estimates")
other <- fit_with(extra_tries = 3L, retry_seed = 99L, max_iterations = 1L, start = hopeless)
expect(!identical(first$retry_attempts$minus2loglik, other$retry_attempts$minus2loglik),
       "a different seed explores different perturbations")

set.seed(5L)
before <- runif(1L)
invisible(fit_with(extra_tries = 2L, retry_seed = 11L))
set.seed(5L)
expect(identical(before, runif(1L)), "a seeded fit restores the caller's RNG state")

# --- 7. The settings record describes the protocol that was run --------------
settings <- first$retry_settings
for (field in c("optimizer", "extraTries", "start", "retry_seed", "rng", "protocol",
                "acceptance", "total_trial_budget", "optimizer_runs",
                "continuation_perturbation"))
  expect(!is.null(settings[[field]]), paste("retry settings record", field))
expect(identical(settings$acceptance, "optimizer0_covariance_stationarity_likelihood"),
       "the recorded acceptance rule is optimizer status plus stationarity plus likelihood")
expect(settings$total_trial_budget == settings$extraTries + 1L,
       "the budget is the declared extra tries plus the first attempt")
expect(identical(settings$optimizer_runs, nrow(first$retry_attempts)),
       "the recorded optimizer-run count matches the retry history")
expect(length(first$retry_log) > 0L, "a retry log is retained for inspection")

cat("PASS: Gaussian retry accounting, acceptance reporting, determinism, and budget contract.\n")
