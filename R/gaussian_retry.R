# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Optimizer retrying for the exact balanced Gaussian engine.
#
# One loop drives the optimizer directly and records what each run returned.
# The earlier implementation wrapped OpenMx's own retry helper and recovered
# the per-trial account by parsing its printed messages, which meant that a
# trial whose message block carried no status line was recorded with an unknown
# status, and that a change in OpenMx's wording could fail an otherwise valid
# fit. Every trial here has a status because this code is the caller that
# received it.
#
# Forward candidate only: at most extra_tries + 1 runs. The continuation anchor
# is the lowest independently reconstructed objective, never a mismatched native
# objective. With no valid anchor, perturb the original declared start. Stop at
# the first externally accepted run. Preserve invalid attempts and, if no valid
# candidate exists, return the first assessable refusal for diagnosis.
# Acceptance remains the caller's `assess` decision; no tolerance is relaxed.

# OpenMx's own jitter, with the parameters the previous implementation passed
# to mxTryHard: a uniform perturbation inside each parameter's bounds.
.gt_gaussian_jitter <- function(model) {
  parameters <- OpenMx::omxGetParameters(model)
  lower <- OpenMx::omxGetParameters(model, fetch = "lbound")
  upper <- OpenMx::omxGetParameters(model, fetch = "ubound")
  lower[is.na(lower)] <- -Inf
  upper[is.na(upper)] <- Inf
  OpenMx::omxSetParameters(model, labels = names(parameters),
    values = OpenMx::imxJiggle(parameters, lower, upper, dsn = "runif", loc = 1, scale = 0.25))
}

# Run the optimizer once, keeping whatever it produced, including a failure.
# Warnings and messages belong to this run and are retained rather than
# escaping into the caller's session mid-retry.
.gt_gaussian_run_once <- function(model, silent, run) {
  messages <- character()
  warnings <- character()
  failure <- NULL
  printed <- character()
  fitted <- NULL
  printed <- utils::capture.output(
    fitted <- tryCatch(withCallingHandlers(run(model, silent = TRUE),
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      },
      message = function(m) {
        messages <<- c(messages, conditionMessage(m))
        invokeRestart("muffleMessage")
      }), error = function(e) {
        failure <<- conditionMessage(e)
        NULL
      }))
  if (!silent && length(printed)) cat(paste(printed, collapse = "\n"), "\n")
  usable <- inherits(fitted, "MxModel") && !is.null(fitted$output) &&
    is.numeric(fitted$output$fit) && length(fitted$output$fit) == 1L
  status <- if (usable && length(fitted$output$status$code) == 1L)
    as.integer(fitted$output$status$code) else NA_integer_
  list(model = if (usable) fitted else NULL,
       status = status,
       objective = if (usable) as.numeric(fitted$output$fit) else NA_real_,
       error = failure, warnings = warnings, messages = messages, printed = printed)
}

.gt_gaussian_retry_row <- function(attempt, optimizer, start_type, run, evaluation) {
  reasons <- unique(c(run$error, if (!is.null(evaluation)) evaluation$reason))
  reasons <- reasons[!is.na(reasons) & nzchar(reasons)]
  data.frame(
    attempt = attempt, optimizer = optimizer, start_type = start_type,
    status = run$status,
    optimizer_success = !is.na(run$status) && run$status == 0L,
    minus2loglik = run$objective,
    external_accepted = if (is.null(evaluation)) NA else isTRUE(evaluation$accepted),
    external_rejection_reason = paste(reasons, collapse = " | "),
    error = if (is.null(run$error)) "" else run$error,
    returned_fit = FALSE, stringsAsFactors = FALSE)
}

