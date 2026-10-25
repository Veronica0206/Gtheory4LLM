# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Discrete G-theory likelihoods shared by package and source-based use.
#
# Dense and sparse algebra share one bounded Laplace fitting policy. Random sources
# are mutually independent, multivariate Gaussian random intercepts. Outcomes
# are conditionally independent given those sources. Within a multinomial
# outcome, its category indicators instead have the joint softmax likelihood.
# Binary/ordinal probit models fix latent residual variance to 1; logit models
# fix it to pi^2/3. No additional free observation-level Gaussian residual is
# estimated. The likelihood is approximate whenever random effects are present.

.gt_d_stop <- function(...) stop(..., call. = FALSE)

# Why a starting-value refusal happened, for the error message and the CI log.
#
# It describes the detailed record of the evaluation that refused, and nothing
# else: it is observational, and can never convert the refusal into a usable
# start. The record is the original evaluation's own, never a replay's. The
# native defect this guards against is intermittent, so a second evaluation
# that happened to succeed would establish only that the failure did not
# reproduce, not that the first evaluation was valid, and a second one that
# failed would only describe itself. Treating a replay as either evidence or
# rescue would turn the numerical policy into "retry until the library
# behaves", which is precisely the behaviour the invariant exists to prevent.
.gt_d_start_failure_detail <- function(evidence) {
  if (!is.list(evidence)) return("; no detailed evaluation record was returned")
  if (isTRUE(evidence$valid)) return("; the evaluation reported valid without a finite objective")
  if (is.null(evidence$reason)) return("")
  detail <- paste0("; reason=", evidence$reason)
  eta <- evidence$solve_backward_error
  bound <- evidence$solve_validity_bound
  if (is.numeric(eta) && length(eta) == 1L && is.numeric(bound) && length(bound) == 1L)
    detail <- paste0(detail, ", backward_error=", format(eta, digits = 6),
                     ", solve_validity_bound=", format(bound, digits = 6),
                     ", backward_error_over_bound=", format(eta / bound, digits = 6),
                     ", random_dimension=", evidence$random_dimension)
  if (!is.null(evidence$probe_index) && length(evidence$probe_index) == 1L &&
      !is.na(evidence$probe_index))
    detail <- paste0(detail, ", probe_index=", evidence$probe_index)
  detail
}

# A detailed evaluation that the outer optimizer may use as a finite objective.
.gt_d_evaluation_usable <- function(value)
  is.list(value) && isTRUE(value$valid) && is.numeric(value$nll) &&
    length(value$nll) == 1L && is.finite(value$nll) && value$nll < 1e99

# Original-operation evidence for evaluations the optimizer could not use.
#
# Every objective evaluation is performed in detailed form and reduced to its
# scalar here, so what is recorded about an evaluation that failed is the
# record of THAT evaluation: its reason, its measurements and the parameters
# it was asked about. Nothing is recomputed to describe it. The arithmetic is
# unchanged, because `details` selects what a mode solver returns and never
# what it computes.
#
# The record is bounded. Counts are kept for every evaluation; the parameters
# and measurements of at most `limit` invalid evaluations are retained, in
# order of occurrence, so a fit object stays small however long the optimizer
# runs. Routine non-converged evaluations are common enough to use that whole
# allowance on their own, so a solve- or factor-validity event has a bounded
# allowance of its own, `validity_limit`, and is not lost behind them; every
# such event is counted whether or not it is retained.
#
# `settings` is the control an evaluation actually ran with. The tightened
# objective runs under a stricter inner tolerance than the coarse one, and a
# specimen that described it by the coarse settings would misreport the
# operation it preserves.
#
# Matrices are never retained in the fit: a failed evaluation's matrix,
# right-hand side, step and factor are written to disk only when
# GTHEORY_DISCRETE_SPECIMEN_DIR is set, and a failed write is recorded rather
# than raised, so it can never mask the refusal it was meant to explain.
.gt_d_evaluation_log <- function(control, prep, limit = 8L, validity_limit = 8L) {
  state <- new.env(parent = emptyenv())
  state$count <- 0L
  state$invalid <- 0L
  state$validity <- 0L
  state$validity_retained <- 0L
  state$at_budget <- 0L
  state$retained <- list()
  state$rescued <- 0L
  state$retained_rescued <- list()
  state$warm_started <- 0L
  state$cold_fallbacks <- 0L
  observe <- function(parameters, value, phase, settings = control) {
    state$count <- state$count + 1L
    # A cold fallback is a warm solve that stopped short and was replaced by the
    # cold solve from zero modes. It is counted whether or not the evaluation
    # was finally usable: both solves ran either way.
    if (is.list(value) && !is.null(value$inner_warm_attempt))
      state$cold_fallbacks <- state$cold_fallbacks + 1L
    if (.gt_d_evaluation_usable(value)) {
      if (is.numeric(value$inner_iterations) && length(value$inner_iterations) == 1L &&
          value$inner_iterations >= settings$inner_maxit)
        state$at_budget <- state$at_budget + 1L
      # A warm start within an optimizer attempt is an ordinary valid
      # evaluation; it is counted so a fit says how many of its solves began
      # from an earlier mode.
      if (isTRUE(value$inner_warm_started) && is.null(value$inner_cold_attempt))
        state$warm_started <- state$warm_started + 1L
      if (isTRUE(value$inner_warm_started) && !is.null(value$inner_cold_attempt)) {
        # A sparse evaluation whose cold solve failed and whose retry from the
        # fit's last valid mode succeeded. It is a valid evaluation, counted and
        # described separately so that a fit which needed the retry says so.
        # No specimen is written for it.
        state$rescued <- state$rescued + 1L
        if (length(state$retained_rescued) < limit)
          state$retained_rescued[[length(state$retained_rescued) + 1L]] <-
            list(evaluation = state$count, phase = phase, parameters = parameters,
                 inner_iterations = value$inner_iterations,
                 cold_attempt = value$inner_cold_attempt,
                 warm_attempt = value$inner_warm_attempt)
      }
      return(value$nll)
    }
    state$invalid <- state$invalid + 1L
    validity <- .gt_d_validity_event(value)
    if (validity) state$validity <- state$validity + 1L
    if (length(state$retained) < limit ||
        (validity && state$validity_retained < validity_limit)) {
      record <- .gt_d_failure_record(value, list(evaluation = state$count, phase = phase,
                                                 parameters = parameters))
      record$specimen <- .gt_d_write_specimen(value, record, prep, settings)
      state$retained[[length(state$retained) + 1L]] <- record
      if (validity) state$validity_retained <- state$validity_retained + 1L
    }
    1e100
  }
  summary <- function() list(
    count = state$count, invalid = state$invalid, validity_events = state$validity,
    valid_at_inner_budget = state$at_budget, inner_budget = control$inner_maxit,
    retained_invalid = state$retained, retention_limit = limit,
    validity_retention_limit = validity_limit,
    warm_rescued = state$rescued, retained_rescued = state$retained_rescued,
    warm_started = state$warm_started, cold_fallbacks = state$cold_fallbacks,
    scope = paste("Every evaluation of the coarse or tightened objective made by the optimizer",
                  "and by the one tighter-tolerance re-evaluation of the primary fit;",
                  "final validation, stationarity and specimen evaluations are not counted.",
                  "Retained records carry the failed evaluation's own measurements.",
                  "A solve- or factor-validity event is retained beyond the ordinary limit,",
                  "within its own. A sparse evaluation rescued by a retry from the last valid",
                  "mode is a valid evaluation, counted and retained separately. A sparse",
                  "evaluation that began from the attempt's centre mode is counted as warm",
                  "started; one whose warm solve stopped short and was replaced by the cold",
                  "solve is counted as a cold fallback, whether or not it was finally usable."))
  list(observe = observe, summary = summary)
}

# A solve- or factor-validity refusal, as opposed to a conditional solve that
# merely did not converge: the four reasons the two mode solvers return when a
# native factorization does not solve its own system.
.gt_d_validity_event <- function(value)
  is.list(value) && is.character(value$reason) && length(value$reason) == 1L &&
    !is.na(value$reason) && grepl("_(newton_solve|final_factor)_invalid$", value$reason)

# The retained description of one failed evaluation: measurements only, never
# the matrices, which go to a specimen file when one is configured.
.gt_d_failure_record <- function(value, record) {
  fields <- c("reason", "inner_converged", "inner_gradient", "inner_iterations",
              "inner_line_search_failed", "inner_factor_unavailable",
              .GT_D_SOLVE_DETAIL, "probe_index", "inner_warm_started", "inner_cold_attempt",
              "inner_warm_attempt")
  if (is.list(value)) for (field in fields) if (!is.null(value[[field]]))
    record[[field]] <- value[[field]]
  if (is.null(record$reason)) record$reason <- NA_character_
  record
}

.gt_d_specimen_directory <- function() {
  configured <- Sys.getenv("GTHEORY_DISCRETE_SPECIMEN_DIR", "")
  if (nzchar(configured)) configured else NULL
}

# Opt-in capture of a failed evaluation, at the site of the failure.
#
# Off unless GTHEORY_DISCRETE_SPECIMEN_DIR names a directory. When on, the
# specimen holds the failed evaluation's own matrix, right-hand side, step and
# factor where the failure produced them, the parameters it was asked about,
# its measurements, and the identity of the numerical environment, as numeric
# objects that can be reloaded and replayed. It holds no observations: the
# dimensions of the response are recorded, the response itself is not. The
# file name is unique per call. Returns the path, or the error message of a
# failed write; it never raises, because the refusal it documents must not be
# replaced by a failure to document it.
.gt_d_write_specimen <- function(value, record, prep, control) {
  directory <- .gt_d_specimen_directory()
  if (is.null(directory)) return(NULL)
  tryCatch({
    dir.create(directory, showWarnings = FALSE, recursive = TRUE)
    label <- if (!is.null(record$evaluation)) paste0("evaluation-", record$evaluation) else
      if (isTRUE(record$phase %in% c("final", "stationarity"))) record$phase else "start"
    path <- tempfile(paste0("gtheory-discrete-specimen-", label, "-"), tmpdir = directory,
                     fileext = ".rds")
    threads <- Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
                            "VECLIB_MAXIMUM_THREADS"))
    saveRDS(list(
      schema = "gtheory-discrete-specimen/1",
      package_version = tryCatch(as.character(utils::packageVersion("Gtheory4LLM")),
                                 error = function(e) NA_character_),
      created = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      record = record[setdiff(names(record), "specimen")],
      specimen = if (is.list(value)) value$specimen else NULL,
      dimensions = list(observations = prep$n, latent_dimensions = prep$q,
                        inner_maxit = control$inner_maxit, inner_tol = control$inner_tol),
      environment = list(
        R = R.version.string, platform = R.version$platform,
        os = unname(Sys.info()[["sysname"]]), machine = unname(Sys.info()[["machine"]]),
        BLAS = extSoftVersion()[["BLAS"]], LAPACK = La_library(), LAPACK_version = La_version(),
        Matrix = tryCatch(as.character(utils::packageVersion("Matrix")),
                          error = function(e) NA_character_),
        threads = paste(names(threads), ifelse(nzchar(threads), threads, "unset"),
                        sep = "=", collapse = " "))),
      path)
    list(path = path)
  }, error = function(e) list(error = conditionMessage(e)))
}

.gt_d_specimen_note <- function(written) {
  if (is.null(written)) return("")
  if (!is.null(written$path)) return(paste0("; specimen=", written$path))
  paste0("; specimen not written: ", written$error)
}

# The public engine label for a marginal backend. The dense label is the
# established one and is unchanged; any other backend names itself, so a fit
# always says which implementation produced it, in the public field that
# reliability, decision studies and diagnostics read.
.gt_d_engine_label <- function(marginal_backend) {
  if (identical(marginal_backend, "dense_marginal_laplace")) return("dense_joint_discrete_laplace")
  paste0(sub("_marginal_laplace$", "", marginal_backend), "_joint_discrete_laplace")
}

