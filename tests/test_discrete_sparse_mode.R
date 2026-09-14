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

# --- The decision constants are the dense ones --------------------------------
# Asserted structurally because they cannot be asserted numerically. On every
# fixture in the reference the full Newton step is accepted at the first
# multiplier, the curvature clamp is never active, and the final relaxed
# tolerance never binds: the conditional problem is a penalised GLM solved with
# its own exact Hessian, so the line search is defensive code that the
# supported envelope does not reach. Mutating the backtracking cap, the
# sufficient-decrease constant or the final relaxation factor therefore leaves
# every numerical result in this file unchanged.
#
# That is a real limit on what the comparisons above qualify, and it is the
# reason these constants are pinned against the dense solver directly. This
# does not test the line search; it tests that the twin did not quietly
# acquire different rules from the solver it is a twin of.
dense_body <- paste(deparse(body(.gt_d_dense_mode)), collapse = " ")
sparse_body <- paste(deparse(body(.gt_d_sparse_mode)), collapse = " ")
literals <- function(text)
  sort(unique(regmatches(text, gregexpr("[0-9]+e[+-][0-9]+|[0-9]*\\.?[0-9]+", text))[[1]]))
expect(identical(literals(sparse_body), literals(dense_body)),
       paste0("the sparse solver uses the dense solver's numeric constants: dense {",
              paste(literals(dense_body), collapse = " "), "}, sparse {",
              paste(literals(sparse_body), collapse = " "), "}"))
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
