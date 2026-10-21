# Analytic observed-scale/decision oracles, invariance and degenerate targets.
source("load_functions.R")
source("R/discrete_simulation.R")
source("R/categorical_targets.R")
expect_error <- function(expression, pattern) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}
near <- function(a, b, tolerance = 1e-10) {
  stopifnot(isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)))
}

binary_fixture <- function(item = 1, rater = 0, intercept = 0) {
  panel <- expand.grid(item = 1:4, rater = 1:2)
  structure(list(data = panel, design = gt_design("item", "rater", random = ~ item + rater),
    outcomes = "y", families = list(y = gt_family("binary", "probit", c("no", "yes"))),
    covariance_components = list(item = matrix(item, 1, 1, dimnames = list("y", "y")),
      rater = matrix(rater, 1, 1, dimnames = list("y", "y"))),
    covariance = "unstructured", means = c(y = intercept), thresholds = list(),
    link_dimensions = data.frame(outcome = "y", family = "binary", link = "probit",
      dimension = "y", category = NA_character_, reference = NA_character_),
    converged = TRUE, numerically_accepted = TRUE), class = "gt_fit")
}

# Independent exact special case: U~N(0,1) implies P=Phi(U)~Uniform(0,1).
# With m independent Bernoulli judgments conditional on P,
# Var(P)=1/12, E[P(1-P)]=1/6 and reliability=m/(m+2).
# For m=2 the influence function is 4.5*((P-.5)^2-1/12), whose
# variance is 0.1125. The independent integration sample is B*N objects;
# sharing the item between panels does not double that sample size.
fit <- binary_fixture()
set.seed(108)
previous <- .Random.seed
B <- 100L
N <- 80L
score <- gt_categorical_target(fit, "score", n_items = N, replications = B, seed = 417)
observed <- as.data.frame(score)
expected_se <- sqrt(.1125 / (B * N))
stopifnot(observed$available, abs(observed$estimate - .5) < 4 * expected_se,
  observed$mc_se / expected_se > .75, observed$mc_se / expected_se < 1.25,
  abs(observed$signal_variance - 1 / 12) < .006,
  abs(observed$total_variance - 1 / 6) < .006,
  identical(previous, .Random.seed), identical(score$integration$se_unit, "whole_panel_pair"),
  !score$integration$parameter_uncertainty)
four <- gt_categorical_target(fit, "score", counts = c(rater = 4),
  n_items = N, replications = B, seed = 417)
stopifnot(as.data.frame(four)$available,
  abs(as.data.frame(four)$estimate - 2 / 3) < 4 * as.data.frame(four)$mc_se)
single <- gt_categorical_target(fit, "score", counts = c(rater = 1),
  n_items = N, replications = B, seed = 417)
single_se <- sqrt((16 / 180) / (B * N))
stopifnot(as.data.frame(single)$available,
  abs(as.data.frame(single)$estimate - 1 / 3) < 4 * single_se,
  single$integration$rows_per_panel == N)
single_plan <- gt_plan(fit, data.frame(rater = c(1, 2)),
  cost = data.frame(annotations = c(80, 160)), currency = "USD", cost_date = "2026-10-20",
  study_items = 80, target = .2, coefficient = "observed_score", scale = "observed",
  integration = list(n_items = N, replications = B, seed = 417))
single_table <- as.data.frame(single_plan)
near(single_table$observed_score[1], as.data.frame(single)$estimate)
stopifnot(single_table$total_annotations[1] == 80, single_table$minimum_cost[1])
cat("PASS: exact binary-probit score coefficients, variance components and analytic integration SE.\n")

# A shared-facet oracle that cannot be passed by treating items as independent.
# Two random raters have P1,P2 iid Uniform(0,1), shared across every item.
# For two votes with uniform ties, conditional decision probability is
# Q=(P1+P2)/2, Var(Q)=1/24. Across independent panel pairs agreement has
# mean 1/2; the variance of an N-item panel-pair average is
# 1/144 + 1/(18*N). The first term persists as item count increases.
facets <- binary_fixture(item = 0, rater = 1)
B <- 160L
decision <- gt_categorical_target(facets, "decision", n_items = N, replications = B, seed = 251)
d <- as.data.frame(decision)
expected_se <- sqrt((1 / 144 + 1 / (18 * N)) / B)
stopifnot(d$available, abs(d$estimate - .5) < 4 * expected_se,
  d$mc_se / expected_se > .75, d$mc_se / expected_se < 1.25,
  d$mc_se > 2 * sqrt((1 / 16) / (B * N)),
  abs(decision$decision_probabilities$y[["yes"]] - .5) < .06,
  abs(d$decision_diversity - .5) < .01)
