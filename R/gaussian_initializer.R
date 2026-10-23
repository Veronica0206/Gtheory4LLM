# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
#
# Square-root initialization for the exact balanced Gaussian engine.
#
# The engine evaluates the exact deviance through OpenMx algebra as
# log|C_m| + tr(C_m^{-1} S_m) over the factorial strata. Where a stratum
# covariance is nearly singular and badly conditioned, forming C_m from its
# factors and inverting it loses information that the factors themselves still
# carry: on the six-outcome mental-health panel the default start led the
# optimizer into such a region, the native objective came out hugely negative,
# and the fit was correctly refused by the independent likelihood check.
#
# This file evaluates the same deviance in square-root form. The stratum
# covariance root is the QR factor of the stacked, weighted source factors, the
# stratum cross-product enters through its own root (computed once by
# gtheory_prepare()), and the quadratic form is a triangular solve. The value is
# the exact deviance, checked against the independent evaluation before any
# handoff, and the gradient is analytic. It is used for one purpose: after an
# ordinary optimizer attempt has been refused, a bounded L-BFGS-B search on this
# form supplies starting components for the next ordinary attempt. Nothing it
# computes is returned as an estimate. The ordinary optimizer, the
# covariance-scale stationarity check and the independent likelihood check
# decide acceptance exactly as before, with the same tolerances and budget.

# Value, analytic gradient and reconstructed components of the exact deviance at
# one parameter vector, in the model's own optimizer coordinates. A block with
# an empty root (the profiled mean stratum under ML) contributes no quadratic
# term. Every evaluation is scaled by the outcomes' observed standard
# deviations so that the QR factorization sees comparable rows.
.gt_square_root_evaluate <- function(parameter, context) {
  stopifnot(identical(names(parameter), names(context$parameter)), all(is.finite(parameter)),
            all(parameter >= context$lower), all(parameter <= context$upper))
  D <- context$D
  units <- context$units
  stopifnot(length(units) == D, all(is.finite(units)), all(units > 0))
  roots <- components <- scores <- list()
  for (g in names(context$sources)) {
    s <- context$sources[[g]]
    v <- parameter[s$labels]
    if (s$type == "diagonal") {
      variance <- v * s$scales
      if (any(variance < 0)) stop("Negative source variance; no projection is applied.", call. = FALSE)
      L <- diag(sqrt(variance), D)
    } else if (s$type == "pooled") {
      if (v < 0) stop("Negative pooled variance; no projection is applied.", call. = FALSE)
      L <- diag(sqrt(v), D)
    } else {
      L <- matrix(0, D, D)
      L[s$select] <- v
    }
    roots[[g]] <- L
    components[[g]] <- tcrossprod(L)
    scores[[g]] <- matrix(0, D, D)
  }
  value <- context$constant
  quadratics <- numeric(length(context$blocks))
  index <- 0L
  for (b in context$blocks) {
    index <- index + 1L
    groups <- names(b$weights)[b$weights > 0]
    A <- do.call(cbind, lapply(groups, function(g) sqrt(b$weights[[g]]) * roots[[g]]))
    A <- sweep(A, 1L, units, "/")
    decomposition <- qr(t(A), LAPACK = TRUE)
    R <- qr.R(decomposition)
    pivot <- decomposition$pivot
    if (any(!is.finite(R)) || any(diag(R) == 0))
      stop("Singular or nonfinite covariance root; evaluation refused.", call. = FALSE)
    scaled_root <- sweep(b$root, 1L, units, "/")
    W <- forwardsolve(t(R), scaled_root[pivot, , drop = FALSE])
    quadratic <- sum(W * W)
    quadratics[index] <- quadratic
    block <- b$df * (2 * sum(log(abs(diag(R)))) + 2 * sum(log(units))) + quadratic
    if (!is.finite(block)) stop("Nonfinite likelihood block; evaluation refused.", call. = FALSE)
    value <- value + block
    V <- backsolve(R, W)
    permuted_score <- b$df * chol2inv(R) - tcrossprod(V)
    H <- matrix(0, D, D)
    H[pivot, pivot] <- permuted_score
    H <- H / outer(units, units)
    for (g in groups) scores[[g]] <- scores[[g]] + b$weights[[g]] * H
  }
  gradient <- stats::setNames(numeric(length(parameter)), names(parameter))
  for (g in names(context$sources)) {
    s <- context$sources[[g]]
    if (s$type == "diagonal") gradient[s$labels] <- diag(scores[[g]]) * s$scales
    else if (s$type == "pooled") gradient[s$labels] <- sum(diag(scores[[g]]))
    else gradient[s$labels] <- (2 * scores[[g]] %*% roots[[g]])[s$select]
  }
  if (!is.finite(value) || any(!is.finite(gradient)))
    stop("Nonfinite objective or gradient; evaluation refused.", call. = FALSE)
  list(value = value, gradient = gradient, components = components, quadratics = quadratics)
}

