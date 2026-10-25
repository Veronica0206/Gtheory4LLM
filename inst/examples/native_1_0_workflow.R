# Installed, opt-in reproduction workflow. Sourcing this file only defines functions.
# source(system.file("examples", "native_1_0_workflow.R", package = "Gtheory4LLM"))
# gt_native_workflow("smoke", tempfile("gt-smoke-"))
# Full runs use BOTH original 21,600-row panels and can take many hours.
# Start R with OMP_NUM_THREADS, OPENBLAS_NUM_THREADS, MKL_NUM_THREADS and
# VECLIB_MAXIMUM_THREADS all set to 1. Install archive_path in an isolated
# library first; its digest records the supplied archive, not proof that the
# loaded namespace was installed from it. See docs/REAL_DATA_WORKFLOW.md.

.gt_native_table <- function(components) {
  do.call(rbind, lapply(names(components), function(source) {
    x <- components[[source]]
    data.frame(source = source, row = rep(rownames(x), ncol(x)),
      column = rep(colnames(x), each = nrow(x)), covariance = as.vector(x),
      stringsAsFactors = FALSE)
  }))
}

# Key and finiteness checks precede arithmetic: empty/misaligned/NA tables
# must never silently satisfy a numerical replay gate.
.gt_native_difference <- function(actual, reference, keys, values, scaled = FALSE) {
  bad <- function(reason) list(valid = FALSE, difference = NA_real_, reason = reason)
  needed <- c(keys, values)
  if (!is.data.frame(actual) || !is.data.frame(reference) ||
      !all(needed %in% names(actual)) || !all(needed %in% names(reference)) ||
      !nrow(actual) || nrow(actual) != nrow(reference)) return(bad("missing rows or columns"))
  key <- function(x) do.call(paste, c(x[keys], sep = "\r"))
  a <- key(actual); r <- key(reference)
  if (anyNA(actual[keys]) || anyNA(reference[keys]) || anyDuplicated(a) ||
      anyDuplicated(r) || !setequal(a, r)) return(bad("keys differ or are duplicated"))
  if (!all(vapply(actual[values], is.numeric, logical(1))) ||
      !all(vapply(reference[values], is.numeric, logical(1)))) return(bad("values are not numeric"))
  x <- as.matrix(actual[match(r, a), values, drop = FALSE])
  y <- as.matrix(reference[values])
  if (any(!is.finite(x)) || any(!is.finite(y))) return(bad("non-finite values"))
  delta <- abs(x - y)
  if (scaled) delta <- delta / pmax(1, abs(y))
  list(valid = TRUE, difference = max(delta), reason = "")
}

.gt_native_compare <- function(deviance, components, reliability, single, numerically_accepted,
                               reference, tolerance) {
  if (!is.list(reference$platforms) || !identical(sort(names(reference$platforms)), c("linux", "mac")))
    stop("Both distinct historical platform references are required.", call. = FALSE)
  do.call(rbind, lapply(names(reference$platforms), function(platform) {
    r <- reference$platforms[[platform]]
    component <- .gt_native_difference(components, r$components,
      c("source", "row", "column"), "covariance", TRUE)
    coefficient <- .gt_native_difference(reliability, r$reliability, "outcome", c("Erho2", "Phi"))
    one <- .gt_native_difference(single, r$reliability_single, "outcome", c("Erho2", "Phi"))
    valid_deviance <- is.numeric(deviance) && length(deviance) == 1L && is.finite(deviance) &&
      is.numeric(r$deviance) && length(r$deviance) == 1L && is.finite(r$deviance)
    difference <- if (valid_deviance) abs(deviance - r$deviance) else NA_real_
    acceptance_matches <- isTRUE(numerically_accepted) && isTRUE(r$accepted)
    valid <- valid_deviance && component$valid && coefficient$valid && one$valid
    passed <- valid && acceptance_matches && difference <= tolerance$deviance_absolute &&
      component$difference <= tolerance$component_scaled &&
      coefficient$difference <= tolerance$reliability_absolute &&
      one$difference <= tolerance$reliability_absolute
    data.frame(reference_platform = platform, valid = valid, passed = passed,
      numerical_acceptance_matches = acceptance_matches,
      deviance_absolute_difference = difference, component_scaled_difference = component$difference,
      reliability_absolute_difference = coefficient$difference,
      single_reliability_absolute_difference = one$difference,
      reason = if (passed) "complete historical platform reference matched" else
        if (!acceptance_matches) "numerical acceptance differs or is unavailable" else
        if (valid) "tolerance exceeded" else
        paste(c(if (!valid_deviance) "non-finite deviance", component$reason, coefficient$reason, one$reason)[
          nzchar(c(if (!valid_deviance) "non-finite deviance", component$reason, coefficient$reason, one$reason))], collapse = "; "),
      stringsAsFactors = FALSE)
  }))
}

