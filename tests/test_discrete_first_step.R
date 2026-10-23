# Run from the project directory with Rscript tests/test_discrete_first_step.R.
#
# The first step of a coarse L-BFGS-B attempt. Every discrete coordinate has two
# finite bounds, so L-BFGS-B starts from an identity Hessian and its first trial
# point is the start minus the raw gradient, which is a sum over rows. On the
# 21,600-row drug-review panel that put an ordinal fit's item variance near
# 4,000; every conditional solve there failed and the line search ended the
# attempt at its start after three evaluations. A coarse attempt that ends where
# it began after an invalid evaluation is now rerun from the same start at a
# uniform parameter scale of 1/sqrt(rows), which makes the first step the
# per-row gradient. Attempts that move are never rerun. Checks:
#
#   * the mechanism, on a quadratic whose gradient is a sum over rows;
#   * a fit whose attempts move is untouched: no scale, no rescue, and nlminb
#     is left alone;
#   * a 7,200-row subset of the drug-review efficacy panel whose default ordinal
#     fit collapsed at its start: the collapse is recorded and the rerun moves.
source("load_functions.R")
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)

# --- the mechanism ------------------------------------------------------------
# n per-row quadratics: gradient n (x - target), Hessian n I. Unscaled, the first
# trial point is start - n (start - target) clipped to the box; at scale
# 1/sqrt(n) it is the Newton point, the target itself.
n <- 21600
target <- c(0.3, 2, -1)
first_trial <- function(control) {
  seen <- list()
  f <- function(x) { seen[[length(seen) + 1L]] <<- x; n * sum((x - target)^2) / 2 }
  .gt_d_optimize(c(0.16, 0.16, 0.16), f, c(0, 0, -15), c(exp(10), exp(10), 15), control, "mechanism",
                 gradient = function(x) n * (x - target))
  seen[[2L]]
}
unscaled <- first_trial(list(maxit = 1L, factr = 1e7))
scaled <- first_trial(list(maxit = 1L, factr = 1e7, parscale = rep(1 / sqrt(n), 3L)))
expect(abs(unscaled[[2L]] - exp(10)) < 1e-6 && abs(unscaled[[3L]] + 15) < 1e-9,
       "unscaled, the first trial point is thrown onto the box")
expect(max(abs(scaled - target)) < 1e-8, "at scale 1/sqrt(rows) the first trial point is the per-row Newton point")

# --- attempts that move are untouched -------------------------------------------
d <- expand.grid(occasion = 1:12, item = 1:8)
d$y <- as.integer(d$occasion <= c(2, 3, 4, 5, 7, 8, 9, 10)[d$item])
design <- gt_design("item", "occasion", random = ~ item)
fit_with <- function(optimizer) gt_fit(d, "y", design, gt_family("binary", "logit"),
  control = gt_control(discrete = list(optimizer = optimizer, maxit = 300L)))
untouched <- function(fit) all(vapply(fit$diagnostics$attempts, function(a)
  is.null(a$optimizer_control$parscale) && is.null(a$first_step_rescue), logical(1)))
lbfgsb <- fit_with("L-BFGS-B")
nlminb <- fit_with("nlminb")
expect(untouched(lbfgsb), "L-BFGS-B attempts that move run unscaled and are not rerun")
expect(untouched(nlminb), "nlminb attempts are left alone")
expect(lbfgsb$numerically_accepted && nlminb$numerically_accepted &&
         abs(lbfgsb$minus2loglik - nlminb$minus2loglik) < 1e-6, "both optimizers still reach the same accepted fit")

# Local copies exercise error preservation without altering the shared functions.
ns <- environment(gt_fit)
internal <- function(name) get(name, envir = ns, inherits = FALSE)
optimize <- .gt_d_optimize
broken <- function(...) stop("injected optimizer error")
expect_error <- function(expr, text) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  expect(inherits(error, "error") && grepl(text, conditionMessage(error), fixed = TRUE), text)
}
make_local_fit <- function() {
  env <- new.env(parent = ns)
  env$.gt_fit_discrete <- internal(".gt_fit_discrete")
  environment(env$.gt_fit_discrete) <- env
  env$gt_fit <- gt_fit
  environment(env$gt_fit) <- env
  env
}

