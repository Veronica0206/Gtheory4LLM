# Run from the repository: Rscript examples/real_data_workflow.R
# Or source this file from any working directory. The returned object retains
# all preflights, descriptive counts, fits, diagnostics, and expected failures.
# Only bundled modeling tables are read. Nothing is downloaded or written.

gt_real_data_workflow <- local({
  source_files <- lapply(sys.frames(), function(frame)
    get0("ofile", envir = frame, inherits = FALSE))
  source_files <- Filter(function(x) is.character(x) && length(x) == 1L, source_files)
  if (length(source_files)) {
    this_file <- tail(source_files, 1L)[[1L]]
  } else {
    file_arg <- commandArgs(trailingOnly = FALSE)
    file_arg <- file_arg[startsWith(file_arg, "--file=")]
    if (!length(file_arg)) stop("Run or source examples/real_data_workflow.R.")
    this_file <- sub("^--file=", "", file_arg[[1L]])
  }
  if (!file.exists(this_file)) this_file <- gsub("~+~", " ", this_file, fixed = TRUE)
  project <- dirname(dirname(normalizePath(this_file, mustWork = TRUE)))
  source(file.path(project, "load_functions.R"), local = environment())
  started <- proc.time()[["elapsed"]]

  # Keep binary flags, ordered labels, and unordered diagnoses distinct. The
  # alternative 7L/3L numeric mental-health codings are working scores, not
  # established clinical severity scales, and are not used in this audit.
  native_sets <- c("hate_speech", "mental_health_6flag", "mental_health_3group",
                   "mental_health_nominal", "drug_review", "drug_review_4aspect")
  audit <- setNames(lapply(native_sets, function(name) {
    example <- gt_example(name, coding = "native")
    # This is an explicit fully crossed reference specification. It requests
    # every interaction; it is not claimed to be the best scientific model.
    design <- gt_design(example$object, example$facets)
    preflight <- gt_preflight(example$data, example$outcomes, design,
                              family = example$families)
    frequency <- do.call(rbind, lapply(example$outcomes, function(outcome) {
      counts <- table(example$data[[outcome]])
      data.frame(outcome = outcome, category = names(counts), rows = as.integer(counts),
                 proportion = as.numeric(counts) / nrow(example$data), row.names = NULL)
    }))
    types <- data.frame(outcome = example$outcomes,
      storage_class = vapply(example$data[example$outcomes], function(x)
        paste(class(x), collapse = "/"), character(1)),
      family = vapply(example$families, `[[`, character(1), "family"), row.names = NULL)
    list(design = design, preflight = preflight, types = types,
         frequency = frequency, coding_notes = example$notes)
  }), native_sets)
  panels <- do.call(rbind, lapply(names(audit), function(name) {
    report <- audit[[name]]$preflight
    data.frame(outcome_set = name, rows = report$observations,
      objects = unname(report$observed_counts[["item"]]),
      outcomes = length(report$outcomes), latent_dimensions = report$predictor_dimensions,
      requested_random_dimensions = report$random_dimension,
      covariance_parameters = unname(report$parameters[["source_covariance"]]),
      dense_lower_bound_GiB = report$resources$dense_matrix_bytes_lower_bound / 1024^3,
      complete_balanced = report$complete_balanced_panel,
      fitting_feasible = report$fitting_feasible, row.names = NULL)
  }))
  stopifnot(all(panels$rows == 21600L), all(panels$objects == 100L),
            all(panels$complete_balanced), !any(panels$fitting_feasible))
  cat("Bundled native panels, preserving all requested source interactions:\n")
  print(panels, row.names = FALSE, digits = 5)
  cat("\nWhy the fully crossed Hate-Speech request is blocked:\n")
  report <- audit$hate_speech$preflight
  print(report$checks[!report$checks$passed, ], row.names = FALSE)
  cat("Kernel check:", report$kernel_check, "\n")
  cat("Counts above describe the requested model when source resolution fails.\n")
  cat("No real-data fit is attempted and no source is automatically removed.\n")

  # The remaining examples are small, hand-constructed diagnostic fixtures.
  # They are unrelated to the bundled annotations and are not a recovery or
  # interval-coverage experiment. Outcomes are never selected for a good fit.
  fixture <- expand.grid(occasion = seq_len(12), item = seq_len(8))
  fixture$y <- as.integer(fixture$occasion <= c(2, 3, 4, 5, 7, 8, 9, 10)[fixture$item])
  fixture$score <- sin(fixture$item) + fixture$occasion / 10 +
    cos(fixture$item * fixture$occasion) / 3
  full_design <- gt_design("item", "occasion")
  gaussian_panel <- gt_preflight(fixture, "score", full_design)
  gaussian_missing <- gt_preflight(fixture[-1, ], "score", full_design)
  discrete_alias <- gt_preflight(fixture, "y", full_design, gt_family("binary"))
  stopifnot(gaussian_panel$fitting_feasible, length(gaussian_panel$aliased_terms) == 1L,
            !gaussian_missing$fitting_feasible, !discrete_alias$fitting_feasible)
  cat("\nSynthetic structural examples:\n")
  cat("Gaussian complete panel: full-cell source combined with residual:",
      paste(gaussian_panel$aliased_terms, collapse = ", "), "\n")
  cat("Gaussian panel missing one cell: blocked.\n")
  cat("Binary full-cell source at one row per cell: blocked.\n")

  # A separate declared model illustrates exchangeable repetitions around an
  # item random intercept. It assumes no shared occasion effect; it is not a
  # repair of the fully crossed real-data design above.
  repeat_design <- gt_design("item", "occasion", random = ~ item)
  repeat_preflight <- gt_preflight(fixture, "y", repeat_design, gt_family("binary"))
  stopifnot(repeat_preflight$fitting_feasible)
  missing_discrete <- gt_preflight(fixture[-1, ], "y", repeat_design, gt_family("binary"))
  stopifnot(missing_discrete$fitting_feasible,
            length(missing_discrete$supported_reliability_scales) == 0L)

  capture_fit <- function(control) {
    messages <- character()
    result <- withCallingHandlers(
      tryCatch(gt_fit(fixture, "y", repeat_design, gt_family("binary", "logit"),
                     control = control), error = identity),
      warning = function(w) {
        messages <<- c(messages, conditionMessage(w))
        invokeRestart("muffleWarning")
      })
    list(result = result, warnings = messages)
  }
  # Deliberately disable restart checking to show why optimizer completion is
  # insufficient. This setting is for this failure demonstration only.
  unchecked <- capture_fit(gt_control(discrete = list(maxit = 150L,
                                                        alternative_starts = 0L)))
  checked <- capture_fit(gt_control(discrete = list(maxit = 150L,
    optimizer = "L-BFGS-B", alternative_starts = 1L)))
  fits <- list(restart_check_disabled = unchecked, default_acceptance = checked)
  fit_status <- do.call(rbind, lapply(names(fits), function(name) {
    fit <- fits[[name]]$result
    data.frame(example = name, returned_fit = inherits(fit, "gt_fit"),
      optimizer_completed = isTRUE(fit$optimizer_completed),
      numerically_accepted = isTRUE(fit$numerically_accepted),
      message = if (inherits(fit, "error")) conditionMessage(fit) else
        paste(gt_diagnostics(fit)$acceptance_failures, collapse = "; "), row.names = NULL)
  }))
  stopifnot(!isTRUE(unchecked$result$numerically_accepted))
  cat("\nSynthetic numerical examples (every outcome is retained):\n")
  print(fit_status, row.names = FALSE)
  expected_failure <- function(expression) {
    error <- tryCatch({ force(expression); NULL }, error = identity)
    if (!inherits(error, "error")) stop("The documented unsupported request unexpectedly succeeded.")
    conditionMessage(error)
  }
  rejected_coefficient <- if (inherits(unchecked$result, "gt_fit"))
    expected_failure(gt_reliability(unchecked$result, scale = "latent")) else
      "No usable fit was returned; inspect the retained failure condition."
  coefficient <- NULL
  unsupported_observed <- NULL
  diagnostics <- NULL
  if (inherits(checked$result, "gt_fit")) {
    diagnostics <- gt_diagnostics(checked$result)
    cat("Approximation adequacy:", diagnostics$approximation_adequacy, "\n")
    if (checked$result$numerically_accepted) {
      coefficient <- gt_reliability(checked$result, scale = "latent")
      cat("Synthetic latent coefficient; discrete intervals remain unavailable:\n")
      print(coefficient$per_trait, row.names = FALSE)
      stopifnot(!diagnostics$standard_errors_available,
                all(is.na(coefficient$per_trait$Erho2_se)),
                all(is.na(coefficient$per_trait$Erho2_lower)))
      unsupported_observed <- expected_failure(gt_reliability(checked$result, scale = "observed"))
    } else cat("Numerically rejected fit: no coefficient is calculated.\n")
  }
  cat("\nElapsed seconds:", round(proc.time()[["elapsed"]] - started, 2), "\n")
  cat("See docs/REAL_DATA_WORKFLOW.md for interpretation and next steps.\n")
  list(native_panels = panels, audit = audit,
    structural_examples = list(gaussian_complete = gaussian_panel,
      gaussian_missing_cell = gaussian_missing, discrete_full_cell = discrete_alias,
      discrete_repeated = repeat_preflight, discrete_missing_cell = missing_discrete),
    fits = fits, fit_status = fit_status, diagnostics = diagnostics,
    latent_coefficient = coefficient, rejected_coefficient_message = rejected_coefficient,
    unsupported_observed_message = unsupported_observed,
    elapsed_seconds = proc.time()[["elapsed"]] - started,
    environment = list(R = R.version.string, platform = R.version$platform,
      package_version = read.dcf(file.path(project, "DESCRIPTION"))[, "Version"]))
})
