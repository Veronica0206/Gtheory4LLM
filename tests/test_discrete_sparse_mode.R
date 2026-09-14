# Run from the project directory with Rscript tests/test_discrete_sparse_mode.R.
#
# The sparse conditional-mode solve at fixed parameters. No outer optimizer
# runs here, so nothing under test depends on the unresolved portability issue
# in #14 through that path.
#
# This solver is a deliberate twin of the dense one, so the risk it carries is
# not a wrong answer but a quietly different algorithm that happens to land
# nearby. Endpoint agreement alone would not detect that: a solver that took a
# different number of steps, or accepted a different line-search multiplier,
# could still converge to the same mode. The iteration count and the
# convergence flag are therefore asserted as equal, not merely as plausible.
#
# The frozen fixtures are all well conditioned: on every one of them the full
# Newton step is accepted at the first multiplier and the relaxed final
# tolerance never binds, so neither branch is exercised by them. That is a
# property of those fixtures, not of the supported envelope. A saturating
# intercept with a large random factor, both inside the package's declared
# bounds, reaches both branches, and the adversarial cases below do so
# deterministically.
#
# The second risk is the Laplace correction. The dense value adds
# sum(log(diag(R))), half the log determinant of the Hessian, while the sparse
# log determinant is the whole one. Getting that wrong moves only the marginal
# value: mode, gradient, eta and every Hessian entry stay in exact agreement.
# The halving is asserted directly and separately below, because no check of
# the conditional problem can see it.
source(file.path("validation-studies", "discrete-sparse-reference", "cases.R"))
source(file.path("R", "discrete_sparse.R"))
source(file.path("R", "discrete_sparse_mode.R"))

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
outcome <- function(expr) tryCatch({ force(expr); "accepted" }, error = conditionMessage)
DIRECTORY <- file.path("validation-studies", "discrete-sparse-reference")
frozen <- read.csv(file.path(DIRECTORY, "reference.csv"), stringsAsFactors = FALSE)

# Restated from the reference's declared tolerances so that loosening one here
# is an edit rather than an argument.
OBJECTIVE <- c(relative = 1e-8, absolute = 1e-10)
MODE <- c(relative = 1e-6, absolute = 1e-6)
STATIONARY <- c(absolute = 1e-6)
IDENTITY <- c(absolute = 1e-10)
# Sparse against dense is a far tighter claim than either against the frozen
# reference. Both evaluate the same algebra at the same fixed parameters from
# the same kernel, so they may differ only by accumulation order. A difference
# above this is an implementation defect, not a tolerance question.
AGAINST_DENSE <- 1e-10

within <- function(got, want, limit) {
  difference <- abs(got - want)
  if (difference <= limit[["absolute"]]) return(TRUE)
  if (!is.na(limit["relative"]) && want != 0)
    return(difference / abs(want) <= limit[["relative"]])
  FALSE
}
frozen_value <- function(key, quantity) {
  value <- frozen$value[frozen$case == key & frozen$quantity == quantity]
  expect(length(value) == 1L, paste("the reference froze", key, quantity))
  value
}

solve_both <- function(case, control_override = list()) {
  control <- .gt_d_control(utils::modifyList(case$control, control_override))
  prep <- .gt_d_prepare(case$data, case$outcomes, case$families)
  groups <- lapply(case$design$term_members, function(m) .gt_d_group(case$data, m))
  setup <- .gt_d_covariance_setup(groups, prep$q, case$covariance, control, prep$dimensions)
  parameters <- c(prep$start + case$offset, setup$start * case$scale)
  factors <- .gt_d_covariance_factors(parameters[-seq_along(prep$start)], setup)
  list(parameters = parameters, prep = prep, control = control,
       dense_backend = .gt_d_dense_backend(groups, factors, prep$n, prep$q),
       sparse_backend = .gt_d_sparse_backend(groups, factors, prep$n, prep$q))
}

