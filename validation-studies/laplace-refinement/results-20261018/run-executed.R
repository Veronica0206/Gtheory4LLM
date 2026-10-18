# Usage: Rscript validation-studies/laplace-refinement/run.R OUTPUT_DIR [R_LIBRARY]
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("Supply a new output directory.")
out <- args[[1L]]
if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE)))
  stop("The output directory must be new or empty.")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
out <- normalizePath(out)
if (length(args) >= 2L) .libPaths(c(args[[2L]], .libPaths()))
library(Gtheory4LLM)

script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[[1L]])
study <- dirname(normalizePath(script))
root <- normalizePath(file.path(study, "../.."))
sources <- file.path(root, c("R/discrete_check.R", "man/gt_laplace_check.Rd",
  "tests/package-laplace-check.R", "validation-studies/laplace-refinement/PROTOCOL.md",
  "validation-studies/laplace-refinement/run.R"))
fingerprints <- function() system2("shasum", c("-a", "256", shQuote(sources)), stdout = TRUE)
before <- fingerprints()
writeLines(before, file.path(out, "source-sha256-before.txt"))
writeLines(c(paste("Started UTC:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  paste("Package version:", packageVersion("Gtheory4LLM")),
  paste("Installed path:", find.package("Gtheory4LLM")),
  paste("Source revision:", system2("git", c("-C", shQuote(root), "rev-parse", "HEAD"), stdout = TRUE)),
  "Source status:", system2("git", c("-C", shQuote(root), "status", "--short"), stdout = TRUE),
  "", capture.output(sessionInfo())), file.path(out, "environment.txt"))

b <- expand.grid(item = 1:3, rater = 1:8)
set.seed(11)
b$y <- rbinom(nrow(b), 1, plogis(c(-1, 0.2, 1.1)[b$item]))
write.csv(b, file.path(out, "fixture.csv"), row.names = FALSE)
fit <- gt_fit(b, "y", gt_design("item", "rater", random = ~ item),
  gt_family("binary", "logit"), control = gt_control(discrete = list(maxit = 200L)))
stopifnot(isTRUE(gt_diagnostics(fit)$numerically_accepted))
beta <- fit$parameters[[1L]]
variance <- gt_components(fit)$item[1L, 1L]
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
p <- fit$conditional_probabilities$y[, "1"]
precision <- 1 + variance * tapply(p * (1 - p), b$item, sum)
stopifnot(all(precision > 2))
write.csv(data.frame(intercept = beta, item_variance = variance,
  laplace_minus2loglik = deviance(fit), reference_minus2loglik = reference,
  reference_refinement_difference = reference - coarser_reference,
  original_proposal_precision_min = min(precision),
  original_proposal_precision_max = max(precision),
  defensive_prior_weight = 0.1, importance_weight_upper_bound = 10),
  file.path(out, "reference.csv"), row.names = FALSE)
write.csv(data.frame(item = names(precision), precision = as.numeric(precision)),
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
writeLines(after, file.path(out, "source-sha256-after.txt"))
stopifnot(identical(before, after))
writeLines(c(paste("Completed UTC:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  "80 planned diagnostic runs retained; no model refits after the initial fixture.",
  "The source fingerprints listed in this study were unchanged during execution.",
  "Scope: one binary-logit fixture; finite weight moments do not establish general MCSE calibration."),
  file.path(out, "completion.txt"))
print(summary, row.names = FALSE)
