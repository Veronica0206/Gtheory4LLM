# Source this file to load the standalone R functions. No package installation.
.gt_loader_files <- lapply(sys.frames(), function(f) get0("ofile", envir = f, inherits = FALSE))
.gt_loader_files <- Filter(function(x) is.character(x) && length(x) == 1L, .gt_loader_files)
if (!length(.gt_loader_files)) stop("Load these functions with source('path/to/load_functions.R').")
.gt_loader_root <- dirname(normalizePath(tail(.gt_loader_files, 1L)[[1L]], mustWork = TRUE))
.gt_example_data_dir <- file.path(.gt_loader_root, "inst", "extdata")
for (.gt_loader_name in c("design.R", "batch.R", "family.R", "gaussian_retry.R", "gaussian_initializer.R", "gaussian_engine.R",
                          "gaussian_observed.R", "gaussian.R", "gaussian_lme4.R",
                          "discrete_response.R", "discrete_dense.R", "discrete_sparse.R", "selected_inverse.R",
                          "discrete_sparse_envelope.R", "discrete_gradient.R", "discrete_boundary_escape.R",
                          "discrete_mode.R", "discrete_sparse_mode.R", "discrete.R",
                          "discrete_check.R", "discrete_information.R",
                          "preflight.R",
                          "diagnostics_stages.R", "fit.R", "methods.R",
                          "reliability.R", "batch_reliability.R", "planning.R", "simulation.R",
                          "discrete_simulation.R", "categorical_targets.R",
                          "visualization.R", "report.R", "examples.R")) {
  .gt_loader_path <- file.path(.gt_loader_root, "R", .gt_loader_name)
  if (!file.exists(.gt_loader_path)) stop("Missing standalone implementation file: ", .gt_loader_name)
  sys.source(.gt_loader_path, envir = environment())
}
# The compiled selected inverse. In the installed package its registered
# routines are namespace objects created by useDynLib(); the no-install path
# compiles the same C file once into a temporary directory, under the package's
# own name so that R finds the same registration function, and binds the same
# symbol objects here. Compiling needs the toolchain R itself uses.
.gt_loader_compile <- function(source_file) {
  build <- file.path(tempfile("gt-shlib-"), "Gtheory4LLM")
  dir.create(build, recursive = TRUE)
  file.copy(source_file, file.path(build, "Gtheory4LLM.c"))
  previous <- setwd(build)
  on.exit(setwd(previous), add = TRUE)
  output <- suppressWarnings(system2(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "Gtheory4LLM.c"),
                                     stdout = TRUE, stderr = TRUE))
  shared <- file.path(build, paste0("Gtheory4LLM", .Platform$dynlib.ext))
  if (!file.exists(shared))
    stop("Compiling src/gt_selected_inverse.c failed:\n", paste(output, collapse = "\n"))
  dyn.load(shared)
}
.gt_loader_dll <- .gt_loader_compile(file.path(.gt_loader_root, "src", "gt_selected_inverse.c"))
for (.gt_loader_symbol in c("gt_selected_inverse", "gt_selected_queries", "gt_selected_contractions",
                            "gt_selected_platform", "gt_selected_caps"))
  assign(.gt_loader_symbol, getNativeSymbolInfo(.gt_loader_symbol, .gt_loader_dll), envir = environment())
rm(.gt_loader_files, .gt_loader_root, .gt_loader_name, .gt_loader_path, .gt_loader_compile, .gt_loader_dll,
   .gt_loader_symbol)
