# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Analytic observed Gaussian and identified latent binary/ordinal coefficients.

# Declare explicit weights for a composite on an already specified score scale
gt_score <- function(weights) {
  if (!is.numeric(weights) || !length(weights) || any(!is.finite(weights)) ||
      is.null(names(weights)) || anyNA(names(weights)) || any(!nzchar(names(weights))) ||
      anyDuplicated(names(weights)) || !any(weights != 0))
    stop("weights must be a finite, uniquely named vector with at least one nonzero entry.", call. = FALSE)
  structure(list(weights = weights, normalization = "as_supplied"), class = "gt_score")
}

.gt_reliability_context <- function(fit, scale) {
  if (!inherits(fit, "gt_fit")) stop("Expected a gt_fit object.", call. = FALSE)
  if (isFALSE(fit$converged) || isFALSE(fit$numerically_accepted) ||
      (!is.null(fit$engine) && identical(fit$engine, "dense_joint_discrete_laplace") &&
       !isTRUE(fit$numerically_accepted)))
    stop("Reliability and D studies require a numerically converged fit. Inspect gt_diagnostics(fit) and resolve the fitting failure first.", call. = FALSE)
  types <- vapply(fit$families, `[[`, character(1), "family")
  gaussian <- all(types == "gaussian")
  if (is.null(scale)) {
    if (!gaussian) stop("For binary/ordinal fits, explicitly request scale='latent'; observed-score coefficients need a separate integration method.", call. = FALSE)
    scale <- "observed"
  }
  if (!is.character(scale) || length(scale) != 1L || is.na(scale)) stop("Specify one coefficient scale.", call. = FALSE)
  if (any(types == "categorical"))
    stop("Unordered categorical outcomes have no default scalar G/Phi. Define a substantive score or category-probability estimand before computing reliability; this is not implemented yet.", call. = FALSE)
  if ((gaussian && scale != "observed") || (!gaussian && scale != "latent"))
    stop("This implementation supports observed Gaussian coefficients and identified latent binary/ordinal coefficients only.", call. = FALSE)
  dimensions <- c(fit$design$object, fit$design$facets)
  counts <- stats::setNames(vapply(fit$data[dimensions], function(x) length(unique(x)), integer(1)), dimensions)
  if (nrow(fit$data) != prod(counts) * fit$design$replicates)
    stop("Analytic coefficients currently require a complete balanced coded panel; unbalanced allocations need separate D-study integration.", call. = FALSE)
  cell_counts <- table(.gt_tuple_key(fit$data, dimensions))
  if (any(cell_counts != fit$design$replicates))
    stop("Analytic coefficients require the declared equal within-cell replication.", call. = FALSE)
  components <- fit$covariance_components
  if (!gaussian) {
    latent_variance <- vapply(fit$families, function(f)
      if (f$link == "probit") 1 else pi^2 / 3, numeric(1))
    components$Residual <- diag(latent_variance, nrow = length(latent_variance))
    dimnames(components$Residual) <- list(fit$outcomes, fit$outcomes)
  }
  expected <- c(fit$design$terms, "Residual")
  if (!all(expected %in% names(components))) stop("Missing fitted covariance components.", call. = FALSE)
  if (any(vapply(components[expected], function(x)
    !is.matrix(x) || !identical(dim(x), c(length(fit$outcomes), length(fit$outcomes))) || any(!is.finite(x)), logical(1))))
    stop("Source covariance dimensions do not match the outcome dimensions.", call. = FALSE)
  list(components = components, counts = counts[fit$design$facets], scale = scale,
       gaussian = gaussian, replicates = fit$design$replicates,
       uncertainty = .gt_coefficient_uncertainty_source(fit, gaussian))
}

