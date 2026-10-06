# Refit the boundary panel guarded by tests/package-discrete-safety.R,
# and print everything the fit recorded about why it was or was not accepted.
library_path <- commandArgs(trailingOnly = TRUE)[[1L]]
suppressMessages(library(Gtheory4LLM, lib.loc = library_path))
cat("Gtheory4LLM", as.character(utils::packageVersion("Gtheory4LLM", lib.loc = library_path)),
    "|", R.version.string, "| long double:", capabilities("long.double"), "\n")
set.seed(912)
boundary_panel <- expand.grid(item = seq_len(24), rater = seq_len(4), replicate = seq_len(3))
object_effect <- rnorm(24, sd = .9)
rater_effect <- c(-.5, -.1, .1, .5)
boundary_eta <- -.2 + object_effect[boundary_panel$item] + rater_effect[boundary_panel$rater]
boundary_panel$success <- rbinom(nrow(boundary_panel), 1, plogis(boundary_eta))
boundary_panel$rating <- cut(boundary_eta + rnorm(nrow(boundary_panel)),
  c(-Inf, -.4, .7, Inf), labels = c("low", "mid", "high"), ordered_result = TRUE)
cat("panel digest (category counts):", paste(table(boundary_panel$rating), collapse = " "),
    "| sum(eta) =", format(sum(boundary_eta), digits = 17), "\n")
boundary_design <- gt_design("item", "rater", random = ~ item + rater, replicates = 3L)
show <- function(fit, label) {
  d <- fit$diagnostics
  cat("\n====", label, "====\n")
  cat("numerically_accepted:", fit$numerically_accepted, "| optimizer_completed:", d$optimizer_completed,
      "| converged:", d$converged, "\n")
  cat("acceptance_failures:", if (length(d$acceptance_failures)) paste(d$acceptance_failures, collapse = " ; ") else "none", "\n")
  cat("optimizer:", d$optimizer, "| code:", d$optimizer_code, "| message:", d$optimizer_message,
      "| trials:", d$optimization_trials, "of", d$optimization_trial_budget, "| selected:", d$selected_attempt, "\n")
  cat("inner: converged", d$inner_converged, "| gradient", format(d$inner_gradient, digits = 6),
      "| iterations", d$inner_iterations, "\n")
  cat("variances:", paste(names(fit$covariance_components),
      vapply(fit$covariance_components, function(m) format(m[1, 1], digits = 10), ""), collapse = ", "), "\n")
  cat("minus2loglik:", format(fit$minus2loglik, digits = 14), "\n")
  scalar <- function(x) x[vapply(x, function(v) is.atomic(v) && length(v) <= 6L, logical(1))]
  cat("-- outer_stationarity\n"); utils::str(scalar(d$outer_stationarity), give.attr = FALSE)
  cat("-- stability\n"); utils::str(scalar(d$stability), give.attr = FALSE)
  cat("-- final_checks\n"); utils::str(d$final_checks, max.level = 2L, give.attr = FALSE)
  cat("-- evaluations\n"); utils::str(scalar(d$evaluations), give.attr = FALSE)
  for (a in d$attempts) cat("-- attempt", a$label, "| available", a$result_available, "| code", a$optimizer_code,
    "| objective", format(a$objective, digits = 14), "| message", paste(a$optimizer_message, collapse = " "),
    "| error", if (is.null(a$error)) "-" else a$error,
    "| warnings", if (length(a$warnings)) paste(a$warnings, collapse = " / ") else "-",
    "\n   parameters", paste(names(a$parameters), format(a$parameters, digits = 10), collapse = " "), "\n")
  if (!is.null(fit$diagnostics) && exists("gt_diagnostics") && !is.null(tryCatch(gt_diagnostics(fit)$stages, error = function(e) NULL))) {
    cat("-- stages\n")
    for (s in gt_diagnostics(fit)$stages) cat("  ", format(s$stage, width = 24), format(s$status, width = 13), s$reason, "\n")
  }
}
for (maxit in c(200L, 1000L)) {
  fit <- withCallingHandlers(
    gt_fit(boundary_panel, "rating", boundary_design,
      family = gt_family("ordinal", link = "probit", levels = c("low", "mid", "high")),
      control = gt_control(discrete = list(maxit = maxit))),
    warning = function(w) { cat("WARNING:", conditionMessage(w), "\n"); invokeRestart("muffleWarning") })
  show(fit, paste("ordinal boundary panel, maxit =", maxit))
}
