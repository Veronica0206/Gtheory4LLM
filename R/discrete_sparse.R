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

# Sparse conditional Hessian assembly.
#
# The same I + W' C W the dense implementation assembles, in sparse storage,
# at a fixed parameter vector. No factorization, no mode solve, no fitting.
#
# Binary and ordinal blocks supply per-observation diagonal curvature and are
# what this assembles. Categorical blocks carry full multinomial curvature
# including off-diagonal terms, and are refused here rather than approximated
# or quietly handled: the supported sparse envelope for 0.2 is binary and
# ordinal, and an explicit refusal is the only way that stays true as this
# file grows. The loop structure generalizes, so adding categorical later is a
# change to this function rather than a change to its callers.
.gt_d_sparse_hessian <- function(curvature, W, n) {
  if (!is.list(curvature) || !length(curvature))
    .gt_d_stop("Sparse Hessian assembly needs at least one response curvature block.")
  if (!methods::is(W, "sparseMatrix"))
    .gt_d_stop("Sparse Hessian assembly needs a sparse random design.")
  if (!is.numeric(n) || length(n) != 1L || !is.finite(n) || n < 1 || n != floor(n))
    .gt_d_stop("Sparse Hessian assembly needs a positive observation count.")
  n <- as.integer(n)
  H <- Matrix::Diagonal(ncol(W))
  for (curv in curvature) {
    if (is.null(curv$diagonal))
      .gt_d_stop("The sparse backend supports binary and ordinal curvature only; ",
                 "categorical blocks carry off-diagonal multinomial curvature and remain ",
                 "on the dense backend until they are separately qualified.")
    # Checked before as.integer() rather than after. A fractional dimension
    # would be truncated to a neighbouring one, and a negative dimension builds
    # negative row indices, which R reads as exclusion: the assembly then
    # succeeds against a different part of the design and returns a plausible
    # wrong answer rather than failing.
    if (!is.numeric(curv$dims) || length(curv$dims) != 1L || !is.finite(curv$dims) ||
        curv$dims < 1 || curv$dims != floor(curv$dims))
      .gt_d_stop("A diagonal curvature block must name one latent dimension.")
    if (!is.numeric(curv$diagonal) || length(curv$diagonal) != n ||
        any(!is.finite(curv$diagonal)))
      .gt_d_stop("A diagonal curvature block must give one finite value per observation.")
    dimension <- as.integer(curv$dims)
    row <- (dimension - 1L) * n + seq_len(n)
    if (max(row) > nrow(W))
      .gt_d_stop("A curvature block names a latent dimension outside the random design.")
    A <- W[row, , drop = FALSE]
    # pmax(0, .) matches the dense clamp. Negative curvature would make the
    # conditional problem non-convex, and the dense implementation already
    # refuses to propagate it; the sparse path must not differ on that.
    H <- H + Matrix::crossprod(A, A * pmax(0, curv$diagonal))
  }
  # Symmetrized the same way rather than assumed symmetric: the accumulation is
  # symmetric in exact arithmetic and only nearly so in floating point, and the
  # frozen reference records the symmetrized matrix.
  (H + Matrix::t(H)) / 2
}

# Sparse factorization, solves, and log determinant.
#
# Fixed parameters only: this factorizes a conditional Hessian that was already
# assembled, solves against it, and reports its log determinant. No mode solve,
# no optimizer, no fitting.
#
# Two properties matter more than the arithmetic. A fill-reducing permutation
# reorders the factor, so every solve must go through the factor object, which
# applies and undoes that permutation itself; a solve written against the raw
# factor would return a plausible vector in the wrong order. And the log
# determinant must come from the factor, never from densifying it, because
# densifying restores exactly the allocation the sparse path exists to avoid.
.gt_d_sparse_factor <- function(H, permute = TRUE) {
  if (!methods::is(H, "sparseMatrix"))
    .gt_d_stop("Sparse factorization needs a sparse conditional Hessian.")
  if (nrow(H) != ncol(H)) .gt_d_stop("A conditional Hessian must be square.")
  if (!is.logical(permute) || length(permute) != 1L || is.na(permute))
    .gt_d_stop("The permutation choice must be TRUE or FALSE.")
  symmetric <- Matrix::forceSymmetric(H)
  factor <- tryCatch(Matrix::Cholesky(symmetric, perm = permute, LDL = FALSE, super = FALSE),
                     error = function(e) NULL)
  if (is.null(factor))
    .gt_d_stop("The conditional Hessian is not positive definite; it has no Cholesky factor.")
  structure(list(factor = factor, dimension = as.integer(nrow(H)), permuted = permute,
                 # Fill is counted on the sparse factor, not a dense copy of it,
                 # and against the triangle it corresponds to. Comparing a
                 # triangular factor with a symmetric matrix stored in both
                 # triangles reports a reduction where there is fill.
                 factor_entries = as.integer(Matrix::nnzero(methods::as(factor, "CsparseMatrix"))),
                 hessian_entries = as.integer(Matrix::nnzero(H)),
                 hessian_triangle_entries =
                   as.integer(Matrix::nnzero(Matrix::tril(Matrix::forceSymmetric(H))))),
            class = "gt_discrete_sparse_factor")
}