# Only a fitted Gaussian source covariance carries a usable curvature-based
# covariance matrix. A latent discrete scale additionally holds its residual
# variance fixed by the link, which is not an estimated quantity at all.
.gt_coefficient_uncertainty_source <- function(fit, gaussian) {
  unavailable <- function(reason) list(available = FALSE, reason = reason,
    entries = NULL, entry_covariance = NULL, method = NA_character_,
    boundary_components = character(), restricted_to_interior = FALSE,
    fixed_components = character())
  if (!gaussian)
    return(unavailable("Standard errors are not implemented for the discrete Laplace engine; its coefficients are point estimates only."))
  record <- fit$uncertainty
  if (!is.list(record) || !isTRUE(record$available))
    return(unavailable(if (is.list(record) && length(record$reason) && !is.na(record$reason))
      record$reason else "No parameter covariance matrix is available for this fit."))
  if (is.null(record$entries) || is.null(record$entry_covariance))
    return(unavailable("The fit does not carry a source-covariance delta-method mapping."))
  list(available = TRUE, reason = NA_character_, entries = record$entries,
       entry_covariance = record$entry_covariance, method = record$method,
       boundary_components = record$boundary_components,
       restricted_to_interior = isTRUE(record$restricted_to_interior),
       fixed_components = record$fixed_components)
}

.gt_reliability_fixed <- function(fit, fixed, counts, observed) {
  if (is.null(fixed)) fixed <- character()
  if (!is.character(fixed) || anyNA(fixed) || any(!nzchar(fixed)) || anyDuplicated(fixed))
    stop("fixed must be a character vector of unique, nonempty instrumentation facet names.", call. = FALSE)
  if (!length(fixed)) return(character())
  unknown <- setdiff(fixed, fit$design$facets)
  if (length(unknown))
    stop("fixed must name declared instrumentation facets; unknown facet(s): ",
         paste(unknown, collapse = ", "), ".", call. = FALSE)
  if (setequal(fixed, fit$design$facets))
    stop("At least one facet must remain random. With every facet fixed there is no facet-sampling error to generalize over, and this design provides no estimable error variance.", call. = FALSE)
  mismatched <- fixed[counts[fixed] != observed[fixed]]
  if (length(mismatched))
    stop("A fixed facet's universe is exactly its observed levels, so its count cannot be changed: ",
         paste(paste0(mismatched, " (observed ", observed[mismatched], ", requested ",
                      counts[mismatched], ")"), collapse = ", "), ".", call. = FALSE)
  fit$design$facets[fit$design$facets %in% fixed]
}

# Brennan (2001) mixed-model decomposition. With every facet random this
# reduces exactly to the fully random weights. For a fixed facet h:
# object-by-fixed terms are averaged over its n_h levels and enter the
# universe score; terms with no object and no random facet shift every object
# equally and leave the model; every other term keeps its usual divisor.
.gt_reliability_weights <- function(fit, counts, replicates, fixed) {
  object <- fit$design$object
  terms <- fit$design$terms
  members <- fit$design$term_members
  labels <- c(terms, "Residual")
  zero <- stats::setNames(numeric(length(labels)), labels)
  universe <- relative <- absolute <- zero
  roles <- stats::setNames(rep("unused", length(labels)), labels)
  universe[[object]] <- 1
  roles[[object]] <- "universe"
  residual_divisor <- prod(counts) * replicates
  relative[["Residual"]] <- absolute[["Residual"]] <- 1 / residual_divisor
  roles[["Residual"]] <- "relative_and_absolute_error"
  for (term in setdiff(terms, object)) {
    facets_in <- setdiff(members[[term]], object)
    divisor <- prod(counts[facets_in])
    random_in <- setdiff(facets_in, fixed)
    if (object %in% members[[term]]) {
      if (length(random_in)) {
        relative[[term]] <- absolute[[term]] <- 1 / divisor
        roles[[term]] <- "relative_and_absolute_error"
      } else {
        universe[[term]] <- 1 / divisor
        roles[[term]] <- "universe_after_fixed_facet_averaging"
      }
    } else if (length(random_in)) {
      absolute[[term]] <- 1 / divisor
      roles[[term]] <- "absolute_error"
    } else {
      roles[[term]] <- "dropped_fixed_instrumentation_constant"
    }
  }
  list(universe = universe, relative = relative, absolute = absolute, roles = roles)
}

