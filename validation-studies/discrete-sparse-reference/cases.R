# Freeze the fixed-parameter targets a sparse discrete backend must reproduce.
#
# Sourced by run.R, which freezes these values, and by
# tests/test_discrete_reference.R, which checks the frozen values still hold.
# Both must evaluate the same fixtures, so neither defines them itself.
#
# Every quantity here is evaluated at a declared parameter vector. No outer
# optimizer runs, so nothing recorded depends on outer optimizer behaviour and
# the unresolved portability issue in #14 cannot reach these values through
# that path. The inner conditional-mode solver does produce them, so if that
# issue lives in the inner solve it would reach them; see PROTOCOL.md. Tolerances are
# declared in PROTOCOL.md from the solver's own tolerances and double
# precision, before any sparse implementation exists to compare against.
for (file in c("design.R", "family.R", "discrete_response.R", "discrete_dense.R",
               "discrete_mode.R", "discrete.R"))
  source(file.path("R", file))

out_dir <- file.path("validation-studies", "discrete-sparse-reference")
family_spec <- function(family, link, levels, reference = NULL)
  list(family = family, link = link, levels = levels, reference = reference)

# --- Fixtures -----------------------------------------------------------------
# Small by intention. These are fixed-parameter algebra targets, not fits: a
# reader must be able to check the recorded numbers, and a large panel would
# make the reference unreviewable without making it more diagnostic.
binary_panel <- function(seed, items, raters, link) {
  set.seed(seed)
  d <- expand.grid(item = seq_len(items), rater = seq_len(raters))
  effect <- rnorm(items, sd = 0.8)
  p <- if (link == "probit") pnorm(-0.2 + effect[d$item]) else plogis(-0.2 + effect[d$item])
  d$y <- rbinom(nrow(d), 1L, p)
  d
}
ordinal_panel <- function(seed, items, raters, link) {
  set.seed(seed)
  d <- expand.grid(item = seq_len(items), rater = seq_len(raters))
  effect <- rnorm(items, sd = 0.7)
  eta <- effect[d$item]
  cuts <- c(-0.8, 0.4)
  probability <- function(x) if (link == "probit") pnorm(x) else plogis(x)
  lower <- probability(cuts[1] - eta); upper <- probability(cuts[2] - eta)
  u <- runif(nrow(d))
  d$y <- factor(ifelse(u < lower, "low", ifelse(u < upper, "mid", "high")),
                levels = c("low", "mid", "high"))
  d
}

crossed <- list(object = "item", facets = "rater",
                term_members = list(item = "item", rater = "rater"))
single <- list(object = "item", facets = character(),
               term_members = list(item = "item"))

cases <- list(
  list(key = "binary_logit_single_source", data = binary_panel(11, 10, 3, "logit"),
       outcomes = "y", families = list(family_spec("binary", "logit", c("0", "1"))),
       design = single, covariance = "diagonal", offset = 0.15, scale = 1.30, control = list()),
  list(key = "binary_probit_crossed", data = binary_panel(12, 10, 3, "probit"),
       outcomes = "y", families = list(family_spec("binary", "probit", c("0", "1"))),
       design = crossed, covariance = "diagonal", offset = -0.20, scale = 0.70, control = list()),
  list(key = "binary_logit_crossed_interior", data = binary_panel(13, 12, 3, "logit"),
       outcomes = "y", families = list(family_spec("binary", "logit", c("0", "1"))),
       design = crossed, covariance = "diagonal", offset = 0.35, scale = 1.75, control = list()),
  list(key = "ordinal_logit_crossed", data = ordinal_panel(21, 10, 3, "logit"),
       outcomes = "y",
       families = list(family_spec("ordinal", "logit", c("low", "mid", "high"))),
       design = crossed, covariance = "diagonal", offset = 0.10, scale = 1.15, control = list()),
  list(key = "ordinal_probit_crossed", data = ordinal_panel(22, 10, 3, "probit"),
       outcomes = "y",
       families = list(family_spec("ordinal", "probit", c("low", "mid", "high"))),
       design = crossed, covariance = "diagonal", offset = -0.25, scale = 0.85, control = list()),
  # A tail-weighted ordinal panel: the extreme categories carry most of the
  # mass, so threshold transforms and log-interval probabilities are exercised
  # where they are least stable.
  list(key = "ordinal_logit_tail_mass", data = local({
         set.seed(23)
         d <- expand.grid(item = seq_len(10), rater = seq_len(3))
         effect <- rnorm(10, sd = 1.4)
         u <- runif(nrow(d))
         lower <- plogis(-2.4 - effect[d$item]); upper <- plogis(2.4 - effect[d$item])
         d$y <- factor(ifelse(u < lower, "low", ifelse(u < upper, "mid", "high")),
                       levels = c("low", "mid", "high"))
         d }),
       outcomes = "y",
       families = list(family_spec("ordinal", "logit", c("low", "mid", "high"))),
       design = crossed, covariance = "diagonal", offset = 0.05, scale = 1.45, control = list()),
  # A source held at an exactly zero covariance coordinate. Its columns are
  # retained rather than dropped, which is the behaviour a sparse construction
  # must not quietly optimize away.
  list(key = "binary_logit_zero_source", data = binary_panel(14, 10, 3, "logit"),
       outcomes = "y", families = list(family_spec("binary", "logit", c("0", "1"))),
       design = crossed, covariance = "diagonal", offset = 0.12, scale = 1,
       control = list(fixed_covariance = list(item = matrix(0.5), rater = matrix(0))),
       fixed_covariance = TRUE),
  # Fixed covariance at ordinary interior values, so the covariance decode path
  # is frozen independently of any estimated coordinate.
  list(key = "binary_probit_fixed_covariance", data = binary_panel(15, 10, 3, "probit"),
       outcomes = "y", families = list(family_spec("binary", "probit", c("0", "1"))),
       design = crossed, covariance = "diagonal", offset = -0.18, scale = 1,
       control = list(fixed_covariance = list(item = matrix(0.6), rater = matrix(0.25))),
       fixed_covariance = TRUE))

