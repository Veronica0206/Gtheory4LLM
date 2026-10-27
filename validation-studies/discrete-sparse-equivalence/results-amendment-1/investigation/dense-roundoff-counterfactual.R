# Counterfactual for C13's macOS dense fit. Not part of the frozen study, not a
# verdict and not a change to the package: in this R session only, the dense
# Newton line search is given the roundoff safeguard the sparse solver already
# uses (.gt_d_roundoff_descent()), and C13 is refitted with both backends as
# stage 4 does. If the rounding-blocked Newton step is the cause, the dense fit
# then follows the sparse fit.
#
# Run from the project directory, with one numerical thread:
#   Rscript --vanilla validation-studies/discrete-sparse-equivalence/results-amendment-1/investigation/dense-roundoff-counterfactual.R
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode",
            "discrete_sparse", "discrete_sparse_mode", "discrete", "diagnostics_stages"))
  source(file.path("R", paste0(f, ".R")))
invisible(capture.output(source(file.path(STUDY, "equivalence-runner-impl.R"))))
cat("R:", R.version.string, "| BLAS:", extSoftVersion()[["BLAS"]], "| LAPACK:", La_version(), "\n")
text <- paste(readLines(file.path("R", "discrete_mode.R")), collapse = "\n")
production <- "      if (next_response$valid && next_response$nll + sum(candidate^2) / 2 <=
          objective - 1e-4 * multiplier * descent + 1e-12) {
        u <- as.vector(candidate)
        accepted <- TRUE
        break
      }"
safeguarded <- "      armijo <- next_response$valid && next_response$nll + sum(candidate^2) / 2 <=
          objective - 1e-4 * multiplier * descent + 1e-12
      roundoff <- FALSE
      if (!armijo && next_response$valid && multiplier == 1) {
        next_gradient <- as.vector(crossprod(W, next_response$gradient)) + candidate
        roundoff <- .gt_d_roundoff_descent(objective, next_response$nll + sum(candidate^2) / 2, descent,
                                          gradient, next_gradient, step, control$inner_tol * 10)
      }
      if (armijo || roundoff) {
        u <- as.vector(candidate)
        accepted <- TRUE
        break
      }"
stopifnot(lengths(regmatches(text, gregexpr(production, text, fixed = TRUE))) == 1L)
eval(parse(text = sub(production, safeguarded, text, fixed = TRUE)), envir = globalenv())
row <- EQ_CORE[EQ_CORE$case == "C13", ]
map <- .eq_parameter_map(row, EQ_GEOMETRY[[row$geometry]])
fits <- lapply(c(dense = "dense", sparse = "sparse"), function(b) .eqr_fit(row, map, b))
for (b in names(fits)) with(fits[[b]], cat(sprintf(
  "%s: %s after %.0f s, objective %.10f, %s evaluations, %s unusable, %s at the inner budget; failures: %s\n",
  b, disposition, elapsed, nll, inner_evaluations, invalid_evaluations, budget_terminations, message)))
cat(sprintf("dense - sparse: objective %.3g (relative %.3g), parameter distance %.3g\n",
            fits$dense$nll - fits$sparse$nll, abs(fits$dense$nll - fits$sparse$nll) / abs(fits$sparse$nll),
            .gt_d_fit_distance(fits$dense$parameters, fits$sparse$parameters, map$prep, map$setup)))
