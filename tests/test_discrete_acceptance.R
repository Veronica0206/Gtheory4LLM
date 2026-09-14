# Clean-session numerical acceptance, labeled-covariance, and integration tests.
source(file.path("R", "design.R"))
source(file.path("R", "discrete_response.R"))
source(file.path("R", "discrete_dense.R"))
source(file.path("R", "discrete_mode.R"))
source(file.path("R", "discrete.R"))
close <- function(a, b, tol = 1e-5) stopifnot(max(abs(a - b)) < tol)
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
}
binary <- list(family = "binary", link = "logit", levels = c("0", "1"))
design <- list(object = "item", facets = "occasion", term_members = list(item = "item"))
panel <- expand.grid(occasion = seq_len(12), item = seq_len(8))
counts <- c(3L, 6L, 7L, 10L, 4L, 8L, 2L, 9L)
panel$a <- as.integer(panel$occasion <= counts[panel$item])
panel$b <- as.integer((panel$occasion + 4L) %% 12L < c(6L, 7L, 8L, 9L, 3L, 7L, 4L, 10L)[panel$item])

# Names identify dimensions; each axis can arrive in a different order. Empty,
# duplicated, partial, and foreign labels must fail instead of being relabeled.
S <- matrix(c(1, .3, .3, 2), 2, dimnames = list(c("a", "b"), c("a", "b")))
groups <- list(item = .gt_d_group(panel, "item"))
setup <- .gt_d_covariance_setup(groups, 2L, "unstructured",
  .gt_d_control(list(fixed_covariance = list(item = S[c("b", "a"), c("a", "b")]))), c("a", "b"))
close(tcrossprod(setup$fixed$item), S, 1e-12)
for (bad in list(`rownames only` = structure(unname(S), dimnames = list(c("a", "b"), NULL)),
                duplicate = structure(unname(S), dimnames = list(c("a", "a"), c("a", "b"))),
                foreign = structure(unname(S), dimnames = list(c("a", "z"), c("a", "b")))))
  expect_error(.gt_d_covariance_setup(groups, 2L, "unstructured",
    .gt_d_control(list(fixed_covariance = list(item = bad))), c("a", "b")), "latent dimensions")
unnamed <- .gt_d_covariance_setup(groups, 2L, "unstructured",
  .gt_d_control(list(fixed_covariance = list(item = unname(S)))), c("a", "b"))
close(tcrossprod(unnamed$fixed$item), S, 1e-12)

fit <- .gt_fit_discrete(panel, c("a", "b"), design, list(binary, binary),
  control = list(fixed_covariance = list(item = S[c("b", "a"), c("b", "a")])))
reversed <- .gt_fit_discrete(panel, c("b", "a"), design, list(binary, binary),
  control = list(fixed_covariance = list(item = S)))
stopifnot(fit$numerically_accepted, reversed$numerically_accepted,
          fit$optimizer_completed,
          identical(fit$approximation_adequacy, "not_assessed_first_order_laplace"))
close(fit$minus2loglik, reversed$minus2loglik, 1e-7)
close(fit$means, reversed$means[c("a", "b")], 1e-5)
close(fit$covariance_components$item, reversed$covariance_components$item[c("a", "b"), c("a", "b")], 1e-12)

# Row order and identifier strings only permute the random-effect integration
# coordinates; the marginal model and conditional probabilities are unchanged.
permutation <- rev(seq_len(nrow(panel)))
renamed <- panel[permutation, ]
renamed$item <- paste0("new:item:", 100L - renamed$item)
invariant <- .gt_fit_discrete(renamed, c("a", "b"), design, list(binary, binary),
  control = list(fixed_covariance = list(item = S)))
close(fit$minus2loglik, invariant$minus2loglik, 1e-7)
close(fit$conditional_probabilities$a, invariant$conditional_probabilities$a[permutation, ], 1e-5)

