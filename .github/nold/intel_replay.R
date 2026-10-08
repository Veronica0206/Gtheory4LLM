# Standalone captured-system diagnostic. No Gtheory4LLM code is loaded or changed.
# Fixed plan: 20 repetitions for every input, stored factor then fresh chol.
# A numerical failure is evidence, never a request to repeat until success.
args <- commandArgs(TRUE)
if (length(args) < 3L) stop("Usage: Rscript --vanilla harness.R OUTPUT_DIR SPECIMEN1.rds SPECIMEN2.rds [...]")
out <- args[[1L]]
paths <- normalizePath(args[-1L], mustWork = TRUE)
if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE)))
  stop("Output directory must be empty.")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
out <- normalizePath(out, mustWork = TRUE)
dir.create(file.path(out, "new-invalid-operations"))
REPETITIONS <- 20L
BOUND_CONSTANT <- 32
methods <- c("native_native", "scalar_scalar", "native_scalar", "scalar_native")
read_optional <- function(path) if (file.exists(path)) readLines(path, warn = FALSE) else character()
dump_text <- function(x, path) writeLines(capture.output(dput(x,
  control = c("keepNA", "keepInteger", "niceNames", "showAttributes", "digits17"))), path)

# No matrix multiplication, norm(), sum(), crossprod(), or native triangular
# solver is used in the scalar reference or its residual calculation.
scalar_forward <- function(R, b) {
  n <- length(b); y <- numeric(n)
  for (i in seq_len(n)) {
    total <- 0
    if (i > 1L) for (j in seq_len(i - 1L)) total <- total + R[j, i] * y[j]
    y[i] <- (b[i] - total) / R[i, i]
  }
  y
}
scalar_backward <- function(R, y) {
  n <- length(y); x <- numeric(n)
  for (i in seq.int(n, 1L)) {
    total <- 0
    if (i < n) for (j in seq.int(i + 1L, n)) total <- total + R[i, j] * x[j]
    x[i] <- (y[i] - total) / R[i, i]
  }
  x
}
scalar_error <- function(A, b, x) {
  if (is.null(x) || length(x) != nrow(A) || any(!is.finite(x))) return(Inf)
  residual <- 0; a_norm <- 0; x_norm <- 0; b_norm <- 0
  for (i in seq_len(nrow(A))) {
    total <- 0; row_norm <- 0
    for (j in seq_len(ncol(A))) {
      total <- total + A[i, j] * x[j]
      row_norm <- row_norm + abs(A[i, j])
    }
    residual <- max(residual, abs(total - b[i]))
    a_norm <- max(a_norm, row_norm)
    x_norm <- max(x_norm, abs(x[i])); b_norm <- max(b_norm, abs(b[i]))
  }
  denominator <- a_norm * x_norm + b_norm
  if (!is.finite(residual) || !is.finite(denominator)) return(Inf)
  if (residual == 0) return(0)
  if (denominator == 0) return(Inf)
  residual / denominator
}
# Production formula, reproduced verbatim in arithmetic and bound. Reported
# beside the independent scalar result; disagreement is never silently ignored.
native_error <- function(H, b, x) {
  if (is.null(x) || length(x) != nrow(H) || any(!is.finite(x))) return(Inf)
  residual <- max(abs(as.numeric(H %*% x) - b))
  denominator <- norm(H, "I") * max(abs(x)) + max(abs(b))
  if (!is.finite(residual) || !is.finite(denominator)) return(Inf)
  if (residual == 0) return(0)
  if (denominator == 0) return(Inf)
  residual / denominator
}
factor_residual <- function(H, R) {
  numerator <- 0; denominator <- 0
  for (i in seq_len(nrow(H))) {
    error_row <- 0; original_row <- 0
    for (j in seq_len(ncol(H))) {
      product <- 0
      for (k in seq_len(nrow(R))) product <- product + R[k, i] * R[k, j]
      error_row <- error_row + abs(product - H[i, j])
      original_row <- original_row + abs(H[i, j])
    }
    numerator <- max(numerator, error_row); denominator <- max(denominator, original_row)
  }
  if (!is.finite(numerator) || !is.finite(denominator)) return(Inf)
  if (numerator == 0) return(0)
  if (denominator == 0) return(Inf)
  numerator / denominator
}
attempt <- function(expr) {
  error <- NULL; warnings <- character()
  value <- tryCatch(withCallingHandlers(force(expr), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
  }), error = function(e) { error <<- conditionMessage(e); NULL })
  list(value = value, error = error, warnings = warnings)
}