.gt_native_uncertainty_compare <- function(uncertainty, reliability, single, reference, tolerance) {
  expected <- reference$conditional
  available <- isTRUE(uncertainty$available) && isTRUE(expected$available)
  conditional <- isTRUE(uncertainty$conditional) && isTRUE(expected$conditional)
  fixed <- uncertainty$fixed_components
  held <- is.character(fixed) && !anyNA(fixed) && !anyDuplicated(fixed) &&
    setequal(fixed, expected$fixed_components)
  columns <- c("Erho2_se", "Erho2_lower", "Erho2_upper", "Phi_se", "Phi_lower", "Phi_upper")
  full <- .gt_native_difference(reliability, expected$reliability, "outcome", columns)
  one <- .gt_native_difference(single, expected$reliability_single, "outcome", columns)
  metadata <- function(x) {
    flags <- c("uncertainty_available", "uncertainty_conditional", "Erho2_interval_available", "Phi_interval_available")
    is.data.frame(x) && all(flags %in% names(x)) && nrow(x) > 0L &&
      all(vapply(x[flags], function(v) is.logical(v) && !anyNA(v) && all(v), logical(1)))
  }
  coherent <- function(x) is.data.frame(x) && all(c(columns, "Erho2", "Phi") %in% names(x)) &&
    all(vapply(x[c(columns, "Erho2", "Phi")], function(v) is.numeric(v) && all(is.finite(v)), logical(1))) &&
    all(x$Erho2_se > 0 & x$Phi_se > 0 & x$Erho2_lower <= x$Erho2 & x$Erho2 <= x$Erho2_upper &
      x$Phi_lower <= x$Phi & x$Phi <= x$Phi_upper & x$Erho2_lower >= 0 & x$Phi_lower >= 0 &
      x$Erho2_upper <= 1 & x$Phi_upper <= 1)
  intervals <- metadata(reliability) && metadata(single) && coherent(reliability) && coherent(single)
  passed <- available && conditional && held && intervals && full$valid && one$valid &&
    full$difference <= tolerance$conditional_interval_absolute && one$difference <= tolerance$conditional_interval_absolute
  data.frame(available_matches = available, conditional_matches = conditional,
    held_sources_match = held, finite_intervals_and_metadata = intervals,
    full_interval_absolute_difference = full$difference, single_interval_absolute_difference = one$difference,
    tolerance = tolerance$conditional_interval_absolute, passed = passed,
    expected_held_sources = paste(expected$fixed_components, collapse = ";"),
    reference_held_kinds = paste(expected$fixed_component_kinds, collapse = ";"),
    actual_held_sources = paste(fixed, collapse = ";"),
    reference_scope = "Saved macOS information-only arithmetic; coverage and Linux information unassessed.",
    reason = if (passed) "conditional arithmetic reference matched" else
      "Conditional availability, held sources, interval metadata or numerical comparison did not match.",
    stringsAsFactors = FALSE)
}

