# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Structural and resource checks without optimization or dense model matrices.

# Inspect an observed design before fitting
gt_preflight <- function(data, outcomes, design, family = gt_family("gaussian"),
                         covariance = "unstructured", residual = NULL,
                         control = gt_control()) {
  if (!inherits(design, "gt_design")) stop("Use gt_design() to declare the design.", call. = FALSE)
  if (!is.data.frame(data) || !nrow(data) || anyDuplicated(names(data)))
    stop("data must be a nonempty data frame with unique column names.", call. = FALSE)
  outcomes <- .gt_design_names(outcomes, "outcomes")
  variables <- c(design$object, design$facets)
  if (length(intersect(outcomes, variables))) stop("Outcome and design columns must differ.", call. = FALSE)
  if (!all(c(variables, outcomes) %in% names(data))) stop("Missing outcome or design columns.", call. = FALSE)
  if (!inherits(control, "gt_control")) stop("control must be created by gt_control().", call. = FALSE)
  for (v in variables) {
    x <- data[[v]]
    if (!is.atomic(x) || anyNA(x) || (is.numeric(x) && any(!is.finite(x))) ||
        length(unique(x)) < 2L)
      stop("Each design variable needs at least two finite, nonmissing levels: ", v, ".", call. = FALSE)
  }
  resolved <- .gt_resolve_families(data[c(variables, outcomes)], outcomes, family)
  families <- resolved$families
  kinds <- vapply(families, `[[`, character(1), "family")
  gaussian <- all(kinds == "gaussian")
  if (any(kinds == "gaussian") && !gaussian)
    stop("Joint Gaussian-discrete outcomes are not supported by the current engines.", call. = FALSE)

  checks <- data.frame(check = character(), passed = logical(), detail = character(),
                       stringsAsFactors = FALSE)
  add_check <- function(name, passed, detail) {
    checks <<- rbind(checks, data.frame(check = name, passed = passed,
                                       detail = detail, stringsAsFactors = FALSE))
  }
  n <- nrow(data)
  counts <- vapply(data[variables], function(x) length(unique(x)), integer(1))
  cell_counts <- table(.gt_tuple_key(data, variables))
  expected_cells <- prod(as.double(counts))
  complete <- length(cell_counts) == expected_cells
  replicated <- all(cell_counts == design$replicates)
  add_check("declared_replication", replicated,
            "Every observed full cell must have the declared number of measurements.")
  design_error <- NULL
  checked <- tryCatch(.gt_resolve_design(resolved$data, design,
    if (gaussian) "gaussian" else "discrete"), error = function(e) {
      design_error <<- conditionMessage(e)
      NULL
    })
  add_check("family_design_resolution", !is.null(checked),
            if (is.null(design_error)) "Family-specific source resolution succeeded." else design_error)
  # Keep requested source counts available even when fitting is blocked.
  reporting_design <- if (is.null(checked)) design else checked
  terms <- reporting_design$term_members
  groups <- lapply(terms, function(members) .gt_d_group(data, members))
  levels <- vapply(groups, `[[`, integer(1), "nlevels")
  q <- if (gaussian) length(outcomes) else sum(vapply(families, function(f)
    if (f$family == "categorical") length(f$levels) - 1L else 1L, integer(1)))
  location_parameters <- if (gaussian) length(outcomes) else sum(vapply(families, function(f)
    if (f$family == "binary") 1L else length(f$levels) - 1L, integer(1)))
  random_dimension <- sum(as.double(levels)) * q
  add_check("repeated_source_groups", all(levels >= 2L),
            "Every retained source needs at least two observed groups.")
  covariance_parameters <- numeric(length(terms))
  names(covariance_parameters) <- names(terms)
  residual_parameters <- 0
  resources <- list()
  kernel_check <- "not_applicable"
  if (gaussian) {
    .gt_gaussian_validate_control(control$gaussian)
    if (is.null(residual)) residual <- "unstructured"
    .gt_validate_residual_request(residual)
    component_names <- c(names(terms), "Residual")
    .gt_validate_covariance_request(covariance, names(terms))
    types <- if (is.null(names(covariance)))
      stats::setNames(rep(covariance, length(component_names)), component_names) else {
        overridden <- stats::setNames(rep("diagonal", length(component_names)), component_names)
        overridden[names(covariance)] <- covariance
        overridden
      }
    types[["Residual"]] <- residual
    parameter_count <- function(type) switch(type, diagonal = q,
      unstructured = q * (q + 1) / 2, pooled = 1)
    covariance_parameters[] <- vapply(types[names(terms)], parameter_count, numeric(1))
    residual_parameters <- parameter_count(residual)
    add_check("complete_coded_panel", complete,
              "Gaussian fitting requires the complete Cartesian product of observed coded levels.")
    add_check("one_row_per_cell", design$replicates == 1L,
              "The Gaussian backend currently supports one measurement per full cell.")
    add_check("factorial_strata_limit", length(variables) <= 12L,
              "The exact Gaussian backend supports at most 4096 strata (12 axes including the object).")
    limit <- control$gaussian$max_preparation_bytes
    if (is.null(limit)) limit <- 512 * 1024^2
    if (!is.numeric(limit) || length(limit) != 1L || !is.finite(limit) || limit <= 0)
      stop("max_preparation_bytes must be a positive finite number of bytes.", call. = FALSE)
    bytes <- .gt_gaussian_preparation_bytes(expected_cells, q, length(variables))
    add_check("preparation_resource_limit", bytes <= limit,
              "The Gaussian preparation estimate must fit the configured allocation limit.")
    resources <- list(preparation_estimated_bytes = bytes, preparation_limit_bytes = limit,
      factorial_strata = 2^length(variables),
      scope = "Preparation working arrays only; excludes caller data and downstream OpenMx objects.")
  } else {
    if (!is.null(residual)) stop("Do not specify a Gaussian residual covariance for discrete outcomes.", call. = FALSE)
    dc <- .gt_d_control(control$discrete)
    .gt_d_validate_covariance_request(covariance)
    covariance_parameters[] <- if (!is.null(dc$fixed_covariance)) 0 else
      if (covariance == "diagonal") q else q * (q + 1) / 2
    add_check("repeated_observations_within_source", all(levels < n),
              "Observation-specific random sources are unsupported for discrete outcomes.")
    add_check("observation_limit", n <= dc$max_observations,
              paste("Measurement rows must not exceed", dc$max_observations))
    add_check("random_dimension_limit", random_dimension <= dc$max_random_dimension,
              paste("Dense random-effect dimensions must not exceed", dc$max_random_dimension))
    add_check("parameter_limit", location_parameters + sum(covariance_parameters) <= dc$max_parameters,
              paste("Free observation and covariance parameters must not exceed", dc$max_parameters))
    dense <- .gt_d_dense_bytes(n, q, random_dimension)
    add_check("dense_memory_limit", dense$total <= dc$max_dense_bytes,
              paste("Estimated dense working memory", .gt_d_format_bytes(dense$total),
                    "must not exceed max_dense_bytes", .gt_d_format_bytes(dc$max_dense_bytes)))
    # Reuse fitting's covariance/kernel checks only within its size limits.
    # No random-design matrix, Hessian, likelihood or optimizer is constructed.
    if (all(checks$passed)) {
      setup_error <- NULL
      setup <- tryCatch({
        prep <- .gt_d_prepare(resolved$data, outcomes, families)
        .gt_d_covariance_setup(groups, prep$q, covariance, dc, prep$dimensions)
      }, error = function(e) {
        setup_error <<- conditionMessage(e)
        NULL
      })
      add_check("covariance_specification", !is.null(setup),
                if (is.null(setup_error)) "Covariance setup succeeded." else setup_error)
      if (!is.null(setup) && is.null(setup$fixed)) {
        rank <- .gt_d_kernel_rank(groups)
        augmented <- .gt_d_kernel_rank(c(unname(groups), list(
          list(index = seq_len(n), nlevels = n))))
        add_check("source_kernel_independence", rank$rank == rank$n_sources,
                  "Observed source kernels must be linearly independent under the current free-covariance guard.")
        add_check("source_residual_separation", augmented$rank == augmented$n_sources,
                  "Free source kernels must not span the observation identity under the current discrete guard.")
        kernel_check <- "checked"
      } else kernel_check <- if (is.null(setup)) "skipped_invalid_covariance" else "not_required_for_fixed_covariance"
    } else kernel_check <- "skipped_after_structural_or_resource_failure"
    resources <- list(dense_matrix_bytes_lower_bound =
      8 * (as.double(n) * q * random_dimension + random_dimension^2),
      dense_working_bytes_estimate = dense$total,
      dense_working_bytes_breakdown = dense[c("random_design", "conditional_hessian",
        "block_slices", "predictors", "multiplier")],
      max_dense_bytes = dc$max_dense_bytes,
      max_observations = dc$max_observations,
      max_random_dimension = dc$max_random_dimension, max_parameters = dc$max_parameters,
      scope = paste("Planning estimates for one dense likelihood evaluation, checked",
        "before allocation. Not peak resident memory and not a runtime prediction."))
  }
  sources <- data.frame(source = names(terms), observed_groups = unname(levels),
    predictor_dimensions = q, random_dimension = unname(as.double(levels) * q),
    covariance_parameters = unname(covariance_parameters), stringsAsFactors = FALSE)
  balanced <- complete && replicated
  scales <- if (!balanced || any(kinds == "categorical")) character() else
    if (gaussian) "observed" else "latent"
  notes <- c("Preflight checks structure and configured size limits. It does not establish identification, approximation adequacy, fit acceptance, or scientific validity.",
    "A supported reliability scale is conditional on a numerically accepted fit and the stated averaging design.",
    "Starting values and all optimizer-specific controls are validated during fitting.")
  if (any(levels < 5L)) notes <- c(notes,
    "Some sources have fewer than five observed groups. This is a descriptive caution about limited information, not a rejection rule.")
  if (!balanced) notes <- c(notes,
    "Analytic reliability and D studies require a complete balanced coded panel even when discrete fitting permits missing whole cells.")
  if (any(kinds == "categorical")) notes <- c(notes,
    "Unordered categorical outcomes have no implemented scalar G/Phi; category contrasts are not separate measured outcomes.")
  structure(list(call = match.call(), outcomes = outcomes, families = families,
    engine = if (gaussian) "exact_balanced_gaussian" else "dense_joint_discrete_laplace",
    observations = n, observed_counts = counts, observed_cells = length(cell_counts),
    expected_cells = expected_cells, observed_replication = sort(unique(as.integer(cell_counts))),
    complete_balanced_panel = balanced, sources = sources,
    source_counts = c(requested = length(design$terms_requested), retained = length(terms)),
    aliased_terms = if (is.null(checked)) character() else checked$aliased_terms,
    random_dimension = random_dimension, predictor_dimensions = q,
    parameters = c(observation = location_parameters, source_covariance = sum(covariance_parameters),
      residual_covariance = residual_parameters,
      total = location_parameters + sum(covariance_parameters) + residual_parameters),
    checks = checks, fitting_feasible = all(checks$passed), resources = resources,
    kernel_check = kernel_check, supported_reliability_scales = scales,
    scale_interpretation = if (length(scales) == 0L) "No implemented analytic scalar coefficient for this family/panel combination." else
      if (gaussian) "Reliability of observed Gaussian-score averages." else
        "Reliability of latent-response averages; not label proportions, majority votes, or ordinal-score averages.",
    notes = notes), class = "gt_preflight")
}

print.gt_preflight <- function(x, ...) {
  cat("G-theory preflight:", x$observations, "rows |", x$engine, "\n")
  cat("Observed levels:", paste(paste(names(x$observed_counts), x$observed_counts, sep = "="), collapse = ", "), "\n")
  cat("Retained random sources:", x$source_counts[["retained"]],
      "| Random dimensions:", x$random_dimension,
      "| Model parameters:", x$parameters[["total"]], "\n")
  cat("Structural/resource checks:", if (x$fitting_feasible) "PASS" else "BLOCKED", "\n")
  if (!x$fitting_feasible) print(x$checks[!x$checks$passed, , drop = FALSE], row.names = FALSE)
  cat("Supported reliability scale:", if (length(x$supported_reliability_scales))
    paste(x$supported_reliability_scales, collapse = ", ") else "none", "\n")
  cat(x$scale_interpretation, "\n")
  cat(x$notes[[1L]], "\n")
  invisible(x)
}
