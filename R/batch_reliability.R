# Fixed-layout Gaussian score projections. No observation covariance is formed.
# Public documentation and exports are maintained manually in man/ and NAMESPACE.

.gt_batch_projection_context <- function(fit, counts) {
  if (!inherits(fit, "gt_fit")) stop("Expected a gt_fit object.", call. = FALSE)
  if (!isTRUE(fit$numerically_accepted) || !isTRUE(fit$converged))
    stop("Batch projections require a numerically accepted fit.", call. = FALSE)
  families <- vapply(fit$families, `[[`, character(1), "family")
  if (!length(families) || any(families != "gaussian"))
    stop("Batch projections currently support Gaussian outcomes only.", call. = FALSE)
  if (!identical(.gt_batch_status(fit$design)$status, "modelled"))
    stop("Batch projections require a fitted shared Call effect for equal fixed batches.", call. = FALSE)
  status <- .gt_batch_status(fit$design)
  if (length(status$not_modelled))
    stop("Batch projections do not support additional unmodelled batch patterns; refit with the shared-call declaration only.", call. = FALSE)
  dimensions <- c(fit$design$object, fit$design$facets)
  panel <- .gt_reliability_panel(fit, dimensions)
  if (!identical(fit$design$replicates, 1L) || panel$rows != prod(panel$counts) ||
      any(panel$cell_replication != 1L))
    stop("Batch projections require the complete balanced panel with one observation per cell.", call. = FALSE)
  model <- fit$design$batch_model
  items <- as.character(model$item_levels)
  batch <- model$item_batches
  if (!length(items) || is.null(batch))
    stop("This fit has no recorded item-to-batch layout. Refit with the current version; the layout cannot be guessed.",
         call. = FALSE)
  if (length(items) != panel$counts[[fit$design$object]] || anyNA(items) ||
      any(!nzchar(items)) || anyDuplicated(items) || length(batch) != length(items) || anyNA(batch))
    stop("The recorded item-to-batch layout has missing, ambiguous, or inconsistent item identifiers.", call. = FALSE)
  batch <- match(batch, unique(batch))
  if (max(batch) != model$batches || any(tabulate(batch) != model$size))
    stop("The recorded layout does not match the fitted equal batch sizes.", call. = FALSE)
  if (is.data.frame(fit$data) && !setequal(as.character(fit$data[[fit$design$object]]), items))
    stop("The retained data and recorded item layout disagree.", call. = FALSE)
  observed <- panel$counts[fit$design$facets]
  planned <- observed
  if (!is.null(counts)) {
    if (!is.numeric(counts) || is.null(names(counts)) || anyNA(names(counts)) ||
        anyDuplicated(names(counts)) || any(!names(counts) %in% names(observed)) ||
        any(!is.finite(counts)) || any(counts < 1 | counts != floor(counts)))
      stop("counts must contain named positive integer instrumentation counts; batch size and item count cannot change.",
           call. = FALSE)
    planned[names(counts)] <- counts
  }
  if (!is.finite(prod(planned)) || prod(planned) * model$batches >= 2^53)
    stop("Planned annotations per item and total calls must be below 2^53 for exact integer accounting.", call. = FALSE)
  sources <- c(fit$design$terms, .GT_CALL_TERM, "Residual")
  components <- fit$covariance_components[sources]
  D <- length(fit$outcomes)
  for (M in components) {
    if (!is.matrix(M) || !is.numeric(M) || !identical(dim(M), c(D, D)) || any(!is.finite(M)))
      stop("Source covariance dimensions do not match the outcome dimensions.", call. = FALSE)
    tolerance <- 1e-10 * max(1, max(abs(M)))
    if (max(abs(M - t(M))) > tolerance || min(eigen(M, symmetric = TRUE, only.values = TRUE)$values) < -tolerance)
      stop("Source covariances must be symmetric positive semidefinite matrices.", call. = FALSE)
  }
  object <- fit$design$object
  kernel <- role <- stats::setNames(character(length(sources)), sources)
  divisor <- stats::setNames(numeric(length(sources)), sources)
  for (s in sources) {
    if (s %in% c(.GT_CALL_TERM, "Residual")) {
      kernel[[s]] <- if (s == .GT_CALL_TERM) "same_batch" else "same_item"
      divisor[[s]] <- prod(planned)
    } else {
      members <- fit$design$term_members[[s]]
      kernel[[s]] <- if (object %in% members) "same_item" else "all_items"
      divisor[[s]] <- prod(planned[setdiff(members, object)])
    }
    role[[s]] <- if (s == object) "universe" else "error"
  }
  list(items = items, batch = batch, counts = planned, observed = observed, components = components,
       kernel = kernel, divisor = divisor, role = role, status = status)
}

