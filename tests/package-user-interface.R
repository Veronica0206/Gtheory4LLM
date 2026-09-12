# Installed interfaces must be reproducible in a user's existing workspace.
library(Gtheory4LLM)

local({
  had_directory <- exists(".gt_example_data_dir", envir = .GlobalEnv, inherits = FALSE)
  if (had_directory) original_directory <- get(".gt_example_data_dir", envir = .GlobalEnv)
  on.exit({
    if (had_directory) assign(".gt_example_data_dir", original_directory, envir = .GlobalEnv)
    else rm(".gt_example_data_dir", envir = .GlobalEnv)
  })
  baseline <- gt_example("hate_speech")
  assign(".gt_example_data_dir", "/this/global/path/must/never/be/read", envir = .GlobalEnv)
  isolated <- gt_example("hate_speech")
  stopifnot(identical(baseline, isolated),
    startsWith(normalizePath(isolated$source), normalizePath(system.file(package = "Gtheory4LLM"))))

  # Intentional overrides remain available and cannot silently fall back.
  directory <- tempfile("gt-explicit-csv-")
  dir.create(directory)
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  raw <- expand.grid(item_id = 1:2, evaluator = c("alpha", "beta"),
    prompt_type = c("short", "long"), temperature = 0, seed = 1)
  raw$severity <- rep(1:3, length.out = nrow(raw))
  utils::write.csv(raw, file.path(directory, "hate_labeling_final.csv"), row.names = FALSE)
  explicit <- gt_example("hate_speech", directory = directory)
  stopifnot(nrow(explicit$data) == nrow(raw), is.ordered(explicit$data$score),
    identical(as.integer(explicit$data$score), raw$severity),
    startsWith(explicit$source, normalizePath(directory)))
  resource_path <- file.path(directory, "hate_speech.rds")
  stopifnot(file.copy(baseline$source, resource_path))
  rds_selected <- gt_example("hate_speech", directory = directory)
  stopifnot(identical(rds_selected$data, baseline$data),
    identical(rds_selected$source, normalizePath(resource_path)))
  saveRDS(list(schema_version = 999L), resource_path)
  error <- tryCatch(gt_example("hate_speech", directory = directory), error = identity)
  stopifnot(inherits(error, "error"), grepl("unsupported schema", conditionMessage(error), fixed = TRUE))
  unlink(resource_path)
  for (bad in list(character(), c(directory, directory), NA_character_, "", 1)) {
    error <- tryCatch(gt_example("hate_speech", directory = bad), error = identity)
    stopifnot(inherits(error, "error"),
      grepl("directory must be", conditionMessage(error), fixed = TRUE))
  }
  error <- tryCatch(gt_example("hate_speech", directory = file.path(directory, "missing")), error = identity)
  stopifnot(inherits(error, "error"), grepl("CSV file not found", conditionMessage(error), fixed = TRUE))
})
cat("PASS: installed examples ignore ambient state, honor RDS/CSV selection, and reject invalid resources.\n")

d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42, extra_tries = 2)))
diagnostics <- gt_diagnostics(fit)
selected <- as.character(fit$retry_attempts$attempt[fit$retry_attempts$returned_fit])
if (!length(selected)) selected <- NA_character_
stopifnot(fit$numerically_accepted,
  identical(diagnostics$selected_attempt, selected),
  identical(diagnostics$optimization_trials, nrow(fit$retry_attempts)),
  !length(diagnostics$acceptance_failures))
fit$data$private_marker <- "OBSERVATION_CONTENT_MUST_NOT_PRINT"
s <- summary(fit)
stopifnot(inherits(s, "summary.gt_fit"), is.function(getS3method("print", "summary.gt_fit")),
  identical(s$minus2loglik, fit$minus2loglik),
  isTRUE(all.equal(s$covariance_components, gt_components(fit))),
  identical(s$variances$source, c("item", "rater", "Residual")),
  !any(c("model", "backend_fit", "data", "prepared") %in% names(s)))
output <- capture.output(returned <- print(s, digits = 4))
stopifnot(identical(returned, s), length(output) < 45L,
  any(grepl("Selected attempt:", output, fixed = TRUE)),
  any(grepl("Source variances", output, fixed = TRUE)),
  !any(grepl("OBSERVATION_CONTENT_MUST_NOT_PRINT|MxModel|\\$data", output)))
for (bad in list(0, 23, 2.5, NA_real_, "3", c(2, 3))) {
  error <- tryCatch(print(s, digits = bad), error = identity)
  stopifnot(inherits(error, "error"))
}

# A missing native trial match must remain unknown, not default to trial 1.
unidentified <- fit
unidentified$retry_attempts$returned_fit[] <- FALSE
stopifnot(is.na(gt_diagnostics(unidentified)$selected_attempt),
  any(grepl("Selected attempt: not identified", capture.output(print(unidentified)), fixed = TRUE)))
cat("PASS: classed Gaussian summaries preserve estimates without dumping models or data.\n")

# The zero-random-variation limit gives an independently checkable binary fit.
d <- expand.grid(item = 1:6, rater = 1:3)
d$binary <- rep(c(0L, 1L, 1L), length.out = nrow(d))
binary <- gt_fit(d, "binary", design, gt_family("binary", "logit"),
  control = gt_control(discrete = list(fixed_covariance =
    list(item = matrix(0, 1, 1), rater = matrix(0, 1, 1)))))
ds <- summary(binary)
stopifnot(binary$numerically_accepted,
  identical(ds$diagnostics$selected_attempt, binary$diagnostics$selected_attempt),
  identical(ds$diagnostics$approximation_adequacy, "exact_no_random_variation"),
  setequal(ds$diagnostics$boundary_sources, c("item", "rater")),
  !length(ds$diagnostics$acceptance_failures))

# Exercise presentation of a recorded rejected-fit state separately from the
# acceptance algorithm. Printing must never reinterpret rejection as success.
rejected <- binary
rejected$numerically_accepted <- FALSE
rejected$diagnostics$acceptance_failures <- c("outer_stationarity_failed", "artificial_parameter_bound_contact")
rejected$diagnostics$parameter_bounds <- "source_variance_lower_bound"
rejected$diagnostics$approximation_adequacy <- "not_assessed_first_order_laplace"
rejected$approximation_adequacy <- "not_assessed_first_order_laplace"
rejected$diagnostics$attempts[[1]]$error <- "recorded trial failure"
rejected$diagnostics$attempts[[1]]$optimizer_code <- 100L
rd <- gt_diagnostics(rejected)
output <- capture.output(print(summary(rejected)))
stopifnot(identical(rd$acceptance_failures, rejected$diagnostics$acceptance_failures),
  nrow(rd$attempt_failures) >= 1L,
  any(grepl("Numerically accepted: FALSE", output, fixed = TRUE)),
  any(grepl("outer_stationarity_failed", output, fixed = TRUE)),
  any(grepl("Artificial parameter bounds:", output, fixed = TRUE)),
  any(grepl("not_assessed_first_order_laplace", output, fixed = TRUE)),
  any(grepl("diagnostic only", output, fixed = TRUE)),
  !rejected$numerically_accepted)
cat("PASS: summaries distinguish rejected trials, natural boundaries, artificial bounds, and approximation adequacy.\n")