# Compute G and Phi under a declared balanced score design
# scale: observed for Gaussian; explicitly latent for binary/ordinal.
# score: Optional gt_score object; per-trait results are always returned.
# design: Optional named positive integer instrumentation counts.
#   Retained as an alias for counts for compatibility.
# counts: Optional named positive integer instrumentation counts.
# fixed: Instrumentation facets treated as fixed rather than randomly
#   sampled. Defaults to none, reproducing the fully random model.
# level: Confidence level for the reported coefficient intervals.
gt_reliability <- function(fit, scale = NULL, score = NULL, design = NULL,
                           counts = NULL, fixed = character(), level = 0.95) {
  if (!is.null(design) && !is.null(counts))
    stop("Supply counts or its compatibility alias design, not both.", call. = FALSE)
  if (!is.null(counts)) design <- counts
  .gt_check_level(level)
  context <- .gt_reliability_context(fit, scale)
  counts <- context$counts
  if (!is.null(design)) {
    if (!is.numeric(design) || is.null(names(design)) || anyNA(names(design)) ||
        anyDuplicated(names(design)) || any(!names(design) %in% names(counts)) ||
        any(!is.finite(design)) || any(design < 1 | design != floor(design)))
      stop("design must contain named positive integer counts of declared instrumentation facets.", call. = FALSE)
    counts[names(design)] <- design
  }
  fixed <- .gt_reliability_fixed(fit, fixed, counts, context$counts)
  .gt_reliability_kernel(fit, context, counts, score, fixed, level)
}

.gt_check_level <- function(level) {
  if (!is.numeric(level) || length(level) != 1L || is.na(level) || !is.finite(level) ||
      level <= 0 || level >= 1)
    stop("level must be one number strictly between 0 and 1.", call. = FALSE)
  invisible(level)
}

# Derivative of a ratio of nonnegative variance aggregates, mapped onto the
# unique source covariance entries the fit's parameter covariance describes.
# Returns NA rather than a number whenever the curvature record is missing.
.gt_coefficient_standard_error <- function(context, fit, weight, universe_weights,
                                           error_weights, universe, error) {
  record <- context$uncertainty
  total <- universe + error
  if (!isTRUE(record$available) || !is.finite(total) || total <= 0) return(NA_real_)
  entries <- record$entries
  row_position <- match(entries$row, fit$outcomes)
  column_position <- match(entries$column, fit$outcomes)
  if (anyNA(row_position) || anyNA(column_position)) return(NA_real_)
  sources <- names(universe_weights)
  if (any(!entries$component %in% sources)) return(NA_real_)
  per_source <- (universe_weights[entries$component] * error -
                 universe * error_weights[entries$component]) / total^2
  multiplier <- ifelse(row_position == column_position, 1, 2)
  gradient <- as.numeric(per_source) * weight[row_position] * weight[column_position] * multiplier
  variance <- drop(crossprod(gradient, record$entry_covariance %*% gradient))
  if (!is.finite(variance) || variance < 0) return(NA_real_)
  sqrt(variance)
}

# Wald interval on the logit scale so a coefficient interval stays inside the
# (0, 1) range the coefficient itself occupies. A point estimate exactly at a
# boundary has no such interval and is reported as NA, not as 0 or 1.
.gt_coefficient_interval <- function(value, standard_error, level) {
  z <- stats::qnorm(1 - (1 - level) / 2)
  lower <- upper <- rep(NA_real_, length(value))
  usable <- is.finite(value) & is.finite(standard_error) & standard_error > 0 &
    value > 0 & value < 1
  if (any(usable)) {
    eta <- log(value[usable] / (1 - value[usable]))
    spread <- z * standard_error[usable] / (value[usable] * (1 - value[usable]))
    lower[usable] <- stats::plogis(eta - spread)
    upper[usable] <- stats::plogis(eta + spread)
  }
  list(lower = lower, upper = upper)
}

