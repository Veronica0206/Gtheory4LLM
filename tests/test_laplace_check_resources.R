# Run from the project directory with Rscript tests/test_laplace_check_resources.R.
#
# gt_laplace_check() budgets its whole workspace, the dense reconstruction of
# the model plus the quadrature grid or the importance-draw matrix, against
# the fit's dense budget before it allocates anything. A budget that the
# estimate exceeds is refused by name; a normal budget records the estimate.
source("load_functions.R")
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
outcome <- function(expr) tryCatch({ force(expr); "accepted" }, error = conditionMessage)

set.seed(11)
b <- expand.grid(item = 1:3, rater = 1:8)
b$y <- rbinom(nrow(b), 1, plogis(c(-1, 0.2, 1.1)[b$item]))
fit <- gt_fit(b, "y", gt_design("item", "rater", random = ~ item), gt_family("binary", "logit"),
              control = gt_control(discrete = list(maxit = 200L)))
expect(isTRUE(fit$numerically_accepted), "the item-only fixture is accepted")

quadrature <- gt_laplace_check(fit, nodes = 5L)
expect(is.list(quadrature$resources) && is.finite(quadrature$resources$total) &&
         quadrature$resources$total > 0 && quadrature$resources$integration > 0 &&
         quadrature$resources$max_dense_bytes == .gt_d_control(fit$control$discrete)$max_dense_bytes,
       "a quadrature comparison records its workspace estimate against the dense budget")
importance <- gt_laplace_check(fit, method = "importance", draws = 1000L, seed = 1L)
expect(importance$resources$integration >= 8 * 1000 * importance$random_dimension,
       "the importance estimate includes the draws-by-dimension matrix")

# The estimate for the same comparison exceeds a budget of 6,000 bytes.
estimate <- .gt_laplace_resources(nrow(b), 1L, 3L, "importance", 20L, 1000L)
expect(estimate$total > 6000, "the probe budget is below the estimate")
starved <- fit
starved$control$discrete$max_dense_bytes <- 6000
refused <- outcome(gt_laplace_check(starved, method = "importance", draws = 1000L, seed = 1L))
expect(grepl("exceeding max_dense_bytes", refused, fixed = TRUE), "an over-budget comparison is refused by name")
refused <- outcome(gt_laplace_check(starved, nodes = 5L))
expect(grepl("exceeding max_dense_bytes", refused, fixed = TRUE), "an over-budget quadrature comparison is refused too")
cat("PASS: gt_laplace_check() estimates its workspace and refuses over-budget comparisons before allocation.\n")
