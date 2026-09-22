# Source this file to load the standalone R functions. No package installation.
.gt_loader_files <- lapply(sys.frames(), function(f) get0("ofile", envir = f, inherits = FALSE))
.gt_loader_files <- Filter(function(x) is.character(x) && length(x) == 1L, .gt_loader_files)
if (!length(.gt_loader_files)) stop("Load these functions with source('path/to/load_functions.R').")
.gt_loader_root <- dirname(normalizePath(tail(.gt_loader_files, 1L)[[1L]], mustWork = TRUE))
.gt_example_data_dir <- file.path(.gt_loader_root, "inst", "extdata")
for (.gt_loader_name in c("design.R", "family.R", "gaussian_retry.R", "gaussian_engine.R", "gaussian.R",
                          "discrete_response.R", "discrete_dense.R", "discrete_sparse.R",
                          "discrete_mode.R", "discrete_sparse_mode.R", "discrete.R", "preflight.R",
                          "diagnostics_stages.R", "fit.R", "methods.R",
                          "reliability.R", "examples.R")) {
  .gt_loader_path <- file.path(.gt_loader_root, "R", .gt_loader_name)
  if (!file.exists(.gt_loader_path)) stop("Missing standalone implementation file: ", .gt_loader_name)
  sys.source(.gt_loader_path, envir = environment())
}
rm(.gt_loader_files, .gt_loader_root, .gt_loader_name, .gt_loader_path)
