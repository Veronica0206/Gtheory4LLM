# These tests run against the installed package, not a source-loaded copy.
library(Gtheory4LLM)
ns <- asNamespace("Gtheory4LLM")
internal <- function(name) get(name, envir = ns, inherits = FALSE)
near <- function(a, b, tolerance = 1e-6) {
  stopifnot(isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance,
                            check.attributes = FALSE)))
}
expect_error <- function(expr, text) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(text, conditionMessage(error), fixed = TRUE))
}

# The reported probabilities use the stable interval calculation, including
# single-row output. Log probabilities remain available below underflow.
probability <- internal(".gt_d_ordinal_probabilities")
for (link in c("probit", "logit")) {
  eta <- c(-40, -9, 0, 9, 40)
  p <- probability(eta, c(0, 1), link)
  lp <- probability(eta, c(0, 1), link, log = TRUE)
  stopifnot(identical(dim(p), c(5L, 3L)), all(is.finite(lp)),
            all(p >= 0), all(p <= 1), all(abs(rowSums(p) - 1) < 1e-12))
  near(exp(lp), p, 1e-12)
  stopifnot(identical(dim(probability(-9, c(0, 1), link)), c(1L, 3L)))
}
tail <- probability(-9, c(0, 1), "probit")
expected <- pnorm(9, lower.tail = FALSE) - pnorm(10, lower.tail = FALSE)
stopifnot(tail[1, 2] > 0, abs(tail[1, 2] / expected - 1) < 1e-12)
expect_error(probability(0, c(1, 0), "probit"), "Invalid ordinal")
expect_error(probability(0, c(0, 1), "unknown"), "Invalid ordinal")
cat("PASS: stable ordinal output, both links, single rows, and extreme tails.\n")

# Unit tests inject optimizer failures without modifying the package namespace.
optimize <- internal(".gt_d_optimize")
quadratic <- function(x) sum((x - 1)^2)
broken <- function(...) stop("injected optimizer error")
attempt <- optimize(c(a = 0), quadratic, -2, 2, list(maxit = 20), "injected", broken)
stopifnot(!attempt$result_available, attempt$convergence == 100L,
          identical(attempt$attempt$error, "injected optimizer error"),
          identical(attempt$attempt$label, "injected"),
          identical(attempt$attempt$start, c(a = 0)))
warning_optimizer <- function(...) {
  warning("injected optimizer warning")
  list(par = c(a = 1), value = 0, convergence = 0L, message = NULL)
}
warned <- optimize(c(a = 0), quadratic, -2, 2, list(maxit = 20),
                   "warning", warning_optimizer)
stopifnot(warned$result_available,
          identical(warned$attempt$warnings, "injected optimizer warning"))
raw_invalid <- list(par = c(a = NA_real_), value = 23, convergence = 52L,
                    message = "original optimizer diagnostic", counts = setNames(7L, "function"))
invalid <- optimize(c(a = 0), quadratic, -2, 2, list(maxit = 20), "invalid",
  function(...) raw_invalid)
stopifnot(!invalid$result_available, is.infinite(invalid$value),
          identical(invalid$attempt$raw_result, raw_invalid),
          identical(invalid$attempt$raw_result$message, "original optimizer diagnostic"),
          identical(invalid$par, c(a = 0)), invalid$convergence == 100L,
          identical(invalid$attempt$parameters, invalid$par))
# An invalid non-list return and a thrown error also retain their distinct
# originals; normalized sentinels are solely for downstream computations.
malformed <- optimize(c(a = 0), quadratic, -2, 2, list(), "malformed", function(...) "bad return")
stopifnot(identical(malformed$attempt$raw_result, "bad return"),
          is.null(attempt$attempt$raw_result))

