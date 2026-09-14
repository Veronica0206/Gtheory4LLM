# Dense matrix operations for the private discrete backend contract.
# Inputs come from response preparation and covariance setup. No fitted state,
# mode cache, source selection, or optimizer decisions live in this object.

.gt_d_dense_backend <- function(groups, factors, n, q) {
  dimensions <- c(n, q)
  if (!is.numeric(dimensions) || length(dimensions) != 2L ||
      any(!is.finite(dimensions)) || any(dimensions < 1) ||
      any(dimensions != floor(dimensions)) || !is.list(groups) ||
      !length(groups) || !is.list(factors) || length(factors) != length(groups))
    .gt_d_stop("Invalid dense backend dimensions or source factors.")
  n <- as.integer(n)
  q <- as.integer(q)
  for (s in seq_along(groups)) {
    group <- groups[[s]]
    L <- factors[[s]]
    if (!is.list(group) || !is.integer(group$nlevels) || length(group$nlevels) != 1L ||
        !is.finite(group$nlevels) || group$nlevels < 1 || group$nlevels != floor(group$nlevels) ||
        !is.numeric(group$index) || length(group$index) != n || anyNA(group$index) ||
        any(!is.finite(group$index)) || any(group$index != floor(group$index)) ||
        any(group$index < 1 | group$index > group$nlevels) ||
        !is.matrix(L) || !is.numeric(L) || !identical(dim(L), c(as.integer(q), as.integer(q))) ||
        any(!is.finite(L)))
      .gt_d_stop("Invalid dense backend group indices or covariance factor.")
  }
  structure(list(W = .gt_d_W(groups, factors, n, q), n = n, q = q),
            class = "gt_discrete_dense_backend")
}

.gt_d_W <- function(groups, factors, n, q) {
  dimension <- sum(vapply(groups, `[[`, integer(1), "nlevels")) * q
  W <- matrix(0, n * q, dimension)
  offset <- 0L
  for (s in seq_along(groups)) {
    group <- groups[[s]]
    L <- factors[[s]]
    for (a in seq_len(q)) for (b in seq_len(q)) if (L[a, b] != 0)
      W[cbind((a - 1L) * n + seq_len(n), offset + (b - 1L) * group$nlevels + group$index)] <- L[a, b]
    offset <- offset + q * group$nlevels
  }
  W
}

.gt_d_dense_hessian <- function(curvature, W, n) {
  H <- diag(ncol(W))
  for (curv in curvature) {
    if (!is.null(curv$diagonal)) {
      row <- (curv$dims - 1L) * n + seq_len(n)
      A <- W[row, , drop = FALSE]
      H <- H + crossprod(A, A * pmax(0, curv$diagonal))
    } else {
      p <- curv$probability
      for (a in seq_along(curv$dims)) {
        ia <- (curv$dims[[a]] - 1L) * n + seq_len(n)
        A <- W[ia, , drop = FALSE]
        for (bb in seq_along(curv$dims)) {
          ib <- (curv$dims[[bb]] - 1L) * n + seq_len(n)
          B <- W[ib, , drop = FALSE]
          weight <- (as.integer(a == bb) * p[, a]) - p[, a] * p[, bb]
          H <- H + crossprod(A, B * weight)
        }
      }
    }
  }
  (H + t(H)) / 2
}

.gt_d_dense_evaluate <- function(eta, parameters, prep, backend) {
  response <- .gt_d_response_kernel(eta, parameters, prep)
  if (response$valid)
    response$H <- .gt_d_dense_hessian(response$curvature, backend$W, prep$n)
  response
}

# Compatibility adapter for internal callers that previously requested W-based
# curvature through the response function. New mode code uses the split kernel.
.gt_d_response <- function(eta, parameters, prep, W = NULL) {
  response <- .gt_d_response_kernel(eta, parameters, prep)
  if (response$valid && !is.null(W)) {
    if (!is.matrix(W) || !is.numeric(W) || nrow(W) != prep$n * prep$q || any(!is.finite(W)))
      .gt_d_stop("Dense response matrix does not match the prepared response dimensions.")
    response$H <- .gt_d_dense_hessian(response$curvature, W, prep$n)
  }
  response
}
