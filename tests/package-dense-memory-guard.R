# Installed-package checks for the discrete dense-memory guard.
#
# The other discrete limits bound counts. This one bounds the dense algebra
# those counts imply, and it is the limit that protects a caller who raises the
# others. It must refuse before allocating, say what it refused and why, and
# never change the result of a model it permits.
library(Gtheory4LLM)

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
expect_error <- function(expr, pattern, label) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  expect(inherits(error, "error"), paste(label, "raises an error"))
  expect(grepl(pattern, conditionMessage(error)), paste(label, ": ", pattern))
  conditionMessage(error)
}

set.seed(3)
panel <- expand.grid(rater = factor(1:6), item = factor(1:18))
panel$label <- rbinom(nrow(panel), 1L, plogis(rnorm(18, sd = .8)[panel$item]))
design <- gt_design("item", "rater", full_cell = FALSE)

# --- The default limit permits every model the other limits permit ----------
report <- gt_preflight(panel, "label", design, gt_family("binary"))
expect("dense_memory_limit" %in% report$checks$check, "preflight reports the memory check")
expect(all(report$checks$passed), "a small design passes every structural and resource check")
expect(report$resources$dense_working_bytes_estimate > 0,
       "preflight reports a positive dense working estimate")
expect(report$resources$max_dense_bytes == 512 * 1024^2, "the default limit is 512 MiB")
breakdown <- report$resources$dense_working_bytes_breakdown
for (part in c("random_design", "conditional_hessian", "block_slices", "predictors", "multiplier"))
  expect(is.numeric(breakdown[[part]]) && breakdown[[part]] > 0,
         paste("the estimate breaks down into", part))
expect(report$resources$dense_working_bytes_estimate >= breakdown$random_design,
       "the total is at least the random-design matrix it contains")

# The largest model the counting limits allow is still well inside the default
# byte limit, so adding this guard cannot reject anything that fitted before.
biggest <- gt_preflight(panel, "label", design, gt_family("binary"),
  control = gt_control(discrete = list(max_observations = 1200L,
                                       max_random_dimension = 200L)))
expect(biggest$resources$dense_working_bytes_estimate < biggest$resources$max_dense_bytes,
       "the default limit is not binding for designs the count limits allow")

fitted <- gt_fit(panel, "label", design, gt_family("binary"),
                 control = gt_control(discrete = list(maxit = 200L)))
expect(isTRUE(fitted$numerically_accepted), "the permitted model fits")

# --- A binding limit refuses before allocating, and explains itself ---------
message <- expect_error(
  gt_fit(panel, "label", design, gt_family("binary"),
         control = gt_control(discrete = list(max_dense_bytes = 1000))),
  "dense working memory", "a binding byte limit")
for (fragment in c("max_dense_bytes", as.character(nrow(panel)), "random-effect dimensions",
                   "random-design matrix", "sparse"))
  expect(grepl(fragment, message, fixed = TRUE),
         paste("the refusal names", fragment))
expect(grepl("Raising max_dense_bytes does not make", message, fixed = TRUE),
       "the refusal says that raising the limit is not a fix")

blocked <- gt_preflight(panel, "label", design, gt_family("binary"),
  control = gt_control(discrete = list(max_dense_bytes = 1000)))
expect(isFALSE(blocked$fitting_feasible), "preflight reports the same model as blocked")
expect(isFALSE(blocked$checks$passed[blocked$checks$check == "dense_memory_limit"]),
       "the memory check is the one that fails")

# --- A permitted model is unaffected by the limit's presence ----------------
generous <- gt_fit(panel, "label", design, gt_family("binary"),
  control = gt_control(discrete = list(maxit = 200L, max_dense_bytes = 1e12)))
expect(isTRUE(all.equal(generous$covariance_components, fitted$covariance_components)),
       "a limit that does not bind changes no estimate")
expect(identical(generous$numerically_accepted, fitted$numerically_accepted),
       "a limit that does not bind changes no acceptance decision")

# --- The estimate grows with the model, not with the limit ------------------
estimate <- function(...) gt_preflight(..., family = gt_family("binary"))$resources$dense_working_bytes_estimate
small <- estimate(panel, "label", design)
wider <- expand.grid(rater = factor(1:6), item = factor(1:36))
wider$label <- rbinom(nrow(wider), 1L, plogis(rnorm(36, sd = .8)[wider$item]))
expect(estimate(wider, "label", design) > small,
       "doubling the objects increases the estimated dense memory")

# --- Invalid limits fail before fitting -------------------------------------
for (bad in list(0, -1, NA_real_, Inf, "512"))
  expect_error(gt_fit(panel, "label", design, gt_family("binary"),
                      control = gt_control(discrete = list(max_dense_bytes = bad))),
               "max_dense_bytes must be a positive finite number",
               "an invalid byte limit")

cat("PASS: the discrete dense-memory guard refuses before allocation and explains what it refused.\n")
