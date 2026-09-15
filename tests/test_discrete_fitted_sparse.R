# Run from the project directory with Rscript tests/test_discrete_fitted_sparse.R.
#
# The frozen fitted smoke matrix, executed through the sparse marginal
# evaluator and compared with dense. The contract this checks was frozen before
# this evaluator existed; nothing here may relax it.
#
# Both fits use the same outer numerical policy. Preparation, parameterization,
# bounds, starts, optimizer, restarts, tight validation, stationarity and
# acceptance are the dense implementation's, reached through the private
# evaluator seam. Only the marginal evaluation differs, which is what makes a
# disagreement attributable.
source(file.path("validation-studies", "discrete-sparse-fitted-smoke", "cases.R"))
source(file.path("R", "discrete_sparse.R"))
source(file.path("R", "discrete_sparse_mode.R"))
suppressMessages(library(Matrix))

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)

# Declared by the frozen protocol. Layer 1 reuses the already-qualified
# fixed-parameter parity scale. Layer 2 reuses the package's own
# restart-stability definitions of "the same solution".
PARITY <- 1e-10
OBJECTIVE_RELATIVE <- 1e-6
FIT_DISTANCE <- 0.02

rebuild <- function(cs) {
  control <- .gt_d_control(cs$control)
  prep <- .gt_d_prepare(cs$data, cs$outcomes, cs$families)
  groups <- lapply(cs$design$term_members, function(m) .gt_d_group(cs$data, m))
  setup <- .gt_d_covariance_setup(groups, prep$q, cs$covariance, control, prep$dimensions)
  validation <- control
  validation$inner_tol <- min(control$inner_tol, control$validation_inner_tol)
  validation$reltol <- min(control$reltol, control$validation_reltol)
  list(control = control, prep = prep, groups = groups, setup = setup,
       validation = validation)
}

fit_with <- function(cs, evaluator, label) {
  started <- Sys.time()
  value <- tryCatch(.gt_fit_discrete(cs$data, cs$outcomes, cs$design, cs$families,
                      covariance = cs$covariance, control = cs$control,
                      .laplace = evaluator, .engine = label),
                    error = function(e) structure(list(message = conditionMessage(e)),
                                                  class = "gt_smoke_refusal"))
  list(fit = value, elapsed = as.numeric(difftime(Sys.time(), started, units = "secs")))
}

classify_refusal <- function(message) {
  if (grepl("inner mode", message, fixed = TRUE) &&
      grepl("starting values", message, fixed = TRUE))
    return("conditional_mode_unavailable_at_start")
  if (grepl("dimension|do not match|Invalid|invalid|malformed", message))
    return("malformed_internal_input")
  "other_refusal"
}

verdict <- function(run) {
  fit <- run$fit
  if (inherits(fit, "gt_smoke_refusal"))
    return(list(disposition = "refused", refusal_class = classify_refusal(fit$message)))
  list(disposition = if (isTRUE(fit$numerically_accepted)) "accepted" else "rejected",
       acceptance_failures = paste(sort(unique(fit$diagnostics$acceptance_failures)),
                                   collapse = "|"),
       zero_variance_parameters = paste(sort(unique(as.character(
         fit$diagnostics$zero_variance_parameters))), collapse = "|"),
       optimizer_completed = isTRUE(fit$optimizer_completed),
       numerically_accepted = isTRUE(fit$numerically_accepted),
       inner_converged = isTRUE(fit$diagnostics$inner_converged),
       tight_final_mode = isTRUE(fit$diagnostics$tight_final_mode))
}

