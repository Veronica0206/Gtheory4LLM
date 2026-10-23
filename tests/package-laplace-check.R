# Installed-package checks for gt_laplace_check().
#
# The check is only worth having if its reference is independent of the
# Laplace machinery it judges. For an item-only binary model the marginal
# likelihood is a product of one-dimensional integrals that integrate() can
# compute on its own, so that is the yardstick; importance sampling is then
# held to quadrature within its own reported error, and the zero-variance
# identity is checked exactly.
library(Gtheory4LLM)

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
outcome <- function(expr) tryCatch({ force(expr); "accepted" }, error = conditionMessage)

b <- expand.grid(item = 1:3, rater = 1:8)
set.seed(11)
b$y <- rbinom(nrow(b), 1, plogis(c(-1, 0.2, 1.1)[b$item]))
item_only <- gt_design("item", "rater", random = ~ item)
fit <- gt_fit(b, "y", item_only, gt_family("binary", "logit"), control = gt_control(discrete = list(maxit = 200L)))

check <- gt_laplace_check(fit)
expect(inherits(check, "gt_laplace_check") && identical(check$method, "quadrature") &&
         check$random_dimension == 3L && isTRUE(check$recomputed_agrees) &&
         isTRUE(check$available) && isTRUE(check$usable) && check$unavailable_evaluations == 0L,
       "three dimensions choose quadrature, the objective is recomputed, and the estimate is usable")
beta <- fit$parameters[[1L]]
sigma <- sqrt(fit$parameters[[2L]])
reference <- -sum(vapply(1:3, function(i) {
  y <- b$y[b$item == i]
  log(integrate(function(u) vapply(u, function(value)
    exp(sum(dbinom(y, 1, plogis(beta + sigma * value), log = TRUE))), numeric(1)) * dnorm(u),
    -Inf, Inf, rel.tol = 1e-10)$value)
}, numeric(1)))
expect(abs(check$refined_minus2loglik - 2 * reference) < 1e-7,
       "the quadrature reference equals an independent integrate() reference")
expect(abs(check$refinement_difference) < 1e-6, "refining the grid does not move the reference")
expect(check$difference > 0 && abs(check$difference - (fit$minus2loglik - 2 * reference)) < 1e-6,
       "the difference is the Laplace error of the stored objective")

importance <- gt_laplace_check(fit, method = "importance", draws = 20000, seed = 7)
expect(identical(importance$method, "importance") && is.finite(importance$mc_se) &&
         importance$effective_sample_size > 1000 && isTRUE(importance$usable),
       "importance sampling reports its Monte Carlo error and effective sample size")
expect(identical(importance$proposal, "defensive_normal_mixture") &&
         identical(importance$prior_weight, 0.1) && importance$weight_upper_bound == 10 &&
         importance$max_importance_weight <= 10 &&
         sum(importance$proposal_draws) == importance$draws &&
         all(importance$proposal_draws > 0) &&
         abs(importance$proposal_draws[["standard_normal_prior"]] / importance$draws - 0.1) < 0.02,
       "the defensive mixture records both sampling components and its finite weight bound")
expect(abs(importance$refined_minus2loglik - check$refined_minus2loglik) < 4 * importance$mc_se + 1e-6,
       "importance sampling agrees with quadrature within its error")
expect(identical(gt_laplace_check(fit, method = "importance", draws = 20000, seed = 7)$refined_minus2loglik,
                 importance$refined_minus2loglik), "a seeded check is reproducible")

# This is the original infinite-second-moment counterexample for a Gaussian-only
# proposal: the posterior precision exceeds 2 in all independent logistic groups.
# The defensive proposal is nevertheless bounded because q >= 0.1 * prior.
p_mode <- fit$conditional_probabilities$y[, "1"]
H_diagonal <- 1 + sigma^2 * tapply(p_mode * (1 - p_mode), b$item, sum)
expect(all(H_diagonal > 2), "the binary fixture retains its Gaussian-only infinite-variance tail condition")
set.seed(271)
rng_before <- .Random.seed
for (budget in c(1000L, 5000L)) for (check_seed in c(17L, 31L, 47L)) {
  replicate_check <- gt_laplace_check(fit, method = "importance", draws = budget, seed = check_seed)
  expect(replicate_check$available && is.finite(replicate_check$mc_se) &&
           abs(replicate_check$refined_minus2loglik - 2 * reference) < 6 * replicate_check$mc_se + 1e-6,
         "independent seeds and two budgets agree with the adaptive-integration reference within a broad regression tolerance")
}
expect(identical(.Random.seed, rng_before), "mixture component selection and normal draws preserve the caller RNG")

zero <- gt_fit(b, "y", gt_design("item", "rater", random = ~ item + rater), gt_family("binary", "logit"),
  control = gt_control(discrete = list(fixed_covariance = list(item = matrix(0, 1, 1), rater = matrix(0, 1, 1)))))
