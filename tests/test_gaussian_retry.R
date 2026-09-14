# Run from the project root: Rscript tests/test_gaussian_retry.R
# Unit tests for the Gaussian optimizer-retry controller.
#
# The controller takes the optimizer and the acceptance check as arguments, so
# every path can be driven deterministically with stand-ins: an attempt that
# fails and is followed by one that succeeds, a budget spent without any
# acceptance, an optimizer that throws, an acceptance check that throws, and a
# perturbation that cannot be formed. Reaching those states through real data
# would mean relying on a pathological dataset behaving pathologically forever.
#
# tests/package-retry-behavior.R covers the same controller through the public
# interface with the real optimizer. Neither replaces the other.
source("R/gaussian_retry.R")

failures <- character()
check <- function(condition, label) {
  ok <- isTRUE(tryCatch(condition, error = function(e) {
    failures <<- c(failures, paste0(label, " (error: ", conditionMessage(e), ")"))
    NA
  }))
  if (!ok && !length(grep(label, failures, fixed = TRUE)))
    failures <<- c(failures, label)
  invisible(ok)
}
expect_condition <- function(expr, class, label) {
  condition <- tryCatch({ force(expr); NULL }, condition = identity)
  check(inherits(condition, class), label)
  condition
}

# A stand-in for what mxRun returns: only the fields the controller reads.
fitted_model <- function(status, objective, tag = NULL)
  structure(list(output = list(status = list(code = status), fit = objective), tag = tag),
            class = "MxModel")

# An optimizer that returns the supplied results in order and records its calls.
scripted_run <- function(...) {
  results <- list(...)
  calls <- 0L
  function(model, silent = TRUE) {
    calls <<- calls + 1L
    outcome <- results[[min(calls, length(results))]]
    if (is.character(outcome)) stop(outcome, call. = FALSE)
    outcome
  }
}

accepted <- function(model) list(accepted = TRUE, reason = "",
                                 components = list(Residual = matrix(1)))
rejected <- function(reason) function(model)
  list(accepted = FALSE, reason = reason, components = list(Residual = matrix(1)))
# Acceptance driven by the optimizer status, as the real check is.
status_based <- function(model) {
  status <- model$output$status$code
  if (identical(status, 0L))
    list(accepted = TRUE, reason = "", components = list(Residual = matrix(1)))
  else list(accepted = FALSE, reason = paste("OpenMx optimizer status", status),
            components = list(Residual = matrix(1)))
}
count_jitter <- function() {
  calls <- 0L
  list(fn = function(model) { calls <<- calls + 1L; model },
       count = function() calls)
}

retry <- function(run, assess, extra_tries = 3L, jitter = function(model) model,
                  start_label = "sample_MoM")
  .gt_gaussian_retry(fitted_model(NA_integer_, NA_real_), "CSOLNP", extra_tries,
                     1e-12, 100L, start_label, TRUE, assess, run = run, jitter = jitter)

# --- The first attempt succeeds --------------------------------------------
jitter <- count_jitter()
result <- retry(scripted_run(fitted_model(0L, 100)), accepted, jitter = jitter$fn)
check(nrow(result$attempts) == 1L, "an accepted first attempt consumes one trial")
check(result$optimizer_runs == 1L, "one optimizer run is reported")
check(result$budget == 4L, "the budget is extra_tries plus one")
check(jitter$count() == 0L, "no perturbation is formed when the first attempt is accepted")
check(isTRUE(result$attempts$returned_fit[1L]), "the accepted attempt is the returned fit")
check(isTRUE(result$attempts$external_accepted[1L]), "external acceptance is recorded")
check(identical(result$attempts$start_type, "sample_MoM"), "the declared start is labelled")
check(isTRUE(result$attempts$optimizer_success[1L]), "optimizer success is recorded")
check(identical(result$assessment$accepted, TRUE), "the assessment is returned to the caller")

# --- A failed attempt followed by a successful one --------------------------
jitter <- count_jitter()
result <- retry(scripted_run(fitted_model(6L, 250), fitted_model(0L, 120)),
                status_based, jitter = jitter$fn)
check(nrow(result$attempts) == 2L, "retrying stops at the first accepted attempt")
check(jitter$count() == 1L, "exactly one perturbation is formed between two attempts")
check(identical(result$attempts$status, c(6L, 0L)), "each attempt records its own status")
check(identical(result$attempts$optimizer_success, c(FALSE, TRUE)),
      "optimizer success follows the status of each attempt")
check(identical(result$attempts$start_type, c("sample_MoM", "uniform_perturbation")),
      "a retry is labelled as a perturbation of the previous best")
check(identical(result$attempts$returned_fit, c(FALSE, TRUE)),
      "the accepted attempt, not the first one, is the returned fit")
check(grepl("status 6", result$attempts$external_rejection_reason[1L]),
      "the rejected attempt keeps its reason")
check(!nzchar(result$attempts$external_rejection_reason[2L]),
      "the accepted attempt records no rejection reason")
check(result$model$output$fit == 120, "the accepted model is returned")

