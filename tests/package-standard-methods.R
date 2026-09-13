# Installed-package checks for the standard R extractors on a fitted model.
#
# The point of these methods is that they agree with the fit's own recorded
# conventions, and that they refuse rather than invent where this
# implementation has no sampling uncertainty to report. Both halves are checked.
library(Gtheory4LLM)

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
near <- function(a, b, label, tolerance = 1e-10)
  expect(isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance)), label)
expect_error <- function(expr, pattern, label) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  expect(inherits(error, "error"), paste(label, "raises an error"))
  expect(grepl(pattern, conditionMessage(error)), paste(label, "explains why"))
  invisible(conditionMessage(error))
}

set.seed(9)
panel <- expand.grid(rater = factor(1:4), item = factor(1:20))
panel$y <- rnorm(20, sd = 1.1)[panel$item] + rnorm(4, sd = .4)[panel$rater] +
  rnorm(nrow(panel), sd = .8)
panel$z <- .6 * rnorm(20, sd = 1.1)[panel$item] + rnorm(nrow(panel), sd = .9)
design <- gt_design("item", "rater")

reml <- gt_fit(panel, "y", design, estimator = "REML")
ml <- gt_fit(panel, "y", design, estimator = "ML")

# --- nobs counts response vectors -------------------------------------------
expect(identical(nobs(reml), nrow(panel)), "nobs counts measurement rows")
expect(is.integer(nobs(reml)), "nobs returns an integer")
joint <- gt_fit(panel, c("y", "z"), design, estimator = "ML", covariance = "unstructured")
expect(identical(nobs(joint), nrow(panel)),
       "a joint fit counts response vectors, not outcome-by-row scalars")

# --- logLik carries the estimator's own parameter count ----------------------
value <- logLik(reml)
expect(inherits(value, "logLik"), "logLik returns a logLik object")
near(as.numeric(value), -reml$minus2loglik / 2, "logLik is minus half the deviance")
expect(identical(attr(value, "df"), as.integer(reml$n_variance_parameters)),
       "a REML fit counts covariance parameters only")
expect(isTRUE(attr(value, "REML")), "a REML fit is labelled as restricted")
expect(identical(attr(value, "likelihood"), "restricted"), "the likelihood kind is labelled")
expect(identical(attr(value, "nobs"), nrow(panel)), "logLik carries the observation count")

ml_value <- logLik(ml)
expect(identical(attr(ml_value, "df"), as.integer(ml$n_model_parameters)),
       "an ML fit counts covariance parameters and profiled means")
expect(isFALSE(attr(ml_value, "REML")), "an ML fit is not labelled restricted")
expect(attr(ml_value, "df") > attr(value, "df"),
       "ML counts more parameters than REML for the same model")

# --- Information criteria reproduce the fit's recorded conventions -----------
near(AIC(ml), ml$ml_AIC, "AIC of an ML fit is the recorded ML AIC")
near(BIC(ml), ml$ml_BIC_response_vectors, "BIC of an ML fit uses N response vectors")
near(AIC(reml), reml$reml_AIC_variance_parameters,
     "AIC of a REML fit is the recorded restricted-likelihood AIC")
near(BIC(reml), reml$minus2loglik + log(nrow(panel)) * reml$n_variance_parameters,
     "BIC of a REML fit uses N response vectors and covariance parameters")
near(BIC(joint), joint$ml_BIC_response_vectors,
     "a joint ML fit's BIC uses response vectors")
expect(!isTRUE(all.equal(BIC(joint), joint$ml_BIC_scalar_scores)),
       "the N * D scalar-score convention stays a separately named alternative")

# --- coef reports location parameters, never variances -----------------------
expect(identical(coef(reml), reml$means), "Gaussian coefficients are the profiled means")
expect(identical(names(coef(joint)), c("y", "z")), "a joint fit reports one mean per outcome")
expect(!any(names(coef(reml)) %in% names(reml$covariance_components)),
       "variance components are not returned as coefficients")

# --- vcov describes source covariances, and says so --------------------------
V <- vcov(reml)
expect(is.matrix(V) && nrow(V) == ncol(V), "vcov returns a square matrix")
expect(identical(rownames(V), rownames(reml$uncertainty$entry_covariance)),
       "vcov is labelled by source covariance entry")
expect(grepl("not the covariance of coef", attr(V, "scope")),
       "vcov states that it is not the covariance of coef()")
expect(isTRUE(all.equal(V, unname(reml$uncertainty$entry_covariance), check.attributes = FALSE)),
       "vcov is the fit's own delta-method entry covariance")
