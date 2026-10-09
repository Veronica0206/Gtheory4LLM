# Source checks: bounded enumeration, independent dominance, uncertainty and cost accounting.
source("load_functions.R")
source("R/planning.R")
near <- function(a, b, label, tolerance = 1e-10) {
  if (!isTRUE(all.equal(unname(a), unname(b), check.attributes = FALSE, tolerance = tolerance)))
    stop("FAILED: ", label)
}
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  if (!inherits(error, "error") || !grepl(pattern, conditionMessage(error), fixed = TRUE))
    stop("Expected error containing: ", pattern)
}

# Independent finite-population averaging fixture: the item x rater source
# makes more raters particularly useful, while occasion main variance only
# affects the absolute comparison. These are exact supplied covariances.
panel <- expand.grid(item = 1:8, rater = 1:3, occasion = 1:2)
panel$y <- seq_len(nrow(panel))
design <- .gt_resolve_design(panel, gt_design("item", c("rater", "occasion")), "gaussian")
source_variances <- c(item = 2, rater = .4, occasion = .2, "item:rater" = 1.2,
                      "item:occasion" = .1, "rater:occasion" = .3, Residual = .6)
fit <- structure(list(data = panel, outcomes = "y", design = design,
  covariance_components = lapply(source_variances, matrix), families = list(y = gt_family()),
  estimator = "REML", converged = TRUE, numerically_accepted = TRUE,
  diagnostics = list(test_fixture = TRUE)), class = "gt_fit")
price <- function(d) list(
  costs = data.frame(tokens = .05 * d$total_annotations,
                     evaluator_setup = 2 * d$allocation_rater,
                     human_review = rep(3, nrow(d))),
  resources = data.frame(request_count = d$total_annotations,
                         review_minutes = rep(6, nrow(d))),
  assumptions = "Every annotation has the same expected token cost; setup differs by rater count.")
plan <- function(..., object = fit) gt_plan(object, ..., currency = "USD", cost_date = "2026-10-09",
                                           study_items = 20, target = .8)
original <- serialize(fit, NULL)
grid <- list(rater = 1:4, occasion = 1:3)
x <- plan(candidates = grid, cost = price)
tab <- as.data.frame(x)
stopifnot(nrow(tab) == 12L, identical(x$provenance$candidate_source, "cartesian_grid"),
          identical(x$provenance$fixed_facets, character()), identical(original, serialize(fit, NULL)),
          all(tab$study_items == 20), all(tab$annotations_per_item == tab$allocation_rater * tab$allocation_occasion),
          all(tab$total_annotations == 20 * tab$annotations_per_item),
          all(tab$total_cost == rowSums(x$cost_breakdown)))
manual_candidates <- data.frame(rater = rep(1:4, 3), occasion = rep(1:3, each = 4))
stopifnot(identical(x$allocations, manual_candidates))
manual_relative <- 1.2 / manual_candidates$rater + .1 / manual_candidates$occasion +
  .6 / (manual_candidates$rater * manual_candidates$occasion)
manual_absolute <- manual_relative + .4 / manual_candidates$rater + .2 / manual_candidates$occasion +
  .3 / (manual_candidates$rater * manual_candidates$occasion)
near(tab$relative_error, manual_relative, "relative error from separately enumerated fixture")
near(tab$absolute_error, manual_absolute, "absolute error from separately enumerated fixture")
near(tab$Erho2, 2 / (2 + manual_relative), "relative coefficients")
near(tab$Phi, 2 / (2 + manual_absolute), "absolute coefficients")
near(tab$total_cost, manual_candidates$rater * manual_candidates$occasion +
       2 * manual_candidates$rater + 3, "heterogeneous expected total cost")
near(tab$extra_cost, tab$total_cost - 6, "baseline cost difference")
near(tab$relative_error_reduction, manual_relative[1] - manual_relative, "relative error reductions")
near(tab$absolute_error_reduction, manual_absolute[1] - manual_absolute, "absolute error reductions")
near(tab$Erho2_gain, tab$Erho2 - tab$Erho2[1], "coefficient differences")
for (i in seq_len(nrow(tab))) {
  sources <- subset(x$source_contributions, design_id == i)
  near(sum(sources$relative_error), tab$relative_error[i], "source relative-error accounting")
  near(sum(sources$absolute_error_reduction), tab$absolute_error_reduction[i], "source benefit accounting")
}
cat("PASS: bounded enumeration, separate item/annotation counts, supplied costs and source-level marginal benefits.\n")

# An independent all-pairs definition checks the optimized Pareto implementation.
# It deliberately includes equal cost and equal performance, duplicates, and
# constraints excluding a would-be dominator.
brute_pareto <- function(cost, performance, feasible) {
  vapply(seq_along(cost), function(i) {
    if (isFALSE(feasible[i])) return(FALSE)
    if (is.na(feasible[i]) || !is.finite(performance[i])) return(NA)
    competitors <- which(feasible & is.finite(performance))
    !any(cost[competitors] <= cost[i] & performance[competitors] >= performance[i] &
           (cost[competitors] < cost[i] | performance[competitors] > performance[i]))
  }, logical(1))
}
near(tab$pareto, brute_pareto(tab$total_cost, tab$Erho2, tab$feasible), "all-pairs dominance")
near(.gt_plan_pareto(1:15, 1:15 / 16, rep(TRUE, 15)), rep(TRUE, 15),
     "strictly improving frontier across at least twelve distinct costs")
