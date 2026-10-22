# Run from the project directory with Rscript tests/test_nominal_planning.R.
#
# gt_plan() on fits with nominal contrast dimensions. A three-category nominal
# outcome spans two latent dimensions, so weights built one per outcome did not
# conform to the covariance matrices and every plan failed, including a plan
# for the binary outcome of a joint nominal-and-binary fit. Checks:
#
#   * a nominal outcome plans on its mean generalized-eigenvalue coefficient,
#     matching gt_dstudy(), with the scalar decomposition unavailable and said so;
#   * the binary outcome of a joint fit plans on its own dimension: its universe
#     and error variances reproduce its coefficient.
source("load_functions.R")
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
set.seed(20261022)
labels <- c("a", "b", "c"); n_item <- 30L; n_rater <- 4L; n_rep <- 3L
panel <- expand.grid(item = factor(seq_len(n_item)), rater = factor(seq_len(n_rater)), rep = factor(seq_len(n_rep)))
item_utility <- matrix(rnorm(n_item * 3L, sd = 0.9), n_item, 3L)
rater_utility <- matrix(rnorm(n_rater * 3L, sd = 0.4), n_rater, 3L)
utility <- item_utility[as.integer(panel$item), ] + rater_utility[as.integer(panel$rater), ] +
  matrix(-log(-log(runif(nrow(panel) * 3L))), nrow(panel), 3L)
panel$y <- factor(labels[max.col(utility)], levels = labels)
panel$z <- factor(ifelse(utility[, 2L] + rnorm(nrow(panel)) > 0.5, "1", "0"), levels = c("0", "1"))
design <- gt_design("item", "rater", random = c("item", "rater"), replicates = n_rep)
nominal <- gt_family("categorical", levels = labels, reference = "a")
grid <- data.frame(rater = c(1, 2, 4))
plan <- function(fit, outcome) gt_plan(fit, grid, data.frame(expected_cost = c(1, 2, 4)), currency = "USD",
  cost_date = "2026-10-22", study_items = 30, target = 0.5, outcome = outcome, scale = "latent")
dstudy <- function(fit, outcome) { d <- as.data.frame(gt_dstudy(fit, grid, scale = "latent")); d[d$outcome == outcome, ] }

for (covariance in c("unstructured", "exchangeable")) {
  fit <- suppressWarnings(gt_fit(panel, "y", design = design, family = nominal, covariance = covariance))
  expect(isTRUE(fit$numerically_accepted), paste(covariance, "nominal fit is accepted"))
  p <- plan(fit, "y")
  expect(isTRUE(all.equal(p$results$Erho2, dstudy(fit, "y")$Erho2)) && isTRUE(all.equal(p$results$Phi, dstudy(fit, "y")$Phi)),
         paste(covariance, "nominal plan screens on the coefficient gt_dstudy() reports"))
  expect(all(is.na(p$results[c("universe_variance", "relative_error", "absolute_error")])) &&
           all(is.na(p$source_contributions$universe)) && startsWith(p$provenance$decomposition, "unavailable"),
         paste(covariance, "nominal plan reports its scalar decomposition as unavailable"))
}

joint <- suppressWarnings(gt_fit(panel, c("y", "z"), design = design,
  family = list(y = nominal, z = gt_family("binary", "logit", levels = c("0", "1"))), covariance = "exchangeable"))
expect(isTRUE(joint$numerically_accepted), "the joint nominal-and-binary fit is accepted")
pz <- plan(joint, "z")
expect(isTRUE(all.equal(pz$results$Erho2, dstudy(joint, "z")$Erho2)), "the binary plan matches gt_dstudy()")
expect(isTRUE(all.equal(pz$results$universe_variance / (pz$results$universe_variance + pz$results$relative_error),
                        pz$results$Erho2)) && startsWith(pz$provenance$decomposition, "scalar"),
       "the binary outcome's universe and error variances reproduce its coefficient, so its weight is on its own dimension")
py <- plan(joint, "y")
expect(isTRUE(all.equal(py$results$Erho2, dstudy(joint, "y")$Erho2)) && all(is.na(py$results$universe_variance)),
       "the nominal outcome of the joint fit plans on its coefficient without a scalar decomposition")
cat("PASS: gt_plan() plans nominal and mixed nominal fits on their latent dimensions.\n")
