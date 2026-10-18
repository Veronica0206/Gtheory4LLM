# Usage: Rscript validation-studies/laplace-refinement/run.R OUTPUT_DIR [R_LIBRARY]
# Alternatively, set GT_STUDY_LIBRARY for archive-based execution.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("Supply a new output directory.")
out <- args[[1L]]
if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE)))
  stop("The output directory must be new or empty.")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
out <- normalizePath(out)
study_library <- if (length(args) >= 2L && nzchar(args[[2L]])) args[[2L]] else
  Sys.getenv("GT_STUDY_LIBRARY", unset = "")
archive_mode <- nzchar(study_library)
if (archive_mode) .libPaths(c(study_library, .libPaths()))
for (dependency in c("digest", "jsonlite"))
  if (!requireNamespace(dependency, quietly = TRUE)) stop("Install the study dependency ", dependency, ".")
library(Gtheory4LLM)

script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]])
# Some R launch paths encode spaces in --file even though trailing arguments
# are ordinary paths. Preserve a literal existing path before decoding it.
if (!file.exists(script)) script <- gsub("~+~", " ", script, fixed = TRUE)
script <- normalizePath(script)
study <- dirname(normalizePath(script))
protocol <- file.path(study, "PROTOCOL.md")
if (!file.exists(protocol)) stop("Keep PROTOCOL.md beside the study runner.")
stopifnot(file.copy(script, file.path(out, "run-executed.R"), overwrite = FALSE),
          file.copy(protocol, file.path(out, "PROTOCOL.md"), overwrite = FALSE))
installed_path <- normalizePath(find.package("Gtheory4LLM"))
installed_relative <- list.files(installed_path, recursive = TRUE, all.files = TRUE, no.. = TRUE)
installed_relative <- installed_relative[!file.info(file.path(installed_path, installed_relative))$isdir]
sources <- c(file.path(installed_path, installed_relative), script, protocol)
source_labels <- c(paste0("installed/Gtheory4LLM/", installed_relative), "study/run.R", "study/PROTOCOL.md")
source_commit <- NULL
source_status <- "Not queried: archive-based mode records installed package identity, not a source-commit claim."
if (!archive_mode) {
  root <- normalizePath(file.path(study, "../.."))
  relative <- c("R/discrete_check.R", "man/gt_laplace_check.Rd", "tests/package-laplace-check.R")
  if (!all(file.exists(file.path(root, relative))))
    stop("Outside the package source tree, supply R_LIBRARY or set GT_STUDY_LIBRARY for archive-based execution.")
  sources <- c(sources, file.path(root, relative))
  source_labels <- c(source_labels, paste0("source/", relative))
  source_commit <- system2("git", c("-C", shQuote(root), "rev-parse", "HEAD"), stdout = TRUE)
  source_status <- system2("git", c("-C", shQuote(root), "status", "--short"), stdout = TRUE)
}
fingerprints <- function() data.frame(file = source_labels,
  sha256 = vapply(sources, function(path) digest::digest(file = path, algo = "sha256"), character(1)),
  row.names = NULL, stringsAsFactors = FALSE)
before <- fingerprints()
write.csv(before, file.path(out, "source-sha256-before.csv"), row.names = FALSE)
execution <- list(complete = FALSE, attempted_runs = 0L, planned_runs = 80L,
  mode = if (archive_mode) "installed_archive" else "source_tree",
  started_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  package_version = as.character(packageVersion("Gtheory4LLM")), installed_path = installed_path,
  source_commit = source_commit, source_status = source_status, source_hashes = before)
