# Point-estimator pilots: independent reference, all attempts and no fabricated CI.
source("load_functions.R")
expect_error <- function(expression, pattern) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}
near <- function(a, b, tolerance = 1e-10) {
  stopifnot(isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)))
}
data <- expand.grid(item = 1:8, rater = 1:3)
data$y <- rep(c(0, 1), 12)
zero <- list(item = matrix(0), rater = matrix(0))
control <- gt_control(discrete = list(optimizer = "nlminb", fixed_covariance = zero))
fit <- gt_fit(y ~ item + rater, data, measured = "item", family = gt_family("binary"), control = control)
stopifnot(gt_diagnostics(fit)$numerically_accepted)
settings <- list(n_items = 20, replications = 5, reference_replications = 10)
set.seed(832)
previous <- .Random.seed

# The original item variance is zero, but the specified generating variance is
# one. P=Phi(U) is uniform, so a single-response target is exactly 1/3.
# Fixed-zero refitting constraints are intentionally retained: these pilots
# evaluate that estimator under the explicitly different generating scenario.
scenario <- list(item = matrix(1), rater = matrix(0))
evaluated <- gt_pilot_plan(fit, data.frame(n_items = 10, rater = 2), 2, 72,
  coefficient = "observed_score", scale = "observed", target_counts = c(rater = 1),
  components = scenario, means = c(y = 0),
  integration = list(n_items = 80, replications = 5, reference_replications = 100))
stopifnot(abs(evaluated$reference$estimate - 1 / 3) < 4 * sqrt((16 / 180) / 8000),
  evaluated$reference$mc_se > 0, evaluated$summary$attempted == 2L,
  evaluated$summary$target_available >= 1L,
  all(evaluated$replicates$estimate[evaluated$replicates$target_available] == 0),
  evaluated$scenario$parameter_source == "specified_parameter_scenario",
  evaluated$scenario$target_counts[["rater"]] == 1,
  all(is.na(evaluated$replicates$lower)), all(is.na(evaluated$replicates$upper)),
  all(is.na(evaluated$replicates$width)), all(!evaluated$replicates$interval_available),
  identical(previous, .Random.seed))
near(evaluated$summary$bias_vs_reference_given_available, -evaluated$reference$estimate)
near(evaluated$summary$rmse_vs_reference_given_available, evaluated$reference$estimate)
stopifnot(any(grepl("Pilot operating characteristics", capture.output(print(evaluated)), fixed = TRUE)))

# Replay the independently recorded data, refit and target-integration streams.
i <- which(evaluated$replicates$target_available)[1L]
record <- evaluated$replicates[i, ]
generated <- gt_simulate(fit, 10, c(rater = 2), seed = record$seed,
  components = scenario, means = c(y = 0))
replayed <- .gt_sim_rng(record$retry_seed, gt_fit(generated, "y", fit$design,
  family = fit$families, control = control))
replayed_target <- as.data.frame(gt_categorical_target(replayed, "score", counts = c(rater = 1),
  n_items = 80, replications = 5, seed = record$integration_seed))
near(record$estimate, replayed_target$estimate)
all_seeds <- c(unlist(evaluated$replicates[c("seed", "retry_seed", "integration_seed")]),
  evaluated$scenario$reference_seed)
stopifnot(!anyDuplicated(all_seeds), identical(previous, .Random.seed))

# Known ledger: six attempts include refusal, fitting error, unavailable
# integration, target error and two available estimates. No failed estimate is
# replaced by zero in bias/RMSE or omitted from availability denominators.
test_environment <- new.env(parent = environment())
sys.source("R/simulation.R", envir = test_environment)
attempt <- 0L
test_environment$gt_fit <- function(...) {
  attempt <<- attempt + 1L
  warning(sprintf("isolated draw %.17g", runif(1)))
  result <- fit
  if (attempt == 1L) {
    result$numerically_accepted <- result$converged <- FALSE
    invisible(runif(50))
  }
  if (attempt == 2L) stop("specified missing category")
  result
}
test_environment$gt_categorical_target <- function(fit, target, counts, ...) {
  stopifnot(identical(target, "score"), counts[["rater"]] == 1)
  if (attempt == 4L) stop("specified integration error")
  data.frame(estimate = if (attempt == 3L) NA_real_ else c(.2, .4)[attempt - 4L],
    raw_estimate = if (attempt == 3L) -.01 else c(.2, .4)[attempt - 4L],
    mc_se = if (attempt == 3L) NA_real_ else c(.01, .02)[attempt - 4L],
    available = attempt != 3L, reason = if (attempt == 3L) "specified unresolved ratio" else NA_character_)
}
run_ledger <- function() test_environment$gt_pilot_plan(fit,
  data.frame(n_items = c(6, 10), rater = c(2, 4)), 3, 21,
  coefficient = "observed_score", scale = "observed", target_counts = c(rater = 1), integration = settings)
ledger <- run_ledger()
stopifnot(identical(ledger$replicates$status, c("numerically_refused", "fit_error", "target_unavailable",
  "target_error", "target_available", "target_available")),
  sum(ledger$summary$attempted) == 6L, sum(ledger$summary$accepted) == 4L,
  sum(ledger$summary$target_available) == 2L, ledger$summary$availability_rate[1] == 0,
  ledger$summary$availability_rate[2] == 2 / 3,
  is.na(ledger$summary$bias_vs_reference_given_available[1]),
  ledger$summary$target_errors[2] == 1L, ledger$summary$preparation_or_fit_errors[1] == 1L)
