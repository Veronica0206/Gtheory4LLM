# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Public dispatch is provided by gt_fit(); this file owns the Gaussian backend.

.gt_gaussian_validate_control <- function(control) {
  allowed <- c("start", "optimizer", "max_iterations", "tolerance", "check_hessian",
               "threads", "silent", "extra_tries", "retry_seed", "max_preparation_bytes")
  if (!is.list(control) || (length(control) && (is.null(names(control)) ||
      anyNA(names(control)) || any(!nzchar(names(control))) || anyDuplicated(names(control)))))
    stop("Gaussian control must be a uniquely named list.", call. = FALSE)
  unknown <- setdiff(names(control), allowed)
  if (length(unknown)) stop("Unsupported Gaussian control setting(s): ",
                           paste(unknown, collapse = ", "), call. = FALSE)
  if (!is.null(control$optimizer) && (!is.character(control$optimizer) ||
      length(control$optimizer) != 1L || is.na(control$optimizer) ||
      !control$optimizer %in% c("CSOLNP", "SLSQP", "NPSOL")))
    stop("optimizer must be CSOLNP, SLSQP, or NPSOL (if available in OpenMx).", call. = FALSE)
  if (!is.null(control$silent) && (!is.logical(control$silent) ||
      length(control$silent) != 1L || is.na(control$silent)))
    stop("silent must be TRUE or FALSE.", call. = FALSE)
  control
}

# Match starting covariance matrices by their source and outcome names before
# the engine checks symmetry/PSD. Fully unnamed axes retain positional meaning;
# one named axis or incomplete labels would make that meaning ambiguous.
# The engine applies its existing interior repair to admissible starts and then
# projects them to the selected diagonal/unstructured/pooled covariance model.
.gt_gaussian_validate_start <- function(start, outcomes, component_names) {
  if (is.null(start)) return(NULL)
  if (!is.list(start) || is.null(names(start)) || anyNA(names(start)) ||
      any(!nzchar(names(start))) || anyDuplicated(names(start)) ||
      !setequal(names(start), component_names))
    stop("Gaussian start must be a uniquely named list with exactly one covariance matrix for every resolved model component, including Residual: ",
         paste(component_names, collapse = ", "), ".", call. = FALSE)
  start <- start[component_names]
  for (component in component_names) {
    M <- start[[component]]
    if (!is.matrix(M) || !is.numeric(M) ||
        !identical(dim(M), rep.int(length(outcomes), 2L)) || any(!is.finite(M)))
      stop("Gaussian start for ", component,
           " must be a finite numeric covariance matrix with one row and column per outcome.",
           call. = FALSE)
    rows <- rownames(M)
    columns <- colnames(M)
    if (!is.null(rows) || !is.null(columns)) {
      valid_names <- function(labels) !is.null(labels) && !anyNA(labels) &&
        all(nzchar(labels)) && !anyDuplicated(labels) && setequal(labels, outcomes)
      if (!valid_names(rows) || !valid_names(columns))
        stop("Gaussian start matrix labels for ", component,
             " must name both axes with every outcome exactly once; use fully unnamed axes for positional input.",
             call. = FALSE)
      M <- M[outcomes, outcomes, drop = FALSE]
    }
    start[[component]] <- M
  }
  start
}

