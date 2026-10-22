# Run from the project directory with Rscript tests/test_discrete_cholesky.R.
#
# Cholesky coordinates for unstructured source covariances: the entries of the
# lower-triangular factor, with a nonnegative diagonal. Log-Cholesky
# coordinates can only approach a singular source matrix; near it the other
# directions become ill-conditioned and the optimizer stalls short of
# stationarity, which refused joint fits of the bundled panels whose evaluator
# and prompt covariances are singular. A zero Cholesky diagonal is a natural
# boundary, as zero is for direct variances. Checks:
#
#   * 'auto' resolves joint unstructured covariance to Cholesky coordinates, with
#     the same factor bounds as log-Cholesky;
#   * a zero diagonal is exact, rounding below it is projected, a meaningful
#     negative value is refused;
#   * the observed-information map matches differences of the covariance;
#   * a constructed joint panel with a rank-one rater covariance fits to an
#     exactly singular, accepted rater matrix, at an objective no worse than
#     the log-Cholesky fit's.
source("load_functions.R")
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
refuses <- function(expr, pattern) {
  message <- tryCatch({ force(expr); "" }, error = conditionMessage)
  expect(grepl(pattern, message, fixed = TRUE), paste("refuses with", pattern))
}

# --- coordinates ----------------------------------------------------------------
dimensions <- c("y", "z")
groups <- list(item = list(index = 1:4, nlevels = 4L), rater = list(index = c(1L, 2L, 1L, 2L), nlevels = 2L))
setup <- .gt_d_covariance_setup(groups, 2L, "unstructured", .gt_d_control(list()), dimensions)
diagonal <- rep(setup$diagpos, 2L)
expect(identical(setup$parameterization, "cholesky"), "'auto' resolves joint unstructured covariance to Cholesky coordinates")
expect(all(setup$start[diagonal] == 0.4) && all(setup$start[!diagonal] == 0) &&
         all(setup$lower[diagonal] == 0) && all(setup$upper[diagonal] == exp(5)) &&
         all(setup$lower[!diagonal] == -10) && all(setup$upper[!diagonal] == 10),
       "diagonals start at start_sd within [0, exp(5)]; off-diagonals within 10 of zero")
legacy <- .gt_d_covariance_setup(groups, 2L, "unstructured",
  .gt_d_control(list(covariance_parameterization = "log_cholesky")), dimensions)
expect(identical(legacy$parameterization, "log_cholesky") && all(exp(legacy$upper[diagonal]) == setup$upper[diagonal]),
       "log-Cholesky stays available with the same largest diagonal factor entry")
factors <- .gt_d_covariance_factors(c(0, .3, .5, 1.2, -.4, 0), setup)
expect(factors$item[1, 1] == 0 && factors$rater[2, 2] == 0 && factors$item[2, 1] == .3,
       "a zero diagonal is an exact zero and the factor entries are the coordinates")
expect(.gt_d_covariance_factors(c(-1e-14, .3, .5, 1, 0, 1), setup)$item[1, 1] == 0,
       "rounding just below zero is projected onto the boundary")
refuses(.gt_d_covariance_factors(c(-0.1, .3, .5, 1, 0, 1), setup), "nonnegative")

# --- observed-information map -----------------------------------------------------
prep <- list(start = c(intercept_y = 0, intercept_z = 0), q = 2L, dimensions = dimensions)
theta <- c(prep$start, c(.7, .3, .5, 1.2, -.4, .2))
names(theta)[-(1:2)] <- names(setup$start)
mapping <- .gt_d_information_mapping(theta, prep, groups, setup)
vech <- function(par) unlist(lapply(.gt_d_covariance_factors(par[-(1:2)], setup), function(L) {
  S <- tcrossprod(L); S[lower.tri(S, diag = TRUE)] }))
numeric_jacobian <- vapply(3:8, function(j) {
  h <- 1e-6; up <- down <- theta; up[[j]] <- up[[j]] + h; down[[j]] <- down[[j]] - h
  (vech(up) - vech(down)) / (2 * h) }, numeric(6))
expect(max(abs(mapping$jacobian[, 3:8] - numeric_jacobian)) < 1e-8,
       "the analytic covariance map matches central differences in Cholesky coordinates")

# --- a fit whose rater covariance is singular -------------------------------------
# Two binary outcomes share one rater effect, so the true rater covariance has
# rank one. Constructed once; seed and sizes fixed before fitting.
set.seed(1)
n_item <- 40L; n_rater <- 6L; n_rep <- 3L
panel <- expand.grid(item = factor(seq_len(n_item)), rater = factor(seq_len(n_rater)), rep = factor(seq_len(n_rep)))
item <- matrix(rnorm(n_item * 2), n_item, 2) %*% chol(matrix(c(1, .5, .5, 1), 2))
rater <- rnorm(n_rater, sd = .6)
eta <- item[as.integer(panel$item), ] + rater[as.integer(panel$rater)]
panel$y <- factor(as.integer(runif(nrow(panel)) < plogis(eta[, 1])), levels = c("0", "1"))
panel$z <- factor(as.integer(runif(nrow(panel)) < plogis(eta[, 2])), levels = c("0", "1"))
design <- gt_design("item", "rater", random = c("item", "rater"), replicates = n_rep)
fit_with <- function(parameterization) suppressWarnings(gt_fit(panel, c("y", "z"), design = design,
  family = gt_family("binary", "logit"), covariance = "unstructured",
  control = gt_control(discrete = list(covariance_parameterization = parameterization))))
best <- function(fit) min(vapply(fit$diagnostics$attempts, function(a) a$objective, numeric(1)))
cholesky <- fit_with("auto")
logchol <- fit_with("log_cholesky")
rater_eigen <- eigen(cholesky$covariance_components$rater, symmetric = TRUE, only.values = TRUE)$values
expect(identical(cholesky$diagnostics$covariance_parameterization, "cholesky") && isTRUE(cholesky$numerically_accepted),
       "the Cholesky fit is accepted")
expect(abs(min(rater_eigen)) < 1e-12 && max(rater_eigen) > .1,
       "the rater covariance is exactly singular, with one positive eigenvalue")
expect("rater::chol[z,z]" %in% cholesky$diagnostics$zero_variance_parameters &&
         !"artificial_parameter_bound_contact" %in% cholesky$diagnostics$acceptance_failures,
       "the zero diagonal is recorded as a natural boundary, not an artificial bound contact")
expect(min(eigen(logchol$covariance_components$rater, symmetric = TRUE, only.values = TRUE)$values) > 0 &&
         best(cholesky) <= best(logchol) + 1e-6,
       "log-Cholesky stays strictly positive definite and does not reach a lower objective")
cat("PASS: Cholesky coordinates reach singular source covariances exactly.\n")