.gt_d_control <- function(control) {
  defaults <- list(engine = "dense", max_random_dimension = 200L, max_observations = 1200L,
                   max_parameters = 80L, max_dense_bytes = 512 * 1024^2,
                   max_sparse_bytes = 512 * 1024^2,
                   check_hessian = FALSE, hessian_step = 1e-3, hessian_tolerance = 0.05,
                   maxit = 150L, inner_maxit = 60L,
                   inner_tol = 1e-7, reltol = 1e-7, start_sd = 0.4,
                   trace = 0L, fixed_covariance = NULL,
                   stationarity_tol = 1e-3, validation_reltol = 1e-10,
                   validation_inner_tol = 1e-9, alternative_starts = 1L,
                   stability_objective_tol = 1e-6,
                   stability_parameter_tol = 0.02, bound_tol = 1e-4,
                   covariance_parameterization = "auto",
                   start = NULL, optimizer = "L-BFGS-B", parameter_bounds = NULL,
                   optimizer_scaling = "none", gradient = "finite_difference")
  if (!is.list(control) || (length(control) &&
      (is.null(names(control)) || anyNA(names(control)) ||
       any(!nzchar(names(control))) || anyDuplicated(names(control)))))
    .gt_d_stop("discrete control must be a named list.")
  unknown <- setdiff(names(control), names(defaults))
  if (length(unknown)) .gt_d_stop("Unknown discrete control: ", paste(unknown, collapse = ", "), ".")
  for (nm in names(control)) defaults[nm] <- control[nm]
  if (!is.character(defaults$engine) || length(defaults$engine) != 1L ||
      is.na(defaults$engine) || !defaults$engine %in% c("dense", "sparse"))
    .gt_d_stop("discrete engine must be 'dense' or 'sparse'.")
  if (!is.logical(defaults$check_hessian) || length(defaults$check_hessian) != 1L ||
      is.na(defaults$check_hessian)) .gt_d_stop("check_hessian must be TRUE or FALSE.")
  for (nm in c("max_random_dimension", "max_observations", "max_parameters", "maxit", "inner_maxit")) {
    z <- defaults[[nm]]
    if (!is.numeric(z) || length(z) != 1L || !is.finite(z) || z < 1 || z != floor(z))
      .gt_d_stop(nm, " must be a positive integer.")
  }
  for (nm in c("inner_tol", "reltol", "start_sd", "stationarity_tol",
               "validation_reltol", "validation_inner_tol",
               "stability_objective_tol", "stability_parameter_tol", "bound_tol",
               "max_dense_bytes", "max_sparse_bytes", "hessian_step", "hessian_tolerance")) {
    z <- defaults[[nm]]
    if (!is.numeric(z) || length(z) != 1L || !is.finite(z) || z <= 0)
      .gt_d_stop(nm, " must be a positive finite number.")
  }
  if (!is.numeric(defaults$alternative_starts) || length(defaults$alternative_starts) != 1L ||
      !is.finite(defaults$alternative_starts) || defaults$alternative_starts < 0 ||
      defaults$alternative_starts != floor(defaults$alternative_starts) || defaults$alternative_starts > 5)
    .gt_d_stop("alternative_starts must be an integer from 0 to 5; zero disables numerical acceptance.")
  if (!is.numeric(defaults$trace) || length(defaults$trace) != 1L ||
      !is.finite(defaults$trace) || !defaults$trace %in% c(0, 1))
    .gt_d_stop("trace must be 0 or 1.")
  if (!is.character(defaults$covariance_parameterization) ||
      length(defaults$covariance_parameterization) != 1L ||
      is.na(defaults$covariance_parameterization) ||
      !defaults$covariance_parameterization %in% c("auto", "cholesky", "log_cholesky", "variance"))
    .gt_d_stop("covariance_parameterization must be 'auto', 'cholesky', 'log_cholesky', or 'variance'.")
  if (!is.character(defaults$optimizer) || length(defaults$optimizer) != 1L ||
      is.na(defaults$optimizer) || !defaults$optimizer %in% c("L-BFGS-B", "nlminb"))
    .gt_d_stop("discrete optimizer must be 'L-BFGS-B' or 'nlminb'.")
  if (!is.character(defaults$optimizer_scaling) || length(defaults$optimizer_scaling) != 1L ||
      is.na(defaults$optimizer_scaling) || !defaults$optimizer_scaling %in% c("none", "start"))
    .gt_d_stop("optimizer_scaling must be 'none' or 'start'.")
  if (defaults$optimizer_scaling != "none" && defaults$optimizer != "L-BFGS-B")
    .gt_d_stop("optimizer_scaling = 'start' requires the L-BFGS-B optimizer.")
  # The analytic gradient replaces only the outer optimizer's finite-difference
  # gradient inside L-BFGS-B attempts on the sparse engine; see
  # R/discrete_gradient.R. Acceptance is decided as before.
  if (!is.character(defaults$gradient) || length(defaults$gradient) != 1L ||
      is.na(defaults$gradient) || !defaults$gradient %in% c("finite_difference", "analytic"))
    .gt_d_stop("gradient must be 'finite_difference' or 'analytic'.")
  if (identical(defaults$gradient, "analytic") &&
      (!identical(defaults$engine, "sparse") || !identical(defaults$optimizer, "L-BFGS-B")))
    .gt_d_stop("gradient = 'analytic' requires engine = 'sparse' and the L-BFGS-B optimizer.")
  z <- defaults$start
  if (!is.null(z) && (!is.numeric(z) || !is.null(dim(z)) || !length(z) ||
      any(!is.finite(z)) || is.null(names(z)) || anyNA(names(z)) ||
      any(!nzchar(names(z))) || anyDuplicated(names(z))))
    .gt_d_stop("discrete start must be a finite, uniquely named numeric parameter vector.")
  defaults$parameter_bounds <- .gt_d_bounds_control(defaults$parameter_bounds)
  defaults
}

# Artificial optimizer domains can be declared before fitting. The response
# likelihood and covariance model do not change, and natural zero boundaries
# cannot be moved. Resolve names only after the observation/covariance model.
.gt_d_bounds_control <- function(bounds) {
  if (is.null(bounds)) return(NULL)
  if (!is.list(bounds) || !length(bounds) || is.null(names(bounds)) ||
      anyNA(names(bounds)) || anyDuplicated(names(bounds)) ||
      any(!names(bounds) %in% c("lower", "upper")))
    .gt_d_stop("parameter_bounds must be NULL or a named list of lower and/or upper overrides.")
  for (side in names(bounds)) {
    x <- bounds[[side]]
    if (!is.numeric(x) || !is.null(dim(x)) || !length(x) ||
        any(!is.finite(x)) || is.null(names(x)) || anyNA(names(x)) ||
        any(!nzchar(names(x))) || anyDuplicated(names(x)))
      .gt_d_stop("Each parameter_bounds side must be a finite, uniquely named numeric vector.")
  }
  bounds
}

.gt_d_parameter_domain <- function(prep, setup, control) {
  parameter_names <- names(c(prep$start, setup$start))
  if (anyDuplicated(parameter_names))
    .gt_d_stop("Outcome/source labels produce ambiguous discrete parameter names; rename the labels before fitting.")
  lower <- stats::setNames(c(prep$lower, setup$lower), parameter_names)
  upper <- stats::setNames(c(prep$upper, setup$upper), parameter_names)
  defaults <- list(lower = lower, upper = upper)
  requested <- .gt_d_bounds_control(control$parameter_bounds)
  for (side in names(requested)) {
    unknown <- setdiff(names(requested[[side]]), parameter_names)
    if (length(unknown)) .gt_d_stop("Unknown parameter_bounds coordinate(s): ",
                                  paste(unknown, collapse = ", "), ".")
    if (side == "lower") lower[names(requested[[side]])] <- requested[[side]] else
      upper[names(requested[[side]])] <- requested[[side]]
  }
  if (any(lower >= upper) || any(!is.finite(upper - lower)))
    .gt_d_stop("parameter_bounds require finite ordered domains with lower < upper.")
  fixed <- seq_along(prep$start)
  covariance <- length(prep$start) + seq_along(setup$start)
  natural <- rep(FALSE, length(parameter_names))
  if (setup$parameterization %in% c("variance", "exchangeable"))
    natural[covariance] <- TRUE
  if (identical(setup$parameterization, "cholesky"))
    natural[covariance] <- rep(setup$diagpos, length(setup$sources))
  if (any(lower[natural] != 0))
    .gt_d_stop("parameter_bounds must preserve natural variance and Cholesky lower boundaries at zero.")
  # Every ordered gap must remain positive and distinguishable throughout its
  # declared domain, including after earlier, potentially much larger gaps.
  for (b in prep$blocks) if (b$family == "ordinal" && length(b$parameters) > 1L) {
    p <- b$parameters
    lo <- lower[p[[1L]]]; hi <- upper[p[[1L]]]
    for (j in p[-1L]) {
      small <- exp(lower[[j]]); large <- exp(upper[[j]])
      if (!is.finite(small) || small <= 0 || !is.finite(large) ||
          !is.finite(lo + small) || !is.finite(hi + large) ||
          lo + small <= lo || hi + small <= hi)
        .gt_d_stop("parameter_bounds must keep ordinal gaps finite, positive and numerically distinguishable.")
      lo <- lo + small; hi <- hi + large
    }
  }
  if (length(covariance)) {
    extremes <- pmax(abs(lower[covariance]), abs(upper[covariance]))
    if (identical(setup$parameterization, "log_cholesky")) {
      diagonal <- rep(setup$diagpos, length(setup$sources))
      extremes[diagonal] <- upper[covariance][diagonal]
      if (any(exp(2 * lower[covariance][diagonal]) == 0))
        .gt_d_stop("parameter_bounds must keep log-Cholesky diagonals representably positive.")
    }
    factors <- .gt_d_covariance_factors(extremes, setup)
    matrices <- lapply(factors, tcrossprod)
    if (any(!is.finite(unlist(factors))) || any(!is.finite(unlist(matrices))) ||
        !is.finite(sum(vapply(matrices, function(S) max(diag(S)), numeric(1)))))
      .gt_d_stop("parameter_bounds must keep covariance factors and their summed variances finite.")
  }
  automatic_start <- c(prep$start, setup$start)
  start <- automatic_start
  if (!is.null(control$start)) {
    unknown <- setdiff(names(control$start), parameter_names)
    if (length(unknown)) .gt_d_stop("Unknown discrete start parameter(s): ",
                                  paste(unknown, collapse = ", "), ".")
    start[names(control$start)] <- control$start
  }
  if (any(!is.finite(start)) || any(start < lower | start > upper))
    .gt_d_stop("Discrete start parameters must lie within their model bounds; check start_sd and explicit start values.")
  prep$lower <- unname(lower[fixed]); prep$upper <- unname(upper[fixed])
  setup$lower <- unname(lower[covariance]); setup$upper <- unname(upper[covariance])
  list(prep = prep, setup = setup, lower = unname(lower), upper = unname(upper),
       start = start, automatic_start = automatic_start, natural_lower = natural,
       record = list(requested = requested, default = defaults,
         effective = list(lower = lower, upper = upper),
         natural_zero_coordinates = parameter_names[natural],
         policy = "Predeclared optimizer-coordinate bounds; no automatic expansion. Artificial-bound contact still prevents numerical acceptance."))
}

# Planning estimate for the dense arrays one marginal likelihood evaluation
# holds at once, in bytes. It covers the random-design matrix W, the conditional
# Hessian and its Cholesky factor, the per-block slices of W that forming that
# Hessian materializes, and the linear predictor and gradient. The multiplier is
# a deliberate planning allowance for R's copy-on-modify during those products.
#
# This is a resource guard evaluated before allocation, not a measurement of
# peak resident memory: it excludes the caller's data, the optimizer's own
# state, and every allocation the finite-difference stationarity pass repeats.
# It is an underestimate of what a fit really uses, which is why it is a guard
# against the obviously impossible rather than a promise about the feasible.
.gt_d_dense_bytes <- function(n, q, random_dimension, multiplier = 2) {
  n <- as.double(n)
  q <- as.double(q)
  random_dimension <- as.double(random_dimension)
  design <- 8 * n * q * random_dimension
  hessian <- 2 * 8 * random_dimension^2
  slices <- 2 * 8 * n * random_dimension
  predictors <- 4 * 8 * n * q
  total <- multiplier * (design + hessian + slices + predictors)
  list(total = total, random_design = design, conditional_hessian = hessian,
       block_slices = slices, predictors = predictors, multiplier = multiplier,
       scope = paste("One dense likelihood evaluation's major arrays, with a",
         "planning multiplier. Excludes caller data, optimizer state, and",
         "repeated allocation during finite-difference validation."))
}