# Context is validated once per D study, independently of grid size.
.gt_reliability_kernel <- function(fit, context, counts, score, fixed = character(),
                                   level = 0.95) {
  matrices <- context$components
  weights <- .gt_reliability_weights(fit, counts, context$replicates, fixed)
  combine <- function(w) Reduce(`+`, Map(function(a, M) a * M, w, matrices[names(w)]))
  universe <- combine(weights$universe)
  relative <- combine(weights$relative)
  absolute <- combine(weights$absolute)
  ratio <- function(u, e) ifelse(is.finite(u + e) & u + e > 0, u / (u + e), NA_real_)
  coefficient <- function(weight, error_matrix, error_weights) {
    u <- as.numeric(crossprod(weight, universe %*% weight))
    e <- as.numeric(crossprod(weight, error_matrix %*% weight))
    value <- ratio(u, e)
    standard_error <- .gt_coefficient_standard_error(context, fit, weight,
      weights$universe, error_weights, u, e)
    interval <- .gt_coefficient_interval(value, standard_error, level)
    c(value = value, se = standard_error, lower = interval$lower, upper = interval$upper)
  }
  unit <- function(j) {
    w <- numeric(length(fit$outcomes))
    w[[j]] <- 1
    w
  }
  relative_rows <- vapply(seq_along(fit$outcomes),
    function(j) coefficient(unit(j), relative, weights$relative), numeric(4L))
  absolute_rows <- vapply(seq_along(fit$outcomes),
    function(j) coefficient(unit(j), absolute, weights$absolute), numeric(4L))
  per_trait <- data.frame(outcome = fit$outcomes,
    Erho2 = relative_rows["value", ], Erho2_se = relative_rows["se", ],
    Erho2_lower = relative_rows["lower", ], Erho2_upper = relative_rows["upper", ],
    Phi = absolute_rows["value", ], Phi_se = absolute_rows["se", ],
    Phi_lower = absolute_rows["lower", ], Phi_upper = absolute_rows["upper", ],
    stringsAsFactors = FALSE)
  composite <- NULL
  if (!is.null(score)) {
    if (!inherits(score, "gt_score") || !setequal(names(score$weights), fit$outcomes))
      stop("score must explicitly weight every outcome exactly once.", call. = FALSE)
    w <- as.numeric(score$weights[fit$outcomes])
    relative_composite <- coefficient(w, relative, weights$relative)
    absolute_composite <- coefficient(w, absolute, weights$absolute)
    composite <- data.frame(
      Erho2 = relative_composite[["value"]], Erho2_se = relative_composite[["se"]],
      Erho2_lower = relative_composite[["lower"]], Erho2_upper = relative_composite[["upper"]],
      Phi = absolute_composite[["value"]], Phi_se = absolute_composite[["se"]],
      Phi_lower = absolute_composite[["lower"]], Phi_upper = absolute_composite[["upper"]],
      row.names = NULL)
  }
  rownames(per_trait) <- NULL
  structure(list(per_trait = per_trait, composite = composite,
       universe_covariance = universe, relative_error_covariance = relative,
       absolute_error_covariance = absolute, scale = context$scale, score = score,
       design = counts, replicates = context$replicates, fixed_facets = fixed,
       random_facets = setdiff(names(counts), fixed),
       source_roles = weights$roles, source_weights = weights[c("universe", "relative", "absolute")],
       level = level, uncertainty = context$uncertainty,
       extrapolated = any(counts > context$counts),
       model = if (length(fixed)) "mixed (Brennan 2001): object-by-fixed-facet variance enters the universe score" else
         "fully random facets",
       interpretation = if (context$gaussian) "Gaussian observed-score coefficient" else
         "Identified latent-response coefficient; not reliability of binary proportions or ordinal observed scores",
       fit_diagnostics = gt_diagnostics(fit)), class = "gt_reliability")
}

