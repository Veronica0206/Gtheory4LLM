# Run against a freshly installed package:
# Rscript examples/analysis_report_workflow.R /path/to/new-report-directory
library(Gtheory4LLM)
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L)
  stop("Usage: Rscript examples/analysis_report_workflow.R OUTPUT_DIRECTORY")
output <- arguments[[1L]]
if (dir.exists(output) && length(list.files(output, all.files = TRUE, no.. = TRUE)))
  stop("Use a new or empty output directory; existing reports are not replaced.")
dir.create(output, recursive = TRUE, showWarnings = FALSE)

set.seed(30117)
d <- expand.grid(item = seq_len(40), evaluator = seq_len(6), prompt = seq_len(3))
d$quality <- rnorm(40, sd = 1.2)[d$item] + rnorm(6, sd = .6)[d$evaluator] +
  rnorm(3, sd = .35)[d$prompt] + rnorm(nrow(d))
d$clarity <- rnorm(40)[d$item] + rnorm(6, sd = .4)[d$evaluator] +
  rnorm(3, sd = .5)[d$prompt] + rnorm(nrow(d), sd = .8)
design <- gt_design("item", c("evaluator", "prompt"), random = ~ item + evaluator + prompt)
preflight <- gt_preflight(d, c("quality", "clarity"), design,
                          covariance = "diagonal", residual = "diagonal")
fit <- gt_fit(d, c("quality", "clarity"), design, covariance = "diagonal", residual = "diagonal",
  control = gt_control(gaussian = list(retry_seed = 42, threads = 1L)))
score <- gt_score(c(quality = .6, clarity = .4))
rel <- gt_reliability(fit, score = score)
study <- gt_dstudy(fit, expand.grid(evaluator = c(2, 4, 6, 8), prompt = c(1, 2, 3)), score = score)
report <- gt_report(fit, preflight, rel, study)
gt_export_report(report, file.path(output, "gaussian-analysis.html"))
saveRDS(report, file.path(output, "gaussian-analysis.rds"))

# A small ordinal example also illustrates the aggregate coverage heatmap.
# Fixed zero random-source covariances make this a transparent engine example,
# not a claim that an LLM measurement study has zero random variation.
ordinal <- expand.grid(item = seq_len(12), evaluator = seq_len(4))
ordinal$grade <- ordered(rep(c("low", "medium", "high"), 16L), levels = c("low", "medium", "high"))
ordinal_design <- gt_design("item", "evaluator", random = ~ item + evaluator, full_cell = FALSE)
control <- gt_control(discrete = list(optimizer = "nlminb",
  fixed_covariance = list(item = matrix(0), evaluator = matrix(0))))
preflight <- gt_preflight(ordinal, "grade", ordinal_design, gt_family("ordinal"), control = control)
fit <- gt_fit(ordinal, "grade", ordinal_design, gt_family("ordinal"), control = control)
report <- gt_report(fit, preflight, gt_reliability(fit, scale = "latent"),
  gt_dstudy(fit, data.frame(evaluator = c(2L, 4L, 6L)), scale = "latent"))
gt_export_report(report, file.path(output, "ordinal-analysis.html"))
saveRDS(report, file.path(output, "ordinal-analysis.rds"))
cat("Portable synthetic reports saved in", normalizePath(output), "\n")