zero_check <- gt_laplace_check(zero, seed = 1)
expect(abs(zero_check$difference) < 1e-8 && zero_check$mc_se < 1e-10,
       "with no random variation the Laplace objective is exact")

# --- Limits before computation, and unavailable rather than zero ------------------
four <- expand.grid(item = 1:4, rater = 1:6)
set.seed(12)
four$y <- rbinom(nrow(four), 1, plogis(c(-1, 0, 0.5, 1)[four$item]))
fit4 <- gt_fit(four, "y", item_only, gt_family("binary", "logit"), control = gt_control(discrete = list(maxit = 200L)))
started <- proc.time()
message <- outcome(gt_laplace_check(fit4, method = "quadrature", nodes = 40))
expect(grepl("more than max_evaluations", message, fixed = TRUE) && (proc.time() - started)[["elapsed"]] < 5,
       "an evaluation budget is refused before any computation")
expect(grepl("exceeds max_dimension", outcome(gt_laplace_check(fit4, seed = 1, max_dimension = 3)), fixed = TRUE),
       "the dimension cap is applied before the dense backend exists")
# On a one-dimensional system with no response blocks the weight is z^2/2 - u^2/2
# exactly; a singular factor must yield an unavailable contribution, not zero.
log_weight <- Gtheory4LLM:::.gt_laplace_log_weight
trivial <- list(n = 1L, q = 1L, blocks = list())
good <- log_weight(0.3, 0, chol(matrix(4)), matrix(0, 1, 1), matrix(0, 1, 1), 0, trivial, 0)
expect(abs(good - (0.3^2 / 2 - (0.3 / 2)^2 / 2)) < 1e-12, "the weight helper reproduces the closed form")
broken <- log_weight(0.3, 0, matrix(0), matrix(0, 1, 1), matrix(0, 1, 1), 0, trivial, 0)
expect(is.na(broken), "a factor that cannot solve its system yields an unavailable contribution, not zero")

# Independent normal density calculation on a correlated two-dimensional
# proposal: both sampling branches must divide by the same FULL mixture.
mixture_weight <- Gtheory4LLM:::.gt_laplace_mixture_log_weight
V <- matrix(c(0.5, 0.12, 0.12, 1.4), 2, 2)
R <- chol(solve(V))
u0 <- c(0.3, -0.2)
for (z in list(c(0.4, -0.7), c(8, -6))) for (from_prior in c(FALSE, TRUE)) {
  u <- if (from_prior) z else u0 + solve(R, z)
  prior_density <- prod(dnorm(u))
  gaussian_density <- exp(-log(2 * pi) - log(det(V)) / 2 -
    as.numeric(crossprod(u - u0, solve(V, u - u0))) / 2)
  expected <- log(prior_density / (0.9 * gaussian_density + 0.1 * prior_density))
  actual <- mixture_weight(z, from_prior, u0, R, matrix(0, 1, 2), matrix(0, 1, 1),
                           0, trivial, -sum(log(diag(R))))
  expect(abs(actual - expected) < 1e-11 && actual <= log(10) + 1e-12,
         "both component draws use the full correlated mixture density and retain the bound")
}

