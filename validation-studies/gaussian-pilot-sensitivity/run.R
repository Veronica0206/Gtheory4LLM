#!/usr/bin/env Rscript
# Predeclared synthetic planning illustration; all attempted fits are retained.
args <- commandArgs(trailingOnly = TRUE)
smoke <- "--smoke" %in% args
args <- args[args != "--smoke"]
if (length(args) > 1L || (smoke && !length(args)))
  stop("Supply one new output directory; --smoke requires an explicit directory.")
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_arg) != 1L) stop("Run this file with Rscript.")
study_dir <- dirname(normalizePath(sub("^--file=", "", script_arg)))
root <- normalizePath(file.path(study_dir, "..", ".."))
installed_library <- Sys.getenv("GT_STUDY_LIBRARY", unset = "")
installed_mode <- nzchar(installed_library)
output_dir <- if (length(args)) args[[1L]] else file.path(study_dir, "results")
if (dir.exists(output_dir) && length(list.files(output_dir, all.files = TRUE, no.. = TRUE)))
  stop("Preserve existing evidence: the output directory must be empty.")
if (!requireNamespace("digest", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE))
  stop("The study runner requires digest and jsonlite for evidence fingerprints.")
git <- function(...) system2("git", c("-C", shQuote(root), ...), stdout = TRUE)
source_commit <- if (installed_mode) NA_character_ else git("rev-parse", "HEAD")
source_status <- if (installed_mode) "Installed-package run; archive provenance is recorded by its caller." else
  git("status", "--porcelain", "--untracked-files=all")
if (!installed_mode && length(git("status", "--porcelain", "--", "R", "DESCRIPTION", "load_functions.R")))
  stop("Commit package sources before executing this study.")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
