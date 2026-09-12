# Public Gaussian starting values, run against the installed package.
library(Gtheory4LLM)

near <- function(actual, expected, tolerance = 1e-6) {
  stopifnot(isTRUE(all.equal(unname(actual), unname(expected),
                            tolerance = tolerance, check.attributes = FALSE)))
}
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"),
            grepl(pattern, conditionMessage(error), fixed = TRUE))
}

set.seed(64021)
d <- expand.grid(item = seq_len(24), rater = seq_len(4), KEEP.OUT.ATTRS = FALSE)
item_y <- rnorm(24)
item_z <- .5 * item_y + rnorm(24, sd = .8)
error_y <- rnorm(nrow(d), sd = .7)
d$y <- item_y[d$item] + error_y
d$z <- item_z[d$item] + .25 * error_y + rnorm(nrow(d), sd = .9)
design <- gt_design("item", "rater", random = ~ item)
starts <- list(item = matrix(c(.8, .2, .2, .4), 2),
               Residual = matrix(c(.5, .1, .1, .9), 2))
for (component in names(starts))
  dimnames(starts[[component]]) <- list(c("y", "z"), c("y", "z"))
settings <- list(optimizer = "SLSQP", check_hessian = FALSE,
                 extra_tries = 2L, retry_seed = 219L)
fit_with_start <- function(start, outcomes = c("y", "z")) {
  control <- settings
  control$start <- start
  gt_fit(d, outcomes, design, estimator = "ML",
         control = gt_control(gaussian = control))
}
automatic <- fit_with_start(NULL)
provided <- fit_with_start(starts)
stopifnot(automatic$numerically_accepted, provided$numerically_accepted)
near(provided$minus2loglik, automatic$minus2loglik)
near(unlist(provided$covariance_components), unlist(automatic$covariance_components), 2e-5)
stopifnot(provided$retry_settings$start == "provided_components",
          automatic$retry_settings$start == "sample_MoM",
          provided$retry_settings$optimizer == "SLSQP",
          provided$retry_settings$extraTries == 2L,
          provided$retry_settings$retry_seed == 219L,
          provided$retry_settings$total_trial_budget == 3L,
          provided$optimization_trials <= 3L,
          provided$returned_trial_identified)
cat("PASS: public Gaussian starts recover the automatic likelihood and retain optimizer/trial controls.\n")

# Each axis is matched separately. These raw matrices are intentionally not
# symmetric until their row and column labels are put back in outcome order.
reordered <- rev(lapply(starts, function(M) M[c("z", "y"), c("y", "z"), drop = FALSE]))
matched <- fit_with_start(reordered)
positional <- fit_with_start(lapply(starts, unname))
stopifnot(matched$numerically_accepted, positional$numerically_accepted)
near(matched$minus2loglik, provided$minus2loglik, 1e-10)
near(unlist(matched$covariance_components), unlist(provided$covariance_components), 1e-10)
near(positional$minus2loglik, provided$minus2loglik, 1e-10)
cat("PASS: source order and independently permuted complete axis labels are normalized; unnamed axes remain positional.\n")

# The one-outcome API still requires 1-by-1 covariance matrices.
univariate <- fit_with_start(list(item = matrix(.8), Residual = matrix(.5)), "y")
stopifnot(univariate$numerically_accepted,
          univariate$retry_settings$start == "provided_components")
expect_error(fit_with_start(list(item = .8, Residual = .5), "y"), "numeric covariance matrix")

expect_error(fit_with_start(starts["item"]), "every resolved model component")
expect_error(fit_with_start(c(starts, list(other = diag(2)))), "every resolved model component")
expect_error(fit_with_start(unname(starts)), "uniquely named list")
expect_error(fit_with_start(setNames(starts, c("item", "item"))), "uniquely named list")
expect_error(fit_with_start(setNames(starts, c("item", NA_character_))), "uniquely named list")
expect_error(fit_with_start(setNames(starts, c("item", ""))), "uniquely named list")

invalid_matrix <- function(M, pattern) {
  bad <- starts
  bad$item <- M
  expect_error(fit_with_start(bad), pattern)
}
invalid_matrix(matrix(1), "numeric covariance matrix")
invalid_matrix(matrix(NA_real_, 2, 2), "numeric covariance matrix")
invalid_matrix(matrix("1", 2, 2), "numeric covariance matrix")
for (axes in list(list(c("y", "z"), NULL), list(NULL, c("y", "z")),
                  list(c("y", "y"), c("y", "z")),
                  list(c("y", "z"), c("y", "other")),
                  list(c("y", NA_character_), c("y", "z")),
                  list(c("y", "z"), c("y", "")))) {
  M <- starts$item
  dimnames(M) <- axes
  invalid_matrix(M, "must name both axes with every outcome exactly once")
}
# Public label matching must not bypass the engine's mathematical checks.
invalid_matrix(matrix(c(1, .2, .3, 1), 2), "Invalid covariance matrix")
invalid_matrix(matrix(c(1, 2, 2, 1), 2), "not positive semidefinite")
cat("PASS: incomplete/ambiguous starts fail; engine symmetry and PSD requirements remain active.\n")
