# Structural/resource checks only: no likelihood optimization is performed.
source("load_functions.R")
failed <- function(x) x$checks$check[!x$checks$passed]
d <- expand.grid(item = 1:12, rater = 1:4)
d$score <- sin(d$item) + d$rater / 3 + cos(d$item * d$rater) / 5
d$flag <- as.integer((d$item + d$rater) %% 3 > 0)
design <- gt_design("item", "rater", random = ~ item + rater)
observed <- d[-c(3, 12, 19), ]
observed_control <- gt_control(gaussian = list(engine = "lme4", panel = "observed"))
checked <- gt_preflight(observed, "score", design, control = observed_control)
stopifnot(checked$fitting_feasible, checked$kernel_check == "checked",
          !checked$complete_balanced_panel, !length(checked$supported_reliability_scales),
          is.null(checked$resources$factorial_strata), checked$resources$max_observed_rows == 1000,
          checked$resources$identification$rank == 3L)
limited <- gt_preflight(observed, "score", design,
  control = gt_control(gaussian = list(engine = "lme4", panel = "observed", max_observed_rows = 10L)))
stopifnot("observed_row_limit" %in% failed(limited),
          limited$kernel_check == "skipped_after_structural_or_resource_failure")
limited <- gt_preflight(observed, "score", design,
  control = gt_control(gaussian = list(engine = "lme4", panel = "observed", max_preparation_bytes = 1)))
stopifnot("preparation_resource_limit" %in% failed(limited))
alias_data <- expand.grid(item = 1:6, run = 1:2)
alias_data$rater <- alias_data$item
alias_data$score <- seq_len(nrow(alias_data))
alias_design <- gt_design("item", c("rater", "run"), random = ~ item + rater + run)
alias <- gt_preflight(alias_data, "score", alias_design, control = observed_control)
stopifnot("observed_covariance_identification" %in% failed(alias),
          alias$kernel_check == "failed_observed_covariance_identification")
batch_design <- gt_design("item", "rater", random = ~ item + rater, batch = gt_batch(3))
batch_observed <- gt_preflight(d, "score", batch_design, control = observed_control)
stopifnot("observed_row_no_batches" %in% failed(batch_observed))
cat("PASS: observed-row Gaussian preflight matches its explicit fit guards and kernel-identification policy.\n")

dense <- gt_preflight(d, "flag", design, gt_family("binary"),
  control = gt_control(discrete = list(max_dense_bytes = 1)))
sparse <- gt_preflight(d, "flag", design, gt_family("binary"),
  control = gt_control(discrete = list(engine = "sparse", max_dense_bytes = 1)))
stopifnot("dense_memory_limit" %in% failed(dense), sparse$fitting_feasible,
          sparse$engine == "sparse_joint_discrete_laplace", sparse$kernel_check == "checked",
          !"dense_memory_limit" %in% sparse$checks$check,
          is.null(sparse$resources$max_dense_bytes),
          sparse$resources$sparse_working_bytes_estimate > 0)
sparse_limit <- gt_preflight(d, "flag", design, gt_family("binary"),
  control = gt_control(discrete = list(engine = "sparse", max_sparse_bytes = 1)))
stopifnot("sparse_memory_limit" %in% failed(sparse_limit))
for (engine in c("dense", "sparse")) {
  calls <- gt_preflight(d, "flag", batch_design, gt_family("binary"),
    control = gt_control(discrete = list(engine = engine)))
  stopifnot(calls$fitting_feasible, calls$batch_audit$model$modelled,
            calls$batch_audit$model$source == "Call", calls$kernel_check == "checked",
            calls$sources$observed_groups[calls$sources$source == "Call"] == 16,
            calls$random_dimension == 12 + 4 + 16,
            calls$parameters[["source_covariance"]] == 3)
}
cat("PASS: sparse preflight uses only its selected byte limit and includes Call dimensions, parameters and kernels.\n")
