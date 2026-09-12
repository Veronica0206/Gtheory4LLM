# Run after installing the development branch. No manuscript datasets required.
library(Gtheory4LLM)
ratings <- expand.grid(occasion = seq_len(12), person = seq_len(8))
ratings$pass <- as.integer(ratings$occasion <= 6L)
design <- gt_design("person", "occasion", random = ~ person)
fit <- gt_fit(ratings, "pass", design, gt_family("binary", "logit"),
  control = gt_control(discrete = list(covariance_parameterization = "variance",
                                      maxit = 300L, alternative_starts = 2L)))
print(fit)
gt_diagnostics(fit)
gt_components(fit)
# Each person has the same event count. In this constructed example, a zero
# person variance is a legitimate optimum, not evidence of high reliability.
if (isTRUE(fit$numerically_accepted)) {
  print(gt_reliability(fit, scale = "latent")$per_trait)
  print(gt_dstudy(fit, data.frame(occasion = c(6, 12, 24)), scale = "latent")$results)
}
# This opt-in mode does not add observed-score reliability, confidence intervals,
# an unstructured boundary solver, or evidence of Laplace approximation accuracy.
