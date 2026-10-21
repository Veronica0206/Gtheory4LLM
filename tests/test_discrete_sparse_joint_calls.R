# Small joint and call fixtures compare fitted sparse likelihoods with dense.
source("load_functions.R")
expect <- function(ok, message) if (!isTRUE(ok)) stop(message)
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  expect(inherits(error, "error") && grepl(pattern, conditionMessage(error)),
         paste("Expected refusal containing", pattern))
}
data <- expand.grid(item = seq_len(12L), rater = seq_len(4L))
data$binary <- as.integer((data$item + 2 * data$rater) %% 5 < 2)
data$ordinal <- ordered(c("low", "middle", "high")[(data$item + data$rater) %% 3 + 1L],
                        levels = c("low", "middle", "high"))
data$nominal <- factor(c("a", "b", "c")[(floor(data$item / 4) + data$rater) %% 3 + 1L],
                       levels = c("a", "b", "c"))
# Explicit observed call IDs repeat across members of each batch-condition.
data$call_id <- paste(ceiling(data$item / 3), data$rater, sep = "-")
families <- list(binary = gt_family("binary", "logit"),
  ordinal = gt_family("ordinal", "probit", levels = levels(data$ordinal)),
  nominal = gt_family("categorical", levels = levels(data$nominal), reference = "a"))
for (spec in list(list(outcomes = "nominal", call = FALSE),
                 list(outcomes = c("binary", "ordinal"), call = FALSE),
                 list(outcomes = c("binary", "nominal"), call = FALSE),
                 list(outcomes = "binary", call = TRUE),
                 list(outcomes = "ordinal", call = TRUE),
                 list(outcomes = "nominal", call = TRUE))) {
  design <- gt_design("item", "rater", random = c("item", "rater"),
    batch = if (spec$call) gt_batch(size = 3, id = "call_id") else NULL)
  q <- sum(ifelse(spec$outcomes == "nominal", 2L, 1L))
  covariance <- matrix(0.05, q, q) + diag(0.25, q)
  fixed <- list(item = covariance, rater = covariance / 2)
  if (spec$call) fixed$Call <- covariance / 3
  fit <- function(engine) gt_fit(data, spec$outcomes, design, families[spec$outcomes],
    control = gt_control(discrete = list(engine = engine, optimizer = "nlminb", fixed_covariance = fixed)))
  dense <- fit("dense")
  sparse <- fit("sparse")
  label <- paste(paste(spec$outcomes, collapse = "+"), if (spec$call) "with calls" else "without calls")
  expect(isTRUE(dense$numerically_accepted) && isTRUE(sparse$numerically_accepted),
         paste(label, "both fits satisfy acceptance"))
  expect(abs(dense$minus2loglik - sparse$minus2loglik) < 1e-6,
         paste(label, "fitted likelihood agrees with dense"))
  expect(max(abs(dense$conditional_eta - sparse$conditional_eta)) < 1e-4,
         paste(label, "fitted conditional predictors agree with dense"))
  if ("nominal" %in% spec$outcomes)
    expect(max(abs(rowSums(sparse$conditional_probabilities$nominal) - 1)) < 1e-12,
           "Nominal probabilities sum to one")
  if (spec$call) {
    expect(isTRUE(sparse$design$batch_model$modelled) && "Call" %in% names(sparse$covariance_components),
           "A declared valid layout is fitted and reports Call covariance")
    expect(identical(sparse$design$batch_model$item_levels, seq_len(12L)) &&
           identical(as.integer(sparse$design$batch_model$item_batches), rep(seq_len(4L), each = 3L)),
           "Fixed item-to-batch membership is retained")
    grouping <- .gt_d_call_group(data, design, .gt_batch_model(data, design))
    expect(identical(outer(grouping$index, grouping$index, `==`),
                     outer(data$call_id, data$call_id, `==`)),
           "Call groups agree with independently recorded call IDs")
    expect(sparse$group_counts[["Call"]] == 16L, "One independent call per batch and condition")
  }
  cat("PASS:", label, "\n")
}

