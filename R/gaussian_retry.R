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
# The retry policy itself is unchanged: at most extra_tries + 1 runs, each
# unsuccessful run followed by OpenMx's own bounded uniform perturbation of the
# best model so far, stopping at the first run the external acceptance check
# accepts, and otherwise returning the best usable candidate. Acceptance is the
# caller's `assess` function; this loop never decides that a fit is good.

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
                               run = OpenMx::mxRun, jitter = .gt_gaussian_jitter) {
  budget <- as.integer(extra_tries) + 1L
  if (!is.finite(budget) || budget < 1L)
    stop("The optimizer trial budget must be at least one attempt.", call. = FALSE)
  rows <- vector("list", budget)
  log <- character()
  best <- NULL
  candidate <- model
  start_type <- start_label
  used <- 0L
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
    # A candidate is usable only if the acceptance check could evaluate it.
    # An accepted candidate always wins; otherwise the lowest objective does,
    # and an accepted candidate is never displaced by a lower unaccepted one.
    usable <- !is.null(result$model) && is.finite(result$objective) &&
      !is.null(evaluation$components)
    if (usable && (is.null(best) || isTRUE(evaluation$accepted) ||
                   (!isTRUE(best$evaluation$accepted) && result$objective < best$objective)))
      best <- list(model = result$model, evaluation = evaluation,
                   objective = result$objective, attempt = attempt)
    if (isTRUE(evaluation$accepted)) break
    if (attempt < budget) {
      base <- if (!is.null(best)) best$model else model
      candidate <- tryCatch(jitter(base), error = function(e) {
        message <- paste("Perturbing the next starting values failed:", conditionMessage(e))
        stop(structure(list(message = message, call = NULL,
          retry_attempts = do.call(rbind, rows[seq_len(attempt)]),
          retry_log = c(log, message), optimization_trials = attempt),
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
    optimization_trials = used), class = c("gt_native_retry_failure", "error", "condition")))
  attempts$returned_fit <- attempts$attempt == best$attempt
  list(model = best$model, assessment = best$evaluation, attempts = attempts,
       log = log, budget = budget, optimizer_runs = used)
}
