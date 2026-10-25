# Selected inverse of the sparse conditional Hessian's Cholesky factor.
#
# The analytic gradient of the first-order Laplace objective needs entries of
# H^{-1} on the structural pattern of H's Cholesky factor: the trace of H^{-1}
# against each parameter derivative of H, and for every observation the small
# block W_i H^{-1} W_i'. The dense inverse is never formed. The recurrence runs
# in compiled code (src/gt_selected_inverse.c) on the factor the sparse engine
# already computes; these functions hand it the factor in the storage it
# expects, map original coordinates to the factor's permuted positions, and
# turn its refusals into the package's.
#
# Coordinates. The factor is computed with a fill-reducing permutation, so
# H[permutation, permutation] = L L': permuted position k holds original
# coordinate permutation[k], and inverse_permutation maps an original
# coordinate to its permuted position. Every function here takes and returns
# ORIGINAL coordinates; the permuted positions never leave this file.
#
# Refusals. An entry outside the factor's pattern is refused, never read as
# zero: a derivative of H can be nonzero where H's current entry is zero, and
# a silently omitted entry would give a plausible wrong gradient. The compiled
# routines also refuse malformed storage, a nonpositive or nonfinite pivot, a
# nonfinite result and any input beyond the declared caps; the caps bound
# allocation and work before anything is allocated and are reported by
# .gt_selected_caps(), not estimates of what a machine can afford.
#
# A fit reaches these only through the analytic gradient route that the
# discrete control requests (gradient = "analytic"); the objective, the
# conditional mode and every acceptance rule are untouched.

.gt_selected_platform <- function() .Call(gt_selected_platform)

.gt_selected_caps <- function() .Call(gt_selected_caps)

# The selected inverse of the factor in `factorization`, a result of
# .gt_d_sparse_factor() or the Matrix factorization inside it. The returned
# values sit on the factor's own pattern, in its permuted coordinates, with the
# permutation retained for the queries below.
.gt_selected_inverse <- function(factorization) {
  factor <- if (inherits(factorization, "gt_discrete_sparse_factor")) factorization$factor else factorization
  if (!methods::is(factor, "CHMfactor"))
    .gt_d_stop("A selected inverse needs the sparse Cholesky factorization from .gt_d_sparse_factor().")
  expanded <- Matrix::expand(factor)
  L <- expanded$L
  if (!methods::is(L, "dtCMatrix") || !identical(L@uplo, "L") || !identical(L@diag, "N"))
    .gt_d_stop("The expanded Cholesky factor is not a stored lower-triangular sparse matrix.")
  n <- nrow(L)
  permutation <- as.integer(expanded$P@perm)
  # An unpermuted factorization stores an empty perm slot; expand() reports the
  # identity for it. A permuted one stores the same permutation zero-based.
  recorded <- if (length(factor@perm)) as.integer(factor@perm) + 1L else seq_len(n)
  if (length(permutation) != n || anyNA(permutation) || !identical(sort(permutation), seq_len(n)) ||
      !identical(permutation, recorded))
    .gt_d_stop("The factor's permutation is not a permutation of its coordinates.")
  answer <- .Call(gt_selected_inverse, L@p, L@i, L@x)
  structure(list(p = L@p, i = L@i, x = answer$x, dimension = n,
                 permutation = permutation, inverse_permutation = match(seq_len(n), permutation),
                 factor_entries = answer$factor_entries, inner_products = answer$inner_products,
                 value_bytes = answer$value_bytes, platform = .gt_selected_platform()),
            class = "gt_selected_inverse")
}

.gt_selected_check <- function(object) {
  if (!inherits(object, "gt_selected_inverse"))
    .gt_d_stop("Selected inverse queries need the result of .gt_selected_inverse().")
}

.gt_selected_positions <- function(object, rows, columns) {
  n <- object$dimension
  if (!is.numeric(rows) || !is.numeric(columns) || length(rows) != length(columns) ||
      anyNA(rows) || anyNA(columns) || any(rows != floor(rows)) || any(columns != floor(columns)) ||
      any(rows < 1 | rows > n) || any(columns < 1 | columns > n))
    .gt_d_stop("Selected inverse queries need original coordinates between 1 and the dimension, in pairs.")
  list(rows = object$inverse_permutation[as.integer(rows)],
       columns = object$inverse_permutation[as.integer(columns)])
}

# Entries of H^{-1} at original coordinates, from either triangle. Positions
# outside the factor's pattern are refused.
.gt_selected_entries <- function(object, rows, columns) {
  .gt_selected_check(object)
  at <- .gt_selected_positions(object, rows, columns)
  .Call(gt_selected_queries, object$p, object$i, object$x, at$rows, at$columns)
}