# Fit Gaussian source covariance matrices for a balanced general G design
#
# The object name and number and names of instrumentation facets are arbitrary.
# Every selected grouping term contributes one source-specific outcome covariance
# matrix. Univariate fitting is the one-outcome case of this same joint engine.
#
# This first backend requires the complete Cartesian panel of the coded object
# and facet levels, with one observation per cell and no missing outcomes. A
# declared nested group is a parent-scoped grouping term in that panel. Physical
# nesting with disjoint globally unique child labels, unbalanced panels, and
# within-cell replication require another preparation backend and are rejected.
#
# ML profiles the fixed outcome means. REML includes D*log(N), matching the
# unscaled fixed-intercept convention in lme4. ML AIC includes profiled means;
# ML BIC uses N response vectors, with an explicit N*D alternative. Legacy
# variance-only criteria remain named separately. Generic AIC/BIC are unavailable
# for REML; explicitly named restricted-likelihood criteria preserve the archive.
#
# covariance: One of unstructured/diagonal or named source overrides.
#   With named overrides, unspecified sources use diagonal covariance.
# residual: One of unstructured, diagonal, or pooled (equal trait variance).
# Returns: A list containing source covariance matrices, outcome means, exact
#   likelihood, stationarity and boundary diagnostics, and the fitted OpenMx model.
.gt_fit_gaussian <- function(data, outcomes, design, estimator = "REML",
                             covariance = "unstructured", residual = "unstructured",
                             control = list()) {
  if (!inherits(design, "gt_design")) stop("design must be created by gt_design().", call. = FALSE)
  design <- .gt_resolve_design(data, design, "gaussian")
  variables <- c(design$object, design$facets)
  if (length(variables) < 2L || anyNA(variables) || anyDuplicated(variables) ||
      any(!nzchar(variables))) stop("Invalid object/facet specification.", call. = FALSE)
  if (!identical(design$replicates, 1L))
    stop("The Gaussian contrast backend currently requires one observation per full cell; within-cell replication is not yet supported.", call. = FALSE)
  # Exact factorial contrasts have 2^(Nfacets+1) strata. This explicit resource
  # guard avoids integer overflow and an accidental exponential allocation.
  if (length(variables) > 12L)
    stop("This exact balanced Gaussian backend is limited to 4096 factorial strata (object plus at most 11 facets). Reduce the design or use a future sparse backend.", call. = FALSE)
  if (!is.character(estimator) || length(estimator) != 1L || is.na(estimator) ||
      !estimator %in% c("ML", "REML")) stop("Gaussian estimator must be ML or REML.", call. = FALSE)
  control <- .gt_gaussian_validate_control(control)
  if (!exists(".gt_gaussian_engine", mode = "function", inherits = TRUE))
    stop("Source R/gaussian_engine.R before fitting Gaussian models.", call. = FALSE)
  engine <- .gt_gaussian_engine(variables)
  facets <- stats::setNames(variables, variables)
  # Prepare once before model construction so unsupported sampling structures
  # produce a specific data error before OpenMx is invoked.
  preparation_limit <- if (is.null(control$max_preparation_bytes)) 512 * 1024^2 else control$max_preparation_bytes
  prepared <- engine$prepare(data, outcomes, facets, max_preparation_bytes = preparation_limit)
  if (!is.null(control$start))
    control$start <- .gt_gaussian_validate_start(control$start, outcomes,
                                               c(design$terms, "Residual"))
  result <- do.call(engine$fit, c(list(data = data, outcomes = outcomes,
    facets = facets, spec = design$terms, reml = estimator == "REML",
    covariance = covariance, residual = residual, prepared = prepared), control))
  checked_design <- .gt_design_validated(design,
    "Complete Cartesian coded panel, one observation per full cell; declared parent-scoped grouping terms. Physical nesting not inferred.")
  checked_design$observed_counts <- prepared$counts
  result$design <- checked_design
  result$family <- stats::setNames(lapply(outcomes, function(x)
    list(name = "gaussian", link = "identity")), outcomes)
  result$estimator <- estimator
  result$backend <- "OpenMx exact balanced Gaussian factorial contrasts"
  result$backend_fit <- result$model
  result$source <- "Balanced Gaussian source-covariance likelihood using OpenMx."
  result$prepared <- prepared
  result$likelihood_convention <- list(
    fixed_effects = "One profiled fixed intercept per outcome", reml_intercept_constant = "D * log(N)",
    information_criteria_parameters = if (estimator == "ML") "Variance/covariance parameters plus profiled means" else
      "Generic AIC/BIC unavailable; named REML conventions use covariance parameters",
    information_criteria_nobs = "ML BIC uses N response vectors; N*D alternative and archive conventions are explicitly named",
    legacy_information_criteria = "legacy_AIC/legacy_BIC exclude profiled means; legacy_BIC uses N*D")
  result
}
