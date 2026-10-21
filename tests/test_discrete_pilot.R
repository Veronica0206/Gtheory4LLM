# Bounded latent pilot refits, reproducible errors and all-attempt accounting.
source("load_functions.R")
source("R/discrete_simulation.R")
expect_error <- function(expression, pattern) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}
data <- expand.grid(item = 1:6, rater = 1:2)
data$y <- rep(c(0, 1), 6)
fit <- gt_fit(y ~ item + rater, data, measured = "item", family = gt_family("binary"),
  control = gt_control(discrete = list(fixed_covariance = list(item = matrix(0), rater = matrix(0)))))
stopifnot(fit$numerically_accepted)
set.seed(199)
previous <- .Random.seed
plan <- gt_pilot_plan(fit, data.frame(n_items = 8, rater = 2), nsim = 2,
  seed = 6, scale = "latent", target_counts = c(rater = 1), width_target = .2)
stopifnot(nrow(plan$replicates) == 2L, plan$summary$attempted == 2L,
  all(plan$replicates$status %in% c("numerically_refused", "interval_unavailable")),
  identical(plan$scenario$scale, "latent"), identical(plan$scenario$families, fit$families),
  identical(plan$scenario$thresholds, fit$thresholds), plan$scenario$target_counts[["rater"]] == 1,
  identical(previous, .Random.seed))

# Replay the same generated labels and refit stream. Numerical refusal is an
# outcome, not grounds for discarding a replicate or changing the seed.
replayed_data <- gt_simulate(fit, 8, c(rater = 2), seed = plan$replicates$seed[1])
replayed <- suppressWarnings(.gt_sim_rng(plan$replicates$retry_seed[1],
  gt_fit(replayed_data, "y", fit$design, family = fit$families,
    estimator = fit$estimator, covariance = fit$covariance, control = plan$scenario$control)))
stopifnot(identical(replayed$numerically_accepted, plan$replicates$accepted[1]))

# At an extreme but permitted parameter scenario every simulated category is
# positive with this recorded seed. The family still declares both categories;
# refitting must reject the absent category and retain every failed attempt.
rare <- gt_pilot_plan(fit, data.frame(n_items = 2), nsim = 2, seed = 9,
  scale = "latent", means = c(y = 15), width_target = .2)
stopifnot(rare$summary$attempted == 2L, rare$summary$preparation_or_fit_errors == 2L,
  rare$summary$precision_success_rate == 0, all(rare$replicates$status == "fit_error"),
  all(grepl("Every declared category", rare$replicates$reason)), identical(previous, .Random.seed))
expect_error(gt_pilot_plan(fit, data.frame(n_items = 2), 1, 9), "explicit scale='latent'")
expect_error(gt_pilot_plan(fit, data.frame(n_items = 2), 1, 9, scale = "observed"), "explicit")
expect_error(gt_pilot_plan(fit, data.frame(n_items = 8, rater = 1), 1, 9,
  scale = "latent", target_counts = c(rater = 1)), "Pilot fitting requires at least two")
expect_error(gt_pilot_plan(fit, data.frame(n_items = 6000), 100, 9, scale = "latent"),
  "one million generated rows")

# Inject only completed fit records to exercise the discrete interval route
# without claiming coverage. This covariance mapping is a stated test fixture.
interior <- fit
interior$covariance_components$item[,] <- .5
interior$covariance_components$rater[,] <- .1
interior$uncertainty <- list(available = TRUE, method = "specified test covariance",
  entries = data.frame(component = c("item", "rater"), row = "y", column = "y"),
  entry_covariance = diag(c(.02, .003)), boundary_components = character(),
  restricted_to_interior = FALSE, fixed_components = character(), fixed_component_kinds = character())
test_environment <- new.env(parent = environment())
sys.source("R/simulation.R", envir = test_environment)
attempt <- 0L
test_environment$gt_fit <- function(data, outcomes, design, family, estimator, covariance, residual, control) {
  attempt <<- attempt + 1L
  stopifnot(identical(family, fit$families), identical(estimator, "ML_Laplace"), is.null(residual))
  result <- interior
  if (attempt == 1L) {
    result$numerically_accepted <- result$converged <- FALSE
    warning("specified refusal")
  } else if (attempt == 2L) stop("specified missing category")
  else if (attempt == 3L) result$uncertainty$available <- FALSE
  result
}
checked <- test_environment$gt_pilot_plan(fit, data.frame(n_items = 8), 4, 70,
  scale = "latent", target_counts = c(rater = 2), width_target = 1)
stopifnot(identical(checked$replicates$status, c("numerically_refused", "fit_error",
    "interval_unavailable", "interval_available")),
  checked$summary$attempted == 4L, checked$summary$accepted == 2L,
  checked$summary$refused == 1L, checked$summary$preparation_or_fit_errors == 1L,
  checked$summary$interval_available == 1L, checked$summary$precision_success_rate == .25,
  abs(checked$replicates$estimate[4] - .5) < 1e-12,
  is.finite(checked$replicates$width[4]), identical(previous, .Random.seed))
cat("PASS: latent pilot replay, absent-category failure retention, finite interval extraction and all-attempt rates.\n")

# An ordered response retains its fitted thresholds and ordered family. This
# bounded zero-source refit checks dispatch without estimating random effects.
data$ordinal <- ordered(rep(c("low", "mid", "high"), 4), levels = c("low", "mid", "high"))
ordinal <- gt_fit(ordinal ~ item + rater, data, measured = "item", family = gt_family("ordinal"),
  control = fit$control)
stopifnot(ordinal$numerically_accepted)
ordinal_plan <- gt_pilot_plan(ordinal, data.frame(n_items = 8), 1, 20,
  scale = "latent", target_counts = c(rater = 1))
stopifnot(ordinal_plan$summary$attempted == 1L,
  identical(ordinal_plan$scenario$thresholds, ordinal$thresholds),
  ordinal_plan$replicates$status %in% c("numerically_refused", "interval_unavailable", "fit_error"))
cat("All categorical pilot tests passed.\n")
