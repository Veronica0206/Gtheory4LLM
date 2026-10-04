# Inner-budget and warm-start measurement on the scale-risk specimen.
#
# Characterization, not qualification, and not a feature. Section 4 of
# results.md established that the specimen's invalid evaluations are
# conditional-mode non-convergence, 44 of 48 at the 60-iteration budget. The
# roadmap makes warm starts conditional on measured need: this script measures
# it. For every evaluation the sparse fit could not use, and every valid solve
# that ended at the budget, it asks two separate questions at the recorded
# parameters and tolerance:
#
#   1. Cold, with a larger inner budget: does the solve CONVERGE, and at which
#      iteration, or does it merely continue?
#   2. Warm, at the ordinary budget: started from the conditional mode of the
#      evaluation the optimizer made just before it, does it converge?
#
# The solver used for the experiment is a copy of the production sparse loop
# with a starting vector and a returned mode; it is experiment code and lives
# here, not in R/. A self-check below requires that from a zero start it
# reproduces the production solver's value and iteration count exactly.
#
# Run from the project directory:
#   Rscript --vanilla validation-studies/discrete-sparse-profile/budget-experiment.R [out_dir]
arguments <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(arguments)) arguments[[1L]] else tempfile("gt-budget-experiment-")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
for (file in c("design.R", "family.R", "discrete_response.R", "discrete_dense.R",
               "discrete_sparse.R", "discrete_mode.R", "discrete_sparse_mode.R",
               "discrete.R"))
  source(file.path("R", file))
suppressMessages(library(Matrix))

set.seed(4101)
items <- 150L
raters <- 16L
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
panel_digest <- local({
  panel_file <- tempfile("gt-panel-", fileext = ".csv")
  write.csv(data, panel_file, row.names = FALSE)
  normalized <- tempfile("gt-norm-")
  connection <- file(normalized, "wb")
  tryCatch(writeBin(charToRaw(paste0(paste(readLines(panel_file, warn = FALSE),
                                           collapse = "\n"), "\n")), connection),
           finally = close(connection))
  on.exit(unlink(c(normalized, panel_file)), add = TRUE)
  unname(tools::md5sum(normalized))
})
cat(sprintf("panel_md5=%s same_as_recorded=%s\n", panel_digest,
            identical(panel_digest, "bad937e27a0ce3ee587b47ca1ae41b25")))

control <- .gt_d_control(list(max_observations = 2400L))
prep <- .gt_d_prepare(data, "y", families)
groups <- lapply(design$term_members, function(members) .gt_d_group(data, members))
setup <- .gt_d_covariance_setup(groups, prep$q, "unstructured", control, prep$dimensions)
context <- .gt_d_sparse_context(groups, prep$n, prep$q)
fixed_length <- length(prep$start)
backend_at <- function(parameters)
  .gt_d_sparse_backend_from(context, .gt_d_covariance_factors(parameters[-seq_len(fixed_length)], setup))

# ---- the fit, observed ----------------------------------------------------------
sparse_evaluator <- .gt_d_sparse_evaluator()
records <- list()
field <- function(value, name, default) if (is.list(value) && !is.null(value[[name]])) value[[name]] else default
observed <- function(parameters, prep, groups, setup, control, details = FALSE,
                     factors_override = NULL) {
  value <- sparse_evaluator(parameters, prep, groups, setup, control,
                            details = TRUE, factors_override = factors_override)
  valid <- .gt_d_evaluation_usable(value)
  records[[length(records) + 1L]] <<- list(
    parameters = parameters, inner_tol = control$inner_tol, valid = valid,
    inner_iterations = field(value, "inner_iterations", NA_integer_),
    line_search_failed = field(value, "inner_line_search_failed", NA),
    override = !is.null(factors_override))
  if (details) value else if (valid) value$nll else 1e100
}
invisible(tryCatch(.gt_fit_discrete(data, "y", design, families, covariance = "unstructured",
                                    control = list(max_observations = 2400L),
                                    .laplace = observed, .engine = "sparse_marginal_laplace"),
                   error = function(e) NULL))
valid <- vapply(records, `[[`, logical(1), "valid")
iterations <- vapply(records, function(r) as.integer(r$inner_iterations), integer(1))
cat(sprintf("observed: evaluations=%d valid=%d invalid=%d valid_at_budget=%d\n",
            length(records), sum(valid), sum(!valid),
            sum(valid & !is.na(iterations) & iterations >= control$inner_maxit)))

