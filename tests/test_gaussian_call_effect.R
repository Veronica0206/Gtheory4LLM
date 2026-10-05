# Independent checks of the call-effect likelihood against lme4.
# Run from the repository root in a clean R session.
#
# A modelled batch changes one thing in the exact balanced engine: which
# factorial axes a source spans. The object becomes a batch-by-slot cell, and
# the call, a batch under one condition, becomes a source. lme4 fits the same
# model with ordinary grouping factors and shares none of that arithmetic.
source("R/design.R")
source("R/batch.R")
source("R/gaussian_retry.R")
source("R/gaussian_engine.R")
source("R/gaussian.R")
stopifnot(requireNamespace("OpenMx", quietly = TRUE), requireNamespace("lme4", quietly = TRUE))
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label, call. = FALSE)

simulate <- function(seed, batches, size, raters, runs, call_sd) {
  set.seed(seed)
  d <- expand.grid(item = seq_len(batches * size), rater = seq_len(raters), run = seq_len(runs))
  d$batch <- (d$item - 1L) %/% size + 1L
  call <- interaction(d$batch, d$rater, d$run, drop = TRUE)
  d$y <- 2 + rnorm(batches * size)[d$item] + rnorm(raters, sd = .5)[d$rater] +
    rnorm(batches * size * raters, sd = .4)[interaction(d$item, d$rater)] +
    rnorm(raters * runs, sd = .3)[interaction(d$rater, d$run)] +
    rnorm(nlevels(call), sd = call_sd)[call] + rnorm(nrow(d), sd = .8)
  d
}
sources <- c("item", "rater", "item:rater", "rater:run", "Call", "Residual")
ours <- function(d, size, estimator, ...) {
  design <- gt_design("item", c("rater", "run"), random = ~ item + rater + item:rater + rater:run,
                      batch = gt_batch(size, ...))
  design <- .gt_resolve_design(d[c("item", "rater", "run", "y")], design, "gaussian")
  fit <- .gt_fit_gaussian(d[c("item", "rater", "run", "y")], "y", design, estimator,
    covariance = "diagonal", residual = "diagonal",
    control = list(threads = 1L, retry_seed = 42), call = .gt_batch_model(d, design))
  list(variance = vapply(fit$covariance_components, function(M) M[1, 1], numeric(1))[sources],
       criterion = fit$minus2loglik, design = fit$design)
}
theirs <- function(d, reml) {
  fit <- lme4::lmer(y ~ 1 + (1 | item) + (1 | rater) + (1 | item:rater) + (1 | rater:run) +
    (1 | batch:rater:run), data = d, REML = reml,
    control = lme4::lmerControl(optimizer = "bobyqa", optCtrl = list(rhoend = 1e-10),
                                check.conv.singular = "ignore", calc.derivs = FALSE))
  table <- as.data.frame(lme4::VarCorr(fit))
  variance <- stats::setNames(table$vcov, ifelse(is.na(table$grp) | table$grp == "Residual", "Residual", table$grp))
  names(variance)[names(variance) == "batch:rater:run"] <- "Call"
  list(variance = variance[sources],
       criterion = if (reml) lme4::REMLcrit(fit) else as.numeric(-2 * stats::logLik(fit)))
}
cases <- list(
  list(label = "four batches of ten", seed = 11, batches = 4L, size = 10L, raters = 5L, runs = 6L, call_sd = .6),
  list(label = "five batches of six", seed = 13, batches = 5L, size = 6L, raters = 4L, runs = 5L, call_sd = .7),
  list(label = "no call effect", seed = 12, batches = 4L, size = 10L, raters = 5L, runs = 6L, call_sd = 0))
for (case in cases) {
  d <- do.call(simulate, case[c("seed", "batches", "size", "raters", "runs", "call_sd")])
  for (estimator in c("REML", "ML")) {
    a <- ours(d, case$size, estimator)
    b <- theirs(d, estimator == "REML")
    # The criterion is compared tightly. The variances are compared at the
    # precision lme4's optimizer delivers on a flat direction such as a
    # variance among four or five raters.
    expect(abs(a$criterion - b$criterion) < 1e-5,
           paste(case$label, estimator, "criterion equals lme4's"))
    expect(max(abs(a$variance - b$variance)) < 2e-3,
           paste(case$label, estimator, "variances equal lme4's"))
    expect(a$criterion <= b$criterion + 1e-7,
           paste(case$label, estimator, "the engine's optimum is at least as good as lme4's"))
  }
  expect(isTRUE(a$design$batch_model$modelled) && identical(a$design$batch_model$batches, case$batches),
         paste(case$label, "the fitted design records the modelled batches"))
  if (case$call_sd == 0) expect(a$variance[["Call"]] < 1e-6, "an absent call effect is estimated at zero")
  else expect(a$variance[["Call"]] > .1, paste(case$label, "a present call effect is estimated away from zero"))
}
cat("PASS: REML and ML call-effect fits match lme4 in criterion and variances, including a zero call variance.\n")

# Recorded calls, in any row order, are the same model as batches cut from the item order.
d <- simulate(11, 4L, 10L, 5L, 6L, .6)
d$call <- paste(d$batch, d$rater, d$run)
inferred <- ours(d, 10L, "REML")
recorded <- ours(d[sample(nrow(d)), ], 10L, "REML", id = "call")
expect(abs(inferred$criterion - recorded$criterion) < 1e-8 &&
         max(abs(inferred$variance - recorded$variance)) < 1e-5,
       "recorded calls in shuffled rows give the fit of inferred batches")
# Relabelling the items inside a batch changes nothing: the slot has no effect of its own.
relabelled <- d
relabelled$item <- (d$batch - 1L) * 10L + (10L - (d$item - 1L) %% 10L)
swapped <- ours(relabelled[order(relabelled$run, relabelled$rater, relabelled$item), ], 10L, "REML")
expect(abs(inferred$criterion - swapped$criterion) < 1e-8,
       "which slot an item occupies in its batch does not enter the likelihood")
cat("PASS: recorded calls, row order and slot labels leave the call-effect fit unchanged.\n")

# Without a call argument the engine is exactly what it was.
plain_design <- .gt_resolve_design(d[c("item", "rater", "run", "y")],
  gt_design("item", c("rater", "run"), random = ~ item + rater + item:rater + rater:run), "gaussian")
plain <- .gt_fit_gaussian(d[c("item", "rater", "run", "y")], "y", plain_design, "REML",
  covariance = "diagonal", residual = "diagonal", control = list(threads = 1L, retry_seed = 42))
reference <- lme4::lmer(y ~ 1 + (1 | item) + (1 | rater) + (1 | item:rater) + (1 | rater:run), data = d,
  control = lme4::lmerControl(optimizer = "bobyqa", optCtrl = list(rhoend = 1e-10), calc.derivs = FALSE))
expect(abs(plain$minus2loglik - lme4::REMLcrit(reference)) < 1e-5 &&
         identical(names(plain$covariance_components), c("item", "rater", "item:rater", "rater:run", "Residual")) &&
         is.null(plain$design$batch_model),
       "a design without a declaration is fitted as before")
cat("All Gaussian call-effect checks passed.\n")