# --- The whole budget is spent without acceptance ---------------------------
jitter <- count_jitter()
result <- retry(scripted_run(fitted_model(6L, 250, "a"), fitted_model(6L, 90, "b"),
                             fitted_model(5L, 400, "c"), fitted_model(6L, 300, "d")),
                status_based, jitter = jitter$fn)
check(nrow(result$attempts) == 4L, "an unaccepted fit spends the whole budget")
check(jitter$count() == 3L, "a perturbation precedes every retry and no more")
check(identical(result$attempts$returned_fit, c(FALSE, TRUE, FALSE, FALSE)),
      "the lowest objective is returned when nothing is accepted")
check(identical(result$model$tag, "b"), "the returned model is the best candidate")
check(!any(result$attempts$external_accepted), "no attempt is recorded as accepted")
check(identical(result$assessment$accepted, FALSE), "the returned assessment is a rejection")
check(sum(result$attempts$returned_fit) == 1L, "exactly one attempt is the returned fit")

# An accepted attempt is never displaced by a later, lower objective, because
# retrying stops at acceptance. Reaching a lower objective first and being
# accepted later must still return the accepted one.
result <- retry(scripted_run(fitted_model(6L, 10, "low"), fitted_model(0L, 999, "accepted")),
                status_based)
check(identical(result$model$tag, "accepted"),
      "an accepted attempt outranks a lower unaccepted objective")
check(identical(result$attempts$returned_fit, c(FALSE, TRUE)),
      "the accepted attempt is recorded as the returned fit")

# --- The optimizer itself fails ---------------------------------------------
result <- retry(scripted_run("solver exploded", fitted_model(0L, 130)), status_based)
check(nrow(result$attempts) == 2L, "an optimizer error consumes one trial and retrying continues")
check(is.na(result$attempts$status[1L]), "a run that produced no fit has no status")
check(identical(result$attempts$error[1L], "solver exploded"),
      "the optimizer error message is retained")
check(isFALSE(result$attempts$optimizer_success[1L]), "a failed run is not an optimizer success")
check(is.na(result$attempts$minus2loglik[1L]), "a failed run reports no objective")
check(isFALSE(result$attempts$external_accepted[1L]), "a failed run cannot be accepted")

condition <- expect_condition(retry(scripted_run("solver exploded"), status_based, extra_tries = 2L),
                              "gt_native_retry_failure",
                              "a budget of only failed runs raises the retry-failure condition")
check(nrow(condition$retry_attempts) == 3L, "the failure condition carries every attempt")
check(condition$optimization_trials == 3L, "the failure condition reports the trial count")
check(all(is.na(condition$retry_attempts$status)), "no attempt in the failed budget has a status")
check(length(condition$retry_log) >= 3L, "the failure condition carries the retry log")

# A run that returns something other than a fitted model is not a fit.
condition <- expect_condition(retry(scripted_run(list(output = list(fit = 1))), status_based,
                                    extra_tries = 0L),
                              "gt_native_retry_failure",
                              "a run returning a non-model raises the retry-failure condition")
check(grepl("no usable", condition$retry_attempts$external_rejection_reason[1L]),
      "the non-model result is described as producing no usable fit")

# --- The acceptance check itself fails ---------------------------------------
throwing <- function(model) stop("stationarity probe failed", call. = FALSE)
condition <- expect_condition(retry(scripted_run(fitted_model(0L, 100)), throwing, extra_tries = 1L),
                              "gt_native_retry_failure",
                              "an acceptance check that throws cannot produce an accepted fit")
check(all(grepl("stationarity probe failed", condition$retry_attempts$external_rejection_reason)),
      "the acceptance error is recorded as the rejection reason")

# An acceptance decision without components is not a usable result. This is a
# contract violation by the acceptance check, and it must fail loudly rather
# than return a fit with no estimates attached.
no_components <- function(model) list(accepted = TRUE, reason = "")
invisible(expect_condition(retry(scripted_run(fitted_model(0L, 100)), no_components, extra_tries = 0L),
                           "gt_native_retry_failure",
                           "acceptance without components does not produce a fit"))

# --- A perturbation that cannot be formed ------------------------------------
condition <- expect_condition(
  retry(scripted_run(fitted_model(6L, 100)), status_based, extra_tries = 2L,
        jitter = function(model) stop("bounds are not finite", call. = FALSE)),
  "gt_native_retry_failure", "a failed perturbation raises the retry-failure condition")
check(grepl("Perturbing the next starting values failed", conditionMessage(condition)),
      "the perturbation failure says what could not be done")
check(nrow(condition$retry_attempts) == 1L,
      "the perturbation failure carries the attempts made before it")

# --- Budget validation --------------------------------------------------------
check(inherits(tryCatch(retry(scripted_run(fitted_model(0L, 1)), accepted, extra_tries = -1L),
                        error = identity), "error"),
      "a negative retry budget is rejected")
single <- retry(scripted_run(fitted_model(6L, 100)), status_based, extra_tries = 0L)
check(nrow(single$attempts) == 1L, "a zero retry budget permits exactly one attempt")
check(single$budget == 1L, "a zero retry budget is a budget of one")

if (length(failures))
  stop("Retry controller failures:\n", paste0("- ", failures, collapse = "\n"))
cat("PASS: retry controller accounting, selection, failure handling, and budget contract.\n")
