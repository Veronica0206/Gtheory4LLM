# Run from the project directory with Rscript tests/test_gaussian_lme4_restart.R.
#
# The lme4 engine's restart-reproduction rule. A restart is evidence that the
# optimum was found twice only when it completed as cleanly as the primary
# attempt must: lme4 optimizer code 0 and no lme4 convergence warning. The
# rule is exercised on synthetic attempt records, every failure is shown to
# refuse the fit under the existing restart-stability label, and a real clean
# fit is shown to record a completed, warning-free restart and be accepted.
source("load_functions.R")
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)

primary <- list(objective = 123.456, theta = c(0.8, 0.3), optimizer_code = 0L,
                warnings = character())
restart <- function(code = 0L, warnings = character(), objective = primary$objective,
                    theta = primary$theta)
  list(objective = objective, theta = theta, optimizer_code = code, warnings = warnings)

clean <- .gt_lme4_restart_stability(primary, restart())
expect(isTRUE(clean$stable) && clean$restart_completed && clean$restart_warning_free &&
         clean$relative_objective == 0 && clean$scaled_parameter == 0,
       "a completed, warning-free restart at the same solution is stable")
incomplete <- .gt_lme4_restart_stability(primary, restart(code = 1L))
expect(!isTRUE(incomplete$stable) && !incomplete$restart_completed &&
         incomplete$restart_warning_free && incomplete$relative_objective == 0,
       "a restart with a nonzero optimizer code is not stable even at the same solution")
warned <- .gt_lme4_restart_stability(primary,
  restart(warnings = "Model failed to converge with max|grad| = 0.1"))
expect(!isTRUE(warned$stable) && warned$restart_completed && !warned$restart_warning_free,
       "a restart with an lme4 convergence warning is not stable even at the same solution")
moved <- .gt_lme4_restart_stability(primary, restart(theta = c(0.9, 0.3)))
expect(!isTRUE(moved$stable) && moved$restart_completed && moved$scaled_parameter > 0.02,
       "a completed restart at a different point is not stable")
worse <- .gt_lme4_restart_stability(primary, restart(objective = primary$objective + 1))
expect(!isTRUE(worse$stable) && worse$relative_objective > 1e-6,
       "a completed restart at a different objective is not stable")
expect(!isTRUE(.gt_lme4_restart_stability(primary, restart(code = NA_integer_))$stable),
       "a missing optimizer code is not completion")
expect(!isTRUE(.gt_lme4_restart_stability(primary, restart(theta = 0.8))$stable),
       "a restart with a different number of parameters is not stable")

# Every failure of the rule refuses the fit under the one existing label.
passing <- list(stationary_within_tolerance = TRUE)
expect("restart_or_tolerance_stability_failed" %in%
         .gt_lme4_acceptance(0L, character(), passing, incomplete$stable, TRUE) &&
         "restart_or_tolerance_stability_failed" %in%
         .gt_lme4_acceptance(0L, character(), passing, warned$stable, TRUE) &&
         !"restart_or_tolerance_stability_failed" %in%
         .gt_lme4_acceptance(0L, character(), passing, clean$stable, TRUE),
       "an incomplete or warned restart refuses the fit under the restart-stability label")

if (requireNamespace("lme4", quietly = TRUE)) {
  set.seed(2026102103L)
  d <- expand.grid(item = seq_len(20L), rater = seq_len(4L))
  d$score <- 5 + rnorm(20L, sd = 1.2)[d$item] + rnorm(4L, sd = .5)[d$rater] +
    rnorm(nrow(d), sd = .8)
  fit <- gt_fit(d, "score", gt_design("item", "rater"),
                control = gt_control(gaussian = list(engine = "lme4")))
  stability <- fit$diagnostics$stability
  expect(isTRUE(fit$numerically_accepted) && isTRUE(stability$stable) &&
           isTRUE(stability$restart_completed) && isTRUE(stability$restart_warning_free) &&
           identical(stability$optimizer_codes, c(0L, 0L)) && !length(stability$restart_warnings),
         "a real clean fit records a completed, warning-free restart and is accepted")
} else cat("SKIP: suggested lme4 is unavailable for the real-fit check.\n")
cat("PASS: the lme4 restart rule requires a completed, warning-free restart that reproduces the solution.\n")