# Use a well-supported one-source model so the boundary is the issue being
# tested, not sparse categories, confounded kernels, or too few dimensions.
d <- expand.grid(occasion = seq_len(12), item = seq_len(8))
d$y <- as.integer(d$occasion <= 6L)
design <- gt_design("item", "occasion", random = ~ item)
control <- gt_control(discrete = list(maxit = 300L, alternative_starts = 2L))
for (link in c("logit", "probit")) {
  boundary <- gt_fit(d, "y", design, gt_family("binary", link), control = control)
  stopifnot(boundary$numerically_accepted,
            identical(boundary$covariance_components$item[[1L]], 0),
            identical(boundary$diagnostics$covariance_parameterization, "variance"),
            identical(boundary$diagnostics$covariance_parameterization_requested, "auto"),
            length(boundary$diagnostics$zero_variance_parameters) == 1L,
            !length(boundary$diagnostics$parameter_bounds),
            boundary$diagnostics$outer_stationarity$stationary_within_tolerance,
            boundary$diagnostics$stability$stable)
  stationarity <- boundary$diagnostics$outer_stationarity
  # Independent analytic Laplace objective at the balanced binary boundary:
  # f(v) = n log(2) + (8/2) log(1 + 12 w v), with w=1/4 or 2/pi.
  expected_derivative <- nrow(d) * if (link == "logit") 1 / 8 else 1 / pi
  near(stationarity$covariance_gradients$item[[1L]], expected_derivative, 1e-6)
  stopifnot(stationarity$tolerance == 1e-3,
            stationarity$finite_difference_disagreement <= stationarity$tolerance / 2)
  if (link == "probit") stopifnot(
    stationarity$finite_difference_refinement$covariance_refinements[["item"]] >= 1L)
  near(boundary$minus2loglik, 2 * nrow(d) * log(2), 1e-7)
  near(gt_reliability(boundary, scale = "latent")$per_trait$Erho2, 0, 1e-12)
}
cat("PASS: both binary links admit an exact-zero variance optimum with unchanged acceptance tolerances.\n")

# Known zero-variance ordinal and nominal boundaries have an independent
# multinomial likelihood and a positive one-sided covariance score. Test the
# numerical boundary check itself, separately from optimizer/restart behavior.
endpoint_data <- d
endpoint_data$y <- ordered(rep(c("low", "middle", "high"), length.out = nrow(d)),
                           levels = c("low", "middle", "high"))
endpoint_groups <- list(item = internal(".gt_d_group")(endpoint_data, "item"))
endpoint_control <- internal(".gt_d_control")(list(covariance_parameterization = "variance"))
for (specification in list(
    list(family = "ordinal", link = "logit", levels = levels(endpoint_data$y)),
    list(family = "ordinal", link = "probit", levels = levels(endpoint_data$y)),
    list(family = "categorical", link = "softmax", levels = levels(endpoint_data$y), reference = "low"))) {
  endpoint_prep <- internal(".gt_d_prepare")(endpoint_data, "y", list(specification))
  endpoint_setup <- internal(".gt_d_covariance_setup")(endpoint_groups, endpoint_prep$q,
    "diagonal", endpoint_control, endpoint_prep$dimensions)
  endpoint_parameters <- c(endpoint_prep$start, rep(0, length(endpoint_setup$start)))
  endpoint_final <- internal(".gt_d_laplace")(endpoint_parameters, endpoint_prep,
    endpoint_groups, endpoint_setup, endpoint_control, details = TRUE)
  endpoint_score <- internal(".gt_d_stationarity")(endpoint_parameters, endpoint_prep,
    endpoint_groups, endpoint_setup, endpoint_control, endpoint_final)
  stopifnot(endpoint_final$valid, endpoint_score$stationary_within_tolerance,
            endpoint_score$tolerance == 1e-3,
            endpoint_score$finite_difference_disagreement <= 5e-4)
  near(endpoint_final$nll, nrow(d) * log(3), 1e-10)
  if (specification$family == "ordinal") {
    thresholds <- internal(".gt_d_thresholds")(endpoint_prep$start)
    density <- if (specification$link == "logit") dlogis(thresholds) else dnorm(thresholds)
    information <- sum(diff(c(0, density, 0))^2 / (1 / 3))
  } else information <- 2 / 9
  near(diag(endpoint_score$covariance_gradients$item),
       rep(nrow(d) * information / 2, endpoint_prep$q), 1e-6)
}
cat("PASS: analytic ordinal logit/probit and diagonal nominal boundary likelihoods and covariance scores.\n")

# Explicit log-Cholesky retains its artificial-floor rejection.
legacy <- suppressWarnings(gt_fit(d, "y", design, gt_family("binary", "logit"),
  control = gt_control(discrete = list(covariance_parameterization = "log_cholesky",
    start_sd = exp(-10), maxit = 50L))))
stopifnot(!legacy$numerically_accepted,
          identical(legacy$diagnostics$covariance_parameterization, "log_cholesky"),
          "artificial_parameter_bound_contact" %in% legacy$diagnostics$acceptance_failures)

# An interior free-variance fit must also work; exact zero is not hard-coded.
d$y <- as.integer(d$occasion <= c(2L, 3L, 4L, 5L, 7L, 8L, 9L, 10L)[d$item])
interior <- gt_fit(d, "y", design, gt_family("binary", "logit"), control = control)
reference <- suppressWarnings(gt_fit(d, "y", design, gt_family("binary", "logit"),
  control = gt_control(discrete = list(covariance_parameterization = "log_cholesky",
    maxit = 300L, alternative_starts = 2L))))
