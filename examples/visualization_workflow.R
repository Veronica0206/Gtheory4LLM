# Render a synthetic gallery and CSV exports from the current checkout.
# Rscript --vanilla examples/visualization_workflow.R /path/to/new-output
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L)
  stop("Usage: Rscript examples/visualization_workflow.R OUTPUT_DIRECTORY")
file_argument <- commandArgs(trailingOnly = FALSE)
file_argument <- sub("^--file=", "", file_argument[startsWith(file_argument, "--file=")])
if (length(file_argument) != 1L) stop("Run this gallery with Rscript.")
file_argument <- gsub("~+~", " ", file_argument, fixed = TRUE)
root <- dirname(dirname(normalizePath(file_argument, mustWork = TRUE)))
source(file.path(root, "load_functions.R"))
output <- arguments[[1L]]
if (dir.exists(output) && length(list.files(output, all.files = TRUE, no.. = TRUE)))
  stop("Use a new or empty output directory; existing figures are not replaced.")
dir.create(output, recursive = TRUE, showWarnings = FALSE)

# Continuous scores from a declared item/evaluator/prompt model. These are not
# numeric codes substituted for an ordinal or binary response.
set.seed(30117)
d <- expand.grid(item = seq_len(40), evaluator = seq_len(6), prompt = seq_len(3))
d$quality <- rnorm(40, sd = 1.2)[d$item] +
  rnorm(6, sd = .6)[d$evaluator] + rnorm(3, sd = .35)[d$prompt] +
  rnorm(nrow(d), sd = 1)
design <- gt_design("item", c("evaluator", "prompt"),
                    random = ~ item + evaluator + prompt)
preflight <- gt_preflight(d, "quality", design)
fit <- gt_fit(d, "quality", design,
  control = gt_control(gaussian = list(retry_seed = 42, threads = 1L)))
stopifnot(isTRUE(fit$numerically_accepted))
reliability <- gt_reliability(fit)
study <- gt_dstudy(fit, expand.grid(evaluator = c(2, 4, 6, 8), prompt = c(1, 2, 3, 4)))
screen <- gt_dstudy_target(study, .8, coefficient = "Phi", outcome = "quality")

# Deliberate omissions and extra rows illustrate the audit; this altered panel
# is not fitted. All declared levels remain represented.
damaged <- rbind(d[-seq_len(72), ], d[101:124, ])
audit <- gt_preflight(damaged, "quality", design)
drawings <- list(
  "panel-audit" = function() plot(audit, type = "cells", main = "Panel audit: deliberately altered example"),
  "source-dimensions" = function() plot(preflight, type = "sources", main = "Dimensions of the declared random sources"),
  "reliability" = function() plot(reliability, target = .8, main = "Reliability of mean continuous judgments"),
  "decision-study" = function() plot(study, coefficient = "Phi", outcome = "quality", target = .8,
    main = "Candidate allocations: absolute reliability")
)
for (name in names(drawings)) {
  grDevices::png(file.path(output, paste0(name, ".png")), width = 1350, height = 900,
    res = 150, type = if (capabilities("aqua")) "quartz" else getOption("bitmapType"))
  tryCatch(drawings[[name]](), finally = grDevices::dev.off())
}
grDevices::pdf(file.path(output, "figures.pdf"), width = 9, height = 6, useDingbats = FALSE)
tryCatch(for (draw in drawings) draw(), finally = grDevices::dev.off())
utils::write.csv(as.data.frame(reliability), file.path(output, "reliability.csv"), row.names = FALSE)
utils::write.csv(as.data.frame(study), file.path(output, "decision-study.csv"), row.names = FALSE)
utils::write.csv(screen, file.path(output, "target-screen.csv"), row.names = FALSE)
capture.output(sessionInfo(), file = file.path(output, "environment.txt"))
cat("Synthetic gallery and tables saved in", normalizePath(output), "\n")
