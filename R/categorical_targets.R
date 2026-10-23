# Repeated-panel categorical targets under a fitted latent random-effects law.
# Integration error is estimated between independent entire panel pairs.
# It is never presented as parameter uncertainty or future-panel prediction.

.gt_categorical_scores <- function(model, outcomes, scores) {
  if (is.numeric(scores) && length(outcomes) == 1L)
    scores <- stats::setNames(list(scores), outcomes)
  if (!is.null(scores) && (!is.list(scores) || is.null(names(scores)) ||
      anyNA(names(scores)) || anyDuplicated(names(scores)) ||
      any(!names(scores) %in% outcomes)))
    stop("scores must be a named list for selected outcomes, or a named vector for one outcome.", call. = FALSE)
  result <- stats::setNames(vector("list", length(outcomes)), outcomes)
  for (outcome in outcomes) {
    block <- model$blocks[[outcome]]
    if (block$family == "categorical")
      stop("Use target = 'category_vector' for unordered labels; this API does not impose a nominal score.",
           call. = FALSE)
    value <- scores[[outcome]]
    if (is.null(value) && block$family == "binary")
      value <- stats::setNames(c(0, 1), block$levels)
    if (!is.numeric(value) || is.complex(value) || length(value) != length(block$levels) ||
        any(!is.finite(value)) || is.null(names(value)) || anyNA(names(value)) ||
        anyDuplicated(names(value)) || !setequal(names(value), block$levels))
      stop("Supply a finite score for every category of outcome '", outcome, "' using exact level names.",
           call. = FALSE)
    value <- value[block$levels]
    if (length(unique(value)) < 2L)
      stop("Scores must distinguish at least two categories.", call. = FALSE)
    span <- max(value) - min(value)
    if (!is.finite(span^2) || span^2 == 0)
      stop("The score range is outside numerically supported variance units; rescale the scores.", call. = FALSE)
    if (block$family == "ordinal" && any(diff(value) <= 0))
      stop("Ordinal scores must increase strictly in the declared category order.", call. = FALSE)
    result[[outcome]] <- value
  }
  result
}

# Sum nonnegative category contributions instead of subtracting moments near one.
# Scratch storage is linear in rows; no row-wise covariance matrices are formed.
.gt_categorical_probability_variance <- function(probability, scores = NULL) {
  variance <- numeric(nrow(probability))
  if (is.null(scores)) {
    prefix <- numeric(nrow(probability))
    for (category in seq_len(ncol(probability))) {
      variance <- variance + 2 * probability[, category] * prefix
      prefix <- prefix + probability[, category]
    }
  } else {
    expected <- drop(probability %*% scores)
    for (category in seq_len(ncol(probability)))
      variance <- variance + probability[, category] * (scores[[category]] - expected)^2
  }
  variance
}

.gt_categorical_item_moments <- function(probability, item, n_items, scores = NULL) {
  if (!is.factor(item) && (!is.numeric(item) || is.complex(item) ||
      any(!is.finite(item)) || any(item != floor(item))))
    stop("Simulated object indices must be finite integers in 1:n_items.", call. = FALSE)
  group <- as.integer(item)
  if (length(group) != nrow(probability) || anyNA(group) || any(group < 1L | group > n_items))
    stop("Simulated object indices must lie in 1:n_items.", call. = FALSE)
  counts <- tabulate(group, nbins = n_items)
  if (any(counts == 0L)) stop("Every simulated object must have observations.", call. = FALSE)
  if (is.null(scores)) {
    mean <- rowsum(probability, group, reorder = TRUE) / counts
    noise <- rowsum(matrix(.gt_categorical_probability_variance(probability)), group, reorder = TRUE)[, 1L] / counts^2
  } else {
    expected <- drop(probability %*% scores)
    variance <- .gt_categorical_probability_variance(probability, scores)
    mean <- rowsum(matrix(expected), group, reorder = TRUE) / counts
    noise <- rowsum(matrix(variance), group, reorder = TRUE)[, 1L] / counts^2
  }
  list(mean = mean, second = rowSums(mean^2) + noise)
}

.gt_categorical_votes <- function(labels, levels, item, n_items) {
  code <- match(as.character(labels), levels)
  if (anyNA(code)) stop("Simulated labels do not match declared categories.", call. = FALSE)
  counts <- matrix(tabulate(item + (code - 1L) * n_items, nbins = n_items * length(levels)),
                   n_items, length(levels))
  ties <- counts == apply(counts, 1L, max)
  # Independent uniform random tie breaking, integrated exactly conditional
  # on the two observed vote panels instead of drawing another random number.
  ties / rowSums(ties)
}