# Parse sparse item weights. Lists permit several targets without an item-square
# identity matrix; item IDs, not positions, determine every supplied weight.
.gt_batch_projection_targets <- function(value, items, kind) {
  if (is.null(value)) return(list())
  if (is.numeric(value)) value <- stats::setNames(list(value), kind)
  if (!is.list(value) || !length(value) || is.null(names(value)) || anyNA(names(value)) ||
      any(!nzchar(names(value))) || anyDuplicated(names(value)))
    stop(kind, " must be a named numeric item-weight vector or a named list of such vectors.", call. = FALSE)
  lapply(seq_along(value), function(i) {
    weight <- value[[i]]
    if (!is.numeric(weight) || !length(weight) || any(!is.finite(weight)) ||
        is.null(names(weight)) || anyNA(names(weight)) || any(!names(weight) %in% items) ||
        anyDuplicated(names(weight)) || !any(weight != 0))
      stop(kind, " weights must be finite, uniquely named by fitted item IDs, and not all zero.", call. = FALSE)
    total <- sum(weight)
    magnitude <- sum(abs(weight))
    squares <- sum(weight^2)
    if (!is.finite(total) || !is.finite(magnitude) || !is.finite(squares) || squares == 0)
      stop("Item weights exceed the finite numerical projection scale; rescale the target weights.", call. = FALSE)
    if (kind == "contrast" && abs(total) > 1e-10 * magnitude)
      stop("contrast weights must sum to zero.", call. = FALSE)
    if (kind == "aggregate" && (any(weight < 0) || abs(total - 1) > 1e-10))
      stop("aggregate weights must be nonnegative and sum to one; weights are not normalized automatically.",
           call. = FALSE)
    weight <- weight[weight != 0]
    list(label = paste0(kind, ":", names(value)[i]), kind = kind,
         index = match(names(weight), items), weight = unname(weight))
  })
}

.gt_batch_projection_output_size <- function(fit, context, contrasts, aggregate, score, allocations = 1L) {
  target_count <- function(x) if (is.null(x)) 0L else if (is.numeric(x)) 1L else length(x)
  targets <- length(context$items) + target_count(contrasts) + target_count(aggregate)
  outcomes <- length(fit$outcomes) + as.integer(!is.null(score))
  rows <- as.double(targets) * outcomes * length(context$components) * allocations
  if (!is.finite(rows) || rows > 1e6)
    stop("Projection output exceeds one million source-contribution rows; reduce the allocation grid or targets.",
         call. = FALSE)
  invisible(rows)
}

