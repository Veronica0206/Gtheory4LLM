# Diagnostic driver for the frozen 0.4.0 archive. This is never a release gate.
# No installed package function, test case, baseline, optimizer, or tolerance is modified.
args <- commandArgs(trailingOnly = TRUE)
required <- c("--archive", "--library", "--output-dir", "--backend-label")
if (length(args) != 2L * length(required) ||
    !setequal(args[seq.int(1L, length(args), 2L)], required) ||
    anyDuplicated(args[seq.int(1L, length(args), 2L)]))
  stop("Usage: characterization_diagnose.R --archive PATH --library PATH --output-dir PATH --backend-label LABEL")
options_cli <- setNames(args[seq.int(2L, length(args), 2L)],
                        args[seq.int(1L, length(args), 2L)])
archive <- normalizePath(options_cli[["--archive"]], mustWork = TRUE)
library_path <- normalizePath(options_cli[["--library"]], mustWork = TRUE)
output <- options_cli[["--output-dir"]]
if (dir.exists(output) && length(list.files(output, all.files = TRUE, no.. = TRUE)))
  stop("Diagnostic output directory must be empty, to keep backend/run evidence separate.")
dir.create(output, recursive = TRUE, showWarnings = FALSE)
output <- normalizePath(output, mustWork = TRUE)
if (nzchar(Sys.getenv("GTHEORY_CHARACTERIZATION_CAPTURE")))
  stop("Baseline capture mode is forbidden in this diagnostic.")

sha256 <- function(path) {
  program <- Sys.which("sha256sum")
  arguments <- shQuote(path)
  if (!nzchar(program)) {
    program <- Sys.which("shasum")
    arguments <- c("-a", "256", shQuote(path))
  }
  if (!nzchar(program)) stop("sha256sum or shasum is required for archive identity.")
  value <- system2(program, arguments, stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(value, "status")) || length(value) != 1L ||
      !grepl("^[0-9a-fA-F]{64} ", value)) stop("Could not compute SHA256 for ", path)
  tolower(substr(value, 1L, 64L))
}
archive_sha256 <- sha256(archive)
frozen_sha256 <- "a43a4cccbf2cd363625f36bad692e57aa0bde113be0492f642194c9c50362d65"
if (!identical(archive_sha256, frozen_sha256))
  stop("Archive is not the exact frozen 0.4.0 publication artifact.")
members <- c("Gtheory4LLM/tests/package-characterization.R", "Gtheory4LLM/DESCRIPTION")
inventory <- utils::untar(archive, list = TRUE)
if (any(vapply(members, function(x) sum(inventory == x) != 1L, logical(1))))
  stop("Frozen archive does not contain exactly one original test and DESCRIPTION.")
extracted <- file.path(output, "archive-source")
dir.create(extracted)
if (utils::untar(archive, files = members, exdir = extracted) != 0L)
  stop("Could not extract the original characterization test.")
test_path <- file.path(extracted, members[[1L]])
archive_description <- read.dcf(file.path(extracted, members[[2L]]))

.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(Gtheory4LLM, lib.loc = library_path))
installed_path <- normalizePath(find.package("Gtheory4LLM"), mustWork = TRUE)
if (!identical(installed_path, normalizePath(file.path(library_path, "Gtheory4LLM"), mustWork = TRUE)))
  stop("The package was loaded from a different library.")
installed_description <- read.dcf(file.path(installed_path, "DESCRIPTION"))
if (!all(colnames(archive_description) %in% colnames(installed_description)) ||
    !identical(unname(archive_description),
               unname(installed_description[, colnames(archive_description), drop = FALSE])))
  stop("Installed package DESCRIPTION does not match the frozen archive.")
installed_gt_fit <- getExportedValue("Gtheory4LLM", "gt_fit")
installed_gt_diagnostics <- getExportedValue("Gtheory4LLM", "gt_diagnostics")
snapshot_rng <- function() list(kind = RNGkind(),
  seed = if (exists(".Random.seed", .GlobalEnv, inherits = FALSE))
    get(".Random.seed", .GlobalEnv, inherits = FALSE) else NULL)
