# Run from the project directory with Rscript tests/test_discrete.R.
source(file.path("R", "design.R"))
source(file.path("R", "discrete_response.R"))
source(file.path("R", "discrete_dense.R"))
source(file.path("R", "discrete_mode.R"))
# Sourced for the issue #14 localization replay only: an independently
# implemented matrix path that shares the response kernel with the dense one.
# Nothing in this file fits, dispatches to, or qualifies a sparse backend.
source(file.path("R", "discrete_sparse.R"))
source(file.path("R", "discrete_sparse_mode.R"))
source(file.path("R", "discrete.R"))
source(file.path("R", "diagnostics_stages.R"))

expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
}
close <- function(a, b, tolerance = 1e-5) stopifnot(max(abs(a - b)) < tolerance)
# Issue #14 evidence. The digest proves fixture identity without assuming the
# RNG reproduces across platforms, so "same fixture" is evidence not inference.
fixture_bytes <- function(...) {
  # Canonical bytes: fixed big-endian IEEE-754 and two's complement, with a
  # type and length delimiter per vector. Hashing a decimal rendering instead
  # makes the digest depend on format(), which is not portable across
  # platforms and reports a difference where the data is identical.
  path <- tempfile("gt-fixture-")
  on.exit(unlink(path), add = TRUE)
  # This file defines its own close() for numeric comparison, so the base
  # connection close must be named explicitly.
  connection <- file(path, "wb")
  tryCatch(for (value in list(...)) {
    # Refuse rather than coerce. as.integer() would silently hash a factor's
    # level codes or turn a character vector into NA, so an input mistake
    # would produce a confident digest of the wrong thing.
    if (!is.integer(value) && !is.double(value))
      stop("fixture_digest needs integer or double input; got ", class(value)[[1L]], ".")
    real <- is.double(value)
    writeBin(c(if (real) 2L else 1L, length(value)), connection, size = 4L, endian = "big")
    if (real) writeBin(value, connection, size = 8L, endian = "big")
    else writeBin(value, connection, size = 4L, endian = "big")
  }, finally = base::close(connection))
  readBin(path, "raw", file.size(path))
}
fixture_digest <- function(...) {
  bytes <- fixture_bytes(...)
  path <- tempfile("gt-digest-")
  on.exit(unlink(path), add = TRUE)
  writeBin(bytes, path)
  unname(tools::md5sum(path))
}
# A failing run must be self-contained: enough to tell a changed fixture from a
# different search path, and to replay the retained solution deterministically.
report_fit_evidence <- function(label, fit, digests) {
  cat(label, "\n", sep = "")
  dput(list(
    fixture_md5 = digests,
    rng_kind = RNGkind(),
    environment = list(
      r_version = R.version.string,
      openmx = as.character(utils::packageVersion("OpenMx")),
      matrix = tryCatch(as.character(utils::packageVersion("Matrix")),
                        error = function(e) NA_character_),
      blas = extSoftVersion()[["BLAS"]],
      lapack_library = La_library(),
      lapack_version = La_version(),
      threads = Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS",
                             "MKL_NUM_THREADS"))),
    result = list(
      covariance_components = fit$covariance_components,
      minus2loglik = fit$minus2loglik,
      parameters = fit$parameters,
      starting_parameters = fit$starting_parameters,
      optimizer_completed = fit$optimizer_completed,
      numerically_accepted = fit$numerically_accepted,
      acceptance_failures = fit$diagnostics$acceptance_failures),
    search = list(
      selected_attempt = fit$diagnostics$selected_attempt,
      optimization_trials = fit$diagnostics$optimization_trials,
      optimization_trial_budget = fit$diagnostics$optimization_trial_budget,
      attempts = lapply(fit$diagnostics$attempts, function(attempt) attempt[c(
        "label", "start", "parameters", "objective", "optimizer",
        "optimizer_code", "optimizer_message", "error", "warnings")]),
      stability = fit$diagnostics$stability),
    stationarity = fit$diagnostics$outer_stationarity,
    inner = fit$diagnostics[c("inner_converged", "inner_gradient",
                              "inner_iterations", "tight_final_mode")],
    bounds = fit$diagnostics[c("parameter_bounds", "boundary_sources",
                               "zero_variance_parameters")]))
}
family_spec <- function(family, link, levels, reference = NULL)
  list(family = family, link = link, levels = levels, reference = reference)
