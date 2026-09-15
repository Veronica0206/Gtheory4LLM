# Installed-package regression tests: conditional-mode failures during finite
# differences must not become apparently flat derivatives through cancellation
# of the optimizer's finite penalty. Local function copies keep fault injection
# separate from the installed namespace and the actual optimization workflow.
library(Gtheory4LLM)
ns <- asNamespace("Gtheory4LLM")
internal <- function(name) get(name, envir = ns, inherits = FALSE)
expect_error <- function(expr, text) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(text, conditionMessage(error), fixed = TRUE))
}

make_probe <- function(kind) {
  env <- new.env(parent = ns)
  # Rebind every layer between stationarity and the pure response kernel so
  # failed conditional responses propagate through the real dense mode solver.
  for (name in c("gt_fit", ".gt_fit_discrete", ".gt_d_stationarity",
                 ".gt_d_laplace", ".gt_d_dense_mode", ".gt_d_dense_evaluate",
                 ".gt_d_response_kernel")) {
    fun <- internal(name)
    environment(fun) <- env
    env[[name]] <- fun
  }
  state <- new.env(parent = emptyenv())
  state$active <- FALSE
  state$invalid_response <- FALSE
  state$evaluations <- list()
  original_response <- env$.gt_d_response_kernel
  original_laplace <- env$.gt_d_laplace
  original_stationarity <- env$.gt_d_stationarity
  env$.gt_d_response_kernel <- function(eta, parameters, prep) {
    if (state$invalid_response) return(list(valid = FALSE))
    original_response(eta, parameters, prep)
  }
  env$.gt_d_laplace <- function(parameters, prep, groups, setup, control,
                                details = FALSE, factors_override = NULL) {
    if (!state$active)
      return(original_laplace(parameters, prep, groups, setup, control,
                              details, factors_override))
    delta <- parameters[[1L]] - state$center[[1L]]
    covariance_change <- tcrossprod(factors_override[[1L]]) - state$covariance
    state$invalid_response <- switch(kind,
      fixed_symmetric = delta != 0,
      fixed_positive = delta > 0,
      fixed_negative = delta < 0,
      # Previously the failed positive coarse probe could be discarded when
      # both fine probes failed, yielding zero disagreement after refinement.
      fixed_asymmetric_refinement = delta > 0 ||
        (delta < 0 && abs(delta) < 0.75e-4),
      fixed_after_refinement = delta != 0 && abs(delta) < 0.375e-4,
      center_invalid = delta == 0 && all(covariance_change == 0),
      covariance_diagonal = any(diag(covariance_change) > 1e-8),
      covariance_positive_contrast = nrow(covariance_change) > 1L &&
        covariance_change[1L, 2L] > 1e-8,
      covariance_negative_contrast = nrow(covariance_change) > 1L &&
        covariance_change[1L, 2L] < -1e-8,
      FALSE)
    on.exit({ state$invalid_response <- FALSE })
    value <- original_laplace(parameters, prep, groups, setup, control,
                              details, factors_override)
    # Additional malformed detailed records exercise both independent gates:
    # an apparently valid mode still needs convergence and a usable objective.
    center <- delta == 0 && all(covariance_change == 0)
    if (details && isTRUE(value$valid)) {
      if ((kind == "center_unconverged" && center) ||
          (kind == "probe_unconverged" && delta > 0)) value$inner_converged <- FALSE
      if ((kind == "center_penalty" && center) ||
          (kind == "probe_penalty" && delta > 0)) value$nll <- 1e100
      if ((kind == "center_nonfinite" && center) ||
          (kind == "probe_nonfinite" && delta > 0)) value$nll <- Inf
      if (kind == "center_missing" && center) value$nll <- NULL
      if (kind == "fixed_after_refinement") value$nll <- value$nll + 1e6 * delta^3
    }
    state$evaluations[[length(state$evaluations) + 1L]] <- list(
      delta = delta, details = details, response_failed = state$invalid_response,
      covariance_change = covariance_change)
    value
  }
  # Stationarity takes the marginal evaluator the fit is using, so that the
  # outer numerical policy is single-sourced across backends. The probe has to
  # forward it, or the interception below would be bypassed and, worse, the
  # unused argument would surface as a validation failure rather than as an
  # obvious error.
  # The default must be the intercepting evaluator in env, not a bare
  # .gt_d_laplace: this wrapper's lexical parent is make_probe's frame, so a
  # bare name would resolve outside env and silently bypass the interception
  # for callers that invoke the wrapper without naming the evaluator.
  env$.gt_d_stationarity <- function(parameters, prep, groups, setup, control, final,
                                     laplace = env$.gt_d_laplace) {
    state$active <- TRUE
    state$center <- parameters
    state$covariance <- tcrossprod(final$factors[[1L]])
    on.exit({ state$active <- FALSE })
    original_stationarity(parameters, prep, groups, setup, control, final,
                          laplace = laplace)
  }
  list(env = env, state = state)
}

d <- expand.grid(occasion = seq_len(12), item = seq_len(8))
d$y <- as.integer(d$occasion <= 6L)
design <- gt_design("item", "occasion", random = ~ item)
fixed_control <- gt_control(discrete = list(
  fixed_covariance = list(item = matrix(0)), alternative_starts = 1L))
