# Run from the project root: Rscript --vanilla tests/test_gaussian_observed.R
source("load_functions.R")
if (!exists(".gt_gaussian_observed_prepare", mode = "function")) source("R/gaussian_observed.R")
stopifnot(requireNamespace("lme4", quietly = TRUE))
near <- function(a, b, tolerance = 1e-8) {
  if (!isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)))
    stop("Independent comparison failed: ", max(abs(a - b)))
}
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  if (is.null(error) || !grepl(pattern, conditionMessage(error), fixed = TRUE))
    stop("Expected error containing: ", pattern,
         if (!is.null(error)) paste0("; got: ", conditionMessage(error)))
}
set.seed(1317)
d <- expand.grid(item = seq_len(24), rater = seq_len(5), KEEP.OUT.ATTRS = FALSE)
d$y <- 8 + rnorm(24, sd = 2)[d$item] + c(-2, -.8, .1, 1, 2.1)[d$rater] +
  rnorm(nrow(d), sd = .7)
observed <- d[-seq(4L, nrow(d), by = 7L), ]
design <- gt_design("item", "rater", random = ~ item + rater)
resolved <- .gt_resolve_design(observed, design, "gaussian")
prepared <- .gt_gaussian_observed_prepare(observed, "y", resolved)
stopifnot(prepared$N == nrow(observed), !prepared$complete_balanced,
          prepared$identification$rank == 3L)

# Independent covariance construction from model matrices, followed by direct
# inversion and a determinant, rather than the implementation's tuple kernels
# and whitened residual calculation.
source_matrices <- function(data) list(
  item = tcrossprod(stats::model.matrix(~ 0 + factor(item), data)),
  rater = tcrossprod(stats::model.matrix(~ 0 + factor(rater), data)),
  Residual = diag(nrow(data)))
reference <- function(data, variances, reml) {
  K <- source_matrices(data)
  V <- Reduce(`+`, Map(`*`, K, variances[names(K)]))
  inverse <- solve(V)
  information <- sum(inverse)
  beta <- sum(inverse %*% data$y) / information
  error <- data$y - beta
  value <- (nrow(data) - as.integer(reml)) * log(2 * pi) +
    as.numeric(determinant(V, logarithm = TRUE)$modulus) +
    as.numeric(crossprod(error, inverse %*% error))
  if (reml) value <- value + log(information)
  value
}
points <- list(c(item = 3.2, rater = .7, Residual = .4),
               c(item = .02, rater = 4.8, Residual = 2),
               c(item = 0, rater = .3, Residual = .8))
complete <- .gt_gaussian_engine(c("item", "rater"))
complete_prepared <- complete$prepare(d, "y")
for (reml in c(FALSE, TRUE)) for (point in points) {
  components <- lapply(point, function(value) matrix(value, 1L, 1L))
  near(.gt_gaussian_observed_deviance(prepared, components, reml),
       reference(observed, point, reml), 1e-10)
  whole <- .gt_gaussian_observed_prepare(d, "y", resolved)
  near(.gt_gaussian_observed_deviance(whole, components, reml),
       complete$deviance(complete_prepared, components, reml), 1e-10)
}
permuted <- .gt_gaussian_observed_prepare(observed[rev(seq_len(nrow(observed))), ], "y", resolved)
shifted <- .gt_gaussian_observed_prepare(transform(observed, y = y + 100000), "y", resolved)
components <- lapply(points[[1L]], function(value) matrix(value, 1L, 1L))
near(.gt_gaussian_observed_deviance(prepared, components),
     .gt_gaussian_observed_deviance(permuted, components), 1e-10)
near(.gt_gaussian_observed_deviance(prepared, components),
     .gt_gaussian_observed_deviance(shifted, components), 1e-9)
cat("PASS: observed-row ML/REML match independent dense likelihoods at six parameter points, balanced contrasts, row permutations and intercept shifts.\n")

# lme4's deviance profiles residual scale as well as the mean. Recover that
# scale independently from the relative covariance, then compare the absolute
# observed-row likelihood at three deliberately non-optimal parameter points.
formula <- y ~ 1 + (1 | item) + (1 | rater)
for (reml in c(FALSE, TRUE)) {
  fitted <- lme4::lmer(formula, observed, REML = reml)
  devfun <- lme4::lmer(formula, observed, REML = reml, devFunOnly = TRUE)
  grouping_order <- sub(".(Intercept)", "", names(lme4::getME(fitted, "theta")), fixed = TRUE)
  for (ratios in list(c(item = .3, rater = 1.2), c(item = 2, rater = .4), c(item = 0, rater = .8))) {
    relative <- c(ratios^2, Residual = 1)
    K <- source_matrices(observed)
    W <- Reduce(`+`, Map(`*`, K, relative[names(K)]))
    inverse <- solve(W)
    beta <- sum(inverse %*% observed$y) / sum(inverse)
    error <- observed$y - beta
    sigma2 <- as.numeric(crossprod(error, inverse %*% error)) / (nrow(observed) - as.integer(reml))
    components <- lapply(relative * sigma2, function(value) matrix(value, 1L, 1L))
    near(.gt_gaussian_observed_deviance(prepared, components, reml),
         devfun(unname(ratios[grouping_order])), 1e-9)
  }
}
cat("PASS: observed-row reference matches lme4's independently profiled objective away from the optimum for ML and REML.\n")

