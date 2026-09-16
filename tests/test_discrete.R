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
# Hosted-runner provenance. The job log records the architecture and nothing
# else, and "x86_64" does not distinguish the microarchitectures a tuned BLAS
# dispatches different kernels for, which is one of the few remaining
# differences between a runner that reproduces issue #14 and one that does
# not. Read on every run, because a failing runner's model is only
# interpretable against the models passing runs reported. Every lookup is
# guarded and reports NA rather than failing: this is provenance, and a
# platform that cannot answer must not take the test down with it.
platform_provenance <- function() {
  info <- tryCatch(if (file.exists("/proc/cpuinfo"))
    readLines("/proc/cpuinfo", warn = FALSE) else character(0),
    error = function(e) character(0))
  field <- function(pattern) {
    hit <- grep(pattern, info, value = TRUE)
    if (!length(hit)) NA_character_ else trimws(sub("^[^:]*:[[:space:]]*", "", hit[[1L]]))
  }
  model <- field("^model name")
  if (is.na(model) && nzchar(Sys.which("sysctl")))
    model <- tryCatch(suppressWarnings(
      system2("sysctl", c("-n", "machdep.cpu.brand_string"), stdout = TRUE, stderr = FALSE))[[1L]],
      error = function(e) NA_character_)
  flags <- field("^flags")
  list(
    cpu_model = if (length(model) == 1L && !is.na(model) && nzchar(model)) model else NA_character_,
    cpu_family = field("^cpu family"), cpu_stepping = field("^stepping"),
    cpu_microcode = field("^microcode"),
    logical_processors = if (length(info)) length(grep("^processor", info)) else NA_integer_,
    # Only the families that decide which kernel a BLAS selects. The full flag
    # line is hundreds of tokens, none of the rest changes an arithmetic
    # result, and printing it on every run buries the part that does.
    dispatch_flags = if (is.na(flags)) NA_character_ else paste(intersect(
      c("sse4_2", "avx", "avx2", "fma", "avx512f", "avx512dq", "avx512bw", "avx512vl"),
      strsplit(flags, "[[:space:]]+")[[1L]]), collapse = " "),
    platform = R.version$platform, os = Sys.info()[["sysname"]],
    r_version = R.version.string,
    matrix_version = tryCatch(as.character(utils::packageVersion("Matrix")),
                              error = function(e) NA_character_),
    blas = tryCatch(extSoftVersion()[["BLAS"]], error = function(e) NA_character_),
    lapack_library = tryCatch(La_library(), error = function(e) NA_character_),
    lapack_version = tryCatch(La_version(), error = function(e) NA_character_),
    threads = Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS")),
    run = Sys.getenv(c("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_JOB",
                       "GITHUB_SHA", "GITHUB_EVENT_NAME", "RUNNER_NAME", "RUNNER_ARCH")))
}