# Evaluate balanced allocations using the analytic coefficient definitions
gt_dstudy <- function(fit, grid, scale = NULL, score = NULL, fixed = character(),
                      level = 0.95) {
  .gt_check_level(level)
  context <- .gt_reliability_context(fit, scale)
  if (!is.data.frame(grid) || !nrow(grid) || !ncol(grid) || anyDuplicated(names(grid)) ||
      any(!names(grid) %in% names(context$counts)) ||
      !all(vapply(grid, is.numeric, logical(1))))
    stop("grid must be a nonempty numeric data frame of declared instrumentation facet counts.", call. = FALSE)
  values <- as.matrix(grid)
  if (any(!is.finite(values)) || any(values < 1 | values != floor(values)))
    stop("D-study counts must be positive finite integers.", call. = FALSE)
  allocation <- as.data.frame(as.list(context$counts), check.names = FALSE)[rep(1L, nrow(grid)), , drop = FALSE]
  rownames(allocation) <- NULL
  allocation[names(grid)] <- grid
  fixed <- .gt_reliability_fixed(fit, fixed, context$counts, context$counts)
  varied <- intersect(names(grid), fixed)
  if (length(varied))
    stop("A decision study cannot project over a fixed facet's population; remove ",
         paste(varied, collapse = ", "), " from grid or from fixed.", call. = FALSE)
  result <- lapply(seq_len(nrow(grid)), function(i) {
    co <- .gt_reliability_kernel(fit, context,
      unlist(allocation[i, , drop = FALSE], use.names = TRUE), score, fixed, level)
    table <- data.frame(design_id = i, kind = "outcome", co$per_trait, stringsAsFactors = FALSE)
    if (!is.null(co$composite)) table <- rbind(table,
      data.frame(design_id = i, kind = "composite", outcome = "composite", co$composite))
    table
  })
  results <- do.call(rbind, result)
  rownames(results) <- NULL
  structure(list(allocations = allocation, results = results,
                 scale = context$scale, score = score, level = level,
                 fixed_facets = fixed, uncertainty = context$uncertainty,
                 measurements_per_object = apply(allocation, 1L, prod) * context$replicates,
                 extrapolated = apply(allocation, 1L, function(x) any(x > context$counts)),
                 fit_diagnostics = gt_diagnostics(fit)), class = "gt_dstudy")
}

.gt_print_coefficient_options <- function(digits, max_rows) {
  if (!is.numeric(digits) || length(digits) != 1L || is.na(digits) ||
      !is.finite(digits) || digits < 1 || digits > 22 || digits != floor(digits))
    stop("digits must be one integer from 1 to 22.", call. = FALSE)
  if (!is.numeric(max_rows) || length(max_rows) != 1L || is.na(max_rows) ||
      !is.finite(max_rows) || max_rows < 1 || max_rows != floor(max_rows))
    stop("max_rows must be one positive integer.", call. = FALSE)
}

# Hide interval columns that carry no information for this fit rather than
# printing a block of NA that reads as a computed result.
.gt_drop_empty_columns <- function(table) {
  keep <- vapply(table, function(column) !is.numeric(column) || any(is.finite(column)), logical(1))
  table[, keep, drop = FALSE]
}

# Name a handful of sources inline; past that a count and a pointer stay
# readable. A caveat nobody finishes reading is not a caveat.
.gt_name_sources <- function(sources, field, limit = 3L) {
  if (length(sources) <= limit) return(paste(sources, collapse = ", "))
  paste0(length(sources), " sources (see $uncertainty$", field, ")")
}

.gt_print_uncertainty_note <- function(x) {
  record <- x$uncertainty
  if (!is.list(record)) return(invisible(NULL))
  if (isTRUE(record$available)) {
    cat(format(100 * x$level, digits = 4), "% intervals: delta method on the logit scale from the fitted parameter covariance.\n", sep = "")
    if (isTRUE(record$restricted_to_interior))
      cat("Conditional on", .gt_name_sources(record$fixed_components, "fixed_components"),
          "held at zero; the intervals carry no uncertainty for those.\n")
    else if (length(record$boundary_components))
      cat("No standard error for", .gt_name_sources(record$boundary_components, "boundary_components"),
          "resting on a variance boundary.\n")
  } else if (length(record$reason) && !is.na(record$reason)) {
    cat("No intervals:", record$reason, "\n")
  }
  invisible(NULL)
}