control <- gt_control(gaussian = list(engine = "lme4", panel = "observed"))
for (estimator in c("ML", "REML")) {
  fit <- gt_fit(observed, y ~ item + rater, measured = "item",
                estimator = estimator, control = control)
  stopifnot(fit$numerically_accepted, fit$diagnostics$independent_likelihood_matches,
    fit$diagnostics$stability$stable,
    identical(fit$approximation_adequacy, "exact_observed_row_gaussian_likelihood"),
    identical(fit$design$panel_type, "observed"), fit$projection$required,
    fit$N == nrow(observed), fit$panel$observed_cells == nrow(observed),
    !any(c("y", "kernels") %in% names(fit$prepared)), !fit$uncertainty$available,
    !is.null(fit$diagnostics$independent_likelihood$exact_observed_row_deviance),
    is.null(fit$diagnostics$independent_likelihood$exact_balanced_deviance))
  conventional <- lme4::lmer(formula, observed, REML = estimator == "REML")
  near(fit$minus2loglik, -2 * as.numeric(stats::logLik(conventional)), 1e-10)
  near(fit$coefficients, lme4::fixef(conventional), 1e-10)
  expect_error(gt_reliability(fit), "complete balanced")
}
kept <- gt_fit(observed, "y", design, control = gt_control(
  gaussian = list(engine = "lme4", panel = "observed"), retain = list(data = FALSE)))
stopifnot(is.null(kept$data), is.null(kept$model), is.null(kept$backend_fit),
          !any(c("y", "kernels") %in% names(kept$prepared)))
projected <- gt_dstudy(kept, data.frame(rater = c(3, 6)), projection = "balanced")
projected_report <- gt_report(kept, dstudy = projected)
stopifnot(all(projected_report$dstudy$projection_target == "intended_complete_balanced"))
altered_projection <- projected
altered_projection$projection$assumptions <- "Changed after fitting."
expect_error(gt_report(kept, dstudy = altered_projection), "does not agree")
cat("PASS: incomplete fits retain acceptance, reference diagnostics and explicit projection assumptions without hidden observation copies.\n")

expect_error(gt_fit(observed, "y", design), "complete balanced factorial")
expect_error(gt_fit(observed, "y", design, control = gt_control(gaussian = list(engine = "lme4"))),
             "complete balanced factorial")
expect_error(gt_fit(observed, "y", design, control = gt_control(gaussian = list(panel = "observed"))),
             "requires engine = 'lme4'")
expect_error(.gt_gaussian_validate_control(list(max_observed_rows = 100)), "applies only")
expect_error(.gt_gaussian_validate_control(list(engine = "lme4", panel = "observed", max_observed_rows = 2.5)),
             "finite integer")
expect_error(.gt_gaussian_observed_prepare(observed, "y", resolved, max_observed_rows = 10),
             "exceeds max_observed_rows")
expect_error(.gt_gaussian_observed_prepare(observed, "y", resolved, max_preparation_bytes = 1),
             "exceeds max_preparation_bytes")
expect_error(gt_fit(rbind(observed, observed[1L, ]), "y", design, control = control), "replication does not match")
expect_error(.gt_gaussian_observed_prepare(transform(observed, y = NA_real_), "y", resolved),
             "missing or non-finite")
expect_error(.gt_gaussian_observed_prepare(transform(observed, z = y), c("y", "z"), resolved),
             "one outcome only")
aliased <- expand.grid(item = 1:6, occasion = 1:2)
aliased$rater <- aliased$item
aliased$y <- seq_len(nrow(aliased))
alias_design <- gt_design("item", c("rater", "occasion"), random = ~ item + rater + occasion)
expect_error(.gt_gaussian_observed_prepare(aliased, "y", alias_design), "linearly dependent")
batch_design <- resolved
batch_design$batch <- list(size = 2L)
expect_error(.gt_gaussian_observed_prepare(observed, "y", batch_design),
             "does not support declared batches")
cat("PASS: opt-in, row/memory limits, missing outcomes, duplicate cells, joint outcomes, aliases and batch restrictions are enforced.\n")

# A failed reference, nonstationarity or failed restart must still refuse the
# fit: the observed-row option does not weaken the existing acceptance policy.
good <- list(stationary_within_tolerance = TRUE)
stopifnot(identical(.gt_lme4_acceptance(0L, character(), good, TRUE, FALSE),
                   "independent_likelihood_mismatch"),
          "restart_or_tolerance_stability_failed" %in%
            .gt_lme4_acceptance(0L, character(), good, FALSE, TRUE))
reference_failure <- local({
  original <- .gt_gaussian_observed_deviance
  assign(".gt_gaussian_observed_deviance", function(...) original(...) + 100, .GlobalEnv)
  on.exit(assign(".gt_gaussian_observed_deviance", original, .GlobalEnv))
  gt_fit(observed, "y", design, control = control)
})
stopifnot(!reference_failure$numerically_accepted,
          "independent_likelihood_mismatch" %in% reference_failure$diagnostics$acceptance_failures)
expect_error(gt_reliability(reference_failure), "numerically converged")
cat("All observed-row Gaussian tests passed.\n")