# A nonzero random-intercept likelihood factors into eight one-dimensional
# integrals. This reference uses direct adaptive integration, without any
# Laplace mode, derivatives, or engine covariance construction.
prep <- .gt_d_prepare(panel, "a", list(binary))
known_variance <- .5
known_intercept <- .2
setup1 <- .gt_d_covariance_setup(groups, 1L, "diagonal",
  .gt_d_control(list(fixed_covariance = list(item = matrix(known_variance)))), "a")
ctl <- .gt_d_control(list())
laplace <- .gt_d_laplace(known_intercept, prep, groups, setup1, ctl)
integrated_nll <- function(tol) -sum(vapply(counts, function(successes) {
  integrand <- function(u) {
    eta <- known_intercept + u
    log_p <- -pmax(-eta, 0) - log1p(exp(-abs(eta)))
    log_one_minus_p <- -pmax(eta, 0) - log1p(exp(-abs(eta)))
    exp(successes * log_p + (12L - successes) * log_one_minus_p +
          dnorm(u, 0, sqrt(known_variance), log = TRUE))
  }
  log(integrate(integrand, -Inf, Inf, rel.tol = tol, abs.tol = tol * 1e-4,
                subdivisions = 1000L, stop.on.error = TRUE)$value)
}, numeric(1)))
reference <- integrated_nll(1e-10)
close(reference, integrated_nll(1e-12), 1e-8)
approximation_error <- laplace - reference
stopifnot(abs(approximation_error) > 1e-6, abs(approximation_error) < .1)
cat(sprintf("Nonzero random-effect integration reference: Laplace minus adaptive-integration NLL = %.8f.\n", approximation_error))

# The covariance derivative must detect an inward direction even when its
# log-SD derivative is effectively zero at the artificial -10 lower bound.
# This coordinate check is specific to log-Cholesky; request it explicitly
# because 'auto' now resolves univariate/diagonal models to direct variances.
cholesky_ctl <- .gt_d_control(list(covariance_parameterization = "log_cholesky"))
free_setup <- .gt_d_covariance_setup(groups, 1L, "diagonal", cholesky_ctl, "a")
stopifnot(identical(free_setup$parameterization, "log_cholesky"))
near_zero <- c(qlogis(mean(panel$a)), -10)
near_zero_detail <- .gt_d_laplace(near_zero, prep, groups, free_setup, cholesky_ctl, details = TRUE)
near_zero_check <- .gt_d_stationarity(near_zero, prep, groups, free_setup, cholesky_ctl, near_zero_detail)
stopifnot(!near_zero_check$stationary_within_tolerance,
          near_zero_check$covariance_gradients$item[[1L]] < -1)

# The resolved default reaches the same natural zero-variance boundary in
# direct variance coordinates, where the lower bound is not artificial.
variance_setup <- .gt_d_covariance_setup(groups, 1L, "diagonal", ctl, "a")
stopifnot(identical(variance_setup$parameterization, "variance"),
          identical(variance_setup$lower, 0))
at_zero <- c(qlogis(mean(panel$a)), 0)
at_zero_detail <- .gt_d_laplace(at_zero, prep, groups, variance_setup, ctl, details = TRUE)
at_zero_check <- .gt_d_stationarity(at_zero, prep, groups, variance_setup, ctl, at_zero_detail)
stopifnot(!at_zero_check$stationary_within_tolerance,
          at_zero_check$covariance_gradients$item[[1L]] < 0)

# A deliberately truncated optimizer is allowed to return inspectable values,
# but cannot enable coefficients. Disabling restart validation is also explicit.
loose <- .gt_fit_discrete(panel, "a", design, list(binary),
  control = list(maxit = 1L, reltol = .1))
stopifnot(!loose$numerically_accepted, !loose$converged,
          length(loose$covariance_components) == 1L,
          length(loose$diagnostics$acceptance_failures) > 0L)
unchecked <- .gt_fit_discrete(panel, "a", design, list(binary),
  control = list(fixed_covariance = list(item = matrix(.5)), alternative_starts = 0L))
stopifnot(unchecked$optimizer_completed, !unchecked$numerically_accepted,
          !unchecked$diagnostics$stability$checked)