# A conditional problem that forces the line search to backtrack. A saturating
# intercept drives the binary curvature to zero, so I + W'CW approaches the
# identity and the Newton step approaches the raw penalised score. That step
# overshoots by orders of magnitude: it buys a likelihood improvement bounded
# by the saturated term while paying a quadratic penalty in the mode.
#
# Both coordinates are inside what the package accepts. The intercept is a
# declared binary mean and the factor gives a variance of 400 to 1600, against
# a direct variance coordinate that admits exp(10), about 22026.
#
# This is a stress test of the conditional solver, not a supported fitted
# design. One item level per observation is deliberate, because it makes the
# penalty dominate cleanly, and the public fitter rejects observation-specific
# random sources. Identifiability does not bear on exercising a
# fixed-parameter Newton step and line search, which is all this is for, and
# nothing here should be read as a claim that such a model can be fitted.
saturating_case <- function(intercept, scale, items = 4L) {
  data <- data.frame(item = factor(seq_len(items)),
                     y = c(rep(1L, items - 1L), 0L))
  prep <- .gt_d_prepare(data, "y", list(list(family = "binary", link = "logit",
                                             levels = c("0", "1"), reference = NULL)))
  groups <- list(item = .gt_d_group(data, "item"))
  factors <- list(item = matrix(scale, 1L, 1L))
  list(prep = prep, parameters = intercept,
       dense_backend = .gt_d_dense_backend(groups, factors, prep$n, prep$q),
       sparse_backend = .gt_d_sparse_backend(groups, factors, prep$n, prep$q))
}

# How many halvings the first Newton step needs before it satisfies sufficient
# decrease. This re-derives the acceptance rule on purpose: it establishes a
# property of the fixture, that the undamped step is rejected, without asking
# either solver whether it agrees. A fixture that stopped forcing backtracking
# would otherwise leave the assertions below passing vacuously.
first_step_reductions <- function(at, control) {
  W <- at$dense_backend$W
  baseline <- .gt_d_baseline(at$parameters, at$prep)
  u <- numeric(ncol(W))
  shape <- function(vector) baseline + matrix(W %*% vector, at$prep$n, at$prep$q)
  response <- .gt_d_response_kernel(shape(u), at$parameters, at$prep)
  expect(isTRUE(response$valid), "the adversarial case evaluates at its starting point")
  gradient <- as.vector(crossprod(W, response$gradient)) + u
  factorization <- chol(.gt_d_dense_hessian(response$curvature, W, at$prep$n))
  step <- backsolve(factorization, forwardsolve(t(factorization), gradient))
  objective <- response$nll + sum(u^2) / 2
  descent <- sum(gradient * step)
  multiplier <- 1
  for (reduction in 0:29) {
    candidate <- u - multiplier * step
    trial <- .gt_d_response_kernel(shape(candidate), at$parameters, at$prep)
    if (isTRUE(trial$valid) && trial$nll + sum(candidate^2) / 2 <=
        objective - 1e-4 * multiplier * descent + 1e-12) return(reduction)
    multiplier <- multiplier / 2
  }
  NA_integer_
}