# trace(H^{-1} D) for a symmetric derivative matrix D in original coordinates
# whose nonzero support lies in the factor's pattern. The inverse is symmetric,
# so the trace is the sum over D's stored entries of S_ij D_ij. Finite inputs
# can still overflow in that sum, and a nonfinite trace is refused by name.
.gt_selected_trace <- function(object, derivative) {
  .gt_selected_check(object)
  n <- object$dimension
  D <- if (methods::is(derivative, "sparseMatrix")) derivative else
    Matrix::Matrix(as.matrix(derivative), sparse = TRUE)
  D <- methods::as(methods::as(D, "generalMatrix"), "CsparseMatrix")
  if (nrow(D) != n || ncol(D) != n || any(!is.finite(D@x)))
    .gt_d_stop("A selected trace needs a finite square derivative matrix of the factor's dimension.")
  stored <- Matrix::summary(D)
  keep <- stored$x != 0
  if (!any(keep)) return(0)
  value <- sum(.gt_selected_entries(object, stored$i[keep], stored$j[keep]) * stored$x[keep])
  if (!is.finite(value))
    .gt_d_stop("Selected inverse: the trace is not finite; the products of inverse entries and derivative values overflow.")
  value
}

# Local contractions for observations that share one local design. `index` is
# an n-by-k integer matrix of each observation's k original random
# coordinates, `design` the q-by-k local design W_i common to all of them, and
# `curvature` an n-by-q-by-q array of response curvature blocks. Returns
# Q[i, , ] = W_i S_i W_i' and the q-by-k sum over observations of C_i W_i S_i,
# where S_i is the k-by-k block of H^{-1} at the observation's coordinates.
.gt_selected_contractions <- function(object, index, design, curvature) {
  .gt_selected_check(object)
  m <- object$dimension
  if (!is.matrix(index) || !is.numeric(index) || !length(index) || anyNA(index) ||
      any(index != floor(index)) || any(index < 1 | index > m))
    .gt_d_stop("Selected contractions need an integer matrix of original random coordinates, one row per observation.")
  n <- nrow(index)
  k <- ncol(index)
  if (!is.matrix(design) || !is.numeric(design) || ncol(design) != k || !nrow(design) || any(!is.finite(design)))
    .gt_d_stop("Selected contractions need a finite local design with one column per random coordinate.")
  q <- nrow(design)
  if (!is.numeric(curvature) || length(curvature) != n * q * q || any(!is.finite(curvature)) ||
      (!is.null(dim(curvature)) && !identical(as.integer(dim(curvature)), c(n, q, q))))
    .gt_d_stop("Selected contractions need a finite n-by-q-by-q curvature array.")
  storage.mode(index) <- "integer"
  storage.mode(design) <- "double"
  answer <- .Call(gt_selected_contractions, object$p, object$i, object$x, object$inverse_permutation,
                  index, design, as.double(curvature))
  list(Q = array(answer$Q, c(n, q, q)), factor_trace = answer$factor_trace,
       local_queries_upper_bound = answer$local_queries_upper_bound, scratch_bytes = answer$scratch_bytes)
}

# The geometry the contractions need, from the sparse engine's retained
# context. Each observation's random coordinates in the sparse design's column
# order, one row per observation: for source s with column offset o_s, latent
# dimension b and the observation's level l, the coordinate
# o_s + (b - 1) * nlevels_s + l. Columns are ordered by source, then dimension.
.gt_selected_local_index <- function(context) {
  if (!inherits(context, "gt_discrete_sparse_context"))
    .gt_d_stop("The local index needs a context from .gt_d_sparse_context().")
  groups <- context$groups
  q <- context$q
  columns <- vector("list", length(groups) * q)
  slot <- 0L
  for (s in seq_along(groups)) for (b in seq_len(q)) {
    slot <- slot + 1L
    columns[[slot]] <- context$offsets[[s]] + (b - 1L) * groups[[s]]$nlevels + groups[[s]]$index
  }
  index <- do.call(cbind, columns)
  storage.mode(index) <- "integer"
  index
}

# The local design shared by every observation, in the same column order: the
# q-by-(S q) matrix [L_1 ... L_S], so that the sparse design holds
# W[(a - 1) n + i, index[i, (s, b)]] = L_s[a, b].
.gt_selected_local_design <- function(factors, q) {
  if (!is.list(factors) || !length(factors) ||
      !all(vapply(factors, function(L) is.matrix(L) && identical(dim(L), c(q, q)), logical(1))))
    .gt_d_stop("The local design needs one q-by-q factor per random source.")
  do.call(cbind, lapply(factors, function(L) {
    storage.mode(L) <- "double"
    unname(L)
  }))
}
