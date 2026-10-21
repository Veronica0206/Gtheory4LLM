# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Public dispatch is provided by gt_fit(); this file owns the Gaussian backend.

# One definition of the Gaussian covariance and residual requests, so that
# gt_preflight() and gt_fit() accept and reject exactly the same arguments.
# A named override names a random source: the residual structure is chosen with
# the residual argument, and accepting it in both places would mean silently
# ignoring one of them.
.gt_gaussian_covariance_choices <- c("diagonal", "unstructured")
.gt_gaussian_residual_choices <- c("unstructured", "diagonal", "pooled")

.gt_validate_covariance_request <- function(covariance, sources) {
  if (!is.character(covariance) || !length(covariance) || anyNA(covariance) ||
      any(!covariance %in% .gt_gaussian_covariance_choices))
    stop("covariance must specify diagonal or unstructured.", call. = FALSE)
  if (is.null(names(covariance))) {
    if (length(covariance) != 1L)
      stop("Multiple covariance types must be named.", call. = FALSE)
    return(invisible(covariance))
  }
  if (anyNA(names(covariance)) || any(!nzchar(names(covariance))) ||
      anyDuplicated(names(covariance)))
    stop("Named covariance overrides must be uniquely named.", call. = FALSE)
  if ("Residual" %in% names(covariance))
    stop("The residual covariance structure is chosen with the residual argument, not with a named covariance override.", call. = FALSE)
  unknown <- setdiff(names(covariance), sources)
  if (length(unknown))
    stop("Named covariance overrides must refer to retained random sources; unknown: ",
         paste(unknown, collapse = ", "), ".", call. = FALSE)
  invisible(covariance)
}

.gt_validate_residual_request <- function(residual) {
  if (!is.character(residual) || length(residual) != 1L || is.na(residual) ||
      !residual %in% .gt_gaussian_residual_choices)
    stop("residual must be unstructured, diagonal, or pooled.", call. = FALSE)
  invisible(residual)
}