# Point projections conditional on the fitted item grouping. All instrumentation
# facets remain random, and each item's score averages every planned condition.
gt_batch_reliability <- function(fit, counts = NULL, contrasts = NULL, aggregate = NULL, score = NULL) {
  context <- .gt_batch_projection_context(fit, counts)
  .gt_batch_projection_output_size(fit, context, contrasts, aggregate, score)
  items <- context$items
  targets <- lapply(seq_along(items), function(i)
    list(label = paste0("item:", items[i]), kind = "absolute_item", index = i, weight = 1))
  targets <- c(targets, .gt_batch_projection_targets(contrasts, items, "contrast"),
               .gt_batch_projection_targets(aggregate, items, "aggregate"))
  outcomes <- fit$outcomes
  outcome_weights <- lapply(seq_along(outcomes), function(i) as.numeric(seq_along(outcomes) == i))
  outcome_kind <- rep("outcome", length(outcomes))
  if (!is.null(score)) {
    if (!inherits(score, "gt_score") || !setequal(names(score$weights), fit$outcomes))
      stop("score must explicitly weight every outcome exactly once.", call. = FALSE)
    outcome_weights <- c(outcome_weights, list(as.numeric(score$weights[fit$outcomes])))
    outcomes <- c(outcomes, "composite")
    outcome_kind <- c(outcome_kind, "composite")
  }
  source_variances <- lapply(outcome_weights, function(w) {
    if (any(!is.finite(w)) || !is.finite(sum(w^2)) || sum(w^2) == 0)
      stop("Outcome weights exceed the finite numerical projection scale; rescale the score.", call. = FALSE)
    vapply(context$components, function(M) {
      value <- drop(crossprod(w, M %*% w))
      if (!is.finite(value)) stop("A source quadratic form exceeds the finite numerical projection scale.",
                                 call. = FALSE)
      max(0, value)
    }, numeric(1))
  })
  summary_rows <- contribution_rows <- vector("list", length(targets) * length(outcomes))
  position <- 0L
  for (target in targets) {
    w <- target$weight
    batch_sums <- tapply(w, context$batch[target$index], sum)
    contractions <- c(same_item = sum(w^2), all_items = sum(w)^2, same_batch = sum(batch_sums^2))
    if (any(!is.finite(contractions)))
      stop("Target contractions exceed the finite numerical projection scale.", call. = FALSE)
    multiplier <- unname(contractions[context$kernel]) / context$divisor
    for (j in seq_along(outcomes)) {
      position <- position + 1L
      contribution <- multiplier * source_variances[[j]]
      universe <- sum(contribution[context$role == "universe"])
      error <- sum(contribution[context$role == "error"])
      if (any(!is.finite(contribution)) || !is.finite(universe + error))
        stop("Projected variances exceed the finite numerical projection scale.", call. = FALSE)
      coefficient <- if (universe + error > 0) universe / (universe + error) else NA_real_
      coefficient_name <- switch(target$kind, absolute_item = "Phi", contrast = "contrast_reliability",
                                 aggregate = "aggregate_dependability")
      summary_rows[[position]] <- data.frame(target = target$label, target_kind = target$kind,
        outcome = outcomes[j], outcome_kind = outcome_kind[j], universe_variance = universe,
        error_variance = error, error_sd = sqrt(error), coefficient = coefficient,
        coefficient_name = coefficient_name, stringsAsFactors = FALSE)
      contribution_rows[[position]] <- data.frame(target = target$label, target_kind = target$kind,
        outcome = outcomes[j], outcome_kind = outcome_kind[j], source = names(context$components),
        role = unname(context$role), kernel = unname(context$kernel),
        contraction = unname(contractions[context$kernel]), divisor = unname(context$divisor),
        variance = unname(contribution), stringsAsFactors = FALSE)
    }
  }
  structure(list(summary = do.call(rbind, summary_rows),
    source_contributions = do.call(rbind, contribution_rows),
    layout = data.frame(item = items, batch = context$batch, stringsAsFactors = FALSE),
    target_weights = stats::setNames(lapply(targets, function(x)
      stats::setNames(x$weight, items[x$index])), vapply(targets, `[[`, character(1), "label")),
    counts = context$counts, observed_counts = context$observed, pilot_items = length(items),
    batch_size = fit$design$batch_model$size, annotations_per_item = prod(context$counts),
    projected_calls = fit$design$batch_model$batches * prod(context$counts),
    score = score, scale = "observed", fixed_facets = character(), batch = context$status,
    extrapolated = any(context$counts > context$observed),
    uncertainty = list(available = FALSE, reason = "Point projections only; sampling intervals are not implemented."),
    interpretation = paste("Conditional on the fitted fixed item grouping, with all instrumentation facets random",
      "and exchangeable and equal averaging over the planned complete panel. The item main effect defines the",
      "universe score. Coefficients describe the explicitly weighted target, not a universal ranking coefficient.",
      "Aggregate error is annotation error conditional on these items, not corpus-sampling uncertainty.",
      "Counts do not change batch size, grouping, item count, or fitted source covariances.")),
    class = "gt_batch_reliability")
}

print.gt_batch_reliability <- function(x, ..., digits = 4L, max_rows = 12L) {
  cat("Gaussian batch projections conditional on the fitted fixed grouping\n")
  cat("Point estimates; all instrumentation facets random.\n")
  print(utils::head(x$summary, max_rows), digits = digits, row.names = FALSE)
  if (nrow(x$summary) > max_rows) cat("Showing", max_rows, "of", nrow(x$summary), "target/outcome rows.\n")
  invisible(x)
}