save_csv <- function(x, name) write.csv(x, file.path(output_dir, name), row.names = FALSE, na = "NA")
save_json <- function(x, name) jsonlite::write_json(x, file.path(output_dir, name),
  auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null", digits = 16)
if (installed_mode) {
  installed_library <- normalizePath(installed_library, mustWork = TRUE)
  .libPaths(c(installed_library, .libPaths()))
  package_path <- find.package("Gtheory4LLM", lib.loc = installed_library)
  package_files <- c("DESCRIPTION", "NAMESPACE",
    paste0("R/", sort(list.files(file.path(package_path, "R")))))
  relative_files <- paste0("installed/Gtheory4LLM/", package_files)
  absolute_files <- file.path(package_path, package_files)
} else {
  relative_files <- c("DESCRIPTION", "load_functions.R",
    paste0("R/", sort(list.files(file.path(root, "R"), pattern = "[.]R$"))))
  absolute_files <- file.path(root, relative_files)
}
study_files <- c("PROTOCOL.md", "config.csv", "run.R")
relative_files <- c(relative_files, paste0("study/", study_files))
absolute_files <- c(absolute_files, file.path(study_dir, study_files))
fingerprints <- function() data.frame(file = relative_files,
  sha256 = vapply(absolute_files, function(path)
    digest::digest(file = path, algo = "sha256"), character(1)), row.names = NULL)
before <- fingerprints()
save_csv(before, "source-files.csv")
writeLines(source_status, file.path(output_dir, "source-status.txt"))
config <- read.csv(file.path(study_dir, "config.csv"), stringsAsFactors = FALSE)
if (smoke) config$replicates <- 2L
stopifnot(nrow(config) == 4L, !anyDuplicated(config$seed), all(config$n_items == 40),
  all(config$target_raters == 4), all(config$replicates > 0), all(config$var_item > 0),
  all(config$var_rater > 0), all(config$var_residual > 0), all(config$mean == 0))
config$cell_id <- seq_len(nrow(config))
save_csv(config, "config.csv")
schedule <- do.call(rbind, lapply(seq_len(nrow(config)), function(i)
  data.frame(cell_id = i, scenario = config$scenario[i], pilot_raters = config$pilot_raters[i],
    replicate_id = seq_len(config$replicates[i]), planned = TRUE, recorded = FALSE)))
save_csv(schedule, "schedule.csv")
if (installed_mode) {
  package_env <- loadNamespace("Gtheory4LLM", lib.loc = installed_library)
} else {
  package_env <- new.env(parent = globalenv())
  source(file.path(root, "load_functions.R"), local = package_env)
}
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
started <- format(Sys.time(), tz = "UTC", usetz = TRUE)
tick <- proc.time()[["elapsed"]]
metadata <- list(source_commit = source_commit, source_snapshot = "SHA-256 in source-files.csv",
  execution_mode = if (installed_mode) "installed_package" else "committed_package_sources",
  source_status = "source-status.txt", started_utc = started, complete = FALSE,
  smoke = smoke, planned_refits = nrow(schedule), attempted_refits = 0L,
  platform = R.version$platform, R = as.character(getRversion()),
  package_version = if (installed_mode) as.character(utils::packageVersion("Gtheory4LLM")) else
    read.dcf(file.path(root, "DESCRIPTION"))[1L, "Version"],
  dependencies = lapply(c("OpenMx", "Matrix", "digest", "jsonlite"), function(package)
    list(package = package, version = as.character(utils::packageVersion(package)))),
  rng = RNGkind(), cell_boundary_budget_seconds = 600,
  coefficient = "Phi", scope = "Local Gaussian precision illustration; no coverage or noLD qualification")
save_json(metadata, "execution.json")
sanitize <- function(text) {
  text <- gsub(root, "<repository>", text, fixed = TRUE)
  text <- gsub(path.expand("~"), "<home>", text, fixed = TRUE)
  gsub("[\r\n]+", " ", text)
}
control <- package_env$gt_control(gaussian = list(optimizer = "CSOLNP", threads = 1L,
  max_iterations = 3000L, tolerance = 1e-12, extra_tries = 9L, check_hessian = TRUE, silent = TRUE))
set.seed(199)
template_data <- expand.grid(item = 1:24, rater = 1:4, KEEP.OUT.ATTRS = FALSE)
template_data$score <- rep(rnorm(24, sd = 2), 4) +
  rep(rnorm(4, sd = .5), each = 24) + rnorm(96)
template <- package_env$gt_fit(template_data, "score", package_env$gt_design("item", "rater"),
  estimator = "REML", covariance = "diagonal", residual = "pooled", control = control)
stopifnot(isTRUE(template$numerically_accepted), isTRUE(template$converged),
  setequal(names(template$covariance_components), c("item", "rater", "Residual")))
save_json(list(seed = 199, n_items = 24, n_raters = 4,
  generating_variances = c(item = 4, rater = .25, Residual = 1),
  numerically_accepted = template$numerically_accepted, converged = template$converged,
  estimated_variances = vapply(template$covariance_components, function(x) x[1, 1], numeric(1)),
  estimator = template$estimator, covariance_types = template$covariance_types,
  control = control$gaussian,
  use = "Template model structure only; all study means and variances overridden explicitly"), "template.json")
replicates <- summaries <- list()
add_rate_interval <- function(row, prefix, successes, denominator) {
  ci <- stats::binom.test(successes, denominator)$conf.int
  row[[paste0(prefix, "_exact95_lower")]] <- ci[[1L]]
  row[[paste0(prefix, "_exact95_upper")]] <- ci[[2L]]
  row
}
for (i in seq_len(nrow(config))) {
  if (proc.time()[["elapsed"]] - tick > 600) stop("Study budget reached; partial cells are preserved.")
  s <- config[i, ]
  mat <- function(value) matrix(value, 1, 1, dimnames = list("score", "score"))
  components <- list(item = mat(s$var_item), rater = mat(s$var_rater), Residual = mat(s$var_residual))
  cell_tick <- proc.time()[["elapsed"]]
  plan <- package_env$gt_pilot_plan(template, data.frame(n_items = s$n_items, rater = s$pilot_raters),
    nsim = s$replicates, seed = s$seed, coefficient = "Phi", outcome = "score",
    width_target = s$width_target, level = s$level, target_counts = c(rater = s$target_raters),
    components = components, means = c(score = s$mean), control = control)
  row <- plan$summary
  records <- plan$replicates
  required <- c("acceptance_failures", "selected_attempt")
  if (!all(required %in% names(records))) stop("Run with the final diagnostic-ledger implementation.")
  stopifnot(nrow(records) == s$replicates, nrow(row) == 1L,
    row$attempted == s$replicates, row$accepted == sum(records$accepted),
    row$interval_available == sum(records$interval_available),
    row$precision_successes == sum(records$meets_width %in% TRUE),
    all(!records$interval_available | records$accepted),
    all(!records$accepted | is.na(records$acceptance_failures) | !nzchar(records$acceptance_failures)))
  for (name in names(records)[vapply(records, is.character, logical(1))])
    records[[name]] <- sanitize(records[[name]])
  context <- data.frame(cell_id = i, scenario = s$scenario, pilot_raters = s$pilot_raters,
    n_items = s$n_items, target_raters = s$target_raters, coefficient = "Phi")
  row <- cbind(context, row, generating_phi = s$var_item /
    (s$var_item + (s$var_rater + s$var_residual) / s$target_raters),
    boundary_fits = sum(records$boundary_fit %in% TRUE),
    elapsed_seconds = proc.time()[["elapsed"]] - cell_tick)
  for (entry in list(c("acceptance", row$accepted), c("refusal", row$refused),
                    c("interval", row$interval_available), c("precision_success", row$precision_successes)))
    row <- add_rate_interval(row, entry[[1L]], as.integer(entry[[2L]]), row$attempted)
  replicates[[i]] <- cbind(context[rep(1L, nrow(records)), ], records)
  summaries[[i]] <- row
  schedule$recorded[schedule$cell_id == i] <- TRUE
  save_csv(do.call(rbind, replicates), "replicates.csv")
  save_csv(do.call(rbind, summaries), "summary.csv")
  save_csv(schedule, "schedule.csv")
  metadata$attempted_refits <- sum(schedule$recorded)
  metadata$elapsed_seconds <- proc.time()[["elapsed"]] - tick
  save_json(metadata, "execution.json")
  cat("Completed", i, "of", nrow(config), "cells; retained", metadata$attempted_refits, "refits.\n")
}
after <- fingerprints()
save_csv(after, "postrun-source-files.csv")
stopifnot(identical(before, after), all(schedule$recorded))
metadata$complete <- TRUE
metadata$source_unchanged <- TRUE
metadata$finished_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
metadata$elapsed_seconds <- proc.time()[["elapsed"]] - tick
save_json(metadata, "execution.json")
cat("Completed all", nrow(schedule), "predeclared refits in", round(metadata$elapsed_seconds, 2), "seconds.\n")