free_control <- gt_control(discrete = list(
  covariance_parameterization = "variance", alternative_starts = 1L,
  maxit = 300L))

fit_probe <- function(kind) {
  probe <- make_probe(kind)
  fit <- suppressWarnings(probe$env$gt_fit(d, "y", design,
    gt_family("binary", "logit"), control = if (kind == "covariance_diagonal")
      free_control else fixed_control))
  stopifnot(inherits(fit, "gt_fit"), is.finite(fit$minus2loglik),
            length(fit$covariance_components) == 1L)
  if (kind == "control") {
    stopifnot(fit$numerically_accepted,
              fit$diagnostics$outer_stationarity$stationary_within_tolerance,
              fit$diagnostics$outer_stationarity$tolerance == 1e-3,
              identical(fit$covariance_components$item[[1L]], 0))
    stopifnot(all(gt_reliability(fit, scale = "latent")$per_trait$Erho2 == 0))
    gt_dstudy(fit, data.frame(occasion = c(6L, 12L)), scale = "latent")
  } else {
    error <- fit$diagnostics$outer_stationarity$error
    location <- if (grepl("^center_", kind)) "center" else if (
      kind == "covariance_diagonal") "covariance source item diagonal" else "fixed parameter y::intercept"
    stopifnot(!fit$numerically_accepted,
              !fit$diagnostics$outer_stationarity$stationary_within_tolerance,
              "validation_computation_failed" %in% fit$diagnostics$acceptance_failures,
              "outer_stationarity_failed" %in% fit$diagnostics$acceptance_failures,
              is.character(error), length(error) == 1L,
              grepl(paste("Stationarity validation failed at", location), error, fixed = TRUE))
    expect_error(gt_reliability(fit, scale = "latent"), "numerically converged")
    expect_error(gt_dstudy(fit, data.frame(occasion = 12), scale = "latent"),
                 "numerically converged")
    if (kind %in% c("fixed_symmetric", "fixed_positive", "fixed_negative",
                    "fixed_asymmetric_refinement", "fixed_after_refinement",
                    "center_invalid", "covariance_diagonal")) {
      failed <- vapply(probe$state$evaluations, `[[`, logical(1), "response_failed")
      # Fail on the first unusable probe; never let a later refinement erase it.
      stopifnot(sum(failed) == 1L, tail(failed, 1L))
    }
    if (kind == "fixed_after_refinement") {
      steps <- abs(vapply(probe$state$evaluations, `[[`, numeric(1), "delta"))
      # Valid coarse and fine probes forced one genuine refinement, followed
      # by a failed quarter-step. The failure is still retained in the fit.
      stopifnot(any(abs(steps - 1e-4) < 1e-12),
                any(abs(steps - 5e-5) < 1e-12),
                abs(tail(steps, 1L) - 2.5e-5) < 1e-12)
    }
  }
  invisible(fit)
}

for (kind in c("control", "fixed_symmetric", "fixed_positive", "fixed_negative",
                "fixed_asymmetric_refinement", "fixed_after_refinement",
                "center_invalid", "center_unconverged", "center_penalty",
                "center_nonfinite", "center_missing", "probe_unconverged",
                "probe_penalty", "probe_nonfinite", "covariance_diagonal"))
  fit_probe(kind)
cat("PASS: invalid centers and fixed/covariance probes remain explicit failures in inspectable fits and block G/Phi/D-study.\n")

# The off-diagonal PSD contrast probes in unstructured joint models use the
# same strict evaluator. Evaluate at a real, finite joint-model conditional
# mode without replacing either the Laplace calculation or covariance algebra.
d$z <- as.integer(d$occasion %% 2L == 0L)
prep <- internal(".gt_d_prepare")(d, c("y", "z"), rep(list(
  list(family = "binary", link = "logit", levels = c("0", "1"))), 2L))
groups <- list(item = internal(".gt_d_group")(d, "item"))
control <- internal(".gt_d_control")(list())
setup <- internal(".gt_d_covariance_setup")(groups, prep$q,
  "unstructured", control, prep$dimensions)
parameters <- c(prep$start, setup$start)
final <- internal(".gt_d_laplace")(parameters, prep, groups, setup, control,
                                  details = TRUE)
stopifnot(final$valid, final$inner_converged, is.finite(final$nll))
for (kind in c("covariance_positive_contrast", "covariance_negative_contrast")) {
  probe <- make_probe(kind)
  captured <- internal(".gt_d_capture")(probe$env$.gt_d_stationarity(
    parameters, prep, groups, setup, control, final))
  location <- if (kind == "covariance_positive_contrast")
    "positive contrast 1 2" else "negative contrast 1 2"
  stopifnot(is.null(captured$value),
    grepl(paste0("Stationarity validation failed at covariance source item ", location),
          captured$error, fixed = TRUE),
    tail(vapply(probe$state$evaluations, `[[`, logical(1), "response_failed"), 1L))
}
cat("PASS: both signed off-diagonal covariance contrasts reject invalid conditional modes.\n")