evidence <- list()
for (cs in cases) {
  label <- paste0("case ", cs$key)
  at <- rebuild(cs)
  dense <- fit_with(cs, .gt_d_laplace, "dense_marginal_laplace")
  sparse <- fit_with(cs, .gt_d_sparse_evaluator(), "sparse_marginal_laplace")

  # The sparse run must actually have been sparse. A seam that silently fell
  # back to dense would otherwise pass every comparison below trivially.
  if (!inherits(sparse$fit, "gt_smoke_refusal"))
    expect(identical(sparse$fit$diagnostics$marginal_backend, "sparse_marginal_laplace"),
           paste(label, "was evaluated by the sparse marginal backend"))

  # --- Layer 3: same behaviour, exactly ---------------------------------------
  dv <- verdict(dense)
  sv <- verdict(sparse)
  expect(identical(sv$disposition, cs$disposition),
         paste0(label, " was declared ", cs$disposition, " and sparse produced ",
                sv$disposition))
  expect(identical(dv$disposition, sv$disposition),
         paste0(label, " dispositions agree: dense ", dv$disposition,
                ", sparse ", sv$disposition))
  # A sparse rejection or refusal must never become an acceptance. Stated
  # separately from the equality above so the asymmetry is explicit: this is
  # the failure the negative controls exist to catch.
  if (!identical(dv$disposition, "accepted"))
    expect(!identical(sv$disposition, "accepted"),
           paste(label, "sparse does not rescue a dense", dv$disposition))
  for (field in intersect(names(dv), names(sv)))
    expect(identical(dv[[field]], sv[[field]]),
           paste0(label, " ", field, ": dense ", format(dv[[field]]),
                  ", sparse ", format(sv[[field]])))

  if (identical(cs$disposition, "refused")) {
    expect(identical(sv$refusal_class, cs$class),
           paste0(label, " refuses with the declared class ", cs$class))
    next
  }

  # --- Layer 1: same function, at both fitted endpoints ------------------------
  # Evaluating only at the dense optimum would leave open that the sparse
  # evaluator differs somewhere the sparse optimizer actually visited.
  evaluator <- .gt_d_sparse_evaluator()
  for (endpoint in list(list(name = "dense endpoint", par = dense$fit$parameters),
                        list(name = "sparse endpoint", par = sparse$fit$parameters))) {
    d <- .gt_d_laplace(endpoint$par, at$prep, at$groups, at$setup, at$validation)
    s <- evaluator(endpoint$par, at$prep, at$groups, at$setup, at$validation)
    expect(is.finite(d) && is.finite(s),
           paste(label, "both evaluators return a finite value at the", endpoint$name))
    expect(abs(d - s) <= PARITY,
           paste0(label, " Layer 1 at the ", endpoint$name, ": dense ",
                  format(d, digits = 17), ", sparse ", format(s, digits = 17),
                  ", difference ", format(abs(d - s), digits = 3)))
  }

  # --- Layer 2: same solution -------------------------------------------------
  objective_difference <- abs(dense$fit$minus2loglik - sparse$fit$minus2loglik)
  relative <- objective_difference / max(1, abs(dense$fit$minus2loglik))
  expect(relative <= OBJECTIVE_RELATIVE,
         paste0(label, " Layer 2 objective: relative difference ",
                format(relative, digits = 3)))
  distance <- .gt_d_fit_distance(dense$fit$parameters, sparse$fit$parameters,
                                 at$prep, at$setup)
  expect(distance <= FIT_DISTANCE,
         paste0(label, " Layer 2 fit distance ", format(distance, digits = 3),
                " exceeds ", FIT_DISTANCE))

  # --- Storage and resource evidence ------------------------------------------
  # Recorded, not asserted against a threshold. No speedup or memory factor is
  # claimed here; that waits for profiling and the benchmark.
  factors <- .gt_d_covariance_factors(
    sparse$fit$parameters[-seq_along(at$prep$start)], at$setup)
  context <- .gt_d_sparse_context(at$groups, at$prep$n, at$prep$q)
  backend <- .gt_d_sparse_backend_from(context, factors)
  kernel <- .gt_d_response_kernel(
    .gt_d_baseline(sparse$fit$parameters, at$prep) +
      matrix(as.numeric(backend$W %*% numeric(ncol(backend$W))), at$prep$n, at$prep$q),
    sparse$fit$parameters, at$prep)
  H <- .gt_d_sparse_hessian(kernel$curvature, backend$W, at$prep$n)
  factorization <- .gt_d_sparse_factor(H)
  expect(methods::is(backend$W, "sparseMatrix"),
         paste(label, "the random design stays in sparse storage"))
  dense_cells <- as.numeric(nrow(backend$W)) * as.numeric(ncol(backend$W))
  expect(backend$stored_entries < dense_cells,
         paste0(label, " stores fewer entries (", backend$stored_entries,
                ") than the dense design has cells (", format(dense_cells), ")"))
  evidence[[length(evidence) + 1L]] <- data.frame(
    case = cs$key, random_dimension = backend$random_dimension,
    dense_cells = dense_cells, nnz_W = backend$stored_entries,
    nnz_H = as.integer(Matrix::nnzero(H)),
    factor_entries = factorization$factor_entries,
    hessian_triangle = factorization$hessian_triangle_entries,
    dense_seconds = round(dense$elapsed, 2), sparse_seconds = round(sparse$elapsed, 2),
    stringsAsFactors = FALSE)
}