# --- Evaluation ---------------------------------------------------------------
rows <- list()
record <- function(key, quantity, value, kind) {
  rows[[length(rows) + 1L]] <<- data.frame(case = key, quantity = quantity,
    value = if (is.logical(value)) as.integer(value) else as.numeric(value),
    kind = kind, stringsAsFactors = FALSE)
}

for (case in cases) {
  control <- .gt_d_control(case$control)
  prep <- .gt_d_prepare(case$data, case$outcomes, case$families)
  groups <- lapply(case$design$term_members, function(m) .gt_d_group(case$data, m))
  setup <- .gt_d_covariance_setup(groups, prep$q, case$covariance, control, prep$dimensions)
  fixed_length <- length(prep$start)
  # Declared, not fitted: a fixed offset on the mean/threshold coordinates and
  # a positive scale on the covariance coordinates. The scale is multiplicative
  # because a shared additive offset can drive a direct variance coordinate
  # negative, which would be an invalid evaluation point rather than a
  # demanding one. Recorded in full below, so the point itself is frozen.
  parameters <- c(prep$start + case$offset, setup$start * case$scale)
  factors <- .gt_d_covariance_factors(parameters[-seq_len(fixed_length)], setup)
  backend <- .gt_d_dense_backend(groups, factors, prep$n, prep$q)
  answer <- .gt_d_laplace(parameters, prep, groups, setup, control, details = TRUE)
  stopifnot(isTRUE(answer$valid))

  # Structure: exact integers a sparse construction must match outright.
  record(case$key, "n", prep$n, "exact")
  record(case$key, "q", prep$q, "exact")
  record(case$key, "random_dimension", answer$random_dimension, "exact")
  record(case$key, "parameter_count", length(parameters), "exact")
  record(case$key, "design_rows", nrow(backend$W), "exact")
  record(case$key, "design_columns", ncol(backend$W), "exact")
  record(case$key, "design_nonzeros", sum(backend$W != 0), "exact")
  record(case$key, "source_count", length(groups), "exact")

  # The evaluation point itself.
  for (i in seq_along(parameters))
    record(case$key, paste0("parameter_", i), parameters[[i]], "algebraic")
  for (name in names(factors)) {
    value <- factors[[name]]
    for (i in seq_along(value))
      record(case$key, paste0("covariance_", name, "_", i), value[[i]], "algebraic")
  }

  # Conditional problem at the returned mode.
  mode <- answer$mode
  eta <- answer$eta
  kernel <- .gt_d_response_kernel(eta, parameters, prep)
  stopifnot(isTRUE(kernel$valid))
  hessian <- .gt_d_dense_hessian(kernel$curvature, backend$W, prep$n)
  penalised_score <- as.numeric(crossprod(backend$W, kernel$gradient)) + mode
  eigenvalues <- eigen(hessian, symmetric = TRUE, only.values = TRUE)$values

  record(case$key, "conditional_objective", answer$conditional_nll, "objective")
  record(case$key, "marginal_laplace_nll", answer$nll, "objective")
  # The solver's marginal value is response nll + sum(u^2)/2 + sum(log(diag(R))),
  # while conditional_nll is the response term alone. Their difference is
  # therefore the mode penalty plus half the log determinant, not the log
  # determinant: record the two Laplace correction terms separately and check
  # the identity that relates them, rather than mislabelling their sum.
  record(case$key, "mode_penalty", sum(mode^2) / 2, "objective")
  record(case$key, "hessian_log_determinant", sum(log(eigenvalues)), "objective")
  record(case$key, "laplace_identity_residual",
         answer$nll - (answer$conditional_nll + sum(mode^2) / 2 + sum(log(eigenvalues)) / 2),
         "identity")
  record(case$key, "hessian_trace", sum(diag(hessian)), "objective")
  record(case$key, "hessian_min_eigenvalue", min(eigenvalues), "objective")

  # Coordinate-wise, not summarised. Two different implementations can share a
  # norm, a maximum and a trace while disagreeing everywhere underneath; only
  # elementwise targets make that disagreement fail. The fixtures are small
  # precisely so this is affordable.
  for (i in seq_along(eta)) record(case$key, paste0("eta_", i), eta[[i]], "mode")
  for (i in seq_along(mode)) record(case$key, paste0("mode_", i), mode[[i]], "mode")
  for (i in seq_along(penalised_score))
    record(case$key, paste0("score_", i), penalised_score[[i]], "stationary")
  # Symmetric, so the upper triangle determines it; symmetry itself is asserted
  # separately rather than stored twice.
  for (j in seq_len(ncol(hessian))) for (i in seq_len(j))
    record(case$key, paste0("hessian_", i, "_", j), hessian[[i, j]], "curvature")
  record(case$key, "hessian_asymmetry", max(abs(hessian - t(hessian))), "identity")
  record(case$key, "inner_gradient", answer$inner_gradient, "stationary")
  record(case$key, "inner_converged", isTRUE(answer$inner_converged), "exact")
}