# The fixed context of one model: the free parameters with their labels and
# bounds as OpenMx holds them, the map from each source to its coordinates, the
# exact strata with their cross-product roots and source weights, the
# likelihood constant, and a fixed parameter metric (standard deviation units
# for factor entries, one for scaled variances). Built from the original model,
# never from a failed endpoint.
.gt_square_root_context <- function(model, prepared, types, algebra_names,
                                    masks, weights, reml) {
  D <- prepared$D
  parameter <- OpenMx::omxGetParameters(model)
  lower <- OpenMx::omxGetParameters(model, fetch = "lbound")
  upper <- OpenMx::omxGetParameters(model, fetch = "ubound")
  lower[is.na(lower)] <- -Inf
  upper[is.na(upper)] <- Inf
  if (anyDuplicated(names(parameter)) || !identical(names(lower), names(parameter)) ||
      !identical(names(upper), names(parameter)))
    stop("Initializer parameter labels and bounds do not match.", call. = FALSE)
  sources <- list()
  labels <- character()
  metric <- stats::setNames(rep(NA_real_, length(parameter)), names(parameter))
  for (g in names(types)) {
    nm <- algebra_names[[g]]
    type <- types[[g]]
    if (type == "diagonal") {
      mat <- model@matrices[[paste0(nm, "_V")]]
      labs <- diag(mat@labels)
      scales <- diag(model@matrices[[paste0(nm, "_scale")]]@values)
      sources[[g]] <- list(type = type, labels = labs, scales = scales)
      metric[labs] <- 1
    } else if (type == "pooled") {
      mat <- model@matrices[[paste0(nm, "_scalar")]]
      labs <- as.vector(mat@labels[mat@free])
      sources[[g]] <- list(type = type, labels = labs)
      metric[labs] <- min(prepared$observed_variances)
    } else {
      mat <- model@matrices[[paste0(nm, "_L")]]
      select <- lower.tri(matrix(0, D, D), diag = TRUE)
      if (!identical(unname(mat@free), select))
        stop("Unexpected source-factor free-coordinate map.", call. = FALSE)
      labs <- mat@labels[select]
      sources[[g]] <- list(type = type, labels = labs, select = select)
      metric[labs] <- sqrt(prepared$observed_variances)[row(select)[select]]
    }
    labels <- c(labels, labs)
  }
  if (anyNA(labels) || anyDuplicated(labels) || !setequal(labels, names(parameter)) ||
      any(!is.finite(metric)) || any(metric <= 0))
    stop("Invalid initializer coordinate map or fixed metric.", call. = FALSE)
  blocks <- list()
  for (s in prepared$strata) {
    if (reml && s$mask == 0L) next
    active <- bitwAnd(as.integer(masks), s$mask) == s$mask
    w <- weights
    w[!active] <- 0
    root <- if (s$mask == 0L) matrix(numeric(), D, 0L) else s$root
    if (!is.matrix(root) || nrow(root) != D || any(!is.finite(root)))
      stop("Prepared exact cross-product root missing.", call. = FALSE)
    blocks[[as.character(s$mask)]] <- list(df = s$df, root = root, weights = w, mask = s$mask)
  }
  list(parameter = parameter, lower = lower, upper = upper, parscale = metric, D = D,
       outcomes = prepared$outcomes,
       N = prepared$N, units = sqrt(unname(prepared$observed_variances)),
       sources = sources, blocks = blocks,
       constant = (prepared$N - as.integer(reml)) * D * log(2 * pi) +
         if (reml) D * log(prepared$N) else 0,
       reml = reml,
       root_max_reconstruction_error = max(vapply(prepared$strata, function(s)
         max(abs(tcrossprod(s$root) - s$SSCP)) / max(1, abs(s$SSCP)), numeric(1))))
}

