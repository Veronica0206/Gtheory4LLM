# Run from the project directory with Rscript tests/test_discrete_sparse_warm_start.R.
#
# A sparse evaluation whose cold conditional-mode solve, from zero modes, ends
# unavailable is retried once from the last valid mode the same evaluator
# produced. The cold solve runs first and is untouched, so the claims here are:
# a valid cold result is what it was; a start at the converged mode reproduces
# that result in one iteration; a start from a neighbouring mode reaches the
# same value in no more iterations; the retry rescues an evaluation the cold
# solve cannot complete under a starved iteration budget, and only when a valid
# mode exists; a rescue is marked, keeps its cold attempt, is counted by the
# evaluation record and agrees with the dense value; a malformed start is
# refused. No tolerance is changed: the starved budget is this test's device
# for making a cold solve fail deterministically, not a solver setting.
source("load_functions.R")
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
outcome <- function(expr) tryCatch({ force(expr); "accepted" }, error = conditionMessage)

set.seed(2026102102L)
data <- expand.grid(item = seq_len(12L), rater = seq_len(4L))
latent <- rnorm(12L, sd = 0.9)[data$item] + rnorm(4L, sd = 0.3)[data$rater]
data$y <- rbinom(nrow(data), 1L, plogis(-0.2 + latent))
families <- list(list(family = "binary", link = "logit", levels = c("0", "1"), reference = NULL))
design <- list(object = "item", facets = "rater",
               term_members = list(item = "item", rater = "rater"))
control <- .gt_d_control(list())
prep <- .gt_d_prepare(data, "y", families)
groups <- lapply(design$term_members, function(m) .gt_d_group(data, m))
setup <- .gt_d_covariance_setup(groups, prep$q, "diagonal", control, prep$dimensions)
parameters <- c(prep$start + 0.1, setup$start * 1.5)
factors <- .gt_d_covariance_factors(parameters[-seq_along(prep$start)], setup)
backend <- .gt_d_sparse_backend(groups, factors, prep$n, prep$q)
evaluate <- function(evaluator, settings = control, details = TRUE)
  evaluator(parameters, prep, groups, setup, settings, details = details)

# --- The cold path, and its agreement with dense -------------------------------
cold <- evaluate(.gt_d_sparse_evaluator())
expect(isTRUE(cold$valid) && isTRUE(cold$inner_converged) && is.null(cold$inner_warm_started),
       "a cold evaluation is valid, converged and not marked as warm-started")
expect(cold$inner_iterations >= 3L,
       "the fixture needs several cold Newton iterations, so a one-iteration budget cannot complete it")
dense <- .gt_d_laplace(parameters, prep, groups, setup, control, details = TRUE)
expect(isTRUE(dense$valid) && abs(cold$nll - dense$nll) <= 1e-10,
       "the cold sparse value matches the dense value")

# --- A start at the converged mode reproduces the cold result in one iteration -
restarted <- .gt_d_sparse_mode(parameters, prep, backend, control, details = TRUE,
                               start = cold$mode)
expect(isTRUE(restarted$valid) && isTRUE(restarted$inner_warm_started) &&
         restarted$inner_iterations == 1L,
       "a start at the converged mode is accepted at the first iteration and marked warm")
expect(abs(restarted$nll - cold$nll) <= 1e-12 && max(abs(restarted$mode - cold$mode)) <= 1e-12,
       "the warm-started value and mode equal the cold ones")

# --- A neighbouring parameter: the same value in no more iterations -----------
nearby <- parameters
nearby[[1L]] <- nearby[[1L]] + 0.05
nearby_factors <- .gt_d_covariance_factors(nearby[-seq_along(prep$start)], setup)
nearby_backend <- .gt_d_sparse_backend(groups, nearby_factors, prep$n, prep$q)
nearby_cold <- .gt_d_sparse_mode(nearby, prep, nearby_backend, control, details = TRUE)
nearby_warm <- .gt_d_sparse_mode(nearby, prep, nearby_backend, control, details = TRUE,
                                 start = cold$mode)