.gt_native_smoke <- function() {
  # Separate synthetic fixture; no rows from the native data are sampled.
  old_kind <- RNGkind()
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv)
    else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
      rm(".Random.seed", envir = .GlobalEnv)
  })
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(9001L)
  d <- expand.grid(rater = factor(seq_len(6L)), item = factor(seq_len(18L)))
  eta <- .3 + rnorm(18L, sd = .9)[d$item] + rnorm(6L, sd = .5)[d$rater]
  d$label <- rbinom(nrow(d), 1L, plogis(eta))
  set.seed(4242L)
  eta <- rnorm(18L, sd = .8)[d$item] + rnorm(6L, sd = .4)[d$rater] + rnorm(nrow(d))
  d$grade <- ordered(c("low", "mid", "high")[1L + (eta > -.7) + (eta > .6)],
    levels = c("low", "mid", "high"))
  list(data = d, formula = cbind(label, grade) ~ item + rater,
    family = list(label = Gtheory4LLM::gt_family("binary"), grade = Gtheory4LLM::gt_family("ordinal")),
    counts = c(rater = 1L), allocations = data.frame(rater = c(1L, 6L)), control = Gtheory4LLM::gt_control(discrete = list(
      engine = "sparse", covariance_parameterization = "cholesky", gradient = "analytic",
      boundary_escape = "projected", maxit = 300L, check_hessian = TRUE)),
    scope = "Independent 108-row synthetic binary/ordinal smoke; no native model qualification.")
}

.gt_native_spec <- function(id) {
  dataset <- if (id == "drug_review_efficacy_safety") "drug_review_4aspect" else "mental_health_3group"
  example <- Gtheory4LLM::gt_example(dataset, coding = "native")
  outcomes <- if (id == "drug_review_efficacy_safety") c("efficacy", "safety") else
    c("stress", "anxiety_depression", "bipolar_personality_suicidal")
  columns <- c("item", "evaluator", "prompt", "temp", "seed", outcomes)
  formula <- stats::as.formula(paste0("cbind(", paste(outcomes, collapse = ","),
    ") ~ item * evaluator * prompt + evaluator:prompt:temp + ",
    "evaluator:prompt:temp:seed + item:evaluator:prompt:temp"))
  # Every control used by the frozen driver is explicit, including defaults
  # that would otherwise change if the package later changed its defaults.
  control <- Gtheory4LLM::gt_control(discrete = list(engine = "sparse",
    covariance_parameterization = "cholesky", optimizer = "L-BFGS-B",
    optimizer_scaling = "start", max_observations = 21600L,
    max_random_dimension = 60000L, max_parameters = 240L,
    max_sparse_bytes = 8 * 1024^3, max_dense_bytes = 512 * 1024^2,
    maxit = 2000L, check_hessian = TRUE, trace = 1L,
    boundary_escape = "projected", gradient = "analytic",
    hessian_step = .001, hessian_tolerance = .05,
    inner_maxit = 60L, inner_tol = 1e-7, reltol = 1e-7, start_sd = .4,
    fixed_covariance = NULL, stationarity_tol = .001,
    validation_reltol = 1e-10, validation_inner_tol = 1e-9,
    alternative_starts = 1L, stability_objective_tol = 1e-6,
    stability_parameter_tol = .02, bound_tol = 1e-4, start = NULL))
  list(data = example$data[columns], formula = formula, family = example$families[outcomes],
    control = control, counts = c(evaluator = 1L, prompt = 1L, temp = 1L, seed = 1L),
    allocations = data.frame(evaluator = c(1L, 4L), prompt = c(1L, 3L), temp = c(1L, 6L), seed = c(1L, 3L)),
    scope = paste("Complete 21,600-row native panel; ten random sources;", length(outcomes),
      "outcomes; unstructured source covariance; probit links; automatic starts."))
}

