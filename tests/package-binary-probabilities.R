# Exercise the installed probability-reporting path with controlled predictors.
# Injected eta values test output arithmetic, not empirical fitting accuracy.
library(Gtheory4LLM)
ns <- asNamespace("Gtheory4LLM")
internal <- function(name) get(name, envir = ns, inherits = FALSE)
d <- expand.grid(item = seq_len(8), occasion = seq_len(12))
d$y <- factor(rep(c("absent", "present"), length.out = nrow(d)),
              levels = c("absent", "present"))
design <- gt_design("item", "occasion", random = ~ item)
control <- gt_control(discrete = list(fixed_covariance = list(item = matrix(0, 1, 1))))
eta <- rep(c(-40, -9, -1, 0, 1, 9, 40, 0), length.out = nrow(d))
for (link in c("probit", "logit")) {
  family <- gt_family("binary", link)
  ordinary <- gt_fit(d, "y", design, family, control = control)
  stopifnot(ordinary$numerically_accepted,
            max(abs(ordinary$conditional_probabilities$y - .5)) < 1e-8)

  local <- new.env(parent = ns)
  local$gt_fit <- gt_fit
  environment(local$gt_fit) <- local
  local$.gt_fit_discrete <- internal(".gt_fit_discrete")
  environment(local$.gt_fit_discrete) <- local
  laplace <- internal(".gt_d_laplace")
  local$.gt_d_laplace <- function(..., details = FALSE) {
    result <- laplace(..., details = details)
    if (details && isTRUE(result$valid)) result$eta[, 1L] <- eta
    result
  }
  fit <- local$gt_fit(d, "y", design, family, control = control)
  probabilities <- fit$conditional_probabilities$y
  cdf <- if (link == "probit") stats::pnorm else stats::plogis
  expected <- cbind(cdf(eta, lower.tail = FALSE), cdf(eta))
  # Relative checks on positive tails catch cancellation that an ordinary
  # absolute tolerance would silently regard as equivalent to zero.
  positive <- expected > 0
  stopifnot(fit$numerically_accepted,
            identical(dim(probabilities), c(nrow(d), 2L)),
            identical(colnames(probabilities), levels(d$y)),
            all(is.finite(probabilities)), all(probabilities >= 0),
            all(probabilities <= 1),
            max(abs(rowSums(probabilities) - 1)) < 1e-15,
            all(probabilities[positive] > 0),
            max(abs(probabilities[positive] / expected[positive] - 1)) < 1e-12,
            all(probabilities[!positive] == 0),
            identical(fit$minus2loglik, ordinary$minus2loglik))
  if (link == "probit") stopifnot(
    all(abs(probabilities[eta == 9, 1L] / 1.1285884059538408e-19 - 1) < 1e-12))
  if (link == "logit") stopifnot(
    all(abs(probabilities[eta == 40, 1L] / 4.2483542552915889e-18 - 1) < 1e-12))
}
cat("PASS: installed binary output retains both tails, category order, and ordinary probabilities for probit and logit.\n")
