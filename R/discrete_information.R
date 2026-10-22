# Full observed information of the Laplace negative log likelihood. Nuisance
# intercepts/threshold coordinates remain in this Hessian; they are not fixed
# while extracting the covariance block. This is approximation-conditional
# asymptotic uncertainty, not a coverage or Laplace-accuracy guarantee.

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
                              numerically_accepted, boundary_components = character()) {
  unavailable <- function(reason) .gt_d_information_unavailable(reason, boundary_components)
  if (!isTRUE(control$check_hessian))
    return(unavailable("Observed information was not requested; use discrete check_hessian=TRUE."))
  if (!isTRUE(numerically_accepted))
    return(unavailable("Observed information requires a numerically accepted fit."))
  if (length(boundary_components) && is.null(setup$fixed))
    return(unavailable("A source covariance is on or near its boundary; ordinary Wald errors are unavailable."))
  attempt <- tryCatch({
    objective <- function(at) {
      ans <- laplace(at, prep, groups, setup, control, details = TRUE)
      if (!isTRUE(ans$valid) || !isTRUE(ans$inner_converged) || !is.finite(ans$nll))
        stop("A conditional mode failed during information evaluation.", call. = FALSE)
      ans$nll
    }
    coarse <- .gt_d_information_hessian(parameters, objective, control$hessian_step, lower, upper)
    fine <- .gt_d_information_hessian(parameters, objective, control$hessian_step / 2, lower, upper)
    scale <- pmax(1, sqrt(outer(abs(diag(fine)), abs(diag(fine)))))
    discrepancy <- max(abs(coarse - fine) / scale)
    if (discrepancy > control$hessian_tolerance)
      stop("Observed information is unstable across finite-difference step sizes.", call. = FALSE)
    eigenvalues <- eigen(fine, symmetric = TRUE, only.values = TRUE)$values
    if (min(eigenvalues) <= 0 || max(eigenvalues) / min(eigenvalues) > 1e12)
      stop("Observed information is nonpositive or too ill-conditioned for Wald errors.", call. = FALSE)
    covariance <- chol2inv(chol(fine))
    dimnames(covariance) <- dimnames(fine)
    identity <- diag(nrow(fine))
    inverse_checks <- lapply(seq_len(nrow(fine)), function(j)
      .gt_d_solve_check(fine, identity[, j], covariance[, j]))
    if (!all(vapply(inverse_checks, function(x) isTRUE(x$valid), logical(1))))
      stop("The information inverse failed its numerical solve-validity check.", call. = FALSE)
    mapping <- .gt_d_information_mapping(parameters, prep, groups, setup)
    entry_covariance <- mapping$jacobian %*% covariance %*% t(mapping$jacobian)
    if (any(!is.finite(entry_covariance)))
      stop("The source-covariance uncertainty map is nonfinite.", call. = FALSE)
    list(available = TRUE, reason = NA_character_,
         method = "full_observed_laplace_information_delta_method",
         parameter_covariance = covariance, parameter_standard_errors = sqrt(diag(covariance)),
         hessian = fine, hessian_scale = "negative_log_likelihood",
         hessian_step = control$hessian_step / 2,
         step_discrepancy = discrepancy, step_tolerance = control$hessian_tolerance,
         condition_number = max(eigenvalues) / min(eigenvalues),
         inverse_backward_error = max(vapply(inverse_checks, `[[`, numeric(1), "solve_backward_error")),
         inverse_validity_bound = inverse_checks[[1L]]$solve_validity_bound,
         entries = mapping$entries, entry_covariance = entry_covariance,
         entry_jacobian = mapping$jacobian, boundary_components = boundary_components,
         restricted_to_interior = FALSE,
         fixed_components = if (!is.null(setup$fixed)) names(groups) else character(),
         fixed_component_kinds = if (!is.null(setup$fixed))
           stats::setNames(rep("specified_fixed_covariance", length(groups)), names(groups)) else character(),
         approximation = "Conditional on first-order Laplace and asymptotic information; coverage not established.")
  }, error = function(e) unavailable(conditionMessage(e)))
  attempt
}
