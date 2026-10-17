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
expect(abs(importance$refined_minus2loglik - check$refined_minus2loglik) < 4 * importance$mc_se + 1e-6,
       "importance sampling agrees with quadrature within its error")
expect(identical(gt_laplace_check(fit, method = "importance", draws = 20000, seed = 7)$refined_minus2loglik,
                 importance$refined_minus2loglik), "a seeded check is reproducible")

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
expect(any(grepl("Laplace approximation check | quadrature", printed, fixed = TRUE)) &&
         any(grepl("Usable:", printed, fixed = TRUE)) &&
         any(grepl("not bias in the estimates", printed, fixed = TRUE)) &&
         identical(withVisible(print(check))$visible, FALSE), "the print names the method, the verdict and its scope")
cat("PASS: the Laplace check matches an independent integration, importance sampling matches quadrature, and refusals hold.\n")
