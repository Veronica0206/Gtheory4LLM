# The compiled selected inverse of the sparse conditional Hessian's Cholesky
# factor, run from sources and from an installed archive. The oracle is the
# dense inverse of each small matrix: every selected entry, every query from
# either triangle, the trace against the matrix itself and against derivative
# matrices with structural-zero entries, and the local contractions for
# observations sharing one design must agree with it to roundoff, with and
# without a fill-reducing permutation and under a shuffled coordinate order.
# Absent structural support, malformed storage, invalid pivots and every
# declared cap must refuse by name. Nothing here fits a model.
if (identical(Sys.getenv("GT_SELECTED_INVERSE_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
selected <- internal(".gt_selected_inverse")
entries <- internal(".gt_selected_entries")
trace_of <- internal(".gt_selected_trace")
contract <- internal(".gt_selected_contractions")
platform <- internal(".gt_selected_platform")
caps <- internal(".gt_selected_caps")
local_index <- internal(".gt_selected_local_index")
local_design <- internal(".gt_selected_local_design")
sparse_factor <- internal(".gt_d_sparse_factor")
sparse_W <- internal(".gt_d_sparse_W")
sparse_hessian <- internal(".gt_d_sparse_hessian")
sparse_context <- internal(".gt_d_sparse_context")
group <- internal(".gt_d_group")
raw <- function(symbol, ...) .Call(internal(symbol), ...)

near <- function(a, b, tolerance = 1e-10) max(abs(as.numeric(a) - as.numeric(b))) <= tolerance
refused <- function(expr, pattern = NULL) {
  got <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(got, "error"))
  if (!is.null(pattern)) stopifnot(grepl(pattern, conditionMessage(got), fixed = TRUE))
  invisible(conditionMessage(got))
}
# A symmetric sparse matrix with a declared pattern: entries on the pattern
# are stored even when their value is exactly zero, as the fit's structural
# envelope stores them. Values and pattern are permuted together.
declared <- function(H, pattern, order) {
  H <- as.matrix(H)[order, order, drop = FALSE]
  pattern <- (as.matrix(pattern) | t(as.matrix(pattern)))[order, order, drop = FALSE]
  diag(pattern) <- TRUE
  ij <- which(pattern & lower.tri(pattern, diag = TRUE), arr.ind = TRUE)
  Matrix::sparseMatrix(i = ij[, 1L], j = ij[, 2L], x = H[ij], dims = dim(H), symmetric = TRUE)
}

info <- platform()
stopifnot(identical(names(info), c("double_bytes", "long_double_bytes", "double_mantissa", "long_double_mantissa")),
          info[["double_bytes"]] == 8L, info[["double_mantissa"]] == 53L,
          info[["long_double_bytes"]] >= 8L, info[["long_double_mantissa"]] >= 53L)
limits <- caps()
stopifnot(identical(names(limits), c("dimension", "fill", "recurrence_products", "queries", "observations",
                                     "local_width", "latent", "contraction_work")),
          all(is.finite(limits)), all(limits > 0), limits[["dimension"]] == 60000, limits[["latent"]] == 8)

# The reference matrices: a diagonal, a chain, a random sparse Gram matrix, a
# disconnected block matrix, a declared pattern whose off-diagonal entry is
# zero, positive or negative, and a conditional Hessian from a rank-one item
# factor whose pattern is the all-ones structural envelope.
set.seed(271828)
chain <- function(n) Matrix::bandSparse(n, k = c(-1, 0, 1),
                                        diagonals = list(rep(-.4, n - 1), rep(3, n), rep(-.4, n - 1)))
A <- Matrix::rsparsematrix(20, 13, .18)
randomH <- Matrix::forceSymmetric(Matrix::crossprod(A) + Matrix::Diagonal(13))
plain <- list(diagonal = Matrix::forceSymmetric(Matrix::Diagonal(x = c(2, 3, 4, 5))),
              chain = Matrix::forceSymmetric(chain(11)), random = randomH,
              disconnected = Matrix::forceSymmetric(Matrix::bdiag(chain(5), randomH[1:7, 1:7],
                                                                  Matrix::Diagonal(x = c(2, 4)))))
transition_pattern <- diag(TRUE, 4)
transition_pattern[1, 2] <- transition_pattern[2, 1] <- TRUE
transition <- lapply(c(0, .2, -.2), function(t) {
  H <- diag(c(2, 3, 4, 5))
  H[1, 2] <- H[2, 1] <- t
  H
})
names(transition) <- paste0("transition_", c(0, .2, -.2))
d <- expand.grid(item = factor(1:4), prompt = factor(1:3))
groups <- list(item = group(d, "item"), prompt = group(d, "prompt"))
factors <- list(item = matrix(c(.7, .2, 0, 0), 2), prompt = matrix(c(.3, -.1, 0, .4), 2))
stopifnot(qr(factors$item)$rank == 1L)
W <- sparse_W(groups, factors, nrow(d), 2L)
curvature <- seq(.1, .6, length.out = nrow(W))
H_source <- Matrix::Diagonal(ncol(W)) + Matrix::crossprod(W, W * curvature)
stopifnot(min(eigen(as.matrix(H_source), symmetric = TRUE, only.values = TRUE)$values) > 0)
envelope_pattern <- as.matrix(Matrix::crossprod(sparse_W(groups, rep(list(matrix(1, 2, 2)), 2), nrow(d), 2L))) != 0
# A coordinate that is zero at the centre changes the Hessian's numeric pattern.
Wj <- sparse_W(groups, list(matrix(c(0, 0, 0, 1), 2), matrix(0, 2, 2)), nrow(d), 2L)
D_source <- as.matrix(Matrix::crossprod(Wj, W * curvature) + Matrix::crossprod(W, Wj * curvature))

build <- function(name, order) {
  if (name %in% names(plain)) {
    H <- plain[[name]]
    return(Matrix::forceSymmetric(methods::as(H, "generalMatrix")[order, order, drop = FALSE]))
  }
  if (name %in% names(transition)) return(declared(transition[[name]], transition_pattern, order))
  declared(H_source, envelope_pattern, order)
}
case_names <- c(names(plain), names(transition), "rank_deficient_source")
records <- list()
set.seed(20261024)
for (name in case_names) for (shuffle in c(FALSE, TRUE)) for (permute in c(FALSE, TRUE)) {
  n <- if (name %in% names(plain)) nrow(plain[[name]]) else if (name %in% names(transition)) 4L else ncol(W)
  order <- if (shuffle) sample.int(n) else seq_len(n)
  H <- build(name, order)
  factorization <- sparse_factor(H, permute = permute)
  S <- selected(factorization)
  dense <- solve(as.matrix(H))
  stopifnot(identical(S$dimension, n), identical(S$platform, info),
            identical(S$factor_entries, as.numeric(length(S$x))), S$inner_products >= 0)
  # Every selected value, at its original coordinates, against the dense inverse.
  cols <- rep(seq_len(n), diff(S$p))
  rows <- S$i + 1L
  orow <- S$permutation[rows]
  ocol <- S$permutation[cols]
  stopifnot(near(S$x, dense[cbind(orow, ocol)]),
            near(entries(S, orow, ocol), dense[cbind(orow, ocol)]),
            near(entries(S, ocol, orow), dense[cbind(orow, ocol)]))
  # trace(H^{-1} H) is the dimension.
  stopifnot(near(trace_of(S, H), n))
  # Finite derivative values whose products with the inverse overflow give a
  # named refusal, not a nonfinite trace.
  huge <- methods::as(methods::as(H, "generalMatrix"), "CsparseMatrix")
  stored <- Matrix::summary(huge)
  huge <- Matrix::sparseMatrix(i = stored$i, j = stored$j, dims = dim(H),
    x = .Machine$double.xmax * ifelse(dense[cbind(stored$i, stored$j)] < 0, -1, 1))
  refused(trace_of(S, huge), "trace is not finite")
  # Row contractions over the largest clique against the dense block.
  largest <- which.max(diff(S$p))
  slots <- seq.int(S$p[largest] + 1L, S$p[largest + 1L])
  clique <- S$permutation[S$i[slots] + 1L]
  k <- length(clique)
  rows_A <- rbind(seq_len(k) / k, (-1)^seq_len(k) / k)
  pairs <- expand.grid(a = clique, b = clique)
  S_clique <- matrix(entries(S, pairs$a, pairs$b), k)
  stopifnot(near(rows_A %*% S_clique %*% t(rows_A), rows_A %*% dense[clique, clique] %*% t(rows_A)))
  # The compiled contractions for four observations whose coordinates are the
  # clique's members in shuffled orders, with a local design that has a zero.
  kk <- min(k, 8L)
  members <- clique[seq_len(kk)]
  index <- matrix(0L, 4L, kk)
  for (i in 1:4) index[i, ] <- members[sample.int(kk)]
  design <- matrix(rnorm(2L * kk), 2L, kk)
  design[1L, 1L] <- 0
  C <- array(0, c(4L, 2L, 2L))
  for (i in 1:4) {
    z <- matrix(rnorm(4), 2)
    C[i, , ] <- crossprod(z) + diag(.1, 2)
  }
  got <- contract(S, index, design, C)
  expected_Q <- array(0, c(4L, 2L, 2L))
  expected_trace <- matrix(0, 2L, kk)
  for (i in 1:4) {
    S_i <- dense[index[i, ], index[i, ], drop = FALSE]
    expected_Q[i, , ] <- design %*% S_i %*% t(design)
    expected_trace <- expected_trace + C[i, , ] %*% design %*% S_i
  }
  stopifnot(identical(dim(got$Q), c(4L, 2L, 2L)), near(got$Q, expected_Q),
            identical(dim(got$factor_trace), c(2L, kk)), near(got$factor_trace, expected_trace),
            got$local_queries_upper_bound == 4 * kk * kk)
  extra <- 0
  if (name %in% names(transition)) {
    # The declared (1, 2) entry is covered even when its value is exactly zero.
    D <- matrix(0, 4, 4)
    D[1, 2] <- D[2, 1] <- 1
    D <- D[order, order]
    stopifnot(is.finite(entries(S, which(order == 1L), which(order == 2L))))
    extra <- abs(trace_of(S, Matrix::Matrix(D, sparse = TRUE)) - sum(dense * D))
  }
  if (name == "rank_deficient_source") {
    D <- D_source[order, order]
    extra <- abs(trace_of(S, Matrix::Matrix(D, sparse = TRUE)) - sum(dense * D))
    for (i in seq_len(nrow(W))) {
      a <- as.matrix(W[i, , drop = FALSE])[, order, drop = FALSE]
      support <- which(a != 0)
      if (!length(support)) next
      pairs <- expand.grid(a = support, b = support)
      extra <- max(extra, abs(sum(a[pairs$a] * entries(S, pairs$a, pairs$b) * a[pairs$b]) - a %*% dense %*% t(a)))
    }
  }
  if (extra > 1e-10)
    stop(sprintf("case %s, shuffle %s, permute %s: derivative contraction error %.3g", name, shuffle, permute, extra))
  records[[length(records) + 1L]] <- data.frame(case = name, shuffle = shuffle, permute = permute, dimension = n,
    nonidentity_permutation = !identical(S$permutation, seq_len(n)), factor_entries = length(S$x))
}
records <- do.call(rbind, records)
stopifnot(nrow(records) == 32L, any(records$nonidentity_permutation), all(records$factor_entries >= records$dimension))

# The engine's own objects: a crossed design with an interaction source, two
# latent dimensions, diagonal curvature blocks, the sparse Hessian the mode
# solver would build. The local index and design must reproduce the sparse
# design row by row. The contractions need every pair of an observation's
# coordinates, and with diagonal factors and diagonal curvature the numeric
# Hessian does not couple them all, so its factor is refused; the factor of
# the same values overlaid on the structural envelope, the pattern every
# factor entry and every latent dimension could reach, covers them, and the
# compiled contractions must then equal the dense W_i H^{-1} W_i' and the
# sum of C_i W_i S_i for every observation.
d2 <- expand.grid(item = factor(1:6), rater = factor(1:3), prompt = factor(1:2))
n2 <- nrow(d2)
q <- 2L
groups2 <- list(item = group(d2, "item"), rater = group(d2, "rater"), prompt = group(d2, "prompt"),
                "item:rater" = group(d2, c("item", "rater")))
factors2 <- list(item = matrix(c(.8, .3, 0, .5), 2), rater = matrix(c(.4, 0, 0, .6), 2),
                 prompt = matrix(c(.5, -.2, 0, .3), 2), "item:rater" = matrix(c(.3, .1, 0, .2), 2))
context <- sparse_context(groups2, n2, q)
W2 <- sparse_W(groups2, factors2, n2, q)
diagonal_curvature <- list(runif(n2, .2, .9), runif(n2, .1, .7))
H2 <- sparse_hessian(list(list(dims = 1L, diagonal = diagonal_curvature[[1L]]),
                          list(dims = 2L, diagonal = diagonal_curvature[[2L]])), W2, n2)
refused(contract(selected(sparse_factor(H2)), local_index(context), local_design(factors2, q),
                 array(c(diagonal_curvature[[1L]], rep(0, 2 * n2), diagonal_curvature[[2L]]), c(n2, q, q))),
        "structural pattern")
envelope2 <- as.matrix(Matrix::crossprod(sparse_W(groups2, rep(list(matrix(1, q, q)), length(groups2)), n2, q))) != 0
H2_envelope <- declared(H2, envelope2, seq_len(ncol(W2)))
numeric_pattern <- as.matrix(H2) != 0
stopifnot(near(as.matrix(H2_envelope), as.matrix(H2)), all(!numeric_pattern | envelope2),
          sum(envelope2) > sum(numeric_pattern))
S2 <- selected(sparse_factor(H2_envelope))
dense2 <- solve(as.matrix(H2))
index2 <- local_index(context)
design2 <- local_design(factors2, q)
k2 <- length(groups2) * q
stopifnot(identical(dim(index2), c(n2, k2)), is.integer(index2), identical(dim(design2), c(q, k2)),
          all(index2 >= 1L & index2 <= ncol(W2)))
for (a in seq_len(q)) {
  W_a <- as.matrix(W2[(a - 1L) * n2 + seq_len(n2), , drop = FALSE])
  stopifnot(near(W_a[cbind(rep(seq_len(n2), k2), as.vector(index2))], rep(design2[a, ], each = n2)),
            sum(W_a != 0) == n2 * sum(design2[a, ] != 0))
}
C2 <- array(0, c(n2, q, q))
C2[, 1L, 1L] <- diagonal_curvature[[1L]]
C2[, 2L, 2L] <- diagonal_curvature[[2L]]
got2 <- contract(S2, index2, design2, C2)
expected_trace2 <- matrix(0, q, k2)
for (i in seq_len(n2)) {
  W_i <- as.matrix(W2[(seq_len(q) - 1L) * n2 + i, , drop = FALSE])
  S_i <- dense2[index2[i, ], index2[i, ], drop = FALSE]
  stopifnot(near(got2$Q[i, , ], W_i %*% dense2 %*% t(W_i)), near(got2$Q[i, , ], design2 %*% S_i %*% t(design2)))
  expected_trace2 <- expected_trace2 + diag(c(C2[i, 1L, 1L], C2[i, 2L, 2L])) %*% design2 %*% S_i
}
stopifnot(near(got2$factor_trace, expected_trace2), near(trace_of(S2, H2), ncol(W2)))

# Refusals, by name: types, lengths checked in a wide type before narrowing,
# pointers, the diagonal, finiteness, absent structural support in queries and
# in the recurrence, and every contraction input.
p <- c(0L, 1L, 2L)
i <- 0:1
x <- c(1, 1)
refusals <- c(
  pointer_type = refused(raw("gt_selected_inverse", as.double(p), i, x), "must be integer"),
  values_type = refused(raw("gt_selected_inverse", p, i, 1:2), "factor values double"),
  wide_length_before_cast = refused(raw("gt_selected_inverse", integer(60002L), integer(), double()), "dimension cap"),
  one_column_needed = refused(raw("gt_selected_inverse", 0L, integer(), double()), "at least one column"),
  lengths_differ = refused(raw("gt_selected_inverse", p, i, 1), "differ in length"),
  pointer_na = refused(raw("gt_selected_inverse", c(0L, NA_integer_, 2L), i, x), "column pointers"),
  pointer_negative = refused(raw("gt_selected_inverse", c(0L, -1L, 2L), i, x), "column pointers"),
  pointer_past_end = refused(raw("gt_selected_inverse", c(0L, 3L, 2L), i, x), "column pointers"),
  missing_diagonal = refused(raw("gt_selected_inverse", p, c(1L, 1L), x), "diagonal"),
  nonfinite = refused(raw("gt_selected_inverse", p, i, c(1, Inf)), "diagonal"),
  nonpositive = refused(raw("gt_selected_inverse", p, i, c(1, 0)), "diagonal"),
  unsorted = refused(raw("gt_selected_inverse", c(0L, 3L, 4L, 5L), c(0L, 2L, 1L, 1L, 2L), rep(1, 5)), "strictly increasing"),
  query_type = refused(raw("gt_selected_queries", p, i, x, 1, 1L), "integer vectors"),
  query_na = refused(raw("gt_selected_queries", p, i, x, NA_integer_, 1L), "outside the matrix"),
  query_missing_entry = refused(raw("gt_selected_queries", p, i, x, 1L, 2L), "structural pattern"),
  recurrence_missing_entry = refused(raw("gt_selected_inverse", c(0L, 3L, 4L, 5L), c(0L, 1L, 2L, 1L, 2L),
                                         c(1, .2, .3, 1, 1)), "structural pattern"),
  permutation = refused(raw("gt_selected_contractions", p, i, x, c(1L, 1L), matrix(1L, 1, 1), matrix(1, 1, 1), 1),
                        "permutation"),
  contraction_type = refused(raw("gt_selected_contractions", p, i, x, 1:2, matrix(1, 1, 1), matrix(1, 1, 1), 1),
                             "contraction inputs"),
  contraction_work = refused(raw("gt_selected_contractions", p, i, x, 1:2, matrix(1L, 7000, 128), matrix(1, 1, 128),
                                 rep(1, 7000)), "contraction work cap"),
  contraction_missing_edge = refused(raw("gt_selected_contractions", p, i, x, 1:2, matrix(1:2, 1, 2), matrix(1, 1, 2), 1),
                                     "structural pattern"),
  index_na = refused(raw("gt_selected_contractions", p, i, x, 1:2, matrix(NA_integer_, 1, 1), matrix(1, 1, 1), 1),
                     "outside the matrix"),
  design_nonfinite = refused(raw("gt_selected_contractions", p, i, x, 1:2, matrix(1L, 1, 1), matrix(Inf, 1, 1), 1),
                             "local design"),
  curvature_nonfinite = refused(raw("gt_selected_contractions", p, i, x, 1:2, matrix(1L, 1, 1), matrix(1, 1, 1), NaN),
                                "curvature"),
  dynamic_symbol = refused(.Call("gt_selected_inverse", p, i, x, PACKAGE = "Gtheory4LLM")),
  wrapper_input = refused(selected(list()), "sparse Cholesky factorization"),
  wrapper_query = refused(entries(S2, 0, 1), "between 1 and the dimension"),
  wrapper_trace = refused(trace_of(S2, matrix(1, 2, 2)), "factor's dimension"),
  wrapper_index = refused(contract(S2, index2 * 0L, design2, C2), "original random coordinates"),
  wrapper_design = refused(contract(S2, index2, design2[, -1L, drop = FALSE], C2), "local design"),
  wrapper_curvature = refused(contract(S2, index2, design2, C2[, , 1L]), "curvature array"))
stopifnot(length(refusals) == 30L)

# Declared caps at their boundaries: the identity at the dimension cap is its
# own selected inverse; one more column is refused; the recurrence work cap is
# accepted at exactly its value and refused one product set beyond it; the
# contraction work cap likewise. Validation runs before any recurrence.
n <- 60000L
identity <- raw("gt_selected_inverse", 0:n, 0:(n - 1L), rep(1, n))
stopifnot(identical(identity$x, rep(1, n)), identity$dimension == n, identity$inner_products == 0)
rm(identity)
counts <- rep(1L, n)
counts[1:6] <- 50001L
at_limit <- list(p = as.integer(c(0, cumsum(counts))), i = as.integer(sequence(counts) - 1L + rep.int(0:(n - 1L), counts)))
stopifnot(sum((as.double(counts) - 1)^2) == limits[["recurrence_products"]],
          length(raw("gt_selected_queries", at_limit$p, at_limit$i, rep(1, length(at_limit$i)), integer(), integer())) == 0L)
counts[1L] <- 50002L
over <- list(p = as.integer(c(0, cumsum(counts))), i = as.integer(sequence(counts) - 1L + rep.int(0:(n - 1L), counts)))
refused(raw("gt_selected_queries", over$p, over$i, rep(1, length(over$i)), integer(), integer()), "recurrence work cap")
rm(counts, at_limit, over)
refused(raw("gt_selected_contractions", p, i, x, c(1L, 1L), matrix(1L, 10000L, 100L), matrix(1, 1L, 100L), rep(1, 10000L)),
        "permutation")
refused(raw("gt_selected_contractions", p, i, x, c(1L, 1L), matrix(1L, 10001L, 100L), matrix(1, 1L, 100L), rep(1, 10001L)),
        "contraction work cap")

# The routines keep their results rooted while the collector runs.
gctorture(TRUE)
gc_inverse <- raw("gt_selected_inverse", p, i, x)
gc_contraction <- raw("gt_selected_contractions", p, i, x, 1:2, matrix(1L, 1, 1), matrix(1, 1, 1), 1)
gctorture(FALSE)
stopifnot(identical(gc_inverse$x, x), identical(gc_contraction$Q, 1))

cat("PASS: 32 selected-inverse cases against dense inverses, the engine's Hessian geometry on its envelope,",
    length(refusals), "refusals, cap boundaries and collector safety.\n")
