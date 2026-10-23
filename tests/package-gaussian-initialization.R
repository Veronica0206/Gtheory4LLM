# Square-root recovery through the public interface, against the installed
# package. An accepted primary attempt is identical under both policies, the
# control is validated, the record is reported, and a one-iteration ordinary
# budget exercises a real recovery without relaxing acceptance.
library(Gtheory4LLM)
check <- function(x, label) {
  if (!isTRUE(x)) stop(label, call. = FALSE)
  cat("PASS:", label, "\n")
}
set.seed(781L)
d <- expand.grid(subject = 1:12, rater = letters[1:3], occasion = 1:2,
                 KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
Y <- matrix(rnorm(nrow(d) * 3), nrow(d), 3) %*%
  chol(matrix(c(1, .2, .1, .2, 1.3, .1, .1, .1, .8), 3)) +
  matrix(rnorm(36), 12, 3)[d$subject, ] + matrix(rnorm(9), 3, 3)[match(d$rater, letters), ] +
  matrix(rnorm(6), 2, 3)[d$occasion, ]
d$one <- Y[, 1]; d$two <- Y[, 2]; d$three <- Y[, 3]
covariance <- c(subject = "unstructured", rater = "diagonal", occasion = "diagonal")
fit_with <- function(policy, estimator = "REML", max_iterations = 3000L) {
  warnings <- character()
  fit <- withCallingHandlers(gt_fit(cbind(one, two, three) ~ subject + rater + occasion, d,
    measured = "subject", covariance = covariance, estimator = estimator,
    control = gt_control(gaussian = list(extra_tries = 1L, check_hessian = TRUE, retry_seed = 439L,
      tolerance = 1e-10, max_iterations = max_iterations, threads = 1L, initialization = policy))),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") })
  fit
}
for (estimator in c("ML", "REML")) {
  auto <- fit_with("automatic", estimator); none <- fit_with("none", estimator)
  check(isTRUE(gt_diagnostics(auto)$numerically_accepted) && auto$optimization_trials == 1L &&
        identical(gt_components(auto), gt_components(none)) && identical(deviance(auto), deviance(none)) &&
        identical(auto$retry_attempts, none$retry_attempts) &&
        identical(gt_diagnostics(auto)$initialization$status, "not_invoked") &&
        identical(gt_diagnostics(none)$initialization$status, "disabled"),
        paste(estimator, "accepted primary attempt identical under automatic and none"))
}
univariate <- gt_fit(one ~ subject + rater + occasion, d, measured = "subject",
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 439L)))
check(identical(gt_diagnostics(univariate)$initialization$status, "not_applicable"),
      "a univariate model records the recovery as not applicable")
check(inherits(tryCatch(gt_fit(cbind(one, two, three) ~ subject + rater + occasion, d, measured = "subject",
        control = gt_control(gaussian = list(initialization = "bogus"))), error = identity), "error"),
      "an unknown initialization value is refused")
check(inherits(tryCatch(gt_fit(one ~ subject + rater + occasion, d, measured = "subject",
        control = gt_control(gaussian = list(engine = "lme4", initialization = "automatic"))), error = identity), "error"),
      "initialization is refused with the lme4 engine")
one_auto <- fit_with("automatic", max_iterations = 1L)
one_none <- fit_with("none", max_iterations = 1L)
init <- gt_diagnostics(one_auto)$initialization
primary_columns <- setdiff(names(one_none$retry_attempts), "returned_fit")
check(identical(one_auto$retry_attempts[1, primary_columns], one_none$retry_attempts[1, primary_columns]) &&
      init$status %in% c("handoff_eligible", "refused") && init$trigger_attempt == 1L &&
      init$ordinary_budget == 2L && is.null(init$context),
      "one-iteration budget: identical primary record, recovery invoked once, compact record")
check(identical(one_none$retry_attempts$start_type[2], "uniform_perturbation") &&
      identical(one_auto$retry_attempts$start_type[2],
        if (isTRUE(init$eligible)) "square_root_cold_recovery" else "uniform_perturbation"),
      "one-iteration budget: handoff when eligible, ordinary perturbation otherwise")
printed <- capture.output(print(gt_diagnostics(one_auto)))
check(any(grepl("Square-root initialization:", printed, fixed = TRUE)), "the diagnostics print reports the recovery")
for (fit in list(one_auto, one_none)) if (isTRUE(gt_diagnostics(fit)$numerically_accepted))
  check(fit$status == 0L && isTRUE(fit$diagnostics$independent_likelihood_matches) &&
        isTRUE(fit$diagnostics$covariance_stationarity$stationary_within_tolerance),
        "an accepted one-iteration fit passed every ordinary gate")
cat("PASS: square-root recovery through the public interface.\n")
