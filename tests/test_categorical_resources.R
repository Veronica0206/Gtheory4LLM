# Resource preflights use arithmetic and fault injection, never large matrices.
source("load_functions.R")
expect_error <- function(expression, pattern) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}

# A source-level parameter fixture, not evidence of estimation or qualification
# of a many-category model. All guards must fire before simulated panels/refits.
ordinal_fixture <- function(categories) {
  levels <- paste0("category", seq_len(categories))
  structure(list(data = expand.grid(item = 1:4, rater = 1:2),
    design = gt_design("item", "rater", random = ~ item + rater),
    outcomes = "y", families = list(y = gt_family("ordinal", "probit", levels)),
    covariance_components = list(item = matrix(1, 1, 1, dimnames = list("y", "y")),
      rater = matrix(0, 1, 1, dimnames = list("y", "y"))),
    covariance = "unstructured", means = c(y = 0),
    thresholds = list(y = seq(-2, 2, length.out = categories - 1L)),
    link_dimensions = data.frame(outcome = "y", family = "ordinal", link = "probit",
      dimension = "y", category = NA_character_, reference = NA_character_),
    control = gt_control(), estimator = "ML_Laplace",
    converged = TRUE, numerically_accepted = TRUE), class = "gt_fit")
}

isolated <- new.env(parent = environment())
for (file in c("R/categorical_targets.R", "R/planning.R", "R/simulation.R"))
  sys.source(file, envir = isolated)
simulations <- refits <- 0L
isolated$.gt_discrete_sim_panels <- function(...) {
  simulations <<- simulations + 1L
  stop("Unexpected simulation before resource refusal")
}
isolated$gt_fit <- function(...) {
  refits <<- refits + 1L
  stop("Unexpected refit before resource refusal")
}
set.seed(192)
previous <- .Random.seed
large <- ordinal_fixture(4000L)
expect_error(isolated$gt_categorical_target(large, "category_vector", counts = c(rater = 1),
  n_items = 2, replications = 10000, seed = 71), "retained moments")
expect_error(isolated$gt_pilot_plan(large, data.frame(n_items = 4, rater = 2), 1, 71,
  coefficient = "category_vector", scale = "observed", target_counts = c(rater = 1),
  integration = list(n_items = 2, replications = 10000, reference_replications = 2)), "retained moments")
stopifnot(simulations == 0L, refits == 0L, identical(previous, .Random.seed))

# Individually safe integrations can still exceed the retained-results budget.
# 250 candidates x 10000 pairs x 2 rows x 2 panels equals the row limit,
# while moments alone use 250 x 10000 x 42 x 8 = 840,000,000 bytes.
moderate <- ordinal_fixture(20L)
model <- .gt_discrete_sim_model(moderate)
allocation <- .gt_discrete_sim_allocation(model, 2, c(rater = 1))
single <- .gt_categorical_target_resources(model, allocation, "category_vector", "y", 10000)
stopifnot(single$estimated_peak_bytes < 512 * 1024^2,
  single$moment_bytes * 250 == 840000000, 2 * single$rows * 10000 * 250 == 10000000)
expect_error(isolated$gt_plan(moderate, data.frame(rater = rep(1, 250)),
  cost = data.frame(annotations = rep(2, 250)), currency = "USD", cost_date = "2026-10-20",
  study_items = 2, target = .5, coefficient = "category_vector", scale = "observed",
  integration = list(n_items = 2, replications = 10000, seed = 71)), "retained target results")
stopifnot(simulations == 0L, refits == 0L, identical(previous, .Random.seed))

# The linear influence projection has exactly the covariance-form delta SE.
i <- seq_len(30)
moments <- cbind(.2 + sin(i) / 100, .3 + cos(i) / 100,
  .2 + cos(i) / 100, .3 + sin(i) / 100, .2 + sin(2 * i) / 100, .6 + cos(2 * i) / 100)
average <- colMeans(moments)
left <- average[1:2]; right <- average[3:4]; center <- (left + right) / 2
signal <- average[5] - sum(left * right)
total <- average[6] - sum(center^2)
gradient <- (c(-right, -left, 1, 0) * total - signal * c(-center, -center, 0, 1)) / total^2
expected_se <- sqrt(drop(crossprod(gradient, stats::cov(moments) %*% gradient)) / nrow(moments))
actual <- .gt_categorical_ratio(moments)
stopifnot(actual$available, abs(actual$mc_se - expected_se) < 1e-14)

# Small results still retain all documented moments and their resource record.
small <- gt_categorical_target(ordinal_fixture(3L), "category_vector", counts = c(rater = 1),
  n_items = 4, replications = 5, seed = 71)
stopifnot(identical(dim(small$integration_moments$y), c(5L, 8L)),
  small$integration$resource_budget$moment_bytes == 5 * 8 * 8,
  identical(previous, .Random.seed))
cat("PASS: pre-allocation target/planner/pilot memory guards, retained moments and equivalent influence SE.\n")