# --- Agreement with the dense solver and with the frozen reference ------------
for (case in cases) {
  at <- solve_both(case)
  label <- paste0("case ", case$key)
  dense <- .gt_d_dense_mode(at$parameters, at$prep, at$dense_backend, at$control, details = TRUE)
  sparse <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control, details = TRUE)
  expect(isTRUE(dense$valid) && isTRUE(sparse$valid), paste(label, "solves on both backends"))

  # Control flow, not just the endpoint. A different step count or a different
  # accepted multiplier is a different algorithm even when the mode agrees.
  expect(identical(dense$inner_iterations, sparse$inner_iterations),
         paste0(label, " takes the same number of inner iterations: dense ",
                dense$inner_iterations, ", sparse ", sparse$inner_iterations))
  expect(identical(isTRUE(dense$inner_converged), isTRUE(sparse$inner_converged)),
         paste(label, "reaches the same convergence verdict"))
  expect(identical(dense$random_dimension, sparse$random_dimension),
         paste(label, "solves in the same random dimension"))

  # Coordinatewise. A shared norm is not shared agreement.
  expect(length(sparse$mode) == length(dense$mode), paste(label, "returns a mode of equal length"))
  expect(max(abs(sparse$mode - dense$mode)) <= AGAINST_DENSE,
         paste0(label, " mode matches dense within ", format(AGAINST_DENSE), "; worst ",
                format(max(abs(sparse$mode - dense$mode)), digits = 3)))
  expect(max(abs(sparse$eta - dense$eta)) <= AGAINST_DENSE,
         paste0(label, " predictor matches dense; worst ",
                format(max(abs(sparse$eta - dense$eta)), digits = 3)))
  expect(abs(sparse$conditional_nll - dense$conditional_nll) <= AGAINST_DENSE,
         paste(label, "conditional objective matches dense"))
  expect(abs(sparse$nll - dense$nll) <= AGAINST_DENSE,
         paste0(label, " marginal value matches dense; difference ",
                format(abs(sparse$nll - dense$nll), digits = 3)))

  # Against the frozen targets, each at the kind the reference declared.
  for (i in seq_along(sparse$mode))
    expect(within(sparse$mode[[i]], frozen_value(case$key, paste0("mode_", i)), MODE),
           paste0(label, " mode_", i, " matches the frozen target"))
  for (i in seq_along(sparse$eta))
    expect(within(sparse$eta[[i]], frozen_value(case$key, paste0("eta_", i)), MODE),
           paste0(label, " eta_", i, " matches the frozen target"))
  expect(within(sparse$conditional_nll, frozen_value(case$key, "conditional_objective"), OBJECTIVE),
         paste(label, "conditional objective matches the frozen target"))
  expect(within(sparse$nll, frozen_value(case$key, "marginal_laplace_nll"), OBJECTIVE),
         paste(label, "marginal Laplace value matches the frozen target"))
  # The penalised score, coordinatewise. inner_gradient is only the largest
  # absolute component, and two different score vectors can share a maximum,
  # so agreeing on it is not agreeing on the score. Both scores are taken at
  # the sparse mode, so what is compared is the product with W rather than a
  # difference in where the two solvers stopped.
  #
  # The three assertions below establish different things, and the difference
  # matters. Only the first is coordinate-wise equivalence.
  #
  #   1. Against dense at 1e-10. This is the equivalence evidence. A permuted
  #      score, or a flat one with the same maximum, differs here by 2.2e-08
  #      and fails.
  #   2. Against the frozen score_i at the declared stationary allowance. On
  #      these fixtures the frozen scores are around 1e-08, two orders below
  #      that 1e-06 absolute allowance, so this asserts that the score is
  #      small and cannot distinguish one near-zero vector from another. That
  #      is what the reference intends by the stationary kind, and it is not
  #      evidence of reproduction. Tightening it would mean redeclaring a
  #      frozen tolerance, which is not this PR's to do.
  #   3. That the reported inner_gradient is the maximum of the vector just
  #      compared. This catches a stale or unrelated reported diagnostic; a
  #      permutation preserves the maximum, so it does not catch that.
  kernel <- .gt_d_response_kernel(sparse$eta, at$parameters, at$prep)
  expect(isTRUE(kernel$valid), paste(label, "evaluates at the returned mode"))
  sparse_score <-
    as.numeric(Matrix::crossprod(at$sparse_backend$W, kernel$gradient)) + sparse$mode
  dense_score <-
    as.vector(crossprod(at$dense_backend$W, kernel$gradient)) + sparse$mode
  expect(length(sparse_score) == length(dense_score),
         paste(label, "scores the same number of coordinates"))
  expect(max(abs(sparse_score - dense_score)) <= AGAINST_DENSE,
         paste0(label, " score matches dense coordinatewise; worst ",
                format(max(abs(sparse_score - dense_score)), digits = 3)))
  for (i in seq_along(sparse_score))
    expect(abs(sparse_score[[i]] - frozen_value(case$key, paste0("score_", i)))
             <= STATIONARY[["absolute"]],
           paste0(label, " score_", i, " matches the frozen target"))
  # The reported diagnostic must summarise the vector just compared, not some
  # other one: a correct score reported alongside an unrelated maximum would
  # otherwise pass both of the checks above.
  expect(abs(max(abs(sparse_score)) - sparse$inner_gradient) <= 1e-14,
         paste0(label, " reports the maximum of the score it actually leaves: ",
                format(max(abs(sparse_score)), digits = 3), " against ",
                format(sparse$inner_gradient, digits = 3)))
  expect(abs(sparse$inner_gradient) <= STATIONARY[["absolute"]],
         paste0(label, " leaves a solved penalised score; worst ",
                format(sparse$inner_gradient, digits = 3)))
  expect(identical(as.numeric(isTRUE(sparse$inner_converged)),
                   frozen_value(case$key, "inner_converged")),
         paste(label, "reaches the frozen convergence verdict"))

  # The scalar path is what an optimizer would call. It must not drift from
  # the detailed path it shares its arithmetic with.
  scalar <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control)
  expect(identical(scalar, sparse$nll), paste(label, "returns the same value without details"))
}