no_signal <- gt_categorical_target(facets, "score", n_items = 20, replications = 8, seed = 4)
stopifnot(as.data.frame(no_signal)$available, as.data.frame(no_signal)$estimate == 0,
  as.data.frame(no_signal)$mc_se == 0)
cat("PASS: whole-panel decision Monte Carlo error retains shared-facet variation; zero item signal is zero.\n")

# Always making the same decision gives perfect agreement and no category
# diversity, while its constant observed score has no reliability ratio.
constant <- binary_fixture(item = 0, rater = 0, intercept = 1000)
constant_decision <- gt_categorical_target(constant, "decision", n_items = 8, replications = 4, seed = 3)
constant_score <- gt_categorical_target(constant, "score", n_items = 8, replications = 4, seed = 3)
stopifnot(as.data.frame(constant_decision)$estimate == 1,
  as.data.frame(constant_decision)$decision_diversity == 0,
  constant_decision$decision_probabilities$y[["yes"]] == 1,
  !as.data.frame(constant_score)$available, is.na(as.data.frame(constant_score)$estimate),
  grepl("variance", as.data.frame(constant_score)$reason))
unresolved <- .gt_categorical_ratio(rbind(c(0, 0, -.1, .5), c(0, 0, -.2, .4)))
stopifnot(!unresolved$available, is.na(unresolved$estimate), unresolved$raw_estimate < 0,
  grepl("outside", unresolved$reason))

# Category-vector reliability must not depend on label names, display order,
# or arbitrary numerical codes. No numeric nominal scores are supplied.
nominal <- binary_fixture()
nominal$families <- list(y = gt_family("categorical", "softmax", c("red", "blue", "green"), "blue"))
nominal$link_dimensions <- data.frame(outcome = "y", family = "categorical", link = "softmax",
  dimension = c("red_vs_blue", "green_vs_blue"), category = c("red", "green"), reference = "blue")
dim_names <- nominal$link_dimensions$dimension
S <- matrix(c(.6, .1, .1, .4), 2, dimnames = list(dim_names, dim_names))
nominal$covariance_components <- list(item = S, rater = S / 3)
nominal$means <- stats::setNames(c(log(2), log(3)), dim_names)
nominal_result <- gt_categorical_target(nominal, "category_vector", n_items = 40, replications = 50, seed = 7)
stopifnot(as.data.frame(nominal_result)$available)
permuted <- nominal
permuted$families$y$levels <- c("green", "red", "blue")
permuted_result <- gt_categorical_target(permuted, "category_vector", n_items = 40,
  replications = 50, seed = 7)
near(as.data.frame(nominal_result)[c("estimate", "mc_se", "signal_variance", "total_variance")],
  as.data.frame(permuted_result)[c("estimate", "mc_se", "signal_variance", "total_variance")])
renamed <- nominal
renaming <- c(red = "300", blue = "-50", green = "9")
renamed$families$y$levels <- unname(renaming[renamed$families$y$levels])
renamed$families$y$reference <- unname(renaming[renamed$families$y$reference])
renamed$link_dimensions$category <- unname(renaming[renamed$link_dimensions$category])
renamed$link_dimensions$reference <- unname(renaming[renamed$link_dimensions$reference])
renamed_result <- gt_categorical_target(renamed, "category_vector", n_items = 40,
  replications = 50, seed = 7)
near(as.data.frame(nominal_result)[c("estimate", "mc_se", "signal_variance", "total_variance")],
  as.data.frame(renamed_result)[c("estimate", "mc_se", "signal_variance", "total_variance")])
expect_error(gt_categorical_target(nominal, "score", n_items = 8, replications = 2, seed = 1),
  "category_vector")
independent_nominal <- nominal
independent_nominal$covariance_components <- lapply(nominal$covariance_components, function(x) x * 0)
independent_nominal$means[] <- log(c(.2, .5) / .3)
independent_vector <- gt_categorical_target(independent_nominal, "category_vector",
  n_items = 8, replications = 4, seed = 3)
