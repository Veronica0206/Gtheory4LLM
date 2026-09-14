# Installed-package checks; no source(), repository paths, or raw CSV dependency.
library(Gtheory4LLM)
expected_exports <- c("gt_design", "gt_family", "gt_control", "gt_score", "gt_fit",
                      "gt_components", "gt_component_vcov", "gt_reliability", "gt_dstudy",
                      "gt_diagnostics", "gt_example", "gt_preflight")
stopifnot(setequal(getNamespaceExports("Gtheory4LLM"), expected_exports))
stopifnot(is.function(getS3method("print", "gt_fit")),
          is.function(getS3method("summary", "gt_fit")),
          is.function(getS3method("print", "summary.gt_fit")),
          is.function(getS3method("plot", "gt_dstudy")))
catalog <- gt_example()
stopifnot(nrow(catalog) == 8L)
for (name in catalog$name) {
  native <- gt_example(name)
  stopifnot(nrow(native$data) == 21600L,
    identical(names(native$data), c(native$object, native$facets, native$outcomes)),
    !anyNA(native$data), file.exists(native$source),
    startsWith(normalizePath(native$source), normalizePath(system.file(package = "Gtheory4LLM"))),
    identical(native$source_provenance$data_kind, "public_llm_annotations"))
  dimensions <- c(native$object, native$facets)
  counts <- vapply(native$data[dimensions], function(x) length(unique(x)), integer(1))
  stopifnot(nrow(native$data) == prod(counts), !anyDuplicated(native$data[dimensions]))
  if (name != "mental_health_nominal") {
    scored <- gt_example(name, coding = "manuscript")
    stopifnot(all(vapply(scored$data[scored$outcomes], is.numeric, logical(1))),
      identical(native$data[c(native$object, native$facets)], scored$data[c(scored$object, scored$facets)]))
  }
  for (outcome in native$outcomes) {
    family <- native$families[[outcome]]$family
    value <- native$data[[outcome]]
    if (family == "ordinal") stopifnot(is.ordered(value))
    if (family == "categorical") stopifnot(is.factor(value), !is.ordered(value))
    if (family == "binary") stopifnot(all(value %in% c(0, 1)))
    if (family == "gaussian") stopifnot(is.numeric(value))
  }
}
cat("PASS: installed exports, registered methods, and all real LLM annotation codings.\n")

d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design, control = gt_control(gaussian =
  list(check_hessian = FALSE, retry_seed = 42, extra_tries = 2)))
stopifnot(fit$numerically_accepted,
          gt_diagnostics(fit)$diagnostics$independent_likelihood_matches,
          identical(names(gt_components(fit)), c("item", "rater", "Residual")),
          is.list(summary(fit)))
reliability <- gt_reliability(fit, score = gt_score(c(score = 1)))
stopifnot(all(reliability$per_trait$Erho2 >= 0), all(reliability$per_trait$Erho2 <= 1),
          all(reliability$per_trait$Phi <= reliability$per_trait$Erho2))
study <- gt_dstudy(fit, data.frame(rater = c(2, 3, 6)))
stopifnot(inherits(study, "gt_dstudy"), nrow(study$results) == 3L)
print(fit)
cat("PASS: installed Gaussian fit, diagnostics, source extraction, composite, and D study.\n")

# With zero fixed random covariance the discrete marginal models reduce to
# independently checkable intercept-only categorical likelihoods.
d <- expand.grid(item = 1:8, rater = 1:3, occasion = 1:2)
d$binary <- rep(c(0L, 0L, 1L), length.out = nrow(d))
d$ordinal <- ordered(rep(c("low", "middle", "high"), length.out = nrow(d)),
                     levels = c("low", "middle", "high"))
d$nominal <- factor(rep(c("red", "blue", "blue", "green"), length.out = nrow(d)),
                    levels = c("red", "blue", "green"))
design <- gt_design("item", c("rater", "occasion"), random = ~ item + rater)
fixed <- function(q) gt_control(discrete = list(fixed_covariance =
  list(item = matrix(0, q, q), rater = matrix(0, q, q))))
check_likelihood <- function(fit, response) {
  n <- table(response)
  expected <- -2 * sum(n * log(n / sum(n)))
  stopifnot(fit$numerically_accepted, abs(fit$minus2loglik - expected) < 1e-6)
}
binary <- gt_fit(d, "binary", design, gt_family("binary", "logit"), control = fixed(1))
ordinal <- gt_fit(d, "ordinal", design, gt_family("ordinal"), control = fixed(1))
nominal <- gt_fit(d, "nominal", design, gt_family("categorical", reference = "blue"), control = fixed(2))
check_likelihood(binary, d$binary)
check_likelihood(ordinal, d$ordinal)
check_likelihood(nominal, d$nominal)
joint <- gt_fit(d, c("binary", "ordinal"), design,
  list(binary = gt_family("binary", "logit"), ordinal = gt_family("ordinal")), control = fixed(2))
stopifnot(joint$numerically_accepted,
  abs(joint$minus2loglik - binary$minus2loglik - ordinal$minus2loglik) < 1e-6)
cat("PASS: installed binary, ordinal, nominal, and joint discrete likelihood identities.\n")
