# Private sparse random-design construction.
#
# This file adds a representation, not a backend. It builds the same random
# coordinate system the dense implementation builds, in sparse storage, and
# nothing else: no Hessian assembly, no factorization, no conditional-mode
# solve, no optimizer involvement, no backend selection, and no public API.
# Those are separate steps, and keeping them separate is what makes a moved
# reference value attributable to coordinate construction alone.
#
# The coordinate convention is the dense one and must stay that way, because
# the frozen fixed-parameter reference is expressed in it. Rows hold every
# observation for the first latent dimension, then the next. Columns run over
# sources in source order; within a source, every group level for the first
# latent coordinate, then the next. The column count is always
# sum(nlevels) * q, including for sources whose covariance factor is entirely
# zero: such a source keeps its columns and contributes no stored entries.
# Dropping those columns would renumber every coordinate after them.

.gt_d_sparse_validate <- function(groups, factors, n, q) {
  dimensions <- c(n, q)
  if (!is.numeric(dimensions) || length(dimensions) != 2L ||
      any(!is.finite(dimensions)) || any(dimensions < 1) ||
      any(dimensions != floor(dimensions)) || !is.list(groups) ||
      !length(groups) || !is.list(factors) || length(factors) != length(groups))
    .gt_d_stop("Invalid sparse backend dimensions or source factors.")
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
        !is.matrix(L) || !is.numeric(L) || !identical(dim(L), c(q, q)) || any(!is.finite(L)))
      .gt_d_stop("Invalid sparse backend group indices or covariance factor.")
  }
  list(n = n, q = q)
}

# Where each source's columns live. Recorded once here rather than recomputed
# by every later caller, because a coordinate boundary derived twice is a
# coordinate boundary that can disagree with itself.
.gt_d_sparse_layout <- function(groups, q) {
  levels <- vapply(groups, `[[`, integer(1), "nlevels")
  width <- levels * q
  last <- cumsum(width)
  data.frame(source = if (is.null(names(groups))) seq_along(groups) else names(groups),
             levels = levels, columns = width,
             first_column = as.integer(last - width + 1L), last_column = as.integer(last),
             stringsAsFactors = FALSE, row.names = NULL)
}

.gt_d_sparse_W <- function(groups, factors, n, q) {
  # Triplets, never a dense intermediate. Materializing the dense matrix and
  # converting would produce the right object and defeat the entire purpose of
  # the exercise, since the dense allocation is the thing being removed.
  rows <- vector("list", length(groups) * q * q)
  columns <- vector("list", length(rows))
  values <- vector("list", length(rows))
  observation <- seq_len(n)
  offset <- 0L
  slot <- 0L
  for (s in seq_along(groups)) {
    group <- groups[[s]]
    L <- factors[[s]]
    for (a in seq_len(q)) for (b in seq_len(q)) if (L[a, b] != 0) {
      slot <- slot + 1L
      rows[[slot]] <- (a - 1L) * n + observation
      columns[[slot]] <- offset + (b - 1L) * group$nlevels + group$index
      values[[slot]] <- rep.int(L[a, b], n)
    }
    offset <- offset + q * group$nlevels
  }
  total <- sum(vapply(groups, `[[`, integer(1), "nlevels")) * q
  if (!slot)
    # Every factor is exactly zero. The coordinate system still exists and must
    # keep its shape; it simply stores nothing.
    return(Matrix::sparseMatrix(i = integer(0), j = integer(0), x = numeric(0),
                                dims = c(n * q, total)))
  Matrix::sparseMatrix(i = unlist(rows[seq_len(slot)]), j = unlist(columns[seq_len(slot)]),
                       x = unlist(values[seq_len(slot)]), dims = c(n * q, total))
}

.gt_d_sparse_backend <- function(groups, factors, n, q) {
  checked <- .gt_d_sparse_validate(groups, factors, n, q)
  n <- checked$n
  q <- checked$q
  W <- .gt_d_sparse_W(groups, factors, n, q)
  structure(list(W = W, n = n, q = q, layout = .gt_d_sparse_layout(groups, q),
                 # Stored entries, not a scalability claim. Factor fill and
                 # measured memory are separate questions and are not answered
                 # by this number.
                 stored_entries = as.integer(Matrix::nnzero(W)),
                 random_dimension = ncol(W)),
            class = "gt_discrete_sparse_backend")
}