discrete_reference_rows <- function() do.call(rbind, rows)

# --- Declared rejections ------------------------------------------------------
# A backend is not qualified by agreeing on calculations that succeed. These
# record what the dense implementation refuses, and how, so that a later
# implementation cannot turn a refusal into an answer. Each case reports an
# outcome class rather than a message, because messages are wording and the
# contract is behaviour.
discrete_reference_rejections <- function() {
  control <- .gt_d_control(list())
  data <- binary_panel(31, 10, 3, "logit")
  families <- list(family_spec("binary", "logit", c("0", "1")))
  prep <- .gt_d_prepare(data, "y", families)
  groups <- lapply(crossed$term_members, function(m) .gt_d_group(data, m))
  setup <- .gt_d_covariance_setup(groups, prep$q, "diagonal", control, prep$dimensions)
  parameters <- c(prep$start, setup$start)
  factors <- .gt_d_covariance_factors(parameters[-seq_along(prep$start)], setup)
  backend <- .gt_d_dense_backend(groups, factors, prep$n, prep$q)

  outcome <- function(expression) {
    result <- tryCatch(expression, error = function(e) structure("error", class = "gt_rejected"))
    if (inherits(result, "gt_rejected")) return("error")
    if (is.list(result) && isFALSE(result$valid)) return("invalid")
    if (is.numeric(result) && length(result) == 1L && result >= 1e100) return("penalty")
    if (is.list(result) && isFALSE(result$inner_converged)) return("not_converged")
    "value"
  }
  cases <- list(
    nonfinite_parameter = function() {
      bad <- parameters; bad[[1L]] <- NA_real_
      .gt_d_dense_mode(bad, prep, backend, control) },
    nonfinite_covariance_factor = function() {
      bad <- factors; bad[[1L]][1L, 1L] <- Inf
      .gt_d_dense_backend(groups, bad, prep$n, prep$q) },
    negative_direct_variance = function()
      .gt_d_covariance_factors(rep(-1, length(setup$start)), setup),
    mismatched_backend_dimensions = function()
      .gt_d_dense_backend(groups, factors, prep$n + 1L, prep$q),
    truncated_inner_solver = function() {
      tight <- control; tight$inner_maxit <- 1L; tight$inner_tol <- 1e-14
      .gt_d_dense_mode(parameters, prep, backend, tight, details = TRUE) },
    nonfinite_predictor = function()
      .gt_d_response_kernel(matrix(Inf, prep$n, prep$q), parameters, prep))
  data.frame(case = names(cases),
             outcome = vapply(names(cases), function(n) outcome(cases[[n]]()), character(1)),
             stringsAsFactors = FALSE, row.names = NULL)
}
