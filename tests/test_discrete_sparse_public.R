# Public backend selection must use the shared numerical acceptance policy.
source("load_functions.R")
source(file.path("validation-studies", "discrete-sparse-fitted-smoke", "cases.R"))
expect <- function(ok, message) if (!isTRUE(ok)) stop(message)
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  expect(inherits(error, "error") && grepl(pattern, conditionMessage(error)),
         paste("Expected refusal containing", pattern))
}

expect(identical(.gt_d_control(list())$engine, "dense"), "Dense remains the default")
for (bad in list("automatic", c("dense", "sparse"), NA_character_, 1))
  expect_error(.gt_d_control(list(engine = bad)), "engine")

for (key in c("fit_binary_probit_fixed_covariance", "fit_ordinal_logit_crossed")) {
  cs <- cases[[which(vapply(cases, `[[`, character(1), "key") == key)]]
  design <- gt_design(object = "item", facets = "rater", random = c("item", "rater"))
  family <- do.call(gt_family, cs$families[[1L]])
  fit <- function(engine) gt_fit(cs$data, "y", design, family,
    control = gt_control(discrete = c(cs$control, list(engine = engine))))
  dense <- fit("dense")
  sparse <- fit("sparse")
  expect(isTRUE(dense$numerically_accepted) && isTRUE(sparse$numerically_accepted),
         paste(key, "both engines satisfy numerical acceptance"))
  expect(identical(sparse$engine, "sparse_joint_discrete_laplace"), "Public engine identity")
  expect(abs(dense$minus2loglik - sparse$minus2loglik) < 1e-6,
         paste(key, "sparse and dense fitted objectives agree"))
  expect(isTRUE(sparse$diagnostics$outer_stationarity$stationary_within_tolerance) &&
         isTRUE(sparse$diagnostics$stability$stable) && sparse$diagnostics$tight_final_mode,
         "Sparse uses stationarity, restart, and tight conditional-mode checks")
  expect_error(gt_fit(cs$data, "y", design, family,
    control = gt_control(discrete = list(engine = "sparse", max_sparse_bytes = 1))),
    "max_sparse_bytes")
  # Dense memory guard is irrelevant to sparse algebra, but its own guard is not.
  limited <- .gt_d_control(list(engine = "sparse", max_dense_bytes = 1))
  expect(identical(limited$engine, "sparse"), "Separate algebra-specific memory controls")
}
cat("PASS: public sparse selection, dense parity, acceptance, and resource guards.\n")