read_optional <- function(path) if (file.exists(path)) readLines(path, warn = FALSE) else character()
environment_record <- function() {
  record <- list(
  session = sessionInfo(), R = R.version, system = Sys.info(),
  long_double = capabilities("long.double"), machine = .Machine,
  external_libraries = extSoftVersion(), LAPACK = La_library(), LAPACK_version = La_version(),
  library_paths = .libPaths(), loaded_namespaces = loadedNamespaces(),
  numerical_environment = Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS",
    "OPENBLAS_CORETYPE", "OPENBLAS_VERBOSE", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS",
    "GTHEORY_DISCRETE_SPECIMEN_DIR", "_R_CHECK_SYSTEM_CLOCK_"), unset = NA_character_),
  process_maps = read_optional("/proc/self/maps"), cpu_info = read_optional("/proc/cpuinfo"))
  label <- options_cli[["--backend-label"]]
  record$backend_proof <- list(required = label %in% c("openblas", "reference"),
                               label = label, verified = FALSE)
  if (record$backend_proof$required) {
    fail_backend <- function(message) {
      record$backend_proof$error <- message
      evidence <- file.path(output, "backend-proof-failure.rds")
      if (!file.exists(evidence)) saveRDS(record, evidence)
      stop("Backend proof failed: ", message, call. = FALSE)
    }
    if (!identical(unname(record$system[["sysname"]]), "Linux") ||
        !isFALSE(unname(record$long_double)))
      fail_backend("The paired arms require Linux R built without long-double support.")
    expected <- if (label == "openblas")
      c("/usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3",
        "/usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblas.so.0") else
      c("/usr/lib/x86_64-linux-gnu/blas/libblas.so.3",
        "/usr/lib/x86_64-linux-gnu/lapack/liblapack.so.3")
    actual <- c(record$external_libraries[["BLAS"]], record$LAPACK)
    if (length(actual) != 2L || anyNA(actual) || any(!nzchar(actual)))
      fail_backend("R did not report both loaded BLAS and LAPACK paths.")
    record$backend_proof$expected_paths <- tryCatch(
      normalizePath(expected, mustWork = TRUE), error = function(e) fail_backend(conditionMessage(e)))
    record$backend_proof$actual_paths <- tryCatch(
      normalizePath(actual, mustWork = TRUE), error = function(e) fail_backend(conditionMessage(e)))
    if (!identical(unname(record$backend_proof$actual_paths), unname(record$backend_proof$expected_paths)))
      fail_backend("Loaded BLAS/LAPACK paths do not match the declared arm.")
    if (!length(record$process_maps)) fail_backend("Linux process maps are unavailable.")
    record$backend_proof$openblas_mapped <- any(grepl("openblas", record$process_maps, ignore.case = TRUE))
    if (label == "reference" && record$backend_proof$openblas_mapped)
      fail_backend("The reference arm still maps OpenBLAS.")
    record$backend_proof$verified <- TRUE
  }
  record
}
write_text <- function(value, path) writeLines(capture.output(dput(value)), path)
condition_record <- function(value) list(class = class(value), message = conditionMessage(value),
  call = conditionCall(value), condition = value)
specimen_dir <- file.path(output, "specimens")
dir.create(specimen_dir)
Sys.setenv(GTHEORY_DISCRETE_SPECIMEN_DIR = specimen_dir)
identity <- list(schema = "gtheory-frozen-characterization-diagnostic/1",
  diagnostic_only = TRUE, package_qualification = FALSE,
  backend_label = options_cli[["--backend-label"]], archive = archive,
  archive_sha256 = archive_sha256, test = test_path, test_sha256 = sha256(test_path),
  installed_path = installed_path, installed_description = installed_description,
  installed_identity_scope = paste("Loaded only from the requested library; every archive DESCRIPTION field matches.",
    "The invoking workflow must establish that this library was freshly installed from this hashed archive."),
  started_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  environment_before = environment_record())
saveRDS(identity, file.path(output, "identity.rds"))
write_text(identity, file.path(output, "identity.txt"))

# Evaluate the archive's definitions, not its driver or capture-mode branch.
expressions <- parse(test_path, keep.source = TRUE)
driver <- which(vapply(expressions, function(x)
  is.call(x) && identical(x[[1L]], as.name("for")) &&
    identical(x[[2L]], as.name("name")) && identical(x[[3L]], quote(names(cases))), logical(1)))
if (length(driver) != 1L || driver <= 1L) stop("Original characterization driver was not recognized uniquely.")
test_environment <- new.env(parent = .GlobalEnv)
for (expression in expressions[seq_len(driver - 1L)]) eval(expression, test_environment)
needed <- c("cases", "BASELINE", "record_case", "compare_exact", "compare_numeric", "NUMERIC_FIELDS", "failures")
if (!all(vapply(needed, exists, logical(1), envir = test_environment, inherits = FALSE)))
  stop("Original characterization definitions are incomplete.")

capture_state <- new.env(parent = emptyenv())
# Only this test environment gets a wrapper. The installed namespace is intact.
# Delegation happens once; argument promises are not forced early. Warnings and
# errors propagate normally. The returned fit is saved and returned unchanged.
test_environment$gt_fit <- function(...) {
  capture_state$fit_calls <- capture_state$fit_calls + 1L
  fit_id <- sprintf("fit-%02d", capture_state$fit_calls)
  prefix <- file.path(capture_state$directory, fit_id)
  call <- match.call(definition = installed_gt_fit, call = sys.call(), expand.dots = TRUE)
  rng_entry <- snapshot_rng()
  saveRDS(list(call = call, rng = rng_entry), paste0(prefix, "-entry.rds"))
  fitted <- installed_gt_fit(...)
  rng_return <- snapshot_rng()
  # Persist first, before downstream gt_reliability or diagnostics can fail.
  saveRDS(fitted, paste0(prefix, "-fit.rds"))
  capture_state$fits[[fit_id]] <- fitted
  supplied_arguments <- list(...)
  names(supplied_arguments) <- names(as.list(call)[-1L])
  saveRDS(supplied_arguments, paste0(prefix, "-arguments.rds"))
  saveRDS(supplied_arguments$data, paste0(prefix, "-data.rds"))
  saveRDS(fitted$control, paste0(prefix, "-control.rds"))
  diagnostic <- installed_gt_diagnostics(fitted)
  details <- list(case = capture_state$name, fit_id = fit_id, original_call = call,
    supplied_argument_sha256 = sha256(paste0(prefix, "-arguments.rds")),
    data_sha256 = sha256(paste0(prefix, "-data.rds")),
    control_sha256 = sha256(paste0(prefix, "-control.rds")),
    rng_entry = rng_entry, rng_return = rng_return,
    numerically_accepted = isTRUE(fitted$numerically_accepted),
    diagnostics = diagnostic, fitted_control = fitted$control,
    environment_after_fit = environment_record())
  saveRDS(details, paste0(prefix, "-details.rds"))
  write_text(details, paste0(prefix, "-details.txt"))
  fitted
}

