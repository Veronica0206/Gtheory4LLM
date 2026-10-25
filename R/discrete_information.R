# Full observed information of the Laplace negative log likelihood. Nuisance
# intercepts/threshold coordinates remain in this Hessian; they are not fixed
# while extracting the covariance block. This is approximation-conditional
# asymptotic uncertainty, not a coverage or Laplace-accuracy guarantee.
#
# Two methods form the Hessian. The finite-difference route uses second
# differences of the objective, 2p^2 + O(p) evaluations per step. The analytic
# route (gradient = "analytic") uses central differences of the analytic
# gradient, 2p gradients per step, each at a cold tight conditional mode; the
# difference matrix is symmetrized after its asymmetry is checked against
# hessian_tolerance. Both run at hessian_step and hessian_step / 2 under the
# same step-discrepancy, eigenvalue and inverse-validity checks. A refused
# gradient makes information unavailable with its reason; there is no fallback
# to the other method.
#
# A source whose covariance is on or near its boundary (smallest eigenvalue
# below 1e-6, the fit's rule) has no ordinary Wald error: its stored
# coordinates sit on or within a difference step of their natural bound, and
# along a zero factor column the covariance moves only to second order. Such a
# source is held fixed at its fitted covariance and the information is formed
# over the remaining coordinates, nuisance ones included, as the Gaussian
# engine inverts its interior block. The record says so and names each held
# source as zero or as singular but nonzero; its entries carry no sampling
# variance. When every estimated source is on its boundary nothing remains to
# condition on, and information is unavailable.

.gt_d_information_unavailable <- function(reason, boundary_components = character()) {
  list(available = FALSE, reason = reason, method = NA_character_,
       boundary_components = boundary_components, restricted_to_interior = FALSE,
       fixed_components = character(), fixed_component_kinds = character(),
       entries = NULL, entry_covariance = NULL, parameter_covariance = NULL)
}

.gt_d_information_hessian <- function(parameters, objective, step, lower, upper) {
  p <- length(parameters)
  h <- step * pmax(1, abs(parameters))
  if (any(parameters - h <= lower | parameters + h >= upper))
    stop("Central information differences contact a parameter bound.", call. = FALSE)
  value <- function(at) {
    ans <- objective(at)
    if (!is.numeric(ans) || length(ans) != 1L || !is.finite(ans))
      stop("An information evaluation is unavailable.", call. = FALSE)
    ans
  }
  center <- value(parameters)
  H <- matrix(0, p, p, dimnames = list(names(parameters), names(parameters)))
  for (i in seq_len(p)) {
    plus <- minus <- parameters
    plus[[i]] <- plus[[i]] + h[[i]]
    minus[[i]] <- minus[[i]] - h[[i]]
    H[i, i] <- (value(plus) - 2 * center + value(minus)) / h[[i]]^2
    if (i > 1L) for (j in seq_len(i - 1L)) {
      pp <- pm <- mp <- mm <- parameters
      pp[c(i, j)] <- pp[c(i, j)] + h[c(i, j)]
      pm[[i]] <- pm[[i]] + h[[i]]; pm[[j]] <- pm[[j]] - h[[j]]
      mp[[i]] <- mp[[i]] - h[[i]]; mp[[j]] <- mp[[j]] + h[[j]]
      mm[c(i, j)] <- mm[c(i, j)] - h[c(i, j)]
      H[i, j] <- H[j, i] <- (value(pp) - value(pm) - value(mp) + value(mm)) /
        (4 * h[[i]] * h[[j]])
    }
  }
  if (any(!is.finite(H))) stop("Information differences are nonfinite.", call. = FALSE)
  H
}

# Central differences of a gradient in stored coordinates: column j is
# (g(theta + h_j e_j) - g(theta - h_j e_j)) / (2 h_j), with the scalar method's
# steps and bound rule. The asymmetry is measured on the scale the step
# discrepancy uses before the matrix is symmetrized.
.gt_d_information_gradient_hessian <- function(parameters, gradient, step, lower, upper) {
  p <- length(parameters)
  h <- step * pmax(1, abs(parameters))
  if (any(parameters - h <= lower | parameters + h >= upper))
    stop("Central information differences contact a parameter bound.", call. = FALSE)
  value <- function(at) {
    g <- gradient(at)
    if (!is.numeric(g) || length(g) != p || !identical(names(g), names(parameters)) || any(!is.finite(g)))
      stop("An information gradient is unavailable.", call. = FALSE)
    g
  }
  H <- matrix(0, p, p, dimnames = list(names(parameters), names(parameters)))
  for (j in seq_len(p)) {
    plus <- minus <- parameters
    plus[[j]] <- plus[[j]] + h[[j]]
    minus[[j]] <- minus[[j]] - h[[j]]
    H[, j] <- (value(plus) - value(minus)) / (2 * h[[j]])
  }
  if (any(!is.finite(H))) stop("Information differences are nonfinite.", call. = FALSE)
  scale <- pmax(1, sqrt(outer(abs(diag(H)), abs(diag(H)))))
  list(hessian = (H + t(H)) / 2, asymmetry = max(abs(H - t(H)) / scale), gradients = 2L * p)
}

