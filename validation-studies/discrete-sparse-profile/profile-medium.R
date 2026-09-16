# Engineering profile of the discrete marginal backends on an accepted panel.
#
# Measurement, not qualification. Nothing here is a threshold, an acceptance
# rule, or a claim. The qualified prototype evidence lives in the two frozen
# studies; this file only records what the backends cost.
#
# The panel is 1200 rows with 112 random coordinates, which sits exactly at
# max_observations and well inside max_random_dimension, so both backends run
# under default limits and neither guard is raised to obtain a comparison.
#
# Run one backend per process: peak RSS is a process property and cannot be
# attributed to a backend that shares its process with the other one.
#
#   Rscript profile-medium.R dense
#   Rscript profile-medium.R sparse
for (file in c("design.R", "family.R", "discrete_response.R", "discrete_dense.R",
               "discrete_sparse.R", "discrete_mode.R", "discrete_sparse_mode.R",
               "discrete.R"))
  source(file.path("R", file))
suppressMessages(library(Matrix))

arguments <- commandArgs(trailingOnly = TRUE)
backend <- arguments[[1L]]
mode <- if (length(arguments) > 1L) arguments[[2L]] else "timing"
if (!backend %in% c("dense", "sparse")) stop("backend must be dense or sparse")
if (!mode %in% c("timing", "work")) stop("mode must be timing or work")
# Peak RSS is a property of the process, so the two passes cannot share one.
# The timing pass fits once and reports wall time, allocation and peak RSS; the
# work pass fits once with details requested and reports only the inner-solve
# distribution, never a time.

set.seed(4101)
items <- 100L
raters <- 12L
data <- expand.grid(item = seq_len(items), rater = seq_len(raters))
item_effect <- rnorm(items, sd = 0.8)
rater_effect <- rnorm(raters, sd = 0.4)
latent <- item_effect[data$item] + rater_effect[data$rater] + rlogis(nrow(data))
proportions <- c(0.10, 0.20, 0.40, 0.20, 0.10)
cuts <- unname(stats::quantile(latent, probs = cumsum(proportions)[-5L], names = FALSE))
data$y <- factor(paste0("c", findInterval(latent, cuts) + 1L), levels = paste0("c", 1:5))
design <- list(object = "item", facets = "rater",
               term_members = list(item = "item", rater = "rater"))
families <- list(list(family = "ordinal", link = "logit",
                      levels = paste0("c", 1:5), reference = NULL))

control <- .gt_d_control(list())
prep <- .gt_d_prepare(data, "y", families)
groups <- lapply(design$term_members, function(members) .gt_d_group(data, members))
setup <- .gt_d_covariance_setup(groups, prep$q, "unstructured", control, prep$dimensions)
start <- c(prep$start, setup$start)

# Outer and inner work, accumulated inside a real fit rather than sampled at one
# parameter point. A microbenchmark at the starting values understates the cost
# by roughly eightfold, because the conditional solve takes more iterations away
# from the optimum.
calls <- 0L
inside <- 0
iterations <- integer(0)
budget_hits <- 0L
evaluator <- if (identical(backend, "sparse")) .gt_d_sparse_evaluator() else .gt_d_laplace
# Timing pass: forward details exactly as the fitter asked. Forcing details on
# every call would make the evaluator assemble a record the optimizer never
# wanted, inflating the very number being measured.
instrumented <- function(parameters, prep, groups, setup, control,
                         details = FALSE, factors_override = NULL) {
  calls <<- calls + 1L
  started <- Sys.time()
  value <- evaluator(parameters, prep, groups, setup, control,
                     details = details, factors_override = factors_override)
  inside <<- inside + as.numeric(difftime(Sys.time(), started, units = "secs"))
  value
}

# Work pass: a second fit that does request details, so the inner-iteration
# distribution can be observed. Its wall time is not reported, because
# requesting details changes what the evaluator does.
work_evaluator <- if (identical(backend, "sparse")) .gt_d_sparse_evaluator() else .gt_d_laplace
observed <- function(parameters, prep, groups, setup, control,
                     details = FALSE, factors_override = NULL) {
  value <- work_evaluator(parameters, prep, groups, setup, control,
                          details = TRUE, factors_override = factors_override)
  if (is.list(value) && isTRUE(value$valid)) {
    iterations <<- c(iterations, value$inner_iterations)
    if (value$inner_iterations >= control$inner_maxit) budget_hits <<- budget_hits + 1L
  }
  if (details) value else if (is.list(value) && isTRUE(value$valid)) value$nll else 1e100
}

if (identical(mode, "work")) {
  invisible(.gt_fit_discrete(data, "y", design, families, covariance = "unstructured",
                             control = list(), .laplace = observed,
                             .engine = paste0(backend, "_marginal_laplace")))
  cat(sprintf("backend=%s mode=work\n", backend))
  cat(sprintf("inner_mean=%.2f inner_p90=%.0f inner_max=%d inner_budget_hits=%d inner_maxit=%d\n",
              mean(iterations), stats::quantile(iterations, 0.9, names = FALSE),
              max(iterations), budget_hits, control$inner_maxit))
  quit(save = "no")
}