.gt_gaussian_validate_control <- function(control) {
  allowed <- c("engine", "start", "optimizer", "max_iterations", "tolerance", "check_hessian",
               "threads", "silent", "extra_tries", "retry_seed", "max_preparation_bytes",
               "panel", "max_observed_rows")
  if (!is.list(control) || (length(control) && (is.null(names(control)) ||
      anyNA(names(control)) || any(!nzchar(names(control))) || anyDuplicated(names(control)))))
    stop("Gaussian control must be a uniquely named list.", call. = FALSE)
  unknown <- setdiff(names(control), allowed)
  if (length(unknown)) stop("Unsupported Gaussian control setting(s): ",
                           paste(unknown, collapse = ", "), call. = FALSE)
  if (!is.null(control$engine) && (!is.character(control$engine) || length(control$engine) != 1L ||
      is.na(control$engine) || !control$engine %in% c("openmx", "lme4")))
    stop("engine must be 'openmx' (the exact balanced likelihood, the default) or 'lme4'.", call. = FALSE)
  if (!is.null(control$panel) && (!is.character(control$panel) || length(control$panel) != 1L ||
      is.na(control$panel) || !control$panel %in% c("complete", "observed")))
    stop("Gaussian panel must be 'complete' (the default) or 'observed'.", call. = FALSE)
  if (identical(control$panel, "observed") && !identical(control$engine, "lme4"))
    stop("Gaussian panel = 'observed' requires engine = 'lme4'.", call. = FALSE)
  if (!is.null(control$max_observed_rows) && !identical(control$panel, "observed"))
    stop("max_observed_rows applies only to Gaussian panel = 'observed'.", call. = FALSE)
  if (!is.null(control$max_observed_rows) && (!is.numeric(control$max_observed_rows) ||
      length(control$max_observed_rows) != 1L || !is.finite(control$max_observed_rows) ||
      control$max_observed_rows < 2 || control$max_observed_rows != floor(control$max_observed_rows)))
    stop("max_observed_rows must be one finite integer of at least two.", call. = FALSE)
  # The exact engine's optimizer settings have no meaning for lme4, and a
  # setting that is accepted and ignored is worse than one that is refused.
  if (identical(control$engine, "lme4")) {
    foreign <- intersect(names(control), .GT_LME4_ONLY_EXACT)
    if (length(foreign))
      stop("Gaussian control setting(s) ", paste(foreign, collapse = ", "),
           " apply to the exact engine only; the lme4 engine uses lme4's own optimizer and computes no Hessian.", call. = FALSE)
  }
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

# Fit Gaussian source covariances for complete or explicitly observed-row panels
#
# The object name and number and names of instrumentation facets are arbitrary.
# Every selected grouping term contributes one source-specific outcome covariance
# matrix. Univariate fitting is the one-outcome case of this same joint engine.
#
# The default backend requires the complete Cartesian panel of coded levels,
# with one observation per cell and no missing outcomes. A declared nested group
# is parent-scoped. The explicit univariate observed-row lme4 option uses a
# separately bounded covariance preparation and checks identification on the
# retained rows. Neither route imputes cells or supports within-cell replication.
#
# ML profiles the fixed outcome means. REML includes D*log(N), matching the
# unscaled fixed-intercept convention in lme4. ML AIC includes profiled means;
# ML BIC uses N response vectors, with an explicit N*D alternative. Legacy
# variance-only criteria remain named separately. For REML the AIC/BIC elements
# are NA; AIC() and BIC() use the restricted likelihood, and every convention has
# an explicit restricted-likelihood name.
#
# covariance: One of unstructured/diagonal or named source overrides.
#   With named overrides, unspecified sources use diagonal covariance.
# residual: One of unstructured, diagonal, or pooled (equal trait variance).
# call: NULL, or what .gt_batch_model() found for a declared batch: whether it
#   can be modelled, and if so the batch and slot of every row.
# Returns: A list containing source covariance matrices, outcome means, exact
#   likelihood, stationarity and boundary diagnostics, and the fitted OpenMx model.
.gt_fit_gaussian <- function(data, outcomes, design, estimator = "REML",
                             covariance = "unstructured", residual = "unstructured",
                             control = list(), call = NULL) {
  if (!inherits(design, "gt_design")) stop("design must be created by gt_design().", call. = FALSE)
  design <- .gt_resolve_design(data, design, "gaussian")
  variables <- c(design$object, design$facets)
  if (length(variables) < 2L || anyNA(variables) || anyDuplicated(variables) ||
      any(!nzchar(variables))) stop("Invalid object/facet specification.", call. = FALSE)
  if (!identical(design$replicates, 1L))
    stop("The Gaussian contrast backend currently requires one observation per full cell; within-cell replication is not yet supported.", call. = FALSE)
  # Exact factorial contrasts have 2^(Nfacets+1) strata. This explicit resource
  # guard avoids integer overflow and an accidental exponential allocation.
  # A declared batch that forms a complete factorial with the facets is
  # modelled: the object becomes a batch-by-slot cell, which is one more axis,
  # and the call, a batch under one condition, becomes a source. gt_fit()
  # resolves the batches from the data as supplied, where the columns a
  # declaration names are still present, and passes the result as call.
  modelled <- isTRUE(call$modelled)
  axes <- variables
  spec <- design$terms
  if (modelled) {
    if (.GT_CALL_TERM %in% design$terms)
      stop("A source named ", .GT_CALL_TERM, " cannot be combined with a modelled batch; rename that variable.", call. = FALSE)
    columns <- utils::tail(make.unique(c(names(data), ".gt_batch", ".gt_slot")), 2L)
    data[[columns[[1L]]]] <- call$batch
    data[[columns[[2L]]]] <- call$slot
    axes <- c(columns, design$facets)
    spec <- c(design$terms, .GT_CALL_TERM)
  }
  if (length(axes) > 12L && !identical(control$panel, "observed"))
    stop("This exact balanced Gaussian backend is limited to 4096 factorial strata (object plus at most 11 facets", if (modelled) ", or 10 with a modelled batch" else "", "). Reduce the design or use a future sparse backend.", call. = FALSE)
  if (!is.character(estimator) || length(estimator) != 1L || is.na(estimator) ||
      !estimator %in% c("ML", "REML")) stop("Gaussian estimator must be ML or REML.", call. = FALSE)
  control <- .gt_gaussian_validate_control(control)
  observed <- identical(control$panel, "observed")
  if (!exists(".gt_gaussian_engine", mode = "function", inherits = TRUE))
    stop("Source R/gaussian_engine.R before fitting Gaussian models.", call. = FALSE)
  engine <- if (observed) list(deviance = .gt_gaussian_observed_deviance,
    correlation = .gt_covariance_correlation) else if (modelled) .gt_gaussian_engine(variables,
    call = list(batch = columns[[1L]], slot = columns[[2L]], term = .GT_CALL_TERM)) else
    .gt_gaussian_engine(variables)
  facets <- stats::setNames(axes, axes)
  # Prepare once before model construction so unsupported sampling structures
  # produce a specific data error before OpenMx is invoked.
  preparation_limit <- if (is.null(control$max_preparation_bytes)) 512 * 1024^2 else control$max_preparation_bytes
  prepared <- if (observed) {
    row_limit <- if (is.null(control$max_observed_rows)) 1000L else control$max_observed_rows
    .gt_gaussian_observed_prepare(data, outcomes, design, row_limit, preparation_limit)
  } else engine$prepare(data, outcomes, facets, max_preparation_bytes = preparation_limit)
  if (!is.null(control$start))
    control$start <- .gt_gaussian_validate_start(control$start, outcomes,
                                               c(spec, "Residual"))
  result <- if (identical(control$engine, "lme4"))
    .gt_fit_gaussian_lme4(data, outcomes, facets, spec, estimator == "REML", covariance, residual,
      prepared, engine, control,
      call = if (modelled) list(term = .GT_CALL_TERM, batch_column = columns[[1L]]) else NULL)
  else do.call(engine$fit, c(list(data = data, outcomes = outcomes,
    facets = facets, spec = spec, reml = estimator == "REML",
    covariance = covariance, residual = residual, prepared = prepared),
    control[setdiff(names(control), c("engine", "panel", "max_observed_rows"))]))
  checked_design <- .gt_design_validated(design, if (observed)
    "Observed rows only, one observation per retained cell; source and residual covariance kernels checked for independence after removing the intercept. No cells imputed; missingness assumptions are not tested."
    else "Complete Cartesian coded panel, one observation per full cell; declared parent-scoped grouping terms. Physical nesting not inferred.")
  if (observed) checked_design$panel_type <- "observed"
  # Counts are reported for the design variables. With a modelled batch the
  # engine's axes split the object in two, so its count is their product.
  checked_design$observed_counts <- if (modelled)
    c(stats::setNames(call$batches * call$size, design$object), prepared$counts[design$facets]) else prepared$counts
  if (!is.null(call)) checked_design$batch_model <- call[setdiff(names(call), c("batch", "slot"))]
  if (modelled) {
    # Fixed-layout projections need the original item-to-batch membership even
    # when observation retention is disabled. Keep one record per item, not the
    # observation-level call identifiers or outcomes. Reports omit this map.
    item_levels <- unique(data[[design$object]])
    first_item_rows <- match(item_levels, data[[design$object]])
    checked_design$batch_model$item_levels <- item_levels
    checked_design$batch_model$item_batches <- unname(call$batch[first_item_rows])
  }
  result$design <- checked_design
  result$family <- stats::setNames(lapply(outcomes, function(x)
    list(name = "gaussian", link = "identity")), outcomes)
  result$estimator <- estimator
  if (identical(control$engine, "lme4")) {
    result$backend <- if (observed)
      "lme4 random-intercept sources, checked against the dense observed-row Gaussian deviance" else
      "lme4 random-intercept sources, checked against the exact balanced deviance"
    result$source <- if (observed)
      "Gaussian source variances maximized by lme4::lmer; the independent observed-row likelihood is evaluated at the estimates." else
      "Gaussian source variances maximized by lme4::lmer; the exact balanced likelihood is evaluated at the estimates."
  } else {
    result$backend <- "OpenMx exact balanced Gaussian factorial contrasts"
    result$engine <- "exact_balanced_gaussian"
    result$source <- "Balanced Gaussian source-covariance likelihood using OpenMx."
  }
  result$backend_fit <- result$model
  # Raw outcomes and covariance kernels are needed only during this reference
  # check. Keep its bounded resource and identification record, not a second
  # observation copy outside the public retention controls.
  result$prepared <- if (observed) prepared[setdiff(names(prepared), c("y", "kernels"))] else prepared
  if (observed) result$projection <- list(required = TRUE, target = "intended_complete_balanced",
    assumptions = c("Missing whole cells are ignorable for the declared Gaussian model.",
      "The intended balanced allocation samples the same facet universes and variance sources.",
      "A projected coefficient does not describe reliability of the incomplete observed allocation."))
  result$likelihood_convention <- list(
    fixed_effects = "One profiled fixed intercept per outcome", reml_intercept_constant = if (observed)
      "log(det(X' V^-1 X)) for the unscaled fixed intercept on observed rows" else "D * log(N)",
    information_criteria_parameters = if (estimator == "ML") "Variance/covariance parameters plus profiled means" else
      "AIC() and BIC() use the restricted likelihood with covariance parameters only; the named REML conventions record N and N*D",
    information_criteria_nobs = "ML BIC uses N response vectors; N*D alternative and archive conventions are explicitly named",
    legacy_information_criteria = "legacy_AIC/legacy_BIC exclude profiled means; legacy_BIC uses N*D")
  result
}
