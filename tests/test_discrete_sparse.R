# Run from the project directory with Rscript tests/test_discrete_sparse.R.
#
# Sparse random-design construction must produce the same coordinate system as
# the dense implementation, in sparse storage, on the same fixtures the frozen
# fixed-parameter reference was built from. This checks the representation
# only: no Hessian, no factorization, no mode solve, no fitting.
#
# The fixtures are sourced rather than restated, so this cannot drift into
# testing a different problem than the one the reference froze.
source(file.path("validation-studies", "discrete-sparse-reference", "cases.R"))
source(file.path("R", "discrete_sparse.R"))

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
outcome <- function(expr) tryCatch({ force(expr); "accepted" }, error = conditionMessage)

# Rebuild one case's prepared inputs. Only the preparation is repeated here;
# the fixtures themselves come from the reference directory.
prepared <- function(case) {
  control <- .gt_d_control(case$control)
  prep <- .gt_d_prepare(case$data, case$outcomes, case$families)
  groups <- lapply(case$design$term_members, function(m) .gt_d_group(case$data, m))
  setup <- .gt_d_covariance_setup(groups, prep$q, case$covariance, control, prep$dimensions)
  parameters <- c(prep$start + case$offset, setup$start * case$scale)
  list(groups = groups, n = prep$n, q = prep$q,
       factors = .gt_d_covariance_factors(parameters[-seq_along(prep$start)], setup))
}

# --- Every reference fixture --------------------------------------------------
for (case in cases) {
  at <- prepared(case)
  dense <- .gt_d_dense_backend(at$groups, at$factors, at$n, at$q)
  sparse <- .gt_d_sparse_backend(at$groups, at$factors, at$n, at$q)
  label <- paste0("case ", case$key)

  expect(inherits(sparse$W, "sparseMatrix"), paste(label, "builds a sparse matrix"))
  expect(identical(dim(sparse$W), dim(dense$W)),
         paste0(label, ": dimensions match, sparse ", paste(dim(sparse$W), collapse = "x"),
                " against dense ", paste(dim(dense$W), collapse = "x")))
  # Exact, not within a tolerance: both write the same factor entry into the
  # same coordinate, so any difference at all is a construction defect rather
  # than arithmetic.
  difference <- max(abs(as.matrix(sparse$W) - dense$W))
  expect(identical(difference, 0), paste0(label, ": entries identical (max |difference| ",
                                          format(difference, digits = 3), ")"))
  expect(identical(sparse$stored_entries, as.integer(sum(dense$W != 0))),
         paste0(label, ": stored entries equal the dense nonzero count"))
  expect(identical(sparse$random_dimension, ncol(dense$W)),
         paste(label, "reports the dense random dimension"))
  # No structural zero is stored. A sparse object that stores explicit zeros
  # would agree numerically while giving up the only thing it is here for.
  expect(identical(as.integer(Matrix::nnzero(sparse$W, na.counted = TRUE)),
                   as.integer(sum(dense$W != 0))),
         paste(label, "stores no explicit zeros"))
  # The recorded layout must describe the coordinates actually used.
  layout <- sparse$layout
  expect(identical(sum(layout$columns), ncol(dense$W)), paste(label, "layout spans every column"))
  expect(identical(layout$first_column[[1L]], 1L), paste(label, "layout starts at the first column"))
  expect(identical(layout$last_column[[nrow(layout)]], ncol(dense$W)),
         paste(label, "layout ends at the last column"))
  covered <- unlist(lapply(seq_len(nrow(layout)), function(s)
    seq(layout$first_column[[s]], layout$last_column[[s]])))
  expect(identical(sort(covered), seq_len(ncol(dense$W))),
         paste(label, "layout blocks tile every column exactly once"))
  # Each source's own columns must be the ones its factor writes into.
  for (s in seq_len(nrow(layout))) {
    single <- at$factors
    for (other in seq_along(single)) if (other != s) single[[other]][] <- 0
    only <- .gt_d_sparse_backend(at$groups, single, at$n, at$q)
    used <- which(Matrix::colSums(abs(only$W)) > 0)
    expect(!length(used) || (min(used) >= layout$first_column[[s]] &&
                             max(used) <= layout$last_column[[s]]),
           paste0(label, ": source ", layout$source[[s]], " writes only inside its own block"))
  }
}

# --- The zero-covariance fixture, stated explicitly ---------------------------
# The contract is a retained coordinate system, not retained storage: the
# columns must exist and hold nothing.
zero_case <- Filter(function(x) identical(x$key, "binary_logit_zero_source"), cases)[[1L]]
at <- prepared(zero_case)
zero_sparse <- .gt_d_sparse_backend(at$groups, at$factors, at$n, at$q)
expect(identical(ncol(zero_sparse$W), 13L),
       paste("a zero source keeps its columns; got", ncol(zero_sparse$W)))
expect(identical(zero_sparse$stored_entries, 30L),
       paste("a zero source stores nothing; got", zero_sparse$stored_entries, "entries"))
empty <- which(Matrix::colSums(abs(zero_sparse$W)) == 0)
expect(length(empty) > 0, "the zero source's columns are present and empty")

