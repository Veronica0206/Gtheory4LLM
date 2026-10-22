# Run from the project directory with Rscript tests/test_discrete_sparse_warm_policy.R.
#
# Warm starts within an optimizer attempt (.gt_d_sparse_evaluator). The
# conditional objective is strictly concave in the random effects, so a start
# changes the path to the mode and never the mode. What this checks is the
# policy around that fact, with roles named by the fit rather than inferred:
#
#   * the explicit gradient reproduces optim()'s own L-BFGS-B path exactly;
#   * an attempt's first solve is cold; "warm" evaluations start from the
#     centre mode and become the centre, including a real move in one
#     coordinate; "warm_probe" evaluations start from the centre mode and never
#     replace it, so every probe of one gradient shares one seed;
#   * no role means a cold solve; a reset makes the next solve cold;
#   * a warm solve that stops short falls back to the cold solve, and a cold
#     failure is then retried from the last valid mode, as before warm starts;
#   * every fallback is counted, usable or not, and failure records keep the
#     warm attempt;
#   * a public L-BFGS-B fit counts its warm starts and ends with a cold final
#     evaluation, while an nlminb fit, whose finite differences are internal,
#     solves cold throughout.
source(file.path("validation-studies", "discrete-sparse-equivalence", "cases.R"))
source("load_functions.R")
suppressMessages(library(Matrix))

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)

row <- EQ_CALIBRATION[EQ_CALIBRATION$case == "K02", ]
map <- .eq_parameter_map(row, EQ_CALIBRATION_GEOMETRY[[row$geometry]])
prep <- map$prep; groups <- map$groups; setup <- map$setup; control <- map$control
theta <- map$start
as_role <- function(base, role) { base$inner_start <- role; base }
warm <- as_role(control, "warm")
probe <- as_role(control, "warm_probe")

# Record the seed of every conditional solve the evaluator starts.
honest_mode <- .gt_d_sparse_mode
seeds <- list()
.gt_d_sparse_mode <- function(parameters, prep, backend, control, details = FALSE, start = NULL) {
  seeds[[length(seeds) + 1L]] <<- list(role = control$inner_start, start = start)
  honest_mode(parameters, prep, backend, control, details = details, start = start)
}
same_seed <- function(a, b) !is.null(a) && !is.null(b) && identical(a, b)

# --- the explicit gradient is optim's own rule ---------------------------------------
cold_evaluator <- .gt_d_sparse_evaluator()
cold_value <- function(par) {
  value <- cold_evaluator(par, prep, groups, setup, control, details = TRUE)
  if (isTRUE(value$valid)) value$nll else 1e100
}
trace_internal <- list(); internal <- function(x) { trace_internal[[length(trace_internal) + 1L]] <<- x; cold_value(x) }
trace_explicit <- list(); explicit <- function(x) { trace_explicit[[length(trace_explicit) + 1L]] <<- x; cold_value(x) }
settings <- list(maxit = 150, factr = 1e-7 / .Machine$double.eps)
a <- optim(theta, internal, method = "L-BFGS-B", lower = map$lower, upper = map$upper, control = settings)
b <- optim(theta, explicit, .gt_d_numerical_gradient(explicit, rep(1e-3, length(theta)), map$lower, map$upper),
           method = "L-BFGS-B", lower = map$lower, upper = map$upper, control = settings)
expect(identical(trace_internal, trace_explicit) && identical(a$par, b$par) && identical(a$value, b$value) &&
         identical(a$counts, b$counts) && identical(a$convergence, b$convergence),
       "the explicit gradient reproduces optim's own L-BFGS-B evaluations, path and result exactly")
clipped <- .gt_d_numerical_gradient(function(x) sum(x^2), c(0.5, 0.5), c(-1, 0), c(1, 0.2))(c(0.9, 0.1))
expect(isTRUE(all.equal(clipped, c((1 - 0.4^2) / 0.6, (0.2^2 - 0) / 0.2))),
       "each side of a difference is clipped to its bound with the step it actually used")

# --- an attempt's first solve is cold and sets the centre -----------------------------
evaluator <- .gt_d_sparse_evaluator()
seeds <- list()
first <- evaluator(theta, prep, groups, setup, warm, details = TRUE)
expect(isTRUE(first$valid) && is.null(first$inner_warm_started) && is.null(seeds[[1L]]$start),
       "the first solve of an attempt is cold even when a role is named")