check_acceptance <- function(fit) {
  expected <- fit$optimizer_completed && fit$diagnostics$inner_converged &&
    fit$diagnostics$outer_stationarity$stationary_within_tolerance &&
    fit$diagnostics$stability$stable && !length(fit$diagnostics$parameter_bounds)
  stopifnot(identical(fit$converged, expected),
            identical(fit$numerically_accepted, expected))
  if (!expected) stopifnot(length(fit$diagnostics$acceptance_failures) > 0L)
}
# Golden vector: fixed input, fixed expected digest, independent of the RNG.
# Every supported platform therefore verifies the canonical encoding itself
# rather than only agreeing with its own earlier run, which is the property a
# cross-run fixture comparison depends on.
# Every value is exactly representable in binary, so the literals convert
# identically everywhere and the vector tests the encoding rather than the
# platform's decimal parser. Magnitude is irrelevant here: the encoding writes
# eight bytes whatever the exponent.
golden_input <- list(c(1L, -2L, 0L), c(0.5, -0.5, 0, 0.25, -1024))
# Printed on every run. If a platform disagrees with the expected digest, its
# own bytes are in the log and the difference is diagnosable without a second
# run on hardware that is not available locally.
cat("fixture encoding: ", paste(do.call(fixture_bytes, golden_input), collapse = ""), "\n", sep = "")
stopifnot(identical(do.call(fixture_digest, golden_input),
                    "e23350c5f0f3418e4886dfef21a24574"))
# Unsupported input is refused, never coerced into a confident wrong digest.
for (unsupported in list(factor("a"), "a", TRUE, list(1)))
  expect_error(fixture_digest(unsupported), "integer or double")

design <- list(object = "item", facets = "rater",
               term_members = list(item = "item", rater = "rater"))

# The integer-tuple encoding must distinguish labels containing separators.
g <- data.frame(a = c("a:b", "a", "a:b"), b = c("c", "b:c", "c"))
stopifnot(identical(.gt_d_group(g, c("a", "b"))$index, c(1L, 2L, 1L)))

# Analytic observation derivatives are checked against finite differences.
# The dense Hessian from W=I includes I from the standardized random prior.
check_derivatives <- function(data, outcomes, families, offsets) {
  prep <- .gt_d_prepare(data, outcomes, families)
  eta <- matrix(offsets, prep$n, prep$q)
  at <- .gt_d_response(eta, prep$start, prep, diag(length(offsets)))
  stopifnot(at$valid)
  epsilon <- 1e-5
  gradient <- numeric(length(offsets))
  H <- matrix(0, length(offsets), length(offsets))
  for (j in seq_along(offsets)) {
    plus <- minus <- eta
    plus[j] <- plus[j] + epsilon
    minus[j] <- minus[j] - epsilon
    a <- .gt_d_response(plus, prep$start, prep)
    b <- .gt_d_response(minus, prep$start, prep)
    gradient[j] <- (a$nll - b$nll) / (2 * epsilon)
    H[, j] <- (a$gradient - b$gradient) / (2 * epsilon)
  }
  close(at$gradient, gradient)
  close(at$H - diag(length(offsets)), H)
}
for (link in c("probit", "logit")) {
  check_derivatives(data.frame(y = c(0, 1, 0, 1)), "y",
                    list(family_spec("binary", link, c("0", "1"))), c(-2, .3, 1, 3))
  check_derivatives(data.frame(y = ordered(c("a", "b", "c", "b"), levels = c("a", "b", "c"))), "y",
                    list(family_spec("ordinal", link, c("a", "b", "c"))), c(-2, .3, 1, 3))
}
check_derivatives(data.frame(y = factor(c("a", "b", "c", "b"))), "y",
                  list(family_spec("categorical", "softmax", c("a", "b", "c"), "a")),
                  c(-2, .3, 1, 3, 0, -.4, .8, -1))