.gt_d_format_bytes <- function(bytes) {
  if (!is.finite(bytes)) return("unavailable")
  units <- c("bytes", "KiB", "MiB", "GiB", "TiB")
  index <- if (bytes <= 0) 1L else min(length(units), 1L + floor(log(bytes, 1024)))
  paste(format(round(bytes / 1024^(index - 1L), 1), scientific = FALSE, trim = TRUE),
        units[[index]])
}

# Keep errors and warnings from numerical attempts without changing the global
# warning option or RNG state. User interrupts are deliberately not caught.
.gt_d_capture <- function(expr) {
  started <- proc.time()[["elapsed"]]
  warnings <- character()
  error <- NULL
  value <- tryCatch(withCallingHandlers(force(expr), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }), error = function(e) {
    error <<- conditionMessage(e)
    NULL
  })
  list(value = value, error = error, warnings = warnings,
       elapsed_seconds = unname(proc.time()[["elapsed"]] - started))
}

# A bounded optimizer can converge to a bound and still report the point a few
# ulps outside it. Snap that rounding noise back onto the bound so a converged
# result is not discarded as unusable; the tolerance scales with each bound's
# own magnitude, so a point meaningfully outside is left alone and still fails
# the availability check. Returns NULL when no projection is defensible.
.gt_d_project_bounds <- function(par, lower, upper) {
  if (!is.numeric(par) || any(!is.finite(par)) ||
      length(par) != length(lower) || length(par) != length(upper)) return(NULL)
  slack <- function(bound) 1e-10 * pmax(1, abs(bound))
  if (any(par < lower - slack(lower)) || any(par > upper + slack(upper))) return(NULL)
  pmin(pmax(par, lower), upper)
}

# The finite-difference gradient optim() computes for L-BFGS-B when no
# gradient is supplied, written out so the fit can name its probes. It follows
# optim's internal rule exactly: for each coordinate, a central difference with
# step ndeps, each side clipped to its bound with the step used on that side.
# Supplying it therefore leaves the evaluation sequence, every value and the
# optimizer's path unchanged; tests/test_discrete_sparse_warm_policy.R checks
# that. At a parameter scale other than one (a coarse attempt rerun after a
# collapsed first step, or optimizer_scaling = "start") optim would difference
# in the scaled coordinates with ndeps applied there; this rule deliberately
# keeps its physical steps in the original coordinates, so the two differ by
# their truncation errors and the scaled attempt follows this rule's path.
# What it adds is the role: objective() here is told the evaluations are
# probes, so a warm-started sparse evaluator seeds all of them from the mode at
# the point whose gradient they form.
.gt_d_numerical_gradient <- function(objective, ndeps, lower, upper) {
  force(objective); force(ndeps); force(lower); force(upper)
  function(p) {
    df <- numeric(length(p))
    for (i in seq_along(p)) {
      eps <- epsused <- ndeps[[i]]
      x <- p
      tmp <- p[[i]] + eps
      if (tmp > upper[[i]]) { tmp <- upper[[i]]; epsused <- tmp - p[[i]] }
      x[[i]] <- tmp
      plus <- objective(x)
      tmp <- p[[i]] - eps
      if (tmp < lower[[i]]) { tmp <- lower[[i]]; eps <- p[[i]] - tmp }
      x[[i]] <- tmp
      minus <- objective(x)
      df[[i]] <- (plus - minus) / (epsused + eps)
      if (!is.finite(df[[i]]))
        stop(sprintf("non-finite finite-difference value [%d]", i), call. = FALSE)
    }
    df
  }
}

# An optional fixed metric for each complete optimizer attempt. The objective,
# its original-coordinate finite differences, and final validation are unchanged.
# This rescales coordinates rather than replacing a failed attempt afterwards.
.gt_d_optimizer_metric <- function(at, n, optimizer_control, policy) {
  if (identical(policy, "start"))
    optimizer_control$parscale <- pmax(1, abs(at)) / sqrt(n)
  optimizer_control
}

.gt_d_optimize <- function(at, objective, lower, upper, optimizer_control,
                            label, optimizer = "L-BFGS-B", gradient = NULL) {
  # A function is allowed internally for failure-injection tests only. Public
  # controls select a supported engine, which remains fixed across all trials.
  optimizer_name <- if (is.function(optimizer)) "injected_function" else optimizer
  native_control <- optimizer_control
  if (identical(optimizer_name, "nlminb")) {
    native_control <- list(iter.max = optimizer_control$maxit,
      eval.max = max(200, 10 * optimizer_control$maxit),
      rel.tol = optimizer_control$factr * .Machine$double.eps,
      trace = optimizer_control$trace)
    captured <- .gt_d_capture(stats::nlminb(at, objective, lower = lower,
      upper = upper, control = native_control))
  } else {
    if (!is.function(optimizer)) {
      if (!identical(optimizer_name, "L-BFGS-B")) .gt_d_stop("Unsupported discrete optimizer.")
      optimizer <- stats::optim
    }
    captured <- .gt_d_capture(if (is.null(gradient))
      optimizer(at, objective, method = "L-BFGS-B",
                lower = lower, upper = upper, control = native_control) else
      optimizer(at, objective, gr = gradient, method = "L-BFGS-B",
                lower = lower, upper = upper, control = native_control))
  }
  raw_result <- captured$value
  fit <- raw_result
  if (identical(optimizer_name, "nlminb") && is.list(fit)) fit$value <- fit$objective
  # The objective is not re-evaluated at the projected point: the move is below
  # 1e-10 relative, far under every acceptance tolerance, and each downstream
  # check recomputes the likelihood at these parameters anyway.
  if (is.list(fit) && is.numeric(fit$par) && length(fit$par) == length(at)) {
    projected <- .gt_d_project_bounds(fit$par, lower, upper)
    if (!is.null(projected)) fit$par <- projected
  }
  available <- is.list(fit) && is.numeric(fit$par) &&
    length(fit$par) == length(at) && all(is.finite(fit$par)) &&
    all(fit$par >= lower & fit$par <= upper) &&
    is.numeric(fit$value) && length(fit$value) == 1L &&
    is.finite(fit$value) && fit$value < 1e99 &&
    is.numeric(fit$convergence) && length(fit$convergence) == 1L &&
    is.finite(fit$convergence)
  if (!available) {
    if (is.null(captured$error))
      captured$error <- "Optimizer returned no usable finite result."
    fit <- list(par = at, value = Inf, convergence = 100L,
                message = captured$error)
  } else {
    fit$convergence <- as.integer(fit$convergence)
  }
  # Native optimizers and bound projection may discard vector names. Restore
  # the prepared coordinate contract without changing any parameter value.
  names(fit$par) <- names(at)
  fit$result_available <- available
  fit$attempt <- list(label = label, start = at, error = captured$error,
    warnings = captured$warnings, elapsed_seconds = captured$elapsed_seconds,
    optimizer_code = fit$convergence, optimizer_message = fit$message,
    result_available = available, parameters = fit$par,
    objective = fit$value, optimizer = optimizer_name,
    optimizer_control = native_control,
    raw_result = raw_result)
  fit
}

.gt_d_group <- function(data, members) {
  # Interaction labels contain integer codes only, not potentially colliding
  # user labels. Observed tuples are matched directly without Cartesian grids.
  if (anyNA(data[members])) .gt_d_stop("Missing grouping values are not supported.")
  key <- .gt_tuple_key(data, members)
  group <- match(key, unique(key))
  list(index = group, nlevels = max(group))
}

# A fixed-layout call is the combination of an item batch and a complete
# facet condition. The batch map was validated against the original data,
# including recorded call identifiers, before outcome-only preparation.
.gt_d_call_group <- function(data, design, call) {
  if (!isTRUE(call$modelled) || length(call$batch) != nrow(data) ||
      anyNA(call$batch)) .gt_d_stop("A discrete call source needs a validated fixed batch layout.")
  condition <- if (length(design$facets)) .gt_tuple_key(data, design$facets) else rep("1", nrow(data))
  key <- paste(call$batch, condition, sep = ":")
  group <- match(key, unique(key))
  list(index = group, nlevels = as.integer(max(group)))
}

.gt_d_prepare <- function(data, outcomes, families) {
  if (!is.data.frame(data) || !nrow(data)) .gt_d_stop("data must be a nonempty data.frame.")
  if (!is.character(outcomes) || !length(outcomes) || anyNA(outcomes) ||
      anyDuplicated(outcomes) || any(!outcomes %in% names(data)))
    .gt_d_stop("outcomes must name distinct existing columns.")
  if (inherits(families, "gt_family") || is.character(families$family)) families <- list(families)
  if (!is.list(families) || length(families) != length(outcomes))
    .gt_d_stop("Provide one resolved family specification per outcome.")
  blocks <- vector("list", length(outcomes))
  dimensions <- character()
  parameter_start <- lower <- upper <- numeric()
  parameter_names <- character()
  for (j in seq_along(outcomes)) {
    name <- outcomes[[j]]
    spec <- families[[j]]
    fam <- spec$family
    if (length(fam) != 1L || !fam %in% c("binary", "ordinal", "categorical"))
      .gt_d_stop("The discrete engine accepts binary, ordinal, or categorical families only.")
    link <- spec$link
    if (is.null(link)) link <- if (fam == "categorical") "softmax" else "probit"
    if (!link %in% if (fam == "categorical") "softmax" else c("probit", "logit"))
      .gt_d_stop("Unsupported link for ", fam, ".")
    raw <- data[[name]]
    if (anyNA(raw)) .gt_d_stop("Missing outcomes are not supported by the prototype discrete engine.")
    lev <- spec$levels
    if (fam == "binary") {
      if (is.logical(raw) || (is.numeric(raw) && all(raw %in% c(0, 1)))) {
        y <- as.integer(raw)
        if (is.null(lev)) lev <- c("0", "1")
      } else {
        if (is.null(lev)) lev <- if (is.factor(raw)) levels(raw) else NULL
        if (is.null(lev) || length(lev) != 2L) .gt_d_stop("Binary labels require two declared levels.")
        y <- match(as.character(raw), as.character(lev)) - 1L
      }
      if (length(lev) != 2L || anyNA(y) || length(unique(y)) != 2L)
        .gt_d_stop("Both binary categories must be observed and match declared levels.")
      p <- (sum(y) + 0.5) / (length(y) + 1)
      start <- if (link == "probit") stats::qnorm(p) else stats::qlogis(p)
      indices <- length(parameter_start) + 1L
      parameter_start <- c(parameter_start, start)
      lower <- c(lower, -15); upper <- c(upper, 15)
      parameter_names <- c(parameter_names, paste0(name, "::intercept"))
      dnames <- name
    } else {
      if (is.null(lev)) {
        if (fam == "ordinal" && !is.ordered(raw))
          .gt_d_stop("Ordinal outcomes require an ordered factor or declared levels.")
        lev <- if (is.factor(raw)) levels(raw) else NULL
      }
      if (is.null(lev) || length(lev) < 2L || anyNA(lev) || anyDuplicated(as.character(lev)))
        .gt_d_stop("Declare at least two distinct outcome levels.")
      lev <- as.character(lev)
      if (fam == "categorical") {
        ref <- spec$reference
        if (is.null(ref)) ref <- lev[[1L]]
        if (length(ref) != 1L || !ref %in% lev) .gt_d_stop("Categorical reference must be a declared level.")
        lev <- c(ref, setdiff(lev, ref))
      }
      y <- match(as.character(raw), lev)
      if (anyNA(y)) .gt_d_stop("Outcome values do not match declared levels for ", name, ".")
      freq <- tabulate(y, nbins = length(lev))
      if (any(freq == 0L)) .gt_d_stop("Every declared category must be observed for ", name,
                                    "; empty categories do not identify the current model.")
      if (fam == "ordinal") {
        cp <- cumsum(freq)[-length(freq)] / sum(freq)
        threshold <- if (link == "probit") stats::qnorm(cp) else stats::qlogis(cp)
        start <- c(threshold[[1L]], log(diff(threshold)))
        indices <- length(parameter_start) + seq_along(start)
        parameter_start <- c(parameter_start, start)
        lower <- c(lower, -15, rep(log(1e-4), length(start) - 1L))
        upper <- c(upper, 15, rep(log(100), length(start) - 1L))
        parameter_names <- c(parameter_names, paste0(name, "::threshold_parameter", seq_along(start)))
        dnames <- name
      } else {
        start <- log(freq[-1L] / freq[[1L]])
        indices <- length(parameter_start) + seq_along(start)
        parameter_start <- c(parameter_start, start)
        lower <- c(lower, rep(-15, length(start))); upper <- c(upper, rep(15, length(start)))
        parameter_names <- c(parameter_names, paste0(name, "::", lev[-1L], "_vs_", lev[[1L]], "::intercept"))
        dnames <- paste0(name, "::", lev[-1L], "_vs_", lev[[1L]])
      }
    }
    dims <- length(dimensions) + seq_along(dnames)
    dimensions <- c(dimensions, dnames)
    blocks[[j]] <- list(outcome = name, family = fam, link = link, levels = lev,
                        y = y, dims = dims, parameters = indices,
                        reference = if (fam == "categorical") lev[[1L]] else NULL)
  }
  if (anyDuplicated(dimensions))
    .gt_d_stop("Outcome/category labels produce duplicate latent-dimension names; use unambiguous labels.")
  names(parameter_start) <- parameter_names
  list(blocks = blocks, dimensions = dimensions, start = parameter_start,
       lower = lower, upper = upper, n = nrow(data), q = length(dimensions))
}