stopifnot(interior$numerically_accepted, interior$covariance_components$item[[1L]] > .01,
          !length(interior$diagnostics$zero_variance_parameters))
near(interior$minus2loglik, reference$minus2loglik, 1e-5)
near(interior$covariance_components$item, reference$covariance_components$item, 1e-3)
escape <- gt_fit(d, "y", design, gt_family("binary", "logit"),
  control = gt_control(discrete = list(covariance_parameterization = "variance",
    start_sd = exp(-10), maxit = 300L, alternative_starts = 2L)))
stopifnot(escape$numerically_accepted, escape$covariance_components$item[[1L]] > .01)
near(escape$minus2loglik, interior$minus2loglik, 1e-5)

# Boundary stationarity must still reject an improving inward variance direction.
ctl <- internal(".gt_d_control")(list(covariance_parameterization = "variance"))
prep <- internal(".gt_d_prepare")(d, "y", list(list(family = "binary", link = "logit", levels = c("0", "1"))))
groups <- list(item = internal(".gt_d_group")(d, "item"))
setup <- internal(".gt_d_covariance_setup")(groups, 1L, "diagonal", ctl, "y")
par <- c(prep$start, 0)
final <- internal(".gt_d_laplace")(par, prep, groups, setup, ctl, details = TRUE)
score <- internal(".gt_d_stationarity")(par, prep, groups, setup, ctl, final)
stopifnot(!score$stationary_within_tolerance, score$covariance_gradients$item[[1L]] < 0)

# An intentionally nonsmooth objective has no stable finite right derivative.
# Exhausting the bounded refinements must reject it, even when its positive
# one-sided scores would otherwise satisfy the zero-variance cone projection.
rough_env <- new.env(parent = ns)
rough_env$.gt_d_laplace <- function(parameters, prep, groups, setup, control,
                                  details = FALSE, factors_override) {
  value <- 1 + parameters[[1L]]^2 + sqrt(sum(factors_override$item^2))
  if (details) list(valid = TRUE, inner_converged = TRUE, nll = value) else value
}
rough_score <- internal(".gt_d_stationarity")
environment(rough_score) <- rough_env
rough <- rough_score(c(0, 0), prep, groups, setup, ctl, final)
stopifnot(!rough$stationary_within_tolerance, rough$covariance_scaled_norm == 0,
          rough$finite_difference_disagreement > rough$tolerance / 2,
          rough$finite_difference_refinement$covariance_refinements[["item"]] == 6L)

# Independent latent dimensions in a diagonal joint model factor into the
# separate univariate likelihoods. An unstructured request must not be coerced.
d$z <- as.integer(d$occasion <= 6L)
joint <- gt_fit(d, c("y", "z"), design, gt_family("binary", "logit"),
                covariance = "diagonal", control = control)
stopifnot(joint$numerically_accepted, joint$covariance_components$item[2, 2] == 0,
          all(joint$covariance_components$item[row(diag(2)) != col(diag(2))] == 0))
near(joint$minus2loglik, interior$minus2loglik + 2 * nrow(d) * log(2), 1e-5)
expect_error(gt_fit(d, c("y", "z"), design, gt_family("binary", "logit"),
  covariance = "unstructured", control = gt_control(discrete = list(
    covariance_parameterization = "variance", maxit = 300L, alternative_starts = 2L))),
  "univariate or diagonal")
# The resolved default must not silently convert that unstructured request:
# 'auto' selects log-Cholesky coordinates and keeps every covariance parameter.
auto_joint <- gt_fit(d, c("y", "z"), design, gt_family("binary", "logit"),
                     covariance = "unstructured", control = control)
stopifnot(identical(auto_joint$diagnostics$covariance_parameterization, "log_cholesky"),
          identical(auto_joint$diagnostics$covariance_parameterization_requested, "auto"),
          length(auto_joint$diagnostics$starting_parameters) == 5L)
expect_error(gt_fit(d, "y", design, gt_family("binary"),
  control = gt_control(discrete = list(covariance_parameterization = "typo"))),
  "covariance_parameterization")
cat("PASS: nonzero free variance, boundary derivative, diagonal joint identity, and unsupported-mode rejection.\n")

