# Exact response-probability oracles and bounded simulation contracts.
source("load_functions.R")
source("R/discrete_simulation.R")
expect_error <- function(expression, pattern) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}
near <- function(a, b, tolerance = 1e-10) {
  stopifnot(isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)))
}

# An accepted-fit fixture isolates generation from numerical optimization.
# Category order deliberately differs from nominal reference order.
families <- list(binary = gt_family("binary", "probit", c("no", "yes")),
  ordinal = gt_family("ordinal", "logit", c("low", "mid", "high")),
  nominal = gt_family("categorical", "softmax", c("red", "blue", "green"), "blue"))
dimensions <- c("binary", "ordinal", "nominal:red", "nominal:green")
mapping <- data.frame(outcome = c("binary", "ordinal", "nominal", "nominal"),
  family = c("binary", "ordinal", "categorical", "categorical"),
  link = c("probit", "logit", "softmax", "softmax"), dimension = dimensions,
  category = c(NA, NA, "red", "green"), reference = c(NA, NA, "blue", "blue"))
panel <- expand.grid(item = 1:4, rater = 1:2, KEEP.OUT.ATTRS = FALSE)
design <- gt_design("item", "rater", random = ~ item + rater)
matrix4 <- function(value = 0) {
  result <- diag(value, 4)
  dimnames(result) <- list(dimensions, dimensions)
  result
}
fixture <- structure(list(data = panel, design = design, outcomes = names(families),
  families = families, converged = TRUE, numerically_accepted = TRUE,
  covariance_components = list(item = matrix4(), rater = matrix4()),
  covariance = "unstructured", link_dimensions = mapping,
  means = stats::setNames(c(.3, 0, log(2), log(3)), dimensions),
  thresholds = list(ordinal = c(-.5, .8))), class = "gt_fit")
model <- .gt_discrete_sim_model(fixture)
eta <- matrix(c(-2, -.2, log(2), log(3), .4, .7, log(5), log(2)), 2, byrow = TRUE)
probability <- .gt_discrete_sim_probabilities(model, eta)
near(probability$binary, cbind(pnorm(-eta[, 1]), pnorm(eta[, 1])))
lower <- plogis(-.5 - eta[, 2])
upper <- plogis(.8 - eta[, 2])
near(probability$ordinal, cbind(lower, upper - lower, 1 - upper))
near(probability$nominal, rbind(c(2, 1, 3) / 6, c(5, 1, 2) / 8))
stopifnot(identical(colnames(probability$nominal), families$nominal$levels))

# Permuting category display order changes no category probability; changing
# the reference subtracts its linear predictor from every other predictor.
permuted <- fixture
permuted$families$nominal$levels <- c("green", "red", "blue")
permuted_probability <- .gt_discrete_sim_probabilities(.gt_discrete_sim_model(permuted), eta)
near(permuted_probability$nominal[, colnames(probability$nominal)], probability$nominal)
relevelled <- fixture
relevelled$families$nominal$reference <- "red"
relevelled$link_dimensions$category[3:4] <- c("blue", "green")
relevelled$link_dimensions$reference[3:4] <- "red"
relevelled_eta <- eta
relevelled_eta[, 3] <- -eta[, 3]
relevelled_eta[, 4] <- eta[, 4] - eta[, 3]
near(.gt_discrete_sim_probabilities(.gt_discrete_sim_model(relevelled), relevelled_eta)$nominal,
  probability$nominal)
tail_eta <- matrix(c(-40, -1000, 1000, -1000, 40, 1000, -1000, 1000), 2, byrow = TRUE)
tail_probability <- .gt_discrete_sim_probabilities(model, tail_eta)
stopifnot(all(vapply(tail_probability, function(x) all(is.finite(x)) &&
  all(x >= 0) && max(abs(rowSums(x) - 1)) < 1e-14, logical(1))))
cat("PASS: binary, ordered-logit and nominal probability oracles, tails, category permutations and references.\n")

set.seed(806)
previous <- .Random.seed
previous_kind <- RNGkind()
generated <- gt_simulate(fixture, 6, counts = c(rater = 3), seed = 50)
stopifnot(nrow(generated) == 18L, identical(previous, .Random.seed), identical(previous_kind, RNGkind()),
  identical(generated, gt_simulate(fixture, 6, counts = c(rater = 3), seed = 50)),
  all(vapply(names(families), function(x) identical(levels(generated[[x]]), families[[x]]$levels), logical(1))),
  is.ordered(generated$ordinal), !is.ordered(generated$nominal), !is.ordered(generated$binary))
