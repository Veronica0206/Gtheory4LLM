#!/usr/bin/env Rscript
# Installed-package driver. Sourcing this file only defines the workflow.
# CLI: Rscript examples/native_1_0_workflow.R smoke NEW_OUTPUT_DIRECTORY
# CLI: Rscript examples/native_1_0_workflow.R full NEW_OUTPUT_DIRECTORY ARCHIVE [MODEL]
local({
  script <- system.file("examples", "native_1_0_workflow.R", package = "Gtheory4LLM")
  if (!nzchar(script)) stop("Install Gtheory4LLM 1.0.0 before running this workflow.")
  source(script, local = .GlobalEnv)
})
if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 2L || length(args) > 4L || !args[1L] %in% c("smoke", "full"))
    stop("Usage: Rscript examples/native_1_0_workflow.R smoke|full NEW_OUTPUT_DIRECTORY [ARCHIVE] [MODEL]")
  answer <- gt_native_workflow(mode = args[1L], output_dir = args[2L],
    archive_path = if (length(args) >= 3L) args[3L] else NULL,
    models = if (length(args) >= 4L) args[4L] else NULL)
  print(answer)
  if (!nrow(answer$status) || any(answer$status$status != "accepted")) quit(status = 1L)
}
