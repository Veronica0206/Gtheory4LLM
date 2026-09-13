#!/usr/bin/env Rscript
# Independent data generator and target formulas; package supplies fits/intervals.
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_arg) != 1L) stop("Run this file with Rscript.")
study_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
root <- normalizePath(file.path(study_dir, "..", ".."))
output_dir <- if (length(args)) args[[1L]] else file.path(study_dir, "results")
if (length(args) > 1L) stop("Supply at most one output directory.")
if (dir.exists(output_dir) && length(list.files(output_dir, all.files = TRUE,
                                              no.. = TRUE)))
  stop("Results directory must be empty; preserve existing runs.")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
config <- read.csv(file.path(study_dir, "config.csv"), stringsAsFactors = FALSE)
stopifnot(!anyDuplicated(config$scenario), all(config$n_items >= 2),
          all(config$n_raters >= 2), all(config$replicates >= 1),
          all(config$var_item > 0), all(config$var_rater >= 0),
          all(config$var_residual > 0))
package_env <- new.env(parent = globalenv())
source(file.path(root, "load_functions.R"), local = package_env)
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
level <- 0.95
fit_budget_seconds <- 240
started <- format(Sys.time(), tz = "UTC", usetz = TRUE)
save_csv <- function(x, name) write.csv(x, file.path(output_dir, name), row.names = FALSE,
                                       na = "NA")
sanitize <- function(x) {
  x <- paste(x, collapse = " | ")
  x <- gsub(root, "<repository>", x, fixed = TRUE)
  x <- gsub(path.expand("~"), "<home>", x, fixed = TRUE)
  gsub("[\r\n]+", " ", x)
}
truth <- function(s) c(Erho2 = s$var_item / (s$var_item + s$var_residual / s$n_raters),
  Phi = s$var_item / (s$var_item + (s$var_rater + s$var_residual) / s$n_raters))
# Analytic limiting-case checks do not call package reliability helpers.
stopifnot(abs(truth(config[4, ])[["Erho2"]] - truth(config[4, ])[["Phi"]]) < 1e-14,
          all(vapply(seq_len(nrow(config)), function(j)
            truth(config[j, ])[["Erho2"]] >= truth(config[j, ])[["Phi"]], logical(1))))
schedule <- do.call(rbind, lapply(seq_len(max(config$replicates)), function(rep) {
  do.call(rbind, lapply(which(rep <= config$replicates), function(j)
    data.frame(scenario = config$scenario[j], replicate = rep,
      estimator = c("ML", "REML"), data_seed = config$seed_base[j] + rep,
      retry_seed = config$seed_base[j] + rep + 500000L, attempted = FALSE)))
}))
save_csv(schedule, "schedule.csv")
save_csv(config, "config.csv")
relative_files <- c("DESCRIPTION", "load_functions.R",
  sort(list.files(file.path(root, "R"), pattern = "[.]R$", full.names = FALSE)),
  "validation-studies/gaussian-coverage/config.csv",
  "validation-studies/gaussian-coverage/PROTOCOL.md",
  "validation-studies/gaussian-coverage/run.R")
relative_files[!grepl("/", relative_files) & grepl("[.]R$", relative_files) &
                 relative_files != "load_functions.R"] <- paste0("R/",
    relative_files[!grepl("/", relative_files) & grepl("[.]R$", relative_files) &
                     relative_files != "load_functions.R"])
save_csv(data.frame(file = relative_files, md5 = unname(tools::md5sum(
  file.path(root, relative_files)))), "source-files.csv")
source_commit <- system2("git", c("-C", shQuote(root), "rev-parse", "HEAD"), stdout = TRUE)
save_csv(data.frame(package = c("Gtheory4LLM (checkout)", "OpenMx", "R"),
  version = c(read.dcf(file.path(root, "DESCRIPTION"))[1, "Version"],
              as.character(utils::packageVersion("OpenMx")), getRversion())),
  "environment.csv")
save_csv(data.frame(key = c("source_commit", "source_snapshot", "started_utc", "platform",
  "rng", "interval_level", "fit_time_budget_seconds", "execution_order", "optimizer",
  "threads", "max_iterations", "tolerance", "extra_tries"),
  value = c(source_commit, "Exact working files identified by source-files.csv",
    started, R.version$platform, paste(RNGkind(), collapse = ";"), level,
    fit_budget_seconds, "replicate then scenario then ML and REML", "CSOLNP", 1,
    3000, 1e-12, 9)), "run-metadata.csv")