write_execution <- function() jsonlite::write_json(execution, file.path(out, "execution.json"),
  pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null")
write_execution()
writeLines(c(paste("Started UTC:", execution$started_utc), paste("Execution mode:", execution$mode),
  paste("Package version:", packageVersion("Gtheory4LLM")),
  paste("Installed path:", installed_path),
  paste("Source revision:", if (is.null(source_commit)) "not claimed in archive-based mode" else source_commit),
  "Source status:", source_status,
  "", capture.output(sessionInfo())), file.path(out, "environment.txt"))

b <- expand.grid(item = 1:3, rater = 1:8)
set.seed(11)
b$y <- rbinom(nrow(b), 1, plogis(c(-1, 0.2, 1.1)[b$item]))
write.csv(b, file.path(out, "fixture.csv"), row.names = FALSE)
fit <- gt_fit(b, "y", gt_design("item", "rater", random = ~ item),
  gt_family("binary", "logit"), control = gt_control(discrete = list(maxit = 200L)))
stopifnot(isTRUE(gt_diagnostics(fit)$numerically_accepted))
beta <- unname(coef(fit)[[1L]])
variance <- gt_components(fit)$item[1L, 1L]
stopifnot(is.finite(beta), is.finite(variance), variance > 0)
reference_at <- function(tolerance) -2 * sum(vapply(1:3, function(i) {
  y <- b$y[b$item == i]
  log(integrate(function(u) vapply(u, function(value)
    exp(sum(dbinom(y, 1, plogis(beta + sqrt(variance) * value), log = TRUE))), numeric(1)) * dnorm(u),
    -Inf, Inf, rel.tol = tolerance, abs.tol = tolerance * 1e-3,
    subdivisions = 2000L, stop.on.error = TRUE)$value)
}, numeric(1)))
reference <- reference_at(1e-12)
coarser_reference <- reference_at(1e-10)
stopifnot(abs(reference - coarser_reference) < 1e-8)
# Independently solve each standardized random intercept's posterior score.
# Its derivative is strictly negative, and +/- sqrt(variance) * n brackets
# the unique root because every Bernoulli residual lies between -1 and 1.
item_ids <- sort(unique(b$item))
conditional_modes <- vapply(item_ids, function(i) {
  y <- b$y[b$item == i]
  score <- function(u) sqrt(variance) * sum(y - plogis(beta + sqrt(variance) * u)) - u
  bound <- sqrt(variance) * length(y)
  uniroot(score, c(-bound, bound), tol = 1e-12)$root
}, numeric(1))
conditional_probabilities <- plogis(beta + sqrt(variance) * conditional_modes)
precision <- 1 + variance * as.numeric(table(factor(b$item, levels = item_ids))) *
  conditional_probabilities * (1 - conditional_probabilities)
stopifnot(all(precision > 2))
write.csv(data.frame(intercept = beta, item_variance = variance,
  laplace_minus2loglik = deviance(fit), reference_minus2loglik = reference,
  reference_refinement_difference = reference - coarser_reference,
  original_proposal_precision_min = min(precision),
  original_proposal_precision_max = max(precision),
  defensive_prior_weight = 0.1, importance_weight_upper_bound = 10),
  file.path(out, "reference.csv"), row.names = FALSE)
write.csv(data.frame(item = item_ids, conditional_mode = conditional_modes,
  precision = as.numeric(precision)),
  file.path(out, "original-proposal-hessian.csv"), row.names = FALSE)

records <- list()
budgets <- c(2000L, 20000L)
for (j in seq_along(budgets)) for (replicate in seq_len(40L)) {
  seed <- 70000L + j * 1000L + replicate
  started <- proc.time()[["elapsed"]]
  check <- tryCatch(gt_laplace_check(fit, method = "importance", draws = budgets[[j]], seed = seed),
                    error = identity)
  row <- data.frame(draws = budgets[[j]], replicate = replicate, seed = seed,
    available = FALSE, usable = FALSE, estimate = NA_real_, error = NA_real_,
    mc_se = NA_real_, effective_sample_size = NA_real_, maximum_weight = NA_real_,
    prior_draws = NA_integer_, gaussian_draws = NA_integer_, contains_reference = NA,
    reason = "", elapsed_seconds = proc.time()[["elapsed"]] - started)
  if (inherits(check, "error")) {
    row$reason <- conditionMessage(check)
  } else {
    row$available <- isTRUE(check$available)
    row$usable <- isTRUE(check$usable)
    row$estimate <- check$refined_minus2loglik
    row$error <- check$refined_minus2loglik - reference
    row$mc_se <- check$mc_se
    row$effective_sample_size <- check$effective_sample_size
    row$maximum_weight <- check$max_importance_weight
    if (length(check$proposal_draws) == 2L) {
      row$prior_draws <- unname(check$proposal_draws[["standard_normal_prior"]])
      row$gaussian_draws <- unname(check$proposal_draws[["laplace_gaussian"]])
    }
    row$contains_reference <- is.finite(row$error) && is.finite(row$mc_se) &&
      abs(row$error) <= 1.96 * row$mc_se
    row$reason <- check$reason
  }
  records[[length(records) + 1L]] <- row
  write.csv(do.call(rbind, records), file.path(out, "replicates.csv"), row.names = FALSE)
  execution$attempted_runs <- length(records)
  write_execution()
  if (replicate %% 10L == 0L) {
    cat("Completed", replicate, "of 40 at", budgets[[j]], "draws\n")
    flush.console()
  }
}
records <- do.call(rbind, records)
summary <- do.call(rbind, lapply(budgets, function(budget) {
  all <- records[records$draws == budget, ]
  finite <- all[all$available & is.finite(all$error) & is.finite(all$mc_se), ]
  n <- nrow(finite)
  coverage <- sum(finite$contains_reference)
  ci <- if (n) binom.test(coverage, n)$conf.int else c(NA_real_, NA_real_)
  data.frame(draws = budget, attempted = nrow(all), finite_results = n,
    screen_passes = sum(all$usable), mean_error = mean(finite$error),
    mean_error_mcse = sd(finite$error) / sqrt(n), empirical_sd = sd(finite$error),
    rmse = sqrt(mean(finite$error^2)), mean_reported_mcse = mean(finite$mc_se),
    rms_reported_mcse = sqrt(mean(finite$mc_se^2)), nominal95_contains_reference = coverage,
    nominal95_fraction = coverage / n, nominal95_fraction_lower = ci[[1L]],
    nominal95_fraction_upper = ci[[2L]], maximum_observed_weight = max(finite$maximum_weight))
}))
write.csv(summary, file.path(out, "summary.csv"), row.names = FALSE)
after <- fingerprints()
write.csv(after, file.path(out, "source-sha256-after.csv"), row.names = FALSE)
execution$postrun_source_hashes <- after
execution$source_hashes_unchanged <- identical(before, after)
write_execution()
stopifnot(identical(before, after))
execution$complete <- TRUE
execution$completed_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
write_execution()
writeLines(c(paste("Completed UTC:", execution$completed_utc),
  "80 planned diagnostic runs retained; no model refits after the initial fixture.",
  "The source fingerprints listed in this study were unchanged during execution.",
  "Scope: one binary-logit fixture; finite weight moments do not establish general MCSE calibration."),
  file.path(out, "completion.txt"))
print(summary, row.names = FALSE)
