# Replay a discrete specimen written under GTHEORY_DISCRETE_SPECIMEN_DIR.
#
# A specimen is the record of one evaluation the discrete engine could not use:
# the parameters it was asked about, the measurements it reported, the identity
# of the numerical environment, and, where the failure produced them, the
# failed operation's matrix, right-hand side, step and factor. This script
# reads one back and answers, separately, three questions the record alone
# cannot:
#
#   1. Does the ORIGINAL step still fail the ORIGINAL system? The backward
#      error is recomputed from the stored numbers and compared with the
#      recorded measurement and validity decision. Agreement is a numerical
#      consistency check, not proof of file integrity.
#   2. Does the ORIGINAL factor act correctly on this host? Its solve is
#      re-applied here and checked against the stored system.
#   3. Does a FRESH factorization on this host pass the same check? Repeated
#      failure can reflect a recurring numerical-library fault; success or
#      failure here does not establish the cause or behaviour on other hosts.
#
# A specimen for a solve that merely did not converge carries no operation, and
# the script says so instead of inventing one. Nothing here changes a fit or
# an acceptance decision; it reads a file and reports.
#
# Run from the project directory:
#   Rscript --vanilla scripts/replay_specimen.R path/to/specimen.rds
for (file in c("design.R", "discrete_response.R", "discrete_dense.R", "discrete_sparse.R",
               "discrete_mode.R", "discrete.R"))
  source(file.path("R", file))
suppressMessages(requireNamespace("Matrix", quietly = TRUE))

gt_specimen_environment <- function() {
  threads <- Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
                          "VECLIB_MAXIMUM_THREADS"))
  list(R = R.version.string, platform = R.version$platform,
       os = unname(Sys.info()[["sysname"]]), machine = unname(Sys.info()[["machine"]]),
       BLAS = extSoftVersion()[["BLAS"]], LAPACK = La_library(), LAPACK_version = La_version(),
       Matrix = tryCatch(as.character(utils::packageVersion("Matrix")),
                         error = function(e) NA_character_),
       threads = paste(names(threads), ifelse(nzchar(threads), threads, "unset"),
                       sep = "=", collapse = " "))
}

# Apply a stored factor to a right-hand side, in the original coordinate order.
gt_specimen_apply_factor <- function(factor, b) {
  if (is.matrix(factor)) return(backsolve(factor, forwardsolve(t(factor), b)))
  as.numeric(Matrix::solve(factor, b, system = "A"))
}

gt_specimen_fresh_factor <- function(H) {
  if (is.matrix(H)) return(tryCatch(chol(H), error = function(e) NULL))
  tryCatch(.gt_d_sparse_factor(H)$factor, error = function(e) NULL)
}

# Residual calculations can differ by roundoff even for identical stored
# numbers. Use a dimension-scaled machine-precision floor near zero and a
# relative tolerance above it, never an absolute tolerance on the scale of 1.
# Each validity decision uses the bound that governed that measurement; a
# tolerance can never turn a failed-versus-passed comparison into agreement.
gt_specimen_compare_measurement <- function(record, replayed, dimension) {
  recorded <- record$solve_backward_error
  current <- replayed$solve_backward_error
  old_bound <- record$solve_validity_bound
  new_bound <- replayed$solve_validity_bound
  measurement <- function(x)
    is.numeric(x) && length(x) == 1L && !is.na(x) && x >= 0
  bound <- function(x) measurement(x) && is.finite(x) && x > 0
  old_valid <- if (measurement(recorded) && bound(old_bound))
    is.finite(recorded) && recorded <= old_bound else NA
  new_valid <- if (measurement(current) && bound(new_bound))
    is.finite(current) && current <= new_bound else NA
  difference <- tolerance <- NA_real_
  matches <- NA
  if (measurement(recorded) && measurement(current)) {
    if (is.finite(recorded) && is.finite(current)) {
      difference <- abs(current - recorded)
      tolerance <- max(1, dimension) * .Machine$double.eps +
        sqrt(.Machine$double.eps) * max(abs(recorded), abs(current))
    }
    if (!is.na(old_valid) && !is.na(new_valid))
      matches <- identical(old_valid, new_valid) &&
        if (is.finite(difference)) difference <= tolerance else identical(recorded, current)
  }
  list(recorded_backward_error = recorded, replayed_backward_error = current,
       recorded_bound = old_bound, replayed_bound = new_bound,
       recorded_valid = old_valid, replayed_valid = new_valid,
       difference = difference, tolerance = tolerance, matches = matches)
}