expect(isTRUE(all.equal(sqrt(diag(V)[paste0("item[y,y]")]),
                        reml$component_standard_errors$std_error[
                          reml$component_standard_errors$component == "item"],
                        check.attributes = FALSE)),
       "vcov diagonal reproduces the reported component standard errors")
parameters <- vcov(reml, "parameters")
expect(is.matrix(parameters), "the parameter covariance matrix is available")
expect(isTRUE(all.equal(parameters, unname(reml$uncertainty$parameter_covariance),
                        check.attributes = FALSE)),
       "the parameter covariance is the fit's own 2 H^-1")
expect_error(vcov(reml, "nonsense"), "arg", "an unknown vcov type")

# Disabling the Hessian removes the uncertainty, and vcov must say which.
without <- gt_fit(panel, "y", design,
                  control = gt_control(gaussian = list(check_hessian = FALSE)))
expect_error(vcov(without), "Hessian diagnostics were disabled",
             "vcov on a fit without Hessian diagnostics")

# --- Discrete fits have no observed information ------------------------------
set.seed(4)
discrete_panel <- expand.grid(rater = factor(1:6), item = factor(1:16))
latent <- rnorm(16, sd = .8)[discrete_panel$item] + rnorm(6, sd = .4)[discrete_panel$rater]
discrete_panel$b <- rbinom(nrow(discrete_panel), 1L, plogis(latent))
graded <- latent + rlogis(nrow(discrete_panel))
discrete_panel$g <- ordered(c("a", "b", "c")[1L + (graded > -.5) + (graded > .7)],
                            levels = c("a", "b", "c"))
reduced <- gt_design("item", "rater", full_cell = FALSE)

binary <- suppressWarnings(gt_fit(discrete_panel, "b", reduced, gt_family("binary"),
  control = gt_control(discrete = list(maxit = 200L))))
ordinal <- suppressWarnings(gt_fit(discrete_panel, "g", reduced, gt_family("ordinal"),
  control = gt_control(discrete = list(maxit = 200L))))

for (fit in list(binary, ordinal)) {
  value <- logLik(fit)
  near(as.numeric(value), -fit$minus2loglik / 2, "discrete logLik is minus half the deviance")
  expect(identical(attr(value, "df"), as.integer(fit$npar)),
         "a discrete fit counts every free parameter")
  expect(identical(attr(value, "likelihood"), "first_order_laplace_marginal"),
         "a discrete log likelihood is labelled as a Laplace approximation")
  expect(isFALSE(attr(value, "REML")), "a discrete fit is not restricted")
  expect(identical(nobs(fit), nrow(discrete_panel)), "a discrete fit counts its rows")
  expect_error(vcov(fit), "no observed information",
               "vcov on a discrete fit")
}
expect(identical(names(coef(binary)), "b"), "a binary fit reports its intercept")
expect(identical(names(coef(ordinal)), c("g::a|b", "g::b|c")),
       "an ordinal fit reports its thresholds as location parameters")
near(unname(coef(ordinal)), unname(ordinal$thresholds$g),
     "ordinal coefficients are the fitted thresholds")
expect(!any(coef(ordinal) == 0),
       "the structurally zero ordinal dimension mean is not reported as an estimate")

# --- Diagnostics print without re-running any check --------------------------
diagnostics <- gt_diagnostics(reml)
expect(inherits(diagnostics, "gt_diagnostics"), "gt_diagnostics returns a classed object")
expect(is.function(getS3method("print", "gt_diagnostics")), "a print method is registered")
output <- capture.output(returned <- print(diagnostics))
expect(identical(returned, diagnostics), "printing returns the object invisibly")
expect(any(grepl("Numerically accepted: TRUE", output, fixed = TRUE)),
       "the acceptance decision is printed")
expect(any(grepl("Likelihood approximation:", output, fixed = TRUE)),
       "the approximation status is printed")
expect(length(output) < 25L, "the diagnostics report stays readable")
expect(!any(grepl("MxModel|\\$data", output)), "printing never dumps the model or the data")

rejected_output <- capture.output(print(gt_diagnostics(
  suppressWarnings(gt_fit(discrete_panel, "b", reduced, gt_family("binary"),
    control = gt_control(discrete = list(maxit = 200L, alternative_starts = 0L)))))))
expect(any(grepl("Numerically accepted: FALSE", rejected_output, fixed = TRUE)),
       "a rejected fit prints as rejected")
expect(any(grepl("restart_or_tolerance_stability_failed", rejected_output, fixed = TRUE)),
       "the acceptance failure is named")
expect(any(grepl("diagnostic only", rejected_output, fixed = TRUE)),
       "a rejected fit says its estimates are diagnostic only")