# Probit and ordered-probit tails remain finite beyond ordinary probability
# underflow. The likelihood must not be clipped to an arbitrary epsilon.
bp <- .gt_d_prepare(data.frame(y = c(0, 1)), "y",
                     list(family_spec("binary", "probit", c("0", "1"))))
tail <- .gt_d_response(matrix(c(40, -40), 2L), bp$start, bp)
stopifnot(tail$valid, tail$nll > 1500, all(is.finite(tail$gradient)))
close(.gt_d_log_interval(c(-41, 40), c(-40, 41), "probit"),
      rep(stats::pnorm(-40, log.p = TRUE), 2), 1e-8)

# At zero random covariance the marginal likelihood must reduce exactly to
# independent Bernoulli / ordinal / multinomial likelihoods.
set.seed(1402)
d <- expand.grid(item = seq_len(16), rater = seq_len(4), rep = seq_len(2))
d$binary <- rbinom(nrow(d), 1, .37)
d$ordinal <- ordered(sample(c("low", "mid", "high"), nrow(d), replace = TRUE,
                             prob = c(.25, .45, .30)), levels = c("low", "mid", "high"))
d$nominal <- factor(sample(c("red", "blue", "green"), nrow(d), replace = TRUE,
                            prob = c(.2, .5, .3)), levels = c("red", "blue", "green"))
zero1 <- list(item = matrix(0, 1, 1), rater = matrix(0, 1, 1))
zero2 <- list(item = matrix(0, 2, 2), rater = matrix(0, 2, 2))
binary_family <- list(family_spec("binary", "logit", c("0", "1")))
b0 <- .gt_fit_discrete(d, "binary", design, binary_family,
                        control = list(fixed_covariance = zero1))
glm0 <- glm(binary ~ 1, data = d, family = binomial())
close(b0$minus2loglik, as.numeric(-2 * logLik(glm0)), 1e-6)
close(b0$means, unname(coef(glm0)), 1e-6)
o0 <- .gt_fit_discrete(d, "ordinal", design,
                        list(family_spec("ordinal", "probit", levels(d$ordinal))),
                        control = list(fixed_covariance = zero1))
freq <- table(d$ordinal)
close(o0$minus2loglik, -2 * sum(freq * log(freq / sum(freq))), 1e-6)
stopifnot(all(diff(o0$thresholds$ordinal) > 0), identical(o0$means[[1L]], 0))
m0 <- .gt_fit_discrete(d, "nominal", design,
                        list(family_spec("categorical", "softmax", levels(d$nominal), "blue")),
                        control = list(fixed_covariance = zero2))
freq <- table(d$nominal)
close(m0$minus2loglik, -2 * sum(freq * log(freq / sum(freq))), 1e-6)
close(rowSums(m0$conditional_probabilities$nominal), rep(1, nrow(d)), 1e-12)
stopifnot(identical(colnames(m0$conditional_probabilities$nominal), c("blue", "red", "green")),
          all(is.na(m0$latent_residual_variances)))

# A two-category multinomial likelihood is identical to binary logistic. The
# public API distinguishes these families, but this engine identity checks the
# reference-category implementation without numeric scoring or one-vs-rest fits.
d$two <- factor(ifelse(d$binary == 1, "yes", "no"), levels = c("no", "yes"))
two <- .gt_fit_discrete(d, "two", design,
                         list(family_spec("categorical", "softmax", c("no", "yes"), "no")),
                         control = list(fixed_covariance = zero1))
close(two$minus2loglik, b0$minus2loglik, 1e-7)
close(two$means, b0$means, 1e-6)

# Joint outcome likelihood with fixed zero covariance equals the product of
# its constituent likelihoods; q-by-q components are retained, not separate fits.
joint0 <- .gt_fit_discrete(d, c("binary", "ordinal"), design,
                            c(binary_family, list(family_spec("ordinal", "probit", levels(d$ordinal)))),
                            control = list(fixed_covariance = zero2))
