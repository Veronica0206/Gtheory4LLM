# Rebuild the replicate table and its summary from the retained rows; never
# fits or resamples data. The rows are the per-replicate files of a run
# (input_dir/rows/*.csv) or, as committed, their consolidated replicates.csv.
# Writing to a separate output_dir leaves the retained records untouched.
summarize_run <- function(input_dir, output_dir = input_dir) {
  if (!dir.exists(output_dir)) stop("output_dir does not exist: ", output_dir, call. = FALSE)
  save_csv <- function(x, name) write.csv(x, file.path(output_dir, name), row.names = FALSE, na = "NA")
  files <- sort(list.files(file.path(input_dir, "rows"), pattern = "[.]csv$", full.names = TRUE))
  consolidated <- file.path(input_dir, "replicates.csv")
  if (length(files)) {
    rows <- lapply(files, read.csv, stringsAsFactors = FALSE)
    columns <- unique(unlist(lapply(rows, names)))
    results <- do.call(rbind, lapply(rows, function(r) { r[setdiff(columns, names(r))] <- NA; r[columns] }))
  } else if (file.exists(consolidated)) {
    results <- read.csv(consolidated, stringsAsFactors = FALSE)
  } else {
    stop("No retained rows in ", input_dir, ": expected rows/*.csv or replicates.csv.", call. = FALSE)
  }
  if (!nrow(results)) stop("The retained rows in ", input_dir, " are empty.", call. = FALSE)
  schedule <- read.csv(file.path(input_dir, "schedule.csv"), stringsAsFactors = FALSE)
  config <- read.csv(file.path(input_dir, "config.csv"), stringsAsFactors = FALSE)
  results <- results[order(match(results$scenario, config$scenario), results$replicate), ]
  save_csv(results, "replicates.csv")
  proportion <- function(successes, n, prefix) {
    p <- if (n > 0L) successes / n else NA_real_
    ci <- if (n > 0L) stats::binom.test(successes, n)$conf.int else c(NA_real_, NA_real_)
    setNames(c(p, if (n > 0L) sqrt(p * (1 - p) / n) else NA_real_, ci),
             paste0(prefix, c("", "_mcse", "_lower", "_upper")))
  }
  summary_rows <- list()
  for (scenario in config$scenario) for (metric in c("Erho2", "Phi")) for (method in c("wald", "percentile", "bca")) {
    d <- results[results$scenario == scenario, ]
    lower <- d[[paste(metric, method, "lower", sep = "_")]]
    upper <- d[[paste(metric, method, "upper", sep = "_")]]
    truth <- d[[paste0(metric, "_true")]]
    accepted <- d$status == "accepted"
    interval <- accepted & is.finite(lower) & is.finite(upper) & lower <= upper
    covered <- interval & lower <= truth & upper >= truth
    covered[is.na(covered)] <- FALSE
    summary_rows[[length(summary_rows) + 1L]] <- data.frame(scenario, metric, method,
      planned = sum(schedule$scenario == scenario), attempted = nrow(d), accepted = sum(accepted),
      interval_n = sum(interval), covered_n = sum(covered),
      mean_interval_width = if (any(interval)) mean(upper[interval] - lower[interval]) else NA_real_,
      as.list(proportion(sum(covered), sum(interval), "coverage")),
      as.list(proportion(sum(interval), nrow(d), "interval_availability")),
      as.list(proportion(sum(covered), nrow(d), "overall_interval_success")))
  }
  summary <- do.call(rbind, summary_rows)
  save_csv(summary, "summary.csv")
  save_csv(data.frame(key = c("finished_utc", "planned_replicates", "attempted_replicates",
    "fit_seconds", "bootstrap_seconds"),
    value = c(format(Sys.time(), tz = "UTC", usetz = TRUE), nrow(schedule), nrow(results),
              sum(results$fit_seconds, na.rm = TRUE), sum(results$bootstrap_seconds, na.rm = TRUE))),
    "completion.csv")
  print(summary[c("scenario", "metric", "method", "interval_n", "coverage", "coverage_lower",
                  "coverage_upper", "mean_interval_width")], row.names = FALSE, digits = 3)
}