# No fitting occurs until this function is explicitly called. An existing output
# path is always refused, including an empty directory or a previous failed run.
gt_native_workflow <- function(mode = c("smoke", "full"), output_dir,
                               models = NULL, archive_path = NULL) {
  mode <- match.arg(mode)
  if (!requireNamespace("Gtheory4LLM", quietly = TRUE)) stop("Install Gtheory4LLM first.", call. = FALSE)
  if (!is.character(output_dir) || length(output_dir) != 1L || is.na(output_dir) || !nzchar(output_dir))
    stop("output_dir must be one new directory path.", call. = FALSE)
  if (file.exists(output_dir) || dir.exists(output_dir)) stop("output_dir already exists; choose a new path.", call. = FALSE)
  allowed <- if (mode == "full") c("drug_review_efficacy_safety", "mental_health_3group") else "synthetic_joint"
  if (is.null(models)) models <- allowed
  if (!is.character(models) || !length(models) || anyNA(models) || anyDuplicated(models) || !all(models %in% allowed))
    stop("models must be distinct names among: ", paste(allowed, collapse = ", "), call. = FALSE)
  if (!is.null(archive_path) && (!is.character(archive_path) || length(archive_path) != 1L ||
      is.na(archive_path) || !file.exists(archive_path) || dir.exists(archive_path)))
    stop("archive_path must identify an existing source archive.", call. = FALSE)
  if (!dir.create(output_dir, recursive = TRUE)) stop("Cannot create output_dir.", call. = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = TRUE)
  write_csv <- function(x, file) utils::write.csv(x, file.path(output_dir, file), row.names = FALSE, na = "NA")
  env <- new.env(parent = baseenv())
  sys.source(system.file("examples", "native_1_0_reference.R", package = "Gtheory4LLM", mustWork = TRUE), env)
  reference <- env$.gt_native_reference
  hash <- function(path) unname(tools::sha256sum(path))
  thread_names <- c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS")
  threads <- Sys.getenv(thread_names, unset = NA_character_)
  session <- utils::sessionInfo()
  installed <- find.package("Gtheory4LLM")
  provenance <- list(mode = mode, started_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    package_version = as.character(utils::packageVersion("Gtheory4LLM")), installed_package = installed,
    supplied_archive = if (is.null(archive_path)) NA_character_ else normalizePath(archive_path),
    supplied_archive_sha256 = if (is.null(archive_path)) NA_character_ else hash(archive_path),
    archive_identity_scope = "Supplied bytes only; install this archive into an isolated library before starting R. This field alone cannot prove namespace/archive correspondence.",
    installed_description_sha256 = hash(file.path(installed, "DESCRIPTION")),
    installed_example_sha256 = hash(system.file("examples", "native_1_0_workflow.R", package = "Gtheory4LLM")),
    installed_reference_sha256 = hash(system.file("examples", "native_1_0_reference.R", package = "Gtheory4LLM")),
    threads = stats::setNames(threads, thread_names), R = R.version.string,
    platform = R.version$platform, BLAS = session$BLAS, LAPACK = session$LAPACK,
    reference = reference$provenance, tolerance = reference$tolerance,
    limit_scope = "Package preflight memory limits are estimates, not an OS memory or wall-time cap. Full fits may take many hours.")
  dput(provenance, file.path(output_dir, "provenance.R"))
  writeLines(capture.output(session), file.path(output_dir, "session-info.txt"))
  status <- data.frame(model = models, mode = mode, status = "not_started", numerical_acceptance = NA,
    observed_information = "unavailable", uncertainty_scope = "unavailable",
    uncertainty_reference_comparison = if (mode == "full") "unavailable" else "not_applicable_synthetic", reference_comparison = if (mode == "full") "unavailable" else "not_applicable_synthetic",
    matched_reference_platform = NA_character_, deviance = NA_real_, elapsed_seconds = NA_real_, reason = "",
    stringsAsFactors = FALSE)
  write_csv(status, "status.csv")
  prerequisite <- if (mode == "full" && is.null(archive_path)) "Full replay requires archive_path for the installed source archive." else
    if (mode == "full" && !all(!is.na(threads) & threads == "1"))
      "Full replay requires all four thread environment variables set to 1 before R starts." else NULL
  if (mode == "full" && is.null(prerequisite)) {
    archive_check <- tryCatch({
      member <- "Gtheory4LLM/DESCRIPTION"
      if (!member %in% utils::untar(archive_path, list = TRUE))
        stop("archive_path is not a Gtheory4LLM source archive.")
      stage <- tempfile("gt-archive-metadata-"); dir.create(stage)
      on.exit(unlink(stage, recursive = TRUE), add = TRUE)
      utils::untar(archive_path, files = member, exdir = stage)
      description <- read.dcf(file.path(stage, member))
      if (!identical(unname(description[1L, "Package"]), "Gtheory4LLM") ||
          !identical(unname(description[1L, "Version"]), provenance$package_version))
        stop("Archive package/version differs from the installed package.")
      TRUE
    }, error = identity)
    if (inherits(archive_check, "error")) prerequisite <- conditionMessage(archive_check)
  }
  for (i in seq_along(models)) {
    id <- models[[i]]; model_dir <- file.path(output_dir, id); dir.create(model_dir)
    if (!is.null(prerequisite)) {
      status$status[[i]] <- "refused"; status$reason[[i]] <- prerequisite
      writeLines(prerequisite, file.path(model_dir, "status.txt")); write_csv(status, "status.csv"); next
    }
    status$status[[i]] <- "running"; write_csv(status, "status.csv")
    started <- Sys.time(); warnings <- character()
    tryCatch(withCallingHandlers({
      spec <- if (mode == "smoke") .gt_native_smoke() else .gt_native_spec(id)
      if (mode == "full") {
        r <- reference$models[[id]]
        observed_hash <- hash(system.file("extdata", paste0(r$dataset, ".rds"), package = "Gtheory4LLM", mustWork = TRUE))
        dput(list(dataset = r$dataset, installed_data_sha256 = observed_hash,
          expected_data_sha256 = r$data_sha256, historical_request_sha256 = r$request_sha256,
          historical_reference_csv_sha256 = r$reference_files_sha256), file.path(model_dir, "data-provenance.R"))
        if (!identical(observed_hash, r$data_sha256)) stop("Native data hash differs from the frozen reference; comparison is unavailable.")
        if (nrow(spec$data) != 21600L || !all(vapply(spec$family, function(f) identical(f$link, "probit"), logical(1))))
          stop("Native row-count or probit-family protocol differs from the frozen request.")
      }
      dput(list(formula = spec$formula, measured = "item", covariance = "unstructured",
        family = spec$family, control = spec$control, single_counts = spec$counts,
        dstudy_allocations = spec$allocations, scope = spec$scope),
        file.path(model_dir, "protocol.R"))
      preflight <- Gtheory4LLM::gt_preflight(spec$formula, spec$data, measured = "item",
        family = spec$family, covariance = "unstructured", control = spec$control)
      writeLines(capture.output(print(preflight)), file.path(model_dir, "preflight.txt"))
      fit <- Gtheory4LLM::gt_fit(spec$formula, spec$data, measured = "item", family = spec$family,
        covariance = "unstructured", control = spec$control)
      # Retain the expensive fit as an opaque artifact for public-API reinspection.
      saveRDS(fit, file.path(model_dir, "fit.rds"))
      diagnostics <- Gtheory4LLM::gt_diagnostics(fit)
      writeLines(capture.output(print(diagnostics)), file.path(model_dir, "diagnostics.txt"))
      dput(diagnostics, file.path(model_dir, "diagnostics.R"))
      accepted <- isTRUE(diagnostics$numerically_accepted)
      status$numerical_acceptance[[i]] <- accepted
      status$observed_information[[i]] <- if (isTRUE(diagnostics$standard_errors_available)) "available" else "unavailable"
      status$deviance[[i]] <- stats::deviance(fit)
      rel <- NULL; dstudy <- NULL; comparison <- NULL; uncertainty_comparison <- NULL
      if (accepted) {
        components <- .gt_native_table(Gtheory4LLM::gt_components(fit))
        rel <- Gtheory4LLM::gt_reliability(fit, scale = "latent")
        rel_table <- as.data.frame(rel)
        single <- as.data.frame(Gtheory4LLM::gt_reliability(fit, scale = "latent", counts = spec$counts))
        utils::write.csv(components, file.path(model_dir, "components.csv"), row.names = FALSE)
        utils::write.csv(rel_table, file.path(model_dir, "reliability.csv"), row.names = FALSE)
        utils::write.csv(single, file.path(model_dir, "reliability-single.csv"), row.names = FALSE)
        dstudy <- Gtheory4LLM::gt_dstudy(fit, spec$allocations, scale = "latent")
        utils::write.csv(as.data.frame(dstudy), file.path(model_dir, "dstudy.csv"), row.names = FALSE)
        if (mode == "full") {
          comparison <- .gt_native_compare(status$deviance[[i]], components, rel_table, single,
            diagnostics$numerically_accepted, r, reference$tolerance)
          utils::write.csv(comparison, file.path(model_dir, "reference-comparison.csv"), row.names = FALSE)
          status$reference_comparison[[i]] <- if (all(comparison$passed)) "matched" else "failed"
          status$matched_reference_platform[[i]] <- paste(comparison$reference_platform[comparison$passed], collapse = ";")
        }
      }
      # Public reports preserve numerical refusal and unavailable intervals.
      report <- Gtheory4LLM::gt_report(fit, preflight = preflight, reliability = rel, dstudy = dstudy)
      status$uncertainty_scope[[i]] <- if (!isTRUE(report$uncertainty$available)) "unavailable" else
        if (isTRUE(report$uncertainty$conditional)) "boundary_conditional" else "ordinary_information"
      if (mode == "full" && accepted) {
        uncertainty_comparison <- .gt_native_uncertainty_compare(report$uncertainty, rel_table, single, r, reference$tolerance)
        utils::write.csv(uncertainty_comparison, file.path(model_dir, "uncertainty-comparison.csv"), row.names = FALSE)
        status$uncertainty_reference_comparison[[i]] <- if (isTRUE(uncertainty_comparison$passed)) "matched" else "failed"
      }
      Gtheory4LLM::gt_export_report(report, file.path(model_dir, "report.html"))
      reason <- c(if (!accepted) diagnostics$acceptance_failures,
        if (!isTRUE(diagnostics$standard_errors_available)) diagnostics$standard_errors_unavailable_reason,
        if (isTRUE(report$uncertainty$conditional)) "Boundary-conditional intervals; coverage remains unassessed.",
        if (mode == "full" && accepted && !all(comparison$passed)) "Both complete historical platform references must pass; at least one did not.",
        if (mode == "full" && accepted && !isTRUE(uncertainty_comparison$passed)) "Current conditional-information contract did not match the saved macOS arithmetic reference.")
      status$reason[[i]] <- paste(reason, collapse = "; ")
      status$status[[i]] <- if (!accepted) "refused" else
        if (mode == "full" && !all(comparison$passed)) "reference_mismatch" else
        if (mode == "full" && !isTRUE(uncertainty_comparison$passed)) "uncertainty_mismatch" else "accepted"
      TRUE
    }, warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }),
      error = function(e) { status$status[[i]] <<- "failed"; status$reason[[i]] <<- conditionMessage(e); FALSE })
    status$elapsed_seconds[[i]] <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    writeLines(warnings, file.path(model_dir, "warnings.txt"))
    writeLines(capture.output(print(status[i, , drop = FALSE], row.names = FALSE)), file.path(model_dir, "status.txt"))
    write_csv(status, "status.csv")
  }
  writeLines(c("Native 1.0 workflow", paste("Mode:", mode),
    "A successful smoke run is synthetic integration evidence only.",
    "A matching full run supports point-estimate numerical reproducibility for the two listed models on this environment.",
    "It does not establish higher-order Laplace accuracy, interval calibration, the full four/six-outcome models, or another platform/archive.",
    "Boundary-conditional intervals hold the listed sources at their fitted covariance matrices; coverage is unassessed.",
    "The .001 interval tolerance is a prospective replay gate. Saved conditional references cover macOS arithmetic only.",
    "Unavailable observed information means supported fitted intervals are unavailable at that fit.",
    "Archive identity requires an independently retained installation record; provenance.R records the supplied archive hash.",
    capture.output(print(status, row.names = FALSE))), file.path(output_dir, "summary.txt"))
  invisible(list(status = status, output_dir = output_dir, provenance = provenance))
}
