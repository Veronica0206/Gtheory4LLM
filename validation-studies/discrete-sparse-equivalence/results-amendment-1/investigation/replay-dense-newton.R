# Investigation of the dense inner Newton solve at two points of C13's macOS
# dense fit. Not part of the frozen study and not a verdict.
#
# The points are evaluations 12 and 15 of that fit. Evaluation 12 is the last
# before the macOS dense fit asks for different parameters from the other fits,
# and its solve needed the whole 60-step budget; evaluation 15 is the first that
# solve could not use. Their parameters are given exactly, in hexadecimal, as
# the macOS fit passed them to the evaluator, so every platform replays the
# same points.
# The loop is a copy of .gt_d_dense_mode() (R/discrete_mode.R) with a record
# of each step added; its mode is checked against the production solver.
#
# Run from the project directory, with one numerical thread:
#   Rscript --vanilla validation-studies/discrete-sparse-equivalence/results-amendment-1/investigation/replay-dense-newton.R
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode",
            "discrete_sparse", "discrete_sparse_mode", "discrete", "diagnostics_stages"))
  source(file.path("R", paste0(f, ".R")))
cat("R:", R.version.string, "| BLAS:", extSoftVersion()[["BLAS"]], "| LAPACK:", La_version(), "\n")
row <- EQ_CORE[EQ_CORE$case == "C13", ]
map <- .eq_parameter_map(row, EQ_GEOMETRY[[row$geometry]])
# The coarse control the fit passed with both evaluations; inner_start is a
# role only the sparse evaluator reads.
control <- .gt_d_control(.eq_control_for(row$covariance))
control$inner_start <- "warm_probe"
points <- list(
  "12" = c(-0x1.aef514fb8e9a9p-3, -0x1.f4c709db24bf1p-4, -0x1.d5240f0e0e077p-1, -0x1.d5240f0e0e077p-1,
           -0x1.d5a7217ca594cp-1),
  "15" = c(-0x1.c7b81c6e599a2p-4, 0x1.26bb1bbb55516p+2, -0x1.4p+3, 0x1.61f67a585d03ap-1, 0x1.4p+2))

replay <- function(parameters) {
  prep <- map$prep
  factors <- .gt_d_covariance_factors(parameters[-seq_along(prep$start)], map$setup)
  backend <- .gt_d_dense_backend(map$groups, factors, prep$n, prep$q)
  W <- backend$W
  baseline <- .gt_d_baseline(parameters, prep)
  u <- numeric(ncol(W)); steps <- list()
  for (iter in seq_len(control$inner_maxit)) {
    response <- .gt_d_dense_evaluate(baseline + matrix(W %*% u, prep$n, prep$q), parameters, prep, backend)
    gradient <- as.vector(crossprod(W, response$gradient)) + u
    if (max(abs(gradient)) <= control$inner_tol) {
      steps[[iter]] <- c(step = iter, gradient = max(abs(gradient)), halvings = NA, decrease = NA,
                         predicted = NA, full_step_excess = NA, objective = NA)
      break
    }
    R <- chol(response$H)
    step <- backsolve(R, forwardsolve(t(R), gradient))
    objective <- response$nll + sum(u^2) / 2
    descent <- sum(gradient * step)
    multiplier <- 1; accepted <- FALSE
    for (line in seq_len(30L)) {
      candidate <- u - multiplier * step
      nr <- .gt_d_response_kernel(baseline + matrix(W %*% candidate, prep$n, prep$q), parameters, prep)
      value <- nr$nll + sum(candidate^2) / 2
      bound <- objective - 1e-4 * multiplier * descent + 1e-12
      if (line == 1L) excess <- value - bound
      if (nr$valid && value <= bound) { u <- as.vector(candidate); accepted <- TRUE; break }
      multiplier <- multiplier / 2
    }
    steps[[iter]] <- c(step = iter, gradient = max(abs(gradient)), halvings = line - 1L,
                       decrease = objective - value, predicted = descent, full_step_excess = excess,
                       objective = objective)
    if (!accepted) break
  }
  list(mode = u, steps = do.call(rbind, steps))
}

for (call in names(points)) {
  parameters <- points[[call]]
  factors <- .gt_d_covariance_factors(parameters[-seq_along(map$prep$start)], map$setup)
  production <- .gt_d_dense_mode(parameters, map$prep, .gt_d_dense_backend(map$groups, factors, map$prep$n, map$prep$q),
                                 control, details = TRUE)
  sparse <- .gt_d_sparse_evaluator()(parameters, map$prep, map$groups, map$setup, control, details = TRUE)
  r <- replay(parameters)
  steps <- r$steps
  cat(sprintf("\n== evaluation %s (inner tolerance %g, budget %d)\n", call, control$inner_tol, control$inner_maxit))
  # A usable production solve returns its mode, which the replay must equal;
  # an unusable one returns only its step count, which the replay must equal.
  cat(sprintf("production dense: %s after %s steps, final gradient %.3g; the replay matches it: %s\n",
              if (isTRUE(production$valid)) "usable" else "unusable", format(production$inner_iterations),
              if (is.null(production$inner_gradient)) NA_real_ else production$inner_gradient,
              if (isTRUE(production$valid)) paste(identical(production$mode, r$mode), "(identical mode)") else
                paste(isTRUE(nrow(steps) == production$inner_iterations), "(same step count)")))
  cat(sprintf("sparse: %s after %s steps, %s of them accepted by the roundoff safeguard\n",
              if (isTRUE(sparse$valid)) "usable" else "unusable", format(sparse$inner_iterations),
              format(sparse$inner_roundoff_steps)))
  shown <- unique(c(seq_len(min(8L, nrow(steps))), max(1L, nrow(steps) - 2L):nrow(steps)))
  print(signif(as.data.frame(steps[shown, , drop = FALSE]), 4), row.names = FALSE)
  cat(sprintf("steps that halved the Newton step: %d of %d; rounding resolution of the objective (eps x objective): %.2e\n",
              sum(steps[, "halvings"] > 0, na.rm = TRUE), nrow(steps), .Machine$double.eps * abs(steps[1L, "objective"])))
}