# Only allocations of at least this size are recorded, so the reported total is
# "recorded allocation at or above the threshold", not all R allocation.
PROFMEM_THRESHOLD <- 1000L
allocation_log <- tempfile("gt-profmem-")
utils::Rprofmem(allocation_log, threshold = PROFMEM_THRESHOLD)
invisible(gc(reset = TRUE, full = TRUE))
started <- Sys.time()
fit <- .gt_fit_discrete(data, "y", design, families, covariance = "unstructured",
                        control = list(), .laplace = instrumented,
                        .engine = paste0(backend, "_marginal_laplace"))
elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
utils::Rprofmem(NULL)

# R-visible allocation. Complementary to peak RSS rather than a substitute:
# Matrix and CHOLMOD allocate natively, and those bytes are not all represented
# in R's own accounting.
records <- tryCatch(readLines(allocation_log, warn = FALSE), error = function(e) character(0))
sizes <- suppressWarnings(as.numeric(sub("^([0-9]+).*$", "\\1", records)))
sizes <- sizes[is.finite(sizes)]

panel_file <- tempfile("gt-panel-", fileext = ".csv")
write.csv(data, panel_file, row.names = FALSE)
panel_digest <- local({
  normalized <- tempfile("gt-norm-")
  connection <- file(normalized, "wb")
  tryCatch(writeBin(charToRaw(paste0(paste(readLines(panel_file, warn = FALSE),
                                           collapse = "\n"), "\n")), connection),
           finally = close(connection))
  on.exit(unlink(c(normalized, panel_file)), add = TRUE)
  unname(tools::md5sum(normalized))
})
threads <- Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
                        "VECLIB_MAXIMUM_THREADS"))
cat(sprintf("backend=%s\n", backend))
cat(sprintf("panel_md5=%s\n", panel_digest))
cat(sprintf("R=%s Matrix=%s\n", R.version.string,
            as.character(utils::packageVersion("Matrix"))))
cat(sprintf("platform=%s os=%s arch=%s\n", R.version$platform,
            Sys.info()[["sysname"]], Sys.info()[["machine"]]))
cat(sprintf("BLAS=%s\n", extSoftVersion()[["BLAS"]]))
cat(sprintf("LAPACK=%s (%s)\n", La_library(), La_version()))
cat(sprintf("threads: %s\n", paste(names(threads), ifelse(nzchar(threads), threads, "unset"),
                                    sep = "=", collapse = " ")))
cat(sprintf("rows=%d q=%d random_dimension=%d parameters=%d\n", nrow(data), prep$q,
            sum(vapply(groups, `[[`, integer(1), "nlevels")) * prep$q, length(start)))
cat(sprintf("accepted=%s optimizer_completed=%s selected=%s\n",
            isTRUE(fit$numerically_accepted), isTRUE(fit$optimizer_completed),
            fit$diagnostics$selected_attempt))
cat(sprintf("elapsed_seconds=%.2f evaluator_seconds=%.2f evaluator_share=%.0f%% ms_per_evaluation=%.2f\n",
            elapsed, inside, 100 * inside / elapsed, 1000 * inside / calls))
cat(sprintf("evaluations=%d\n", calls))
cat(sprintf("rprofmem_threshold_bytes=%d rprofmem_records=%d rprofmem_recorded_Mb=%.1f rprofmem_max_single_Mb=%.2f\n",
            PROFMEM_THRESHOLD, length(sizes), sum(sizes) / 1024^2,
            if (length(sizes)) max(sizes) / 1024^2 else 0))

cat(sprintf("inner_mean=%.2f inner_p90=%.0f inner_max=%d inner_budget_hits=%d inner_maxit=%d\n",
            mean(iterations), stats::quantile(iterations, 0.9, names = FALSE),
            max(iterations), budget_hits, control$inner_maxit))

factors <- .gt_d_covariance_factors(fit$parameters[-seq_along(prep$start)], setup)
if (identical(backend, "sparse")) {
  context <- .gt_d_sparse_context(groups, prep$n, prep$q)
  sparse_backend <- .gt_d_sparse_backend_from(context, factors)
  eta <- .gt_d_baseline(fit$parameters, prep)
  kernel <- .gt_d_response_kernel(eta, fit$parameters, prep)
  hessian <- .gt_d_sparse_hessian(kernel$curvature, sparse_backend$W, prep$n)
  factorization <- .gt_d_sparse_factor(hessian)
  cat(sprintf("dense_cells=%.0f nnz_W=%d nnz_H=%d factor_entries=%d hessian_triangle=%d\n",
              as.numeric(nrow(sparse_backend$W)) * ncol(sparse_backend$W),
              sparse_backend$stored_entries, as.integer(Matrix::nnzero(hessian)),
              factorization$factor_entries, factorization$hessian_triangle_entries))
} else {
  dense_backend <- .gt_d_dense_backend(groups, factors, prep$n, prep$q)
  cat(sprintf("dense_cells=%.0f\n",
              as.numeric(nrow(dense_backend$W)) * ncol(dense_backend$W)))
}
unlink(allocation_log)