.gt_categorical_ratio <- function(moments, zero_signal = FALSE) {
  q <- (ncol(moments) - 2L) / 2L
  average <- colMeans(moments)
  left <- average[seq_len(q)]
  right <- average[q + seq_len(q)]
  center <- (left + right) / 2
  signal <- average[2L * q + 1L] - sum(left * right)
  total <- average[2L * q + 2L] - sum(center^2)
  if (zero_signal) signal <- 0
  raw <- signal / total
  result <- list(estimate = NA_real_, raw_estimate = raw, mc_se = NA_real_,
                 signal_variance = signal, total_variance = total,
                 available = FALSE, reason = NA_character_)
  if (!is.finite(total) || total <= 64 * .Machine$double.eps * max(1, abs(average))) {
    result$reason <- "The projected score has zero or numerically unresolved total variance."
    return(result)
  }
  if (!is.finite(raw) || raw < 0 || raw > 1) {
    result$reason <- "Monte Carlo moments put the ratio outside [0,1]; increase integration precision."
    return(result)
  }
  gradient_signal <- c(-right, -left, 1, 0)
  gradient_total <- c(-center, -center, 0, 1)
  gradient <- (gradient_signal * total - signal * gradient_total) / total^2
  # The variance of projected influence rows equals g' cov(M) g, without
  # allocating a covariance matrix quadratic in the number of categories.
  variance <- if (zero_signal) 0 else
    stats::var(drop(moments %*% gradient)) / nrow(moments)
  if (!is.finite(variance) || variance < -1e-12) {
    result$reason <- "The Monte Carlo variance calculation is unavailable."
    return(result)
  }
  result$estimate <- raw
  result$mc_se <- sqrt(max(0, variance))
  result$available <- TRUE
  result
}

# Account for stored moments as well as one active panel pair. The estimate
# includes a second moment copy, per-object target scratch and influence rows;
# it is a working-storage guard, not a promise about the R process's total RSS.
.gt_categorical_target_resources <- function(model, allocation, target, outcome, replications) {
  simulation <- .gt_discrete_sim_resources(model, allocation, 2L)
  dimensions <- vapply(outcome, function(name)
    if (target == "score") 1 else length(model$blocks[[name]]$levels), numeric(1))
  columns <- if (target == "decision") dimensions + 1 else 2 * dimensions + 2
  moment_bytes <- 8 * as.double(replications) * sum(columns)
  # A small allowance covers result tables, lists and category/score metadata.
  metadata_bytes <- 65536 + 256 * sum(dimensions)
  retained_bytes <- moment_bytes + metadata_bytes
  scratch_bytes <- 8 * (8 * allocation[[model$design$object]] * max(dimensions) +
    12 * max(columns) + 4 * replications)
  estimated_bytes <- simulation$estimated_bytes + 2 * moment_bytes + metadata_bytes + scratch_bytes
  limit <- 512 * 1024^2
  if (!is.finite(estimated_bytes) || estimated_bytes > limit)
    stop("Estimated categorical target workspace, including retained moments, exceeds the 512 MiB limit.",
         call. = FALSE)
  list(rows = simulation$rows, moment_bytes = moment_bytes, retained_bytes = retained_bytes,
       estimated_peak_bytes = estimated_bytes, max_bytes = limit)
}

gt_categorical_target <- function(fit, target = c("score", "category_vector", "decision"),
                                  counts = NULL, scores = NULL, n_items = 200L,
                                  replications = 40L, seed, max_rows = 100000L, outcome = NULL) {
  target <- match.arg(target)
  model <- .gt_discrete_sim_model(fit)
  .gt_categorical_target_model(model, target, counts, scores, n_items,
    replications, seed, max_rows, outcome)
}

