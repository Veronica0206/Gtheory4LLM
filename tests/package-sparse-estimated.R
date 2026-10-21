# Installed estimated nominal and call covariance regressions.
# The frozen 108/120-row source fixtures and numerical tolerances are unchanged.
library(Gtheory4LLM)
expect <- function(ok, message) if (!isTRUE(ok)) stop(message)
# Estimated nominal variances, including exact zero boundaries. The outcomes
# are fixed bytes from the existing seed-901 test fixture, not regenerated.
nominal_data <- expand.grid(item = seq_len(12L), rater = seq_len(3L), rep = seq_len(3L))
codes <- c(2, 2, 1, 2, 2, 2, 1, 3, 3, 3, 2, 2, 3, 2, 3,
  2, 2, 1, 2, 3, 2, 2, 1, 1, 2, 1, 1, 1, 2, 3, 1,
  1, 2, 2, 2, 2, 2, 2, 3, 1, 3, 2, 2, 1, 3, 3, 3,
  1, 2, 1, 2, 2, 1, 3, 2, 3, 3, 3, 1, 2, 1, 2, 1,
  1, 2, 1, 3, 3, 1, 3, 1, 2, 3, 1, 1, 2, 1, 1, 1,
  3, 3, 1, 1, 1, 2, 1, 1, 2, 1, 1, 1, 2, 3, 2, 3,
  2, 1, 1, 2, 3, 1, 3, 1, 1, 2, 1, 3, 3)
nominal_data$y <- factor(c("a", "b", "c")[codes], levels = c("a", "b", "c"))
nominal_fit <- function(engine) gt_fit(nominal_data, "y",
  gt_design("item", "rater", random = c("item", "rater"), replicates = 3),
  gt_family("categorical", levels = c("a", "b", "c"), reference = "a"), covariance = "diagonal",
  control = gt_control(discrete = list(engine = engine, optimizer = "nlminb", maxit = 200)))
dense_estimated <- nominal_fit("dense")
sparse_estimated <- nominal_fit("sparse")
expect(gt_diagnostics(dense_estimated)$numerically_accepted && gt_diagnostics(sparse_estimated)$numerically_accepted,
       "Estimated nominal fits pass all acceptance checks")
expect(abs(-2 * as.numeric(logLik(dense_estimated)) - -2 * as.numeric(logLik(sparse_estimated))) < 1e-6 &&
       max(abs(unlist(gt_components(dense_estimated)) -
                 unlist(gt_components(sparse_estimated)))) < 1e-4,
       "Nominal variance estimates and objective agree with dense")
expect(gt_components(sparse_estimated)$item[2, 2] > 0.1 &&
       length(gt_diagnostics(sparse_estimated)$diagnostics$zero_variance_parameters) > 0,
       "The estimated fixture exercises positive and exact-zero source variances")
cat("PASS: estimated sparse nominal variances and boundaries match dense.\n")

# Estimated call covariance: fixed responses from a seed-842 synthetic panel.
call_data <- expand.grid(item = seq_len(24L), rater = seq_len(5L))
call_data$call_id <- paste(ceiling(call_data$item / 4), call_data$rater, sep = "-")
call_data$y <- c(1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1,
  1, 0, 1, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0, 1, 1, 1,
  0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1,
  1, 1, 0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 0,
  1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1,
  1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 1,
  0, 0, 1, 0, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0,
  0, 1, 0, 1, 1, 0, 1, 0, 0)
call_fit <- function(engine) gt_fit(call_data, "y",
  gt_design("item", "rater", random = c("item", "rater"), batch = gt_batch(4, id = "call_id")),
  gt_family("binary", "logit"),
  control = gt_control(discrete = list(engine = engine, optimizer = "nlminb", maxit = 200)))
dense_call <- call_fit("dense")
sparse_call <- call_fit("sparse")
expect(gt_diagnostics(dense_call)$numerically_accepted && gt_diagnostics(sparse_call)$numerically_accepted &&
       gt_components(sparse_call)$Call[1, 1] > 0.1,
       "A nonzero call variance is estimated and numerically accepted")
expect(abs(-2 * as.numeric(logLik(dense_call)) - -2 * as.numeric(logLik(sparse_call))) < 1e-6 &&
       max(abs(unlist(gt_components(dense_call)) -
                 unlist(gt_components(sparse_call)))) < 1e-4,
       "Estimated call variance and objective agree with dense")
if (requireNamespace("lme4", quietly = TRUE)) {
  reference <- lme4::glmer(y ~ 1 + (1 | item) + (1 | rater) + (1 | call_id),
    call_data, family = stats::binomial(), nAGQ = 1,
    control = lme4::glmerControl(optimizer = "bobyqa", optCtrl = list(rhoend = 1e-9),
                                check.conv.singular = "ignore"))
  reference_variances <- as.data.frame(lme4::VarCorr(reference))
  reference_variances$grp[reference_variances$grp == "call_id"] <- "Call"
  reference_variances <- setNames(reference_variances$vcov, reference_variances$grp)
  actual <- vapply(gt_components(sparse_call), function(S) S[1, 1], numeric(1))
  expect(reference@optinfo$conv$opt == 0 && is.null(reference@optinfo$conv$lme4$messages),
         "The independent glmer reference converges")
  expect(abs(-2 * as.numeric(logLik(sparse_call)) + 2 * as.numeric(logLik(reference))) < 1e-5 &&
         max(abs(actual - reference_variances[names(actual)])) < 1e-3,
         "Sparse call likelihood and variances agree with independent glmer Laplace fitting")
} else cat("SKIP: optional independent lme4 call-likelihood comparison.\n")
cat("PASS: estimated sparse call covariance, dense parity, and available external reference.\n")