# A data configuration with no between-item variation has a legitimate zero
# variance optimum. The current log-Cholesky parameterization cannot attain
# exact zero: contact with its artificial floor must be reported and rejected.
boundary <- panel
boundary$a <- as.integer(boundary$occasion <= 6L)
boundary_fit <- .gt_fit_discrete(boundary, "a", design, list(binary),
  control = list(covariance_parameterization = "log_cholesky",
    start_sd = exp(-10), maxit = 50L))
stopifnot(boundary_fit$optimizer_completed, !boundary_fit$numerically_accepted,
          "artificial_parameter_bound_contact" %in% boundary_fit$diagnostics$acceptance_failures)

# Changing a nominal reference is a linear transformation of an unstructured
# covariance model; a diagonal restriction would generally change the model.
nominal <- panel
nominal$category <- factor(c("red", "blue", "green")[(nominal$occasion + nominal$item) %% 3L + 1L],
                           levels = c("red", "blue", "green"))
family1 <- list(family = "categorical", link = "softmax", levels = levels(nominal$category), reference = "red")
family2 <- family1; family2$reference <- "blue"
first_names <- c("category::blue_vs_red", "category::green_vs_red")
second_names <- c("category::red_vs_blue", "category::green_vs_blue")
C <- matrix(c(.5, .15, .15, .8), 2, dimnames = list(first_names, first_names))
T <- matrix(c(-1, -1, 0, 1), 2)
D <- T %*% C %*% t(T); dimnames(D) <- list(second_names, second_names)
nominal1 <- .gt_fit_discrete(nominal, "category", design, list(family1),
  control = list(fixed_covariance = list(item = C)))
nominal2 <- .gt_fit_discrete(nominal, "category", design, list(family2),
  control = list(fixed_covariance = list(item = D)))
stopifnot(nominal1$numerically_accepted, nominal2$numerically_accepted)
close(nominal1$minus2loglik, nominal2$minus2loglik, 1e-7)
close(nominal1$conditional_probabilities$category,
      nominal2$conditional_probabilities$category[, colnames(nominal1$conditional_probabilities$category)], 1e-5)

# Small repeated sparse-group regression experiment. These six replicates
# exercise interior and near-zero estimates; they are deliberately insufficient
# for claims about bias, coverage, or general approximation adequacy.
simulation_panel <- expand.grid(occasion = seq_len(6), item = seq_len(10))
simulation_results <- lapply(seq_len(6), function(replicate) {
  set.seed(8230L + replicate)
  truth <- if (replicate <= 3L) 0 else 1
  random <- rnorm(10, sd = sqrt(truth))
  simulation_panel$a <- rbinom(nrow(simulation_panel), 1,
                                plogis(-.2 + random[simulation_panel$item]))
  simulation_fit <- .gt_fit_discrete(simulation_panel, "a", design, list(binary),
                                     control = list(maxit = 80L))
  if (simulation_fit$numerically_accepted) stopifnot(
    simulation_fit$diagnostics$outer_stationarity$stationary_within_tolerance,
    simulation_fit$diagnostics$stability$stable,
    !length(simulation_fit$diagnostics$parameter_bounds))
  data.frame(replicate = replicate, generating_variance = truth,
    estimated_variance = simulation_fit$covariance_components$item[[1L]],
    numerically_accepted = simulation_fit$numerically_accepted,
    near_zero = simulation_fit$covariance_components$item[[1L]] < 1e-6)
})
simulation_results <- do.call(rbind, simulation_results)
stopifnot(all(is.finite(simulation_results$estimated_variance)),
          all(simulation_results$estimated_variance >= 0),
          any(simulation_results$near_zero), any(!simulation_results$near_zero))
cat(sprintf("Sparse-group regression experiment: %d/6 numerically accepted, %d/6 near-zero variance estimates; no recovery or coverage claim.\n",
            sum(simulation_results$numerically_accepted), sum(simulation_results$near_zero)))
cat("Discrete acceptance checks passed: covariance labels, permutations, direct integration, covariance-boundary score, tight restarts, bound rejection, and nominal reference invariance.\n")