# --- Source order permutes coordinates without changing the predictor ---------
# Reordering sources must relabel coordinates, not alter what the design does.
two <- Filter(function(x) identical(x$key, "binary_probit_crossed"), cases)[[1L]]
at <- prepared(two)
forward <- .gt_d_sparse_backend(at$groups, at$factors, at$n, at$q)
reversed <- .gt_d_sparse_backend(rev(at$groups), rev(at$factors), at$n, at$q)
expect(identical(dim(forward$W), dim(reversed$W)), "reordering sources preserves the shape")
sizes <- vapply(at$groups, function(g) g$nlevels * at$q, integer(1))
# Forward column j of the first source lives at reversed column sB + j, and the
# second source's columns move to the front.
permutation <- c(sizes[[2L]] + seq_len(sizes[[1L]]), seq_len(sizes[[2L]]))
expect(identical(max(abs(as.matrix(reversed$W)[, permutation] - as.matrix(forward$W))), 0),
       "reversing source order permutes coordinate blocks and nothing else")
set.seed(31)
u <- rnorm(ncol(forward$W))
expect(max(abs(as.numeric(forward$W %*% u) -
               as.numeric(reversed$W %*% u[order(permutation)]))) < 1e-12,
       "the modeled predictor is unchanged by source order")

# --- Non-diagonal factors and off-diagonal curvature --------------------------
joint <- list(item = list(index = rep(seq_len(6), each = 3L), nlevels = 6L),
              rater = list(index = rep(seq_len(3), times = 6L), nlevels = 3L))
oblique <- list(item = matrix(c(0.9, 0.4, 0, 0.7), 2, 2), rater = matrix(c(0.5, -0.2, 0, 0.3), 2, 2))
d_joint <- .gt_d_dense_backend(joint, oblique, 18L, 2L)
s_joint <- .gt_d_sparse_backend(joint, oblique, 18L, 2L)
expect(identical(max(abs(as.matrix(s_joint$W) - d_joint$W)), 0),
       "an off-diagonal covariance factor maps to the same coordinates")
expect(identical(s_joint$stored_entries, as.integer(sum(d_joint$W != 0))),
       "an off-diagonal factor stores exactly the dense nonzeros")

# --- Group level ordering ------------------------------------------------------
shuffled <- joint
shuffled$item$index <- rev(joint$item$index)
d_shuffled <- .gt_d_dense_backend(shuffled, oblique, 18L, 2L)
s_shuffled <- .gt_d_sparse_backend(shuffled, oblique, 18L, 2L)
expect(identical(max(abs(as.matrix(s_shuffled$W) - d_shuffled$W)), 0),
       "group level order is followed, not assumed")
expect(!identical(max(abs(as.matrix(s_shuffled$W) - as.matrix(s_joint$W))), 0),
       "a different grouping really does produce a different design")

# --- Malformed input is refused exactly as the dense backend refuses it -------
malformed <- list(
  bad_n = function(f) f(joint, oblique, 0L, 2L),
  bad_q = function(f) f(joint, oblique, 18L, 0L),
  factor_count = function(f) f(joint, oblique[1L], 18L, 2L),
  factor_shape = function(f) f(joint, list(item = matrix(1, 1, 1), rater = oblique$rater), 18L, 2L),
  factor_nonfinite = function(f) f(joint, list(item = matrix(c(1, 0, 0, NA), 2, 2),
                                               rater = oblique$rater), 18L, 2L),
  index_range = function(f) f(list(item = list(index = rep(99L, 18L), nlevels = 6L),
                                   rater = joint$rater), oblique, 18L, 2L),
  index_length = function(f) f(list(item = list(index = 1L, nlevels = 6L), rater = joint$rater),
                               oblique, 18L, 2L),
  no_sources = function(f) f(list(), list(), 18L, 2L))
for (name in names(malformed)) {
  dense_said <- outcome(malformed[[name]](.gt_d_dense_backend))
  sparse_said <- outcome(malformed[[name]](.gt_d_sparse_backend))
  expect(!identical(dense_said, "accepted"), paste("dense refuses", name))
  expect(!identical(sparse_said, "accepted"),
         paste0("sparse refuses ", name, "; it said: ", sparse_said))
}

# --- No dense intermediate ----------------------------------------------------
# Building the dense matrix and converting it returns a sparse object while
# keeping the allocation this work exists to remove, so the absence of that
# shortcut is checked rather than trusted to review.
builder <- readLines(file.path("R", "discrete_sparse.R"))
start <- grep("^\\.gt_d_sparse_W <- function", builder)
body <- builder[start:(start + which(builder[start:length(builder)] == "}")[1] - 1)]
code <- body[!grepl("^\\s*#", body)]
# Matrix::Matrix() is the dense-coercion constructor; sparseMatrix() is the
# triplet one and is what should be here, so match the former exactly rather
# than by a substring both of them share.
for (forbidden in c("matrix(", "as.matrix", "Matrix::Matrix(", "array(", "diag("))
  expect(!any(grepl(forbidden, code, fixed = TRUE)),
         paste0("the sparse builder never calls ", forbidden, " on its way to a sparse matrix"))
expect(any(grepl("sparseMatrix", code, fixed = TRUE)),
       "the sparse builder assembles from triplets")

# --- Measured storage, reported rather than claimed ---------------------------
# nnz alone is not evidence that the problem scales; factor fill and measured
# memory are separate questions for later steps. This records what is actually
# stored today.
cat("\nStored entries against dense cells:\n")
for (case in cases) {
  at <- prepared(case)
  sparse <- .gt_d_sparse_backend(at$groups, at$factors, at$n, at$q)
  cells <- prod(dim(sparse$W))
  cat(sprintf("  %-34s %6d of %8d cells (%.2f%%)\n", case$key,
              sparse$stored_entries, cells, 100 * sparse$stored_entries / cells))
  expect(sparse$stored_entries <= cells, paste(case$key, "stores no more than the dense cell count"))
}

cat("PASS: sparse design construction reproduces the dense coordinate system on ",
    length(cases), " reference fixtures, storing ", "no explicit zeros.\n", sep = "")