# --- The Laplace correction is half the log determinant -----------------------
# Asserted on its own because nothing about the conditional problem depends on
# it: with the whole log determinant added instead, the mode, the predictor,
# the gradient and every Hessian entry are still exactly right.
for (case in cases) {
  at <- solve_both(case)
  label <- paste0("case ", case$key)
  sparse <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control, details = TRUE)
  kernel <- .gt_d_response_kernel(sparse$eta, at$parameters, at$prep)
  expect(isTRUE(kernel$valid), paste(label, "evaluates at its own returned mode"))
  H <- .gt_d_sparse_hessian(kernel$curvature, at$sparse_backend$W, at$prep$n)
  logdet <- .gt_d_sparse_logdet(.gt_d_sparse_factor(H))
  conditional <- sparse$conditional_nll + sum(sparse$mode^2) / 2

  expect(abs(sparse$nll - (conditional + logdet / 2)) <= IDENTITY[["absolute"]],
         paste0(label, " adds half the log determinant; residual ",
                format(abs(sparse$nll - (conditional + logdet / 2)), digits = 3)))
  # And is not merely within reach of the unhalved value. Without this the
  # assertion above would pass on a fixture whose log determinant is near zero.
  unhalved <- abs(sparse$nll - (conditional + logdet))
  expect(unhalved > 1e3 * IDENTITY[["absolute"]],
         paste0(label, " distinguishes the halved correction from the whole one; ",
                "the whole one is off by ", format(unhalved, digits = 3)))
  expect(within(logdet, frozen_value(case$key, "hessian_log_determinant"), OBJECTIVE),
         paste(label, "log determinant matches the frozen target"))
}

# --- The budget is respected and reported the same way ------------------------
# One inner iteration cannot solve these, so both solvers must agree that they
# did not converge rather than one of them reporting success.
for (case in cases[1:3]) {
  at <- solve_both(case, list(inner_maxit = 1L))
  label <- paste0("case ", case$key, " at one inner iteration")
  dense <- .gt_d_dense_mode(at$parameters, at$prep, at$dense_backend, at$control, details = TRUE)
  sparse <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control, details = TRUE)
  expect(identical(isTRUE(dense$valid), isTRUE(sparse$valid)),
         paste(label, "reaches the same validity verdict"))
  expect(identical(isTRUE(dense$inner_converged), isTRUE(sparse$inner_converged)),
         paste(label, "reaches the same convergence verdict"))
  scalar_dense <- .gt_d_dense_mode(at$parameters, at$prep, at$dense_backend, at$control)
  scalar_sparse <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control)
  expect(identical(scalar_dense, scalar_sparse),
         paste0(label, " returns the same scalar: dense ", format(scalar_dense),
                ", sparse ", format(scalar_sparse)))
}

# --- A tighter inner tolerance is still reproduced -----------------------------
# The reference was produced at the default tolerance. Agreeing only there
# would leave open that the two solvers differ in how they approach the mode
# rather than in where they stop.
for (case in cases) {
  at <- solve_both(case, list(inner_tol = 1e-11))
  label <- paste0("case ", case$key, " at a tightened inner tolerance")
  dense <- .gt_d_dense_mode(at$parameters, at$prep, at$dense_backend, at$control, details = TRUE)
  sparse <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control, details = TRUE)
  expect(isTRUE(dense$valid) && isTRUE(sparse$valid), paste(label, "still solves"))
  expect(identical(dense$inner_iterations, sparse$inner_iterations),
         paste(label, "still takes the same number of inner iterations"))
  expect(max(abs(sparse$mode - dense$mode)) <= AGAINST_DENSE,
         paste(label, "still matches the dense mode"))
  expect(abs(sparse$nll - dense$nll) <= AGAINST_DENSE,
         paste(label, "still matches the dense marginal value"))
}

# --- Categorical is refused, not approximated ---------------------------------
categorical <- list(key = "categorical_refusal",
  data = local({
    set.seed(91)
    d <- expand.grid(item = seq_len(8), rater = seq_len(3))
    d$y <- factor(c("a", "b", "c")[sample.int(3L, nrow(d), replace = TRUE)],
                  levels = c("a", "b", "c"))
    d
  }),
  outcomes = "y",
  families = list(list(family = "categorical", link = "softmax",
                       levels = c("a", "b", "c"), reference = "a")),
  design = list(object = "item", facets = "rater",
                term_members = list(item = "item", rater = "rater")),
  covariance = "diagonal", offset = 0.1, scale = 1, control = list())
at <- solve_both(categorical)
said <- outcome(.gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, at$control))
expect(!identical(said, "accepted"), "the sparse mode solver refuses a categorical response")
expect(grepl("categorical", said) && grepl("dense", said),
       paste0("the categorical refusal names the dense backend; it said: ", said))
