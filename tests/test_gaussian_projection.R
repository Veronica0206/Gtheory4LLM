# Future balanced allocations are distinct from irregular observed averages.
source("load_functions.R")
set.seed(71)
d <- expand.grid(item = 1:20, rater = 1:4, occasion = 1:3)
d$y <- rnorm(20)[d$item] + rnorm(4, sd = .8)[d$rater] +
  rnorm(3, sd = .5)[d$occasion] + rnorm(nrow(d), sd = .4)
d <- d[-seq(3, nrow(d), by = 8), ]
fit <- gt_fit(d, y ~ item + rater + occasion, measured = "item",
  control = gt_control(gaussian = list(engine = "lme4", panel = "observed")))
stopifnot(fit$numerically_accepted)
expect_error <- function(expression, pattern) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}
expect_error(gt_reliability(fit), "complete balanced")
expect_error(gt_dstudy(fit, data.frame(rater = 4, occasion = 3)), "complete balanced")
expect_error(gt_dstudy(fit, data.frame(rater = 4), projection = "balanced"), "every facet")
expect_error(gt_dstudy(fit, data.frame(rater = 4, occasion = 3), fixed = "rater",
  projection = "balanced"), "all facets random")
grid <- data.frame(rater = c(4, 8), occasion = c(3, 6))
study <- gt_dstudy(fit, grid, projection = "balanced")
table <- as.data.frame(study)
components <- gt_components(fit)
variance <- vapply(fit$covariance_components, function(x) x[1, 1], numeric(1))
# Independent allocation definition for additive random intercepts:
# relative error is residual / (raters * occasions); absolute error adds
# the two instrumentation main-effect variances divided by their counts.
relative <- variance[["Residual"]] / (grid$rater * grid$occasion)
absolute <- relative + variance[["rater"]] / grid$rater + variance[["occasion"]] / grid$occasion
stopifnot(max(abs(table$Erho2 - variance[["item"]] / (variance[["item"]] + relative))) < 1e-12,
  max(abs(table$Phi - variance[["item"]] / (variance[["item"]] + absolute))) < 1e-12,
  all(table$projection_target == "intended_complete_balanced"),
  all(nzchar(table$projection_assumptions)), !any(table$uncertainty_available))
retained <- fit
retained$data <- NULL
stopifnot(identical(table, as.data.frame(gt_dstudy(retained, grid, projection = "balanced"))))
cat("PASS: explicit future-panel projection, independent allocation weights, retained assumptions and refusals.\n")