set.seed(188)
for (iteration in seq_len(20)) {
  costs <- sample(0:12, 50, replace = TRUE)
  performance <- sample(c(seq(0, 1, .1), NA), 50, replace = TRUE)
  feasible <- sample(c(TRUE, FALSE, NA), 50, replace = TRUE)
  near(.gt_plan_pareto(costs, performance, feasible), brute_pareto(costs, performance, feasible),
       "all-pairs randomized exact-tie dominance")
}
tie_candidates <- data.frame(rater = c(4, 4, 5, 5), occasion = c(2, 2, 2, 2))
ties <- plan(candidates = tie_candidates, cost = data.frame(evaluation = c(5, 5, 4, 8)),
  constraints = function(d) data.frame(in_scope = c(TRUE, TRUE, FALSE, TRUE)))
stopifnot(identical(ties$results$minimum_cost, c(TRUE, TRUE, FALSE, FALSE)),
          identical(ties$results$pareto, c(TRUE, TRUE, FALSE, TRUE)),
          nrow(ties$results) == 4L, nrow(ties$constraint_checks) == 4L,
          identical(ties$results$constraint_reason[3], "Failed: in_scope"))
limited <- plan(candidates = grid, cost = price,
  constraints = function(d) data.frame(budget = d$total_cost <= 15,
                                       requests = d$resource_request_count <= 200))
near(limited$results$pareto,
     brute_pareto(tab$total_cost, tab$Erho2, tab$total_cost <= 15 & tab$resource_request_count <= 200),
     "cost/resource constraints before dominance")
uncertain_constraint <- plan(candidates = tie_candidates, cost = data.frame(cost = rep(5, 4)),
  constraints = data.frame(recorded = c(TRUE, NA, FALSE, TRUE)), baseline = 3)
stopifnot(is.na(uncertain_constraint$results$eligible[2]),
          is.na(uncertain_constraint$results$minimum_cost[2]),
          is.na(uncertain_constraint$results$pareto[2]),
          identical(uncertain_constraint$provenance$baseline_id, 3),
          grepl("Unknown", uncertain_constraint$results$constraint_reason[2]))
cat("PASS: independent exhaustive dominance, exact ties, excluded/unknown constraints and explicit baseline.\n")

# A missing interval never becomes a point estimate or zero uncertainty.
no_bounds <- plan(candidates = grid, cost = price, screening = "lower")
stopifnot(all(is.na(no_bounds$results$screening_value)),
          all(is.na(no_bounds$results$meets_target)), all(is.na(no_bounds$results$minimum_cost)),
          all(!no_bounds$results$screening_available), all(nzchar(no_bounds$results$screening_reason)),
          all(is.finite(no_bounds$results$Erho2)))
# Positive-definite supplied component curvature gives an independent, analytic
# interval fixture. It is checked against the parent reliability interval, and
# a target between its point and bound distinguishes the two screening rules.
curvature <- fit
curvature$uncertainty <- list(available = TRUE, reason = NA_character_,
  entries = data.frame(component = names(source_variances), row = "y", column = "y"),
  entry_covariance = diag(rep(.01, length(source_variances))), method = "fixture curvature",
  boundary_components = character(), restricted_to_interior = FALSE,
  fixed_components = character(), fixed_component_kinds = character())
ci <- gt_reliability(curvature, counts = c(rater = 3, occasion = 2))
cutoff <- mean(c(ci$per_trait$Erho2, ci$per_trait$Erho2_lower))
run_screen <- function(screening) gt_plan(curvature, data.frame(rater = 3, occasion = 2),
  cost = data.frame(total = 1), currency = "USD", cost_date = as.Date("2026-10-09"),
  study_items = 20, target = cutoff, screening = screening)
point <- run_screen("point"); lower <- run_screen("lower")
stopifnot(isTRUE(point$results$minimum_cost), isFALSE(lower$results$minimum_cost),
          lower$results$screening_value == ci$per_trait$Erho2_lower,
          isTRUE(lower$results$screening_available))
latent <- fit
latent$families <- list(y = gt_family("binary", "probit", c("no", "yes")))
latent$covariance_components$Residual <- NULL
latent_plan <- plan(candidates = grid, cost = price, object = latent, scale = "latent", screening = "lower")
stopifnot(all(is.na(latent_plan$results$meets_target)),
          all(grepl("point estimates only", latent_plan$results$screening_reason)))
undefined <- fit
undefined$covariance_components <- lapply(undefined$covariance_components, function(x) x * 0)
unknown <- plan(candidates = grid, cost = price, object = undefined)
stopifnot(all(is.na(unknown$results$minimum_cost)), all(is.na(unknown$results$pareto)),
          all(grepl("undefined", unknown$results$screening_reason)))
