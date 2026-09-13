# Public numerical controls tested against the installed artifact.
library(Gtheory4LLM)
expect_error <- function(expr, pattern) {
  error <- tryCatch({force(expr); NULL}, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}
near <- function(a, b, tolerance = 1e-6)
  stopifnot(isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance,
                            check.attributes = FALSE)))
d <- expand.grid(occasion = 1:12, item = 1:8)
design <- gt_design("item", "occasion", random = ~ item)
d$y <- as.integer(d$occasion <= c(2, 3, 4, 5, 7, 8, 9, 10)[d$item])
controls <- function(optimizer, start = NULL, alternatives = 2L)
  gt_control(discrete = list(optimizer = optimizer, start = start,
    covariance_parameterization = "variance", maxit = 300L,
    alternative_starts = alternatives))
fits <- lapply(c("L-BFGS-B", "nlminb"), function(engine)
  gt_fit(d, "y", design, gt_family("binary", "logit"), control = controls(engine)))
for (i in seq_along(fits)) {
  fit <- fits[[i]]
  engine <- c("L-BFGS-B", "nlminb")[[i]]
  diagnostics <- gt_diagnostics(fit)$diagnostics
  stopifnot(fit$numerically_accepted, fit$covariance_components$item[[1]] > .01,
    diagnostics$optimizer == engine, diagnostics$optimizer_fixed_across_attempts,
    diagnostics$optimization_trials == 6L, diagnostics$optimization_trial_budget == 6L,
    all(vapply(diagnostics$attempts, function(x) x$optimizer == engine, logical(1))))
  if (engine == "nlminb") stopifnot(all(vapply(diagnostics$attempts, function(x)
    is.numeric(x$raw_result$objective) && is.null(x$raw_result$value) &&
      x$optimizer_control$iter.max == 300L && x$optimizer_control$eval.max == 3000,
    logical(1))))
}
near(fits[[1]]$minus2loglik, fits[[2]]$minus2loglik, 1e-6)
near(fits[[1]]$covariance_components$item, fits[[2]]$covariance_components$item, 1e-3)

# Complete warm starts match by names; partial starts leave automatic values
# in unspecified positions. Neither form fixes any model parameter.
warm <- rev(fits[[1]]$parameters)
refit <- gt_fit(d, "y", design, gt_family("binary", "logit"),
                control = controls("nlminb", warm))
stopifnot(refit$numerically_accepted)
near(refit$starting_parameters, warm[names(refit$starting_parameters)], 1e-12)
near(refit$minus2loglik, fits[[1]]$minus2loglik, 1e-6)
partial <- c("item::variance[y]" = 0)
escaped <- gt_fit(d, "y", design, gt_family("binary", "logit"),
                  control = controls("nlminb", partial))
stopifnot(escaped$numerically_accepted, escaped$starting_parameters[[2]] == 0,
          escaped$covariance_components$item[[1]] > .01)
near(escaped$minus2loglik, fits[[1]]$minus2loglik, 1e-6)
diagnostics <- gt_diagnostics(escaped)$diagnostics
near(diagnostics$starting_parameters[[1]], diagnostics$automatic_starting_parameters[[1]])
expect_error(gt_fit(d, "y", design, gt_family("binary"), control = controls("typo")), "optimizer")
for (invalid in list(0, numeric(), c(x = NA_real_), c(x = 1, x = 2), matrix(1)))
  expect_error(gt_fit(d, "y", design, gt_family("binary"),
                      control = controls("nlminb", invalid)), "named numeric")
expect_error(gt_fit(d, "y", design, gt_family("binary"),
  control = controls("nlminb", c(unknown = 0))), "Unknown discrete start")
expect_error(gt_fit(d, "y", design, gt_family("binary"),
  control = controls("nlminb", c("item::variance[y]" = -1))), "model bounds")
expect_error(gt_fit(d, "y", design, gt_family("binary"),
  control = controls("nlminb", c("y::intercept" = 16))), "model bounds")
no_restart <- suppressWarnings(gt_fit(d, "y", design, gt_family("binary", "logit"),
  control = controls("nlminb", alternatives = 0L)))
stopifnot(!no_restart$numerically_accepted,
          no_restart$diagnostics$optimization_trials == 2L)
many <- gt_fit(d, "y", design, gt_family("binary", "logit"),
               control = controls("nlminb", alternatives = 5L))
preliminary <- Filter(function(x) !grepl("tight", x$label), many$diagnostics$attempts)
starts <- do.call(rbind, lapply(preliminary, `[[`, "start"))
stopifnot(many$numerically_accepted, nrow(starts) == 6L,
          nrow(unique(starts)) == 6L, many$diagnostics$optimization_trials == 12L)
for (override in list(NULL, c("y::intercept" = 0)))
  expect_error(gt_fit(d, "y", design, gt_family("binary"),
    control = gt_control(discrete = list(covariance_parameterization = "log_cholesky",
      start_sd = 1e-6, start = override))), "model bounds")
ambiguous <- c("c", "b,c", "a", "a,b")
for (name in ambiguous) d[[name]] <- d$y
expect_error(gt_fit(d, ambiguous, design, gt_family("binary")), "ambiguous discrete parameter names")
cat("PASS: named starts, bounded optimizer selection, unchanged trial plan, native diagnostics, and rejected invalid controls.\n")

# Exact boundary likelihood fixtures cover all discrete families and both
# cumulative links using the explicitly selected second optimizer.
d$y <- as.integer(d$occasion <= 6)
d$o <- ordered(rep(c("a", "b", "c"), each = 4, length.out = nrow(d)))
d$n <- factor(d$o)
set.seed(314)
rng <- .Random.seed
for (kind in c("binary", "ordinal", "categorical")) {
  links <- if (kind == "categorical") "softmax" else c("logit", "probit")
  outcome <- switch(kind, binary = "y", ordinal = "o", categorical = "n")
  for (link in links) {
    fit <- gt_fit(d, outcome, design, gt_family(kind, link), covariance = "diagonal",
                  control = controls("nlminb"))
    stopifnot(fit$numerically_accepted, all(fit$covariance_components$item == 0),
      fit$approximation_adequacy == "exact_no_random_variation")
    counts <- table(d[[outcome]])
    near(fit$minus2loglik, -2 * sum(counts * log(counts / sum(counts))), 1e-7)
  }
}
stopifnot(identical(.Random.seed, rng))
cat("PASS: explicit nlminb zero-boundary binary, ordinal, and nominal fits preserve the exact likelihood and caller RNG state.\n")