metadata_so <- Sys.getenv("GTHEORY_META_SO")
if (nzchar(metadata_so)) dyn.load(normalizePath(metadata_so, mustWork = TRUE))
blas_metadata <- function() {
  if (!nzchar(metadata_so)) return(NULL)
  .Call("gtheory_openblas_meta", normalizePath(extSoftVersion()[["BLAS"]], mustWork = TRUE))
}
environment_record <- function(include_shim = TRUE) {
  cpu <- read_optional("/proc/cpuinfo")
  if (!length(cpu) && identical(unname(Sys.info()[["sysname"]]), "Darwin"))
    cpu <- tryCatch(system2("/usr/sbin/sysctl", c("-n", "machdep.cpu.brand_string"),
      stdout = TRUE, stderr = TRUE), error = conditionMessage)
  maps <- read_optional("/proc/self/maps")
  meta <- if (include_shim) blas_metadata() else NULL
  libR_candidates <- file.path(R.home("lib"), c("libR.so", "libR.dylib", "R.dll"))
  libR_path <- libR_candidates[file.exists(libR_candidates)][1L]
  native_files <- c(BLAS = extSoftVersion()[["BLAS"]], LAPACK = La_library(),
    R_executable = file.path(R.home("bin"), "exec", "R"),
    libR = libR_path,
    shim = metadata_so, OpenBLAS_provider = if (is.null(meta$provider_path)) "" else meta$provider_path)
  mapped_R <- unique(sub("^.*[[:space:]](/.*)$", "\\1", maps[grepl("/libR\\.(so|dylib)$", maps)]))
  if (length(mapped_R)) native_files <- c(native_files, setNames(mapped_R, paste0("mapped_libR_", seq_along(mapped_R))))
  native_files <- native_files[!is.na(native_files) & nzchar(native_files) & file.exists(native_files)]
  native_paths <- normalizePath(native_files, mustWork = TRUE)
  native_hashes <- data.frame(role = names(native_files), path = unname(native_paths),
    bytes = unname(file.info(native_paths)$size), md5 = unname(tools::md5sum(native_paths)), stringsAsFactors = FALSE)
  list(R = R.version, system = Sys.info(), long_double = capabilities("long.double"),
    sizeof_longdouble = .Machine$sizeof.longdouble, epsilon = .Machine$double.eps,
    BLAS = extSoftVersion()[["BLAS"]], LAPACK = La_library(), LAPACK_version = La_version(),
    shim_metadata = meta, native_file_hashes = native_hashes,
    shim_probe_deferred = !include_shim, cpu = cpu, process_maps = maps,
    options_matprod = getOption("matprod"),
    environment = Sys.getenv(c("GTHEORY_REQUIRE_NOLD", "GT_EXPECT_BACKEND", "GT_EXPECT_CORE",
      "GTHEORY_META_SO", "GTHEORY_ORIGINAL_RUNTIME", "OPENBLAS_CORETYPE", "OPENBLAS_VERBOSE", "OPENBLAS_NUM_THREADS",
      "OMP_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"), unset = NA_character_),
    loaded_dlls = vapply(getLoadedDLLs(), function(x) x[["path"]], character(1)))
}
verify_environment <- function(info, require_metadata = TRUE) {
  if (identical(Sys.getenv("GTHEORY_REQUIRE_NOLD"), "1") &&
      !isFALSE(unname(info$long_double))) stop("Requested noLD proof failed.")
  backend <- Sys.getenv("GT_EXPECT_BACKEND")
  core <- Sys.getenv("GT_EXPECT_CORE")
  if (nzchar(backend)) {
    if (!backend %in% c("openblas", "reference")) stop("Unknown expected backend.")
    if (!identical(unname(info$system[["sysname"]]), "Linux")) stop("Backend proof requires Linux.")
    if (!all(c("BLAS", "LAPACK", "R_executable", "libR") %in% info$native_file_hashes$role))
      stop("A required loaded numerical runtime/executable file hash is missing.")
    expected <- if (backend == "openblas")
      c("/usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3",
        "/usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblas.so.0") else
      c("/usr/lib/x86_64-linux-gnu/blas/libblas.so.3", "/usr/lib/x86_64-linux-gnu/lapack/liblapack.so.3")
    original_runtime <- Sys.getenv("GTHEORY_ORIGINAL_RUNTIME")
    if (backend == "openblas" && nzchar(original_runtime)) {
      expected <- readLines(normalizePath(original_runtime, mustWork = TRUE), warn = FALSE)
      if (length(expected) != 2L || any(!grepl("openblas", expected, ignore.case = TRUE)))
        stop("Original runtime must contain exactly the two recorded OpenBLAS paths.")
    }
    actual <- normalizePath(c(info$BLAS, info$LAPACK), mustWork = TRUE)
    expected <- normalizePath(expected, mustWork = TRUE)
    if (!identical(unname(actual), unname(expected))) stop("Loaded BLAS/LAPACK paths do not match expected backend.")
    if (!length(info$process_maps)) stop("Linux process maps are unavailable.")
    if (backend == "reference" && any(grepl("openblas", info$process_maps, ignore.case = TRUE)))
      stop("Reference process still maps OpenBLAS.")
    if (backend == "openblas" && require_metadata) {
      meta <- info$shim_metadata
      if (!isTRUE(meta$available) || !is.character(meta$config) ||
          length(meta$config) != 1L || !grepl("OpenBLAS 0.3.20", meta$config, fixed = TRUE) ||
          !grepl("DYNAMIC_ARCH", meta$config, fixed = TRUE) || !identical(as.integer(meta$num_threads), 1L))
        stop("Same-process OpenBLAS configuration/thread metadata proof failed.")
    }
  }
  if (nzchar(core) && require_metadata) {
    if (is.null(info$shim_metadata)) stop("Expected OpenBLAS core requires loaded metadata shim.")
    if (!isTRUE(info$shim_metadata$available) ||
        !identical(toupper(info$shim_metadata$corename), toupper(core)))
      stop("OpenBLAS reported core does not match GT_EXPECT_CORE.")
  }
  invisible(TRUE)
}
environment_before <- environment_record(include_shim = FALSE)
saveRDS(environment_before, file.path(out, "environment-before.rds"))
dump_text(environment_before, file.path(out, "environment-before.txt"))
verify_environment(environment_before, require_metadata = FALSE)
plan <- list(diagnostic_only = TRUE, package_qualification = FALSE, repetitions = REPETITIONS,
  factor_sources_in_order = c("stored", "fresh_chol"), methods = methods,
  bound_formula = "32 * nrow(H) * .Machine$double.eps", bound_constant = BOUND_CONSTANT,
  original_step_not_replaced = TRUE, adaptive_retries = FALSE,
  first_native_arithmetic = "forwardsolve(t(stored_factor), stored_rhs) for the first CLI specimen",
  primary_solve_order = "native forward/back before residual, scalar reference, hybrid solves, or fresh chol",
  metadata_probe_order = "No shim getters until the first native forward/back pair has been saved; then query and verify in the same R process.",
  inputs = setNames(as.list(unname(tools::md5sum(paths))), paths))
