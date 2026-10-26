# Investigation of the stage 3 failures in the executed qualification record.
# Not part of the frozen study and not a verdict: it re-evaluates the failing
# fixed points with the same code to explain each failure, and changes no rule.
#
# Run from the project directory, with one numerical thread:
#   Rscript --vanilla validation-studies/discrete-sparse-equivalence/results/investigation/investigate-stage3.R
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))
invisible(capture.output(source(file.path(STUDY, "equivalence-runner-impl.R"))))
cat("R:", R.version.string, "| BLAS:", extSoftVersion()[["BLAS"]], "| LAPACK:", La_version(), "\n")
rel <- function(a, b) max(abs(a - b)) / (1 + max(abs(a), abs(b)))
probe <- function(id, label) {
  row <- EQ_CORE[EQ_CORE$case == id, ]
  map <- .eq_parameter_map(row, EQ_GEOMETRY[[row$geometry]])
  theta <- .eq_fixed_points(map$start, map$lower, map$upper, map$zero_coordinates)[[label]]
  d <- .gt_d_laplace(theta, map$prep, map$groups, map$setup, map$control, details = TRUE)
  s <- .gt_d_sparse_evaluator()(theta, map$prep, map$groups, map$setup, map$control, details = TRUE)
  cat(sprintf("\n%s %s (inner_tol %.0e)\n", id, label, map$control$inner_tol))
  cat(sprintf("  dense : %2d Newton steps, final mode gradient %.3g, objective %.12f\n",
              d$inner_iterations, d$inner_gradient, d$nll))
  cat(sprintf("  sparse: %2d Newton steps, final mode gradient %.3g, objective %.12f\n",
              s$inner_iterations, s$inner_gradient, s$nll))
  cat(sprintf("  dense - sparse: objective %.3g, mode (symmetric relative) %.3g\n",
              d$nll - s$nll, rel(d$mode, s$mode)))
  for (tol in c(1e-9, 1e-10)) {
    tight <- map$control; tight$inner_tol <- tol; tight$inner_maxit <- 500L
    ref <- .gt_d_laplace(theta, map$prep, map$groups, map$setup, tight, details = TRUE)
    if (isTRUE(ref$valid))
      cat(sprintf("  dense solve to %.0e (%d steps): objective dense - ref %.3g, sparse - ref %.3g; mode dense %.3g, sparse %.3g\n",
                  tol, ref$inner_iterations, d$nll - ref$nll, s$nll - ref$nll, rel(d$mode, ref$mode), rel(s$mode, ref$mode)))
    else cat(sprintf("  dense solve to %.0e unavailable: %s\n", tol, paste(ref$reason, collapse = "; ")))
  }
  fixed_length <- length(map$prep$start)
  factors <- .gt_d_covariance_factors(theta[-seq_len(fixed_length)], map$setup)
  Wd <- .gt_d_dense_backend(map$groups, factors, map$prep$n, map$prep$q)$W
  Ws <- .gt_d_sparse_backend(map$groups, factors, map$prep$n, map$prep$q)$W
  k <- .gt_d_response_kernel(.gt_d_baseline(theta, map$prep), theta, map$prep)
  sd <- as.vector(crossprod(Wd, k$gradient)); ss <- as.numeric(Matrix::crossprod(Ws, k$gradient))
  cat(sprintf("  mode score at latent zero: max|score| %.4g, max|dense - sparse| %.3g (relative to max|score| %.3g)\n",
              max(abs(sd)), max(abs(sd - ss)), max(abs(sd - ss)) / max(abs(sd))))
}
for (id in c("C08", "C13")) for (label in EQ_FIXED_POINT_LABELS) probe(id, label)