# Local function copies isolate injected failures: no assignInNamespace(),
# source(), mutation of a package namespace, or external source tree is used.
make_local_fit <- function() {
  env <- new.env(parent = ns)
  env$.gt_fit_discrete <- internal(".gt_fit_discrete")
  environment(env$.gt_fit_discrete) <- env
  env$gt_fit <- gt_fit
  environment(env$gt_fit) <- env
  env
}
local <- make_local_fit()
local$.gt_d_optimize <- function(at, objective, lower, upper, optimizer_control, label, optimizer = "L-BFGS-B") {
  optimizer <- if (grepl("alternative", label)) broken else stats::optim
  optimize(at, objective, lower, upper, optimizer_control, label, optimizer)
}
failed_restart <- suppressWarnings(local$gt_fit(d, "y", design,
  gt_family("binary", "logit"), control = control))
stopifnot(inherits(failed_restart, "gt_fit"), !failed_restart$numerically_accepted,
          is.finite(failed_restart$minus2loglik),
          length(failed_restart$covariance_components) == 1L,
          any(vapply(failed_restart$diagnostics$attempts,
                     function(x) identical(x$error, "injected optimizer error"), logical(1))),
          "validation_computation_failed" %in% failed_restart$diagnostics$acceptance_failures)
expect_error(gt_reliability(failed_restart, scale = "latent"), "numerically converged")
expect_error(gt_dstudy(failed_restart, data.frame(occasion = 12), scale = "latent"), "numerically converged")

local <- make_local_fit()
local$.gt_d_optimize <- function(at, objective, lower, upper, optimizer_control, label, optimizer = "L-BFGS-B") {
  optimizer <- if (grepl("tight", label)) broken else stats::optim
  optimize(at, objective, lower, upper, optimizer_control, label, optimizer)
}
primary_retained <- suppressWarnings(local$gt_fit(d, "y", design,
  gt_family("binary", "logit"), control = control))
stopifnot(!primary_retained$numerically_accepted, is.finite(primary_retained$minus2loglik))

# A successful coarse alternative is still usable when the original primary
# and every tight optimizer attempt fail. Both alternatives are re-evaluated;
# neither an inspectable estimate nor a tight conditional mode licenses G/Phi.
local <- make_local_fit()
local$.gt_d_optimize <- function(at, objective, lower, upper, optimizer_control, label, optimizer = "L-BFGS-B") {
  optimizer <- if (label == "primary" || grepl("tight", label)) broken else stats::optim
  optimize(at, objective, lower, upper, optimizer_control, label, optimizer)
}
alternative_retained <- suppressWarnings(local$gt_fit(d, "y", design,
  gt_family("binary", "logit"), control = control))
stopifnot(inherits(alternative_retained, "gt_fit"),
          !alternative_retained$numerically_accepted,
          is.finite(alternative_retained$minus2loglik),
          grepl("^alternative_[12]$", alternative_retained$diagnostics$selected_attempt),
          alternative_retained$diagnostics$tight_final_mode,
          !alternative_retained$diagnostics$stability$stable,
          "validation_computation_failed" %in% alternative_retained$diagnostics$acceptance_failures)
checks <- alternative_retained$diagnostics$final_checks
stopifnot(all(c("alternative_1_fallback_tight", "alternative_2_fallback_tight") %in%
                vapply(checks, `[[`, character(1), "label")),
          all(vapply(checks, `[[`, logical(1), "valid")))
near(alternative_retained$minus2loglik, interior$minus2loglik, 1e-5)
expect_error(gt_reliability(alternative_retained, scale = "latent"), "numerically converged")
expect_error(gt_dstudy(alternative_retained, data.frame(occasion = 12), scale = "latent"),
             "numerically converged")

local <- make_local_fit()
local$.gt_d_stationarity <- function(...) stop("injected stationarity error")
failed_diagnostic <- suppressWarnings(local$gt_fit(d, "y", design,
  gt_family("binary", "logit"), control = control))
stopifnot(!failed_diagnostic$numerically_accepted, is.finite(failed_diagnostic$minus2loglik),
          identical(failed_diagnostic$diagnostics$outer_stationarity$error,
                    "injected stationarity error"))
expect_error(gt_reliability(failed_diagnostic, scale = "latent"), "numerically converged")

local <- make_local_fit()
local$.gt_d_optimize <- function(at, objective, lower, upper, optimizer_control, label, optimizer = "L-BFGS-B")
  optimize(at, objective, lower, upper, optimizer_control, label, broken)
no_fit <- tryCatch(local$gt_fit(d, "y", design, gt_family("binary", "logit"), control = control),
                   error = identity)
stopifnot(inherits(no_fit, "gt_discrete_numerical_failure"), length(no_fit$attempts) > 0L)
cat("PASS: restart/refinement/diagnostic exceptions preserve inspectable fits and block coefficients; total failure retains attempt records.\n")
