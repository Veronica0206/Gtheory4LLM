# Independent simulation moments, failure accounting, and a real refitting smoke test.
source("load_functions.R")
source("R/simulation.R")
expect_error <- function(expression, pattern) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}
near <- function(a, b, tolerance = 1e-8) {
  stopifnot(isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)))
}

# An explicit accepted-fit fixture isolates the data generator from fitting.
# The reference covariance below is assembled observation by observation.
design <- gt_design("item", c("rater", "occasion"), crossed = "rater",
  nested = list(occasion = "rater"))
panel <- expand.grid(item = 1:2, rater = 1:2, occasion = 1:2, KEEP.OUT.ATTRS = FALSE)
panel$first <- panel$second <- 0
design <- .gt_resolve_design(panel, design, "gaussian")
outcomes <- c("first", "second")
mat <- function(a, b, c) matrix(c(a, c, c, b), 2, dimnames = list(outcomes, outcomes))
components <- list(item = mat(1, 2, .4), rater = mat(0, 0, 0),
  "item:rater" = mat(.3, .3, .3), "rater:occasion" = mat(.2, .4, -.1),
  Residual = mat(.5, .6, .1))
components <- components[c(design$terms, "Residual")]
fixture <- structure(list(data = panel, design = design, outcomes = outcomes,
  families = stats::setNames(rep(list(gt_family()), 2), outcomes),
  converged = TRUE, numerically_accepted = TRUE, estimator = "REML",
  covariance_components = components, means = c(first = 2, second = -1),
  covariance_types = stats::setNames(rep("unstructured", length(components)), names(components)),
  control = gt_control()), class = "gt_fit")
set.seed(828)
previous <- .Random.seed
kind <- RNGkind()
generated <- gt_simulate(fixture, 2, seed = 74)
stopifnot(identical(previous, .Random.seed), identical(kind, RNGkind()),
  identical(generated, gt_simulate(fixture, 2, seed = 74)),
  nrow(gt_simulate(fixture, 5, c(rater = 3), seed = 74)) == 30L,
  identical(attr(generated, "simulation")$parameter_source, "fitted_model_plugin"))