# Print a concise reliability report without expanding fit diagnostics
print.gt_reliability <- function(x, ..., digits = 4L, max_rows = 12L) {
  .gt_print_coefficient_options(digits, max_rows)
  cat("G-theory reliability |", x$scale, "scale\n")
  cat("Facet counts:", paste(paste(names(x$design), x$design, sep = "="), collapse = ", "), "\n")
  if (length(x$fixed_facets))
    cat("Fixed facets:", paste(x$fixed_facets, collapse = ", "), "|", x$model, "\n")
  print(.gt_drop_empty_columns(utils::head(x$per_trait, max_rows)), row.names = FALSE, digits = digits)
  if (nrow(x$per_trait) > max_rows) cat("Further outcomes are available in $per_trait.\n")
  if (!is.null(x$composite)) {
    cat("Weighted composite:\n")
    print(.gt_drop_empty_columns(x$composite), row.names = FALSE, digits = digits)
  }
  cat("Erho2: relative comparisons; Phi: absolute decisions.\n")
  .gt_print_uncertainty_note(x)
  if (identical(x$scale, "latent")) cat("Latent-response coefficients; not observed-score reliability.\n")
  if (isTRUE(x$extrapolated)) cat("Allocation exceeds fitted counts; source covariances are held fixed.\n")
  cat("Full covariance matrices and fit diagnostics remain in the returned object.\n")
  invisible(x)
}

# Print allocations and coefficients without expanding fit diagnostics
print.gt_dstudy <- function(x, ..., digits = 4L, max_rows = 12L) {
  .gt_print_coefficient_options(digits, max_rows)
  cat("G-theory decision study |", nrow(x$allocations), "allocations |", x$scale, "scale\n")
  if (length(x$fixed_facets)) cat("Fixed facets:", paste(x$fixed_facets, collapse = ", "), "\n")
  shown <- utils::head(x$results, max_rows)
  allocation <- x$allocations[shown$design_id, , drop = FALSE]
  # Format facets in one column so arbitrary facet names cannot overwrite
  # result columns such as outcome or Phi.
  allocation_text <- vapply(seq_len(nrow(allocation)), function(i)
    paste(paste(names(allocation), unlist(allocation[i, ], use.names = FALSE), sep = "="), collapse = ", "), character(1))
  shown <- .gt_drop_empty_columns(shown)
  shown$allocation <- allocation_text
  print(shown, row.names = FALSE, digits = digits)
  if (nrow(x$results) > max_rows) cat("Showing", max_rows, "of", nrow(x$results), "rows; see $results and $allocations.\n")
  cat("Erho2: relative comparisons; Phi: absolute decisions. Point projections.\n")
  .gt_print_uncertainty_note(x)
  if (identical(x$scale, "latent")) cat("Latent-response coefficients; not observed-score reliability.\n")
  if (any(x$extrapolated)) cat(sum(x$extrapolated), "allocations exceed fitted counts; source covariances are held fixed.\n")
  invisible(x)
}

plot.gt_dstudy <- function(x, coefficient = "Erho2", interval = TRUE, ...) {
  if (!coefficient %in% c("Erho2", "Phi")) stop("coefficient must be Erho2 or Phi.")
  if (!is.logical(interval) || length(interval) != 1L || is.na(interval))
    stop("interval must be TRUE or FALSE.")
  tab <- x$results
  series <- interaction(tab$kind, tab$outcome, drop = TRUE)
  colors <- seq_len(nlevels(series))
  xx <- x$measurements_per_object[tab$design_id]
  lower <- tab[[paste0(coefficient, "_lower")]]
  upper <- tab[[paste0(coefficient, "_upper")]]
  drawn <- interval && !is.null(lower) && any(is.finite(lower) & is.finite(upper))
  limits <- if (drawn) range(c(tab[[coefficient]], lower, upper), na.rm = TRUE) else
    range(tab[[coefficient]], na.rm = TRUE)
  graphics::plot(xx, tab[[coefficient]], col = colors[series], pch = 19, ylim = limits,
                 xlab = "Measurements per object", ylab = paste(coefficient, "-", x$scale, "scale"), ...)
  if (drawn) graphics::segments(xx, lower, xx, upper, col = colors[series])
  graphics::legend("bottomright", legend = levels(series), col = colors, pch = 19, bty = "n")
  invisible(x)
}