close(joint0$minus2loglik, b0$minus2loglik + o0$minus2loglik, 1e-6)
stopifnot(identical(dim(joint0$covariance_components$item), c(2L, 2L)),
          identical(colnames(joint0$covariance_components$item), c("binary", "ordinal")))

# Actual estimated random effects are benchmarked against mature Laplace
# implementations when present. These checks compare the objective and the
# estimated variance, not merely the return-value structure.
set.seed(912)
sim <- expand.grid(item = seq_len(24), rater = seq_len(4), rep = seq_len(3))
u <- rnorm(24, sd = .9)
v <- c(-.5, -.1, .1, .5)
eta <- -.2 + u[sim$item] + v[sim$rater]
sim$y <- rbinom(nrow(sim), 1, plogis(eta))
bfit <- .gt_fit_discrete(sim, "y", design, binary_family,
                          control = list(maxit = 200L))
stopifnot(bfit$converged, bfit$diagnostics$inner_converged,
          bfit$covariance_components$item[[1L]] > .01)
if (requireNamespace("lme4", quietly = TRUE)) {
  benchmark <- lme4::glmer(y ~ 1 + (1 | item) + (1 | rater), data = sim,
                            family = binomial(), nAGQ = 1,
                            control = lme4::glmerControl(optimizer = "bobyqa"))
  close(bfit$minus2loglik, as.numeric(-2 * logLik(benchmark)), .005)
  close(bfit$means, lme4::fixef(benchmark), .005)
  close(bfit$covariance_components$item[[1L]], as.numeric(lme4::VarCorr(benchmark)$item), .01)
} else cat("SKIP: lme4 independent binary Laplace comparison (required by the full-validation runner).\n")

# Ordinal random effects retain threshold ordering and agree with clmm's
# Laplace marginal likelihood on the same cumulative-probit model.
sim$ordered <- cut(eta + rnorm(nrow(sim)), c(-Inf, -.4, .7, Inf),
                    labels = c("low", "mid", "high"), ordered_result = TRUE)
ofit <- .gt_fit_discrete(sim, "ordered", design,
                          list(family_spec("ordinal", "probit", levels(sim$ordered))),
                          control = list(maxit = 200L))
check_acceptance(ofit)
stopifnot(ofit$optimizer_completed, all(diff(ofit$thresholds$ordered) > 0))
if (requireNamespace("ordinal", quietly = TRUE)) {
  benchmark <- ordinal::clmm(ordered ~ 1 + (1 | item) + (1 | rater), data = sim,
                              link = "probit", nAGQ = 1,
                              control = ordinal::clmm.control(maxIter = 100))
  close(ofit$minus2loglik, as.numeric(-2 * logLik(benchmark)), .02)
  close(ofit$thresholds$ordered, benchmark$alpha, .02)
} else cat("SKIP: ordinal independent cumulative-probit Laplace comparison (required by the full-validation runner).\n")

# Fit a genuinely joint nominal random-effects model. Probabilities sum to one
# and source matrices are positive semidefinite over both category contrasts.
set.seed(901)
small <- expand.grid(item = seq_len(12), rater = seq_len(3), rep = seq_len(3))
u <- matrix(rnorm(24, sd = .6), 12, 2)
e <- cbind(.3 + u[small$item, 1], -.4 + u[small$item, 2])
p <- cbind(1, exp(e)); p <- p / rowSums(p)
small$y <- factor(vapply(seq_len(nrow(small)), function(i)
  sample(c("a", "b", "c"), 1, prob = p[i, ]), character(1)), levels = c("a", "b", "c"))
mfit <- .gt_fit_discrete(small, "y", design,
                          list(family_spec("categorical", "softmax", c("a", "b", "c"), "a")),
                          covariance = "diagonal", control = list(maxit = 200L))
check_acceptance(mfit)
stopifnot(mfit$optimizer_completed, all(vapply(mfit$covariance_components,
  function(S) min(eigen(S, symmetric = TRUE, only.values = TRUE)$values) >= -1e-10, logical(1))))