# Analytic source-covariance map, independently checked against differences of
# the natural covariance matrices. Fixed source matrices have zero derivatives.
.gt_d_information_mapping <- function(parameters, prep, groups, setup) {
  q <- prep$q
  cells <- which(lower.tri(matrix(0, q, q), diag = TRUE), arr.ind = TRUE)
  entries <- do.call(rbind, lapply(names(groups), function(source)
    data.frame(component = source, row = prep$dimensions[cells[, 1L]],
               column = prep$dimensions[cells[, 2L]], stringsAsFactors = FALSE)))
  J <- matrix(0, nrow(entries), length(parameters),
              dimnames = list(NULL, names(parameters)))
  if (!is.null(setup$fixed)) return(list(entries = entries, jacobian = J))
  offset <- length(prep$start)
  factors <- .gt_d_covariance_factors(parameters[-seq_len(offset)], setup)
  for (s in seq_along(setup$sources)) {
    L <- factors[[s]]
    for (k in seq_len(setup$per)) {
      parameter <- offset + (s - 1L) * setup$per + k
      if (identical(setup$parameterization, "exchangeable")) {
        derivative <- matrix(0, q, q)
        d <- setup$blocks[[k]]$dims
        derivative[d, d] <- setup$blocks[[k]]$shape
      } else if (identical(setup$parameterization, "variance")) {
        derivative <- matrix(0, q, q)
        derivative[k, k] <- 1
      } else {
        direction <- matrix(0, q, q)
        ij <- setup$positions[k, ]
        # A log-Cholesky diagonal is a log, so its factor entry moves by itself;
        # every Cholesky coordinate is the factor entry.
        direction[ij[[1L]], ij[[2L]]] <- if (setup$diagpos[[k]] && identical(setup$parameterization, "log_cholesky"))
          L[ij[[1L]], ij[[2L]]] else 1
        derivative <- direction %*% t(L) + L %*% t(direction)
      }
      J[(s - 1L) * nrow(cells) + seq_len(nrow(cells)), parameter] <- derivative[cells]
    }
  }
  list(entries = entries, jacobian = J)
}