# ---- experiment solver: the production loop with a starting vector ---------------
experiment_mode <- function(parameters, backend, inner_maxit, inner_tol, u_start = NULL) {
  W <- backend$W
  baseline <- .gt_d_baseline(parameters, prep)
  u <- if (is.null(u_start)) numeric(ncol(W)) else u_start
  converged <- FALSE
  accepted <- TRUE
  last_gradient <- Inf
  iter <- 0L
  for (iter in seq_len(inner_maxit)) {
    eta <- baseline + matrix(as.numeric(W %*% u), prep$n, prep$q)
    response <- .gt_d_response_kernel(eta, parameters, prep)
    if (!response$valid) return(list(valid = FALSE, why = "response_invalid", iterations = iter))
    gradient <- as.numeric(Matrix::crossprod(W, response$gradient)) + u
    last_gradient <- max(abs(gradient))
    if (last_gradient <= inner_tol) { converged <- TRUE; break }
    H <- .gt_d_sparse_hessian(response$curvature, W, prep$n)
    factorization <- tryCatch(.gt_d_sparse_factor(H), error = function(e) NULL)
    if (is.null(factorization)) return(list(valid = FALSE, why = "no_factor", iterations = iter))
    step <- .gt_d_sparse_solve(factorization, gradient)
    if (!isTRUE(.gt_d_solve_check(H, gradient, step)$valid))
      return(list(valid = FALSE, why = "solve_invalid", iterations = iter))
    objective <- response$nll + sum(u^2) / 2
    descent <- sum(gradient * step)
    multiplier <- 1
    accepted <- FALSE
    for (line in seq_len(30L)) {
      candidate <- u - multiplier * step
      next_eta <- baseline + matrix(as.numeric(W %*% candidate), prep$n, prep$q)
      next_response <- .gt_d_response_kernel(next_eta, parameters, prep)
      if (next_response$valid && next_response$nll + sum(candidate^2) / 2 <=
          objective - 1e-4 * multiplier * descent + 1e-12) {
        u <- as.vector(candidate)
        accepted <- TRUE
        break
      }
      multiplier <- multiplier / 2
    }
    if (!accepted) break
  }
  eta <- baseline + matrix(as.numeric(W %*% u), prep$n, prep$q)
  response <- .gt_d_response_kernel(eta, parameters, prep)
  if (!response$valid) return(list(valid = FALSE, why = "response_invalid", iterations = iter))
  last_gradient <- max(abs(as.numeric(Matrix::crossprod(W, response$gradient)) + u))
  converged <- is.finite(last_gradient) && last_gradient <= inner_tol * 10
  H <- .gt_d_sparse_hessian(response$curvature, W, prep$n)
  factorization <- tryCatch(.gt_d_sparse_factor(H), error = function(e) NULL)
  if (is.null(factorization) || !converged)
    return(list(valid = FALSE, why = if (!accepted) "line_search_failed" else "budget",
                iterations = iter, gradient = last_gradient, mode = u))
  if (!isTRUE(.gt_d_sparse_final_factor_check(H, factorization)$valid))
    return(list(valid = FALSE, why = "factor_invalid", iterations = iter, mode = u))
  list(valid = TRUE, why = "converged", iterations = iter, gradient = last_gradient,
       nll = response$nll + sum(u^2) / 2 + .gt_d_sparse_logdet(factorization) / 2, mode = u)
}

# Self-check: from a zero start the experiment solver must reproduce the
# production solver exactly, value and iteration count, on recorded points.
check_points <- head(which(valid), 3L)
for (index in check_points) {
  r <- records[[index]]
  ctl <- control; ctl$inner_tol <- r$inner_tol
  production <- .gt_d_sparse_mode(r$parameters, prep, backend_at(r$parameters), ctl, details = TRUE)
  experiment <- experiment_mode(r$parameters, backend_at(r$parameters), control$inner_maxit, r$inner_tol)
  stopifnot(isTRUE(production$valid), isTRUE(experiment$valid),
            identical(production$inner_iterations, experiment$iterations),
            abs(production$nll - experiment$nll) <= 1e-12)
}
cat("self-check: the experiment solver reproduces the production solver from a zero start\n")

# ---- the measurement ----------------------------------------------------------------
BUDGETS <- c(60L, 120L, 300L)
selected <- which(!valid | (!is.na(iterations) & iterations >= control$inner_maxit))
cat(sprintf("measuring %d evaluations (%d invalid, %d valid at budget)\n",
            length(selected), sum(!valid[selected]), sum(valid[selected])))