close(rowSums(mfit$conditional_probabilities$y), rep(1, nrow(small)), 1e-12)

# An estimated bivariate binary fit must learn covariance from shared source
# effects. Positive dependence is generated at the object level only.
set.seed(223)
pair <- expand.grid(item = seq_len(18), rater = seq_len(3), rep = seq_len(3))
shared <- rnorm(18, sd = 1.1)
pair$a <- rbinom(nrow(pair), 1, pnorm(-.3 + shared[pair$item]))
pair$b <- rbinom(nrow(pair), 1, pnorm(.2 + .8 * shared[pair$item]))
# Two digests: the panel is what the optimizer actually saw, so it alone
# proves two runs were given the same problem. The latent draws are generation
# input only and are separated so a generator change is distinguishable.
joint_digest <- c(panel = fixture_digest(pair$item, pair$rater, pair$rep, pair$a, pair$b),
                  latent = fixture_digest(shared))
# Printed on every run: a failing digest is only interpretable against the
# digest a passing run reported.
cat("Joint binary covariance fixture md5: panel=", joint_digest[["panel"]],
    " latent=", joint_digest[["latent"]], "\n", sep = "")
jfit <- .gt_fit_discrete(pair, c("a", "b"), design,
                          rep(list(family_spec("binary", "probit", c("0", "1"))), 2),
                          covariance = "unstructured", control = list(maxit = 200L))