as.data.frame.gt_batch_reliability <- function(x, row.names = NULL, optional = FALSE, ...) {
  result <- x$summary
  if (!is.null(row.names)) rownames(result) <- row.names
  attr(result, "counts") <- x$counts
  attr(result, "interpretation") <- x$interpretation
  attr(result, "uncertainty") <- x$uncertainty
  result
}

# A finite supplied grid, rather than an optimizer or a change in batch layout.
gt_batch_dstudy <- function(fit, grid, contrasts = NULL, aggregate = NULL, score = NULL) {
  if (!is.data.frame(grid) || !nrow(grid) || !ncol(grid) || anyDuplicated(names(grid)) ||
      any(!vapply(grid, is.numeric, logical(1))))
    stop("grid must be a nonempty data frame of numeric instrumentation counts with unique column names.",
         call. = FALSE)
  if (nrow(grid) > 1000L)
    stop("A batch D study accepts at most 1000 supplied allocations.", call. = FALSE)
  context <- .gt_batch_projection_context(fit, NULL)
  .gt_batch_projection_output_size(fit, context, contrasts, aggregate, score, nrow(grid))
  first <- gt_batch_reliability(fit, counts = unlist(grid[1L, , drop = FALSE], use.names = TRUE),
    contrasts = contrasts, aggregate = aggregate, score = score)
  summaries <- contributions <- allocations <- vector("list", nrow(grid))
  for (i in seq_len(nrow(grid))) {
    result <- if (i == 1L) first else gt_batch_reliability(fit,
      counts = unlist(grid[i, , drop = FALSE], use.names = TRUE),
      contrasts = contrasts, aggregate = aggregate, score = score)
    summaries[[i]] <- cbind(data.frame(design_id = i), result$summary)
    contributions[[i]] <- cbind(data.frame(design_id = i), result$source_contributions)
    allocations[[i]] <- as.data.frame(as.list(result$counts), check.names = FALSE)
  }
  structure(list(summary = do.call(rbind, summaries), source_contributions = do.call(rbind, contributions),
    grid = do.call(rbind, allocations), layout = first$layout, target_weights = first$target_weights,
    observed_counts = first$observed_counts, pilot_items = first$pilot_items, batch_size = first$batch_size,
    score = first$score, scale = first$scale, fixed_facets = first$fixed_facets,
    batch = first$batch, uncertainty = first$uncertainty, interpretation = first$interpretation),
    class = "gt_batch_dstudy")
}

print.gt_batch_dstudy <- function(x, ..., digits = 4L, max_rows = 12L) {
  cat("Gaussian batch D study:", nrow(x$grid), "supplied allocations, fixed item grouping\n")
  cat("Point estimates; all instrumentation facets random.\n")
  print(utils::head(x$summary, max_rows), digits = digits, row.names = FALSE)
  if (nrow(x$summary) > max_rows) cat("Showing", max_rows, "of", nrow(x$summary), "design/target/outcome rows.\n")
  invisible(x)
}

as.data.frame.gt_batch_dstudy <- function(x, row.names = NULL, optional = FALSE, ...) {
  result <- x$summary
  allocation_rows <- match(result$design_id, seq_len(nrow(x$grid)))
  if (anyNA(allocation_rows))
    stop("Summary design_id values must identify rows of the allocation grid.", call. = FALSE)
  allocations <- x$grid[allocation_rows, , drop = FALSE]
  names(allocations) <- paste0("allocation_", names(allocations))
  annotations <- apply(x$grid, 1L, prod)
  extrapolated <- vapply(seq_len(nrow(x$grid)), function(i)
    any(unlist(x$grid[i, , drop = FALSE], use.names = TRUE) > x$observed_counts[names(x$grid)]), logical(1))
  result <- cbind(result, allocations)
  result$pilot_items <- x$pilot_items
  result$batch_size <- x$batch_size
  result$annotations_per_item <- annotations[allocation_rows]
  result$projected_calls <- annotations[allocation_rows] * (x$pilot_items / x$batch_size)
  result$extrapolated <- extrapolated[allocation_rows]
  result$scale <- x$scale
  result$uncertainty_available <- x$uncertainty$available
  result$uncertainty_reason <- x$uncertainty$reason
  result$interpretation <- x$interpretation
  if (!is.null(row.names)) rownames(result) <- row.names
  attr(result, "grid") <- x$grid
  attr(result, "interpretation") <- x$interpretation
  attr(result, "uncertainty") <- x$uncertainty
  result
}