# One definition of the discrete covariance request, shared with gt_preflight()
# so that a request it permits is a request that fitting also permits.
.gt_d_validate_covariance_request <- function(covariance) {
  if (!is.character(covariance) || length(covariance) != 1L || is.na(covariance) ||
      !covariance %in% c("diagonal", "unstructured", "exchangeable"))
    .gt_d_stop("Discrete covariance must be a single 'diagonal', 'unstructured' or 'exchangeable'; ",
               "per-source overrides are a Gaussian option.")
  invisible(covariance)
}

# The category-exchangeable structure for nominal outcomes. Each source gives
# every category of a nominal outcome its own random utility, independently and
# with one variance; on the K - 1 contrasts against the reference category that
# is sigma^2 (I + 11'), closed under any change of reference category or
# relabelling of categories. Binary and ordinal outcomes in the same fit keep
# one variance on their single latent dimension, and outcomes are independent of
# one another within a source. One variance parameter per source and outcome,
# in exact-zero-capable variance coordinates.
.gt_d_exchangeable_blocks <- function(blocks, q) {
  if (is.null(blocks) || !is.list(blocks) || !length(blocks))
    .gt_d_stop("The exchangeable covariance needs the prepared outcome blocks.")
  if (!any(vapply(blocks, function(b) identical(b$family, "categorical"), logical(1))))
    .gt_d_stop("covariance = 'exchangeable' is defined for nominal (categorical) outcomes; ",
               "use 'diagonal' for binary and ordinal outcomes.")
  dims <- unlist(lapply(blocks, `[[`, "dims"), use.names = FALSE)
  if (!identical(sort(as.integer(dims)), seq_len(q)))
    .gt_d_stop("The outcome blocks do not partition the latent dimensions.")
  lapply(blocks, function(b) {
    m <- length(b$dims)
    shape <- if (identical(b$family, "categorical")) diag(m) + matrix(1, m, m) else diag(1, m)
    list(outcome = b$outcome, family = b$family, dims = as.integer(b$dims),
         shape = shape, root = t(chol(shape)))
  })
}

.gt_d_covariance_setup <- function(groups, q, covariance, control, dimensions, blocks = NULL) {
  .gt_d_validate_covariance_request(covariance)
  fixed <- control$fixed_covariance
  if (identical(covariance, "exchangeable")) {
    if (!is.null(fixed))
      .gt_d_stop("fixed_covariance is not combined with covariance = 'exchangeable'; ",
                 "supply fixed matrices with covariance = 'unstructured'.")
    if (!control$covariance_parameterization %in% c("auto", "variance"))
      .gt_d_stop("The exchangeable covariance uses variance coordinates; ",
                 "covariance_parameterization must be 'auto' or 'variance'.")
    structure <- .gt_d_exchangeable_blocks(blocks, q)
    start <- rep(control$start_sd^2, length(groups) * length(structure))
    if (any(!is.finite(start)) || (is.null(control$parameter_bounds) && any(start > exp(10))))
      .gt_d_stop("start_sd exceeds the variance parameterization's upper bound.")
    names(start) <- unlist(lapply(names(groups), function(s)
      vapply(structure, function(b) if (identical(b$family, "categorical"))
        paste0(s, "::exchangeable[", b$outcome, "]") else
        paste0(s, "::variance[", dimensions[b$dims], "]"), character(1))), use.names = FALSE)
    return(list(fixed = NULL, start = start, lower = rep(0, length(start)),
      upper = rep(exp(10), length(start)), blocks = structure,
      diagpos = rep(TRUE, length(structure)), per = length(structure), q = q,
      sources = names(groups), parameterization = "exchangeable"))
  }
  if (!is.null(fixed)) {
    if (!is.list(fixed) || is.null(names(fixed)) || anyDuplicated(names(fixed)) ||
        !setequal(names(fixed), names(groups)))
      .gt_d_stop("fixed_covariance must give one named matrix for every random source.")
    factors <- lapply(fixed[names(groups)], function(x) {
      if (!is.matrix(x) || !is.numeric(x) || !identical(dim(x), c(q, q)) ||
          any(!is.finite(x)))
        .gt_d_stop("Fixed source covariance matrices must be finite symmetric q by q matrices.")
      # Unnamed matrices are positional. Once either axis is named, both axes
      # must identify every latent dimension and are aligned independently.
      if (!is.null(rownames(x)) || !is.null(colnames(x))) {
        labels <- dimnames(x)
        if (any(vapply(labels, function(z) is.null(z) || anyNA(z) ||
                       any(!nzchar(z)) || anyDuplicated(z) ||
                       !setequal(z, dimensions), logical(1))))
          .gt_d_stop("Named fixed covariance matrices require unique row and column names matching all latent dimensions.")
        x <- x[dimensions, dimensions, drop = FALSE]
      }
      if (max(abs(x - t(x))) > 1e-9)
        .gt_d_stop("Fixed source covariance matrices must be finite symmetric q by q matrices after label alignment.")
      eig <- eigen(x, symmetric = TRUE)
      if (min(eig$values) < -1e-9) .gt_d_stop("Fixed source covariance matrices must be positive semidefinite.")
      if (covariance == "diagonal" && any(abs(x[row(x) != col(x)]) > 1e-9))
        .gt_d_stop("Off-diagonal fixed covariance supplied with covariance='diagonal'.")
      sweep(eig$vectors, 2L, sqrt(pmax(0, eig$values)), "*")
    })
    return(list(fixed = factors, start = numeric(), lower = numeric(), upper = numeric(), q = q,
                parameterization = "fixed"))
  }
  # Resolve coordinates without changing the requested covariance model.
  # Joint unstructured models retain all cross-outcome covariance parameters.
  # They default to Cholesky coordinates, the entries of the lower-triangular
  # factor with a nonnegative diagonal, which reach a singular source matrix
  # exactly: a zero diagonal entry is a natural boundary, as zero is for direct
  # variances. Log-Cholesky coordinates can only approach that boundary; near
  # it the remaining directions become ill-conditioned and the optimizer stalls
  # short of stationarity. They remain available by explicit request.
  parameterization <- control$covariance_parameterization
  if (identical(parameterization, "auto"))
    parameterization <- if (q == 1L || covariance == "diagonal") "variance" else "cholesky"
  if (identical(parameterization, "variance")) {
    if (q > 1L && covariance != "diagonal")
      .gt_d_stop("The variance parameterization requires a univariate or diagonal covariance model; unstructured joint covariance uses cholesky or log_cholesky coordinates.")
    start <- rep(control$start_sd^2, length(groups) * q)
    if (any(!is.finite(start)) || (is.null(control$parameter_bounds) && any(start > exp(10))))
      .gt_d_stop("start_sd exceeds the variance parameterization's upper bound.")
    names(start) <- unlist(lapply(names(groups), function(s)
      paste0(s, "::variance[", dimensions, "]")), use.names = FALSE)
    return(list(fixed = NULL, start = start, lower = rep(0, length(start)),
      upper = rep(exp(10), length(start)),
      positions = which(diag(q) == 1, arr.ind = TRUE), diagpos = rep(TRUE, q),
      per = as.integer(q), q = q, sources = names(groups),
      parameterization = "variance"))
  }
  positions <- if (covariance == "diagonal") which(diag(q) == 1, arr.ind = TRUE) else
    which(lower.tri(matrix(0, q, q), diag = TRUE), arr.ind = TRUE)
  diagpos <- positions[, 1L] == positions[, 2L]
  per <- nrow(positions)
  # The same factor bounds in both coordinates: a diagonal factor entry at most
  # exp(5), off-diagonal entries within 10 of zero. Cholesky diagonals start at
  # start_sd and may reach zero; log-Cholesky diagonals are logs.
  cholesky <- identical(parameterization, "cholesky")
  if (cholesky && (!is.finite(control$start_sd) || (is.null(control$parameter_bounds) && control$start_sd > exp(5))))
    .gt_d_stop("start_sd exceeds the Cholesky parameterization's upper bound.")
  start <- rep(ifelse(diagpos, if (cholesky) control$start_sd else log(control$start_sd), 0), length(groups))
  lower <- rep(ifelse(diagpos, if (cholesky) 0 else -10, -10), length(groups))
  upper <- rep(ifelse(diagpos, if (cholesky) exp(5) else 5, 10), length(groups))
  names(start) <- unlist(lapply(names(groups), function(s)
    paste0(s, "::chol[", dimensions[positions[, 1L]], ",", dimensions[positions[, 2L]], "]")), use.names = FALSE)
  list(fixed = NULL, start = start, lower = lower, upper = upper,
       positions = positions, diagpos = diagpos, per = per, q = q, sources = names(groups),
       parameterization = if (cholesky) "cholesky" else "log_cholesky")
}

.gt_d_covariance_factors <- function(parameters, setup) {
  if (!is.null(setup$fixed)) return(setup$fixed)
  setNames(lapply(seq_along(setup$sources), function(s) {
    x <- parameters[(s - 1L) * setup$per + seq_len(setup$per)]
    if (setup$parameterization %in% c("variance", "exchangeable")) {
      if (any(!is.finite(x)))
        .gt_d_stop("Direct variance parameters must be finite.")
      # Zero is this parameterization's natural domain boundary, and a bounded
      # optimizer may evaluate a few ulps outside a bound while projecting onto
      # it. Project that rounding noise back onto the boundary; turning it into
      # an error rejects fits whose only fault is arithmetic. A coordinate
      # meaningfully below zero is still a caller error and still stops.
      tolerance <- 1e-10 * max(1, max(abs(x)))
      if (any(x < -tolerance))
        .gt_d_stop("Direct variance parameters must be finite and nonnegative.")
      x <- sqrt(pmax(x, 0))
    } else if (identical(setup$parameterization, "cholesky")) {
      # A zero diagonal entry is the natural boundary; the same rounding
      # projection as for direct variances applies to it.
      if (any(!is.finite(x)))
        .gt_d_stop("Cholesky parameters must be finite.")
      tolerance <- 1e-10 * max(1, max(abs(x)))
      if (any(x[setup$diagpos] < -tolerance))
        .gt_d_stop("Cholesky diagonal parameters must be finite and nonnegative.")
      x[setup$diagpos] <- pmax(x[setup$diagpos], 0)
    } else {
      x[setup$diagpos] <- exp(x[setup$diagpos])
    }
    L <- matrix(0, setup$q, setup$q)
    if (identical(setup$parameterization, "exchangeable")) {
      for (k in seq_along(setup$blocks)) {
        d <- setup$blocks[[k]]$dims
        L[d, d] <- x[[k]] * setup$blocks[[k]]$root
      }
    } else L[setup$positions] <- x
    L
  }), setup$sources)
}

.gt_d_kernel_rank <- function(groups) {
  # <Z_s Z_s', Z_t Z_t'> is the sum of squared joint group counts.
  # This checks source-kernel linear dependence without allocating n by n K's.
  k <- length(groups)
  gram <- matrix(0, k, k)
  for (s in seq_len(k)) for (t in seq_len(s)) {
    key <- paste(groups[[s]]$index, groups[[t]]$index, sep = ":")
    counts <- tabulate(match(key, unique(key)))
    gram[s, t] <- gram[t, s] <- sum(counts^2)
  }
  normalized <- gram / sqrt(outer(diag(gram), diag(gram)))
  values <- eigen(normalized, symmetric = TRUE, only.values = TRUE)$values
  list(rank = sum(values > max(values) * 1e-10), n_sources = k,
       smallest_normalized_eigenvalue = min(values))
}