# One bounded L-BFGS-B search on the square-root form from the original
# coordinates. Its endpoint is eligible as a starting vector only when the
# optimizer reports convergence, the point is inside the bounds, and the
# independent deviance evaluation reproduces the square-root value to 1e-5.
# The record is compact: it carries the decision, the endpoint's coordinates and
# covariance components (handed to the next ordinary attempt through the
# ordinary start path), and the optimizer's counts, never the context or any
# fitted estimate.
.gt_square_root_initialize <- function(context, independent) {
  started <- proc.time()[["elapsed"]]
  calls <- 0L
  cache <- new.env(parent = emptyenv())
  cache$parameter <- NULL
  cache$answer <- NULL
  evaluate <- function(x) {
    names(x) <- names(context$parameter)
    if (identical(x, cache$parameter)) return(cache$answer)
    answer <- .gt_square_root_evaluate(x, context)
    cache$parameter <- x
    cache$answer <- answer
    answer
  }
  objective <- function(x) {
    calls <<- calls + 1L
    evaluate(x)$value
  }
  derivative <- function(x) evaluate(x)$gradient
  record <- list(algorithm = "square_root_cold_v1", status = "started", eligible = FALSE,
    original_parameter = context$parameter, metric = "standard deviation units for factor entries, one for scaled variances",
    fnscale = context$N, maxit = 10000L, factr = 1e3, pgtol = 0,
    independent_tolerance = 1e-5, no_fitted_endpoint_reuse = TRUE,
    scope = "Initial values only; ordinary final acceptance is unchanged.")
  result <- tryCatch({
    opt <- stats::optim(context$parameter, objective, derivative, method = "L-BFGS-B",
      lower = context$lower, upper = context$upper,
      control = list(maxit = 10000L, factr = 1e3, pgtol = 0, fnscale = context$N,
                     parscale = context$parscale))
    names(opt$par) <- names(context$parameter)
    answer <- evaluate(opt$par)
    reconstructed <- independent(answer$components)
    discrepancy <- abs(reconstructed - answer$value)
    eligible <- identical(opt$convergence, 0L) && is.finite(answer$value) &&
      is.finite(reconstructed) && all(opt$par >= context$lower) &&
      all(opt$par <= context$upper) && discrepancy <= 1e-5
    components <- lapply(answer$components, function(M) {
      dimnames(M) <- list(context$outcomes, context$outcomes)
      M
    })
    list(status = if (eligible) "handoff_eligible" else "refused", eligible = eligible,
      components = components,
      optimizer_convergence = opt$convergence, optimizer_message = opt$message,
      optimizer_counts = opt$counts, budget_exhausted = identical(opt$convergence, 1L),
      parameter = opt$par, objective = answer$value, independent_deviance = reconstructed,
      independent_difference = discrepancy, maximum_raw_gradient = max(abs(answer$gradient)),
      objective_calls = calls)
  }, error = function(e) list(status = "refused", eligible = FALSE, error = conditionMessage(e),
    objective_calls = calls))
  record[names(result)] <- result
  record$elapsed_seconds <- unname(proc.time()[["elapsed"]] - started)
  record
}