compare_record <- function(name, record) {
  expected <- test_environment$BASELINE[[name]]
  before <- length(test_environment$failures)
  if (is.null(expected)) {
    test_environment$note(name, ": no stored baseline")
  } else {
    if (!setequal(names(record), names(expected)))
      test_environment$note(name, ": recorded fields changed from [", paste(sort(names(expected)), collapse = ", "),
                            "] to [", paste(sort(names(record)), collapse = ", "), "]")
    # On a downstream error, a fit-only record still permits diagnosis of the
    # acceptance decision. Missing coefficient fields remain an explicit failure.
    for (field in intersect(names(record), names(expected))) {
      numeric_field <- test_environment$NUMERIC_FIELDS[[field]]
      if (is.null(numeric_field))
        test_environment$compare_exact(name, field, record[[field]], expected[[field]])
      else test_environment$compare_numeric(name, field, record[[field]], expected[[field]],
        numeric_field$tolerance, numeric_field$relative,
        if (is.null(numeric_field$floor_fraction)) 0 else numeric_field$floor_fraction)
    }
  }
  test_environment$failures[seq_along(test_environment$failures) > before]
}
summary <- list(diagnostic_only = TRUE, package_qualification = FALSE,
  archive_sha256 = archive_sha256, backend_label = options_cli[["--backend-label"]],
  case_order = names(test_environment$cases), completed = FALSE, cases = list())
write_summary <- function() {
  saveRDS(summary, file.path(output, "summary.rds"))
  write_text(summary, file.path(output, "summary.txt"))
}
write_summary()
cat("DIAGNOSTIC ONLY: this run cannot qualify the package for release.\n")
for (name in names(test_environment$cases)) {
  capture_state$name <- name
  capture_state$directory <- file.path(output, name)
  dir.create(capture_state$directory)
  capture_state$fit_calls <- 0L
  capture_state$fits <- list()
  warnings <- list()
  error <- NULL
  partial <- FALSE
  cat("CASE", name, "BEGIN\n"); flush.console()
  rng_before <- snapshot_rng()
  record <- tryCatch(withCallingHandlers({
    result <- test_environment$cases[[name]]()
    test_environment$record_case(result)
  }, warning = function(w) {
    warnings[[length(warnings) + 1L]] <<- condition_record(w)
    # Do not muffle or replace the original warning.
  }), error = function(e) { error <<- condition_record(e); NULL })
  if (is.null(record) && length(capture_state$fits)) {
    partial <- TRUE
    record <- tryCatch(test_environment$record_case(list(fit = tail(capture_state$fits, 1L)[[1L]])),
      error = function(e) list(diagnostic_record_error = conditionMessage(e)))
  }
  differences <- if (is.null(record)) "No fitted characterization record was returned." else compare_record(name, record)
  result <- list(name = name, fit_calls = capture_state$fit_calls, record = record,
    partial_record = partial, error = error, warnings = warnings,
    expected_numerically_accepted = test_environment$BASELINE[[name]]$numerically_accepted,
    numerically_accepted = if (!is.null(record$numerically_accepted)) record$numerically_accepted else NA,
    baseline_differences = differences,
    original_case_and_baseline_passed = is.null(error) && !length(differences),
    rng_before_case = rng_before, rng_after_case = snapshot_rng(),
    environment_after_case = environment_record())
  saveRDS(result, file.path(capture_state$directory, "result.rds"))
  write_text(result, file.path(capture_state$directory, "result.txt"))
  summary$cases[[name]] <- result
  write_summary()
  cat("CASE ", name, " END accepted=", result$numerically_accepted,
      " original_case_and_baseline_passed=", result$original_case_and_baseline_passed,
      " error=", if (is.null(error)) "none" else error$message, "\n", sep = "")
}
summary$completed <- TRUE
summary$all_original_cases_and_baselines_passed <- all(vapply(summary$cases,
  `[[`, logical(1), "original_case_and_baseline_passed"))
summary$finished_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
summary$environment_after <- environment_record()
write_summary()
cat("DIAGNOSTIC ONLY: all original cases and baselines passed =",
    summary$all_original_cases_and_baselines_passed, "; package qualification = FALSE\n")
quit(save = "no", status = if (summary$all_original_cases_and_baselines_passed) 0L else 1L)