near(ledger$summary$bias_vs_reference_given_available[2], .3)
near(ledger$summary$rmse_vs_reference_given_available[2], sqrt(.1))
near(ledger$summary$bias_mcse_given_reference[2], .1)
near(ledger$summary$empirical_sd_given_available[2], sqrt(.02))
near(ledger$summary$mean_inner_mc_se_given_available[2], .015)
attempt <- 0L
stopifnot(identical(ledger$replicates, run_ledger()$replicates), identical(previous, .Random.seed))
cat("PASS: analytic scenario override, separate reference MCSE, stream replay and independent all-attempt ledger.\n")

nominal_data <- data
nominal_data$nominal <- factor(rep(c("red", "blue", "green"), 8), levels = c("red", "blue", "green"))
nominal <- gt_fit(nominal_data, "nominal", fit$design, family = gt_family("categorical", reference = "blue"),
  control = gt_control(discrete = list(optimizer = "nlminb",
    fixed_covariance = list(item = matrix(0, 2, 2), rater = matrix(0, 2, 2)))))
nominal_plan <- gt_pilot_plan(nominal, data.frame(n_items = 8), 1, 32,
  coefficient = "category_vector", scale = "observed", target_counts = c(rater = 1), integration = settings)
stopifnot(nominal_plan$reference$estimate == 0, nominal_plan$summary$attempted == 1L,
  nominal_plan$summary$target_available == 1L, nominal_plan$replicates$estimate == 0)
joint <- gt_fit(nominal_data, c("y", "nominal"), fit$design,
  family = list(y = gt_family("binary"), nominal = gt_family("categorical", reference = "blue")),
  control = gt_control(discrete = list(optimizer = "nlminb",
    fixed_covariance = list(item = matrix(0, 3, 3), rater = matrix(0, 3, 3)))))
joint_plan <- gt_pilot_plan(joint, data.frame(n_items = 8), 1, 32, outcome = "nominal",
  coefficient = "category_vector", scale = "observed", target_counts = c(rater = 1), integration = settings)
stopifnot(joint_plan$summary$target_available == 1L, joint_plan$replicates$estimate == 0,
  length(joint_plan$scenario$families) == 2L, joint_plan$scenario$outcome == "nominal")
expect_error(gt_pilot_plan(joint, data.frame(n_items = 8), 1, 32,
  coefficient = "category_vector", scale = "observed", integration = settings), "exactly one fitted outcome")

# Fixed membership is retained even with one future facet level. No pilot or
# integration item-count change may silently regroup the call layout.
call_data <- data
call_data$call_id <- paste(ceiling(call_data$item / 2), call_data$rater, sep = "-")
calls <- gt_fit(call_data, "y", gt_design("item", "rater", random = ~ item + rater,
  batch = gt_batch(2, id = "call_id")), family = gt_family("binary"),
  control = gt_control(discrete = list(engine = "sparse", optimizer = "nlminb",
    fixed_covariance = c(zero, list(Call = matrix(0))))))
call_settings <- list(replications = 5, reference_replications = 10)
call_plan <- gt_pilot_plan(calls, data.frame(n_items = 8, rater = 2), 1, 42,
  coefficient = "decision_agreement", scale = "decision", target_counts = c(rater = 1),
  integration = call_settings)
stopifnot(call_plan$summary$attempted == 1L, call_plan$summary$target_available == 1L,
  call_plan$scenario$integration$n_items == 8L, call_plan$reference$batch_status == "modelled")
expect_error(gt_pilot_plan(calls, data.frame(n_items = 10), 1, 42,
  coefficient = "decision_agreement", scale = "decision", integration = call_settings), "fitted item count")
expect_error(gt_pilot_plan(calls, data.frame(n_items = 8), 1, 42,
  coefficient = "decision_agreement", scale = "decision", integration = c(call_settings, list(n_items = 10))),
  "fitted item count")
cat("PASS: actual nominal and fixed-call refits with explicit point targets and retained layouts.\n")

expect_error(gt_pilot_plan(fit, data.frame(n_items = 8), 1, 2,
  coefficient = "observed_score", integration = settings), "explicit scale")
expect_error(gt_pilot_plan(fit, data.frame(n_items = 8), 1, 2, coefficient = "observed_score",
  scale = "observed", width_target = .2, integration = settings), "no parameter confidence intervals")
expect_error(gt_pilot_plan(fit, data.frame(n_items = 8, rater = 1), 1, 2,
  coefficient = "observed_score", scale = "observed", integration = settings), "Pilot fitting requires")
expect_error(gt_pilot_plan(fit, data.frame(n_items = 8), 1, 2, coefficient = "observed_score",
  scale = "observed", integration = c(settings, list(seed = 2))), "seeds come from the master")
expect_error(gt_pilot_plan(fit, data.frame(n_items = 8), 10, 2, coefficient = "observed_score",
  scale = "observed", integration = list(n_items = 200, replications = 10000)), "ten million generated rows")
expect_error(gt_pilot_plan(fit, data.frame(n_items = 8), 1, 2, coefficient = "observed_score",
  scale = "observed", means = c(y = 1000), integration = settings), "reference is unavailable")
stopifnot(identical(previous, .Random.seed))
cat("All categorical point-target pilot tests passed.\n")
