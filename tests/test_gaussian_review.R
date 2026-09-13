# Independent regression checks for the repository review's Gaussian findings.
# Run from the repository root in a clean R session.
source("R/design.R")
source("R/gaussian_engine.R")
source("R/gaussian.R")
stopifnot(requireNamespace("OpenMx", quietly = TRUE), requireNamespace("lme4", quietly = TRUE))
near <- function(a, b, tolerance = 1e-8) {
  stopifnot(isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance,
                            check.attributes = FALSE)))
}
expect_error <- function(expr, pattern) {
  err <- tryCatch({force(expr); NULL}, error = identity)
  stopifnot(inherits(err, "error"), grepl(pattern, conditionMessage(err), fixed = TRUE))
}
# Exercise derivative warning isolation without an optimizer or fit.
raw_warning <- "diagnostic-only fixture: status RED / Hessian not convex"
sentinel <- list(output = list(hessian = diag(2), infoDefinite = FALSE))
escaped <- character()
captured <- withCallingHandlers(.gt_gaussian_derivative_run(sentinel,
  run = function(model, silent) { warning(raw_warning, call. = FALSE); model }),
  warning = function(w) { escaped <<- c(escaped, conditionMessage(w)); invokeRestart("muffleWarning") })
stopifnot(identical(captured$model, sentinel), identical(captured$warnings, raw_warning),
          is.null(captured$error), !length(escaped))
failed <- .gt_gaussian_derivative_run(sentinel, run = function(model, silent) {
  warning(raw_warning, call. = FALSE); stop("derivative fixture failure", call. = FALSE)
})
stopifnot(is.null(failed$model), identical(failed$error, "derivative fixture failure"),
          identical(failed$warnings, raw_warning))
# Warnings outside the derivative call remain visible to the caller.
withCallingHandlers({
  .gt_gaussian_derivative_run(sentinel, run = function(model, silent) model)
  warning("optimizer fixture warning", call. = FALSE)
}, warning = function(w) { escaped <<- c(escaped, conditionMessage(w)); invokeRestart("muffleWarning") })
stopifnot(identical(escaped, "optimizer fixture warning"))
cat("PASS: derivative-only warnings and errors retain their exact text without hiding other warnings.\n")

set.seed(5012)
for (n in c(2L, 3L, 11L, 51L)) {
  x <- matrix(rnorm(n * 4L), n, 4L)
  h <- stats::contr.helmert(n)
  q <- cbind(rep(1 / sqrt(n), n), sweep(h, 2L, sqrt(colSums(h^2)), "/"))
  transformed <- .gt_helmert_transform(x)
  near(transformed, crossprod(q, x), 1e-13)
  near(crossprod(transformed), crossprod(x), 1e-13)
}
cat("PASS: implicit Helmert transform equals the dense normalized basis and preserves cross-products.\n")

# This object axis formerly required a 20,000-by-20,000 dense basis (3.2 GB).
large <- expand.grid(item = seq_len(20000L), rater = 1:2, KEEP.OUT.ATTRS = FALSE)
large$y <- sin(large$item) + large$rater / 10
engine <- .gt_gaussian_engine(c("item", "rater"))
prepared_large <- engine$prepare(large, "y")
stopifnot(prepared_large$N == 40000L,
          prepared_large$allocation$estimated_bytes < 20 * 1024^2,
          all(is.finite(unlist(lapply(prepared_large$strata, `[[`, "SSCP")))))
# A rejected request must not reach the contrast transform.
original_transform <- .gt_helmert_transform
.gt_helmert_transform <- function(...) stop("Unexpected transform allocation")
expect_error(engine$prepare(large, "y", max_preparation_bytes = 1024), "allocation estimate")
.gt_helmert_transform <- original_transform
cat("PASS: 40,000-row panel prepares with linear storage; explicit allocation guard precedes transformation.\n")

