# Public extractor and report contracts on a genuine fitted information record.
source("load_functions.R")
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}
d <- expand.grid(item = seq_len(12), rater = seq_len(4))
d$y <- rep(c(1, 0, 1, 0, 1, 1, 0, 1), 6)
fixed <- list(item = matrix(0, 1, 1), rater = matrix(0, 1, 1))
fit <- gt_fit(y ~ item + rater, d, measured = "item", family = gt_family("binary", link = "logit"),
  control = gt_control(discrete = list(fixed_covariance = fixed,
    optimizer = "nlminb", check_hessian = TRUE)))
stopifnot(fit$numerically_accepted, fit$uncertainty$available)
reference <- stats::glm(y ~ 1, data = d, family = stats::binomial())
parameters <- gt_component_vcov(fit, type = "parameters")
components <- gt_component_vcov(fit)
stopifnot(abs(parameters[1, 1] - stats::vcov(reference)[1, 1]) < 1e-5,
          identical(rownames(parameters), names(fit$parameters)),
          identical(rownames(components), c("item[y,y]", "rater[y,y]")),
          identical(rownames(components), colnames(components)), all(components == 0),
          setequal(attr(components, "conditional_on_fixed"), names(fixed)),
          attr(components, "hessian_scale") == "negative_log_likelihood",
          grepl("coverage not established", attr(components, "approximation"), fixed = TRUE),
          grepl("nuisance", attr(parameters, "scope"), fixed = TRUE))
expect_error(stats::vcov(fit), "extractor matching coef()")
latent <- gt_reliability(fit, scale = "latent")
stopifnot(latent$uncertainty$available, all(latent$per_trait$Erho2 == 0),
          setequal(latent$uncertainty$fixed_components, names(fixed)))
report <- gt_report(fit, reliability = latent)
stopifnot(report$uncertainty$available,
          grepl("conditional on first-order Laplace", report$uncertainty$scope, fixed = TRUE),
          grepl("finite-sample coverage is not established", report$uncertainty$scope, fixed = TRUE),
          !grepl("point estimates only", report$uncertainty$scope, fixed = TRUE))

without <- gt_fit(y ~ item + rater, d, measured = "item", family = gt_family("binary", link = "logit"),
  control = gt_control(discrete = list(fixed_covariance = fixed, optimizer = "nlminb")))
stopifnot(without$numerically_accepted, !without$uncertainty$available)
expect_error(gt_component_vcov(without), "not requested")
stopifnot(!gt_report(without)$uncertainty$available,
          grepl("intervals are unavailable", gt_report(without)$uncertainty$scope, fixed = TRUE))
boundary <- fit
boundary$uncertainty <- .gt_d_information_unavailable("A source covariance is on its boundary.", "item")
expect_error(gt_component_vcov(boundary), "on its boundary")
broken <- fit
broken$uncertainty$entries <- NULL
expect_error(gt_component_vcov(broken), "no matching entry labels")
cat("PASS: discrete full-information public covariance, fixed assumptions, GLM comparison, report qualifications and unavailable cases.\n")