# The dense solver takes exactly the case the refusal points at, so the
# refusal describes a real alternative rather than an unimplemented one.
dense_categorical <- .gt_d_dense_mode(at$parameters, at$prep, at$dense_backend,
                                      at$control, details = TRUE)
expect(isTRUE(dense_categorical$valid),
       "the dense backend does solve the categorical case the refusal names")

# --- Malformed input ----------------------------------------------------------
at <- solve_both(cases[[1L]])
malformed <- list(
  dense_backend = function()
    .gt_d_sparse_mode(at$parameters, at$prep, at$dense_backend, at$control),
  no_backend = function() .gt_d_sparse_mode(at$parameters, at$prep, list(), at$control),
  wrong_dimensions = function() {
    backend <- at$sparse_backend
    backend$n <- backend$n + 1L
    .gt_d_sparse_mode(at$parameters, at$prep, backend, at$control)
  },
  short_parameters = function()
    .gt_d_sparse_mode(numeric(0), at$prep, at$sparse_backend, at$control),
  control_not_a_list = function()
    .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, "default"),
  inner_maxit_zero = function()
    .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend,
                      utils::modifyList(at$control, list(inner_maxit = 0L))),
  inner_maxit_fractional = function()
    .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend,
                      utils::modifyList(at$control, list(inner_maxit = 2.5))),
  inner_tol_zero = function()
    .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend,
                      utils::modifyList(at$control, list(inner_tol = 0))),
  inner_tol_infinite = function()
    .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend,
                      utils::modifyList(at$control, list(inner_tol = Inf))),
  nonfinite_design = function() {
    backend <- at$sparse_backend
    backend$W@x[[1L]] <- NA_real_
    .gt_d_sparse_mode(at$parameters, at$prep, backend, at$control)
  })
for (name in names(malformed)) {
  said <- outcome(malformed[[name]]())
  expect(!identical(said, "accepted"), paste("the sparse mode solver refuses", name))
  expect(grepl("sparse mode|dimensions|matrix|parameters or controls", said),
         paste0("the refusal of ", name, " is the backend's own; it said: ", said))
}

# --- The line search actually backtracks, and both solvers agree while it does -
# Three cases needing one, two and three halvings on the first step. The
# reduction count is established first, from the acceptance rule itself, so
# these cannot pass by quietly ceasing to be adversarial.
for (spec in list(c(intercept = -15, scale = 10, least = 1),
                  c(intercept = -15, scale = 20, least = 2),
                  c(intercept = -15, scale = 40, least = 3))) {
  at <- saturating_case(spec[["intercept"]], spec[["scale"]])
  control <- .gt_d_control(list())
  label <- paste0("saturating case intercept ", spec[["intercept"]],
                  " factor ", spec[["scale"]])
  reductions <- first_step_reductions(at, control)
  expect(!is.na(reductions) && reductions >= spec[["least"]],
         paste0(label, " rejects the undamped Newton step and needs at least ",
                spec[["least"]], " halvings; it needed ", reductions))

  dense <- .gt_d_dense_mode(at$parameters, at$prep, at$dense_backend, control, details = TRUE)
  sparse <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, control, details = TRUE)
  expect(isTRUE(dense$valid) && isTRUE(sparse$valid),
         paste(label, "solves on both backends despite the backtracking"))
  expect(identical(dense$inner_iterations, sparse$inner_iterations),
         paste0(label, " takes the same number of inner iterations through the line ",
                "search: dense ", dense$inner_iterations, ", sparse ", sparse$inner_iterations))
  expect(identical(isTRUE(dense$inner_converged), isTRUE(sparse$inner_converged)),
         paste(label, "reaches the same convergence verdict"))
  expect(max(abs(sparse$mode - dense$mode)) <= AGAINST_DENSE,
         paste0(label, " reaches the dense mode; worst ",
                format(max(abs(sparse$mode - dense$mode)), digits = 3)))
  expect(abs(sparse$nll - dense$nll) <= AGAINST_DENSE,
         paste0(label, " reaches the dense marginal value; difference ",
                format(abs(sparse$nll - dense$nll), digits = 3)))
}