d <- expand.grid(item = 1:16, rater = 1:3, occasion = 1:2, KEEP.OUT.ATTRS = FALSE)
d$y <- rnorm(nrow(d)) + rnorm(16, sd = 1.4)[d$item] + c(-.8, 0, .8)[d$rater]
d$z <- .4 * d$y + rnorm(nrow(d), sd = 1.2)
d$w <- -.2 * d$y + rnorm(nrow(d), sd = .9)
design <- gt_design("item", c("rater", "occasion"), random = c("item", "rater"))
engine <- .gt_gaussian_engine(c("item", "rater", "occasion"))
p <- engine$prepare(d, c("y", "z", "w"))
shuffled <- d[sample(seq_len(nrow(d))), ]
q <- engine$prepare(shuffled, c("y", "z", "w"))
near(unlist(p$strata), unlist(q$strata), 1e-12)
# Changing labels only permutes orthonormal contrasts within the same stratum.
relabeled <- d
relabeled$item <- paste0("I", 100L - d$item)
relabeled$rater <- c("Z", "A", "M")[d$rater]
r <- engine$prepare(relabeled, c("y", "z", "w"))
near(unlist(p$strata), unlist(r$strata), 1e-12)
permuted <- engine$prepare(d, c("w", "y", "z"))
for (i in seq_along(p$strata))
  near(permuted$strata[[i]]$SSCP, p$strata[[i]]$SSCP[c(3,1,2), c(3,1,2)], 1e-12)
expect_error(engine$prepare(d[-1, ], c("y", "z", "w")), "within-parent index")
cat("PASS: multivariate preparation is invariant to row order and ID relabeling, and equivariant to outcome order.\n")

# Instrument the actual closure's preparation entry, including the fitter's
# lexical reference, to detect duplicate preparation in the public backend.
original_constructor <- .gt_gaussian_engine
preparation_calls <- 0L
.gt_gaussian_engine <- function(...) {
  e <- original_constructor(...)
  original_prepare <- e$prepare
  counted <- function(...) {
    preparation_calls <<- preparation_calls + 1L
    original_prepare(...)
  }
  assign("gtheory_prepare", counted, envir = environment(e$fit))
  e$prepare <- counted
  e
}
control <- list(extra_tries = 2L, check_hessian = FALSE, retry_seed = 821L,
                tolerance = 1e-10, max_iterations = 2000L)
ml <- .gt_fit_gaussian(d, "y", design, estimator = "ML", control = control)
.gt_gaussian_engine <- original_constructor
stopifnot(ml$converged, preparation_calls == 1L,
  !any(grepl("Specification only:", ml$design$notes, fixed = TRUE)))
reference <- lme4::lmer(y ~ 1 + (1|item) + (1|rater), d, REML = FALSE,
  control = lme4::lmerControl(optimizer = "bobyqa", optCtrl = list(rhoend = 1e-10)))
near(ml$minus2loglik, -2 * as.numeric(stats::logLik(reference)), 1e-8)
stopifnot(ml$n_model_parameters == attr(stats::logLik(reference), "df"))
near(ml$AIC, stats::AIC(reference), 1e-8)
near(ml$BIC, stats::BIC(reference), 1e-8)
near(ml$legacy_AIC + 2 * ml$D, ml$AIC, 1e-12)
cat("PASS: Gaussian backend prepares once; conventional ML parameter count and AIC/BIC match lme4.\n")

joint <- .gt_fit_gaussian(d, c("y", "z", "w"), design, estimator = "ML",
  covariance = "diagonal", residual = "diagonal", control = control)
stopifnot(joint$converged)
near(joint$ml_BIC_scalar_scores - joint$BIC, log(joint$D) * joint$n_model_parameters, 1e-12)
# Same model in different measurement units. With D=3 and scale=1e60 a raw
# covariance determinant overflows, although the standardized matrix is benign.
scaled <- d
scaled[c("y", "z", "w")] <- lapply(scaled[c("y", "z", "w")], `*`, 1e60)
scaled_fit <- .gt_fit_gaussian(scaled, c("y", "z", "w"), design, estimator = "ML",
  covariance = "diagonal", residual = "diagonal", control = control)
stopifnot(scaled_fit$converged, scaled_fit$diagnostics$independent_likelihood_matches)
near(scaled_fit$minus2loglik - joint$minus2loglik, 2 * joint$N * joint$D * log(1e60), 1e-10)
near(unlist(scaled_fit$covariance_components) / 1e120, unlist(joint$covariance_components), 1e-5)
cat("PASS: vector/scalar BIC conventions are explicit and Gaussian ML is equivariant under extreme common unit scaling.\n")

reml <- .gt_fit_gaussian(d, "y", design, estimator = "REML", control = control)
stopifnot(reml$converged, is.na(reml$AIC), is.na(reml$BIC),
          is.finite(reml$legacy_AIC), is.finite(reml$legacy_BIC),
          reml$reml_AIC_variance_parameters == reml$legacy_AIC)
cat("PASS: REML criteria have explicit restricted-likelihood names and no generic ML correction.\n")
cat("All Gaussian repository-review checks passed.\n")