.gt_d_sparse_logdet <- function(factorization) {
  if (!inherits(factorization, "gt_discrete_sparse_factor"))
    .gt_d_stop("A sparse log determinant needs a factorization from .gt_d_sparse_factor().")
  # sqrt = FALSE is passed explicitly and must stay explicit. The default
  # returns the log determinant of the factor rather than of the matrix, which
  # is half the value wanted, and Matrix warns that this default may change.
  # Relying on it would put a silent factor of two into the Laplace correction,
  # in one direction now and the other after an upgrade.
  as.numeric(Matrix::determinant(factorization$factor, logarithm = TRUE, sqrt = FALSE)$modulus)
}

.gt_d_sparse_solve <- function(factorization, b) {
  if (!inherits(factorization, "gt_discrete_sparse_factor"))
    .gt_d_stop("A sparse solve needs a factorization from .gt_d_sparse_factor().")
  if (!is.numeric(b) || !length(b) || any(!is.finite(b)))
    .gt_d_stop("A sparse solve needs a finite numeric right-hand side.")
  if (length(b) != factorization$dimension)
    .gt_d_stop("The right-hand side does not match the factorized dimension.")
  # system = "A" solves against the original matrix, so the factor object
  # applies its own permutation and undoes it. Solving against the raw factor
  # would return a correctly sized vector in the wrong order.
  as.numeric(Matrix::solve(factorization$factor, b, system = "A"))
}

# Retained sparse structure for repeated fitted evaluation.
#
# An outer optimizer evaluates the marginal objective many times at different
# covariance parameters. The coordinate geometry does not change between those
# calls: which observation belongs to which group level, where each source's
# columns begin, and how many columns exist in total are all fixed by the
# design. Only the covariance factors change.
#
# What is deliberately NOT retained is the sparsity pattern. A block is stored
# only where its factor entry is nonzero, so the pattern depends on the
# parameters: a source whose factor decodes to exactly zero keeps its columns
# and contributes no stored entries. That behaviour is the established
# representation contract and the frozen reference records the stored-entry
# counts it produces, so the pattern is recomputed from the factors on every
# call. Precomputing it once would give a source at the zero boundary stored
# entries it should not have.
.gt_d_sparse_context <- function(groups, n, q) {
  checked <- .gt_d_sparse_validate(groups, factors_for_validation(groups, q), n, q)
  n <- checked$n
  q <- checked$q
  offsets <- integer(length(groups))
  offset <- 0L
  for (s in seq_along(groups)) {
    offsets[[s]] <- offset
    offset <- offset + q * groups[[s]]$nlevels
  }
  structure(list(groups = groups, n = n, q = q, offsets = offsets,
                 observation = seq_len(n), layout = .gt_d_sparse_layout(groups, q),
                 random_dimension = sum(vapply(groups, `[[`, integer(1), "nlevels")) * q),
            class = "gt_discrete_sparse_context")
}

# Validation needs factors of the right shape; the context is built before any
# parameters exist, so it checks the geometry against placeholders and the
# real factors are validated on every build below.
factors_for_validation <- function(groups, q)
  rep(list(matrix(0, q, q)), length(groups))

.gt_d_sparse_build <- function(context, factors) {
  if (!inherits(context, "gt_discrete_sparse_context"))
    .gt_d_stop("A sparse build needs a context from .gt_d_sparse_context().")
  .gt_d_sparse_validate(context$groups, factors, context$n, context$q)
  n <- context$n
  q <- context$q
  rows <- vector("list", length(context$groups) * q * q)
  columns <- vector("list", length(rows))
  values <- vector("list", length(rows))
  slot <- 0L
  for (s in seq_along(context$groups)) {
    group <- context$groups[[s]]
    L <- factors[[s]]
    offset <- context$offsets[[s]]
    for (a in seq_len(q)) for (b in seq_len(q)) if (L[a, b] != 0) {
      slot <- slot + 1L
      rows[[slot]] <- (a - 1L) * n + context$observation
      columns[[slot]] <- offset + (b - 1L) * group$nlevels + group$index
      values[[slot]] <- rep.int(L[a, b], n)
    }
  }
  if (!slot)
    return(Matrix::sparseMatrix(i = integer(0), j = integer(0), x = numeric(0),
                                dims = c(n * q, context$random_dimension)))
  Matrix::sparseMatrix(i = unlist(rows[seq_len(slot)]), j = unlist(columns[seq_len(slot)]),
                       x = unlist(values[seq_len(slot)]),
                       dims = c(n * q, context$random_dimension))
}

.gt_d_sparse_backend_from <- function(context, factors) {
  W <- .gt_d_sparse_build(context, factors)
  structure(list(W = W, n = context$n, q = context$q, layout = context$layout,
                 stored_entries = as.integer(Matrix::nnzero(W)),
                 random_dimension = ncol(W)),
            class = "gt_discrete_sparse_backend")
}