# --- Issue #14 localization (test-only) ---------------------------------------
# Runs after the fit above has finished and before the assertion below, so the
# fit it describes is the one that may be about to fail, and the evidence is
# retained whether or not it does. The fit itself is untouched: nothing here
# feeds back into jfit, its controls, or its result.
#
# The question this answers is which layer a divergence enters at. A failing
# run alone cannot say whether the panel, the starting point, the shared
# response kernel, the matrix algebra or the conditional solve is responsible,
# and every one of those has a different fix. Each checkpoint below is
# reported on every run, because a failing value is only interpretable against
# the value a passing run reported.
#
# The sparse engine is used here as an independently implemented witness for
# the matrix algebra only. It shares the response kernel with the dense path,
# so agreement between them isolates the kernel from the linear algebra
# rather than confirming either. This is a fixed-parameter replay; no sparse
# fitting happens and no backend is selected.
localize_joint_divergence <- function(fit, digests) {
  control <- .gt_d_control(list(maxit = 200L))
  families <- rep(list(family_spec("binary", "probit", c("0", "1"))), 2)
  prep <- .gt_d_prepare(pair, c("a", "b"), families)
  groups <- lapply(design$term_members, function(members) .gt_d_group(pair, members))
  setup <- .gt_d_covariance_setup(groups, prep$q, "unstructured", control, prep$dimensions)
  start <- c(prep$start, setup$start)
  factors <- .gt_d_covariance_factors(start[-seq_along(prep$start)], setup)
  dense_backend <- .gt_d_dense_backend(groups, factors, prep$n, prep$q)
  sparse_backend <- .gt_d_sparse_backend(groups, factors, prep$n, prep$q)

  # Does the reconstruction describe the same starting point the fit used? If
  # not, everything below describes a different problem and says so.
  retained <- fit$starting_parameters
  reconstruction <- list(
    reconstructed_start = start,
    retained_start = retained,
    starts_agree = isTRUE(length(retained) == length(start)) &&
      isTRUE(max(abs(unname(retained) - unname(start))) < 1e-12),
    start_difference = if (length(retained) == length(start))
      max(abs(unname(retained) - unname(start))) else NA_real_)

  # Identity of the replayed problem, on every run.
  identity <- list(
    panel = digests[["panel"]], latent = digests[["latent"]],
    start = fixture_digest(start),
    covariance_factors = fixture_digest(unlist(lapply(factors, as.numeric), use.names = FALSE)),
    dense_design = fixture_digest(as.numeric(dense_backend$W)),
    sparse_stored = sparse_backend$stored_entries,
    random_dimension = sparse_backend$random_dimension)

  # The shared response kernel at u = 0, before any factorization. Both engines
  # call this same function, so a difference here is upstream of the algebra.
  baseline <- .gt_d_baseline(start, prep)
  kernel <- .gt_d_response_kernel(baseline, start, prep)
  curvature_values <- unlist(lapply(kernel$curvature, `[[`, "diagonal"), use.names = FALSE)
  shared_kernel <- if (!isTRUE(kernel$valid)) list(valid = FALSE) else list(
    valid = TRUE, nll = kernel$nll,
    eta = fixture_digest(as.numeric(baseline)),
    gradient = fixture_digest(kernel$gradient),
    curvature = fixture_digest(curvature_values),
    max_abs_gradient = max(abs(kernel$gradient)),
    min_curvature = min(curvature_values), max_curvature = max(curvature_values))

  # The first Newton step through both matrix paths, at u = 0.
  first_step <- if (!isTRUE(kernel$valid)) list(valid = FALSE) else {
    zero <- numeric(ncol(dense_backend$W))
    dense_score <- as.vector(crossprod(dense_backend$W, kernel$gradient)) + zero
    sparse_score <- as.numeric(Matrix::crossprod(sparse_backend$W, kernel$gradient)) + zero
    dense_H <- .gt_d_dense_hessian(kernel$curvature, dense_backend$W, prep$n)
    sparse_H <- .gt_d_sparse_hessian(kernel$curvature, sparse_backend$W, prep$n)
    dense_R <- tryCatch(chol(dense_H), error = function(e) NULL)
    sparse_factor <- tryCatch(.gt_d_sparse_factor(sparse_H), error = function(e) NULL)
    dense_step <- if (is.null(dense_R)) NULL else
      backsolve(dense_R, forwardsolve(t(dense_R), dense_score))
    sparse_step <- if (is.null(sparse_factor)) NULL else
      .gt_d_sparse_solve(sparse_factor, sparse_score)
    list(valid = TRUE,
         dense_score = fixture_digest(dense_score),
         sparse_score = fixture_digest(sparse_score),
         score_difference = max(abs(dense_score - sparse_score)),
         hessian_difference = max(abs(dense_H - as.matrix(sparse_H))),
         dense_factorized = !is.null(dense_R), sparse_factorized = !is.null(sparse_factor),
         dense_logdet = if (is.null(dense_R)) NA_real_ else 2 * sum(log(diag(dense_R))),
         sparse_logdet = if (is.null(sparse_factor)) NA_real_ else
           .gt_d_sparse_logdet(sparse_factor),
         step_difference = if (is.null(dense_step) || is.null(sparse_step)) NA_real_ else
           max(abs(dense_step - sparse_step)),
         max_abs_dense_step = if (is.null(dense_step)) NA_real_ else max(abs(dense_step)))
  }

  # The complete fixed-parameter conditional solve through both engines, at the
  # ordinary inner tolerance and at the tightened one the retained attempt used.
  #
  # Read the digests across runs of the same engine, never across the two
  # engines. They hash exact bytes, so a last-bit difference changes them
  # completely: dense and sparse routinely report different mode digests while
  # agreeing to 2e-16. Engine agreement is the numeric difference reported
  # under agreement, not digest equality.
  summarise <- function(answer) {
    if (!is.list(answer) || !isTRUE(answer$valid))
      return(list(valid = FALSE,
                  inner_converged = if (is.list(answer)) answer$inner_converged else NA,
                  inner_gradient = if (is.list(answer)) answer$inner_gradient else NA_real_))
    list(valid = TRUE, nll = answer$nll, conditional_nll = answer$conditional_nll,
         mode_penalty = sum(answer$mode^2) / 2,
         inner_iterations = answer$inner_iterations,
         inner_gradient = answer$inner_gradient,
         inner_converged = answer$inner_converged,
         mode = fixture_digest(answer$mode), eta = fixture_digest(as.numeric(answer$eta)),
         max_abs_mode = max(abs(answer$mode)))
  }
  tolerances <- list(ordinary = control$inner_tol,
                     tightened = min(control$inner_tol, control$validation_inner_tol))
  replay <- lapply(tolerances, function(tolerance) {
    at <- control
    at$inner_tol <- tolerance
    dense <- .gt_d_dense_mode(start, prep, dense_backend, at, details = TRUE)
    sparse <- .gt_d_sparse_mode(start, prep, sparse_backend, at, details = TRUE)
    agreement <- if (isTRUE(dense$valid) && isTRUE(sparse$valid)) list(
      mode_difference = max(abs(dense$mode - sparse$mode)),
      objective_difference = abs(dense$nll - sparse$nll),
      iterations_agree = identical(dense$inner_iterations, sparse$inner_iterations))
      else list(mode_difference = NA_real_, objective_difference = NA_real_,
                iterations_agree = NA)
    list(inner_tol = tolerance, dense = summarise(dense), sparse = summarise(sparse),
         agreement = agreement,
         dense_hit_budget = isTRUE(dense$inner_iterations >= at$inner_maxit))
  })

  # Only when the dense replay looks pathological: it exhausted its budget,
  # returned invalid, or failed to converge. A budget hit alone is too narrow a
  # trigger, because an invalid replay reports no iteration count and would
  # silently skip the ladder in exactly the case worth laddering.
  #
  # This is diagnostic evidence about why a platform needs more steps. It is
  # not a proposal to raise inner_maxit, and jfit's own control is untouched.
  #
  # Each ladder keeps the inner tolerance of the replay that triggered it. The
  # captured #14 failure exhausted its budget on the tight final mode, at 60
  # iterations with a gradient of 8.95e-09 and tight_final_mode TRUE, so the
  # question worth spending a rare specimen on is whether 120 or 240 iterations
  # reach the healthy mode at that tolerance. Rebuilding the control from the
  # default would ladder at 1e-07 instead and answer a question nobody asked.
  # inner_tol is reported in every entry so the log says which solve it
  # describes rather than leaving it to be inferred.
  pathological <- function(r) isTRUE(r$dense_hit_budget) ||
    !isTRUE(r$dense$valid) || !isTRUE(r$dense$inner_converged)
  triggered <- names(replay)[vapply(replay, pathological, logical(1))]
  ladder <- NULL
  if (length(triggered)) {
    ladder <- stats::setNames(lapply(triggered, function(label) {
      tolerance <- replay[[label]]$inner_tol
      lapply(c(60L, 120L, 240L), function(budget) {
        at <- control
        at$inner_tol <- tolerance
        at$inner_maxit <- budget
        c(list(replay = label, inner_tol = tolerance, inner_maxit = budget),
          summarise(.gt_d_dense_mode(start, prep, dense_backend, at, details = TRUE)))
      })
    }), triggered)
  }

  list(reconstruction = reconstruction, identity = identity,
       shared_kernel = shared_kernel, first_step = first_step,
       fixed_parameter_replay = replay, budget_ladder = ladder)
}
# Diagnostics must not decide the test. A failure inside the replay is reported
# and swallowed, so the assertion below still judges the fit rather than being
# pre-empted by an error in the instrument that was meant to explain it.
cat("Joint binary covariance localization (issue #14):\n")
dput(tryCatch(localize_joint_divergence(jfit, joint_digest),
              error = function(e) list(localization_error = conditionMessage(e))))

