# The analytic gradient of the Laplace objective at fixed points, run from
# sources and from an installed archive. The oracle is the objective itself:
# central finite differences of the sparse evaluator's value, cold at a tight
# inner tolerance, in every stored coordinate, on small fixtures that cover
# binary, ordinal and nominal blocks, both links, joint outcomes, natural
# Cholesky, log-Cholesky, variance, exchangeable and fixed covariance
# coordinates, an exact zero pivot and an exact zero factor column. Negative
# controls drop the implicit-mode term and the log-determinant term and must
# fail by a margin. Refusals name their reason.
if (identical(Sys.getenv("GT_DISCRETE_GRADIENT_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
problem_of <- internal(".gt_d_laplace_problem")
gradient_of <- internal(".gt_d_gradient")
evaluator_of <- internal(".gt_d_sparse_evaluator")

data <- expand.grid(item = seq_len(12L), rater = seq_len(4L))
data$binary <- as.integer((data$item + 2 * data$rater) %% 5 < 2)
data$ordinal <- ordered(c("low", "middle", "high")[(data$item + data$rater) %% 3 + 1L],
                        levels = c("low", "middle", "high"))
data$ordinal4 <- ordered(c("a", "b", "c", "d")[(2 * data$item + data$rater) %% 4 + 1L], levels = c("a", "b", "c", "d"))
data$nominal <- factor(c("a", "b", "c")[(floor(data$item / 4) + data$rater) %% 3 + 1L], levels = c("a", "b", "c"))
families <- list(binary = gt_family("binary", "logit"),
                 binary_probit = gt_family("binary", "probit"),
                 ordinal = gt_family("ordinal", "probit", levels = levels(data$ordinal)),
                 ordinal4 = gt_family("ordinal", "logit", levels = levels(data$ordinal4)),
                 nominal = gt_family("categorical", levels = levels(data$nominal), reference = "a"))
data$binary_probit <- data$binary
design <- gt_design("item", "rater", random = c("item", "rater"))
tight <- list(engine = "sparse", inner_tol = 1e-10, validation_inner_tol = 1e-10)

objective_of <- function(problem) function(p)
  evaluator_of()(p, problem$prep, problem$groups, problem$setup, problem$control, details = TRUE)$nll
finite_difference <- function(objective, at, lower, step = 1e-5) {
  vapply(seq_along(at), function(j) {
    up <- at; up[j] <- up[j] + step
    if (at[j] - step >= lower[j]) {
      down <- at; down[j] <- down[j] - step
      (objective(up) - objective(down)) / (2 * step)
    } else {
      # Three-point forward difference inside a natural boundary.
      up2 <- at; up2[j] <- up2[j] + 2 * step
      (-3 * objective(at) + 4 * objective(up) - objective(up2)) / (2 * step)
    }
  }, numeric(1))
}
within <- function(analytic, reference, scale = 3e-7)
  all(is.finite(analytic)) && max(abs(analytic - reference) - scale * (1 + abs(reference))) <= 0

check <- function(label, outcomes, covariance = "unstructured", control = list(), covariance_values = NULL,
                  fixed_shift = 0.2, negative = FALSE) {
  problem <- problem_of(data, outcomes, design, families[outcomes], covariance, c(tight, control))
  at <- problem$start
  fixed <- seq_along(problem$prep$start)
  at[fixed] <- at[fixed] + fixed_shift * (-1)^fixed
  if (length(problem$setup$start)) {
    where <- length(problem$prep$start) + seq_along(problem$setup$start)
    if (!is.null(covariance_values)) at[where] <- covariance_values
  }
  names(at) <- names(problem$start)
  result <- gradient_of(at, problem$prep, problem$groups, problem$setup, problem$control, problem$context,
                        problem$envelope)
  stopifnot(isTRUE(result$valid), identical(names(result$gradient), names(at)))
  reference <- finite_difference(objective_of(problem), at, problem$lower)
  error <- max(abs(result$gradient - reference))
  if (!within(result$gradient, reference))
    stop(sprintf("%s: analytic gradient differs from finite differences by %.3g", label, error))
  stopifnot(is.list(result$timings), result$envelope$stored_entries > 0,
            result$selected_inverse$platform[["double_mantissa"]] == 53L)
  if (negative) {
    for (omit in c("implicit", "log_determinant")) {
      partial <- gradient_of(at, problem$prep, problem$groups, problem$setup, problem$control, problem$context,
                             problem$envelope, parts = setdiff(c("explicit", "log_determinant", "implicit"), omit))
      shortfall <- max(abs(partial$gradient - reference))
      if (shortfall < 1e-3)
        stop(sprintf("%s: omitting the %s term changes the gradient by only %.3g", label, omit, shortfall))
    }
  }
  cat(sprintf("PASS: %s (%d coordinates, max error %.2e)\n", label, length(at), error))
  invisible(list(problem = problem, at = at, result = result, reference = reference))
}

check("binary logit, variance coordinates", "binary", covariance_values = c(.3, .2))
check("binary logit, natural Cholesky", "binary", control = list(covariance_parameterization = "cholesky"),
      covariance_values = c(.6, .45))
check("binary probit, log-Cholesky", "binary_probit", control = list(covariance_parameterization = "log_cholesky"),
      covariance_values = log(c(.6, .45)))
check("ordinal probit, three categories", "ordinal", control = list(covariance_parameterization = "cholesky"),
      covariance_values = c(.7, .35), fixed_shift = 0.15)
check("ordinal logit, four categories, variance coordinates", "ordinal4", covariance_values = c(.4, .25),
      fixed_shift = 0.1)
check("nominal, unstructured natural Cholesky", "nominal", control = list(covariance_parameterization = "cholesky"),
      covariance_values = c(.6, .2, .5, .4, -.15, .35))
check("nominal, exchangeable", "nominal", covariance = "exchangeable", covariance_values = c(.3, .2))
joint <- check("joint binary and ordinal, natural Cholesky", c("binary", "ordinal"),
               control = list(covariance_parameterization = "cholesky"),
               covariance_values = c(.6, .2, .5, .4, -.1, .3), negative = TRUE)
check("joint binary and nominal, natural Cholesky", c("binary", "nominal"),
      control = list(covariance_parameterization = "cholesky"),
      covariance_values = c(.6, .2, .1, .5, .15, .4, .4, -.1, .05, .3, .1, .35))
check("joint binary and ordinal, log-Cholesky", c("binary", "ordinal"),
      control = list(covariance_parameterization = "log_cholesky"),
      covariance_values = c(log(.6), .2, log(.5), log(.4), -.1, log(.3)))
# Natural boundaries: an exact zero pivot and an exact zero factor column, with
# three-point forward differences in the coordinates at their bound.
check("zero pivot in a natural Cholesky factor", c("binary", "ordinal"),
      control = list(covariance_parameterization = "cholesky"),
      covariance_values = c(0, .2, .5, .4, -.1, .3))
check("zero factor column", c("binary", "ordinal"), control = list(covariance_parameterization = "cholesky"),
      covariance_values = c(0, 0, .5, .4, -.1, .3))
# Fixed source covariance: fixed-effect and threshold coordinates only.
covariance <- matrix(c(.3, .05, .05, .25), 2)
check("fixed covariance, fixed-effect gradient only", c("binary", "ordinal"),
      control = list(fixed_covariance = list(item = covariance, rater = covariance / 2)))

# The complete gradient on an explicitly widened ordinal domain, at the two
# witnesses of the paired logistic third derivative: before it was rescaled,
# the middle interval (-0.5, 475) gave a silently zero derivative and
# (-0.5, 499.5) a nonfinite one. Twelve rows, three categories, the first cut
# at -0.5 and the log gap at log(475.5) or log(500), declared within an upper
# bound of log(600); natural Cholesky coordinates at three covariance sizes.
# The reference is the objective's central differences at three steps.
wide <- data.frame(item = rep(seq_len(4L), each = 3L), rater = rep(seq_len(3L), 4L))
wide$grade <- ordered(c("low", "mid", "high")[c(2, 2, 1, 2, 2, 2, 3, 2, 2, 2, 1, 2)],
                      levels = c("low", "mid", "high"))
wide_family <- list(grade = gt_family("ordinal", "logit", levels = c("low", "mid", "high")))
wide_control <- c(tight, list(covariance_parameterization = "cholesky",
  parameter_bounds = list(upper = stats::setNames(log(600), "grade::threshold_parameter2"))))
for (gap in c(475.5, 500)) for (variance in c(0.05, 0.5, 2)) {
  problem <- problem_of(wide, "grade", design, wide_family, "unstructured", wide_control)
  at <- problem$start
  at[["grade::threshold_parameter1"]] <- -0.5
  at[["grade::threshold_parameter2"]] <- log(gap)
  at[length(problem$prep$start) + seq_along(problem$setup$start)] <- sqrt(variance)
  result <- gradient_of(at, problem$prep, problem$groups, problem$setup, problem$control, problem$context,
                        problem$envelope)
  label <- sprintf("wide logistic gap %.1f, variance %.2f", gap, variance)
  if (!isTRUE(result$valid)) stop(label, ": the analytic gradient was refused (", result$reason, ")")
  stopifnot(identical(names(result$gradient), names(at)), result$regimes[[1L]][["paired"]] > 0)
  for (step in c(1e-4, 5e-5, 1e-5)) {
    reference <- finite_difference(objective_of(problem), at, problem$lower, step)
    if (!within(result$gradient, reference))
      stop(sprintf("%s: analytic gradient differs from finite differences at step %g by %.3g", label, step,
                   max(abs(result$gradient - reference))))
  }
}
cat("PASS: complete gradient at the two wide logistic witnesses, three covariance sizes, three steps\n")

# The derivative is exact at the stationary conditional mode: its error
# against a tight reference shrinks as the inner tolerance tightens.
problem <- joint$problem
loose <- lapply(c(1e-3, 1e-6, 1e-10), function(tolerance) {
  control <- problem$control
  control$inner_tol <- tolerance
  gradient_of(joint$at, problem$prep, problem$groups, problem$setup, control, problem$context, problem$envelope)$gradient
})
errors <- vapply(loose, function(g) max(abs(g - joint$reference)), numeric(1))
stopifnot(errors[1] >= errors[2], errors[3] <= 1e-6)

# Refusals name their reason: an unusable evaluation, a variance coordinate at
# its zero boundary, an envelope of another design, an unknown part.
refusal <- gradient_of(joint$at, problem$prep, problem$groups, problem$setup, problem$control, problem$context,
                       problem$envelope, record = list(valid = FALSE))
stopifnot(identical(refusal$valid, FALSE), identical(refusal$reason, "invalid_evaluation"))
variance <- problem_of(data, "binary", design, families["binary"], "unstructured", tight)
at_zero <- variance$start
at_zero[length(variance$prep$start) + 1L] <- 0
refusal <- gradient_of(at_zero, variance$prep, variance$groups, variance$setup, variance$control, variance$context,
                       variance$envelope)
stopifnot(identical(refusal$valid, FALSE), identical(refusal$reason, "unsupported_coordinate_at_zero"),
          grepl("item", refusal$detail, fixed = TRUE))
other <- problem_of(data, "binary", gt_design("item", "rater", random = c("item", "rater", "item:rater")),
                    families["binary"], "unstructured", tight)
got <- tryCatch(gradient_of(variance$start, variance$prep, variance$groups, variance$setup, variance$control,
                            variance$context, other$envelope), error = identity)
stopifnot(inherits(got, "error") || identical(got$valid, FALSE))
got <- tryCatch(gradient_of(joint$at, problem$prep, problem$groups, problem$setup, problem$control, problem$context,
                            problem$envelope, parts = "everything"), error = identity)
stopifnot(inherits(got, "error"))
# The explicit term cannot be omitted: a selection without it is refused,
# never answered with the explicit term anyway.
for (parts in list(character(), c("log_determinant", "implicit"), "implicit")) {
  got <- tryCatch(gradient_of(joint$at, problem$prep, problem$groups, problem$setup, problem$control,
                              problem$context, problem$envelope, parts = parts), error = identity)
  stopifnot(inherits(got, "error"), grepl("must include explicit", conditionMessage(got), fixed = TRUE))
}
cat("PASS: analytic gradients against finite differences on thirteen fixtures, negative controls,",
    "inner-tolerance convergence and refusals.\n")
