# A constructed panel whose zero object variance is a legitimate optimum.
#
# Run with:
#   source(system.file("examples", "discrete-boundary.R", package = "Gtheory4LLM"))
#
# Everything here is synthetic and needs no data.
library(Gtheory4LLM)
ratings <- expand.grid(occasion = seq_len(12), person = seq_len(8))
ratings$pass <- as.integer(ratings$occasion <= 6L)
design <- gt_design("person", "occasion", random = ~ person)
fit <- gt_fit(ratings, "pass", design, gt_family("binary", "logit"),
  control = gt_control(discrete = list(maxit = 300L, alternative_starts = 2L)))
print(fit)
gt_diagnostics(fit)
gt_components(fit)
# Each person has the same event count. In this constructed example, a zero
# person variance is a legitimate optimum, not evidence of high reliability.
if (isTRUE(fit$numerically_accepted)) {
  # The print methods state that this engine supplies no interval; the
  # underlying $per_trait and $results tables keep the empty columns.
  print(gt_reliability(fit, scale = "latent"))
  print(gt_dstudy(fit, data.frame(occasion = c(6, 12, 24)), scale = "latent"))
}
# The default auto coordinates use direct variances for this univariate model.
# They do not add observed-score reliability, standard errors or intervals of
# any kind, an unstructured boundary solver, or evidence of Laplace
# approximation accuracy. Only Gaussian fits currently supply intervals.