# --- The relaxed final tolerance binds, at the factor the dense solver uses ---
# The final verdict is last_gradient <= inner_tol * 10. On the frozen fixtures
# the mode is solved far past that, so the factor never matters and mutating it
# changes nothing. Here the stopping point is pinned by allowing a single inner
# iteration, and the tolerances are then derived from the gradient the dense
# solver actually leaves there, so the bracket comes from dense behaviour
# rather than from the implementation under test.
at <- saturating_case(-15, 20)
probe <- .gt_d_control(list(inner_maxit = 1L, inner_tol = 1e-12))
left <- .gt_d_dense_mode(at$parameters, at$prep, at$dense_backend, probe, details = TRUE)
stopping_gradient <- left$inner_gradient
expect(is.finite(stopping_gradient) && stopping_gradient > 0,
       "one dense inner iteration leaves a positive final gradient to calibrate against")

# At inner_tol = g/100 the declared rule asks g <= g/10 and must refuse; any
# factor of 100 or more would accept. At inner_tol = g/5 it asks g <= 2g and
# must accept; any factor below 5 would refuse. Together these bracket the
# declared factor of 10 from both sides.
for (spec in list(list(tolerance = stopping_gradient / 100, converged = FALSE,
                       misses = "a factor of 100 or more would accept this"),
                  list(tolerance = stopping_gradient / 5, converged = TRUE,
                       misses = "a factor below 5 would refuse this"))) {
  control <- .gt_d_control(list(inner_maxit = 1L, inner_tol = spec$tolerance))
  dense <- .gt_d_dense_mode(at$parameters, at$prep, at$dense_backend, control, details = TRUE)
  sparse <- .gt_d_sparse_mode(at$parameters, at$prep, at$sparse_backend, control, details = TRUE)
  label <- paste0("at inner_tol = ", format(spec$tolerance, digits = 3))
  # The bracket is only about the factor if the solver stopped in the same
  # place; a tolerance large enough to end the loop early would move it.
  expect(isTRUE(all.equal(dense$inner_gradient, stopping_gradient)),
         paste(label, "the dense solver stops at the same gradient"))
  expect(isTRUE(all.equal(sparse$inner_gradient, stopping_gradient)),
         paste(label, "the sparse solver stops at the same gradient"))
  expect(identical(isTRUE(sparse$inner_converged), spec$converged),
         paste0(label, " the sparse solver reports converged = ", spec$converged,
                "; ", spec$misses))
  expect(identical(isTRUE(dense$inner_converged), isTRUE(sparse$inner_converged)),
         paste(label, "both solvers reach the same verdict"))
}

# --- The decision constants are the dense ones --------------------------------
# A last-resort drift alarm, not branch coverage. The line search and the
# relaxed final tolerance are exercised numerically above; this only pins the
# few source-level rules that no reachable input distinguishes, such as the
# backtracking cap being 30 rather than 29.
#
# Named constructs only. An earlier version compared the whole set of numeric
# literals in the two bodies, which was too broad in one direction and too weak
# in the other: a harmless sparse-only literal would have broken it, while equal
# literal sets never established that the numbers play the same roles.
#
# Each rule is required of the dense solver first. If the dense solver stops
# containing one, this fails and says the pin is stale, rather than silently
# becoming a check that nothing has to satisfy.
dense_body <- paste(deparse(body(.gt_d_dense_mode)), collapse = " ")
sparse_body <- paste(deparse(body(.gt_d_sparse_mode)), collapse = " ")
for (construct in c("seq_len(30L)", "1e-04", "multiplier * descent", "multiplier <- 1",
                    "multiplier/2", "inner_tol * 10", "1e+100", "1e-12",
                    "sum(u^2)/2", "sum(candidate^2)/2")) {
  expect(grepl(construct, dense_body, fixed = TRUE),
         paste0("the dense solver still contains ", construct,
                "; this pin is stale and must be rewritten, not deleted"))
  expect(grepl(construct, sparse_body, fixed = TRUE),
         paste0("the sparse solver keeps the dense rule ", construct))
}

# --- The solver never builds a dense design -----------------------------------
# Mechanical, like the guard on the earlier sparse steps: the point of this
# path is the allocation it does not make, and that is a property of the source
# rather than of any one run.
source_text <- readLines(file.path("R", "discrete_sparse_mode.R"), warn = FALSE)
code <- grep("^\\s*#", source_text, value = TRUE, invert = TRUE)
for (banned in c("as.matrix(", "Matrix::Matrix(", "matrix(0", "diag("))
  expect(!any(grepl(banned, code, fixed = TRUE)),
         paste0("the sparse mode solver never calls ", banned))

cat("PASS: the sparse conditional mode reproduces the dense solve and the frozen ",
    "targets, including the halved log determinant.\n", sep = "")