rm(".Random.seed", envir = .GlobalEnv)
invisible(gt_simulate(fixture, 2, seed = 1))
stopifnot(!exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
RNGkind("L'Ecuyer-CMRG")
kind <- RNGkind()
seed <- .Random.seed
stopifnot(identical(generated, gt_simulate(fixture, 6, counts = c(rater = 3), seed = 50)),
  identical(kind, RNGkind()), identical(seed, .Random.seed))
do.call(RNGkind, as.list(previous_kind))
assign(".Random.seed", previous, envir = .GlobalEnv)

# Exact rank-one covariance forces equal predictors for the binary and
# ordinal dimensions. Item effects persist across panels; rater effects are
# shared across items within a panel and redrawn between panels.
dependent <- fixture
dependent$covariance_components$item <- matrix4()
dependent$covariance_components$item[1:2, 1:2] <- 1
dependent$means[] <- 0
dependent_model <- .gt_discrete_sim_model(dependent)
allocation <- .gt_discrete_sim_allocation(dependent_model, 4)
paired <- .gt_sim_rng(41, .gt_discrete_sim_panels(dependent_model, allocation))
stopifnot(identical(paired$probabilities[[1]], paired$probabilities[[2]]),
  identical(paired$shared_sources, "item"), identical(paired$redrawn_sources, "rater"))
near(qnorm(paired$probabilities[[1]]$binary[, "yes"]),
  -.5 - qlogis(paired$probabilities[[1]]$ordinal[, "low"]), 1e-7)
near(paired$probabilities[[1]]$binary[1:4, ], paired$probabilities[[1]]$binary[5:8, ])
dependent$covariance_components$item[] <- 0
dependent$covariance_components$rater <- matrix4(.4)
rater_model <- .gt_discrete_sim_model(dependent)
rater_pair <- .gt_sim_rng(41, .gt_discrete_sim_panels(rater_model, allocation))
stopifnot(!identical(rater_pair$probabilities[[1]], rater_pair$probabilities[[2]]))
near(rater_pair$probabilities[[1]]$binary[1:4, 2], rep(rater_pair$probabilities[[1]]$binary[1, 2], 4))
all_shared <- .gt_sim_rng(41, .gt_discrete_sim_panels(rater_model, allocation,
  shared_sources = names(rater_model$components)))
stopifnot(identical(all_shared$probabilities[[1]], all_shared$probabilities[[2]]))

# Independent probit moment: for U~N(0,1), E[Phi(U)]=1/2 and
# E[Phi(U)^2]=1/4+asin(1/2)/(2*pi)=1/3. A bounded 4,000-object
# draw checks that the latent source variance is actually used, not discarded.
moment_model <- .gt_discrete_sim_model(fixture,
  components = list(item = matrix4(1), rater = matrix4()), means = stats::setNames(numeric(4), dimensions))
moment_panel <- .gt_sim_rng(412, .gt_discrete_sim_panels(moment_model,
  .gt_discrete_sim_allocation(moment_model, 4000), 1L))
p <- moment_panel$probabilities[[1]]$binary[1:4000, "yes"]
stopifnot(abs(mean(p) - .5) < .025, abs(mean(p^2) - 1 / 3) < .025)
cat("PASS: shared item, redrawn facet, joint covariance, independent probit moments and isolated RNG.\n")

# Whole missing fitted cells do not create default labels: the requested
# future panel is complete. Replicate observations share their predictors.
incomplete <- fixture
incomplete$data <- incomplete$data[-1, ]
stopifnot(nrow(gt_simulate(incomplete, 4, seed = 4)) == 8L)
replicated <- dependent
replicated$design$replicates <- 2L
replicated$data <- replicated$data[rep(seq_len(nrow(replicated$data)), each = 2L), ]
replicate_model <- .gt_discrete_sim_model(replicated)
replicate_draw <- .gt_sim_rng(8, .gt_discrete_sim_panels(replicate_model,
  .gt_discrete_sim_allocation(replicate_model, 4), 1L))
stopifnot(nrow(replicate_draw$panels[[1]]) == 16L)
near(replicate_draw$probabilities[[1]]$binary[seq(1, 16, 2), ],
  replicate_draw$probabilities[[1]]$binary[seq(2, 16, 2), ])

# Call law is shared across items in each fixed call and condition, and fresh
# between repeated panels. Metadata is the contract shared with the fitter.
batched <- fixture
batched$design$batch <- gt_batch(2, id = "call_id", order = "position")
batched$design$batch_model <- list(modelled = TRUE, term = "Call", batches = 2L,
  size = 2L, calls = 4L, item_levels = 1:4, item_batches = c(1L, 2L, 1L, 2L))
batched$covariance_components$Call <- matrix4(.7)
batch_model <- .gt_discrete_sim_model(batched)
batch_pair <- .gt_sim_rng(91, .gt_discrete_sim_panels(batch_model,
  .gt_discrete_sim_allocation(batch_model, 4)))
batch_data <- batch_pair$panels[[1]]
reconstructed <- .gt_batch_model(batch_data, batched$design)
stopifnot(reconstructed$modelled, all(table(batch_data$call_id) == 2L),
  !identical(batch_pair$probabilities[[1]], batch_pair$probabilities[[2]]))
near(batch_pair$probabilities[[1]]$binary[c(1, 2, 5, 6), ],
  batch_pair$probabilities[[1]]$binary[c(3, 4, 7, 8), ])
stopifnot(identical(batch_data$call_id[c(1, 2, 5, 6)], batch_data$call_id[c(3, 4, 7, 8)]))
future_calls <- gt_simulate(batched, 4, counts = c(rater = 3), seed = 91)
stopifnot(attr(future_calls, "simulation")$call_layout$calls == 6L,
  length(unique(future_calls$call_id)) == 6L)
single_calls <- gt_simulate(batched, 4, counts = c(rater = 1), seed = 91)
stopifnot(nrow(single_calls) == 4L, length(unique(single_calls$call_id)) == 2L,
  all(table(single_calls$call_id) == 2L), .gt_batch_model(single_calls, batched$design)$modelled)
expect_error(gt_simulate(batched, 6, seed = 8), "retains the fitted item count")
batched$design$batch$sequential <- 1L
expect_error(gt_simulate(batched, 4, seed = 8), "unmodelled batches")

bad <- fixture
bad$numerically_accepted <- FALSE
expect_error(gt_simulate(bad, 4, seed = 1), "accepted fit")
bad <- fixture
bad$data <- bad$data[bad$data$rater == 1, ]
expect_error(gt_simulate(bad, 4, c(rater = 1), seed = 1), "recorded object and facet counts of at least two")
bad <- fixture
bad$thresholds$ordinal <- c(0, 0)
expect_error(gt_simulate(bad, 4, seed = 1), "strictly ordered")
bad <- fixture
bad$link_dimensions$link[1] <- NA_character_
expect_error(gt_simulate(bad, 4, seed = 1), "mapping")
bad <- fixture
bad$covariance_components$item[1, 1] <- -1
expect_error(gt_simulate(bad, 4, seed = 1), "positive semidefinite")
expect_error(gt_simulate(fixture, 4, seed = 1, components = list(item = matrix4())), "every fitted")
expect_error(gt_simulate(fixture, 4, seed = 1, means = c(binary = 0, ordinal = 1,
  "nominal:red" = 0, "nominal:green" = 0)), "intercepts must remain zero")
stopifnot(nrow(gt_simulate(fixture, 4, c(rater = 1), seed = 1)) == 4L)
expect_error(gt_simulate(fixture, 4, c(rater = 0), seed = 1), "positive integer")
expect_error(gt_simulate(fixture, 1, c(rater = 1), seed = 1), "n_items")
expect_error(gt_simulate(fixture, 4, c(item = 2), seed = 1), "declared facets")
expect_error(gt_simulate(fixture, 4, seed = 1, max_rows = 7), "max_rows")
expect_error(gt_simulate(fixture, 1000000, seed = 1), "max_rows")
expect_error(.gt_discrete_sim_panels(model, c(item = 100000, rater = 2), 100), "512 MiB")
expect_error(.gt_discrete_sim_panels(model, allocation, shared_sources = "unknown"), "shared_sources")
cat("PASS: future allocations, replication, fixed-call dependence, metadata round trip and refusals.\n")

# A public fit verifies the actual retained threshold/contrast interface.
# With fixed zero source covariance this is three elementary intercept-only
# likelihoods; no high-dimensional numerical fit is involved.
observed <- expand.grid(item = 1:6, rater = 1:2, KEEP.OUT.ATTRS = FALSE)
observed$binary <- factor(rep(c("no", "yes"), 6), levels = families$binary$levels)
observed$ordinal <- ordered(rep(c("low", "mid", "high"), 4), levels = families$ordinal$levels)
observed$nominal <- factor(rep(c("red", "blue", "green"), 4), levels = families$nominal$levels)
fit <- gt_fit(observed, names(families), design, family = families,
  control = gt_control(discrete = list(fixed_covariance = lapply(fixture$covariance_components, unname))))
stopifnot(fit$numerically_accepted, fit$converged)
fitted_simulation <- gt_simulate(fit, 4, seed = 841)
stopifnot(nrow(fitted_simulation) == 8L,
  identical(levels(fitted_simulation$nominal), families$nominal$levels),
  identical(attr(fitted_simulation, "simulation")$parameter_source, "fitted_model_plugin"))
fitted_model <- .gt_discrete_sim_model(fit)
fitted_probability <- .gt_discrete_sim_probabilities(fitted_model, matrix(fitted_model$means, 1))
near(fitted_probability$binary, matrix(c(.5, .5), 1), 1e-6)
near(fitted_probability$ordinal, matrix(rep(1 / 3, 3), 1), 1e-6)
near(fitted_probability$nominal, matrix(rep(1 / 3, 3), 1), 1e-6)
cat("PASS: accepted public joint fit to categorical simulation and elementary likelihood probabilities.\n")
cat("All categorical simulation tests passed.\n")