# A validated generating scenario can differ from the original fitted values.
# This private seam evaluates that model without constructing a fictitious fit.
.gt_categorical_target_model <- function(model, target, counts = NULL, scores = NULL,
                                         n_items = 200L, replications = 40L, seed,
                                         max_rows = 100000L, outcome = NULL) {
  if (!inherits(model, "gt_discrete_sim_model"))
    stop("Expected a validated categorical simulation model.", call. = FALSE)
  target <- match.arg(target, c("score", "category_vector", "decision"))
  replications <- .gt_sim_integer(replications, "replications", 2L, 10000L)
  seed <- .gt_sim_integer(seed, "seed", 0L)
  if (is.null(outcome)) outcome <- model$outcomes
  if (!is.character(outcome) || !length(outcome) || anyNA(outcome) || anyDuplicated(outcome) ||
      any(!outcome %in% model$outcomes))
    stop("outcome must name one or more fitted outcomes exactly once.", call. = FALSE)
  if (target != "score" && !is.null(scores))
    stop("scores applies only to target = 'score'.", call. = FALSE)
  score_map <- if (target == "score") .gt_categorical_scores(model, outcome, scores) else NULL
  integration_scores <- lapply(score_map, function(x) (x - min(x)) / (max(x) - min(x)))
  allocation <- .gt_discrete_sim_allocation(model, n_items, counts, max_rows)
  resources <- .gt_categorical_target_resources(model, allocation, target, outcome, replications)
  if (2 * resources$rows * replications > 10000000)
    stop("Integration exceeds ten million generated rows across panel pairs; reduce allocation or replications.",
         call. = FALSE)
  object <- model$design$object
  shared <- intersect(object, names(model$components))
  records <- stats::setNames(lapply(outcome, function(name) {
    dimension <- if (target == "score") 1L else length(model$blocks[[name]]$levels)
    matrix(NA_real_, replications, if (target == "decision") 1L + dimension else 2L * dimension + 2L)
  }), outcome)
  records <- .gt_sim_rng(seed, {
    for (replication in seq_len(replications)) {
      paired <- .gt_discrete_sim_panels(model, allocation, n_panels = 2L, shared_sources = shared)
      item <- paired$panels[[1L]][[object]]
      for (name in outcome) {
        if (target == "decision") {
          left <- .gt_categorical_votes(paired$panels[[1L]][[name]], model$blocks[[name]]$levels,
                                         item, n_items)
          right <- .gt_categorical_votes(paired$panels[[2L]][[name]], model$blocks[[name]]$levels,
                                          item, n_items)
          records[[name]][replication, ] <- c(mean(rowSums(left * right)), colMeans((left + right) / 2))
        } else {
          left <- .gt_categorical_item_moments(paired$probabilities[[1L]][[name]], item, n_items,
                                                integration_scores[[name]])
          right <- .gt_categorical_item_moments(paired$probabilities[[2L]][[name]], item, n_items,
                                                 integration_scores[[name]])
          records[[name]][replication, ] <- c(colMeans(left$mean), colMeans(right$mean),
            mean(rowSums(left$mean * right$mean)), mean((left$second + right$second) / 2))
        }
      }
    }
    records
  })
  marginals <- list()
  results <- lapply(outcome, function(name) {
    moments <- records[[name]]
    diversity <- NA_real_
    if (target == "decision") {
      estimate <- mean(moments[, 1L])
      marginal <- colMeans(moments[, -1L, drop = FALSE])
      names(marginal) <- model$blocks[[name]]$levels
      marginals[[name]] <<- marginal
      diversity <- 1 - sum(marginal^2)
      value <- list(estimate = estimate, raw_estimate = estimate,
        mc_se = stats::sd(moments[, 1L]) / sqrt(replications),
        signal_variance = NA_real_, total_variance = NA_real_, available = TRUE, reason = NA_character_)
    } else {
      dims <- model$blocks[[name]]$dims
      zero_signal <- !length(shared) || all(model$components[[object]][dims, dims, drop = FALSE] == 0)
      value <- .gt_categorical_ratio(moments, zero_signal)
      if (target == "score") {
        units <- (max(score_map[[name]]) - min(score_map[[name]]))^2
        value$signal_variance <- value$signal_variance * units
        value$total_variance <- value$total_variance * units
      }
    }
    data.frame(outcome = name, target = target, as.data.frame(value, stringsAsFactors = FALSE),
               decision_diversity = diversity, stringsAsFactors = FALSE)
  })
  table <- do.call(rbind, results)
  rownames(table) <- NULL
  structure(list(results = table, allocation = allocation, scores = score_map,
    decision_probabilities = marginals, integration_moments = records,
    integration = list(seed = seed, n_items = n_items, replications = replications,
      rows_per_panel = resources$rows, max_rows = max_rows, method = "independent_paired_panel_monte_carlo",
      se_unit = "whole_panel_pair", parameter_uncertainty = FALSE,
      resource_budget = resources,
      moment_units = if (target == "score") "scores_normalized_to_unit_range" else
        if (target == "category_vector") "category_proportions" else "plurality_probabilities",
      score_transform = lapply(score_map, function(x) c(offset = min(x), span = max(x) - min(x)))),
    shared_sources = shared, redrawn_sources = setdiff(names(model$components), shared),
    target = target, decision_rule = if (target == "decision") "plurality_uniform_independent_ties" else NULL,
    batch = .gt_batch_status(model$design), parameter_source = model$parameter_source,
    interpretation = paste("Repeated future panels share the object's main effect and redraw other sources.",
      "Score/vector ratios include shifts from random instrumentation in total variance.",
      "Decision agreement is stability, not discrimination, correctness or agreement with human labels.",
      "Monte Carlo SE describes integration error at fixed fitted parameters; it is not a confidence interval.")),
    class = "gt_categorical_target")
}

as.data.frame.gt_categorical_target <- function(x, row.names = NULL, optional = FALSE, ...) {
  result <- x$results
  if (!is.null(row.names)) rownames(result) <- row.names
  result$integration_replications <- x$integration$replications
  result$integration_items <- x$integration$n_items
  result$parameter_uncertainty <- FALSE
  result$batch_status <- x$batch$status
  result
}

print.gt_categorical_target <- function(x, ..., digits = 4L) {
  .gt_print_coefficient_options(digits, 12L)
  cat("Categorical repeated-panel target:", x$target, "\n")
  print(x$results, row.names = FALSE, digits = digits)
  cat("MC SE measures integration error across independent whole panel pairs. Parameters are held fixed.\n")
  if (x$target == "decision") cat("Plurality agreement does not measure discrimination or accuracy.\n")
  invisible(x)
}