# Retain the failure specimen.
#
# The measurements it records run unconditionally; only this dump is
# conditional, and only because it is the one bulky part. The recurrence is
# rare, so the next one has to leave behind the exact numbers rather than a
# formatted summary of them: the matrices, right-hand sides, starting point
# and curvature, as numeric objects that can be re-loaded and replayed.
#
# The trigger is deliberately backend-neutral and wide. Retaining on "dense
# and sparse disagree" would write the hypothesis under investigation into the
# evidence meant to test it, and the first condition below already fires
# whenever the assertion fails, so the specimen cannot be missed even if every
# numerical trigger turns out to be badly calibrated.
#
# These bounds are retention triggers, not acceptance criteria. Nothing in the
# test is judged against them, and they are loose by design: a well
# conditioned 42-dimensional matrix reconstructs and solves to about 1e-15
# here, so anything at 1e-8 is a signal and not a tolerance question.
ISSUE14_RESIDUAL_TRIGGER <- 1e-8
ISSUE14_LOGDET_TRIGGER <- 1e-9
ISSUE14_STEP_TRIGGER <- 1e-8
retain_joint_specimen <- function(localization, assertion_failed, fit, digests) {
  evidence <- localization$evidence
  reasons <- character(0)
  note <- function(condition, reason) if (isTRUE(condition)) reasons <<- c(reasons, reason)
  exceeds <- function(x, bound) any(!is.finite(x)) || any(x > bound, na.rm = TRUE)

  note(assertion_failed, "fitted_assertion_failed")
  note(is.null(evidence), "localization_unavailable")
  crossed <- evidence$cross_factorization
  if (is.list(crossed) && isTRUE(crossed$valid)) {
    note(!all(vapply(crossed$combinations, function(x) isTRUE(x$factorized), logical(1))),
         "factorization_failed")
    for (measure in c("solve_residual", "blas_free_solve_residual",
                      "reconstruction_residual", "blas_free_reconstruction_residual")) {
      values <- vapply(crossed$combinations, function(x) x[[measure]], numeric(1))
      # A measure no combination reports at all is absent by construction, not
      # anomalous: CHOLMOD exposes no plain factor to reconstruct without BLAS.
      # An all-NA vector must not make every run retain a specimen.
      if (any(is.finite(values))) note(exceeds(values[!is.na(values)],
                                               ISSUE14_RESIDUAL_TRIGGER), measure)
    }
    note(exceeds(stats::na.omit(vapply(crossed$combinations,
                                       function(x) x$blas_gram_difference, numeric(1))),
                 ISSUE14_RESIDUAL_TRIGGER), "blas_gram_difference")
    for (pair in c("factorizer_on_dense_assembly", "factorizer_on_sparse_assembly",
                   "assembly_under_base_chol", "assembly_under_cholmod")) {
      note(exceeds(crossed$comparisons[[pair]]$logdet, ISSUE14_LOGDET_TRIGGER),
           paste0("logdet_gap:", pair))
      note(exceeds(crossed$comparisons[[pair]]$step, ISSUE14_STEP_TRIGGER),
           paste0("step_gap:", pair))
    }
    note(exceeds(crossed$comparisons$logdet_versus_eigen, ISSUE14_LOGDET_TRIGGER),
         "logdet_versus_eigen")
    note(exceeds(crossed$comparisons$step_versus_lu, ISSUE14_STEP_TRIGGER), "step_versus_lu")
  } else note(TRUE, "cross_factorization_unavailable")
  for (label in names(evidence$fixed_parameter_replay)) {
    entry <- evidence$fixed_parameter_replay[[label]]
    note(!isTRUE(entry$dense$valid) || !isTRUE(entry$sparse$valid),
         paste0("invalid_replay:", label))
    note(isTRUE(entry$dense_hit_budget), paste0("dense_budget:", label))
    note(!isTRUE(entry$dense$inner_converged) || !isTRUE(entry$sparse$inner_converged),
         paste0("inner_not_converged:", label))
  }
  note(!is.null(evidence$budget_ladder), "budget_ladder_fired")
  note(!isTRUE(evidence$reconstruction$starts_agree), "start_mismatch")

  cat("Issue #14 specimen retention: triggers=",
      if (length(reasons)) paste(reasons, collapse = ",") else "none", "\n", sep = "")
  if (!length(reasons)) return(invisible(NULL))
  # Never the working tree: the validation job asserts that running the tests
  # changes no tracked file, and a specimen written into the repository would
  # fail that gate instead of the assertion it was collected for. The job
  # points this at a directory its upload step reaches.
  configured <- Sys.getenv("GTHEORY_ISSUE14_ARTIFACT_DIR", "")
  directory <- if (nzchar(configured)) configured else file.path(tempdir(), "gtheory-issue14")
  dir.create(directory, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(directory, "issue14-factor-specimen.rds")
  specimen <- localization$specimen
  saveRDS(list(
    schema = "gtheory-issue14-factor-specimen/1",
    triggers = reasons, assertion_failed = assertion_failed,
    fixture_md5 = digests, evidence = evidence,
    # Raw numeric objects, not formatted text. A specimen is worth keeping
    # because it can be re-loaded and replayed exactly; a rendering of it to
    # fifteen digits cannot be.
    panel = if (is.null(specimen)) NULL else specimen$panel,
    start = if (is.null(specimen)) NULL else specimen$start,
    curvature = if (is.null(specimen)) NULL else specimen$curvature,
    gradient = if (is.null(specimen)) NULL else specimen$gradient,
    eta = if (is.null(specimen)) NULL else specimen$eta,
    dense_score = if (is.null(specimen)) NULL else specimen$newton$dense_score,
    sparse_score = if (is.null(specimen)) NULL else specimen$newton$sparse_score,
    dense_hessian = if (is.null(specimen)) NULL else specimen$newton$dense_H,
    # Both the plain numeric copy and the sparse object: the numbers stay
    # readable without Matrix installed, and the storage object is itself part
    # of what a factorization difference could be about.
    sparse_hessian_dense = if (is.null(specimen)) NULL else as.matrix(specimen$newton$sparse_H),
    sparse_hessian = if (is.null(specimen)) NULL else specimen$newton$sparse_H,
    covariance_factors = if (is.null(specimen)) NULL else specimen$factors,
    fit = list(parameters = fit$parameters, starting_parameters = fit$starting_parameters,
               covariance_components = fit$covariance_components,
               minus2loglik = fit$minus2loglik,
               optimizer_completed = fit$optimizer_completed,
               numerically_accepted = fit$numerically_accepted,
               acceptance_failures = fit$diagnostics$acceptance_failures),
    provenance = platform_provenance(), session = utils::sessionInfo()), path)
  cat("Issue #14 specimen written: ", path, " (", file.size(path), " bytes)\n", sep = "")
  invisible(path)
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

  # The exact matrices and right-hand sides at u = 0, assembled once. Every
  # block below reads these same objects, so the paired first step, the
  # cross-factorization witness and any retained specimen describe one problem
  # rather than three separately rebuilt ones.
  newton <- if (!isTRUE(kernel$valid)) NULL else {
    zero <- numeric(ncol(dense_backend$W))
    list(dense_score = as.vector(crossprod(dense_backend$W, kernel$gradient)) + zero,
         sparse_score = as.numeric(Matrix::crossprod(sparse_backend$W, kernel$gradient)) + zero,
         dense_H = .gt_d_dense_hessian(kernel$curvature, dense_backend$W, prep$n),
         sparse_H = .gt_d_sparse_hessian(kernel$curvature, sparse_backend$W, prep$n))
  }

  # The first Newton step through both matrix paths, at u = 0, with each
  # assembly paired to its own factorizer exactly as the fitter pairs them.
  first_step <- if (is.null(newton)) list(valid = FALSE) else {
    dense_R <- tryCatch(chol(newton$dense_H), error = function(e) NULL)
    sparse_factor <- tryCatch(.gt_d_sparse_factor(newton$sparse_H), error = function(e) NULL)
    dense_step <- if (is.null(dense_R)) NULL else
      backsolve(dense_R, forwardsolve(t(dense_R), newton$dense_score))
    sparse_step <- if (is.null(sparse_factor)) NULL else
      .gt_d_sparse_solve(sparse_factor, newton$sparse_score)
    list(valid = TRUE,
         dense_score = fixture_digest(newton$dense_score),
         sparse_score = fixture_digest(newton$sparse_score),
         score_difference = max(abs(newton$dense_score - newton$sparse_score)),
         hessian_difference = max(abs(newton$dense_H - as.matrix(newton$sparse_H))),
         dense_factorized = !is.null(dense_R), sparse_factorized = !is.null(sparse_factor),
         dense_logdet = if (is.null(dense_R)) NA_real_ else 2 * sum(log(diag(dense_R))),
         sparse_logdet = if (is.null(sparse_factor)) NA_real_ else
           .gt_d_sparse_logdet(sparse_factor),
         step_difference = if (is.null(dense_step) || is.null(sparse_step)) NA_real_ else
           max(abs(dense_step - sparse_step)),
         max_abs_dense_step = if (is.null(dense_step)) NA_real_ else max(abs(dense_step)))
  }

  # Cross-factorization witness.
  #
  # The block above pairs each assembly with its own factorizer, which is how
  # the fitter uses them and therefore what a fitted divergence reports. That
  # pairing is exactly what makes such a divergence unattributable: assembly
  # and factorization always move together, so "the Hessians differ" and "the
  # factorizations differ" cannot be told apart from it.
  #
  # Breaking the pairing separates them. The same exact matrix is factored
  # through both implementations, and both matrices are factored through the
  # same implementation. Labels are (assembly)(factorizer): DD is the
  # dense-assembled Hessian through base chol(), DS is that same matrix
  # through Matrix/CHOLMOD, SD is the sparse-assembled Hessian through base
  # chol(), SS is it through CHOLMOD.
  #
  #                  base chol()   Matrix/CHOLMOD
  #   dense-assembled     DD             DS
  #   sparse-assembled    SD             SS
  #
  # DD and DS disagreeing while SD and SS agree follows the factorizer. DD and
  # SD disagreeing while DS and SS agree follows the assembly. Neither pair
  # disagreeing, with the paired fitted results still diverging, says the
  # divergence is not in this step at all.
  #
  # Which result is correct is a separate question from which of them differ,
  # and no comparison among these four answers it: they could agree and all be
  # wrong. Three algebraic witnesses are computed against the exact matrix for
  # that: a spectral decomposition, whose eigenvalue sum is a log determinant
  # obtained without any Cholesky factor; an LU solve through solve(), which
  # is a different algorithm with different pivoting; and a spectral solve.
  # A factorization that satisfies its own reconstruction and solve residuals
  # and agrees with the independent witnesses has met an invariant, rather
  # than merely reproduced a number a previous run also reported.
  #
  # Everything here is computed on every run, not on a trigger. The random
  # dimension is 42, so four factorizations, four solves, a spectral
  # decomposition and an LU solve cost nothing measurable beside the fit, and
  # the failure is rare enough that a trigger which fails to fire wastes the
  # specimen. Conditioning the measurement on dense and sparse disagreeing
  # would also write the hypothesis under investigation into the evidence
  # meant to test it.
  #
  # This is observational. It selects no backend, changes no control, defines
  # no threshold the test is judged against, and feeds nothing back into the
  # fit.
  cross_factorization <- function(newton) {
    to_dense <- function(H) if (is.matrix(H)) H else as.matrix(H)
    # The general sparse class, matching what the sparse assembly itself
    # produces. Matrix(sparse = TRUE) would hand CHOLMOD a symmetric-storage
    # object for one input and a general one for the other, which is a
    # difference between the two runs that has nothing to do with the values.
    to_sparse <- function(H) if (methods::is(H, "sparseMatrix")) H else
      methods::as(methods::as(methods::as(H, "dMatrix"), "generalMatrix"), "CsparseMatrix")
    score <- newton$dense_score
    # One canonical right-hand side for all four solves. The two scores differ
    # in the last bits and that difference is already reported above; reusing
    # each engine's own score here would put a second varying input into a
    # comparison whose whole purpose is to vary one thing at a time.
    rhs_scale <- max(1, max(abs(score)))

    # What each library is actually handed, rather than what it is assumed to
    # be handed. "The same mathematical Hessian" and "the same bytes presented
    # to the numerical library" are different claims, and only the second one
    # decides a floating-point result.
    presented <- function(H) {
      M <- to_dense(H)
      list(class = class(H)[[1L]], dimension = nrow(M),
           stored_entries = as.integer(Matrix::nnzero(to_sparse(H))),
           symmetry_residual = max(abs(M - t(M))),
           min_diagonal = min(diag(M)), max_diagonal = max(diag(M)),
           max_abs = max(abs(M)), digest = fixture_digest(as.numeric(M)))
    }

    # Witnesses that do not go through BLAS at all.
    #
    # The leading explanation for a divergence that follows the runner and not
    # the source is a tuned kernel selected by microarchitecture. If that is
    # what this is, then crossprod(), %*%, chol(), eigen() and solve() all sit
    # on the suspect layer, and their agreeing with each other is agreement
    # among affected parties rather than independent confirmation.
    #
    # These two compute the same quantities from elementwise products and sums,
    # which R evaluates itself. They are the slow, obviously correct
    # implementations, and at 42 dimensions the cost of preferring them is
    # nothing.
    gram <- function(A) {
      out <- matrix(0, ncol(A), ncol(A))
      for (i in seq_len(ncol(A))) for (j in seq_len(ncol(A)))
        out[i, j] <- sum(A[, i] * A[, j])
      out
    }
    applied <- function(M, x) rowSums(M * rep(x, each = nrow(M)))

    factorizers <- list(
      D = function(H) {
        M <- to_dense(H)
        R <- tryCatch(chol(M), error = function(e) NULL)
        if (is.null(R)) return(NULL)
        list(logdet = 2 * sum(log(diag(R))),
             step = backsolve(R, forwardsolve(t(R), score)),
             # R'R = H is the invariant the factor is supposed to satisfy. It
             # is checked rather than assumed, because a factor can be
             # returned without error and still not reconstruct its input.
             reconstruction = max(abs(crossprod(R) - M)),
             # The same product recomputed without BLAS, and the gap between
             # the two. A nonzero gap indicts the kernel directly, with no
             # inference from a fitted result in between.
             blas_free_reconstruction = max(abs(gram(R) - M)),
             blas_gram_difference = max(abs(gram(R) - crossprod(R))),
             factor_entries = NA_integer_, permutation = NA_character_)
      },
      S = function(H) {
        sparse <- to_sparse(H)
        f <- tryCatch(.gt_d_sparse_factor(sparse), error = function(e) NULL)
        if (is.null(f)) return(NULL)
        # The sparse counterpart of R'R = H, with the fill-reducing
        # permutation included: expand2() returns the factors whose product is
        # the original matrix, so a factor that dropped or misordered anything
        # fails here. Guarded because the expansion is a Matrix interface the
        # frozen numerical environment does not pin.
        rebuilt <- tryCatch(as.matrix(Reduce(`%*%`, Matrix::expand2(f$factor, LDL = FALSE))),
                            error = function(e) NULL)
        list(logdet = .gt_d_sparse_logdet(f),
             step = .gt_d_sparse_solve(f, score),
             reconstruction = if (is.null(rebuilt)) NA_real_ else
               max(abs(rebuilt - as.matrix(Matrix::forceSymmetric(sparse)))),
             # CHOLMOD's factor is not exposed as a plain R matrix the way
             # chol()'s is, so the BLAS-free reconstruction has no counterpart
             # here. The BLAS-free solve residual below applies to all four.
             blas_free_reconstruction = NA_real_, blas_gram_difference = NA_real_,
             factor_entries = f$factor_entries,
             permutation = tryCatch(fixture_digest(as.integer(f$factor@perm)),
                                    error = function(e) NA_character_))
      })

    labels <- c("DD", "DS", "SD", "SS")
    assemblies <- list(D = newton$dense_H, S = newton$sparse_H)
    computed <- stats::setNames(lapply(labels, function(label) {
      H <- assemblies[[substr(label, 1L, 1L)]]
      answer <- tryCatch(factorizers[[substr(label, 2L, 2L)]](H), error = function(e) NULL)
      if (is.null(answer)) return(NULL)
      M <- to_dense(H)
      scale <- max(abs(M))
      answer$solve_residual <- max(abs(as.numeric(M %*% answer$step) - score)) / rhs_scale
      answer$blas_free_solve_residual <- max(abs(applied(M, answer$step) - score)) / rhs_scale
      answer$reconstruction_residual <-
        if (!is.finite(answer$reconstruction) || !is.finite(scale) || scale <= 0) NA_real_
        else answer$reconstruction / scale
      answer$blas_free_reconstruction_residual <-
        if (!is.finite(answer$blas_free_reconstruction) || !is.finite(scale) || scale <= 0)
          NA_real_ else answer$blas_free_reconstruction / scale
      answer
    }), labels)

    combinations <- stats::setNames(lapply(labels, function(label) {
      answer <- computed[[label]]
      head <- list(
        assembly = if (substr(label, 1L, 1L) == "D") "dense" else "sparse",
        factorizer = if (substr(label, 2L, 2L) == "D") "base_chol" else "matrix_cholmod",
        factorized = !is.null(answer))
      if (is.null(answer))
        return(c(head, list(logdet = NA_real_, step = NA_character_,
                            max_abs_step = NA_real_, solve_residual = NA_real_,
                            blas_free_solve_residual = NA_real_,
                            reconstruction_residual = NA_real_,
                            blas_free_reconstruction_residual = NA_real_,
                            blas_gram_difference = NA_real_,
                            factor_entries = NA_integer_, permutation = NA_character_)))
      c(head, list(logdet = answer$logdet, step = fixture_digest(answer$step),
                   max_abs_step = max(abs(answer$step)),
                   solve_residual = answer$solve_residual,
                   blas_free_solve_residual = answer$blas_free_solve_residual,
                   reconstruction_residual = answer$reconstruction_residual,
                   blas_free_reconstruction_residual =
                     answer$blas_free_reconstruction_residual,
                   blas_gram_difference = answer$blas_gram_difference,
                   factor_entries = answer$factor_entries,
                   permutation = answer$permutation))
    }), labels)

    # Independent witnesses, on the dense-assembled matrix. The assembly
    # difference is reported separately, so a witness is wanted against one
    # named matrix rather than against an average of two.
    canonical <- to_dense(newton$dense_H)
    spectrum <- tryCatch(eigen(canonical, symmetric = TRUE), error = function(e) NULL)
    values <- if (is.null(spectrum)) NULL else spectrum$values
    lu_step <- tryCatch(as.numeric(solve(canonical, score)), error = function(e) NULL)
    spectral_step <- if (is.null(spectrum)) NULL else tryCatch(
      as.numeric(spectrum$vectors %*% (crossprod(spectrum$vectors, score) / values)),
      error = function(e) NULL)
    residual_of <- function(step) if (is.null(step)) NA_real_ else
      max(abs(as.numeric(canonical %*% step) - score)) / rhs_scale
    blas_free_residual_of <- function(step) if (is.null(step)) NA_real_ else
      max(abs(applied(canonical, step) - score)) / rhs_scale
    # The sparse assembly's own spectrum. Two matrices agreeing entrywise to
    # machine precision can still be reported here, and a claim about
    # conditioning has to name which matrix it is about.
    sparse_values <- tryCatch(eigen(to_dense(newton$sparse_H), symmetric = TRUE,
                                    only.values = TRUE)$values, error = function(e) NULL)
    witnesses <- list(
      eigen_available = !is.null(values),
      eigen_logdet = if (is.null(values)) NA_real_ else sum(log(values)),
      min_eigenvalue = if (is.null(values)) NA_real_ else min(values),
      max_eigenvalue = if (is.null(values)) NA_real_ else max(values),
      condition_number = if (is.null(values) || min(values) <= 0) NA_real_ else
        max(values) / min(values),
      reciprocal_condition = tryCatch(rcond(canonical), error = function(e) NA_real_),
      sparse_eigen_logdet = if (is.null(sparse_values)) NA_real_ else sum(log(sparse_values)),
      sparse_min_eigenvalue = if (is.null(sparse_values)) NA_real_ else min(sparse_values),
      lu_step = if (is.null(lu_step)) NA_character_ else fixture_digest(lu_step),
      lu_solve_residual = residual_of(lu_step),
      blas_free_lu_solve_residual = blas_free_residual_of(lu_step),
      spectral_step = if (is.null(spectral_step)) NA_character_ else fixture_digest(spectral_step),
      spectral_solve_residual = residual_of(spectral_step),
      blas_free_spectral_solve_residual = blas_free_residual_of(spectral_step))

    # The comparisons the layout exists to make. Each holds one input fixed
    # and varies the other, so a nonzero entry names the layer it varies.
    gap <- function(a, b) {
      x <- computed[[a]]; y <- computed[[b]]
      if (is.null(x) || is.null(y)) return(list(logdet = NA_real_, step = NA_real_))
      list(logdet = abs(x$logdet - y$logdet), step = max(abs(x$step - y$step)))
    }
    against <- function(reference, extract) vapply(labels, function(label) {
      answer <- computed[[label]]
      if (is.null(answer) || is.null(reference)) NA_real_ else extract(answer, reference)
    }, numeric(1))
    comparisons <- list(
      # Same matrix, different factorizer.
      factorizer_on_dense_assembly = gap("DD", "DS"),
      factorizer_on_sparse_assembly = gap("SD", "SS"),
      # Same factorizer, different matrix.
      assembly_under_base_chol = gap("DD", "SD"),
      assembly_under_cholmod = gap("DS", "SS"),
      # Against algebra rather than against each other.
      logdet_versus_eigen = against(
        if (is.null(values)) NULL else sum(log(values)),
        function(answer, reference) abs(answer$logdet - reference)),
      step_versus_lu = against(lu_step, function(answer, reference)
        max(abs(answer$step - reference))),
      step_versus_spectral = against(spectral_step, function(answer, reference)
        max(abs(answer$step - reference))))

    list(presented = list(dense = presented(newton$dense_H),
                          sparse = presented(newton$sparse_H),
                          assembly_difference =
                            max(abs(to_dense(newton$dense_H) - to_dense(newton$sparse_H))),
                          score_digest = fixture_digest(score)),
         combinations = combinations, witnesses = witnesses, comparisons = comparisons)
  }
  crossed <- if (is.null(newton)) list(valid = FALSE) else
    tryCatch(c(list(valid = TRUE), cross_factorization(newton)),
             error = function(e) list(valid = FALSE,
                                      cross_factorization_error = conditionMessage(e)))

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

  evidence <- list(reconstruction = reconstruction, identity = identity,
       platform = platform_provenance(),
       shared_kernel = shared_kernel, first_step = first_step,
       cross_factorization = crossed,
       fixed_parameter_replay = replay, budget_ladder = ladder)
  # Raw objects travel separately from the printed evidence. dput() of a pair
  # of 42 by 42 matrices is unreadable, and what a retained specimen is for is
  # replaying exact numbers rather than parsing a rendering of them.
  list(evidence = evidence,
       specimen = list(
         panel = list(item = pair$item, rater = pair$rater, rep = pair$rep,
                      a = pair$a, b = pair$b),
         start = start, factors = factors, newton = newton,
         curvature = curvature_values,
         gradient = if (isTRUE(kernel$valid)) kernel$gradient else NULL,
         eta = as.numeric(baseline)))
}
# Diagnostics must not decide the test. A failure inside the replay is reported
# and swallowed, so the assertion below still judges the fit rather than being
# pre-empted by an error in the instrument that was meant to explain it.
cat("Joint binary covariance localization (issue #14):\n")
joint_localization <- tryCatch(localize_joint_divergence(jfit, joint_digest),
  error = function(e) list(evidence = list(localization_error = conditionMessage(e)),
                           specimen = NULL))
dput(joint_localization$evidence)

# Identical source has produced both passing and failing results here. Retain
# evidence on failure; the assertion below is deliberately left unweakened.
# The condition is named once and read twice, so the printed diagnostics and
# the retained specimen cannot come to disagree about whether the fit failed.
joint_assertion_failed <- !isTRUE(jfit$optimizer_completed) ||
  !isTRUE(jfit$covariance_components$item[1, 2] > .2) ||
  !isTRUE(all(vapply(jfit$covariance_components,
    function(S) min(eigen(S, symmetric = TRUE, only.values = TRUE)$values) > -1e-10,
    logical(1))))
if (joint_assertion_failed) {
  report_fit_evidence("Joint binary covariance fixture failure diagnostics (issue #14):",
                      jfit, joint_digest)
}
# Swallowed for the reason the replay is: an error while writing evidence must
# not replace the failure that evidence was collected to explain.
tryCatch(retain_joint_specimen(joint_localization, joint_assertion_failed, jfit, joint_digest),
         error = function(e)
           cat("Issue #14 specimen retention failed: ", conditionMessage(e), "\n", sep = ""))
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