rm(".Random.seed", envir = .GlobalEnv)
invisible(gt_simulate(fixture, 2, seed = 74))
stopifnot(!exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
assign(".Random.seed", previous, envir = .GlobalEnv)
RNGkind("L'Ecuyer-CMRG")
previous_kind <- RNGkind()
previous_seed <- .Random.seed
stopifnot(identical(generated, gt_simulate(fixture, 2, seed = 74)),
  identical(previous_kind, RNGkind()), identical(previous_seed, .Random.seed))
do.call(RNGkind, as.list(kind))
assign(".Random.seed", previous, envir = .GlobalEnv)

model <- .gt_sim_model(fixture, NULL, NULL)
allocation <- .gt_sim_allocation(model, 2, NULL, 100)
draws <- .gt_sim_rng(51, replicate(6000,
  as.vector(t(as.matrix(.gt_sim_draw(model, allocation)[outcomes])))))
expected <- matrix(0, nrow(panel) * 2, nrow(panel) * 2)
for (source in names(components)) {
  if (source == "Residual") kernel <- diag(nrow(panel)) else {
    members <- strsplit(source, ":", fixed = TRUE)[[1L]]
    kernel <- Reduce(`*`, lapply(panel[members], function(x) outer(x, x, `==`)))
  }
  expected <- expected + kronecker(kernel, components[[source]])
}
stopifnot(max(abs(rowMeans(draws) - rep(fixture$means, nrow(panel)))) < .08,
  max(abs(stats::cov(t(draws)) - expected)) < .16)
cat("PASS: independent dense source-kernel covariance matches generated nested multivariate moments.\n")

zero <- lapply(components, function(value) value * 0)
constant <- gt_simulate(fixture, 2, seed = 6, components = zero,
  means = c(second = 3, first = -2))
stopifnot(all(constant$first == -2), all(constant$second == 3),
  attr(constant, "simulation")$parameter_source == "specified_parameter_scenario")
bad <- components
bad$item[1, 1] <- -1
expect_error(gt_simulate(fixture, 2, seed = 6, components = bad), "positive semidefinite")
bad <- components
bad$item[1, 2] <- 9
expect_error(gt_simulate(fixture, 2, seed = 6, components = bad), "symmetric")
expect_error(gt_simulate(fixture, 2, seed = 6, components = components[-1]), "every resolved model component")
expect_error(gt_simulate(fixture, 2, seed = 6, means = c(1, 2)), "naming every outcome")
expect_error(gt_simulate(fixture, 2, counts = c(rater = 1), seed = 6), "at least two")
expect_error(gt_simulate(fixture, 2, counts = c(item = 3), seed = 6), "declared facets")
expect_error(gt_simulate(fixture, 2, counts = c(rater = 3), seed = 6, max_rows = 8), "max_rows")
expect_error(gt_simulate(fixture, 2, seed = NA_real_), "seed")
badfit <- fixture
badfit$numerically_accepted <- FALSE
expect_error(gt_simulate(badfit, 2, seed = 1), "accepted fit")
badfit <- fixture
badfit$design$batch <- gt_batch(2)
expect_error(gt_simulate(badfit, 2, seed = 1), "batches")
badfit <- fixture
badfit$data <- badfit$data[-1, ]
expect_error(gt_simulate(badfit, 2, seed = 1), "balanced")
badfit <- fixture
badfit$families[[1]] <- gt_family("binary")
expect_error(gt_simulate(badfit, 2, seed = 1), "Gaussian")
badfit <- fixture
badfit$covariance_types["item"] <- "diagonal"
expect_error(gt_simulate(badfit, 2, seed = 1), "diagonal structure")
cat("PASS: zero and singular sources, input refusals, seeds, and caller RNG preservation.\n")

# A deterministic ledger checks the all-attempt denominators independently of
# optimizers. Conditional summaries explicitly use their smaller denominator.
ledger <- do.call(rbind, lapply(1:6, function(i) .gt_pilot_record(1L, i, i)))
ledger$status <- c("interval_available", "interval_available", "interval_unavailable",
  "reliability_error", "numerically_refused", "fit_error")
ledger$accepted <- c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE)
ledger$interval_available <- c(TRUE, TRUE, FALSE, FALSE, FALSE, FALSE)
ledger$interval_conditional <- c(FALSE, TRUE, NA, NA, NA, NA)
ledger$width <- c(.1, .3, NA, NA, NA, NA)
ledger$meets_width <- c(TRUE, FALSE, NA, NA, NA, NA)
summary <- .gt_pilot_summary(ledger, data.frame(n_items = 20), .2)
stopifnot(summary$attempted == 6L, summary$accepted == 4L, summary$interval_available == 2L,
  summary$refused == 1L, summary$preparation_or_fit_errors == 1L,
  summary$reliability_errors == 1L, summary$interval_unavailable == 1L,
  summary$conditional_intervals == 1L)
near(summary$acceptance_rate, 4 / 6)
near(summary$acceptance_mcse, sqrt((4 / 6) * (2 / 6) / 6))
near(summary$precision_success_rate, 1 / 6)
near(summary$precision_success_mcse, sqrt((1 / 6) * (5 / 6) / 6))
near(summary$precision_rate_given_interval, .5)
near(summary$mean_width_given_interval, .2)
near(summary$mean_width_mcse_given_interval, .1)
near(summary$refusal_rate, 1 / 6)
near(summary$error_rate, 2 / 6)
cat("PASS: precision and refusal rates retain all attempts and report matching Monte Carlo denominators.\n")

set.seed(199)
data <- expand.grid(item = 1:24, rater = 1:4, KEEP.OUT.ATTRS = FALSE)
data$score <- rep(rnorm(24, sd = 2), 4) + rep(rnorm(4, sd = .5), each = 24) + rnorm(96)
fit <- gt_fit(data, "score", gt_design("item", "rater"))
stopifnot(isTRUE(fit$numerically_accepted), isTRUE(fit$converged))
previous <- .Random.seed
plan <- gt_pilot_plan(fit, data.frame(n_items = c(16, 24), rater = c(3, 4)),
  nsim = 2, seed = 3, width_target = .4, target_counts = c(rater = 2))
