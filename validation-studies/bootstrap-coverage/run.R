#!/usr/bin/env Rscript
# Independent data generator and target formulas; the package supplies fits,
# bootstraps and intervals. See PROTOCOL.md.
args <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_arg) != 1L) stop("Run this file with Rscript.")
study_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
root <- normalizePath(file.path(study_dir, "..", ".."))
if (length(args) != 2L) stop("Supply an empty output directory and a worker count.")
output_dir <- args[[1L]]
workers <- as.integer(args[[2L]])
if (!is.finite(workers) || workers < 1L) stop("The worker count must be a positive integer.")
if (dir.exists(output_dir) && length(list.files(output_dir, all.files = TRUE, no.. = TRUE)))
  stop("Results directory must be empty; preserve existing runs.")
dir.create(file.path(output_dir, "rows"), recursive = TRUE, showWarnings = FALSE)
invisible(file.copy(file.path(study_dir, "run.R"), file.path(output_dir, "run-executed.R")))
config <- read.csv(file.path(study_dir, "config.csv"), stringsAsFactors = FALSE)
package_env <- new.env(parent = globalenv())
source(file.path(root, "load_functions.R"), local = package_env)
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
level <- 0.95
save_csv <- function(x, name) write.csv(x, file.path(output_dir, name), row.names = FALSE, na = "NA")
truth <- function(s) c(Erho2 = s$var_item / (s$var_item + s$var_residual / s$n_raters),
  Phi = s$var_item / (s$var_item + (s$var_rater + s$var_residual) / s$n_raters))
schedule <- do.call(rbind, lapply(seq_len(nrow(config)), function(j)
  data.frame(scenario = config$scenario[j], replicate = seq_len(config$replicates[j]),
             data_seed = config$seed_base[j] + seq_len(config$replicates[j]))))
schedule$retry_seed <- schedule$data_seed + 500000L
schedule$bootstrap_seed <- schedule$data_seed + 1000000L
save_csv(schedule, "schedule.csv")
save_csv(config, "config.csv")
relative_files <- c("DESCRIPTION", "load_functions.R",
  file.path("R", sort(list.files(file.path(root, "R"), pattern = "[.]R$"))),
  file.path("validation-studies/bootstrap-coverage", c("config.csv", "PROTOCOL.md", "run.R", "summarize.R")))
save_csv(data.frame(file = relative_files, md5 = unname(tools::md5sum(file.path(root, relative_files)))),
         "source-files.csv")
commit_file <- file.path(root, "SOURCE_COMMIT")
source_commit <- if (file.exists(commit_file)) readLines(commit_file, n = 1L) else
  suppressWarnings(tryCatch(system2("git", c("-C", shQuote(root), "rev-parse", "HEAD"), stdout = TRUE,
                                    stderr = FALSE), error = function(e) character()))
if (length(source_commit) != 1L) source_commit <- NA_character_
save_csv(data.frame(package = c("Gtheory4LLM (source)", "OpenMx", "R"),
  version = c(read.dcf(file.path(root, "DESCRIPTION"))[1, "Version"],
              as.character(utils::packageVersion("OpenMx")), as.character(getRversion()))), "environment.csv")
save_csv(data.frame(key = c("source_commit", "started_utc", "platform", "rng", "interval_level",
  "workers", "bootstrap_replicates", "bootstrap_max_attempts", "jackknife"),
  value = c(source_commit, format(Sys.time(), tz = "UTC", usetz = TRUE), R.version$platform,
            paste(RNGkind(), collapse = ";"), level, workers, 500, 1000, TRUE)), "run-metadata.csv")