# The replay itself. Returns a list; printing is separate so a test can read
# the verdicts without parsing text.
gt_replay_specimen <- function(path) {
  specimen <- readRDS(path)
  if (!identical(specimen$schema, "gtheory-discrete-specimen/1"))
    stop("Not a discrete specimen: schema is ", format(specimen$schema), call. = FALSE)
  record <- specimen$record
  operation <- specimen$specimen
  result <- list(path = path, record = record, recorded_environment = specimen$environment,
                 current_environment = gt_specimen_environment(),
                 replayable = !is.null(operation) && !is.null(operation$hessian))
  if (!result$replayable) {
    result$verdict <- "no operation to replay: no stored matrix is available; consult the recorded evaluation measurements"
    return(result)
  }
  H <- operation$hessian
  b <- operation$right_hand_side
  x <- operation$step
  factor <- operation$factor
  dimension <- nrow(H)
  bound <- .gt_d_solve_bound(dimension)
  result$random_dimension <- dimension
  result$bound <- bound
  result$kind <- if (!is.null(b) || !is.null(x)) "newton_solve" else "final_factor"
  result$factor_check <- if (!is.null(b)) "stored right-hand side" else "fixed probes"
  if (!is.null(b) && !is.null(x)) {
    # 1. the original step against the original system
    original <- .gt_d_solve_check(H, b, x)
    result$original_step <- original
    result$original_record_comparison <- gt_specimen_compare_measurement(record, original, dimension)
    result$original_reproduces_record <- result$original_record_comparison$matches
  }
  # Apply stored and fresh factors independently. An absent stored factor or
  # step must not prevent the remaining evidence from being checked. Without
  # a stored right-hand side, use the same fixed probes as final-factor checks
  # and say so explicitly; that is not a replay of a missing Newton step.
  check_factor <- function(fac) {
    rhs <- if (!is.null(b)) list(b) else .gt_d_solve_probes(dimension)
    for (k in seq_along(rhs)) {
      y <- tryCatch(gt_specimen_apply_factor(fac, rhs[[k]]), error = function(e) e)
      if (inherits(y, "error")) return(list(valid = FALSE, solve_backward_error = Inf,
        solve_available = FALSE, error = conditionMessage(y),
        probe_index = if (is.null(b)) k else NA_integer_))
      check <- .gt_d_solve_check(H, rhs[[k]], y)
      if (!isTRUE(check$valid) || !is.null(b))
        return(c(check, list(solve_available = TRUE,
                            probe_index = if (is.null(b)) k else NA_integer_)))
    }
    list(valid = TRUE, solve_backward_error = NA_real_, solve_available = TRUE,
         probe_index = NA_integer_)
  }
  if (!is.null(factor)) result$original_factor_here <- check_factor(factor)
  fresh <- gt_specimen_fresh_factor(H)
  result$fresh_factor_available <- !is.null(fresh)
  if (!is.null(fresh)) result$fresh_factor_here <- check_factor(fresh)
  observed <- function(check) {
    if (is.null(check)) return("unavailable")
    if (isFALSE(check$solve_available)) return("solve unavailable here")
    if (isTRUE(check$valid)) "passes the check here" else "fails the check here"
  }
  result$verdict <- paste0("stored step: ", observed(result$original_step),
    "; stored factor: ", observed(result$original_factor_here),
    "; fresh factor: ", observed(result$fresh_factor_here),
    ". Factor checks use ", result$factor_check,
    "; the cause and behaviour on other hosts are not established.")
  result
}

gt_print_specimen_replay <- function(result) {
  fmt <- function(x) if (is.null(x) || length(x) != 1L || !is.numeric(x)) "NA" else format(x, digits = 6)
  cat("specimen:", result$path, "\n")
  cat("recorded: reason=", format(result$record$reason), " phase=", format(result$record$phase),
      " evaluation=", format(result$record$evaluation),
      " backward_error=", fmt(result$record$solve_backward_error),
      " bound=", fmt(result$record$solve_validity_bound),
      " random_dimension=", format(result$record$random_dimension), "\n", sep = "")
  cat("recorded environment: R=", format(result$recorded_environment$R),
      " BLAS=", format(result$recorded_environment$BLAS), "\n", sep = "")
  cat("current environment:  R=", result$current_environment$R,
      " BLAS=", result$current_environment$BLAS, "\n", sep = "")
  if (!result$replayable) { cat("verdict:", result$verdict, "\n"); return(invisible(result)) }
  if (!is.null(result$original_step))
    cat("1. original step vs original system: backward_error=",
        fmt(result$original_step$solve_backward_error), " valid=", result$original_step$valid,
        " reproduces_record=", format(result$original_reproduces_record), "\n", sep = "")
  comparison <- result$original_record_comparison
  if (!is.null(comparison))
    cat("   measurement comparison: difference=", fmt(comparison$difference),
        " tolerance=", fmt(comparison$tolerance),
        " recorded_valid=", format(comparison$recorded_valid),
        " replayed_valid=", format(comparison$replayed_valid), "\n", sep = "")
  if (!is.null(result$original_factor_here))
    cat("2. original factor applied here:     backward_error=",
        fmt(result$original_factor_here$solve_backward_error), " valid=",
        result$original_factor_here$valid, "\n", sep = "")
  if (!is.null(result$fresh_factor_here))
    cat("3. fresh factorization here:         backward_error=",
        fmt(result$fresh_factor_here$solve_backward_error), " valid=",
        result$fresh_factor_here$valid, "\n", sep = "")
  cat("bound: ", fmt(result$bound), "\n", sep = "")
  cat("verdict:", result$verdict, "\n")
  invisible(result)
}

if (sys.nframe() == 0L) {
  arguments <- commandArgs(trailingOnly = TRUE)
  if (length(arguments) != 1L)
    stop("Usage: Rscript --vanilla scripts/replay_specimen.R path/to/specimen.rds", call. = FALSE)
  gt_print_specimen_replay(gt_replay_specimen(arguments[[1L]]))
}