# Identical source has produced both passing and failing results here. Retain
# evidence on failure; the assertion below is deliberately left unweakened.
if (!isTRUE(jfit$optimizer_completed) ||
    !isTRUE(jfit$covariance_components$item[1, 2] > .2) ||
    !isTRUE(all(vapply(jfit$covariance_components,
      function(S) min(eigen(S, symmetric = TRUE, only.values = TRUE)$values) > -1e-10,
      logical(1))))) {
  report_fit_evidence("Joint binary covariance fixture failure diagnostics (issue #14):",
                      jfit, joint_digest)
}
check_acceptance(jfit)
stopifnot(jfit$optimizer_completed, jfit$covariance_components$item[1, 2] > .2,
          all(vapply(jfit$covariance_components,
            function(S) min(eigen(S, symmetric = TRUE, only.values = TRUE)$values) > -1e-10, logical(1))))

# Malformed and unsupported inputs fail explicitly before estimation.
expect_error(.gt_fit_discrete(d, "binary", design, binary_family,
                               control = list(max_random_dimension = 2)), "max_random_dimension")
expect_error(.gt_fit_discrete(d, "binary", design, binary_family,
                               control = list(max_observations = 2)), "max_observations")
expect_error(.gt_fit_discrete(d, "binary", design, binary_family,
                               control = list(fixed_covariance = list(item = matrix(-1), rater = matrix(0)))),
             "positive semidefinite")