cat("PASS: unavailable discrete/Gaussian bounds, undefined coefficients and distinct point/lower-bound screening.\n")

# Fixed instrumentation is chosen once, never optimized. Study item count is
# costing volume only; no pilot precision or human-review benefit is fabricated.
fixed <- plan(candidates = data.frame(rater = 2:4), cost = price, fixed = "occasion")
stopifnot(all(fixed$allocations$occasion == 2), identical(fixed$provenance$fixed_facets, "occasion"))
expect_error(plan(candidates = data.frame(occasion = 1:3), cost = price, fixed = "occasion"),
             "fixed facet's observed levels")
changed_volume <- gt_plan(fit, grid, price, currency = "USD", cost_date = "2026-10-09",
                          study_items = 200, target = .8)
near(changed_volume$results$Erho2, tab$Erho2, "study item count cannot improve D-study coefficients")
near(changed_volume$results$Erho2_lower, tab$Erho2_lower, "no manufactured pilot precision")
review <- function(d) data.frame(human_review = 100 * d$total_annotations)
expensive <- plan(candidates = grid, cost = review)
near(expensive$results$Phi, tab$Phi, "review costs alone cannot alter reliability")
failed <- fit; failed$numerically_accepted <- FALSE
expect_error(plan(candidates = grid, cost = price, object = failed), "numerically converged fit")
batched <- fit
batched$design$batch <- gt_batch(2)
batched$design$batch_model <- list(modelled = TRUE)
expect_error(plan(candidates = grid, cost = price, object = batched), "does not yet project modelled batch")
batched$design$batch_model <- list(modelled = FALSE, reason = "fixture unsupported layout")
unmodelled <- plan(candidates = grid, cost = price, object = batched)
stopifnot(all(unmodelled$results$batch_status == "declared_not_modelled"),
          any(grepl("but not modelled", capture.output(print(unmodelled)))))
cat("PASS: fixed-universe guards and costing volume are separate from statistical precision.\n")

# Multivariate composites retain their declared score, including a negative
# weight. Cross-outcome source covariance must enter both total and source
# explanations; costs cannot choose a different weighting.
joint <- fit
joint$outcomes <- c("y", "z")
joint$data$z <- -joint$data$y
joint$families <- list(y = gt_family(), z = gt_family())
joint$covariance_components <- lapply(source_variances, function(v)
  matrix(c(v, .2 * v, .2 * v, 1.5 * v), 2, dimnames = list(joint$outcomes, joint$outcomes)))
weights <- gt_score(c(z = -.5, y = 1))
composite <- plan(candidates = grid, cost = price, object = joint, kind = "composite", score = weights)
# [1, -.5] V [1, -.5]' = (1 + .375 - .2) times the scalar component.
near(composite$results$relative_error, 1.175 * manual_relative,
     "composite error includes off-diagonal covariance with signed weights")
near(composite$results$Erho2, tab$Erho2, "common component scaling preserves composite reliability")
stopifnot(nrow(composite$all_coefficients) == 36L,
          identical(composite$provenance$score$weights, weights$weights))
expect_error(plan(candidates = grid, cost = price, object = joint), "Specify outcome explicitly")
cat("PASS: multivariate composite score covariance, all outcomes and explicit outcome selection.\n")

expect_error(plan(candidates = list(rater = 1:100, occasion = 1:100), cost = price, max_candidates = 10),
             "Cartesian candidate grid")
expect_error(plan(candidates = data.frame(rater = 1.5), cost = price), "positive finite integers")
expect_error(plan(candidates = data.frame(item = 3), cost = price), "named facet columns")
expect_error(plan(candidates = data.frame(rater = 2^52), cost = price), "exactly representable")
expect_error(plan(candidates = grid, cost = price, baseline = 13), "baseline must identify")
expect_error(plan(candidates = grid, cost = data.frame(cost = -seq_len(12))), "finite nonnegative")
expect_error(plan(candidates = grid, cost = data.frame(cost = rep(NA_real_, 12))), "finite nonnegative")
expect_error(plan(candidates = grid, cost = data.frame(cost = rep(Inf, 12))), "finite nonnegative")
expect_error(plan(candidates = grid, cost = data.frame(cost = 1)), "one row per candidate")
expect_error(plan(candidates = grid, cost = price, constraints = rep(1, 12)), "logical")
expect_error(plan(candidates = grid, cost = function(d) list(costs = data.frame(cost = rep(1, 12)),
  resources = data.frame(request_count = rep(-1, 12)))), "finite nonnegative")
expect_error(gt_plan(fit, grid, price, "USD", "2026-02-30", 20, .8), "valid date")
expect_error(gt_plan(fit, grid, price, "usd", "2026-10-09", 20, .8), "currency")
expect_error(plan(candidates = grid, cost = price, outcome = "missing"), "No results match")
stopifnot(identical(original, serialize(fit, NULL)))
cat("PASS: malformed costs, resources, constraints, dates, grids, bounds and rejected fits fail explicitly.\n")
cat("All cost-aware planning tests passed.\n")