# --- A retained context may not outlive its design -----------------------------
# The evaluator caches the coordinate geometry so an outer optimizer does not
# rediscover it on every call. That cache is correct only while the design is
# the same one, and "the same" has to mean the grouping itself rather than its
# dimensions.
#
# Two designs can agree on observation count, latent dimension, source count
# and every level count while disagreeing on which observation belongs to which
# level. A dimension-only guard admits the second design and answers with the
# first design's coordinates, which is the specific failure this whole sparse
# effort exists to avoid: a finite, plausible number computed for a model
# nobody asked about.
#
# The fixture below is built so that a weaker guard would pass it. Its
# preconditions are asserted first, so it cannot quietly stop being adversarial.
local({
  cs <- Filter(function(c) identical(c$key, "fit_binary_probit_crossed"), cases)[[1L]]
  at <- rebuild(cs)
  first <- at$groups
  second <- first
  # Same number of levels, same length, a different partition of observations.
  second$item$index <- ((seq_along(first$item$index) - 1L) %/% 10L) + 1L
  parameters <- c(at$prep$start, at$setup$start)

  expect(identical(length(first), length(second)),
         "the two designs have the same number of random sources")
  expect(identical(vapply(first, `[[`, integer(1), "nlevels"),
                   vapply(second, `[[`, integer(1), "nlevels")),
         "the two designs have the same level counts")
  expect(!identical(first, second),
         "the two designs differ in grouping, which is the only difference")

  # They must also disagree numerically, or a stale context would be harmless
  # and the refusal below would be asserting nothing.
  truth_first <- .gt_d_laplace(parameters, at$prep, first, at$setup, at$control)
  truth_second <- .gt_d_laplace(parameters, at$prep, second, at$setup, at$control)
  expect(abs(truth_first - truth_second) > 1,
         paste0("the two designs give materially different objectives: ",
                format(truth_first, digits = 12), " against ",
                format(truth_second, digits = 12)))

  evaluator <- .gt_d_sparse_evaluator()
  value <- evaluator(parameters, at$prep, first, at$setup, at$control)
  expect(abs(value - truth_first) <= PARITY,
         "the first design evaluates correctly through the sparse evaluator")
  reused <- tryCatch({ evaluator(parameters, at$prep, second, at$setup, at$control) },
                     error = conditionMessage)
  expect(is.character(reused),
         paste0("reusing the evaluator across designs is refused; it instead returned ",
                format(reused)))
  expect(grepl("different designs", reused, fixed = TRUE),
         paste0("the refusal is the evaluator's own; it said: ", reused))
})

table <- do.call(rbind, evidence)
cat("\nSparse storage and resource evidence (recorded, not thresholded):\n")
print(table, row.names = FALSE)
cat("\nPASS: the frozen fitted matrix reproduces through the sparse marginal ",
    "evaluator at all three layers.\n", sep = "")