stopifnot(nrow(plan$replicates) == 4L, nrow(plan$summary) == 2L,
  sum(plan$summary$attempted) == 4L, identical(previous, .Random.seed),
  identical(unname(plan$scenario$target_counts), 2), all(plan$replicates$accepted),
  all(plan$replicates$interval_available), all(is.finite(plan$replicates$width)))
# Replay exactly one recorded seed and independently project its coefficient.
replay_control <- plan$scenario$control
replay_control$gaussian$retry_seed <- plan$replicates$retry_seed[1]
replayed <- gt_fit(gt_simulate(fit, 16, c(rater = 3), seed = plan$replicates$seed[1]),
  "score", fit$design, estimator = fit$estimator,
  covariance = fit$covariance_types[fit$design$terms], residual = fit$covariance_types[["Residual"]],
  control = replay_control)
reference <- gt_reliability(replayed, design = c(rater = 2))
near(plan$replicates$estimate[1], reference$per_trait$Erho2, 1e-8)
near(plan$replicates$width[1], reference$per_trait$Erho2_upper - reference$per_trait$Erho2_lower, 1e-8)

zero <- lapply(fit$covariance_components, function(value) value * 0)
failed <- gt_pilot_plan(fit, data.frame(n_items = 8), nsim = 2, seed = 3,
  components = zero, width_target = .4)
stopifnot(nrow(failed$replicates) == 2L, all(failed$replicates$status == "fit_error"),
  failed$summary$attempted == 2L, failed$summary$preparation_or_fit_errors == 2L,
  failed$summary$precision_success_rate == 0, is.na(failed$summary$mean_width_given_interval))
expect_error(gt_pilot_plan(fit, data.frame(n_items = 8), nsim = 10001, seed = 3), "10000")
expect_error(gt_pilot_plan(fit, data.frame(n_items = 8), nsim = 2, seed = 3,
  target_counts = c(rater = 0)), "positive integer")

# Injection is confined to a separate test environment. The production API
# never accepts a refit function or an acceptance override.
test_environment <- new.env(parent = environment())
sys.source("R/simulation.R", envir = test_environment)
attempt <- 0L
test_environment$gt_fit <- function(...) {
  attempt <<- attempt + 1L
  warning(sprintf("injected random draw %.17g", runif(1)))
  result <- fit
  if (attempt == 1L) {
    # A variable number of retry draws must not change later replicate streams.
    invisible(runif(1000))
    result$converged <- result$numerically_accepted <- FALSE
    warning("deterministic refusal fixture")
  } else result$uncertainty <- list(available = FALSE, reason = "deterministic unavailable fixture")
  result
}
injected <- test_environment$gt_pilot_plan(fit, data.frame(n_items = 8), nsim = 2, seed = 3)
stopifnot(identical(injected$replicates$status, c("numerically_refused", "interval_unavailable")),
  injected$summary$refused == 1L, injected$summary$interval_unavailable == 1L,
  grepl("deterministic refusal", injected$replicates$warnings[1]),
  identical(previous, .Random.seed))
for (i in 1:2) {
  expected_warning <- .gt_sim_rng(injected$replicates$retry_seed[i],
    sprintf("injected random draw %.17g", runif(1)))
  stopifnot(grepl(expected_warning, injected$replicates$warnings[i], fixed = TRUE))
}
attempt <- 0L
explicit <- test_environment$gt_pilot_plan(fit, data.frame(n_items = 8), nsim = 2, seed = 3,
  control = gt_control(gaussian = list(retry_seed = 777)))
stopifnot(all(explicit$replicates$retry_seed == 777L), identical(previous, .Random.seed))
expected_warning <- .gt_sim_rng(777, sprintf("injected random draw %.17g", runif(1)))
stopifnot(all(grepl(expected_warning, explicit$replicates$warnings, fixed = TRUE)))
cat("PASS: real fit/simulate/refit precision, fixed target protocol, replay, and retained failures.\n")
cat("All simulation and pilot planning tests passed.\n")
