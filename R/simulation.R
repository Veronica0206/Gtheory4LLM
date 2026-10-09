# Model-based Gaussian simulation and bounded pilot precision experiments.
# These functions do not calibrate confidence intervals or perform a bootstrap.

.gt_sim_integer <- function(x, name, minimum = 1L, maximum = .Machine$integer.max) {
  if (!is.numeric(x) || is.complex(x) || length(x) != 1L || !is.finite(x) ||
      x != floor(x) || x < minimum || x > maximum)
    stop(name, " must be one integer from ", minimum, " to ", maximum, ".", call. = FALSE)
  as.integer(x)
}

.gt_sim_rng <- function(seed, expression) {
  seed <- .gt_sim_integer(seed, "seed", 0L)
  kind <- RNGkind()
  existed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  previous <- if (existed) get(".Random.seed", envir = .GlobalEnv, inherits = FALSE) else NULL
  on.exit({
    do.call(RNGkind, as.list(kind))
    if (existed) assign(".Random.seed", previous, envir = .GlobalEnv)
    else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
      rm(".Random.seed", envir = .GlobalEnv)
  }, add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(seed)
  force(expression)
}

.gt_sim_model <- function(fit, components, means) {
  if (!inherits(fit, "gt_fit")) stop("Expected a gt_fit object.", call. = FALSE)
  if (!isTRUE(fit$numerically_accepted) || !isTRUE(fit$converged))
    stop("Simulation requires an explicitly numerically accepted fit.", call. = FALSE)
  if (!length(fit$families) || any(vapply(fit$families, `[[`, character(1), "family") != "gaussian"))
    stop("Simulation currently supports Gaussian outcomes only.", call. = FALSE)
  if (!is.null(fit$design$batch))
    stop("Simulation does not yet support declared or modelled batches.", call. = FALSE)
  if (!identical(fit$design$replicates, 1L))
    stop("Simulation requires one observation per complete coded cell.", call. = FALSE)
  dimensions <- c(fit$design$object, fit$design$facets)
  panel <- .gt_reliability_panel(fit, dimensions)
  if (panel$rows != prod(panel$counts) || any(panel$cell_replication != 1L))
    stop("Simulation requires a complete balanced fitted panel.", call. = FALSE)
  sources <- c(fit$design$terms, "Residual")
  types <- fit$covariance_types
  if (!is.character(types) || is.null(names(types)) || anyDuplicated(names(types)) ||
      !setequal(names(types), sources) || anyNA(types) ||
      any(!types %in% c("diagonal", "unstructured", "pooled")) ||
      any(types[fit$design$terms] == "pooled"))
    stop("The fit must retain its resolved covariance structures.", call. = FALSE)
  scenario <- !is.null(components) || !is.null(means)
  if (is.null(components)) components <- fit$covariance_components
  components <- .gt_gaussian_validate_start(components, fit$outcomes, sources)
  roots <- stats::setNames(vector("list", length(sources)), sources)
  for (source in sources) {
    value <- components[[source]]
    tolerance <- 1e-10 * max(1, max(abs(value)))
    if (max(abs(value - t(value))) > tolerance)
      stop("Simulation covariance must be symmetric: ", source, ".", call. = FALSE)
    value <- (value + t(value)) / 2
    if (types[[source]] %in% c("diagonal", "pooled") &&
        any(abs(value[row(value) != col(value)]) > tolerance))
      stop("Simulation covariance must preserve the fitted diagonal structure: ", source, ".", call. = FALSE)
    if (types[[source]] == "pooled" && max(abs(diag(value) - mean(diag(value)))) > tolerance)
      stop("Simulation covariance must preserve the fitted pooled residual structure.", call. = FALSE)
    decomposition <- eigen(value, symmetric = TRUE)
    if (any(!is.finite(decomposition$values)))
      stop("Simulation covariance exceeds floating-point range: ", source, ".", call. = FALSE)
    if (min(decomposition$values) < -tolerance)
      stop("Simulation covariance must be positive semidefinite: ", source, ".", call. = FALSE)
    # Only roundoff-level negative eigenvalues are set to zero; zero sources
    # and singular positive semidefinite sources need no interior jitter.
    root <- decomposition$vectors %*% diag(sqrt(pmax(0, decomposition$values)), nrow(value))
    roots[[source]] <- root
    components[[source]] <- tcrossprod(root)
    if (any(!is.finite(components[[source]])))
      stop("Simulation covariance exceeds floating-point range: ", source, ".", call. = FALSE)
    dimnames(components[[source]]) <- list(fit$outcomes, fit$outcomes)
  }
  if (is.null(means)) means <- fit$means
  if (!is.numeric(means) || is.complex(means) || length(means) != length(fit$outcomes) ||
      any(!is.finite(means)) || is.null(names(means)) || anyNA(names(means)) ||
      anyDuplicated(names(means)) || !setequal(names(means), fit$outcomes))
    stop("means must be a finite numeric vector naming every outcome exactly once.", call. = FALSE)
  list(design = fit$design, outcomes = fit$outcomes, counts = panel$counts,
       components = components, roots = roots, means = means[fit$outcomes],
       covariance_types = types[sources],
       parameter_source = if (scenario) "specified_parameter_scenario" else "fitted_model_plugin")
}

.gt_sim_allocation <- function(model, n_items, counts, max_rows) {
  n_items <- .gt_sim_integer(n_items, "n_items", 2L)
  max_rows <- .gt_sim_integer(max_rows, "max_rows", 1L, 1000000L)
  allocation <- model$counts
  allocation[[model$design$object]] <- n_items
  if (!is.null(counts)) {
    if (!is.numeric(counts) || is.complex(counts) || !length(counts) || is.null(names(counts)) ||
        anyNA(names(counts)) || anyDuplicated(names(counts)) ||
        any(!names(counts) %in% model$design$facets) || any(!is.finite(counts)) ||
        any(counts < 2 | counts != floor(counts) | counts > .Machine$integer.max))
      stop("counts must uniquely name declared facets with integer counts of at least two.", call. = FALSE)
    allocation[names(counts)] <- counts
  }
  rows <- prod(as.double(allocation))
  if (!is.finite(rows) || rows > max_rows)
    stop("Simulation rows exceed max_rows; reduce the proposed allocation.", call. = FALSE)
  groups <- sum(vapply(model$design$term_members, function(members)
    prod(as.double(allocation[members])), numeric(1))) + rows
  dimensions <- length(model$outcomes)
  bytes <- 8 * (rows * (2 * length(allocation) + 4 * dimensions) +
    groups * dimensions + 4 * dimensions^2)
  if (!is.finite(bytes) || bytes > 512 * 1024^2)
    stop("Estimated simulation workspace exceeds the 512 MiB limit.", call. = FALSE)
  allocation
}

.gt_sim_draw <- function(model, allocation) {
  values <- lapply(unname(allocation), seq_len)
  # Positional inputs avoid collisions with expand.grid's formal arguments.
  panel <- expand.grid(values, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  names(panel) <- names(allocation)
  responses <- matrix(rep(model$means, each = nrow(panel)), nrow(panel), length(model$outcomes))
  for (source in names(model$components)) {
    group <- if (source == "Residual") seq_len(nrow(panel)) else {
      keys <- .gt_tuple_key(panel, model$design$term_members[[source]])
      match(keys, unique(keys))
    }
    levels <- max(group)
    effects <- matrix(stats::rnorm(levels * length(model$outcomes)), levels, length(model$outcomes))
    effects <- effects %*% t(model$roots[[source]])
    responses <- responses + effects[group, , drop = FALSE]
  }
  for (i in seq_along(model$outcomes)) panel[[model$outcomes[[i]]]] <- responses[, i]
  panel
}

# Each call draws new objects and new levels for every instrumentation facet.
# Nothing conditions on estimated random-effect realizations from the pilot.
gt_simulate <- function(fit, n_items, counts = NULL, seed, components = NULL,
                        means = NULL, max_rows = 1000000L) {
  model <- .gt_sim_model(fit, components, means)
  allocation <- .gt_sim_allocation(model, n_items, counts, max_rows)
  result <- .gt_sim_rng(seed, .gt_sim_draw(model, allocation))
  attr(result, "simulation") <- list(
    purpose = "design_simulation", parameter_source = model$parameter_source,
    seed = as.integer(seed), n_items = allocation[[model$design$object]],
    counts = allocation[model$design$facets], means = model$means,
    components = model$components, covariance_types = model$covariance_types, design = model$design,
    interpretation = paste("Independent Gaussian random effects for new items and all facet levels;",
      "complete balanced coded panel. This generates a parameter scenario, not calibrated bootstrap inference."))
  result
}

.gt_pilot_record <- function(design_id, replicate_id, seed) {
  data.frame(design_id = design_id, replicate_id = replicate_id, seed = seed, retry_seed = NA_integer_,
    status = "not_started", phase = "simulation", accepted = FALSE,
    interval_available = FALSE, interval_conditional = NA, boundary_fit = NA,
    estimate = NA_real_, lower = NA_real_, upper = NA_real_, width = NA_real_,
    meets_width = NA, reason = NA_character_, warnings = NA_character_, stringsAsFactors = FALSE)
}

.gt_pilot_summary <- function(records, allocations, width_target) {
  rate <- function(success, denominator) if (denominator) success / denominator else NA_real_
  mcse <- function(p, denominator) if (denominator) sqrt(p * (1 - p) / denominator) else NA_real_
  rows <- lapply(seq_len(nrow(allocations)), function(id) {
    x <- records[records$design_id == id, , drop = FALSE]
    total <- nrow(x)
    accepted <- sum(x$accepted)
    available <- sum(x$interval_available)
    widths <- x$width[x$interval_available]
    acceptance_rate <- rate(accepted, total)
    interval_rate <- rate(available, total)
    refusals <- sum(x$status == "numerically_refused")
    errors <- sum(x$status %in% c("simulation_error", "fit_error", "reliability_error"))
    refusal_rate <- rate(refusals, total)
    error_rate <- rate(errors, total)
    precision <- if (is.null(width_target)) NA_integer_ else sum(x$meets_width %in% TRUE)
    precision_rate <- if (is.null(width_target)) NA_real_ else rate(precision, total)
    data.frame(design_id = id, attempted = total, accepted = accepted,
      preparation_or_fit_errors = sum(x$status == "fit_error"),
      simulation_errors = sum(x$status == "simulation_error"),
      refused = refusals,
      reliability_errors = sum(x$status == "reliability_error"),
      interval_available = available, interval_unavailable = sum(x$status == "interval_unavailable"),
      conditional_intervals = sum(x$interval_available & x$interval_conditional %in% TRUE),
      acceptance_rate = acceptance_rate, acceptance_mcse = mcse(acceptance_rate, total),
      refusal_rate = refusal_rate, refusal_mcse = mcse(refusal_rate, total),
      error_rate = error_rate, error_mcse = mcse(error_rate, total),
      interval_rate = interval_rate, interval_mcse = mcse(interval_rate, total),
      mean_width_given_interval = if (available) mean(widths) else NA_real_,
      mean_width_mcse_given_interval = if (available > 1L) stats::sd(widths) / sqrt(available) else NA_real_,
      width_target = if (is.null(width_target)) NA_real_ else width_target,
      precision_successes = precision, precision_success_rate = precision_rate,
      precision_success_mcse = mcse(precision_rate, total),
      precision_rate_given_interval = if (is.null(width_target)) NA_real_ else rate(precision, available),
      precision_mcse_given_interval = if (is.null(width_target)) NA_real_ else
        mcse(rate(precision, available), available),
      stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# Every planned refit has one row, including preparation errors and refusals.
# Interval precision is a plug-in operating characteristic under this scenario;
# neither interval coverage nor boundary calibration is asserted.
gt_pilot_plan <- function(fit, grid, nsim, seed, coefficient = "Erho2", outcome = NULL,
                          score = NULL, kind = "outcome", width_target = NULL, level = 0.95,
                          target_counts = NULL,
                          components = NULL, means = NULL, control = fit$control,
                          max_rows = 1000000L) {
  model <- .gt_sim_model(fit, components, means)
  .gt_check_coefficient(coefficient)
  .gt_check_level(level)
  if (!is.character(kind) || length(kind) != 1L || is.na(kind) ||
      !kind %in% c("outcome", "composite"))
    stop("kind must be outcome or composite.", call. = FALSE)
  nsim <- .gt_sim_integer(nsim, "nsim", 1L, 10000L)
  seed <- .gt_sim_integer(seed, "seed", 0L)
  if ("n_items" %in% fit$design$facets)
    stop("Pilot grid reserves n_items for the number of distinct objects; rename this facet first.", call. = FALSE)
  if (!is.data.frame(grid) || !nrow(grid) || !"n_items" %in% names(grid) ||
      anyDuplicated(names(grid)) || any(!names(grid) %in% c("n_items", fit$design$facets)) ||
      !all(vapply(grid, function(x) is.numeric(x) && !is.complex(x), logical(1))))
    stop("grid must be a nonempty numeric data frame with n_items and optional declared facet counts.", call. = FALSE)
  if (nrow(grid) > 100L || nrow(grid) * nsim > 10000L)
    stop("Pilot planning is limited to 100 candidate designs and 10000 total refits.", call. = FALSE)
  if (!inherits(control, "gt_control")) stop("control must be created by gt_control().", call. = FALSE)
  .gt_gaussian_validate_control(control$gaussian)
  if (!is.null(control$gaussian$retry_seed))
    .gt_sim_integer(control$gaussian$retry_seed, "control$gaussian$retry_seed", 0L)
  if (!is.character(fit$estimator) || length(fit$estimator) != 1L ||
      !fit$estimator %in% c("ML", "REML")) stop("The fit must retain its Gaussian estimator.", call. = FALSE)
  if (!is.null(width_target) && (!is.numeric(width_target) || is.complex(width_target) ||
      length(width_target) != 1L || !is.finite(width_target) || width_target <= 0 || width_target > 1))
    stop("width_target must be NULL or one finite number in (0, 1].", call. = FALSE)
  # Validate coefficient selection before starting a potentially long experiment.
  target <- gt_reliability(fit, score = score, design = target_counts, level = level)
  target_counts <- target$design
  selection <- .gt_reporting_select(as.data.frame(target),
    outcome, kind, single = TRUE)
  if (nrow(selection) != 1L) stop("Select exactly one outcome or composite coefficient.", call. = FALSE)
  allocations <- lapply(seq_len(nrow(grid)), function(i) {
    facets <- setdiff(names(grid), "n_items")
    counts <- if (length(facets)) unlist(grid[i, facets, drop = FALSE], use.names = TRUE) else NULL
    .gt_sim_allocation(model, grid$n_items[[i]], counts, max_rows)
  })
  allocation_table <- do.call(rbind, lapply(allocations, function(x) {
    row <- as.data.frame(as.list(x), check.names = FALSE)
    names(row)[1L] <- "n_items"
    row
  }))
  rownames(allocation_table) <- NULL
  covariance <- model$covariance_types[fit$design$terms]
  residual <- unname(model$covariance_types[["Residual"]])
  records <- .gt_sim_rng(seed, {
    total <- nrow(grid) * nsim
    seeds <- sample.int(.Machine$integer.max, total * 2L, replace = FALSE)
    rows <- vector("list", total)
    index <- 0L
    for (design_id in seq_len(nrow(grid))) for (replicate_id in seq_len(nsim)) {
      index <- index + 1L
      record <- .gt_pilot_record(design_id, replicate_id, seeds[[index]])
      refit_control <- control
      if (is.null(refit_control$gaussian$retry_seed))
        refit_control$gaussian$retry_seed <- seeds[[total + index]]
      record$retry_seed <- as.integer(refit_control$gaussian$retry_seed)
      warnings <- character()
      record <- withCallingHandlers(tryCatch({
        data <- .gt_sim_rng(seeds[[index]], .gt_sim_draw(model, allocations[[design_id]]))
        record$phase <- "preparation_or_fit"
        refit <- .gt_sim_rng(record$retry_seed,
          gt_fit(data, fit$outcomes, fit$design, family = gt_family("gaussian"),
            estimator = fit$estimator, covariance = covariance, residual = residual, control = refit_control))
        record$accepted <- isTRUE(refit$numerically_accepted) && isTRUE(refit$converged)
        record$boundary_fit <- length(refit$uncertainty$boundary_components) > 0L
        if (!record$accepted) {
          record$status <- "numerically_refused"
          record$reason <- "Refit failed numerical acceptance; no coefficient was extracted."
        } else {
          record$phase <- "reliability"
          reliability <- gt_reliability(refit, score = score, design = target_counts, level = level)
          selected <- .gt_reporting_select(as.data.frame(reliability), selection$outcome,
            selection$kind, single = TRUE)
          record$estimate <- selected[[coefficient]]
          record$lower <- selected[[paste0(coefficient, "_lower")]]
          record$upper <- selected[[paste0(coefficient, "_upper")]]
          record$interval_available <- is.finite(record$estimate) && is.finite(record$lower) &&
            is.finite(record$upper) && record$upper >= record$lower
          record$interval_conditional <- isTRUE(reliability$uncertainty$restricted_to_interior)
          if (record$interval_available) {
            record$width <- record$upper - record$lower
            record$meets_width <- if (is.null(width_target)) NA else record$width <= width_target
            record$status <- "interval_available"
          } else {
            record$status <- "interval_unavailable"
            reason <- reliability$uncertainty$reason
            record$reason <- if (length(reason) == 1L && !is.na(reason) && nzchar(reason))
              reason else "The coefficient has no finite interval."
          }
        }
        record
      }, error = function(error) {
        record$status <- switch(record$phase, simulation = "simulation_error",
          preparation_or_fit = "fit_error", reliability = "reliability_error")
        record$reason <- conditionMessage(error)
        record
      }), warning = function(warning) {
        warnings <<- c(warnings, conditionMessage(warning))
        invokeRestart("muffleWarning")
      })
      if (length(warnings)) record$warnings <- paste(unique(warnings), collapse = " | ")
      rows[[index]] <- record
    }
    do.call(rbind, rows)
  })
  list(allocations = allocation_table, replicates = records,
    summary = .gt_pilot_summary(records, allocation_table, width_target),
    scenario = list(parameter_source = model$parameter_source, components = model$components,
      means = model$means, covariance_types = model$covariance_types, estimator = fit$estimator,
      design = model$design,
      coefficient = coefficient, outcome = selection$outcome, kind = selection$kind,
      score = score, level = level, target_counts = target_counts,
      seed = seed, nsim = nsim, control = control),
    interpretation = paste("Design simulation with new items and newly sampled levels of every random facet.",
      "Each pilot estimates the same fully random target protocol given by target_counts.",
      "Rates use every attempted replicate; mean widths condition on an available interval.",
      "Precision success requires an available interval meeting width_target, so failures are non-successes.",
      "Conditional intervals remain labelled; their widths do not validate boundary coverage.",
      "These are model-based plug-in operating characteristics, not calibrated coverage or bootstrap inference."))
}