.gt_d_information <- function(parameters, prep, groups, setup, control,
                              laplace = .gt_d_laplace, lower, upper,
                              numerically_accepted, boundary_components = character(),
                              gradient = NULL) {
  unavailable <- function(reason) .gt_d_information_unavailable(reason, boundary_components)
  if (!isTRUE(control$check_hessian))
    return(unavailable("Observed information was not requested; use discrete check_hessian=TRUE."))
  if (!isTRUE(numerically_accepted))
    return(unavailable("Observed information requires a numerically accepted fit."))
  # Each stored coordinate's source; nuisance coordinates have none.
  owner <- rep(NA_character_, length(parameters))
  if (is.null(setup$fixed))
    owner[length(prep$start) + seq_len(length(setup$sources) * setup$per)] <- rep(setup$sources, each = setup$per)
  held <- if (is.null(setup$fixed)) intersect(setup$sources, boundary_components) else character()
  interior <- !owner %in% held
  if (length(held) && !any(interior & !is.na(owner)))
    return(unavailable("Every estimated source covariance is on or near its boundary; no interior block remains for Wald errors."))
  # A held source is zero when its largest eigenvalue is negligible on the
  # latent scale, whose residual variance is 1 (probit) or about 3.3 (logit).
  held_kinds <- if (length(held)) {
    factors <- .gt_d_covariance_factors(parameters[-seq_len(length(prep$start))], setup)
    vapply(held, function(s) if (max(eigen(tcrossprod(factors[[s]]), symmetric = TRUE,
                                           only.values = TRUE)$values) <= 1e-8) "zero" else "singular_nonzero",
           character(1))
  } else character()
  attempt <- tryCatch({
    complete <- function(x) {
      at <- parameters
      at[interior] <- x
      at
    }
    objective <- function(x) {
      ans <- laplace(complete(x), prep, groups, setup, control, details = TRUE)
      if (!isTRUE(ans$valid) || !isTRUE(ans$inner_converged) || !is.finite(ans$nll))
        stop("A conditional mode failed during information evaluation.", call. = FALSE)
      ans$nll
    }
    block_gradient <- if (!is.null(gradient)) function(x) {
      g <- gradient(complete(x))
      if (!is.numeric(g) || length(g) != length(parameters))
        stop("An information gradient is unavailable.", call. = FALSE)
      g[interior]
    }
    at <- parameters[interior]
    asymmetry <- NA_real_
    gradient_evaluations <- 0L
    if (is.null(gradient)) {
      coarse <- .gt_d_information_hessian(at, objective, control$hessian_step, lower[interior], upper[interior])
      fine <- .gt_d_information_hessian(at, objective, control$hessian_step / 2, lower[interior], upper[interior])
    } else {
      coarse <- .gt_d_information_gradient_hessian(at, block_gradient, control$hessian_step,
                                                   lower[interior], upper[interior])
      fine <- .gt_d_information_gradient_hessian(at, block_gradient, control$hessian_step / 2,
                                                 lower[interior], upper[interior])
      asymmetry <- max(coarse$asymmetry, fine$asymmetry)
      gradient_evaluations <- coarse$gradients + fine$gradients
      if (asymmetry > control$hessian_tolerance)
        stop("Observed information from analytic gradient differences is not symmetric within hessian_tolerance.",
             call. = FALSE)
      coarse <- coarse$hessian
      fine <- fine$hessian
    }
    scale <- pmax(1, sqrt(outer(abs(diag(fine)), abs(diag(fine)))))
    discrepancy <- max(abs(coarse - fine) / scale)
    if (discrepancy > control$hessian_tolerance)
      stop("Observed information is unstable across finite-difference step sizes.", call. = FALSE)
    eigenvalues <- eigen(fine, symmetric = TRUE, only.values = TRUE)$values
    if (min(eigenvalues) <= 0 || max(eigenvalues) / min(eigenvalues) > 1e12)
      stop("Observed information is nonpositive or too ill-conditioned for Wald errors.", call. = FALSE)
    block <- chol2inv(chol(fine))
    identity <- diag(nrow(fine))
    inverse_checks <- lapply(seq_len(nrow(fine)), function(j)
      .gt_d_solve_check(fine, identity[, j], block[, j]))
    if (!all(vapply(inverse_checks, function(x) isTRUE(x$valid), logical(1))))
      stop("The information inverse failed its numerical solve-validity check.", call. = FALSE)
    # Held coordinates have no sampling covariance; their standard errors are
    # NA, not a zero that would read as an estimate known without error.
    covariance <- matrix(0, length(parameters), length(parameters),
                         dimnames = list(names(parameters), names(parameters)))
    covariance[interior, interior] <- block
    standard_errors <- sqrt(diag(covariance))
    standard_errors[!interior] <- NA_real_
    mapping <- .gt_d_information_mapping(parameters, prep, groups, setup)
    entry_covariance <- mapping$jacobian %*% covariance %*% t(mapping$jacobian)
    if (any(!is.finite(entry_covariance)))
      stop("The source-covariance uncertainty map is nonfinite.", call. = FALSE)
    list(available = TRUE, reason = NA_character_,
         method = "full_observed_laplace_information_delta_method",
         parameter_covariance = covariance, parameter_standard_errors = standard_errors,
         hessian = fine, hessian_scale = "negative_log_likelihood",
         information_coordinates = names(parameters)[interior],
         hessian_method = if (is.null(gradient)) "objective_second_differences" else "analytic_gradient_differences",
         hessian_asymmetry = asymmetry, information_gradient_evaluations = gradient_evaluations,
         hessian_step = control$hessian_step / 2,
         step_discrepancy = discrepancy, step_tolerance = control$hessian_tolerance,
         condition_number = max(eigenvalues) / min(eigenvalues),
         inverse_backward_error = max(vapply(inverse_checks, `[[`, numeric(1), "solve_backward_error")),
         inverse_validity_bound = inverse_checks[[1L]]$solve_validity_bound,
         entries = mapping$entries, entry_covariance = entry_covariance,
         entry_jacobian = mapping$jacobian, boundary_components = boundary_components,
         restricted_to_interior = length(held) > 0L,
         fixed_components = if (!is.null(setup$fixed)) names(groups) else held,
         fixed_component_kinds = if (!is.null(setup$fixed))
           stats::setNames(rep("specified_fixed_covariance", length(groups)), names(groups)) else held_kinds,
         interpretation = if (length(held)) paste("Asymptotic Wald standard errors conditional on",
           paste0(.gt_conditioning_clause(held, held_kinds), ","),
           "because a source covariance on or near its boundary has no ordinary Wald error.",
           "They describe the remaining components only.") else NA_character_,
         approximation = "Conditional on first-order Laplace and asymptotic information; coverage not established.")
  }, error = function(e) unavailable(conditionMessage(e)))
  attempt
}
