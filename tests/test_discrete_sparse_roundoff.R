# Objective plateaus may change search steps, never the final score tolerance.
source("load_functions.R")
expect <- function(ok, message) if (!isTRUE(ok)) stop(message)
slack <- 32 * .Machine$double.eps * 1000
expect(.gt_d_roundoff_descent(1000, 1000 + slack / 2, slack / 4, c(1e-7, 0), c(1e-10, 0)),
       "An objective-indistinguishable full step with strict score improvement is eligible")
expect(!.gt_d_roundoff_descent(1000, 1000, slack * 2, 1e-7, 1e-10),
       "A decrement beyond the small window needs directional evidence and a final-mode bound")
expect(!.gt_d_roundoff_descent(1000, 1000 + slack * 2, slack / 4, 1e-7, 1e-10),
       "A discrepancy beyond the small window needs directional evidence and a final-mode bound")
expect(!.gt_d_roundoff_descent(1000, 1000, slack / 4, 1e-7, 1e-7),
       "An unchanged score cannot rescue a stalled step")
expect(!.gt_d_roundoff_descent(1000, 1000, -slack / 4, 1e-7, 1e-10),
       "A non-descent Newton direction is refused")
expect(!.gt_d_roundoff_descent(1000, 1000, slack / 4, 1e-7, NA_real_),
       "A nonfinite score is refused")

# A rounded quadratic supplies an independent derivative oracle: the full
# Newton step reaches its exact stationary point while scalar evaluation
# noise exceeds a handful of ulps. The exception still needs both directional
# inequalities; an infinity-norm decrease alone does not imply them.
g <- 2e-7
step <- 1e-7
descent <- g * step
noisy_value <- 1000 + 1e-10
expect(!.gt_d_roundoff_descent(1000, noisy_value, descent, g, 0),
       "A larger scalar discrepancy needs the directional check")
expect(.gt_d_roundoff_descent(1000, noisy_value, descent, g, 0, step, 1e-9),
       "The derivative safeguard reaches the quadratic's stationary point")
expect(!.gt_d_roundoff_descent(1000, 1000 + 2 * sqrt(.Machine$double.eps) * 1000,
                               descent, g, 0, step, 1e-9),
       "A material scalar increase remains refused despite a zero score")
allowance <- sqrt(.Machine$double.eps) * 1000
large_g <- sqrt(2 * allowance)
expect(!.gt_d_roundoff_descent(1000, noisy_value, large_g^2, large_g, 0, large_g, 1e-9),
       "The directional safeguard refuses a decrement beyond its function allowance")
expect(!.gt_d_roundoff_descent(1000, noisy_value, descent, g, 0, NA_real_, 1e-9),
       "Nonfinite directional evidence is unavailable")
expect(!.gt_d_roundoff_descent(1000, noisy_value, descent, g, 0, c(step, step), 1e-9),
       "Directional evidence must match the score dimension")
expect(!.gt_d_roundoff_descent(1000, noisy_value, descent, g, 1e-8, step, 1e-9),
       "The wider function window cannot accept a nonstationary candidate")
expect(!.gt_d_roundoff_descent(1000, noisy_value, descent, g, 0, step),
       "The wider function window requires an explicit final-mode bound")
g2 <- c(3e-7, 2.9e-7)
step2 <- c(1e-7, -0.9e-7)
descent2 <- sum(g2 * step2)
expect(!.gt_d_roundoff_descent(1000, noisy_value, descent2, g2, c(2e-7, -2e-7), step2, 2.1e-7),
       "A smaller score can still violate the lower directional bound")
expect(!.gt_d_roundoff_descent(1000, noisy_value, descent2, g2, c(-2e-7, 2e-7), step2, 2.1e-7),
       "A smaller score can still violate the upper directional bound")
expect(!.gt_d_roundoff_descent(1000, noisy_value, 0, g, 0, step, 1e-9),
       "A zero or underflowed decrement supplies no descent evidence")