# --- probes start from the centre and never replace it --------------------------------
j <- length(prep$start) + 1L
plus <- theta; plus[[j]] <- plus[[j]] + 1e-3
minus <- theta; minus[[j]] <- minus[[j]] - 1e-3
seeds <- list()
positive <- evaluator(plus, prep, groups, setup, probe, details = TRUE)
negative <- evaluator(minus, prep, groups, setup, probe, details = TRUE)
expect(isTRUE(positive$inner_warm_started) && isTRUE(negative$inner_warm_started) &&
         same_seed(seeds[[1L]]$start, first$mode) && same_seed(seeds[[2L]]$start, first$mode),
       "both probes of a coordinate start from the centre mode")
again <- evaluator(minus, prep, groups, setup, probe, details = TRUE)
expect(identical(again$mode, negative$mode) && identical(again$nll, negative$nll),
       "a probe does not replace the centre: repeating it reproduces it exactly")

# --- a real move in one coordinate becomes the centre (round-6 finding W1) ------------
moved <- theta; moved[[1L]] <- moved[[1L]] + 0.05
seeds <- list()
centre_b <- evaluator(moved, prep, groups, setup, warm, details = TRUE)
expect(same_seed(seeds[[1L]]$start, first$mode) && isTRUE(centre_b$inner_warm_started),
       "a move in one coordinate is a warm evaluation from the previous centre")
k <- length(prep$start) + 2L
b_plus <- moved; b_plus[[k]] <- b_plus[[k]] + 1e-3
b_minus <- moved; b_minus[[k]] <- b_minus[[k]] - 1e-3
seeds <- list()
invisible(evaluator(b_plus, prep, groups, setup, probe, details = TRUE))
invisible(evaluator(b_minus, prep, groups, setup, probe, details = TRUE))
expect(same_seed(seeds[[1L]]$start, centre_b$mode) && same_seed(seeds[[2L]]$start, centre_b$mode),
       "after a one-coordinate move, both probes in another coordinate start from the new centre's mode")

# --- every probe of every gradient in a real attempt shares the preceding centre ----
attempt <- .gt_d_sparse_evaluator()
log <- list()
fn <- function(x) {
  value <- attempt(x, prep, groups, setup, warm, details = TRUE)
  log[[length(log) + 1L]] <<- list(role = "warm", seed = seeds[[length(seeds)]]$start,
                                    mode = if (isTRUE(value$valid)) value$mode)
  if (isTRUE(value$valid)) value$nll else 1e100
}
pr <- function(x) {
  value <- attempt(x, prep, groups, setup, probe, details = TRUE)
  log[[length(log) + 1L]] <<- list(role = "warm_probe", seed = seeds[[length(seeds)]]$start)
  if (isTRUE(value$valid)) value$nll else 1e100
}
seeds <- list()
invisible(optim(theta, fn, .gt_d_numerical_gradient(pr, rep(1e-3, length(theta)), map$lower, map$upper),
                method = "L-BFGS-B", lower = map$lower, upper = map$upper, control = list(maxit = 8)))
centre <- NULL
probes <- 0L
for (entry in log) {
  if (identical(entry$role, "warm")) centre <- entry$mode else {
    probes <- probes + 1L
    expect(same_seed(entry$seed, centre), "every probe of a gradient starts from the mode at that gradient's point")
  }
}
expect(probes >= 2L * length(theta), "the attempt evaluated at least one complete gradient")

# --- the mode is the same point whatever the start ------------------------------------
reference <- .gt_d_sparse_evaluator()
cold_plus <- reference(plus, prep, groups, setup, control, details = TRUE)
expect(abs(positive$nll - cold_plus$nll) <= 1e-8,
       paste0("warm and cold objectives agree at the coarse tolerance (",
              format(abs(positive$nll - cold_plus$nll), digits = 3), ")"))
expect(max(abs(positive$mode - cold_plus$mode)) <= 1e-6,
       "warm and cold modes agree within the inner tolerance")

# --- no role, an unknown role, and a reset --------------------------------------------
seeds <- list()
cold_again <- evaluator(theta, prep, groups, setup, control, details = TRUE)
expect(is.null(cold_again$inner_warm_started) && is.null(seeds[[1L]]$start),
       "an evaluation without a role is a cold solve")
expect(inherits(tryCatch(evaluator(theta, prep, groups, setup, as_role(control, "hot"), details = TRUE),
                         error = identity), "error"), "an unknown role is refused")
expect(is.function(attr(evaluator, "reset")), "the evaluator exposes a reset for the fit")
attr(evaluator, "reset")()
seeds <- list()
after_reset <- evaluator(plus, prep, groups, setup, warm, details = TRUE)
expect(is.null(after_reset$inner_warm_started) && is.null(seeds[[1L]]$start),
       "after a reset the next solve is cold")
expect(is.null(attr(.gt_d_laplace, "reset")), "the dense evaluator has no warm-start state to reset")