near(as.data.frame(independent_vector)$total_variance, (1 - sum(c(.2, .3, .5)^2)) / 2)
stopifnot(as.data.frame(independent_vector)$estimate == 0)
cat("PASS: constant-decision versus discrimination distinction, unavailable noisy ratios and nominal label invariance.\n")

# Ordered scores are substantive and explicit; affine transformations preserve
# a variance ratio while multiplying the two variances by the squared scale.
ordinal <- binary_fixture(item = .8, rater = .3)
ordinal$families <- list(y = gt_family("ordinal", "probit", c("low", "mid", "high")))
ordinal$link_dimensions$family <- "ordinal"
ordinal$thresholds <- list(y = c(-.4, .9))
value <- c(low = -2, mid = 0, high = 3)
ordered <- gt_categorical_target(ordinal, "score", scores = value,
  n_items = 40, replications = 50, seed = 180)
shifted <- gt_categorical_target(ordinal, "score", scores = 1000000 + 7 * value,
  n_items = 40, replications = 50, seed = 180)
near(as.data.frame(ordered)[c("estimate", "mc_se")], as.data.frame(shifted)[c("estimate", "mc_se")])
near(as.data.frame(ordered)[c("signal_variance", "total_variance")] * 49,
  as.data.frame(shifted)[c("signal_variance", "total_variance")])
expect_error(gt_categorical_target(ordinal, "score", n_items = 8, replications = 2, seed = 1),
  "finite score")
expect_error(gt_categorical_target(ordinal, "score", scores = c(low = 0, mid = 1, high = 1),
  n_items = 8, replications = 2, seed = 1), "increase strictly")
expect_error(gt_categorical_target(ordinal, "score", scores = c(low = 1, mid = 1, high = 1),
  n_items = 8, replications = 2, seed = 1), "distinguish")
for (multiplier in c(1e308, 1e200, 1e-200))
  expect_error(gt_categorical_target(ordinal, "score", scores = c(low = -1, mid = 0, high = 1) * multiplier,
    n_items = 8, replications = 2, seed = 1), "rescale")

# The probability of the first ordered category has an exact marginal oracle:
# U~N(0,.8+.3) gives E[Phi(-.4-U)]=Phi(-.4/sqrt(2.1)).
# The upper cumulative probability is analogous. Use expected observations,
# not arbitrarily numeric category codes, to obtain the marginal score mean.
expected_probability <- c(pnorm(-.4 / sqrt(2.1)),
  pnorm(.9 / sqrt(2.1)) - pnorm(-.4 / sqrt(2.1)), 1 - pnorm(.9 / sqrt(2.1)))
expected_mean <- sum(expected_probability * value)
normalized_mean <- mean(ordered$integration_moments$y[, 1:2])
estimated_mean <- min(value) + diff(range(value)) * normalized_mean
mean_se <- diff(range(value)) * sd(rowMeans(ordered$integration_moments$y[, 1:2])) / sqrt(50)
stopifnot(abs(estimated_mean - expected_mean) < 4 * mean_se)
independent_ordinal <- ordinal
independent_ordinal$covariance_components <- lapply(ordinal$covariance_components, function(x) x * 0)
independent_ordinal$thresholds$y <- qnorm(c(.25, .75))
independent_score <- gt_categorical_target(independent_ordinal, "score", scores = value,
  n_items = 8, replications = 4, seed = 3)
near(as.data.frame(independent_score)$total_variance, (sum(c(.25, .5, .25) * value^2) - .25^2) / 2)
near(-2 + 5 * mean(independent_score$integration_moments$y[, 1:2]), .25)
stopifnot(as.data.frame(independent_score)$estimate == 0)
incomplete <- ordinal
incomplete$data <- incomplete$data[-1, ]
incomplete_result <- gt_categorical_target(incomplete, "score", scores = value,
  n_items = 40, replications = 50, seed = 180)
near(as.data.frame(incomplete_result)[c("estimate", "mc_se")], as.data.frame(ordered)[c("estimate", "mc_se")])
cat("PASS: explicit ordinal scores, affine invariance, marginal mean oracle and complete-future projection.\n")
cat("All categorical target tests passed.\n")