.gt_d_laplace <- function(parameters, prep, groups, setup, control, details = FALSE,
                          factors_override = NULL) {
  fixed_length <- length(prep$start)
  factors <- if (is.null(factors_override))
    .gt_d_covariance_factors(parameters[-seq_len(fixed_length)], setup) else factors_override
  backend <- .gt_d_dense_backend(groups, factors, prep$n, prep$q)
  answer <- .gt_d_dense_mode(parameters, prep, backend, control, details)
  if (details && isTRUE(answer$valid))
    answer <- append(answer, list(factors = factors), after = 2L)
  answer
}

.gt_d_psd <- function(S) {
  eig <- eigen((S + t(S)) / 2, symmetric = TRUE)
  tcrossprod(sweep(eig$vectors, 2L, sqrt(pmax(0, eig$values)), "*"))
}

.gt_d_covariance_factor <- function(S) {
  eig <- eigen((S + t(S)) / 2, symmetric = TRUE)
  sweep(eig$vectors, 2L, sqrt(pmax(0, eig$values)), "*")
}

# Independent finite differences of the final marginal objective. Covariance
# derivatives use PSD rank-one increments, so they remain defined at zero and
# singular covariance matrices and do not vanish merely because log-SD does.
# Richardson extrapolation and bounded step halving check truncation stability.
# Refinement changes the numerical resolution, never the acceptance tolerance.
.gt_d_stationarity <- function(parameters, prep, groups, setup, control, final,
                              laplace = .gt_d_laplace) {
  # Optimizers may use a finite penalty for a failed conditional mode, but
  # finite differences must never subtract those penalties. Require the
  # detailed validity record at every center and perturbation, stopping at
  # the first failure so later step refinement cannot erase it. The caller
  # preserves this error in the fit and blocks numerical acceptance.
  objective <- function(par, factors = final$factors, location) {
    value <- laplace(par, prep, groups, setup, control,
                     details = TRUE, factors_override = factors)
    reason <- if (!is.list(value) || !isTRUE(value$valid))
      "invalid conditional mode" else if (!isTRUE(value$inner_converged))
      "conditional mode did not converge" else if (
        !is.numeric(value$nll) || length(value$nll) != 1L ||
        !is.finite(value$nll) || value$nll >= 1e99)
      "unusable marginal objective" else NULL
    if (!is.null(reason)) {
      # The probe stops here either way. When the evaluation returned a record,
      # that record travels with the error, so the fit can say why the probe
      # was refused in the evaluation's own terms, and the failed operation is
      # written as a specimen when a directory is configured. A structured
      # refusal's reason and measurements are named in the message; a probe
      # that merely did not converge keeps the established message unchanged.
      # The first failure is the only one, so this needs no allowance.
      failure <- NULL
      detail <- ""
      if (is.list(value)) {
        failure <- .gt_d_failure_record(value,
          list(phase = "stationarity", location = location, parameters = par))
        failure$specimen <- .gt_d_write_specimen(value, failure, prep, control)
        if (!isTRUE(value$valid) && !is.null(value$reason))
          detail <- .gt_d_start_failure_detail(value)
      }
      stop(structure(class = c("gt_discrete_stationarity_failure", "error", "condition"),
        list(message = paste0("Stationarity validation failed at ", location, ": ", reason,
                              detail, "."),
             call = NULL, failure = failure)))
    }
    value$nll
  }
  base <- objective(parameters, location = "center")
  normalization <- sqrt(prep$n)
  # At a natural zero-variance boundary the valid derivative is one-sided.
  # Its raw O(h) truncation error can exceed the accuracy gate even when the
  # extrapolated score is accurate. Halve the step at most six times and keep
  # the original, conservative coarse/fine disagreement criterion.
  max_refinements <- 6L
  refine <- function(derivative, h, scaling, order) {
    coarse <- derivative(h)
    fine <- derivative(h / 2)
    refinements <- 0L
    disagreement <- max(abs(fine - coarse)) * scaling
    while (is.finite(disagreement) &&
           disagreement > control$stationarity_tol / 2 &&
           refinements < max_refinements) {
      h <- h / 2
      coarse <- fine
      fine <- derivative(h / 2)
      refinements <- refinements + 1L
      disagreement <- max(abs(fine - coarse)) * scaling
    }
    multiplier <- 2^order
    list(score = (multiplier * fine - coarse) / (multiplier - 1),
         disagreement = disagreement, step = h, refinements = refinements)
  }
  fixed_score <- fixed_disagreement <- fixed_steps <- numeric(length(prep$start))
  fixed_refinements <- integer(length(prep$start))
  for (j in seq_along(prep$start)) {
    h <- 1e-4 * max(1, abs(parameters[[j]]))
    derivative <- function(step) {
      plus <- minus <- parameters
      plus[[j]] <- plus[[j]] + step; minus[[j]] <- minus[[j]] - step
      label <- paste0("fixed parameter ", names(prep$start)[[j]],
                      " (step ", format(step, scientific = TRUE), ")")
      (objective(plus, location = paste(label, "positive probe")) -
       objective(minus, location = paste(label, "negative probe"))) / (2 * step)
    }
    difference <- refine(derivative, h, 1 / normalization, order = 2L)
    fixed_score[[j]] <- difference$score
    fixed_disagreement[[j]] <- difference$disagreement
    fixed_steps[[j]] <- difference$step
    fixed_refinements[[j]] <- difference$refinements
  }
  names(fixed_score) <- names(fixed_steps) <- names(fixed_refinements) <- names(prep$start)
  cov_gradients <- projected <- list()
  cov_disagreement <- cov_steps <- numeric()
  cov_refinements <- integer()
  if (is.null(setup$fixed)) for (s in seq_along(final$factors)) {
    S <- tcrossprod(final$factors[[s]])
    scale <- max(1, max(diag(S)))
    h <- 1e-4 * scale
    evaluate <- function(increment, direction, step) {
      factors <- final$factors
      factors[[s]] <- .gt_d_covariance_factor(S + increment)
      objective(parameters, factors, location = paste0("covariance source ",
        names(final$factors)[[s]], " ", direction,
        " (step ", format(step, scientific = TRUE), ")"))
    }
    if (identical(setup$parameterization, "exchangeable")) {
      # The feasible directions are the blocks' variances: S moves along its
      # block shape, sigma^2 (I + 11') for a nominal outcome, and only forward
      # from zero. The score of each variance and its KKT projection follow the
      # diagonal case with that one direction per block.
      blocks <- setup$blocks
      derivative <- function(step) vapply(seq_along(blocks), function(k) {
        direction <- matrix(0, prep$q, prep$q)
        d <- blocks[[k]]$dims
        direction[d, d] <- step * blocks[[k]]$shape
        (evaluate(direction, paste("exchangeable block", blocks[[k]]$outcome), step) - base) / step
      }, numeric(1))
      difference <- refine(derivative, h, scale / normalization, order = 1L)
      g <- difference$score
      variance <- vapply(blocks, function(b) S[b$dims[[1L]], b$dims[[1L]]] / b$shape[1L, 1L], numeric(1))
      normalized_variance <- variance / scale
      normalized_g <- g * scale / normalization
      name <- names(final$factors)[[s]]
      projected[[name]] <- normalized_variance - pmax(0, normalized_variance - normalized_g)
      cov_gradients[[name]] <- stats::setNames(g, vapply(blocks, `[[`, character(1), "outcome"))
      cov_disagreement <- c(cov_disagreement, difference$disagreement)
      cov_steps[[name]] <- difference$step
      cov_refinements[[name]] <- difference$refinements
      next
    }
    derivative <- function(step) {
      G <- matrix(0, prep$q, prep$q)
      for (a in seq_len(prep$q)) {
        direction <- matrix(0, prep$q, prep$q); direction[a, a] <- step
        G[a, a] <- (evaluate(direction, paste("diagonal", a), step) - base) / step
      }
      if (!identical(setup$per, prep$q)) for (a in seq_len(prep$q)) {
        if (a == prep$q) next
        for (b in seq.int(a + 1L, prep$q)) {
          plus <- minus <- numeric(prep$q)
          plus[c(a, b)] <- 1; minus[c(a, b)] <- c(1, -1)
          G[a, b] <- G[b, a] <-
            (evaluate(step * tcrossprod(plus), paste("positive contrast", a, b), step) -
             evaluate(step * tcrossprod(minus), paste("negative contrast", a, b), step)) / (4 * step)
        }
      }
      G
    }
    difference <- refine(derivative, h, scale / normalization, order = 1L)
    G <- difference$score
    normalized_S <- S / scale
    normalized_G <- G * scale / normalization
    projected[[names(final$factors)[[s]]]] <- if (identical(setup$per, prep$q))
      diag(normalized_S) - pmax(0, diag(normalized_S) - diag(normalized_G)) else
      normalized_S - .gt_d_psd(normalized_S - normalized_G)
    cov_gradients[[names(final$factors)[[s]]]] <- G
    cov_disagreement <- c(cov_disagreement, difference$disagreement)
    cov_steps[[names(final$factors)[[s]]]] <- difference$step
    cov_refinements[[names(final$factors)[[s]]]] <- difference$refinements
  }
  fixed_norm <- max(c(0, abs(fixed_score) / normalization))
  covariance_norm <- max(abs(c(0, unlist(projected))))
  finite_difference_disagreement <- max(c(0, fixed_disagreement, cov_disagreement))
  checked <- all(is.finite(c(base, fixed_norm, covariance_norm, finite_difference_disagreement))) && base < 1e99
  accepted <- checked && max(fixed_norm, covariance_norm) <= control$stationarity_tol &&
    finite_difference_disagreement <= control$stationarity_tol / 2
  list(stationary_within_tolerance = accepted, fixed_effect_score = fixed_score,
       covariance_gradients = cov_gradients, covariance_projected_scores = projected,
       fixed_effect_scaled_norm = fixed_norm, covariance_scaled_norm = covariance_norm,
       finite_difference_disagreement = finite_difference_disagreement,
       finite_difference_refinement = list(max_refinements = max_refinements,
         fixed_steps = fixed_steps, fixed_refinements = fixed_refinements,
         covariance_steps = cov_steps, covariance_refinements = cov_refinements,
         method = "Richardson extrapolation with bounded step halving; unchanged raw coarse/fine disagreement gate."),
       tolerance = control$stationarity_tol,
       scaling = "Fixed scores divided by sqrt(number of rows); source covariance PSD projection after scaling by max(1, largest source variance), with scores divided by sqrt(number of rows).",
       interpretation = "Independent local first-order Laplace-objective stationarity only; not global optimality, identification, or integration accuracy.")
}

.gt_d_fit_distance <- function(a, b, prep, setup) {
  fixed <- seq_along(prep$start)
  location <- max(c(0, abs(a[fixed] - b[fixed]) / pmax(1, abs(a[fixed]), abs(b[fixed]))))
  A <- .gt_d_covariance_factors(a[-fixed], setup)
  B <- .gt_d_covariance_factors(b[-fixed], setup)
  covariance <- max(c(0, vapply(seq_along(A), function(s) {
    left <- tcrossprod(A[[s]])
    right <- tcrossprod(B[[s]])
    max(abs(left - right)) / max(1, abs(left), abs(right))
  }, numeric(1))))
  max(location, covariance)
}