expect_error(.gt_fit_discrete(d, "ordinal", design,
                               list(family_spec("ordinal", "probit", c("low", "mid", "high", "empty")))),
             "empty categories")
expect_error(.gt_fit_discrete(d, "nominal", design,
                               list(family_spec("categorical", "logit", levels(d$nominal)))), "Unsupported link")
expect_error(.gt_fit_discrete(d, "binary", design, binary_family,
                               control = list(typo = 1)), "Unknown discrete control")
one <- d; one$binary <- 0
expect_error(.gt_fit_discrete(one, "binary", design, binary_family), "Both binary")
alias <- d; alias$rater <- alias$item
expect_error(.gt_fit_discrete(alias, "binary", design, binary_family), "linearly dependent")
# Repeated grouping kernels can jointly span the observation identity even
# though no single source is observation-specific and the sources are mutually
# independent. This creates a latent scale alias for a probit response.
identity_panel <- data.frame(item = c(1, 1, 2, 3), A = c(1, 2, 1, 3),
                              B = c(1, 2, 2, 3), C = c(1, 1, 1, 2),
                              y = c(0, 1, 0, 1))
identity_design <- list(object = "item", facets = c("A", "B", "C"),
                         term_members = list(item = "item", A = "A", B = "B", C = "C"))
identity_groups <- lapply(identity_design$term_members,
                           function(members) .gt_d_group(identity_panel, members))
K <- lapply(identity_panel[names(identity_design$term_members)], function(x) outer(x, x, `==`) * 1)
close(K$item + K$A + K$B - K$C, 2 * diag(nrow(identity_panel)), 1e-12)
stopifnot(.gt_d_kernel_rank(identity_groups)$rank == 4L)
expect_error(.gt_fit_discrete(identity_panel, "y", identity_design,
                              list(family_spec("binary", "probit", c("0", "1")))),
             "span an observation-specific component")
# Fixed matrices remove the unidentified covariance-estimation problem. They
# remain a valid exact-zero-variance baseline and must retain the rank metadata.
fixed_identity <- setNames(rep(list(matrix(0, 1, 1)), 4L), names(identity_design$term_members))
identity_fixed_fit <- .gt_fit_discrete(identity_panel, "y", identity_design,
                                       list(family_spec("binary", "probit", c("0", "1"))),
                                       control = list(fixed_covariance = fixed_identity))
close(identity_fixed_fit$minus2loglik, 2 * nrow(identity_panel) * log(2), 1e-10)
stopifnot(identity_fixed_fit$converged,
          identity_fixed_fit$diagnostics$source_kernel_rank$rank == 4L,
          identity_fixed_fit$diagnostics$source_residual_kernel_rank$rank == 4L,
          identity_fixed_fit$diagnostics$source_residual_kernel_rank$n_kernels == 5L,
          identity_fixed_fit$diagnostics$source_residual_kernel_rank$n_random_sources == 4L,
          identity_fixed_fit$diagnostics$source_residual_kernel_rank$includes_observation_identity,
          identical(identity_fixed_fit$diagnostics$source_covariances_estimated, FALSE),
          grepl("not enforced", identity_fixed_fit$design$validation_scope, fixed = TRUE))
cat("Discrete function checks passed: derivatives, exact zero-variance likelihoods, joint endpoints, multinomial reference contrasts, external Laplace benchmarks, and validation.\n")