# --- a restrictive budget: fallback, then the older rescue (round-6 finding W2) -------
starved <- as_role(control, "warm")
starved$inner_maxit <- 1L
rescue <- .gt_d_sparse_evaluator()
invisible(rescue(theta, prep, groups, setup, warm, details = TRUE))          # centre A
far <- theta; far[[j]] <- far[[j]] + 0.5
near_far <- rescue(far, prep, groups, setup, probe, details = TRUE)          # last valid mode, not the centre
target <- far; target[[j]] <- target[[j]] + 1e-6
seeds <- list()
rescued <- rescue(target, prep, groups, setup, starved, details = TRUE)
expect(isTRUE(rescued$valid) && is.list(rescued$inner_warm_attempt) && is.list(rescued$inner_cold_attempt) &&
         isTRUE(rescued$inner_warm_started),
       "a warm solve and its cold fallback that stop short are followed by the retry from the last valid mode")
expect(length(seeds) == 3L && is.null(seeds[[2L]]$start) && same_seed(seeds[[3L]]$start, near_far$mode),
       "the order is warm from the centre, cold from zero modes, then the last valid mode")
cold_only <- .gt_d_sparse_mode(target, prep, .gt_d_sparse_backend_from(.gt_d_sparse_context(groups, prep$n, prep$q),
  .gt_d_covariance_factors(target[-seq_along(prep$start)], setup)), starved, details = TRUE)
expect(!isTRUE(cold_only$valid), "the cold solve alone cannot complete this evaluation within the budget")

# --- every fallback is counted, usable or not (round-6 finding W3) --------------------
counted <- .gt_d_evaluation_log(control, prep)
invisible(counted$observe(target, rescued, "coarse"))
unusable <- .gt_d_sparse_evaluator()
invisible(unusable(theta, prep, groups, setup, warm, details = TRUE))        # centre and last mode coincide
failed <- unusable(target, prep, groups, setup, starved, details = TRUE)
expect(!isTRUE(failed$valid) && is.list(failed$inner_warm_attempt) && is.null(failed$inner_cold_attempt),
       "with no last valid mode other than the seed already tried, the evaluation is unavailable")
invisible(counted$observe(target, failed, "coarse"))
summary <- counted$summary()
expect(summary$count == 2L && summary$cold_fallbacks == 2L && summary$invalid == 1L && summary$warm_rescued == 1L,
       "both fallbacks are counted, the failed one as well, with one rescue and one unusable evaluation")
expect(is.list(summary$retained_invalid[[1L]]$inner_warm_attempt) &&
         is.list(summary$retained_rescued[[1L]]$warm_attempt),
       "failure and rescue records keep the warm attempt")
.gt_d_sparse_mode <- honest_mode

# --- through the public interface ------------------------------------------------------
panel <- map$panel
panel$y <- factor(as.character(panel$y), levels = c("0", "1"))
fit_with <- function(engine, optimizer = "L-BFGS-B") suppressWarnings(gt_fit(panel, "y",
  design = gt_design("item", "rater", random = c("item", "rater"), replicates = 2L),
  family = gt_family("binary", "logit", levels = c("0", "1")), covariance = "diagonal",
  control = gt_control(discrete = list(engine = engine, optimizer = optimizer))))
fit <- fit_with("sparse")
evaluations <- fit$diagnostics$evaluations
expect(isTRUE(fit$numerically_accepted), "the sparse fit is numerically accepted")
expect(is.numeric(evaluations$warm_started) && evaluations$warm_started > 0L &&
         evaluations$warm_started < evaluations$count,
       "the fit counts its warm-started evaluations, and not every evaluation is one")
expect(identical(evaluations$cold_fallbacks, 0L) && identical(evaluations$warm_rescued, 0L),
       "no cold fallback and no rescue were needed on this panel")
expect(!isTRUE(fit$diagnostics$inner_warm_started), "the final evaluation of the fit is a cold solve")
dense <- fit_with("dense")
expect(abs(dense$logLik - fit$logLik) / max(1, abs(dense$logLik)) <= 1e-6,
       "the warm-started sparse fit reaches the dense objective within the fitted tolerance")
cold_nlminb <- fit_with("sparse", "nlminb")
expect(identical(cold_nlminb$diagnostics$evaluations$warm_started, 0L),
       "an nlminb fit, whose finite differences are internal, solves cold throughout")
cat("PASS: explicit gradient identical to optim's; cold first solve; centre and probe roles, including a",
    "one-coordinate move; shared seeds within every gradient; reset and no-role cold solves; fallback then",
    "rescue under a restrictive budget; every fallback counted; L-BFGS-B fits warm, nlminb fits cold.\n")
