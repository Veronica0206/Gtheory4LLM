# Investigation of C13's stage 4 outcome in the Amendment 1 record.
# Not part of the frozen study and not a verdict: it refits C13 exactly as
# stage 4 does, through a pass-through logger around each backend's Laplace
# evaluator, to explain why neither fit is accepted and why the dense fit takes
# a different path on macOS. It changes no rule and writes nothing.
#
# Run from the project directory, with one numerical thread:
#   Rscript --vanilla validation-studies/discrete-sparse-equivalence/results-amendment-1/investigation/investigate-c13-fits.R
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode",
            "discrete_sparse", "discrete_sparse_mode", "discrete", "diagnostics_stages"))
  source(file.path("R", paste0(f, ".R")))
invisible(capture.output(source(file.path(STUDY, "equivalence-runner-impl.R"))))
cat("R:", R.version.string, "| BLAS:", extSoftVersion()[["BLAS"]], "| LAPACK:", La_version(), "\n")
row <- EQ_CORE[EQ_CORE$case == "C13", ]
map <- .eq_parameter_map(row, EQ_GEOMETRY[[row$geometry]])

# The arguments of .eqr_fit(), with the evaluator wrapped. The wrapper returns
# exactly what the evaluator returns; the fit's own evaluation counts are
# printed beside the logged ones as the check that nothing changed.
fit_logged <- function(backend) {
  evaluator <- if (identical(backend, "dense")) .gt_d_laplace else .gt_d_sparse_evaluator()
  calls <- list()
  logged <- function(parameters, prep, groups, setup, control, details = FALSE, ...) {
    value <- evaluator(parameters, prep, groups, setup, control, details = details, ...)
    if (isTRUE(details) && is.list(value)) {
      field <- function(k) if (length(value[[k]])) value[[k]][[1L]] else NA
      calls[[length(calls) + 1L]] <<- list(parameters = parameters, inner_tol = control$inner_tol,
        usable = isTRUE(value$valid), nll = if (isTRUE(value$valid)) value$nll else NA_real_,
        iterations = field("inner_iterations"), gradient = field("inner_gradient"),
        line_search_failed = isTRUE(value$inner_line_search_failed),
        roundoff = field("inner_roundoff_steps"))
    }
    value
  }
  attr(logged, "reset") <- attr(evaluator, "reset")
  label <- if (identical(backend, "dense")) "dense_marginal_laplace" else "sparse_marginal_laplace"
  started <- Sys.time()
  fit <- suppressWarnings(.gt_fit_discrete(map$panel, .eq_outcomes(row$family), EQ_DESIGNS[[row$structure]],
    .eq_families(row$family, row$link, row$geometry), covariance = EQ_COVARIANCE_PROFILE[[row$covariance]]$covariance,
    control = .eq_control_for(row$covariance), .laplace = logged, .engine = label))
  list(fit = fit, calls = calls, seconds = as.numeric(difftime(Sys.time(), started, units = "secs")))
}

report <- function(backend, run) {
  fit <- run$fit; d <- fit$diagnostics; e <- d$evaluations; calls <- run$calls
  usable <- vapply(calls, `[[`, logical(1), "usable")
  cat(sprintf("\n== %s: %s after %.0f s, objective %.10f\n", backend,
              if (isTRUE(fit$numerically_accepted)) "accepted" else "rejected", run$seconds, -fit$logLik))
  cat("acceptance failures:", paste(sort(unique(unlist(d$acceptance_failures))), collapse = ", "), "\n")
  cat(sprintf("optimizer: code %s, %s\n", format(d$optimizer_code), format(d$optimizer_message)))
  cat(sprintf("fit's evaluation counts: %d evaluations, %d unusable, %d usable at the inner budget | logged calls: %d, unusable %d\n",
              e$count, e$invalid, e$valid_at_inner_budget, length(calls), sum(!usable)))
  s <- d$outer_stationarity
  cat(sprintf("outer stationarity: within tolerance %s; fixed-effect scaled norm %.3g, covariance scaled norm %.3g, tolerance %g\n",
              format(s$stationary_within_tolerance), s$fixed_effect_scaled_norm, s$covariance_scaled_norm, s$tolerance))
  cat("covariance projected scores:", paste(sprintf("%s %.3g", names(s$covariance_projected_scores),
                                                    unlist(s$covariance_projected_scores)), collapse = ", "), "\n")
  cat("estimates:", paste(sprintf("%s %.6g", names(fit$parameters), fit$parameters), collapse = ", "), "\n")
  if (any(!usable)) {
    bad <- calls[!usable]
    at_budget <- vapply(bad, function(x) isTRUE(x$iterations >= 60), logical(1))
    failed_search <- vapply(bad, `[[`, logical(1), "line_search_failed")
    gradient <- vapply(bad, function(x) as.numeric(x$gradient), numeric(1))
    cat(sprintf("unusable evaluations: %d stopped at the 60-step inner budget, %d at a failed line search, %d otherwise;",
                sum(at_budget), sum(failed_search & !at_budget), sum(!at_budget & !failed_search)),
        sprintf("final inner gradient median %.3g, range %.3g to %.3g\n",
                stats::median(gradient, na.rm = TRUE), min(gradient, na.rm = TRUE), max(gradient, na.rm = TRUE)))
    # The finite-difference gradient evaluates each coordinate on both sides in
    # consecutive calls that differ in that coordinate alone.
    x <- t(vapply(calls, `[[`, numeric(length(fit$parameters)), "parameters"))
    pairs <- list(); i <- 1L
    while (i < length(calls)) {
      differs <- which(x[i, ] != x[i + 1L, ])
      if (length(differs) == 1L && identical(calls[[i]]$inner_tol, calls[[i + 1L]]$inner_tol)) {
        pairs[[length(pairs) + 1L]] <- c(i, i + 1L, differs); i <- i + 2L
      } else i <- i + 1L
    }
    pairs <- do.call(rbind, pairs)
    one_sided <- usable[pairs[, 1L]] != usable[pairs[, 2L]]
    cat(sprintf("finite-difference pairs: %d, holding %d of the %d unusable evaluations; penalty on one side in %d pairs, on both sides in %d\n",
                nrow(pairs), sum(!usable[pairs[, 1L]]) + sum(!usable[pairs[, 2L]]), sum(!usable),
                sum(one_sided), sum(!usable[pairs[, 1L]] & !usable[pairs[, 2L]])))
    first <- pairs[which(one_sided)[1L], ]
    step <- abs(x[first[1L], first[3L]] - x[first[2L], first[3L]]) / 2
    cat(sprintf("first one-sided pair: calls %d and %d, parameter %d, step %.3g, so that gradient component is about %.1e\n",
                first[1L], first[2L], first[3L], step, 1e100 / (2 * step)))
  }
  cat("first 16 calls (usable, inner Newton steps, objective):\n")
  for (i in seq_len(min(16L, length(calls))))
    cat(sprintf("  %2d %-5s %2s %.12f\n", i, calls[[i]]$usable, format(calls[[i]]$iterations), calls[[i]]$nll))
}

runs <- list(sparse = fit_logged("sparse"), dense = fit_logged("dense"))
for (b in names(runs)) report(b, runs[[b]])
cat(sprintf("\nthe two rejected fits, dense - sparse: objective %.3g (relative %.3g), parameter distance %.3g\n",
            runs$sparse$fit$logLik - runs$dense$fit$logLik,
            abs(runs$sparse$fit$logLik - runs$dense$fit$logLik) / abs(runs$sparse$fit$logLik),
            .gt_d_fit_distance(runs$dense$fit$parameters, runs$sparse$fit$parameters, map$prep, map$setup)))
