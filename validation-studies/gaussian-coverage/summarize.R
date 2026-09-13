# Rebuild descriptive tables from retained fits; never fits or resamples data.
summarize_run <- function(output_dir) {
  save_csv <- function(x, name) write.csv(x, file.path(output_dir, name),
                                         row.names = FALSE, na = "NA")
  results <- read.csv(file.path(output_dir, "replicates.csv"), stringsAsFactors = FALSE)
  schedule <- read.csv(file.path(output_dir, "schedule.csv"), stringsAsFactors = FALSE)
  config <- read.csv(file.path(output_dir, "config.csv"), stringsAsFactors = FALSE)
  cumulative_fit_seconds <- sum(results$fit_seconds)
  proportion <- function(successes, n, prefix) {
    p <- if (n > 0L) successes / n else NA_real_
    ci <- if (n > 0L) stats::binom.test(successes, n)$conf.int else c(NA_real_, NA_real_)
    setNames(c(p, if (n > 0L) sqrt(p * (1 - p) / n) else NA_real_, ci),
             paste0(prefix, c("", "_mcse", "_lower", "_upper")))
  }
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
}