saveRDS(plan, file.path(out, "plan.rds")); dump_text(plan, file.path(out, "plan.txt"))
all_records <- list(); rows <- list(); specimen_summaries <- list()
first_native_saved <- FALSE
environment_after_first_native <- NULL
emit <- function(record) {
  index <- length(all_records) + 1L
  all_records[[index]] <<- record
  row <- record$row
  rows[[index]] <<- row
  printable <- lapply(row, function(x) if (is.numeric(x)) sprintf("%.17g", x) else x)
  write.table(as.data.frame(printable, stringsAsFactors = FALSE), file.path(out, "results.tsv"),
    sep = "\t", quote = TRUE, row.names = FALSE, col.names = index == 1L, append = index != 1L)
  if (record$row$repetition > 0L && (!record$row$scalar_valid || !record$row$native_valid))
    saveRDS(record, file.path(out, "new-invalid-operations", sprintf("operation-%05d.rds", index)))
}
for (input in seq_along(paths)) {
  specimen <- readRDS(paths[[input]])
  if (!identical(specimen$schema, "gtheory-discrete-specimen/1")) stop("Unrecognized specimen schema.")
  operation <- specimen$specimen
  H <- operation$hessian; b <- operation$right_hand_side; original_x <- operation$step; original_R <- operation$factor
  n <- nrow(H)
  if (!is.matrix(H) || !identical(dim(H), c(28L, 28L)) || !is.numeric(H) ||
      !is.matrix(original_R) || !identical(dim(original_R), dim(H)) ||
      !is.numeric(b) || length(b) != n || !is.numeric(original_x) || length(original_x) != n ||
      any(!is.finite(c(H, b, original_x, original_R))) || any(diag(original_R) == 0) ||
      any(original_R[lower.tri(original_R)] != 0)) stop("Expected a finite captured 28-by-28 upper-Cholesky system.")
  bound <- BOUND_CONSTANT * n * .Machine$double.eps
  if (!identical(as.numeric(specimen$record$solve_validity_bound), as.numeric(bound)))
    stop("Recorded validity bound differs from unchanged 32*d*eps.")
  id <- sprintf("specimen-%02d", input)
  saveRDS(specimen, file.path(out, paste0(id, "-original.rds")))
  original_scalar_eta <- scalar_error(H, b, original_x)
  original_logged <- FALSE
  for (repetition in seq_len(REPETITIONS)) for (factor_source in c("stored", "fresh_chol")) {
    factor_attempt <- if (factor_source == "stored") list(value = original_R, error = NULL, warnings = character()) else attempt(chol(H))
    R <- factor_attempt$value
    # Preserve the first native forward/back calls before any BLAS residual check.
    ny <- if (!is.null(R)) attempt(forwardsolve(t(R), b)) else list(value = NULL, error = factor_attempt$error)
    nx <- if (!is.null(ny$value)) attempt(backsolve(R, ny$value)) else list(value = NULL, error = ny$error)
    if (!first_native_saved) {
      saveRDS(list(input_path = paths[[input]], H = H, b = b, factor = R,
                   forward = ny, step = nx), file.path(out, "first-native-operation.rds"))
      first_native_saved <- TRUE
      environment_after_first_native <- environment_record()
      saveRDS(environment_after_first_native, file.path(out, "environment-after-first-native.rds"))
      dump_text(environment_after_first_native, file.path(out, "environment-after-first-native.txt"))
      verify_environment(environment_after_first_native)
    }
    if (!original_logged) {
      original_native_eta <- native_error(H, b, original_x)
      emit(list(row = list(specimen = id, repetition = 0L, factor_source = "captured", method = "stored_invalid_step",
        available = TRUE, scalar_error = original_scalar_eta, native_error = original_native_eta, bound = bound,
        scalar_valid = is.finite(original_scalar_eta) && original_scalar_eta <= bound,
        native_valid = is.finite(original_native_eta) && original_native_eta <= bound,
        forward_error = NA_real_, backward_error = NA_real_, factor_residual = NA_real_,
        max_difference_from_scalar = NA_real_, max_difference_from_original_step = 0,
        identical_to_original_step = TRUE, original_step_values_identical = TRUE, error = ""),
        H = H, b = b, factor = original_R, step = original_x, recorded = specimen$record))
      original_logged <- TRUE
    }
    sy <- if (!is.null(R)) attempt(scalar_forward(R, b)) else list(value = NULL, error = factor_attempt$error)
    sx <- if (!is.null(sy$value)) attempt(scalar_backward(R, sy$value)) else list(value = NULL, error = sy$error)
    nsx <- if (!is.null(ny$value)) attempt(scalar_backward(R, ny$value)) else list(value = NULL, error = ny$error)
    snx <- if (!is.null(sy$value)) attempt(backsolve(R, sy$value)) else list(value = NULL, error = sy$error)
    variants <- list(native_native = list(y = ny, x = nx), scalar_scalar = list(y = sy, x = sx),
      native_scalar = list(y = ny, x = nsx), scalar_native = list(y = sy, x = snx))
    reconstruction <- if (is.null(R)) Inf else factor_residual(H, R)
    for (method in methods) {
      v <- variants[[method]]; x <- v$x$value; y <- v$y$value
      scalar_eta <- scalar_error(H, b, x); native_eta <- native_error(H, b, x)
      errors <- unique(unlist(lapply(list(factor_attempt, v$y, v$x), `[[`, "error")))
      emit(list(row = list(specimen = id, repetition = repetition, factor_source = factor_source, method = method,
        available = !is.null(x), scalar_error = scalar_eta, native_error = native_eta, bound = bound,
        scalar_valid = is.finite(scalar_eta) && scalar_eta <= bound,
        native_valid = is.finite(native_eta) && native_eta <= bound,
        forward_error = if (is.null(R)) Inf else scalar_error(t(R), b, y),
        backward_error = if (is.null(R) || is.null(y)) Inf else scalar_error(R, y, x),
        factor_residual = reconstruction,
        max_difference_from_scalar = if (is.null(x) || is.null(sx$value)) NA_real_ else max(abs(x - sx$value)),
        max_difference_from_original_step = if (is.null(x)) NA_real_ else max(abs(as.numeric(x) - as.numeric(original_x))),
        identical_to_original_step = identical(x, original_x),
        original_step_values_identical = identical(as.numeric(x), as.numeric(original_x)),
        error = paste(errors, collapse = " | ")),
        input_path = paths[[input]], H = H, b = b, factor = R, forward = y, step = x,
        scalar_reference_forward = sy$value, scalar_reference_step = sx$value,
        recorded_environment = specimen$environment, captured_conditions = list(factor_attempt, v$y, v$x)))
    }
  }
  specimen_summaries[[id]] <- list(path = paths[[input]], recorded = specimen$record,
    original_scalar_error = original_scalar_eta, original_native_error = original_native_eta,
    recorded_environment = specimen$environment)
}
environment_after <- environment_record()
saveRDS(environment_after, file.path(out, "environment-after.rds"))
dump_text(environment_after, file.path(out, "environment-after.txt"))
verify_environment(environment_after)
table <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
replays <- table[table$repetition > 0L, ]
summary <- list(diagnostic_only = TRUE, package_qualification = FALSE, operational_complete = TRUE,
  planned_repetitions = REPETITIONS, input_count = length(paths), actual_replay_rows = nrow(replays),
  expected_replay_rows = length(paths) * REPETITIONS * 2L * length(methods),
  newly_invalid_rows = sum(!replays$scalar_valid | !replays$native_valid),
  original_invalid_steps = sum(!table$scalar_valid[table$repetition == 0L]),
  scalar_native_verdict_disagreements = sum(table$scalar_valid != table$native_valid),
  per_group = lapply(split(replays, interaction(replays$specimen, replays$factor_source, replays$method, drop = TRUE)),
    function(x) list(calls = nrow(x), scalar_failures = sum(!x$scalar_valid), native_failures = sum(!x$native_valid),
      first_scalar_error = x$scalar_error[1L], last_scalar_error = tail(x$scalar_error, 1L),
      min_scalar_error = min(x$scalar_error), max_scalar_error = max(x$scalar_error),
      max_native_error = max(x$native_error), max_forward_error = max(x$forward_error),
      max_backward_error = max(x$backward_error), max_factor_residual = max(x$factor_residual))),
  specimens = specimen_summaries)
stopifnot(summary$actual_replay_rows == summary$expected_replay_rows)
saveRDS(list(plan = plan, summary = summary, environment_before = environment_before,
  environment_after_first_native = environment_after_first_native,
  environment_after = environment_after, results = all_records), file.path(out, "replay-results.rds"))
saveRDS(summary, file.path(out, "summary.rds")); dump_text(summary, file.path(out, "summary.txt"))
cat("DIAGNOSTIC ONLY: completed", REPETITIONS, "fixed repetitions per factor for", length(paths), "specimens.\n")
cat("Stored invalid steps:", summary$original_invalid_steps, "; new invalid replay rows:", summary$newly_invalid_rows,
    "; scalar/native verdict disagreements:", summary$scalar_native_verdict_disagreements, "\n")
# Numeric failures are the requested evidence. Operational/identity errors
# throw above; completed numerical experiments return zero even when invalid.
quit(save = "no", status = 0L)