# Dispatch keeps these methods away from foreign objects, so the guards are
# checked by invoking the registered methods directly.
impostor <- structure(list(minus2loglik = 1, N = 1L), class = "not_a_fit")
for (generic in c("logLik", "nobs", "coef", "vcov"))
  expect_error(getS3method(generic, "gt_fit")(impostor), "Expected a gt_fit",
               paste(generic, "on a foreign object"))

cat("PASS: logLik, nobs, coef, vcov, information criteria, and diagnostics printing.\n")

# --- Retention controls change size, never results ---------------------------
lean_control <- gt_control(retain = list(data = FALSE, model = FALSE,
                                         session = FALSE, retry_log = FALSE))
lean <- gt_fit(panel, "y", design, control = lean_control)
expect(is.null(lean$data), "dropping the data removes it from the fit")
expect(is.null(lean$model) && is.null(lean$backend_fit), "dropping the model removes it")
expect(is.null(lean$session), "dropping the session record removes it")
expect(is.null(lean$retry_log), "dropping the retry log removes it")
expect(identical(lean$retained, c(data = FALSE, model = FALSE,
                                  retry_log = FALSE, session = FALSE)),
       "the fit records which components were dropped")
expect(as.numeric(object.size(lean)) < as.numeric(object.size(reml)) / 2,
       "dropping the stored copies of the data at least halves the fit")

expect(identical(gt_reliability(lean)$per_trait, gt_reliability(reml)$per_trait),
       "reliability is unchanged by retention")
expect(identical(gt_dstudy(lean, data.frame(rater = c(2, 4, 8)))$results,
                 gt_dstudy(reml, data.frame(rater = c(2, 4, 8)))$results),
       "a decision study is unchanged by retention")
expect(identical(gt_components(lean, correlation = TRUE),
                 gt_components(reml, correlation = TRUE)),
       "correlations are unchanged: the observed outcome scale is always kept")
expect(identical(summary(lean)$variances, summary(reml)$variances),
       "the source-variance table is unchanged by retention")
expect(identical(gt_diagnostics(lean), gt_diagnostics(reml)),
       "every diagnostic decision and reason is unchanged by retention")
expect(identical(logLik(lean), logLik(reml)), "the log likelihood is unchanged")
expect(identical(vcov(lean), vcov(reml)), "the sampling covariance is unchanged")
expect(identical(lean$panel$counts, c(item = 20L, rater = 4L)),
       "the panel summary records the observed level counts")

# Defaults keep everything, so an existing call is unaffected.
expect(all(gt_control()$retain), "every retention default is TRUE")
expect(!is.null(reml$data) && !is.null(reml$model) && !is.null(reml$session),
       "a default fit keeps its data, model, and session record")

# Discrete fits keep the decisions that matter after dropping their payloads.
lean_binary <- suppressWarnings(gt_fit(discrete_panel, "b", reduced, gt_family("binary"),
  control = gt_control(discrete = list(maxit = 200L),
                       retain = list(data = FALSE, model = FALSE, retry_log = FALSE))))
expect(is.null(lean_binary$conditional_eta) && is.null(lean_binary$conditional_probabilities),
       "dropping the model removes the discrete per-observation matrices")
expect(identical(gt_diagnostics(lean_binary)$acceptance_failures,
                 gt_diagnostics(binary)$acceptance_failures),
       "discrete acceptance reasons survive dropping the attempt payloads")
expect(identical(gt_reliability(lean_binary, scale = "latent")$per_trait,
                 gt_reliability(binary, scale = "latent")$per_trait),
       "discrete latent reliability is unchanged by retention")
expect(length(gt_diagnostics(lean_binary)$diagnostics$attempts) ==
         length(gt_diagnostics(binary)$diagnostics$attempts),
       "every attempt is still recorded, only its payload is dropped")
expect(is.null(gt_diagnostics(lean_binary)$diagnostics$attempts[[1L]]$raw_result),
       "the bulky raw optimizer result is the part that is dropped")
expect(!is.null(gt_diagnostics(lean_binary)$diagnostics$attempts[[1L]]$label),
       "an attempt keeps the label that identifies it")

# Invalid retention settings fail before anything is fitted.
expect_error(gt_control(retain = list(nonsense = TRUE)), "Unsupported retention setting",
             "an unknown retention switch")
expect_error(gt_control(retain = list(data = "no")), "must be TRUE or FALSE",
             "a non-logical retention switch")
expect_error(gt_control(retain = list(data = NA)), "must be TRUE or FALSE",
             "a missing retention switch")
expect_error(gt_control(retain = list(TRUE)), "uniquely named", "an unnamed retention switch")

cat("PASS: retention controls reduce fit size without changing any reported result.\n")
