# Cost-aware, bounded D studies. Costs do not alter the fitted statistical model.

.gt_plan_text <- function(x, name) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x)))
    stop(name, " must be one nonempty character string.", call. = FALSE)
  x
}

.gt_plan_integer <- function(x, name) {
  if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || x < 1 ||
      x != floor(x) || x >= 2^53)
    stop(name, " must be one positive integer below 2^53.", call. = FALSE)
  x
}

.gt_plan_candidates <- function(candidates, observed, max_candidates) {
  valid_names <- function(x) length(x) && !is.null(names(x)) &&
    !anyNA(names(x)) && all(nzchar(names(x))) && !anyDuplicated(names(x)) &&
    all(names(x) %in% names(observed))
  if (is.data.frame(candidates)) {
    if (!nrow(candidates) || !valid_names(candidates) || nrow(candidates) > max_candidates)
      stop("candidates must have named facet columns and 1 to max_candidates rows.", call. = FALSE)
    grid <- candidates
  } else if (is.list(candidates) && valid_names(candidates)) {
    if (any(lengths(candidates) == 0L) || prod(as.double(lengths(candidates))) > max_candidates)
      stop("The Cartesian candidate grid must contain 1 to max_candidates rows.", call. = FALSE)
    grid <- expand.grid(candidates, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  } else {
    stop("candidates must be a data frame or named list of declared instrumentation facet counts.", call. = FALSE)
  }
  if (!all(vapply(grid, is.numeric, logical(1))) || any(!is.finite(as.matrix(grid))) ||
      any(as.matrix(grid) < 1 | as.matrix(grid) != floor(as.matrix(grid))) ||
      any(as.matrix(grid) >= 2^53))
    stop("Candidate counts must be positive finite integers below 2^53.", call. = FALSE)
  allocation <- as.data.frame(as.list(observed), check.names = FALSE)[rep(1L, nrow(grid)), , drop = FALSE]
  allocation[names(grid)] <- grid
  rownames(allocation) <- NULL
  allocation
}

.gt_plan_numeric_frame <- function(x, rows, name, empty = FALSE) {
  if (!is.data.frame(x) || nrow(x) != rows || (!empty && !ncol(x)) ||
      anyNA(names(x)) || any(!nzchar(names(x))) || anyDuplicated(names(x)) ||
      !all(vapply(x, is.numeric, logical(1))))
    stop(name, " must be a numeric data frame with one row per candidate and unique nonempty names.",
         call. = FALSE)
  if (any(!is.finite(as.matrix(x))) || any(as.matrix(x) < 0))
    stop(name, " must contain only finite nonnegative values.", call. = FALSE)
  rownames(x) <- NULL
  x
}

.gt_plan_cost <- function(cost, input, description) {
  callback <- is.function(cost)
  value <- if (callback) cost(input) else cost
  assumptions <- NULL
  resources <- data.frame(row.names = seq_len(nrow(input)))
  if (is.list(value) && !is.data.frame(value)) {
    if (is.null(names(value)) || anyNA(names(value)) || anyDuplicated(names(value)) ||
        !"costs" %in% names(value) || any(!names(value) %in% c("costs", "resources", "assumptions")))
      stop("A cost callback list must contain costs and optionally resources and assumptions.", call. = FALSE)
    if (!is.null(value$resources)) resources <- value$resources
    assumptions <- value$assumptions
    if (!is.null(assumptions) && (!is.character(assumptions) || anyNA(assumptions)))
      stop("Cost assumptions must be character text without missing entries.", call. = FALSE)
    value <- value$costs
  }
  costs <- .gt_plan_numeric_frame(value, nrow(input), "cost breakdown")
  resources <- .gt_plan_numeric_frame(resources, nrow(input), "cost resources", empty = TRUE)
  total <- rowSums(costs)
  if (any(!is.finite(total))) stop("Total candidate cost must be finite.", call. = FALSE)
  if (is.null(description)) description <- "User-supplied cost components; no provider prices are embedded."
  .gt_plan_text(description, "cost_description")
  list(costs = costs, resources = resources, total = total,
       provenance = list(description = description, assumptions = assumptions,
         type = if (callback) "callback" else "supplied_breakdown",
         callback = if (callback) paste(deparse(cost), collapse = "\n") else NULL))
}

.gt_plan_constraints <- function(constraints, input) {
  if (is.null(constraints)) {
    return(list(checks = data.frame(row.names = seq_len(nrow(input))),
                feasible = rep(TRUE, nrow(input)), reason = rep(NA_character_, nrow(input))))
  }
  value <- if (is.function(constraints)) constraints(input) else constraints
  if (is.logical(value)) value <- data.frame(user_constraint = value)
  if (!is.data.frame(value) || nrow(value) != nrow(input) || !ncol(value) ||
      anyNA(names(value)) || any(!nzchar(names(value))) || anyDuplicated(names(value)) ||
      !all(vapply(value, is.logical, logical(1))))
    stop("constraints must return a logical vector or named logical data frame with one row per candidate.",
         call. = FALSE)
  feasible <- apply(value, 1L, function(x) if (any(!x, na.rm = TRUE)) FALSE else
    if (anyNA(x)) NA else TRUE)
  reason <- vapply(seq_len(nrow(value)), function(i) {
    row <- unlist(value[i, , drop = FALSE], use.names = FALSE)
    failed <- names(value)[which(!row)]
    unknown <- names(value)[is.na(row)]
    parts <- c(if (length(failed)) paste0("Failed: ", paste(failed, collapse = ", ")),
               if (length(unknown)) paste0("Unknown: ", paste(unknown, collapse = ", ")))
    if (length(parts)) paste(parts, collapse = "; ") else NA_character_
  }, character(1))
  rownames(value) <- NULL
  list(checks = value, feasible = feasible, reason = reason)
}

# Pareto dominance in cost versus one declared performance objective. A group
# at the same cost is handled together, so exact ties are all retained.
.gt_plan_pareto <- function(cost, performance, feasible) {
  result <- rep(NA, length(cost))
  result[which(!feasible)] <- FALSE
  usable <- which(feasible & is.finite(performance))
  if (!length(usable)) return(result)
  usable <- usable[order(cost[usable], -performance[usable])]
  best_cheaper <- -Inf
  group_id <- match(cost[usable], unique(cost[usable]))
  groups <- split(usable, factor(group_id, levels = seq_len(max(group_id))))
  for (positions in groups) {
    best_here <- max(performance[positions])
    result[positions] <- performance[positions] == best_here & performance[positions] > best_cheaper
    best_cheaper <- max(best_cheaper, best_here)
  }
  result
}

# Enumerate a bounded grid while preserving the same score and facet universe.
gt_plan <- function(fit, candidates, cost, currency, cost_date, study_items, target,
                    coefficient = "Erho2", outcome = NULL, kind = "outcome",
                    screening = c("point", "lower"), baseline = 1L, constraints = NULL,
                    scale = NULL, score = NULL, fixed = character(), level = 0.95,
                    max_candidates = 10000L, cost_description = NULL) {
  .gt_check_target(target)
  .gt_check_coefficient(coefficient)
  .gt_check_level(level)
  screening <- match.arg(screening)
  .gt_plan_text(currency, "currency")
  if (!grepl("^[A-Z]{3}$", currency))
    stop("currency must be a three-letter uppercase currency code supplied by the user.", call. = FALSE)
  if (inherits(cost_date, "Date")) cost_date <- as.character(cost_date)
  .gt_plan_text(cost_date, "cost_date")
  parsed_date <- tryCatch(as.Date(cost_date, format = "%Y-%m-%d"), error = function(e) as.Date(NA))
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", cost_date) || is.na(parsed_date) ||
      as.character(parsed_date) != cost_date)
    stop("cost_date must be a valid date in YYYY-MM-DD form.", call. = FALSE)
  .gt_plan_integer(study_items, "study_items")
  .gt_plan_integer(max_candidates, "max_candidates")
  .gt_plan_integer(baseline, "baseline")
  if (inherits(fit, "gt_fit") && identical(.gt_batch_status(fit$design)$status, "modelled"))
    stop("gt_plan does not yet project modelled batch layouts. No Call component is dropped; use a separately declared layout-specific batch analysis.", call. = FALSE)
  context <- .gt_reliability_context(fit, scale)
  allocation <- .gt_plan_candidates(candidates, context$counts, max_candidates)
  if (baseline > nrow(allocation)) stop("baseline must identify one candidate row.", call. = FALSE)
  fixed <- .gt_reliability_fixed(fit, fixed, context$counts, context$counts)
  for (facet in fixed) {
    if (any(allocation[[facet]] != context$counts[[facet]]))
      stop("A fixed facet's observed levels cannot be changed by the planner: ", facet, ".", call. = FALSE)
  }
  measurements <- apply(allocation, 1L, prod) * context$replicates
  total_annotations <- measurements * study_items
  if (any(!is.finite(total_annotations)) || any(total_annotations >= 2^53))
    stop("Total annotations must be exactly representable integers below 2^53 for every candidate.", call. = FALSE)
  coefficients <- lapply(seq_len(nrow(allocation)), function(i)
    .gt_reliability_kernel(fit, context, unlist(allocation[i, , drop = FALSE], use.names = TRUE),
                           score, fixed, level))
  tables <- lapply(seq_along(coefficients), function(i) {
    table <- as.data.frame(coefficients[[i]])
    table$design_id <- i
    table
  })
  all_results <- do.call(rbind, tables)
  rownames(all_results) <- NULL
  if (is.null(kind)) stop("kind must be \"outcome\" or \"composite\".", call. = FALSE)
  results <- .gt_reporting_select(all_results, outcome, kind, single = TRUE)
  if (nrow(results) != nrow(allocation)) stop("Select exactly one outcome or composite per candidate.", call. = FALSE)
  rownames(results) <- NULL
  results$annotations_per_item <- measurements
  results$study_items <- rep(study_items, nrow(results))
  results$total_annotations <- total_annotations
  input <- results[, c("design_id", paste0("allocation_", names(allocation)),
                       "annotations_per_item", "study_items", "total_annotations"), drop = FALSE]
  attr(input, "allocation_columns") <- stats::setNames(names(allocation), paste0("allocation_", names(allocation)))
  cost_record <- .gt_plan_cost(cost, input, cost_description)
  results$total_cost <- cost_record$total
  results$currency <- currency
  results$cost_date <- cost_date
  for (name in names(cost_record$costs)) results[[paste0("cost_component_", name)]] <- cost_record$costs[[name]]
  for (name in names(cost_record$resources)) results[[paste0("resource_", name)]] <- cost_record$resources[[name]]
  constraint_record <- .gt_plan_constraints(constraints, results)
  results$feasible <- constraint_record$feasible
  results$constraint_reason <- constraint_record$reason
  results$coefficient <- coefficient
  results$target <- target
  results$screening <- screening
  results$screening_value <- results[[paste0(coefficient, if (screening == "lower") "_lower" else "")]]
  results$screening_available <- is.finite(results$screening_value)
  results$screening_reason <- NA_character_
  missing <- which(!results$screening_available)
  if (length(missing)) {
    reason <- if (screening == "lower") results$uncertainty_reason[missing] else
      rep("The projected coefficient is undefined for this allocation.", length(missing))
    empty <- is.na(reason) | !nzchar(reason)
    reason[empty] <- "A finite lower confidence bound is unavailable for this coefficient and allocation."
    results$screening_reason[missing] <- reason
  }
  results$meets_target <- ifelse(results$screening_available, results$screening_value >= target, NA)
  results$eligible <- results$feasible & results$meets_target
  results$minimum_cost <- ifelse(is.na(results$eligible), NA, FALSE)
  qualified <- which(results$eligible)
  if (length(qualified)) results$minimum_cost[qualified] <-
    results$total_cost[qualified] == min(results$total_cost[qualified])
  results$pareto <- .gt_plan_pareto(results$total_cost, results$screening_value, results$feasible)
  results$cost_rank <- NA_integer_
  feasible_rows <- which(results$feasible)
  results$cost_rank[feasible_rows] <- rank(results$total_cost[feasible_rows], ties.method = "min")
  weight <- if (kind == "composite") as.numeric(score$weights[fit$outcomes]) else
    as.numeric(fit$outcomes == unique(results$outcome))
  quadratic <- function(matrix) drop(crossprod(weight, matrix %*% weight))
  results$universe_variance <- vapply(coefficients, function(x) quadratic(x$universe_covariance), numeric(1))
  results$relative_error <- vapply(coefficients, function(x) quadratic(x$relative_error_covariance), numeric(1))
  results$absolute_error <- vapply(coefficients, function(x) quadratic(x$absolute_error_covariance), numeric(1))
  results$baseline_id <- baseline
  results$extra_cost <- results$total_cost - results$total_cost[baseline]
  results$relative_error_reduction <- results$relative_error[baseline] - results$relative_error
  results$absolute_error_reduction <- results$absolute_error[baseline] - results$absolute_error
  results$Erho2_gain <- results$Erho2 - results$Erho2[baseline]
  results$Phi_gain <- results$Phi - results$Phi[baseline]
  component_variance <- vapply(context$components, quadratic, numeric(1))
  contributions <- lapply(seq_along(coefficients), function(i) {
    object <- coefficients[[i]]
    sources <- names(object$source_roles)
    reference <- coefficients[[baseline]]$source_weights
    data.frame(design_id = i, source = sources, role = unname(object$source_roles),
      universe = component_variance[sources] * object$source_weights$universe,
      relative_error = component_variance[sources] * object$source_weights$relative,
      absolute_error = component_variance[sources] * object$source_weights$absolute,
      relative_error_reduction = component_variance[sources] *
        (reference$relative - object$source_weights$relative),
      absolute_error_reduction = component_variance[sources] *
        (reference$absolute - object$source_weights$absolute), row.names = NULL)
  })
  structure(list(results = results, allocations = allocation, all_coefficients = all_results,
    source_contributions = do.call(rbind, contributions), cost_breakdown = cost_record$costs,
    resources = cost_record$resources, constraint_checks = constraint_record$checks,
    baseline = results[baseline, , drop = FALSE],
    provenance = list(currency = currency, cost_date = cost_date, cost_model = cost_record$provenance,
      study_items = study_items, observed_counts = context$counts, replicates = context$replicates,
      candidate_count = nrow(allocation), max_candidates = max_candidates,
      candidate_source = if (is.data.frame(candidates)) "supplied_rows" else "cartesian_grid",
      search_scope = "declared_candidates_only", pareto_scope = "feasible_candidates_with_available_screening_value",
      screening = screening, target = target, coefficient = coefficient,
      outcome = unique(results$outcome), kind = kind, scale = context$scale,
      fixed_facets = fixed, score = score, interval_level = level, uncertainty = context$uncertainty,
      baseline_id = baseline, batch = .gt_batch_status(fit$design),
      interpretation = paste("Source covariances, outcome scale, identities and facet universe are held fixed.",
        "Facet counts represent exchangeable draws under that same model; evaluator identities are not optimized.",
        "study_items scales costs, not reliability or pilot precision; request size is not a replicate count.",
        "Request batching in cost resources does not account for dependence absent from the fit.",
        "Human-review costs alone do not change projected reliability.",
        "Lower bounds are pointwise model-based intervals, not simultaneous guarantees after selection.")),
    fit_diagnostics = gt_diagnostics(fit)), class = "gt_plan")
}