# A failed coarse optimizer must not be relabeled as a collapsed finite first
# step and replaced by an apparently clean scaled rerun. First create one
# invalid inner evaluation, then fail the optimizer; later attempts may still
# complete, but the original failure must keep the whole fit unaccepted.
for (failure_kind in c("exception", "unusable_result")) {
  local <- make_local_fit()
  local$first_optimizer <- TRUE
  local$force_invalid <- FALSE
  honest_laplace <- internal(".gt_d_laplace")
  local$.gt_d_laplace <- function(parameters, prep, groups, setup, control,
                                 details = FALSE, ...) {
    if (local$force_invalid) {
      local$force_invalid <- FALSE
      return(list(valid = FALSE, inner_converged = FALSE))
    }
    honest_laplace(parameters, prep, groups, setup, control, details = details, ...)
  }
  local$.gt_d_optimize <- function(at, objective, lower, upper, optimizer_control,
                                   label, optimizer = "L-BFGS-B", gradient = NULL) {
    if (local$first_optimizer) {
      local$first_optimizer <- FALSE
      local$force_invalid <- TRUE
      invisible(objective(at))
      failed_optimizer <- if (failure_kind == "exception") broken else
        function(...) list(par = at, value = Inf, convergence = 0L)
      return(optimize(at, objective, lower, upper, optimizer_control, label, failed_optimizer))
    }
    optimize(at, objective, lower, upper, optimizer_control, label, optimizer, gradient)
  }
  refused <- suppressWarnings(local$gt_fit(d, "y", design, gt_family("binary", "logit"),
    control = gt_control(discrete = list(fixed_covariance = list(item = matrix(0.3))))))
  original <- refused$diagnostics$attempts[[1L]]
  stopifnot(!refused$numerically_accepted, is.finite(refused$minus2loglik),
    !original$result_available, !is.null(original$error),
    is.null(original$first_step_rescue),
    "validation_computation_failed" %in% refused$diagnostics$acceptance_failures,
    refused$diagnostics$evaluations$invalid >= 1L)
  expect_error(gt_reliability(refused, scale = "latent"), "numerically converged")
}

# --- a panel whose first step collapsed ---------------------------------------
# 100 items x 4 evaluators x 3 prompts x 3 temperatures x 2 seeds of the bundled
# drug-review efficacy labels, fitted as ordinal with default controls. Before
# the rescue the primary attempt evaluated three points, its conditional solves
# at the first trial point failed, and it stopped at its start.
dr <- gt_example("drug_review_4aspect", coding = "native")$data
keep <- dr$temp %in% unique(as.character(dr$temp))[1:3] & dr$seed %in% unique(as.character(dr$seed))[1:2]
panel <- droplevels(dr[keep, ])
six <- gt_design("item", c("evaluator", "prompt", "temp", "seed"),
  random = c("item", "evaluator", "prompt", "evaluator:prompt", "item:evaluator", "item:prompt"))
ordinal <- suppressWarnings(gt_fit(panel, "efficacy", design = six,
  family = gt_family("ordinal", "logit", levels = levels(dr$efficacy)),
  control = gt_control(discrete = list(engine = "sparse", max_observations = 21600L, max_random_dimension = 1000L,
    alternative_starts = 0L))))
expect(nrow(panel) == 7200L, "the regression panel has 7,200 rows")
primary <- ordinal$diagnostics$attempts[[1L]]
rescue <- primary$first_step_rescue
expect(!is.null(rescue) && rescue$invalid_evaluations > 0L && rescue$collapsed_counts[["function"]] <= 3L,
       "the collapsed first run is recorded: three or fewer evaluations and failed conditional solves")
expect(isTRUE(all.equal(primary$optimizer_control$parscale, rep(1 / sqrt(7200), length(primary$start)))),
       "the rerun runs at parameter scale 1/sqrt(rows)")
expect(max(abs(primary$parameters - primary$start)) > 1 && primary$objective < rescue$collapsed_objective - 1,
       "the rerun leaves its start and improves on the collapsed run")
tight <- ordinal$diagnostics$attempts[[2L]]
expect(identical(tight$label, "primary_tight") && is.null(tight$optimizer_control$parscale) &&
         is.null(tight$first_step_rescue), "the tight attempt that follows is unscaled")
cat("PASS: a collapsed first step is rerun at the per-row scale; attempts that move are untouched.\n")
