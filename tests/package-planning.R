# Installed interface: accepted numerical fit, public extraction and user cost model.
library(Gtheory4LLM)

set.seed(9417)
panel <- expand.grid(item = 1:24, rater = 1:4, occasion = 1:3)
item_rater <- matrix(rnorm(96, sd = .7), 24, 4)
panel$y <- rnorm(24, sd = 1.4)[panel$item] + rnorm(4, sd = .45)[panel$rater] +
  rnorm(3, sd = .3)[panel$occasion] + item_rater[cbind(panel$item, panel$rater)] +
  rnorm(nrow(panel), sd = .8)
fit <- gt_fit(panel, "y", gt_design("item", c("rater", "occasion"),
  random = ~ item + rater + occasion + item:rater))
stopifnot(isTRUE(fit$numerically_accepted))
identity_before <- serialize(fit, NULL)
allocations <- data.frame(rater = c(2, 3, 4, 4), occasion = c(2, 2, 3, 3))
callback_count <- 0L
cost <- function(d) {
  callback_count <<- callback_count + 1L
  list(costs = data.frame(request_tokens = .01 * d$total_annotations,
                          setup = 2 * d$allocation_rater,
                          human_review = 5 + 0 * d$study_items),
       resources = data.frame(request_count = d$total_annotations),
       assumptions = "User-supplied illustrative costs; no call dependence is modelled.")
}
result <- gt_plan(fit, allocations, cost, currency = "USD", cost_date = "2026-10-09",
  study_items = 100, target = .7, coefficient = "Phi", baseline = 2,
  constraints = function(d) data.frame(budget = d$total_cost <= 50),
  cost_description = "Illustrative fixed date and a callback invoked exactly once.")
stopifnot(callback_count == 1L, inherits(result, "gt_plan"), nrow(as.data.frame(result)) == 4L,
          nrow(result$all_coefficients) == 4L, all(result$results$study_items == 100),
          identical(identity_before, serialize(fit, NULL)),
          all(result$results$minimum_cost %in% c(TRUE, FALSE)),
          all(result$results$total_cost == rowSums(result$cost_breakdown)),
          result$provenance$baseline_id == 2L,
          identical(result$provenance$cost_model$assumptions,
                    "User-supplied illustrative costs; no call dependence is modelled."))
reference <- gt_dstudy(fit, allocations)
stopifnot(isTRUE(all.equal(result$results$Erho2, reference$results$Erho2)),
          isTRUE(all.equal(result$results$Phi, reference$results$Phi)),
          isTRUE(all.equal(result$results$Phi_lower, reference$results$Phi_lower)),
          result$results$extra_cost[2] == 0,
          result$results$relative_error_reduction[2] == 0,
          result$results$Erho2_gain[2] == 0)
# Equal final candidates keep the same flags and cost, never silently disappear.
stopifnot(identical(result$results$minimum_cost[3], result$results$minimum_cost[4]),
          identical(result$results$pareto[3], result$results$pareto[4]),
          identical(result$results$total_cost[3], result$results$total_cost[4]))
for (id in seq_len(nrow(allocations))) {
  source_rows <- subset(result$source_contributions, design_id == id)
  stopifnot(abs(sum(source_rows$relative_error) - result$results$relative_error[id]) < 1e-10,
            abs(sum(source_rows$absolute_error_reduction) -
                  result$results$absolute_error_reduction[id]) < 1e-10)
}
lower <- gt_plan(fit, allocations, data.frame(expected_cost = rep(1, 4)),
  currency = "USD", cost_date = "2026-10-09", study_items = 100,
  target = .7, coefficient = "Phi", screening = "lower")
stopifnot(isTRUE(all.equal(lower$results$screening_value, reference$results$Phi_lower)),
          all(lower$results$meets_target[lower$results$screening_available] ==
                (reference$results$Phi_lower[lower$results$screening_available] >= .7)))
text <- capture.output(print(result))
stopifnot(any(grepl("declared candidates", text)), any(grepl("2026-10-09", text)))
cat("PASS: installed cost-aware planner uses accepted estimates, preserves all candidates and records cost assumptions.\n")
