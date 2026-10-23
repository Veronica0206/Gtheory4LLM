# The same numerical-domain contract runs from sources and the installed archive.
if (identical(Sys.getenv("GT_DOMAIN_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
expect_error <- function(expr, text) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(text, conditionMessage(error), fixed = TRUE))
}
d <- expand.grid(item = 1:2, rater = 1:6)
d$y <- as.integer(d$rater <= 3)
d$o <- ordered(rep(c("low", "middle", "high"), length.out = nrow(d)))
design <- gt_design("item", "rater", random = ~ item)
fixed <- list(item = matrix(0, 1, 1))
control <- internal(".gt_d_control")
prepare <- internal(".gt_d_prepare")
setup <- internal(".gt_d_covariance_setup")
domain <- internal(".gt_d_parameter_domain")
groups <- list(item = internal(".gt_d_group")(d, "item"))
families <- list(o = gt_family("ordinal", "probit"))
prep <- prepare(d, "o", families)
ctl <- control(list(fixed_covariance = fixed))
base <- setup(groups, 1L, "unstructured", ctl, "o", prep$blocks)
default <- domain(prep, base, ctl)
stopifnot(identical(default$prep, prep), identical(default$setup, base),
          identical(default$lower, c(prep$lower, base$lower)),
          is.null(default$record$requested))
request <- list(lower = c("o::threshold_parameter1" = -30),
                upper = c("o::threshold_parameter1" = 40))
extended_control <- control(list(fixed_covariance = fixed, parameter_bounds = request))
extended <- domain(prep, base, extended_control)
parameter <- c("o::threshold_parameter1" = -20, "o::threshold_parameter2" = log(40))
stopifnot(all(parameter >= extended$lower & parameter <= extended$upper),
          identical(extended$record$requested, request))
# Only the declared search domain changes, never the ordinal likelihood.
reference <- internal(".gt_d_laplace")(parameter, prep, groups, base, ctl, details = TRUE)
replayed <- internal(".gt_d_laplace")(parameter, extended$prep, groups, extended$setup,
                                     extended_control, details = TRUE)
stopifnot(reference$valid, replayed$valid, identical(reference$nll, replayed$nll))
for (link in c("probit", "logit")) {
  pp <- prepare(d, "o", list(o = gt_family("ordinal", link)))
  p <- pp$start; eta <- matrix(seq(-1, 1, length.out = nrow(d)), ncol = 1)
  z <- internal(".gt_d_response_kernel")(eta, p, pp)
  p[[1]] <- p[[1]] + 30
  shifted <- internal(".gt_d_response_kernel")(eta + 30, p, pp)
  stopifnot(shifted$valid, abs(z$nll - shifted$nll) < 1e-10,
            max(abs(z$gradient - shifted$gradient)) < 1e-10)
}
for (bad in list(list(), list(low = c(x = 0)), list(lower = 0),
                list(lower = c(x = 0, x = 1)), list(upper = c(x = Inf))))
  expect_error(control(list(parameter_bounds = bad)), "parameter_bounds")
expect_error(domain(prep, base, control(list(parameter_bounds = list(lower = c(typo = -30))))),
             "Unknown parameter_bounds")
expect_error(domain(prep, base, control(list(parameter_bounds = list(lower = c("o::threshold_parameter1" = 15))))),
             "lower < upper")
for (side in c("lower", "upper")) {
  value <- if (side == "lower") -1000 else 1000
  bounds <- setNames(list(c("o::threshold_parameter2" = value)), side)
  expect_error(domain(prep, base, control(list(parameter_bounds = bounds))), "ordinal gaps")
}
free <- setup(groups, 1L, "unstructured", control(list()), "o", prep$blocks)
for (value in c(-1, 0.1))
  expect_error(domain(prep, free, control(list(parameter_bounds = list(
    lower = c("item::variance[o]" = value))))), "natural")
log_control <- control(list(covariance_parameterization = "log_cholesky"))
log_setup <- setup(groups, 1L, "unstructured", log_control, "o", prep$blocks)
expect_error(domain(prep, log_setup, control(list(parameter_bounds = list(
  upper = c("item::chol[o,o]" = 1000))))), "covariance")
expect_error(domain(prep, log_setup, control(list(parameter_bounds = list(
  lower = c("item::chol[o,o]" = -1000))))), "representably positive")
expect_error(domain(prep, log_setup, control(list(parameter_bounds = list(
  lower = c("item::chol[o,o]" = -400))))), "representably positive")
# A valid SPD matrix with a factor entry above ten is permitted explicitly.
joint <- prepare(transform(d, second = o), c("o", "second"), rep(families, 2))
js <- setup(groups, 2L, "unstructured", control(list()), joint$dimensions, joint$blocks)
wide <- domain(joint, js, control(list(parameter_bounds = list(
  upper = c("item::chol[second,o]" = 60)))))
stopifnot(wide$setup$upper[[2]] == 60)
expect_error(domain(joint, js, control(list(parameter_bounds = list(
  upper = c("item::chol[second,o]" = 1e200))))), "covariance")
expect_error(domain(joint, js, control(list(parameter_bounds = list(
  lower = c("item::chol[o,o]" = -1))))), "natural")
# Automatic starts are checked against the amended domain, including preflight.
large_start_control <- control(list(start_sd = 200, parameter_bounds = list(
  upper = c("item::variance[o]" = 50000))))
large_start_setup <- setup(groups, 1L, "unstructured", large_start_control, "o", prep$blocks)
large_start <- domain(prep, large_start_setup, large_start_control)
stopifnot(large_start$start[["item::variance[o]"]] == 40000)
expect_error(domain(prep, large_start_setup, control(list(parameter_bounds = request))),
             "model bounds")
cat("PASS: declared domains preserve likelihood, covariance models and natural boundaries; malformed and unrepresentable domains are refused.\n")

# Real public fits retain both domain identity and the bound-contact refusal.
binary_control <- gt_control(discrete = list(fixed_covariance = fixed,
  parameter_bounds = list(lower = c("y::intercept" = -30), upper = c("y::intercept" = 30))))
fit <- gt_fit(d, "y", design, gt_family("binary", "logit"), control = binary_control)
stopifnot(fit$numerically_accepted,
  fit$diagnostics$parameter_domain$effective$lower[["y::intercept"]] == -30,
  identical(fit$diagnostics$parameter_domain$requested, binary_control$discrete$parameter_bounds))
path <- tempfile(fileext = ".rds")
saveRDS(fit, path); retained <- readRDS(path); unlink(path)
check <- gt_laplace_check(retained, nodes = 8)
stopifnot(check$recomputed_agrees, abs(check$difference) < 1e-8)
retained$control$discrete$parameter_bounds$lower[[1]] <- -31
expect_error(gt_laplace_check(retained, nodes = 8), "recorded parameter domain")
bounded <- suppressWarnings(gt_fit(d, "y", design, gt_family("binary", "logit"),
  control = gt_control(discrete = list(fixed_covariance = fixed,
    parameter_bounds = list(upper = c("y::intercept" = 0))))))
stopifnot(!bounded$numerically_accepted,
  "artificial_parameter_bound_contact" %in% bounded$diagnostics$acceptance_failures,
  "y::intercept" %in% bounded$diagnostics$parameter_bounds,
  bounded$diagnostics$outer_stationarity$tolerance == 1e-3)
pre <- gt_preflight(d, "y", design, gt_family("binary", "logit"), control = binary_control)
stopifnot(all(pre$checks$passed))
bad_pre <- gt_preflight(d, "y", design, gt_family("binary", "logit"),
  control = gt_control(discrete = list(parameter_bounds = list(lower = c(typo = -30)))))
stopifnot(!all(bad_pre$checks$passed), any(grepl("Unknown parameter_bounds", bad_pre$checks$detail)))
cat("PASS: public fits and serialized diagnostics retain domains; preflight checks them, and artificial contact still refuses acceptance.\n")

# A domain narrower than the historical restart padding must keep every
# retained start feasible. This exact balanced binomial model has its optimum
# at zero, so optimizer failure is not a substitute for the bound policy.
narrow_bounds <- list(lower = c("y::intercept" = -2e-7),
                      upper = c("y::intercept" = 2e-7))
narrow_fits <- lapply(c(1e-4, 1e-10), function(bound_tol) {
  narrow_control <- gt_control(discrete = list(fixed_covariance = fixed,
    parameter_bounds = narrow_bounds, bound_tol = bound_tol))
  narrow_preflight <- gt_preflight(d, "y", design, gt_family("binary", "logit"),
    control = narrow_control)
  stopifnot(all(narrow_preflight$checks$passed))
  answer <- suppressWarnings(gt_fit(d, "y", design, gt_family("binary", "logit"),
    control = narrow_control))
  bounds <- answer$diagnostics$parameter_domain$effective
  stopifnot(length(answer$diagnostics$attempts) == 4L,
    all(vapply(answer$diagnostics$attempts, function(trial) {
      all(trial$start >= bounds$lower & trial$start <= bounds$upper) &&
        is.null(trial$error) && identical(trial$optimizer_code, 0L)
    }, logical(1))))
  answer
})
stopifnot(!narrow_fits[[1]]$numerically_accepted,
  "artificial_parameter_bound_contact" %in%
    narrow_fits[[1]]$diagnostics$acceptance_failures,
  narrow_fits[[2]]$numerically_accepted,
  isTRUE(narrow_fits[[2]]$diagnostics$stability$stable))

# The default and extended domains above retain the historical clipping map
# exactly. This guards against changing already-qualified wide-domain paths.
for (candidate in list(default, extended, wide, large_start)) {
  width <- candidate$upper - candidate$lower
  padding <- pmin(1e-6, width / 4)
  stopifnot(all(width >= 4e-6), all(padding == 1e-6))
  for (proposal in list(candidate$lower - 1, candidate$start,
                        candidate$upper + 1)) {
    previous <- pmin(candidate$upper - 1e-6,
      pmax(candidate$lower + 1e-6, proposal))
    current <- pmin(candidate$upper - padding,
      pmax(candidate$lower + padding, proposal))
    stopifnot(identical(previous, current))
  }
}
cat("PASS: narrow domains keep every restart feasible; artificial contact still refuses, and wide-domain clipping is unchanged.\n")