rows <- list()
cumulative_fit_seconds <- 0
for (k in seq_len(nrow(schedule))) {
  if (cumulative_fit_seconds >= fit_budget_seconds) break
  plan <- schedule[k, ]
  s <- config[match(plan$scenario, config$scenario), ]
  set.seed(plan$data_seed)
  dat <- expand.grid(rater = factor(seq_len(s$n_raters)),
                     item = factor(seq_len(s$n_items)))
  item <- rnorm(s$n_items, sd = sqrt(s$var_item))
  rater <- rnorm(s$n_raters, sd = sqrt(s$var_rater))
  dat$score <- s$mean + item[dat$item] + rater[dat$rater] +
    rnorm(nrow(dat), sd = sqrt(s$var_residual))
  target <- truth(s)
  row <- data.frame(scenario = plan$scenario, replicate = plan$replicate,
    estimator = plan$estimator, data_seed = plan$data_seed, retry_seed = plan$retry_seed,
    status = "error", optimizer_completed = FALSE, numerically_accepted = FALSE,
    uncertainty_available = FALSE, restricted_to_interior = FALSE,
    boundary_components = "", boundary_count = NA_integer_, issues = "", warnings = "",
    error = "", uncertainty_reason = "", fit_seconds = NA_real_,
    optimization_trials = NA_integer_, var_item = NA_real_, var_rater = NA_real_,
    var_residual = NA_real_, Erho2_true = target[["Erho2"]], Phi_true = target[["Phi"]],
    Erho2 = NA_real_, Erho2_se = NA_real_, Erho2_lower = NA_real_, Erho2_upper = NA_real_,
    Phi = NA_real_, Phi_se = NA_real_, Phi_lower = NA_real_, Phi_upper = NA_real_)
  warnings <- character()
  tick <- proc.time()[["elapsed"]]
  fit <- tryCatch(withCallingHandlers(package_env$gt_fit(dat, "score",
    package_env$gt_design("item", "rater", random = ~ item + rater),
    estimator = plan$estimator, covariance = "diagonal", residual = "pooled",
    control = package_env$gt_control(gaussian = list(optimizer = "CSOLNP", threads = 1L,
      max_iterations = 3000L, tolerance = 1e-12, extra_tries = 9L,
      retry_seed = plan$retry_seed, check_hessian = TRUE, silent = TRUE))),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w));
                           invokeRestart("muffleWarning") }), error = identity)
  row$fit_seconds <- proc.time()[["elapsed"]] - tick
  cumulative_fit_seconds <- cumulative_fit_seconds + row$fit_seconds
  row$warnings <- sanitize(warnings)
  if (inherits(fit, "error")) {
    row$error <- sanitize(conditionMessage(fit))
  } else {
    row$numerically_accepted <- isTRUE(fit$numerically_accepted)
    row$optimizer_completed <- isTRUE(fit$optimizer_completed)
    row$status <- if (row$numerically_accepted) "accepted" else "rejected"
    row$uncertainty_available <- isTRUE(fit$uncertainty$available)
    row$restricted_to_interior <- isTRUE(fit$uncertainty$restricted_to_interior)
    row$boundary_components <- paste(fit$uncertainty$boundary_components, collapse = ";")
    row$boundary_count <- length(fit$uncertainty$boundary_components)
    row$issues <- sanitize(fit$diagnostics$issues)
    row$uncertainty_reason <- sanitize(fit$uncertainty$reason)
    row$optimization_trials <- fit$optimization_trials
    row$var_item <- fit$covariance_components$item[1, 1]
    row$var_rater <- fit$covariance_components$rater[1, 1]
    row$var_residual <- fit$covariance_components$Residual[1, 1]
    if (row$numerically_accepted) {
      reliability <- tryCatch(withCallingHandlers(package_env$gt_reliability(fit,
        level = level), warning = function(w) {
          warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
        }), error = identity)
      if (inherits(reliability, "error")) row$error <- sanitize(conditionMessage(reliability)) else {
        columns <- c("Erho2", "Erho2_se", "Erho2_lower", "Erho2_upper",
                     "Phi", "Phi_se", "Phi_lower", "Phi_upper")
        row[columns] <- reliability$per_trait[1L, columns]
      }
      row$warnings <- sanitize(warnings)
    }
  }
  rows[[length(rows) + 1L]] <- row
  schedule$attempted[k] <- TRUE
  # Persist after every fit, including failures; no selective recovery reruns.
  save_csv(do.call(rbind, rows), "replicates.csv")
  save_csv(schedule, "schedule.csv")
  if (k %% 40L == 0L) cat("Attempted", k, "of", nrow(schedule), "fits; fit seconds",
                         round(cumulative_fit_seconds, 2), "\n")
}
if (!length(rows)) stop("No fit was attempted.")
results <- do.call(rbind, rows)
proportion <- function(successes, n, prefix) {
  p <- if (n > 0L) successes / n else NA_real_
  ci <- if (n > 0L) stats::binom.test(successes, n)$conf.int else c(NA_real_, NA_real_)
  setNames(c(p, if (n > 0L) sqrt(p * (1 - p) / n) else NA_real_, ci),
           paste0(prefix, c("", "_mcse", "_lower", "_upper")))
summarize <- function(d, metric, planned = NA_integer_) {
  accepted <- d$numerically_accepted
  point <- accepted & is.finite(d[[metric]])
  interval <- point & is.finite(d[[paste0(metric, "_lower")]]) &
    is.finite(d[[paste0(metric, "_upper")]]) &
    d[[paste0(metric, "_lower")]] <= d[[paste0(metric, "_upper")]]
  covered <- interval & d[[paste0(metric, "_lower")]] <= d[[paste0(metric, "_true")]] &
    d[[paste0(metric, "_upper")]] >= d[[paste0(metric, "_true")]]
  covered[is.na(covered)] <- FALSE
  err <- d[[metric]][point] - d[[paste0(metric, "_true")]][point]
  data.frame(metric = metric, planned = planned, attempted = nrow(d),
    accepted = sum(accepted), rejected = sum(d$status == "rejected"),
    errors = sum(d$status == "error"), boundary_fits = sum(d$boundary_count > 0, na.rm = TRUE),
    restricted_fits = sum(d$restricted_to_interior), point_n = sum(point),
    interval_n = sum(interval), covered_n = sum(covered),
    bias = if (length(err)) mean(err) else NA_real_,
    rmse = if (length(err)) sqrt(mean(err^2)) else NA_real_,
    estimate_mcse = if (length(err) > 1L) sd(err) / sqrt(length(err)) else NA_real_,
    mean_interval_width = if (any(interval)) mean(d[[paste0(metric, "_upper")]][interval] -
      d[[paste0(metric, "_lower")]][interval]) else NA_real_,
    as.list(proportion(sum(accepted), nrow(d), "acceptance_rate")),
    as.list(proportion(sum(interval), nrow(d), "interval_availability")),
    as.list(proportion(sum(covered), sum(interval), "coverage")),
    as.list(proportion(sum(covered), nrow(d), "overall_interval_success")))
}
summary_rows <- boundary_rows <- recovery_rows <- list()
for (scenario in config$scenario) for (estimator in c("ML", "REML")) {
  d <- results[results$scenario == scenario & results$estimator == estimator, ]
  planned <- sum(schedule$scenario == scenario & schedule$estimator == estimator)
  for (metric in c("Erho2", "Phi")) {
    summary_rows[[length(summary_rows) + 1L]] <- cbind(scenario, estimator,
      summarize(d, metric, planned))
    for (stratum in c("no_boundary", "boundary_full_curvature", "boundary_restricted")) {
      keep <- d$numerically_accepted & switch(stratum,
        no_boundary = !is.na(d$boundary_count) & d$boundary_count == 0,
        boundary_full_curvature = !is.na(d$boundary_count) & d$boundary_count > 0 &
          !d$restricted_to_interior,
        boundary_restricted = !is.na(d$boundary_count) & d$boundary_count > 0 &
          d$restricted_to_interior)
      boundary_rows[[length(boundary_rows) + 1L]] <- cbind(scenario, estimator, stratum,
        summarize(d[keep, ], metric))
    }
  }
  for (component in c("var_item", "var_rater", "var_residual")) {
    target <- config[config$scenario == scenario, component]
    keep <- d$numerically_accepted & is.finite(d[[component]])
    err <- d[[component]][keep] - target
    recovery_rows[[length(recovery_rows) + 1L]] <- data.frame(scenario, estimator,
      component, true_variance = target, planned, attempted = nrow(d), accepted = sum(keep),
      bias = if (length(err)) mean(err) else NA_real_,
      rmse = if (length(err)) sqrt(mean(err^2)) else NA_real_,
      estimate_mcse = if (length(err) > 1L) sd(err) / sqrt(length(err)) else NA_real_)
  }
}
save_csv(do.call(rbind, summary_rows), "summary.csv")
save_csv(do.call(rbind, boundary_rows), "boundary-summary.csv")
save_csv(do.call(rbind, recovery_rows), "recovery.csv")
save_csv(data.frame(key = c("finished_utc", "planned_fits", "attempted_fits",
  "cumulative_fit_seconds", "stopped_at_fit_budget"),
  value = c(format(Sys.time(), tz = "UTC", usetz = TRUE), nrow(schedule), nrow(results),
            cumulative_fit_seconds, any(!schedule$attempted))), "completion.csv")
cat("Completed", nrow(results), "of", nrow(schedule), "planned fits.\n")
print(do.call(rbind, summary_rows)[c("scenario", "estimator", "metric", "accepted",
                                   "interval_n", "coverage", "coverage_mcse")], row.names = FALSE)