# --- Refusals and the data argument ------------------------------------------
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
gaussian <- gt_fit(d, "score", gt_design("item", "rater", random = ~ item + rater),
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
expect(grepl("exact likelihood", outcome(gt_laplace_check(gaussian)), fixed = TRUE), "a Gaussian fit is refused")
expect(grepl("needs a seed", outcome(gt_laplace_check(fit, method = "importance")), fixed = TRUE),
       "importance sampling needs a seed")
expect(grepl("limited to four", outcome(gt_laplace_check(zero, method = "quadrature")), fixed = TRUE),
       "quadrature refuses more than four dimensions")
expect(grepl("exceeds max_dimension", outcome(gt_laplace_check(zero, seed = 1, max_dimension = 5)), fixed = TRUE),
       "the dimension cap is enforced")
dropped <- gt_fit(b, "y", item_only, gt_family("binary", "logit"),
  control = gt_control(discrete = list(maxit = 200L), retain = list(data = FALSE)))
expect(grepl("without its data", outcome(gt_laplace_check(dropped)), fixed = TRUE),
       "a fit stored without data asks for data =")
expect(abs(gt_laplace_check(dropped, data = b)$refined_minus2loglik - check$refined_minus2loglik) < 1e-9,
       "and gives the same reference once data = is supplied")
for (bad in list(0, 4, 81, 2.5, NA)) expect(inherits(tryCatch(gt_laplace_check(fit, nodes = bad), error = identity), "error"),
                                            "invalid node counts are refused")

printed <- capture.output(print(check))
printed_text <- paste(trimws(printed), collapse = " ")
expect(any(grepl("Laplace approximation check: adaptive Gauss-Hermite quadrature", printed, fixed = TRUE)) &&
         !any(nchar(printed) > 80L) &&
         any(grepl("Usable:", printed, fixed = TRUE)) &&
         any(grepl("not bias in the estimates", printed, fixed = TRUE)) &&
         grepl("not an error bound", printed_text, fixed = TRUE) &&
         any(grepl("independent seeds", printed, fixed = TRUE)) &&
         identical(withVisible(print(check))$visible, FALSE), "the print names the method, the verdict and its scope")
importance_printed <- capture.output(print(importance))
expect(any(grepl("defensive-mixture importance sampling", importance_printed, fixed = TRUE)) &&
         any(grepl("accuracy guarantee", importance_printed, fixed = TRUE)) &&
         any(grepl("delta-method estimate", importance_printed, fixed = TRUE)),
       "the importance print describes its proposal and finite-sample limitations")

# --- Retained labeled binary responses are read as the fit's own encoding ------
# A binary outcome fitted with labels other than "0"/"1" is retained as 0/1
# integers; the check must not re-resolve that frame as new user data.
labeled <- b
labeled$y <- factor(ifelse(b$y == 1L, "yes", "no"), levels = c("no", "yes"))
labeled_fit <- gt_fit(labeled, "y", item_only, gt_family("binary", "logit", levels = c("no", "yes")),
                      control = gt_control(discrete = list(maxit = 200L)))
expect(is.integer(labeled_fit$data$y) && all(labeled_fit$data$y == b$y),
       "the labeled fit retains its responses as 0/1 integers")
from_retained <- gt_laplace_check(labeled_fit)
from_explicit <- gt_laplace_check(labeled_fit, data = labeled)
expect(isTRUE(from_retained$available) && isTRUE(from_explicit$available) &&
         abs(from_retained$difference - from_explicit$difference) <= 1e-10 &&
         abs(from_retained$laplace_minus2loglik - check$laplace_minus2loglik) <= 1e-8,
       "retained and explicit labeled data give the same comparison, matching the numeric fit")
expect(grepl("Numeric/logical binary input", outcome(gt_laplace_check(labeled_fit, data = b))),
       "numeric 0/1 supplied as new data for a labeled family is still refused")

# Saved auto requests must retain the coordinates that the fitting version
# resolved. Before the Cholesky default changed, the following explicit fit
# would have recorded an auto request with these same log-Cholesky parameters.
# A deliberately short fit is sufficient: this diagnostic describes the
# recorded point and must not alter its covariance coordinates.
legacy_panel <- expand.grid(item = 1:4, rater = 1:6)
legacy_panel$y <- as.integer((legacy_panel$item + legacy_panel$rater) %% 3L > 0L)
legacy_panel$z <- as.integer((2L * legacy_panel$item + legacy_panel$rater) %% 4L > 1L)
legacy_fit <- suppressWarnings(gt_fit(legacy_panel, c("y", "z"),
  gt_design("item", "rater", random = "item"), gt_family("binary", "logit"),
  covariance = "unstructured", control = gt_control(discrete = list(
    covariance_parameterization = "log_cholesky", maxit = 2L, alternative_starts = 0L))))
legacy_explicit <- gt_laplace_check(legacy_fit, draws = 100L, seed = 71L)
expect(identical(legacy_fit$diagnostics$covariance_parameterization, "log_cholesky"),
       "the fixture records resolved log-Cholesky coordinates")
legacy_fit$control$discrete$covariance_parameterization <- "auto"
legacy_auto <- gt_laplace_check(legacy_fit, draws = 100L, seed = 71L)
legacy_fit$control$discrete$covariance_parameterization <- NULL
legacy_default <- gt_laplace_check(legacy_fit, draws = 100L, seed = 71L)
for (comparison in list(legacy_auto, legacy_default)) {
  expect(isTRUE(comparison$available) && isTRUE(comparison$recomputed_agrees) &&
           abs(comparison$laplace_minus2loglik - legacy_explicit$laplace_minus2loglik) < 1e-10 &&
           abs(comparison$refined_minus2loglik - legacy_explicit$refined_minus2loglik) < 1e-10,
         "saved auto and omitted requests use their recorded covariance coordinates")
}
legacy_fit$diagnostics$covariance_parameterization <- "future_coordinates"
expect(grepl("unsupported covariance parameterization",
             outcome(gt_laplace_check(legacy_fit, draws = 100L, seed = 71L)), fixed = TRUE),
       "unknown recorded coordinates are refused rather than reinterpreted")
cat("PASS: retained response and covariance coordinates, integration and diagnostic safeguards.\n")