as.data.frame.gt_plan <- function(x, row.names = NULL, optional = FALSE, ...) {
  result <- x$results
  if (!is.null(row.names)) rownames(result) <- row.names
  result
}

print.gt_plan <- function(x, ..., digits = 4L, max_rows = 12L) {
  .gt_print_coefficient_options(digits, max_rows)
  cat("Cost-aware D study |", nrow(x$results), "declared candidates |", x$provenance$currency,
      "costs dated", x$provenance$cost_date, "\n")
  cat("Screen:", x$provenance$coefficient, x$provenance$screening, ">=", x$provenance$target,
      "| baseline candidate", x$provenance$baseline_id, "\n")
  columns <- c("design_id", "annotations_per_item", "total_cost", "screening_value", "feasible",
               "meets_target", "minimum_cost", "pareto", "extra_cost")
  print(utils::head(x$results[columns], max_rows), row.names = FALSE, digits = digits)
  if (nrow(x$results) > max_rows) cat("All candidates remain in as.data.frame(x).\n")
  if (any(!x$results$screening_available))
    cat("Some screening values are unavailable; inspect screening_reason. Missing bounds are not treated as certainty.\n")
  batch_note <- .gt_batch_status_text(x$provenance$batch)
  if (length(batch_note)) cat(batch_note, "\n")
  cat("Minimum cost and Pareto status are limited to the declared, feasible, evaluable candidates.\n")
  cat("Study items scale cost; this D study does not estimate pilot precision or change evaluator identities.\n")
  invisible(x)
}
