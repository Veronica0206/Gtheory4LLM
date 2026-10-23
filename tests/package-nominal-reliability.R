# Installed nominal latent coefficients: a real estimated covariance fit and
# independent generalized-eigenvalue boundary oracles through public APIs.
library(Gtheory4LLM)
expect <- function(ok, label) if (!isTRUE(ok)) stop(label)

set.seed(20261022)
labels <- c("a", "b", "c")
n_item <- 12L; n_rater <- 3L; n_rep <- 3L
panel <- expand.grid(item = factor(seq_len(n_item)), rater = factor(seq_len(n_rater)),
  rep = factor(seq_len(n_rep)))
item_utility <- matrix(rnorm(n_item * 3L, sd = .9), n_item, 3L)
rater_utility <- matrix(rnorm(n_rater * 3L, sd = .4), n_rater, 3L)
utility <- item_utility[as.integer(panel$item), ] + rater_utility[as.integer(panel$rater), ] +
  matrix(-log(-log(runif(nrow(panel) * 3L))), nrow(panel), 3L)
panel$y <- factor(labels[max.col(utility)], levels = labels)
fit <- gt_fit(panel, "y", gt_design("item", "rater", random = c("item", "rater"),
  replicates = n_rep), family = gt_family("categorical", levels = labels, reference = "a"),
  covariance = "exchangeable")
expect(gt_diagnostics(fit)$numerically_accepted,
  "The installed exchangeable nominal fit passes numerical acceptance")
components <- gt_components(fit)
sigma2 <- components$item[1, 1] / 2
expect(sigma2 > .1, "The item signal is estimated and nonzero")
co <- as.data.frame(gt_reliability(fit, scale = "latent"))
expected <- sigma2 / (sigma2 + (pi^2 / 6) / (n_rater * n_rep))
expect(abs(co$Erho2 - expected) < 1e-12 && co$latent_dimensions == 2L &&
  abs(co$Erho2_min - co$Erho2_max) < 1e-12,
  "The estimated exchangeable coefficient matches its independent utility-scale formula")

# This test-only accepted-model fixture supplies a known rank-one source law;
# it is not evidence of fitting or qualification of huge allocation sizes.
# U = diag(1,0), E = (pi^2/6)(I+11')/m has eigenvalues
# {1/(1 + pi^2/(4m)), 0}, obtained by a two-by-two Schur complement.
dimensions <- c("y:b_vs_a", "y:c_vs_a")
M <- diag(c(1, 0)); dimnames(M) <- list(dimensions, dimensions)
known <- structure(list(data = expand.grid(item = 1:4, rater = 1:2),
  design = gt_design("item", "rater", random = c("item", "rater")),
  outcomes = "y", families = list(y = gt_family("categorical", levels = labels, reference = "a")),
  covariance_components = list(item = M, rater = M * 0), covariance = "unstructured",
  link_dimensions = data.frame(outcome = "y", family = "categorical", link = "softmax",
    dimension = dimensions, category = c("b", "c"), reference = "a"),
  converged = TRUE, numerically_accepted = TRUE), class = "gt_fit")
grid <- data.frame(rater = c(2, 4, 1e17, 1e200))
projected <- as.data.frame(gt_dstudy(known, grid, scale = "latent"))
expected <- 1 / (2 * (1 + pi^2 / (4 * grid$rater)))
expect(nrow(projected) == nrow(grid) && max(abs(projected$Erho2 - expected)) < 1e-12 &&
  all(abs(projected$Erho2_min) < 1e-12) &&
  identical(projected$measurement_count_exact, c(TRUE, TRUE, FALSE, FALSE)),
  "A singular universe preserves its zero eigenvalue at finite large allocations")

# A covariance whose small error is lost at machine precision is explicitly
# unavailable, while the remaining supplied allocations still return normally.
known$covariance_components$item[,] <- 1
unresolved <- as.data.frame(gt_dstudy(known, data.frame(rater = c(2, 1e200)), scale = "latent"))
expect(is.finite(unresolved$Erho2[1]) && is.na(unresolved$Erho2[2]) &&
  is.na(unresolved$Erho2_min[2]) && is.na(unresolved$Erho2_max[2]),
  "An unresolved total covariance retains its row with unavailable coefficients")
cat("PASS: installed estimated nominal exchangeability, exact-zero eigenvalue and finite-allocation projection guards.\n")