run_one <- function(k) {
  plan <- schedule[k, ]
  s <- config[match(plan$scenario, config$scenario), ]
  set.seed(plan$data_seed)
  dat <- expand.grid(rater = factor(seq_len(s$n_raters)), item = factor(seq_len(s$n_items)))
  item <- rnorm(s$n_items, sd = sqrt(s$var_item))
  rater <- rnorm(s$n_raters, sd = sqrt(s$var_rater))
  dat$score <- s$mean + item[dat$item] + rater[dat$rater] + rnorm(nrow(dat), sd = sqrt(s$var_residual))
  target <- truth(s)
  row <- data.frame(scenario = plan$scenario, replicate = plan$replicate, data_seed = plan$data_seed,
    status = "error", error = "", boundary_components = "", restricted_to_interior = NA,
    Erho2_true = target[["Erho2"]], Phi_true = target[["Phi"]], Erho2 = NA_real_, Phi = NA_real_,
    bootstrap_accepted = NA_integer_, bootstrap_attempts = NA_integer_, jackknife_complete = NA,
    fit_seconds = NA_real_, bootstrap_seconds = NA_real_, stringsAsFactors = FALSE)
  for (method in c("wald", "percentile", "bca")) for (metric in c("Erho2", "Phi"))
    for (part in c("se", "lower", "upper")) row[[paste(metric, method, part, sep = "_")]] <- NA_real_
  tick <- proc.time()[["elapsed"]]
  fit <- tryCatch(suppressWarnings(package_env$gt_fit(dat, "score",
    package_env$gt_design("item", "rater", random = ~ item + rater),
    estimator = "REML", covariance = "diagonal", residual = "pooled",
    control = package_env$gt_control(gaussian = list(optimizer = "CSOLNP", threads = 1L,
      max_iterations = 3000L, tolerance = 1e-12, extra_tries = 9L,
      retry_seed = plan$retry_seed, check_hessian = TRUE, silent = TRUE)))), error = identity)
  row$fit_seconds <- proc.time()[["elapsed"]] - tick
  if (inherits(fit, "error")) { row$error <- conditionMessage(fit); return(row) }
  if (!isTRUE(fit$numerically_accepted)) { row$status <- "rejected"; return(row) }
  row$status <- "accepted"
  row$boundary_components <- paste(fit$uncertainty$boundary_components, collapse = ";")
  row$restricted_to_interior <- isTRUE(fit$uncertainty$restricted_to_interior)
  tick <- proc.time()[["elapsed"]]
  boot <- tryCatch(package_env$gt_bootstrap(fit, replicates = 500L, seed = plan$bootstrap_seed,
                                            jackknife = TRUE, cores = 1L), error = identity)
  row$bootstrap_seconds <- proc.time()[["elapsed"]] - tick
  if (inherits(boot, "error")) { row$error <- conditionMessage(boot); return(row) }
  row$bootstrap_accepted <- boot$accepted
  row$bootstrap_attempts <- boot$attempts
  row$jackknife_complete <- isTRUE(boot$jackknife$complete)
  for (method in c("wald", "percentile", "bca")) {
    table <- tryCatch(package_env$as.data.frame.gt_reliability(if (method == "wald")
      package_env$gt_reliability(fit, level = level) else
      package_env$gt_reliability(fit, level = level, bootstrap = boot, interval_type = method)), error = identity)
    if (inherits(table, "error")) { row$error <- paste(row$error, method, conditionMessage(table)); next }
    row$Erho2 <- table$Erho2
    row$Phi <- table$Phi
    for (metric in c("Erho2", "Phi")) for (part in c("se", "lower", "upper"))
      row[[paste(metric, method, part, sep = "_")]] <- table[[paste(metric, part, sep = "_")]]
  }
  row
}
worker <- function(k) {
  row <- tryCatch(run_one(k), error = function(e) data.frame(scenario = schedule$scenario[k],
    replicate = schedule$replicate[k], status = "error", error = conditionMessage(e)))
  write.csv(row, file.path(output_dir, "rows", sprintf("%s-%03d.csv", schedule$scenario[k], schedule$replicate[k])),
            row.names = FALSE, na = "NA")
  TRUE
}
order <- as.vector(t(matrix(seq_len(nrow(schedule)), ncol = nrow(config))))
done <- parallel::mclapply(order, worker, mc.cores = workers, mc.preschedule = FALSE, mc.set.seed = FALSE)
source(file.path(study_dir, "summarize.R"), local = TRUE)
summarize_run(output_dir)
