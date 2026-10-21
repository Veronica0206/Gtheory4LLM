# Categorical planning: real small fits, declared target semantics and cost accounting.
source("load_functions.R")
expect <- function(ok, message) if (!isTRUE(ok)) stop(message)
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  expect(inherits(error, "error") && grepl(pattern, conditionMessage(error), fixed = TRUE),
         paste("Expected refusal containing", pattern))
}
data <- expand.grid(item = seq_len(12L), rater = seq_len(3L))
data$binary <- as.integer((data$item + data$rater) %% 2)
data$nominal <- factor(c("a", "b", "c")[(data$item + data$rater) %% 3 + 1L],
                       levels = c("a", "b", "c"))
families <- list(binary = gt_family("binary", "logit"),
                 nominal = gt_family("categorical", levels = c("a", "b", "c")))
fit <- gt_fit(data, c("binary", "nominal"), gt_design("item", "rater", random = c("item", "rater")),
  families, control = gt_control(discrete = list(engine = "sparse", optimizer = "nlminb",
    fixed_covariance = list(item = matrix(0, 3L, 3L), rater = matrix(0, 3L, 3L)))))
expect(isTRUE(fit$numerically_accepted), "The planning fixture is an accepted joint fit")
original <- serialize(fit, NULL)
cost_calls <- 0L
cost <- function(x) {
  cost_calls <<- cost_calls + 1L
  expect(identical(attr(x, "allocation_columns"), c(allocation_rater = "rater")),
         "Cost callbacks retain the allocation-column map")
  list(costs = data.frame(labels = 0.1 * x$total_annotations),
       resources = data.frame(requests = x$total_annotations))
}
arguments <- list(fit = fit, candidates = data.frame(rater = c(2, 2, 3, 4)), cost = cost,
  currency = "USD", cost_date = "2026-10-21", study_items = 20, target = 0,
  coefficient = "observed_score", outcome = "binary", scale = "observed",
  constraints = data.frame(allowed = c(TRUE, TRUE, FALSE, NA)),
  integration = list(seed = 821, n_items = 8, replications = 4))
plan <- function(...) {
  overrides <- list(...)
  actual <- arguments
  for (name in names(overrides)) actual[name] <- overrides[name]
  if ("integration" %in% names(overrides))
    actual$integration <- utils::modifyList(arguments$integration, overrides$integration)
  do.call(gt_plan, actual)
}
set.seed(423)
previous <- .Random.seed
answer <- plan()
table <- as.data.frame(answer)
expect(identical(previous, .Random.seed) && identical(original, serialize(fit, NULL)),
       "Planning preserves RNG and fitted model")
expect(cost_calls == 1L && all(table$estimate == 0) && all(table$available),
       "A single cost callback and the zero-universe-variance score oracle")
expect(identical(table$minimum_cost, c(TRUE, TRUE, FALSE, NA)) &&
       identical(table$pareto, c(TRUE, TRUE, FALSE, NA)), "Cost ties and unknown feasibility are retained")
expect(all(table$total_cost == 0.1 * table$total_annotations) &&
       all(table$total_annotations == 20 * table$allocation_rater) &&
       all(table$annotations_per_item == table$allocation_rater), "Costs retain separate study and integration sizes")
expect(answer$provenance$total_simulated_rows == 2 * 8 * sum(c(2, 2, 3, 4)) * 4 &&
       !any(c("Erho2", "Phi", "relative_error", "absolute_error") %in% names(table)) &&
       nrow(answer$source_contributions) == 0L, "Work and target-specific output are explicit")
expect(all(table$target_gain == 0) && all(table$mc_se == 0), "Baseline gains and integration errors are separate")

vector <- plan(coefficient = "category_vector", outcome = "nominal")
expect(all(as.data.frame(vector)$estimate == 0), "Unordered-label vector target does not impose numeric scores")
decision <- plan(coefficient = "decision_agreement", outcome = "nominal", scale = "decision")
decision_table <- as.data.frame(decision)
expect(decision_table$estimate[1] == decision_table$estimate[2] &&
       all(is.finite(decision_table$decision_diversity)) &&
       all(decision_table$estimate >= 0 & decision_table$estimate <= 1),
       "Decision target retains diversity, bounds and exact duplicate allocations")

expect_error(plan(screening = "lower"), "point screening only")
expect_error(plan(scale = "latent"), "explicit scale")
expect_error(plan(kind = "composite"), "no composite")
expect_error(plan(fixed = "rater"), "fixed facets")
expect_error(plan(outcome = c("binary", "nominal")), "exactly one")
expect_error(plan(coefficient = "observed_score", outcome = "nominal"), "category_vector")
expect_error(do.call(gt_plan, c(arguments[names(arguments) != "integration"], list(integration = list()))),
             "explicit integration seed")
expect_error(plan(integration = list(unrecognized = 1)), "uniquely name")
single_response <- plan(candidates = list(rater = 1), constraints = NULL)
expect(as.data.frame(single_response)$annotations_per_item == 1,
       "A future categorical allocation may contain one facet level")
expect_error(plan(integration = list(max_rows = 1)), "max_rows")
expect_error(plan(candidates = list(rater = c(3, 4)),
  integration = list(n_items = 100, replications = 10000)), "across all candidate panel pairs")

# An undefined target remains a row with an explanation, not a zero standard error.
degenerate <- fit
degenerate$means[["binary"]] <- 1000
missing <- plan(fit = degenerate)
missing_table <- as.data.frame(missing)
expect(all(!missing_table$screening_available) && all(is.na(missing_table$meets_target)) &&
       all(!is.na(missing_table$screening_reason)) && all(is.na(missing_table$mc_se)),
       "Undefined categorical targets preserve missing screening and reasons")

# Calls retain observed membership and item count, even though facet counts can change.
data$call_id <- paste(ceiling(data$item / 4), data$rater, sep = "-")
call_fit <- gt_fit(data, c("binary", "nominal"),
  gt_design("item", "rater", random = c("item", "rater"), batch = gt_batch(4, id = "call_id")),
  families, control = gt_control(discrete = list(engine = "sparse", optimizer = "nlminb",
    fixed_covariance = list(item = matrix(0, 3L, 3L), rater = matrix(0, 3L, 3L),
                            Call = matrix(0, 3L, 3L)))))
call_plan <- plan(fit = call_fit, study_items = 12, integration = list(n_items = 12))
expect(all(as.data.frame(call_plan)$batch_status == "modelled") &&
       all(as.data.frame(call_plan)$study_items == 12), "Call planning preserves layout metadata")
expect_error(plan(fit = call_fit, study_items = 20), "fitted item count and layout")
expect_error(plan(fit = call_fit, study_items = 12, integration = list(n_items = 8)),
             "fitted item count and layout")
cat("PASS: categorical costs, target selection, missing values, bounds, RNG and fixed-call contracts.\n")
