# Installed-package checks for the lme4 Gaussian engine.
#
# The engine fits the same random sources as random intercepts through lme4,
# so every check here is a comparison: against the exact balanced engine on
# the same data, against lme4's own criteria, and against the refusals the
# exact engine's settings and multivariate models must meet on this path.
library(Gtheory4LLM)

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
outcome <- function(expr) tryCatch({ force(expr); "accepted" }, error = conditionMessage)
near <- function(a, b, tolerance, label)
  expect(isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)), label)

run <- function() {
  set.seed(3)
  d <- expand.grid(item = 1:12, rater = 1:3)
  d$score <- rnorm(12, sd = 1.2)[d$item] + rnorm(3, sd = .5)[d$rater] + rnorm(nrow(d), sd = .8)
  d$second <- d$score + rnorm(nrow(d))
  design <- gt_design("item", "rater")
  lme4_control <- gt_control(gaussian = list(engine = "lme4"))
  exact <- gt_fit(d, "score", design, control = gt_control(gaussian = list(retry_seed = 42)))
  lme <- gt_fit(d, "score", design, control = lme4_control)

  # --- One likelihood, two engines ------------------------------------------
  expect(identical(class(lme), c("gt_gaussian_fit", "gt_fit")), "an lme4 fit has the Gaussian class vector")
  expect(identical(lme$engine, "lme4_gaussian_mixed_model") && identical(exact$engine, "exact_balanced_gaussian"),
         "the engines are labelled")
  expect(isTRUE(lme$numerically_accepted), "the lme4 fit is accepted")
  near(unlist(gt_components(lme)), unlist(gt_components(exact)), 1e-4, "REML components agree with the exact engine")
  near(lme$minus2loglik, exact$minus2loglik, 1e-7, "REML criteria agree")
  expect(isTRUE(lme$diagnostics$independent_likelihood_matches), "the exact deviance at lme4's estimates matches")
  stages <- gt_diagnostics(lme)$stages
  expect(all(vapply(stages[c("optimizer", "stationarity", "restart_stability", "numerical_acceptance",
                              "approximation_assessment")], function(s) identical(s$status, "passed"), logical(1))),
         "every applicable stage passed")
  diagnostics <- gt_diagnostics(lme)
  expect(grepl("^None", diagnostics$approximation) && grepl("lme4", diagnostics$optimizer),
         "engine, optimizer and approximation are recorded separately")
  expect(any(grepl("approximation:", capture.output(print(diagnostics)), fixed = TRUE)), "and printed")

  # --- lme4's own criteria -----------------------------------------------------
  ml <- gt_fit(d, "score", design, estimator = "ML", control = lme4_control)
  reference <- lme4::lmer(score ~ 1 + (1 | item) + (1 | rater), d, REML = FALSE)
  near(as.numeric(logLik(ml)), as.numeric(logLik(reference)), 1e-8, "ML log likelihood equals lme4's")
  near(AIC(ml), AIC(reference), 1e-8, "AIC equals lme4's")
  near(BIC(ml), BIC(reference), 1e-8, "BIC equals lme4's")
  expect(identical(deviance(ml), ml$minus2loglik), "deviance is the retained criterion")

  # --- Downstream objects work; intervals are honestly unavailable ------------
  reliability <- gt_reliability(lme)
  expect(is.finite(reliability$per_trait$Erho2[1]) && is.na(reliability$per_trait$Erho2_lower[1]),
         "reliability is computed without intervals")
  near(reliability$per_trait$Erho2, gt_reliability(exact)$per_trait$Erho2, 1e-4, "G agrees")
  expect(nrow(gt_dstudy(lme, data.frame(rater = c(2, 6)))$results) == 2L, "D study works")
  expect(inherits(summary(lme)$reliability, "gt_reliability"), "summary carries the reliability")
  expect(inherits(gt_report(lme), "gt_report"), "a report can be built")
  expect(identical(update(lme, estimator = "ML")$engine, "lme4_gaussian_mixed_model"), "update() keeps the engine")
  dropped <- gt_fit(d, "score", design, control = gt_control(gaussian = list(engine = "lme4"),
                                                               retain = list(data = FALSE)))
  expect(is.null(dropped$model) && is.null(dropped$data), "dropping the data drops the lme4 model")
  near(unlist(gt_components(dropped)), unlist(gt_components(lme)), 1e-12, "and changes no estimate")

  # --- Refusals ---------------------------------------------------------------
  expect(grepl("one Gaussian outcome", outcome(gt_fit(d, c("score", "second"), design, control = lme4_control)), fixed = TRUE),
         "a joint multivariate model is refused")
  expect(grepl("apply to the exact engine",
               outcome(gt_fit(d, "score", design, control = gt_control(gaussian = list(engine = "lme4", check_hessian = FALSE)))),
               fixed = TRUE), "exact-engine settings are refused with lme4")
  expect(grepl("engine must be", outcome(gt_fit(d, "score", design, control = gt_control(gaussian = list(engine = "nlme")))), fixed = TRUE),
         "an unknown engine is refused")
  preflight <- gt_preflight(d, "score", design, control = lme4_control)
  expect(identical(preflight$engine, "lme4_gaussian_mixed_model") &&
           all(c("lme4_available", "single_outcome_for_lme4") %in% preflight$checks$check) &&
           isTRUE(preflight$fitting_feasible), "preflight names the engine and its checks")
  expect(!gt_preflight(d, c("score", "second"), design, control = lme4_control)$fitting_feasible,
         "preflight reports a joint lme4 request as infeasible")

  # --- A modelled batch: the call source through lme4 ------------------------
  b <- expand.grid(item = 1:12, rater = 1:3, run = 1:2)
  b$batch <- (b$item - 1) %/% 4 + 1
  b$y <- rnorm(12)[b$item] + rnorm(3, sd = .4)[b$rater] + rnorm(9, sd = .5)[b$batch + 3 * (b$rater - 1)] +
    rnorm(nrow(b), sd = .7)
  batched <- gt_design("item", c("rater", "run"), random = ~ item + rater + item:rater + rater:run,
                       batch = gt_batch(4))
  exact_batch <- gt_fit(b, "y", batched, control = gt_control(gaussian = list(retry_seed = 1, check_hessian = FALSE)))
  lme4_batch <- gt_fit(b, "y", batched, control = lme4_control)
  expect(identical(names(gt_components(lme4_batch)), names(gt_components(exact_batch))) &&
           "Call" %in% names(gt_components(lme4_batch)), "the call source is fitted")
  near(unlist(gt_components(lme4_batch)), unlist(gt_components(exact_batch)), 1e-3, "call-effect components agree")
  near(lme4_batch$minus2loglik, exact_batch$minus2loglik, 1e-6, "call-effect criteria agree")
  expect(isTRUE(lme4_batch$design$batch_model$modelled) && isTRUE(lme4_batch$numerically_accepted),
         "the batch is recorded as modelled and the fit accepted")

  # --- Planning refits through the same engine ---------------------------------
  plan <- gt_pilot_plan(lme, data.frame(n_items = 12), nsim = 1, seed = 5)
  expect(plan$summary$accepted == 1L, "a pilot plan refits through lme4")
  cat("PASS: the lme4 engine reproduces the exact engine and lme4's own criteria, with honest refusals.\n")
}

if (requireNamespace("lme4", quietly = TRUE)) run() else
  cat("SKIP: lme4 is not installed, so the lme4 engine was not exercised.\n")