# Permuting row order cannot change recorded calls or the likelihood.
reverse <- data[nrow(data):1L, ]
reversed <- gt_fit(reverse, "nominal", design, families["nominal"],
  control = gt_control(discrete = list(engine = "sparse", optimizer = "nlminb", fixed_covariance = fixed)))
expect(abs(reversed$minus2loglik - sparse$minus2loglik) < 1e-6, "Call fitting is row-order invariant")

# A size-one call is observation-specific and cannot be estimated on a fixed latent scale.
expect_error(gt_design("item", "rater", random = c("item", "rater"),
                        batch = gt_batch(size = 1, order = "item")), "at least 2")

# Fixed zero sources reduce to independent multinomial likelihood, an external oracle.
independent <- gt_fit(data, "nominal", gt_design("item", "rater", random = c("item", "rater")),
  families$nominal, control = gt_control(discrete = list(engine = "sparse",
    fixed_covariance = list(item = matrix(0, 2L, 2L), rater = matrix(0, 2L, 2L)))))
frequencies <- table(data$nominal)
oracle <- -2 * sum(frequencies * log(frequencies / sum(frequencies)))
expect(abs(independent$minus2loglik - oracle) < 1e-7, "Zero-covariance nominal likelihood is exact")
cat("PASS: sparse joint, nominal, fixed-layout calls, ordering, and independent zero-source oracle.\n")

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
expect(dense_estimated$numerically_accepted && sparse_estimated$numerically_accepted,
       "Estimated nominal fits pass all acceptance checks")
expect(abs(dense_estimated$minus2loglik - sparse_estimated$minus2loglik) < 1e-6 &&
       max(abs(unlist(dense_estimated$covariance_components) -
                 unlist(sparse_estimated$covariance_components))) < 1e-4,
       "Nominal variance estimates and objective agree with dense")
expect(sparse_estimated$covariance_components$item[2, 2] > 0.1 &&
       length(sparse_estimated$diagnostics$zero_variance_parameters) > 0,
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
expect(dense_call$numerically_accepted && sparse_call$numerically_accepted &&
       sparse_call$covariance_components$Call[1, 1] > 0.1,
       "A nonzero call variance is estimated and numerically accepted")
expect(abs(dense_call$minus2loglik - sparse_call$minus2loglik) < 1e-6 &&
       max(abs(unlist(dense_call$covariance_components) -
                 unlist(sparse_call$covariance_components))) < 1e-4,
       "Estimated call variance and objective agree with dense")
if (requireNamespace("lme4", quietly = TRUE)) {
  reference <- lme4::glmer(y ~ 1 + (1 | item) + (1 | rater) + (1 | call_id),
    call_data, family = stats::binomial(), nAGQ = 1,
    control = lme4::glmerControl(optimizer = "bobyqa", optCtrl = list(rhoend = 1e-9),
                                check.conv.singular = "ignore"))
  reference_variances <- as.data.frame(lme4::VarCorr(reference))
  reference_variances$grp[reference_variances$grp == "call_id"] <- "Call"
  reference_variances <- setNames(reference_variances$vcov, reference_variances$grp)
  actual <- vapply(sparse_call$covariance_components, function(S) S[1, 1], numeric(1))
  expect(reference@optinfo$conv$opt == 0 && is.null(reference@optinfo$conv$lme4$messages),
         "The independent glmer reference converges")
  expect(abs(sparse_call$minus2loglik + 2 * as.numeric(logLik(reference))) < 1e-5 &&
         max(abs(actual - reference_variances[names(actual)])) < 1e-3,
         "Sparse call likelihood and variances agree with independent glmer Laplace fitting")
} else cat("SKIP: optional independent lme4 call-likelihood comparison.\n")
cat("PASS: estimated sparse call covariance, dense parity, and available external reference.\n")