rows <- lapply(selected, function(index) {
  r <- records[[index]]
  backend <- backend_at(r$parameters)
  row <- list(evaluation = index, phase = if (r$inner_tol < control$inner_tol) "tight" else "coarse",
              inner_tol = r$inner_tol, recorded_valid = r$valid,
              recorded_iterations = r$inner_iterations,
              recorded_line_search_failed = r$line_search_failed)
  for (budget in BUDGETS) {
    cold <- experiment_mode(r$parameters, backend, budget, r$inner_tol)
    row[[paste0("cold", budget, "_converged")]] <- isTRUE(cold$valid)
    row[[paste0("cold", budget, "_why")]] <- cold$why
    row[[paste0("cold", budget, "_iterations")]] <- cold$iterations
    row[[paste0("cold", budget, "_gradient")]] <- if (is.null(cold$gradient)) NA_real_ else cold$gradient
  }
  # Warm start: the mode of the evaluation made just before this one, solved
  # cold at the ordinary budget with ITS tolerance; the mode where it stopped
  # is used whether or not that solve converged, which is what a cached
  # previous mode would supply in practice.
  previous <- index - 1L
  if (previous >= 1L) {
    p <- records[[previous]]
    before <- experiment_mode(p$parameters, backend_at(p$parameters), control$inner_maxit, p$inner_tol)
    warm <- if (is.null(before$mode)) NULL else
      experiment_mode(r$parameters, backend, control$inner_maxit, r$inner_tol, u_start = before$mode)
    row$previous_converged <- isTRUE(before$valid)
    row$parameter_distance_to_previous <- max(abs(r$parameters - p$parameters))
    row$warm60_converged <- if (is.null(warm)) NA else isTRUE(warm$valid)
    row$warm60_why <- if (is.null(warm)) NA_character_ else warm$why
    row$warm60_iterations <- if (is.null(warm)) NA_integer_ else warm$iterations
    row$warm60_gradient <- if (is.null(warm) || is.null(warm$gradient)) NA_real_ else warm$gradient
  } else {
    row$previous_converged <- NA; row$parameter_distance_to_previous <- NA_real_
    row$warm60_converged <- NA; row$warm60_why <- NA_character_
    row$warm60_iterations <- NA_integer_; row$warm60_gradient <- NA_real_
  }
  as.data.frame(row, stringsAsFactors = FALSE)
})
table <- do.call(rbind, rows)
write.csv(table, file.path(out_dir, "budget-experiment.csv"), row.names = FALSE)

count <- function(x) sum(x, na.rm = TRUE)
report <- function(subset, label) {
  t <- table[subset, ]
  cat(sprintf("\n== %s (%d evaluations; tight=%d coarse=%d) ==\n", label, nrow(t),
              count(t$phase == "tight"), count(t$phase == "coarse")))
  for (budget in BUDGETS) {
    conv <- t[[paste0("cold", budget, "_converged")]]
    why <- t[[paste0("cold", budget, "_why")]]
    it <- t[[paste0("cold", budget, "_iterations")]]
    cat(sprintf("cold budget %3d: converged %2d of %2d", budget, count(conv), nrow(t)))
    if (count(conv)) cat(sprintf(" (iterations to converge: median %.0f, max %d)",
                                 median(it[conv %in% TRUE]), max(it[conv %in% TRUE])))
    cat(sprintf("; not converged: budget=%d line_search=%d other=%d\n",
                count(why == "budget"), count(why == "line_search_failed"),
                count(!(why %in% c("budget", "line_search_failed", "converged")))))
  }
  cat(sprintf("warm start at budget 60: converged %d of %d", count(t$warm60_converged),
              count(!is.na(t$warm60_converged))))
  if (count(t$warm60_converged))
    cat(sprintf(" (iterations: median %.0f, max %d)",
                median(t$warm60_iterations[t$warm60_converged %in% TRUE]),
                max(t$warm60_iterations[t$warm60_converged %in% TRUE])))
  cat(sprintf("; previous evaluation's own cold solve converged in %d of %d cases\n",
              count(t$previous_converged), count(!is.na(t$previous_converged))))
  cat(sprintf("max |parameter change| from the previous evaluation: median %.2g, max %.2g\n",
              median(t$parameter_distance_to_previous, na.rm = TRUE),
              max(t$parameter_distance_to_previous, na.rm = TRUE)))
}
report(!table$recorded_valid, "recorded INVALID evaluations")
report(table$recorded_valid, "recorded VALID evaluations that ended at the budget")
cat(sprintf("\ntable written to %s\n", out_dir))