expect(isTRUE(nearby_cold$valid) && isTRUE(nearby_warm$valid) &&
         abs(nearby_warm$nll - nearby_cold$nll) <= 1e-9 &&
         nearby_warm$inner_iterations <= nearby_cold$inner_iterations,
       "a warm start from a neighbouring mode reaches the same value in no more iterations")

# --- The retry rescues only what the cold solve cannot complete ----------------
starved <- control
starved$inner_maxit <- 1L
failed <- evaluate(.gt_d_sparse_evaluator(), starved)
expect(!isTRUE(failed$valid) && isFALSE(failed$inner_converged) &&
         is.null(failed$inner_warm_started),
       "without a stored mode a starved cold solve is unavailable and no retry is attempted")
expect(identical(evaluate(.gt_d_sparse_evaluator(), starved, details = FALSE), 1e100),
       "the scalar form of that unavailable evaluation is the penalty")
primed <- .gt_d_sparse_evaluator()
expect(isTRUE(evaluate(primed)$valid), "the priming evaluation is valid")
rescued <- evaluate(primed, starved)
expect(isTRUE(rescued$valid) && isTRUE(rescued$inner_warm_started) &&
         isTRUE(rescued$inner_converged) && rescued$inner_iterations == 1L,
       "with a stored mode the starved evaluation is rescued in one warm iteration")
expect(abs(rescued$nll - cold$nll) <= 1e-12 && abs(rescued$nll - dense$nll) <= 1e-10,
       "the rescued value equals the cold value and the dense value")
expect(is.list(rescued$inner_cold_attempt) &&
         isFALSE(rescued$inner_cold_attempt$inner_converged) &&
         identical(rescued$inner_cold_attempt$inner_iterations, 1L),
       "the rescued evaluation retains the measurements of its failed cold attempt")
expect(identical(names(rescued)[1:3], c("valid", "nll", "factors")),
       "the rescued details keep the evaluator's return shape")
scalar <- .gt_d_sparse_evaluator()
invisible(evaluate(scalar))
expect(abs(evaluate(scalar, starved, details = FALSE) - cold$nll) <= 1e-12,
       "the scalar form of a rescued evaluation is its value, not the penalty")

# --- The fit's evaluation record counts a rescue as valid, separately ----------
record <- .gt_d_evaluation_log(control, prep)
expect(abs(record$observe(parameters, rescued, "coarse", starved) - cold$nll) <= 1e-12,
       "a rescued evaluation is usable by the optimizer")
expect(identical(record$observe(parameters, failed, "coarse", starved), 1e100),
       "an unrescued failure still returns the penalty")
summary <- record$summary()
expect(summary$count == 2L && summary$invalid == 1L && summary$warm_rescued == 1L &&
         length(summary$retained_rescued) == 1L &&
         isFALSE(summary$retained_rescued[[1L]]$cold_attempt$inner_converged) &&
         identical(summary$retained_rescued[[1L]]$evaluation, 1L),
       "the record separates one rescue from one invalid evaluation and keeps the cold attempt")

# --- Malformed starts are refused, not silently replaced -----------------------
expect(grepl("start", outcome(.gt_d_sparse_mode(parameters, prep, backend, control, TRUE,
                                                  start = cold$mode[-1L]))),
       "a start of the wrong length is refused")
expect(grepl("start", outcome(.gt_d_sparse_mode(parameters, prep, backend, control, TRUE,
                                                  start = replace(cold$mode, 1L, NA_real_)))),
       "a non-finite start is refused")

# --- The cold path is unchanged: a fresh evaluator reproduces the first exactly -
again <- evaluate(.gt_d_sparse_evaluator())
expect(identical(again$nll, cold$nll) && identical(again$mode, cold$mode) &&
         identical(again$inner_iterations, cold$inner_iterations),
       "fresh cold evaluations are deterministic and unaffected by the retry")
cat("PASS: a failed cold sparse solve is retried once from the last valid mode; cold results are unchanged.\n")
