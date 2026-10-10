# Independent observation-covariance contractions for fixed-layout projections.
if (identical(Sys.getenv("GT_BATCH_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  if (!exists("gt_batch_reliability", mode = "function")) source("R/batch_reliability.R")
} else library(Gtheory4LLM)
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
near <- function(a, b, label, tolerance = 1e-9)
  expect(isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)), label)
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  expect(inherits(error, "error") && grepl(pattern, conditionMessage(error), fixed = TRUE), pattern)
}
set.seed(2718)
data <- expand.grid(item = sprintf("PRIVATE_ITEM_%02d", 1:24), rater = 1:4, run = 1:3,
                    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
i <- match(data$item, unique(data$item))
b <- (i - 1L) %/% 6L + 1L
call <- as.integer(interaction(b, data$rater, data$run, drop = TRUE))
data$call <- paste0("private_call_", call)
data$score <- 1 + rnorm(24)[i] + rnorm(4, sd = .5)[data$rater] +
  rnorm(96, sd = .4)[as.integer(interaction(i, data$rater))] +
  rnorm(48, sd = .7)[call] + rnorm(nrow(data), sd = .8)
data$second <- data$score / 2 + rnorm(48, sd = .6)[call] + rnorm(nrow(data), sd = .7)
design <- gt_design("item", c("rater", "run"), random = ~ item + rater + item:rater,
                    batch = gt_batch(6, id = "call"))
control <- gt_control(gaussian = list(extra_tries = 2L, retry_seed = 439L, check_hessian = FALSE))
fit <- gt_fit(data, c("score", "second"), design,
  covariance = c(item = "unstructured", Call = "unstructured"), residual = "diagonal", control = control)
expect(isTRUE(fit$numerically_accepted), "projection reference fit is accepted")
ids <- unique(data$item)
within <- stats::setNames(c(1, -1), ids[c(1, 2)])
between <- stats::setNames(c(1, -1), ids[c(1, 7)])
concentrated <- stats::setNames(rep(1 / 6, 6), ids[1:6])
spread <- stats::setNames(rep(1 / 6, 6), ids[c(1, 2, 7, 8, 13, 19)])
composite <- gt_score(c(score = .3, second = .7))
projection <- gt_batch_reliability(fit, contrasts = list(within = within, between = between),
  aggregate = list(concentrated = concentrated, spread = spread), score = composite)

# Build the whole observation covariance from equality indicators, then apply
# an independent observation-to-item averaging matrix A and the supplied target.
# This reference does not use the implementation's source divisors or kernels.
dense_reference <- function(fit, counts, weights, outcome_weights) {
  layout <- projection$layout
  panel <- expand.grid(item = layout$item, rater = seq_len(counts[["rater"]]),
    run = seq_len(counts[["run"]]), KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  panel$call <- interaction(layout$batch[match(panel$item, layout$item)], panel$rater, panel$run, drop = TRUE)
  N <- nrow(panel)
  D <- length(fit$outcomes)
  A <- vapply(layout$item, function(id) as.numeric(panel$item == id) / sum(panel$item == id), numeric(N))
  A <- t(A)
  item_weights <- numeric(nrow(layout))
  item_weights[match(names(weights), layout$item)] <- weights
  B <- kronecker(matrix(item_weights, nrow = 1) %*% A, matrix(outcome_weights, nrow = 1))
  error <- universe <- matrix(0, N * D, N * D)
  reference_sources <- numeric(length(fit$covariance_components))
  names(reference_sources) <- names(fit$covariance_components)
  for (source in names(fit$covariance_components)) {
    if (source == "Residual") K <- diag(N) else {
      columns <- if (source == "Call") "call" else strsplit(source, ":", fixed = TRUE)[[1L]]
      K <- Reduce(`*`, lapply(panel[columns], function(x) outer(x, x, "==")))
    }
    V <- kronecker(K, fit$covariance_components[[source]])
    reference_sources[[source]] <- drop(B %*% V %*% t(B))
    if (source == "item") universe <- universe + V else error <- error + V
  }
  c(universe = drop(B %*% universe %*% t(B)), error = drop(B %*% error %*% t(B)), reference_sources)
}
for (target in names(projection$target_weights)) {
  # All 24 item rows are identical by exchangeability; test two, plus every
  # contrast and aggregate, avoiding repeated dense allocations for duplicates.
  if (startsWith(target, "item:") && !target %in% paste0("item:", ids[c(1, 7)])) next
  for (outcome in c("score", "second", "composite")) {
    weights <- switch(outcome, score = c(1, 0), second = c(0, 1), composite = c(.3, .7))
    reference <- dense_reference(fit, projection$counts, projection$target_weights[[target]], weights)
    row <- projection$summary[projection$summary$target == target & projection$summary$outcome == outcome, ]
    near(row$universe_variance, reference[["universe"]], "dense universe contraction")
    near(row$error_variance, reference[["error"]], "dense error contraction")
    details <- subset(projection$source_contributions, target == row$target & outcome == row$outcome)
    near(details$variance, reference[details$source], "every source matches dense A V A transpose")
  }
}
call_part <- function(target, object = projection) {
  rows <- object$source_contributions
  rows$variance[rows$source == "Call" & rows$outcome == "score" & rows$target == target]
}
near(call_part("contrast:within"), 0, "shared call cancels within a batch")
near(call_part("contrast:between"), 2 * call_part(paste0("item:", ids[1])),
     "independent calls remain in a between-batch contrast")
expect(call_part(paste0("item:", ids[1])) > 0, "absolute error retains shared-call variation")
expect(call_part("aggregate:concentrated") > call_part("aggregate:spread"),
       "weighted corpus error depends on batch grouping")
rater_part <- subset(projection$source_contributions, target == "aggregate:spread" &
  source == "rater" & outcome == "score")$variance
near(rater_part, fit$covariance_components$rater[1, 1] / 4,
     "common rater variation does not vanish from a corpus mean")

# Changed counts keep grouping and fitted components, with dense confirmation.
projected <- gt_batch_reliability(fit, counts = c(rater = 2, run = 5),
  contrasts = list(within = within, between = between), aggregate = spread)
reference <- dense_reference(fit, projected$counts, between, c(1, 0))
near(subset(projected$summary, target == "contrast:between" & outcome == "score")$error_variance,
     reference[["error"]], "future counts agree with new full observation covariance")
expect(identical(projected$batch_size, projection$batch_size) && projected$annotations_per_item == 10,
       "count projection cannot change batch size")

# A zero shared-call covariance reduces absolute item Phi to the existing
# fully random coefficient. This parameter fixture tests a mathematical limit.
zero <- fit
zero$covariance_components$Call[] <- 0
plain <- zero
plain$design$batch <- NULL
plain$design$batch_model <- NULL
plain$covariance_components$Call <- NULL
ordinary <- gt_reliability(plain)
zero_projection <- gt_batch_reliability(zero)
near(zero_projection$summary$coefficient[1:2], ordinary$per_trait$Phi,
     "zero-call limit equals ordinary absolute reliability")

# The projection must use a recorded layout, not current retained row order.
shuffled <- fit
shuffled$data <- fit$data[sample(nrow(fit$data)), ]
near(gt_batch_reliability(shuffled)$summary$error_variance,
     gt_batch_reliability(fit)$summary$error_variance, "retained-row permutation invariance")
renamed <- fit
new_ids <- rev(paste0("renamed_", seq_along(ids)))
renamed$design$batch_model$item_levels <- new_ids
renamed$data$item <- new_ids[match(renamed$data$item, ids)]
renamed$design$batch_model$item_batches <- paste0("group_", renamed$design$batch_model$item_batches)
near(gt_batch_reliability(renamed)$summary$error_variance,
     gt_batch_reliability(fit)$summary$error_variance, "item and batch label invariance")

# A second fit with shuffled observations proves that recorded call membership
# is persisted at fitting time, including with data and model retention disabled.
lean_control <- gt_control(gaussian = list(extra_tries = 2L, retry_seed = 439L, check_hessian = FALSE),
                           retain = list(data = FALSE, model = FALSE))
lean <- gt_fit(data[sample(nrow(data)), ], c("score", "second"), design,
  covariance = c(item = "unstructured", Call = "unstructured"), residual = "diagonal", control = lean_control)
lean_projection <- gt_batch_reliability(lean, contrasts = list(within = within, between = between))
for (target in c("contrast:within", "contrast:between"))
  near(lean_projection$summary$error_variance[lean_projection$summary$target == target &
         lean_projection$summary$outcome == "score"],
       projection$summary$error_variance[projection$summary$target == target &
         projection$summary$outcome == "score"],
       "recorded-call shuffled refit with no retained observations", tolerance = 1e-5)
expect(is.null(lean$data) && is.null(lean$model), "projection works without retained outcomes or backend model")

# Distinct doubles can have identical default character representations. Fit
# them through the public API, then address targets using the returned keys.
numeric_ids <- 1e15 + seq_along(ids) - 1
expect(anyDuplicated(as.character(numeric_ids)) > 0L && !anyDuplicated(numeric_ids),
       "numeric-ID regression has distinct values with colliding display strings")
numeric_data <- data
numeric_data$item <- numeric_ids[match(data$item, ids)]
numeric_fit <- gt_fit(numeric_data, c("score", "second"), design,
  covariance = c(item = "unstructured", Call = "unstructured"), residual = "diagonal", control = control)
expect(isTRUE(numeric_fit$numerically_accepted), "large-numeric-ID reference fit is accepted")
numeric_projection <- gt_batch_reliability(numeric_fit)
numeric_keys <- numeric_projection$layout$item
expect(length(unique(numeric_keys)) == length(ids) && identical(as.numeric(numeric_keys), numeric_ids),
       "numeric item keys preserve every original double exactly")
numeric_within <- stats::setNames(c(1, -1), numeric_keys[c(1, 2)])
numeric_between <- stats::setNames(c(1, -1), numeric_keys[c(1, 7)])
numeric_spread <- stats::setNames(rep(1 / 6, 6), numeric_keys[c(1, 2, 7, 8, 13, 19)])
numeric_targets <- list(within = numeric_within, between = numeric_between)
numeric_projection <- gt_batch_reliability(numeric_fit,
  contrasts = numeric_targets, aggregate = list(spread = numeric_spread), score = composite)
for (target in c("contrast:within", "contrast:between", "aggregate:spread"))
  near(numeric_projection$summary$coefficient[numeric_projection$summary$target == target],
       projection$summary$coefficient[projection$summary$target == target],
       "numeric target weights preserve the character-ID projection", tolerance = 1e-5)
numeric_study <- gt_batch_dstudy(numeric_fit, data.frame(rater = c(2, 4), run = c(3, 5)),
  contrasts = numeric_targets, aggregate = list(spread = numeric_spread), score = composite)
character_study <- gt_batch_dstudy(fit, data.frame(rater = c(2, 4), run = c(3, 5)),
  contrasts = list(within = within, between = between), aggregate = list(spread = spread), score = composite)
near(numeric_study$summary$error_variance, character_study$summary$error_variance,
     "numeric-ID D studies agree with the equivalent character-ID fit", tolerance = 1e-5)
numeric_shuffled <- numeric_fit
numeric_shuffled$data <- numeric_fit$data[sample(nrow(numeric_data)), ]
near(gt_batch_reliability(numeric_shuffled, contrasts = numeric_targets)$summary$coefficient,
     gt_batch_reliability(numeric_fit, contrasts = numeric_targets)$summary$coefficient,
     "typed retained membership is invariant to row permutation")
numeric_lean <- gt_fit(numeric_data[sample(nrow(numeric_data)), ], c("score", "second"), design,
  covariance = c(item = "unstructured", Call = "unstructured"), residual = "diagonal", control = lean_control)
expect(isTRUE(numeric_lean$numerically_accepted) && is.null(numeric_lean$data),
       "large-numeric-ID shuffled fit is accepted without retained observations")
numeric_lean_projection <- gt_batch_reliability(numeric_lean,
  contrasts = numeric_targets, aggregate = list(spread = numeric_spread), score = composite)
for (target in c("contrast:within", "contrast:between", "aggregate:spread")) {
  selected <- numeric_projection$summary$target == target
  selected_lean <- numeric_lean_projection$summary$target == target
  near(numeric_lean_projection$summary$coefficient[selected_lean],
       numeric_projection$summary$coefficient[selected],
       "numeric weighted targets survive shuffled fitting without observations", tolerance = 1e-5)
}

# Projection fixtures isolate key formatting from numerical fitting. Character
# and factor labels stay unchanged; numeric keys are independent of print
# options, preserve fractional doubles and identify either signed zero as 0.
check_keys <- function(item_values, expected) {
  renamed <- fit
  renamed$design$batch_model$item_levels <- item_values
  renamed$data$item <- item_values[match(data$item, ids)]
  result <- gt_batch_reliability(renamed)
  if (!is.null(expected))
    expect(identical(result$layout$item, expected), "projection exposes stable item keys")
  near(result$summary$coefficient, gt_batch_reliability(fit)$summary$coefficient,
       "key formatting cannot change projected coefficients")
  result$layout$item
}
check_keys(ids, ids)
check_keys(factor(ids, levels = rev(ids)), ids)
check_keys(seq_along(ids), as.character(seq_along(ids)))
fractional_ids <- c(-0, .1, 1 + .Machine$double.eps, 1 + 2 * .Machine$double.eps,
                    seq_len(length(ids) - 4L) + 2)
fractional_keys <- check_keys(fractional_ids, sprintf("%.17g", replace(fractional_ids, 1L, 0)))
expect(identical(as.numeric(fractional_keys), fractional_ids) && fractional_keys[1L] == "0",
       "fractional and signed-zero keys preserve R item identity")
# The keys are opaque strings, even at floating-point extremes. In particular,
# R's no-long-double parser need not recover extreme values exactly, and the
# projection must never need that conversion to preserve identity.
smallest <- .Machine$double.xmin * .Machine$double.eps
extreme_ids <- c(0, smallest, -smallest, .Machine$double.xmin, -.Machine$double.xmin,
                 .Machine$double.xmax, -.Machine$double.xmax, .1,
                 seq_len(length(ids) - 8L))
extreme_keys <- check_keys(extreme_ids, NULL)
expect(length(extreme_keys) == length(extreme_ids) && !anyDuplicated(extreme_keys),
       "extreme finite numeric identifiers have distinct keys without reparsing")
local({
  previous <- options(digits = 3, scipen = -9, OutDec = ",")
  on.exit(options(previous))
  expect(identical(gt_batch_reliability(numeric_fit)$layout$item, numeric_keys),
         "large numeric keys ignore print options")
  check_keys(fractional_ids, fractional_keys)
})
local({
  previous <- Sys.getlocale("LC_NUMERIC")
  on.exit(suppressWarnings(Sys.setlocale("LC_NUMERIC", previous)))
  # This locale is optional on the test host; do not change the process locale
  # permanently, and always exercise the option-independent contract above.
  alternative <- suppressWarnings(Sys.setlocale("LC_NUMERIC", "de_DE.UTF-8"))
  if (nzchar(alternative)) check_keys(fractional_ids, fractional_keys)
})
bad_numeric <- numeric_fit
bad_numeric$data$item[bad_numeric$data$item == numeric_ids[1L]] <- numeric_ids[1L] + .5
expect_error(gt_batch_reliability(bad_numeric), "retained data and recorded item layout disagree")
bad_numeric <- numeric_fit
bad_numeric$data$item <- as.character(bad_numeric$data$item)
expect_error(gt_batch_reliability(bad_numeric), "complete balanced panel")
bad_labels <- fit
decimal_ids <- seq_along(ids) / 10
bad_labels$design$batch_model$item_levels <- decimal_ids
bad_labels$data$item <- as.character(decimal_ids[match(data$item, ids)])
expect(length(unique(bad_labels$data$item)) == length(decimal_ids) &&
         setequal(bad_labels$data$item, decimal_ids),
       "coercive membership alone would accept changed retained identifier types")
expect_error(gt_batch_reliability(bad_labels), "retained data and recorded item layout disagree")
for (invalid_ids in list(replace(numeric_ids, 2L, numeric_ids[1L]),
                        replace(numeric_ids, 2L, NA_real_),
                        replace(numeric_ids, 2L, Inf),
                        c(0, -0, numeric_ids[-c(1L, 2L)]),
                        as.list(numeric_ids))) {
  bad_numeric <- numeric_fit
  bad_numeric$design$batch_model$item_levels <- invalid_ids
  expect_error(gt_batch_reliability(bad_numeric), "missing, ambiguous, or inconsistent item identifiers")
}
report <- gt_report(fit)
raw_report <- serialize(report, NULL)
expect(!length(grepRaw("PRIVATE_ITEM_", raw_report, fixed = TRUE)), "portable report excludes item layout identifiers")
html <- tempfile(fileext = ".html")
gt_export_report(report, html)
expect(!any(grepl("PRIVATE_ITEM_", readLines(html, warn = FALSE), fixed = TRUE)),
       "portable HTML excludes item layout identifiers")
unlink(html)

# The grid preserves every candidate and produces the same explicit targets.
grid <- data.frame(rater = c(2, 4, 2), run = c(3, 5, 3))
study <- gt_batch_dstudy(fit, grid, contrasts = list(between = between))
expect(nrow(study$grid) == 3 && identical(study$summary$design_id,
  rep(seq_len(3), each = (length(ids) + 1) * 2)), "D study preserves repeated candidates")
near(subset(study$summary, design_id == 1)$error_variance,
     subset(study$summary, design_id == 3)$error_variance, "duplicate grid rows agree")
expect(is.data.frame(as.data.frame(projection)) && is.data.frame(as.data.frame(study)), "tabular methods available")
expect(!projection$uncertainty$available && !study$uncertainty$available,
       "new projections never claim estimated sampling intervals")

# Flat exports retain allocations and their interpretation without attributes.
# Repeated allocations, outcomes, and targets must not multiply rows or turn
# design_id into a position-based recycling join.
export_study <- gt_batch_dstudy(fit, grid, contrasts = list(within = within, between = between),
  aggregate = list(concentrated = concentrated, spread = spread), score = composite)
export_study$summary <- export_study$summary[rev(seq_len(nrow(export_study$summary))), ]
export <- as.data.frame(export_study)
expect(identical(export[, names(export_study$summary)], export_study$summary),
       "flat export preserves every summary row in its supplied order")
expect(identical(attr(export, "grid"), export_study$grid) &&
       identical(attr(export, "interpretation"), export_study$interpretation) &&
       identical(attr(export, "uncertainty"), export_study$uncertainty),
       "flat export retains original attributes for compatibility")
csv <- tempfile(fileext = ".csv")
utils::write.csv(export, csv, row.names = FALSE)
roundtrip <- utils::read.csv(csv, stringsAsFactors = FALSE)
unlink(csv)
expect(nrow(roundtrip) == 3 * (length(ids) + 4) * 3 &&
       identical(roundtrip$design_id, export_study$summary$design_id) &&
       identical(roundtrip$target, export_study$summary$target) &&
       identical(roundtrip$outcome, export_study$summary$outcome),
       "CSV retains multiple targets, outcomes, and repeated candidate rows in order")
near(roundtrip$allocation_rater, c(2, 4, 2)[roundtrip$design_id], "CSV joins rater allocation by design_id")
near(roundtrip$allocation_run, c(3, 5, 3)[roundtrip$design_id], "CSV joins run allocation by design_id")
near(roundtrip$annotations_per_item, c(6, 20, 6)[roundtrip$design_id], "CSV annotation counts")
near(roundtrip$projected_calls, c(24, 80, 24)[roundtrip$design_id], "CSV call counts for four fixed batches")
expect(all(roundtrip$batch_size == 6 & roundtrip$pilot_items == 24) &&
       identical(roundtrip$extrapolated, roundtrip$design_id == 2L) &&
       all(roundtrip$scale == "observed"), "CSV retains fixed layout and extrapolation context")
expect(all(!roundtrip$uncertainty_available) &&
       all(roundtrip$uncertainty_reason == export_study$uncertainty$reason) &&
       all(roundtrip$interpretation == export_study$interpretation),
       "CSV retains point-only uncertainty and interpretation")
partial <- as.data.frame(gt_batch_dstudy(fit, data.frame(rater = c(1, 3))))
expect(all(partial$allocation_run == 3), "flat export includes unspecified facets at fitted counts")

# A valid exporter must keep arbitrary facet names separate from its own fields.
# This table fixture exercises naming without a numerically redundant refit.
collision <- export_study
names(collision$grid) <- names(collision$observed_counts) <- c("design_id", "batch_size")
collision_export <- as.data.frame(collision, row.names = paste0("row", seq_len(nrow(collision$summary))))
expect(!anyDuplicated(names(collision_export)) &&
       identical(collision_export$design_id, collision$summary$design_id) &&
       all(collision_export$batch_size == 6) &&
       identical(rownames(collision_export), paste0("row", seq_len(nrow(collision$summary)))),
       "prefixed allocation fields cannot overwrite identifiers or layout context")
near(collision_export$allocation_design_id, roundtrip$allocation_rater, "identifier-named facet stays distinct")
near(collision_export$allocation_batch_size, roundtrip$allocation_run, "batch-size-named facet stays distinct")

bad <- fit
bad$numerically_accepted <- FALSE
expect_error(gt_batch_reliability(bad), "numerically accepted")
bad$numerically_accepted <- NA
expect_error(gt_batch_reliability(bad), "numerically accepted")
bad <- fit
bad$design$batch_model$item_levels <- NULL
expect_error(gt_batch_reliability(bad), "layout cannot be guessed")
bad <- fit
bad$families[[1]]$family <- "binary"
expect_error(gt_batch_reliability(bad), "Gaussian outcomes only")
expect_error(gt_batch_reliability(plain), "fitted shared Call effect")
expect_error(gt_batch_reliability(fit, counts = c(batch_size = 3)), "batch size and item count cannot change")
expect_error(gt_batch_reliability(fit, counts = c(item = 12)), "batch size and item count cannot change")
expect_error(gt_batch_reliability(fit, counts = c(rater = 0)), "positive integer")
expect_error(gt_batch_reliability(fit, counts = c(rater = 2^53)), "below 2^53")
expect_error(gt_batch_reliability(fit, contrasts = concentrated), "sum to zero")
expect_error(gt_batch_reliability(fit, contrasts = stats::setNames(c(1e-12, 1e-12), ids[1:2])), "sum to zero")
expect_error(gt_batch_reliability(fit, contrasts = stats::setNames(c(1e200, -1e200), ids[1:2])),
             "finite numerical projection scale")
expect_error(gt_batch_reliability(fit, score = gt_score(c(score = 1e200, second = 1))),
             "finite numerical projection scale")
expect_error(gt_batch_reliability(fit, contrasts = stats::setNames(c(1e-300, -1e-300), ids[1:2])),
             "finite numerical projection scale")
# Reject the output size before validating or materializing an oversized target list.
many <- stats::setNames(rep(list(NULL), 100001), paste0("target", seq_len(100001)))
expect_error(gt_batch_reliability(fit, contrasts = many), "one million")
expect_error(gt_batch_dstudy(fit, data.frame(rater = rep(2, 1000)),
  contrasts = stats::setNames(rep(list(within), 100), paste0("pair", seq_len(100)))), "one million")

expect_error(gt_batch_reliability(fit, aggregate = within), "nonnegative and sum to one")
expect_error(gt_batch_reliability(fit, aggregate = c(unknown_item = 1)), "fitted item IDs")
expect_error(gt_batch_dstudy(fit, data.frame(rater = rep(2, 1001))), "at most 1000")
cat("PASS: batch projections match dense covariance contractions, preserve grouping, and guard targets.\n")