# Fit one or more discrete outcomes using a joint Laplace likelihood
#
# Internal engine for gt_fit(). covariance is shared as a structure choice
# across sources; every source gets its own matrix. A multivariate ordinal or
# binary fit estimates source covariances across outcomes. A categorical fit
# has K-1 correlated category contrasts per outcome with an explicit reference.
# Mixed discrete families are supported; Gaussian-discrete combinations are
# outside this engine. Missing outcomes and unobserved declared categories are
# rejected in this first implementation. This engine has no REML estimator.
# .laplace and .engine remain private seams for validation. Public callers use
# control$engine; the default remains the dense reference implementation.
# Alternative marginal evaluators are substituted without
# duplicating the outer numerical policy: optimizer, restarts, tight
# validation, stationarity and acceptance must stay single-sourced, because two
# copies of an acceptance rule diverge the moment either is touched.
.gt_fit_discrete <- function(data, outcomes, design, families,
                             covariance = "unstructured", control = list(),
                             call = NULL,
                             .laplace = .gt_d_laplace,
                             .engine = "dense_marginal_laplace") {
  if (!is.function(.laplace)) .gt_d_stop("The marginal evaluator must be a function.")
  if (!is.character(.engine) || length(.engine) != 1L || is.na(.engine) || !nzchar(.engine))
    .gt_d_stop("The engine label must be a single non-empty string.")
  control <- .gt_d_control(control)
  if (missing(.laplace)) {
    .laplace <- if (identical(control$engine, "sparse")) .gt_d_sparse_evaluator() else .gt_d_laplace
    .engine <- paste0(control$engine, "_marginal_laplace")
  }
  sparse <- identical(.engine, "sparse_marginal_laplace")
  analytic <- identical(control$gradient, "analytic")
  if (analytic && !sparse)
    .gt_d_stop("gradient = 'analytic' requires the sparse marginal evaluator.")
  if (analytic && is.null(tryCatch(.gt_selected_platform(), error = function(e) NULL)))
    .gt_d_stop("gradient = 'analytic' needs the compiled selected-inverse routines, which are not available in this session.")
  if (!is.data.frame(data) || nrow(data) > control$max_observations)
    .gt_d_stop("Discrete prototype exceeds max_observations (", control$max_observations,
               "); use a smaller validation design or explicitly revise the resource guard.")
  prep <- .gt_d_prepare(data, outcomes, families)
  terms <- design$term_members
  if (!is.list(terms) || !length(terms) || is.null(names(terms)))
    .gt_d_stop("design must contain named random-source term_members.")
  if (any(!unique(unlist(terms, use.names = FALSE)) %in% names(data)))
    .gt_d_stop("Design grouping columns are missing from data.")
  groups <- lapply(terms, function(members) .gt_d_group(data, members))
  if (isTRUE(call$modelled)) {
    if (.GT_CALL_TERM %in% names(groups))
      .gt_d_stop("A source named ", .GT_CALL_TERM,
        " cannot be combined with a modelled batch; rename that variable.")
    groups[[.GT_CALL_TERM]] <- .gt_d_call_group(data, design, call)
  }
  group_sizes <- vapply(groups, `[[`, integer(1), "nlevels")
  if (any(group_sizes < 2L)) .gt_d_stop("Every random source must contain at least two observed groups.")
  # An unrestricted observation-specific source confounds the identified
  # latent scale, including in joint binary/ordinal models; reject it here.
  if (any(group_sizes == nrow(data)))
    .gt_d_stop("Observation-specific random sources are not supported for discrete outcomes; preserve repeated observations within each source group.")
  random_dimension <- sum(group_sizes) * prep$q
  if (random_dimension > control$max_random_dimension)
    .gt_d_stop("Discrete prototype requires ", random_dimension,
               " random-effect dimensions, exceeding max_random_dimension (",
               control$max_random_dimension, "). Raise this guard only for a qualified design.")
  # Refuse before allocating rather than after the allocation fails. The other
  # limits bound counts; this one bounds the dense algebra those counts imply,
  # and it is what protects a caller who raises them.
  dense <- .gt_d_dense_bytes(nrow(data), prep$q, random_dimension)
  if (!sparse && dense$total > control$max_dense_bytes)
    .gt_d_stop("This discrete model needs an estimated ",
      .gt_d_format_bytes(dense$total), " of dense working memory, above the configured ",
      "max_dense_bytes (", .gt_d_format_bytes(control$max_dense_bytes), "). ",
      "The model has ", nrow(data), " observations, ", prep$q,
      " latent dimension(s) per observation, and ", random_dimension,
      " random-effect dimensions, so its random-design matrix alone is ",
      .gt_d_format_bytes(dense$random_design), ". ",
      "Raising max_dense_bytes does not make the dense algebra practical or the ",
      "Laplace approximation accurate. Fit a scientifically justified smaller ",
      "design, reduce the number of jointly modelled outcomes, or use an ",
      "implementation with a sparse random-effects backend.")
  sparse_memory <- if (sparse)
    .gt_d_sparse_resources(groups, nrow(data), prep$q, random_dimension,
                           control$max_sparse_bytes) else NULL
  if (sparse && sparse_memory$total > control$max_sparse_bytes)
    .gt_d_stop("This discrete model exceeds max_sparse_bytes (",
      .gt_d_format_bytes(control$max_sparse_bytes), "); its sparse working-memory ",
      if (identical(sparse_memory$method, "pattern_exceeds_budget"))
        "lower bound from the conditional Hessian's structural nonzeros alone is " else
        "estimate from one factorization of the structural pattern is ",
      .gt_d_format_bytes(sparse_memory$total), ". Raising a resource guard ",
      "does not establish numerical acceptance or Laplace approximation accuracy.")
  setup <- .gt_d_covariance_setup(groups, prep$q, covariance, control, prep$dimensions, prep$blocks)
  # A direct or exchangeable variance is a square of the factor entry the
  # gradient is computed in; at an exact zero, a natural bound the optimizer
  # reaches whenever a variance's optimum is zero, its derivative needs second
  # derivatives in the factor and the fixed-point gradient refuses it. Natural
  # Cholesky entries are differentiable at zero and log-Cholesky diagonals never
  # reach it, so the route is offered on those coordinates and on fixed
  # covariances, and refused here rather than at the first boundary gradient.
  if (analytic && setup$parameterization %in% c("variance", "exchangeable"))
    .gt_d_stop("gradient = 'analytic' supports natural Cholesky and log-Cholesky source covariance ",
      "coordinates and fixed covariances. This model resolves to ", setup$parameterization,
      " coordinates, whose derivative at an exact zero variance is not available analytically; ",
      if (identical(setup$parameterization, "variance"))
        "set covariance_parameterization = 'cholesky' or use the finite-difference gradient." else
        "use the finite-difference gradient for an exchangeable covariance.")
  kernel_rank <- .gt_d_kernel_rank(groups)
  # A combination of individually repeated-group kernels can still equal I.
  # For probit responses, that permits rescaling the total latent covariance
  # and intercepts/thresholds despite the nominally fixed residual variance.
  # Apply this conservative prototype guard to all free-covariance discrete
  # fits; it is not a claim of nonidentification for every possible link/model.
  augmented_rank <- .gt_d_kernel_rank(c(unname(groups), list(
    list(index = seq_len(nrow(data)), nlevels = nrow(data)))))
  source_residual_rank <- list(rank = augmented_rank$rank,
    n_kernels = augmented_rank$n_sources, n_random_sources = length(groups),
    includes_observation_identity = TRUE,
    smallest_normalized_eigenvalue = augmented_rank$smallest_normalized_eigenvalue)
  if (is.null(setup$fixed) && kernel_rank$rank < kernel_rank$n_sources)
    .gt_d_stop("Random-source kernels are linearly dependent in the observed data; separate source covariances are not identified.")
  if (is.null(setup$fixed) && source_residual_rank$rank < source_residual_rank$n_kernels)
    .gt_d_stop("Random-source kernels span an observation-specific component. The discrete prototype does not estimate this structure alongside its fixed observation-scale model; revise the source specification.")
  domain <- .gt_d_parameter_domain(prep, setup, control)
  prep <- domain$prep; setup <- domain$setup
  start <- domain$start; automatic_start <- domain$automatic_start
  lower <- domain$lower; upper <- domain$upper
  if (length(start) > control$max_parameters)
    .gt_d_stop("Discrete prototype exceeds max_parameters (", control$max_parameters, ").")
  # The analytic route's structural envelope is built once per fit, and the
  # design is checked against the compiled caps before any attempt runs.
  gradient_route <- NULL
  if (analytic) {
    envelope_started <- proc.time()[["elapsed"]]
    gradient_context <- .gt_d_sparse_context(groups, prep$n, prep$q)
    gradient_envelope <- .gt_d_sparse_envelope(gradient_context)
    envelope_seconds <- unname(proc.time()[["elapsed"]] - envelope_started)
    feasibility <- .gt_d_gradient_feasibility(length(groups), prep$n, prep$q, random_dimension,
                                              gradient_envelope$factor_entries)
    if (!isTRUE(feasibility$passed))
      .gt_d_stop("gradient = 'analytic' cannot run on this design: ", feasibility$detail)
    gradient_route <- .gt_d_gradient_route(prep, groups, setup, gradient_context, gradient_envelope,
                                           names(start), envelope_seconds = envelope_seconds)
  }
  retain <- if (analytic) gradient_route$retain else function(parameters, value, phase) value
  # Every objective evaluation is performed in detailed form and reduced to its
  # scalar by the log, so an evaluation that fails is described by its own
  # record; see .gt_d_evaluation_log(). The arithmetic is unchanged.
  evaluations <- .gt_d_evaluation_log(control, prep)
  # L-BFGS-B attempts name each evaluation's role (see .gt_d_sparse_evaluator):
  # the optimizer's function evaluations are "warm" and the probes of the
  # explicit gradient below are "warm_probe". The gradient is optim's own
  # finite-difference rule written out (.gt_d_numerical_gradient), so the
  # optimizer's path is unchanged. Other optimizers form their finite
  # differences internally, where no role can be named; their evaluations,
  # and every evaluation outside an optimizer attempt, carry no role and solve
  # cold from zero modes. The dense evaluator ignores roles.
  explicit_roles <- identical(control$optimizer, "L-BFGS-B")
  role_control <- function(base, role) {
    if (explicit_roles) base$inner_start <- role
    base
  }
  warm_control <- role_control(control, "warm")
  probe_control <- role_control(control, "warm_probe")
  reset_evaluator <- attr(.laplace, "reset")
  begin_attempt <- function() {
    if (is.function(reset_evaluator)) reset_evaluator()
    if (analytic) gradient_route$clear()
  }
  objective <- function(par)
    evaluations$observe(par, retain(par, .laplace(par, prep, groups, setup, warm_control, details = TRUE),
                                    "coarse"), "coarse")
  probe_objective <- function(par)
    evaluations$observe(par, .laplace(par, prep, groups, setup, probe_control, details = TRUE), "coarse")
  coarse_gradient <- if (analytic) gradient_route$callback("coarse", objective, warm_control) else
    if (explicit_roles)
    .gt_d_numerical_gradient(probe_objective, rep(1e-3, length(start)), lower, upper)
  # The start is evaluated once and its record read directly. There is no
  # replay: see .gt_d_start_failure_detail. The refusal stands on the evidence
  # of the evaluation that refused.
  initial <- .laplace(start, prep, groups, setup, control, details = TRUE)
  if (!.gt_d_evaluation_usable(initial)) {
    record <- .gt_d_failure_record(initial, list(phase = "start", parameters = start))
    .gt_d_stop("The discrete likelihood did not yield a converged finite inner mode at starting values",
               .gt_d_start_failure_detail(initial),
               .gt_d_specimen_note(.gt_d_write_specimen(initial, record, prep, control)), ".")
  }
  optimizer_control <- list(maxit = control$maxit,
    factr = control$reltol / .Machine$double.eps, trace = control$trace)
  # L-BFGS-B begins from an identity Hessian, and every discrete coordinate has
  # two finite bounds, so its first trial point is the start minus the raw
  # gradient. The objective sums over rows and so does its gradient: on the
  # 21,600-row drug-review panel an ordinal fit's first trial point put the item
  # variance near 4,000, every conditional solve there failed, and the line
  # search ended the attempt at its start after three evaluations. A coarse
  # attempt that ends where it began after an invalid evaluation has collapsed
  # this way. It is run again from the same start at a uniform parameter scale
  # of 1/sqrt(rows), which makes the first step the per-row gradient; later
  # steps take their scale from the curvature the optimizer observes, and the
  # objective is not rescaled, so the relative-reduction rule is unchanged. An
  # attempt that moved is never rerun, so no path that did not collapse
  # changes. Scaling every attempt instead changes every path, and on a frozen
  # smoke case it left a tight attempt starting within 1e-8 of the optimum with
  # no representable decrease, so its line search ended abnormally. The
  # collapsed run is kept in the attempt's record.
  coarse_attempt <- function(at, label) {
    invalid_before <- evaluations$summary()$invalid
    begin_attempt()
    attempt_control <- .gt_d_optimizer_metric(at, prep$n, optimizer_control,
                                             control$optimizer_scaling)
    result <- .gt_d_optimize(at, objective, lower, upper, attempt_control, label,
                             optimizer = control$optimizer, gradient = coarse_gradient)
    invalid <- evaluations$summary()$invalid - invalid_before
    moved <- max(c(0, abs(result$par - at) / pmax(1, abs(at))))
    # An exception or unusable optimizer result is a failed attempt, not a
    # finite first step that collapsed. Keep that original failure so the
    # downstream acceptance rule cannot mistake a successful rerun for clean
    # completion of every required attempt.
    if (!identical(control$optimizer_scaling, "none") ||
        !explicit_roles || !isTRUE(result$result_available) ||
        !is.null(result$attempt$error) || invalid == 0L || moved > 1e-8) return(result)
    collapsed <- result$attempt
    scaled_control <- optimizer_control
    scaled_control$parscale <- rep(1 / sqrt(prep$n), length(at))
    begin_attempt()
    result <- .gt_d_optimize(at, objective, lower, upper, scaled_control, label,
                             optimizer = control$optimizer, gradient = coarse_gradient)
    result$attempt$first_step_rescue <- list(
      invalid_evaluations = invalid, parameter_scale = 1 / sqrt(prep$n),
      collapsed_objective = collapsed$objective,
      collapsed_optimizer_code = collapsed$optimizer_code,
      collapsed_optimizer_message = collapsed$optimizer_message,
      collapsed_counts = collapsed$raw_result$counts,
      collapsed_elapsed_seconds = collapsed$elapsed_seconds,
      collapsed_attempt = collapsed)
    result
  }
  primary_fit <- coarse_attempt(start, "primary")
  attempts <- list(primary_fit$attempt)
  coarse_candidates <- list(primary_fit)
  # Optimizer completion alone is insufficient. Refine with a tighter inner
  # solve and objective tolerance, then independently restart away from the
  # fitted point. No random numbers or global RNG state are used for starts.
  validation_control <- control
  validation_control$inner_tol <- min(control$inner_tol, control$validation_inner_tol)
  validation_control$reltol <- min(control$reltol, control$validation_reltol)
  tight_objective <- function(par)
    evaluations$observe(par, .laplace(par, prep, groups, setup, validation_control, details = TRUE),
                        "tight", settings = validation_control)
  tight_warm_control <- role_control(validation_control, "warm")
  tight_probe_control <- role_control(validation_control, "warm_probe")
  tight_attempt_objective <- function(par)
    evaluations$observe(par, retain(par, .laplace(par, prep, groups, setup, tight_warm_control,
                                                  details = TRUE), "tight"),
                        "tight", settings = validation_control)
  tight_probe_objective <- function(par)
    evaluations$observe(par, .laplace(par, prep, groups, setup, tight_probe_control, details = TRUE),
                        "tight", settings = validation_control)
  tight_steps <- rep(1e-4, length(start))
  tight_gradient <- if (analytic) gradient_route$callback("tight", tight_attempt_objective,
                                                          tight_warm_control) else
    if (explicit_roles)
    .gt_d_numerical_gradient(tight_probe_objective, tight_steps, lower, upper)
  optimize_tight <- function(at, label) {
    begin_attempt()
    attempt_control <- .gt_d_optimizer_metric(at, prep$n,
      list(maxit = control$maxit,
        factr = validation_control$reltol / .Machine$double.eps,
        pgtol = 1e-7, ndeps = tight_steps, trace = control$trace), control$optimizer_scaling)
    result <- .gt_d_optimize(at, tight_attempt_objective, lower, upper,
      attempt_control, label,
      optimizer = control$optimizer, gradient = tight_gradient)
    attempts[[length(attempts) + 1L]] <<- result$attempt
    result
  }
  fit <- optimize_tight(primary_fit$par, "primary_tight")
  alternatives <- vector("list", control$alternative_starts)
  for (attempt in seq_len(control$alternative_starts)) {
    alternative <- start
    fixed <- seq_along(prep$start)
    tier <- 1L + (attempt - 1L) %/% 2L
    alternative[fixed] <- alternative[fixed] + .15 * tier * (-1)^(fixed + attempt)
    if (length(setup$start)) {
      cov_index <- length(prep$start) + seq_along(setup$start)
      alternative[cov_index] <- setup$start
      diagonal <- rep(setup$diagpos, length(groups))
      multiplier <- if (attempt %% 2L) 1.8 * tier else .55 / tier
      if (setup$parameterization %in% c("variance", "exchangeable")) {
        alternative[cov_index] <- alternative[cov_index] * multiplier^2
      } else if (identical(setup$parameterization, "cholesky")) {
        alternative[cov_index[diagonal]] <- alternative[cov_index[diagonal]] * multiplier
        alternative[cov_index[!diagonal]] <- .1 * tier * (-1)^attempt
      } else {
        alternative[cov_index[diagonal]] <- alternative[cov_index[diagonal]] + log(multiplier)
        alternative[cov_index[!diagonal]] <- .1 * tier * (-1)^attempt
      }
    }
    # A fixed padding can leave a narrow user-declared domain. Keep the
    # established padding for ordinary domains and scale it only when needed.
    padding <- pmin(1e-6, (upper - lower) / 4)
    alternative <- pmin(upper - padding, pmax(lower + padding, alternative))
    names(alternative) <- names(start)
    # Clipping extreme user starts can collapse otherwise distinct trials.
    # Keep a distinct first fixed-effect coordinate without using the RNG.
    duplicate_start <- function(x) any(vapply(coarse_candidates, function(candidate)
      identical(unname(x), unname(candidate$attempt$start)), logical(1)))
    if (duplicate_start(alternative)) {
      grid <- lower[[1L]] + seq(.1, .9, length.out = 25L) * (upper[[1L]] - lower[[1L]])
      for (value in grid[order(abs(grid - automatic_start[[1L]]))]) {
        alternative[[1L]] <- value
        if (!duplicate_start(alternative)) break
      }
    }
    alternative_primary <- coarse_attempt(alternative, paste0("alternative_", attempt))
    attempts[[length(attempts) + 1L]] <- alternative_primary$attempt
    coarse_candidates[[length(coarse_candidates) + 1L]] <- alternative_primary
    alternatives[[attempt]] <- optimize_tight(alternative_primary$par,
      paste0("alternative_", attempt, "_tight"))
  }
  if (analytic) gradient_route$clear()
  # Return the best tight fit; retain all objective values and distances so a
  # better restart cannot erase evidence of unstable solutions.
  candidates <- c(list(fit), alternatives)
  values <- vapply(candidates, `[[`, numeric(1), "value")
  # Independently re-evaluate usable candidates; a diagnostic exception must
  # not erase a completed primary fit. Failed checks remain explicit and block
  # reliability, even when another candidate can be retained for inspection.
  final_checks <- list()
  evaluate_final <- function(candidate, settings, label) {
    captured <- .gt_d_capture(.laplace(candidate$par, prep, groups,
      setup, settings, details = TRUE))
    valid <- isTRUE(captured$value$valid) &&
      is.finite(captured$value$nll) && captured$value$nll < 1e99
    # A final check can fail without raising: the evaluator returns a
    # structured refusal carrying its reason, its measurements and the failed
    # operation. That record is kept with the check, and the operation is
    # written as a specimen when a directory is configured, under the settings
    # this check ran with. The number of final checks is bounded by the number
    # of candidates, so this needs no allowance of its own.
    failure <- NULL
    if (!valid && is.list(captured$value)) {
      failure <- .gt_d_failure_record(captured$value,
        list(phase = "final", label = label, parameters = candidate$par))
      failure$specimen <- .gt_d_write_specimen(captured$value, failure, prep, settings)
    }
    final_checks[[length(final_checks) + 1L]] <<- list(label = label,
      valid = valid, error = captured$error, warnings = captured$warnings,
      elapsed_seconds = captured$elapsed_seconds, failure = failure)
    if (valid) captured$value else NULL
  }
  final <- NULL
  tight_final_mode <- FALSE
  usable <- which(vapply(candidates, function(x) isTRUE(x$result_available), logical(1)))
  for (index in usable[order(values[usable])]) {
    checked <- evaluate_final(candidates[[index]], validation_control,
                              paste0("tight_candidate_", index))
    if (!is.null(checked)) {
      fit <- candidates[[index]]
      final <- checked
      tight_final_mode <- TRUE
      break
    }
  }
  # Every usable preliminary attempt remains eligible for diagnostic fallback,
  # including alternatives when the primary and all refinements failed. Try
  # tight conditional modes for all of them before using a looser mode. Such
  # failed validation paths still block numerical acceptance below.
  if (is.null(final)) {
    coarse_values <- vapply(coarse_candidates, `[[`, numeric(1), "value")
    coarse_usable <- which(vapply(coarse_candidates,
      function(x) isTRUE(x$result_available), logical(1)))
    coarse_order <- coarse_usable[order(coarse_values[coarse_usable])]
    for (tight in c(TRUE, FALSE)) {
      checked_candidates <- lapply(coarse_order, function(index) {
        candidate <- coarse_candidates[[index]]
        evaluate_final(candidate, if (tight) validation_control else control,
          paste0(candidate$attempt$label, if (tight) "_fallback_tight" else "_fallback"))
      })
      valid <- which(!vapply(checked_candidates, is.null, logical(1)))
      if (length(valid)) {
        selected <- valid[[which.min(vapply(checked_candidates[valid], `[[`, numeric(1), "nll"))]]
        final <- checked_candidates[[selected]]
        fit <- coarse_candidates[[coarse_order[[selected]]]]
        tight_final_mode <- tight
        break
      }
    }
  }
  if (is.null(final)) stop(structure(list(
    message = "No fitted candidate supplied a usable final conditional mode; inspect the condition's attempts and final_checks.",
    call = NULL, attempts = attempts, final_checks = final_checks),
    class = c("gt_discrete_numerical_failure", "error", "condition")))
  stationarity_failure <- NULL
  captured_stationarity <- .gt_d_capture(withCallingHandlers(
    .gt_d_stationarity(fit$par, prep, groups, setup, validation_control, final,
                       laplace = .laplace),
    gt_discrete_stationarity_failure = function(e) stationarity_failure <<- e$failure))
  stationarity <- captured_stationarity$value
  if (is.null(stationarity)) stationarity <- list(
    stationary_within_tolerance = FALSE,
    error = captured_stationarity$error, tolerance = control$stationarity_tol,
    failure = stationarity_failure)
  stationarity$warnings <- captured_stationarity$warnings
  # The gradient record. For the analytic route it also carries, as a
  # diagnostic only, the analytic gradient at the selected point beside the
  # stationarity check's finite-difference fixed-effect score, on the check's
  # scale. Acceptance never reads it.
  gradient_record <- list(route = control$gradient)
  if (analytic) {
    gradient_record <- gradient_route$summary()
    gradient_record$selected_point <- tryCatch({
      answer <- gradient_route$at(fit$par, final, validation_control)
      if (!isTRUE(answer$valid)) list(available = FALSE, reason = answer$reason) else {
        analytic_fixed <- answer$gradient[names(prep$start)]
        score <- stationarity$fixed_effect_score
        list(available = TRUE, gradient = answer$gradient,
             finite_difference_fixed_effect_score = score,
             max_scaled_fixed_difference = if (is.numeric(score) && identical(names(score), names(analytic_fixed)))
               max(c(0, abs(analytic_fixed - score))) / sqrt(prep$n) else NA_real_,
             scaling = "Fixed-effect differences divided by sqrt(number of rows), as the stationarity check scales its scores.")
      }
    }, error = function(e) list(available = FALSE, reason = conditionMessage(e)))
  }
  primary_tight <- .gt_d_capture(tight_objective(primary_fit$par))
  computation_failed <- any(vapply(attempts, function(x) !is.null(x$error), logical(1))) ||
    any(vapply(final_checks, function(x) !isTRUE(x$valid), logical(1))) ||
    !is.null(captured_stationarity$error) || !is.null(primary_tight$error)
  objective_difference <- abs(values - fit$value) / max(1, abs(fit$value))
  parameter_difference <- vapply(candidates, function(x) {
    if (!isTRUE(x$result_available)) return(Inf)
    .gt_d_fit_distance(x$par, fit$par, prep, setup)
  }, numeric(1))
  candidate_codes <- vapply(candidates, `[[`, integer(1), "convergence")
  stability <- list(checked = length(alternatives) > 0L,
    stable = length(alternatives) > 0L && !computation_failed &&
      tight_final_mode && all(candidate_codes == 0L) &&
      all(objective_difference <= control$stability_objective_tol) &&
      all(parameter_difference <= control$stability_parameter_tol),
    primary_optimizer_code = primary_fit$convergence,
    primary_objective_at_tighter_tolerance = if (is.null(primary_tight$value)) NA_real_ else primary_tight$value,
    primary_tight_evaluation_error = primary_tight$error,
    tight_objectives = values, optimizer_codes = candidate_codes,
    tight_parameters = lapply(candidates, `[[`, "par"),
    relative_objective_differences = objective_difference,
    scaled_parameter_differences = parameter_difference,
    objective_tolerance = control$stability_objective_tol,
    parameter_tolerance = control$stability_parameter_tol,
    alternative_starts = length(alternatives),
    validation_inner_tol = validation_control$inner_tol,
    validation_reltol = validation_control$reltol,
    # Retained beside the validation tolerances they are compared against. A
    # public fit stores the gt_control object, whose discrete settings are
    # empty unless the caller set one, so these cannot be recovered from the
    # fit's control afterwards.
    inner_tol = control$inner_tol, inner_maxit = control$inner_maxit)
  components <- lapply(final$factors, function(L) {
    out <- tcrossprod(L)
    dimnames(out) <- list(prep$dimensions, prep$dimensions)
    out
  })
  means <- setNames(numeric(prep$q), prep$dimensions)
  thresholds <- list()
  residual <- setNames(rep(NA_real_, prep$q), prep$dimensions)
  mapping <- vector("list", length(prep$blocks))
  probabilities <- vector("list", length(prep$blocks))
  for (j in seq_along(prep$blocks)) {
    b <- prep$blocks[[j]]
    if (b$family == "ordinal") {
      thresholds[[b$outcome]] <- setNames(.gt_d_thresholds(fit$par[b$parameters]),
                                          paste(b$levels[-length(b$levels)], b$levels[-1L], sep = "|"))
      probs <- .gt_d_ordinal_probabilities(as.vector(final$eta[, b$dims]),
                                            thresholds[[b$outcome]], b$link)
    } else {
      means[b$dims] <- fit$par[b$parameters]
      if (b$family == "binary") {
        # Evaluate each tail directly: subtraction can round small but
        # representable negative-event probabilities to zero.
        cdf <- if (b$link == "probit") stats::pnorm else stats::plogis
        probs <- cbind(cdf(final$eta[, b$dims], lower.tail = FALSE),
                       cdf(final$eta[, b$dims]))
      } else {
        e <- cbind(0, final$eta[, b$dims, drop = FALSE])
        e <- exp(e - apply(e, 1L, max))
        probs <- e / rowSums(e)
      }
    }
    colnames(probs) <- b$levels
    probabilities[[j]] <- probs
    if (b$family != "categorical") residual[b$dims] <- if (b$link == "probit") 1 else pi^2 / 3
    mapping[[j]] <- data.frame(outcome = b$outcome, family = b$family, link = b$link,
                               dimension = prep$dimensions[b$dims],
                               category = if (b$family == "categorical") b$levels[-1L] else NA_character_,
                               reference = if (b$family == "categorical") b$levels[[1L]] else NA_character_,
                               stringsAsFactors = FALSE)
  }
  names(probabilities) <- outcomes
  natural_lower <- domain$natural_lower
  at_bound <- names(start)[(!natural_lower & fit$par - lower < control$bound_tol) |
                            (upper - fit$par < control$bound_tol)]
  zero_variances <- names(start)[natural_lower & fit$par == 0]
  boundary_sources <- names(components)[vapply(components, function(S)
    min(eigen(S, symmetric = TRUE, only.values = TRUE)$values) < 1e-6, logical(1))]
  variables <- unique(c(design$object, design$facets))
  counts <- setNames(vapply(data[variables], function(x) length(unique(x)), integer(1)), variables)
  optimizer_completed <- fit$convergence == 0L
  converged <- optimizer_completed && final$inner_converged && tight_final_mode &&
    isTRUE(stationarity$stationary_within_tolerance) && stability$stable &&
    !computation_failed && !length(at_bound)
  approximation_adequacy <- if (all(vapply(final$factors, function(L) all(L == 0), logical(1))))
    "exact_no_random_variation" else "not_assessed_first_order_laplace"
  acceptance_failures <- c(if (!optimizer_completed) "optimizer_incomplete",
    if (!final$inner_converged) "inner_mode_not_converged",
    if (!tight_final_mode) "tight_final_mode_unavailable",
    if (computation_failed) "validation_computation_failed",
    if (!isTRUE(stationarity$stationary_within_tolerance)) "outer_stationarity_failed",
    if (!stability$stable) "restart_or_tolerance_stability_failed",
    if (length(at_bound)) "artificial_parameter_bound_contact")
  diagnostics <- list(converged = converged, optimizer_completed = optimizer_completed,
                       numerically_accepted = converged,
                       approximation_adequacy = approximation_adequacy,
                       acceptance_failures = acceptance_failures,
                       outer_stationarity = stationarity, stability = stability,
                       attempts = attempts, final_checks = final_checks,
                       selected_attempt = fit$attempt$label,
                       optimizer = control$optimizer,
                       optimizer_fixed_across_attempts = TRUE,
                       optimization_trials = length(attempts),
                       optimization_trial_budget = 2L * (1L + control$alternative_starts),
                       starting_parameters = start, automatic_starting_parameters = automatic_start,
                       supplied_start_parameters = control$start,
                       tight_final_mode = tight_final_mode,
                       # Which marginal evaluator produced this fit. Retained so
                       # a qualification run can prove the backend it claims to
                       # exercise actually ran, rather than inferring it from a
                       # green result. Not a public selector. The public
                       # fit$engine is derived from it by .gt_d_engine_label(),
                       # so a fit produced through the private seam by another
                       # backend never describes itself as the dense engine.
                       marginal_backend = .engine,
                       resource_estimate = if (sparse) sparse_memory else dense,
                       # Original-operation evidence for the evaluations the
                       # optimizer could not use; see .gt_d_evaluation_log().
                       evaluations = evaluations$summary(),
                       gradient = gradient_record,
                       covariance_parameterization = setup$parameterization,
                       covariance_parameterization_requested = control$covariance_parameterization,
                       zero_variance_parameters = zero_variances,
                       acceptance = "Completed optimizer, tight conditional mode, independent fixed-effect and covariance-scale stationarity, stable tight restarts, and no artificial-bound contact. Approximation adequacy is separate.",
                       optimizer_code = fit$convergence,
                       optimizer_message = fit$message, inner_converged = final$inner_converged,
                       inner_gradient = final$inner_gradient, inner_iterations = final$inner_iterations,
                       inner_roundoff_steps = final$inner_roundoff_steps,
                       inner_warm_started = isTRUE(final$inner_warm_started),
                       random_dimension = random_dimension, parameter_count = length(start),
                       boundary_sources = boundary_sources, parameter_bounds = at_bound,
                       parameter_domain = domain$record,
                       source_kernel_rank = kernel_rank,
                       source_residual_kernel_rank = source_residual_rank,
                       source_covariances_estimated = is.null(setup$fixed),
                       observation_scale_guard = if (is.null(setup$fixed))
                         "Random-source kernels and observation identity must be linearly independent; necessary safeguard, not proof of identification." else
                         "Covariance-estimation rank guards bypassed because all source covariance matrices were supplied as fixed.",
                       approximation = "First-order Laplace marginal ML; accuracy is not established for sparse groups or large annotation panels.",
                       conditional_independence = TRUE,
                       uncertainty = "Observed-information uncertainty is conditional on numerical acceptance, interior covariance and stable curvature.")
  # The same validated-design step the Gaussian path uses: it records the
  # scope and removes the constructor's specification-only note, which would
  # otherwise survive into gt_diagnostics() after the data checks had run.
  design <- .gt_design_validated(design, if (is.null(setup$fixed))
    "Observed grouping columns, repeated groups, and linear independence of source kernels plus observation identity; this is not proof of discrete-model identification." else
    "Observed grouping columns and repeated groups checked; all source covariances fixed, so covariance-estimation rank guards were not enforced.")
  if (!is.null(call)) design$batch_model <- call[setdiff(names(call), c("batch", "slot"))]
  if (isTRUE(call$modelled)) {
    item_levels <- unique(data[[design$object]])
    first_item_rows <- match(item_levels, data[[design$object]])
    design$batch_model$item_levels <- item_levels
    design$batch_model$item_batches <- unname(call$batch[first_item_rows])
  }
  # On the analytic route the information differences the analytic gradient,
  # each at a cold conditional mode under the validation settings.
  information_gradient <- if (analytic) function(at) {
    record <- .laplace(at, prep, groups, setup, validation_control, details = TRUE)
    if (!.gt_d_evaluation_usable(record) || !isTRUE(record$inner_converged))
      stop("A conditional mode failed during information evaluation.", call. = FALSE)
    answer <- gradient_route$at(at, record, validation_control)
    if (!isTRUE(answer$valid))
      stop("An information gradient was refused (", answer$reason, ").", call. = FALSE)
    answer$gradient
  }
  information <- if (isTRUE(control$check_hessian))
    .gt_d_information(fit$par, prep, groups, setup, validation_control, laplace = .laplace,
      lower = lower, upper = upper, numerically_accepted = converged,
      boundary_components = boundary_sources, gradient = information_gradient) else
    list(available = FALSE,
         reason = "Observed-information calculation was not requested; coefficients are point estimates only.",
         method = NA_character_, boundary_components = boundary_sources)
  diagnostics$uncertainty <- if (isTRUE(information$available)) information$method else information$reason
  component_errors <- NULL
  if (isTRUE(information$available)) {
    diagonal <- information$entries$row == information$entries$column
    entries <- information$entries[diagonal, , drop = FALSE]
    component_errors <- data.frame(component = entries$component, trait = entries$row,
      std_error = sqrt(pmax(0, diag(information$entry_covariance)[diagonal])),
      at_boundary = entries$component %in% boundary_sources, stringsAsFactors = FALSE)
  }
  list(engine = .gt_d_engine_label(.engine), estimator = "ML_Laplace", method = "ML_Laplace",
       means = means, coefficients = means, thresholds = thresholds,
       covariance_components = components, latent_residual_variances = residual,
       link_dimensions = do.call(rbind, mapping), minus2loglik = 2 * final$nll,
       logLik = -final$nll, npar = length(start), nobs = nrow(data), counts = counts,
       group_counts = group_sizes, converged = converged,
       optimizer_completed = optimizer_completed, numerically_accepted = converged,
       approximation_adequacy = approximation_adequacy, diagnostics = diagnostics,
       conditional_eta = final$eta, conditional_probabilities = probabilities,
       uncertainty = information, component_standard_errors = component_errors,
       parameters = fit$par, starting_parameters = start, optimizer = fit, covariance = covariance,
       families = families, outcomes = outcomes, design = design, residual_structure = "fixed_by_link",
       control = control)
}

.gt_fit_binary <- function(data, outcomes, design, families,
                           covariance = "unstructured", control = list()) {
  if (any(vapply(families, function(x) x$family != "binary", logical(1))))
    .gt_d_stop(".gt_fit_binary requires binary family specifications.")
  .gt_fit_discrete(data, outcomes, design, families, covariance, control)
}

.gt_fit_ordinal <- function(data, outcomes, design, families,
                            covariance = "unstructured", control = list()) {
  if (any(vapply(families, function(x) x$family != "ordinal", logical(1))))
    .gt_d_stop(".gt_fit_ordinal requires ordinal family specifications.")
  .gt_fit_discrete(data, outcomes, design, families, covariance, control)
}

.gt_fit_categorical <- function(data, outcomes, design, families,
                                covariance = "unstructured", control = list()) {
  if (any(vapply(families, function(x) x$family != "categorical", logical(1))))
    .gt_d_stop(".gt_fit_categorical requires categorical family specifications.")
  .gt_fit_discrete(data, outcomes, design, families, covariance, control)
}