# Retry until acceptance or the budget is spent, and account for every run.
#
# model: the constructed OpenMx model, carrying its own compute plan.
# assess: the external acceptance check. It receives a fitted model and returns
#   a list with accepted, reason, components and the diagnostics behind them.
#   A fit is returned only if assess could evaluate it (components present).
# run, jitter: injected for testing; the defaults are the real optimizer and
#   OpenMx's own perturbation.
.gt_gaussian_retry <- function(model, optimizer, extra_tries, tolerance,
                               max_iterations, start_label, silent, assess,
                               run = OpenMx::mxRun, jitter = .gt_gaussian_jitter,
                                recover = NULL) {
  budget <- as.integer(extra_tries) + 1L
  if (!is.finite(budget) || budget < 1L)
    stop("The optimizer trial budget must be at least one attempt.", call. = FALSE)
  rows <- vector("list", budget)
  log <- character()
  best <- NULL
  anchor <- NULL
  candidate <- model
  start_type <- start_label
  used <- 0L
  recovery_attempted <- FALSE
  recovery_record <- NULL
  for (attempt in seq_len(budget)) {
    used <- attempt
    result <- .gt_gaussian_run_once(candidate, silent, run)
    evaluation <- if (is.null(result$model)) list(accepted = FALSE,
        reason = if (is.null(result$error)) "The optimizer returned no usable fit." else result$error) else
      tryCatch(assess(result$model),
               error = function(e) list(accepted = FALSE, reason = conditionMessage(e)))
    rows[[attempt]] <- .gt_gaussian_retry_row(attempt, optimizer, start_type, result, evaluation)
    log <- c(log, sprintf("Attempt %d of %d from %s: status %s, objective %s, accepted %s%s",
      attempt, budget, start_type,
      if (is.na(result$status)) "unavailable" else result$status,
      if (is.na(result$objective)) "unavailable" else format(result$objective, digits = 10),
      isTRUE(evaluation$accepted),
      if (nzchar(rows[[attempt]]$external_rejection_reason))
        paste0(" (", rows[[attempt]]$external_rejection_reason, ")") else ""),
      result$messages, result$warnings, result$printed)
    # Retain a rejected result for inspection, but never rank a result whose
    # native objective the independent likelihood evaluation contradicted as if
    # that objective were meaningful: it neither seeds another trial nor
    # displaces a reconstructed candidate. Among reconstructed candidates an
    # accepted one always wins and otherwise the lowest objective does. An
    # acceptance check that makes no likelihood comparison leaves the rule as
    # it was.
    usable <- !is.null(result$model) && is.finite(result$objective) &&
      !is.null(evaluation$components)
    reconstructs <- usable && !isFALSE(evaluation$likelihood_matches)
    candidate_record <- if (usable) list(model = result$model,
      evaluation = evaluation, objective = result$objective, attempt = attempt,
      reconstructs = reconstructs) else NULL
    if (reconstructs && (is.null(anchor) || result$objective < anchor$objective))
      anchor <- candidate_record
    if (usable && (is.null(best) || isTRUE(evaluation$accepted) ||
        (reconstructs && !isTRUE(best$evaluation$accepted) &&
          (!best$reconstructs || result$objective < best$objective)))) best <- candidate_record
    rows[[attempt]]$retry_anchor_eligible <- reconstructs
    rows[[attempt]]$retry_anchor_attempt <- if (is.null(anchor)) NA_integer_ else anchor$attempt
    if (isTRUE(evaluation$accepted)) break
    if (attempt < budget) {
      recovered <- NULL
      if (!is.null(recover) && !recovery_attempted) {
        recovery_attempted <- TRUE
        recovered <- tryCatch(recover(model), error = function(e)
          list(model = NULL, diagnostics = list(status = "refused", eligible = FALSE,
            error = conditionMessage(e))))
        recovery_record <- recovered$diagnostics
        recovery_record$trigger_attempt <- attempt
        recovery_record$handoff_attempt <- if (is.null(recovered$model)) NA_integer_ else attempt + 1L
        recovery_record$ordinary_budget <- budget
      }
      if (!is.null(recovered$model)) {
        if (!inherits(recovered$model, "MxModel") ||
            !isTRUE(recovery_record$eligible))
          stop(structure(list(message = "Invalid internal recovery handoff; ordinary acceptance cannot be bypassed.",
            call = NULL, retry_attempts = do.call(rbind, rows[seq_len(attempt)]),
            retry_log = log, optimization_trials = attempt,
            recovery_attempted = recovery_attempted, recovery_record = recovery_record),
            class = c("gt_native_retry_failure", "error", "condition")))
        candidate <- recovered$model
        start_type <- "square_root_cold_recovery"
        next
      }
      base <- if (!is.null(anchor)) anchor$model else model
      candidate <- tryCatch(jitter(base), error = function(e) {
        message <- paste("Perturbing the next starting values failed:", conditionMessage(e))
        stop(structure(list(message = message, call = NULL,
          retry_attempts = do.call(rbind, rows[seq_len(attempt)]),
          retry_log = c(log, message), optimization_trials = attempt,
          recovery_attempted = recovery_attempted, recovery_record = recovery_record),
          class = c("gt_native_retry_failure", "error", "condition")))
      })
      start_type <- "uniform_perturbation"
    }
  }
  attempts <- do.call(rbind, rows[seq_len(used)])
  rownames(attempts) <- NULL
  if (is.null(best)) stop(structure(list(
    message = "No optimizer attempt supplied usable covariance estimates within the trial budget.",
    call = NULL, retry_attempts = attempts, retry_log = log,
    optimization_trials = used, recovery_attempted = recovery_attempted,
    recovery_record = recovery_record), class = c("gt_native_retry_failure", "error", "condition")))
  attempts$returned_fit <- attempts$attempt == best$attempt
  list(model = best$model, assessment = best$evaluation, attempts = attempts,
       log = log, budget = budget, optimizer_runs = used,
       recovery_attempted = recovery_attempted, recovery_record = recovery_record)
}