# A quadratic Newton step may exceed the small plateau window yet finish at
# its exact minimum. The wider branch must test its own decrement allowance,
# not first reject it using the narrower branch's bound.
g3 <- step3 <- 1e-4
descent3 <- g3 * step3
expect(descent3 > slack && descent3 < allowance, "Independent quadratic spans the two windows")
expect(.gt_d_roundoff_descent(1000, noisy_value, descent3, g3, 0, step3, 1e-9),
       "A stationary full step may use the wider function allowance")
for (candidate_score in c(.999e-9, 1e-9))
  expect(.gt_d_roundoff_descent(1000, noisy_value, descent3, g3, candidate_score, step3, 1e-9),
         "The unchanged final-mode bound includes equality")
expect(!.gt_d_roundoff_descent(1000, noisy_value, descent3, g3, 1.001e-9, step3, 1e-9),
       "Strict score improvement above the final-mode bound is still refused")
for (bad_tolerance in list(NULL, 0, -1, NA_real_, Inf, c(1e-9, 1e-8), "1e-9"))
  expect(!.gt_d_roundoff_descent(1000, noisy_value, descent3, g3, 0, step3, bad_tolerance),
         "The wider branch requires one finite positive numerical mode bound")
expect(.gt_d_roundoff_descent(1000, 1000, slack / 4, g, 0, step, NA_real_),
       "The legacy small-plateau branch does not acquire a new tolerance argument")

# No RNG: a moderate ordinal panel that encounters a rounded objective plateau
# on the development platform. Other BLAS builds may take different steps;
# the portable contract is the same objective and final stationarity.
data <- expand.grid(item = seq_len(20L), rater = seq_len(20L))
data$y <- ordered(paste0("c", (data$item * 7 + data$rater * 11 + data$item %/% 3) %% 5 + 1),
                  levels = paste0("c", 1:5))
family <- list(list(family = "ordinal", link = "logit", levels = levels(data$y), reference = NULL))
prep <- .gt_d_prepare(data, "y", family)
groups <- list(item = .gt_d_group(data, "item"), rater = .gt_d_group(data, "rater"))
factors <- list(item = matrix(0.4), rater = matrix(0.2))
dense <- .gt_d_dense_backend(groups, factors, prep$n, prep$q)
sparse <- .gt_d_sparse_backend(groups, factors, prep$n, prep$q)
control <- .gt_d_control(list(inner_tol = 1e-10))
reference <- .gt_d_dense_mode(prep$start - 2, prep, dense, control, details = TRUE)
answer <- .gt_d_sparse_mode(prep$start - 2, prep, sparse, control, details = TRUE)
expect(isTRUE(reference$valid) && isTRUE(answer$valid), "Both conditional modes satisfy the same tolerance")
expect(abs(reference$nll - answer$nll) < 1e-9 && max(abs(reference$mode - answer$mode)) < 1e-8,
       "Roundoff-aware search agrees with the independent dense solution")
expect(answer$inner_gradient <= control$inner_tol * 10 && is.numeric(answer$inner_roundoff_steps),
       "The original score gate and the search diagnostic are retained")

# Tail-stable arithmetic may reach this strict bound on some platforms. The
# portable contract concerns the final score, not a prescribed refusal.
strict <- .gt_d_control(list(inner_tol = 1e-16))
strict_answer <- .gt_d_sparse_mode(prep$start - 2, prep, sparse, strict, details = TRUE)
expect(!isTRUE(strict_answer$valid) ||
         (is.finite(strict_answer$inner_gradient) && strict_answer$inner_gradient <= strict$inner_tol * 10),
       "Acceptance still requires the original strict final score bound")
# A one-step budget deliberately leaves this panel far from stationarity,
# independently of whether the fully iterated path reaches machine precision.
strict$inner_maxit <- 1L
refused <- .gt_d_sparse_mode(prep$start - 2, prep, sparse, strict, details = TRUE)
expect(!isTRUE(refused$valid) && refused$inner_gradient > strict$inner_tol * 10,
       "Search progress does not relax final stationarity")
cat("PASS: roundoff-aware sparse search preserves stationarity and dense likelihood.\n")
