# Run from the project directory with Rscript tests/test_discrete_sparse_hessian.R.
#
# Sparse assembly of the conditional Hessian at fixed parameters. This checks
# assembly only: the mode is taken from the dense solver and used as an input,
# because what is under test is I + W' C W, not how the mode was found. No
# factorization, no sparse mode solve, no fitting.
#
# The frozen reference is the oracle. Agreeing with the dense implementation
# and agreeing with the committed targets are different claims, so both are
# checked.
source(file.path("validation-studies", "discrete-sparse-reference", "cases.R"))
source(file.path("R", "discrete_sparse.R"))

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
outcome <- function(expr) tryCatch({ force(expr); "accepted" }, error = conditionMessage)
DIRECTORY <- file.path("validation-studies", "discrete-sparse-reference")
frozen <- read.csv(file.path(DIRECTORY, "reference.csv"), stringsAsFactors = FALSE)
# The tolerance the reference declared for curvature, restated here so that
# loosening it is an edit rather than an argument.
CURVATURE_TOLERANCE <- c(relative = 1e-6, absolute = 1e-6)

at_frozen_point <- function(case) {
  control <- .gt_d_control(case$control)
  prep <- .gt_d_prepare(case$data, case$outcomes, case$families)
  groups <- lapply(case$design$term_members, function(m) .gt_d_group(case$data, m))
  setup <- .gt_d_covariance_setup(groups, prep$q, case$covariance, control, prep$dimensions)
  parameters <- c(prep$start + case$offset, setup$start * case$scale)
  factors <- .gt_d_covariance_factors(parameters[-seq_along(prep$start)], setup)
  answer <- .gt_d_laplace(parameters, prep, groups, setup, control, details = TRUE)
  stopifnot(isTRUE(answer$valid))
  kernel <- .gt_d_response_kernel(answer$eta, parameters, prep)
  stopifnot(isTRUE(kernel$valid))
  list(groups = groups, factors = factors, n = prep$n, q = prep$q,
       curvature = kernel$curvature)
}

for (case in cases) {
  at <- at_frozen_point(case)
  dense_W <- .gt_d_dense_backend(at$groups, at$factors, at$n, at$q)$W
  sparse_W <- .gt_d_sparse_backend(at$groups, at$factors, at$n, at$q)$W
  dense_H <- .gt_d_dense_hessian(at$curvature, dense_W, at$n)
  sparse_H <- .gt_d_sparse_hessian(at$curvature, sparse_W, at$n)
  label <- paste0("case ", case$key)

  expect(methods::is(sparse_H, "sparseMatrix"), paste(label, "assembles a sparse Hessian"))
  expect(identical(dim(sparse_H), dim(dense_H)), paste(label, "Hessian dimensions match"))

  # Against the dense implementation, elementwise. Both evaluate the same
  # algebra at the same fixed parameters, so this is held far tighter than the
  # reference tolerance: a real difference here is an assembly defect rather
  # than arithmetic. It is not held at zero, because dense BLAS and sparse
  # kernels may accumulate in different orders.
  gap <- max(abs(as.matrix(sparse_H) - dense_H))
  expect(gap <= 1e-12, paste0(label, ": sparse and dense Hessians agree elementwise (max |difference| ",
                              format(gap, digits = 3), ")"))

  # Against the committed oracle, at the tolerance that reference declared.
  rows <- frozen[frozen$case == case$key &
                   grepl("^hessian_[0-9]+_[0-9]+$", frozen$quantity), ]
  expect(nrow(rows) > 0, paste(label, "has frozen Hessian entries to check"))
  worst <- 0
  for (k in seq_len(nrow(rows))) {
    index <- as.integer(strsplit(sub("^hessian_", "", rows$quantity[[k]]), "_")[[1L]])
    got <- sparse_H[index[[1L]], index[[2L]]]
    want <- rows$value[[k]]
    difference <- abs(got - want)
    ok <- difference <= CURVATURE_TOLERANCE[["absolute"]] ||
      (want != 0 && difference / abs(want) <= CURVATURE_TOLERANCE[["relative"]])
    expect(ok, paste0(label, " ", rows$quantity[[k]], ": frozen ", format(want, digits = 17),
                      ", sparse ", format(got, digits = 17)))
    worst <- max(worst, difference)
  }
  cat(sprintf("  %-34s %4d frozen entries, worst |difference| %.3e, %d stored\n",
              case$key, nrow(rows), worst, as.integer(Matrix::nnzero(sparse_H))))

  # Symmetry is a property of the result, not of how it was stored.
  expect(max(abs(as.matrix(sparse_H) - t(as.matrix(sparse_H)))) == 0,
         paste(label, "Hessian is exactly symmetric"))
  # The identity is present: an all-zero curvature would still leave I.
  zeroed <- lapply(at$curvature, function(c) { c$diagonal <- rep(0, at$n); c })
  identity_only <- .gt_d_sparse_hessian(zeroed, sparse_W, at$n)
  expect(max(abs(as.matrix(identity_only) - diag(ncol(sparse_W)))) == 0,
         paste(label, "zero curvature leaves exactly the identity"))
}

# --- Negative curvature is clamped the same way -------------------------------
# The dense implementation applies pmax(0, .). A sparse path that propagated
# negative curvature would build a different, non-convex problem.
case <- cases[[1L]]
at <- at_frozen_point(case)
sparse_W <- .gt_d_sparse_backend(at$groups, at$factors, at$n, at$q)$W
dense_W <- .gt_d_dense_backend(at$groups, at$factors, at$n, at$q)$W
negative <- lapply(at$curvature, function(c) { c$diagonal <- -abs(c$diagonal); c })
expect(max(abs(as.matrix(.gt_d_sparse_hessian(negative, sparse_W, at$n)) -
                .gt_d_dense_hessian(negative, dense_W, at$n))) == 0,
       "negative curvature is clamped exactly as the dense implementation clamps it")
expect(max(abs(as.matrix(.gt_d_sparse_hessian(negative, sparse_W, at$n)) -
                diag(ncol(sparse_W)))) == 0,
       "fully negative curvature contributes nothing beyond the identity")

# --- Categorical curvature is refused, not approximated -----------------------
# Off-diagonal multinomial curvature is outside the supported sparse envelope
# for 0.2. Refusing it explicitly is what keeps that envelope from widening by
# accident as this file grows.
categorical <- list(list(dims = c(1L, 2L), probability = matrix(0.3, at$n, 2L)))
refusal <- outcome(.gt_d_sparse_hessian(categorical, sparse_W, at$n))
expect(grepl("categorical", refusal), paste("categorical curvature is refused; it said:", refusal))
expect(grepl("dense", refusal), "the refusal says where such a model is still handled")

# --- Malformed input ----------------------------------------------------------
malformed <- list(
  no_blocks = function() .gt_d_sparse_hessian(list(), sparse_W, at$n),
  dense_design = function() .gt_d_sparse_hessian(at$curvature, dense_W, at$n),
  bad_n = function() .gt_d_sparse_hessian(at$curvature, sparse_W, 0L),
  wrong_length = function() .gt_d_sparse_hessian(
    list(list(dims = 1L, diagonal = rep(1, at$n + 1L))), sparse_W, at$n),
  dimension_outside = function() .gt_d_sparse_hessian(
    list(list(dims = 99L, diagonal = rep(1, at$n))), sparse_W, at$n),
  # Below the first dimension rather than above the last. A negative index
  # builds negative rows, which R reads as exclusion, so the assembly would
  # succeed against a different part of the design and return a plausible
  # wrong answer instead of failing.
  dimension_zero = function() .gt_d_sparse_hessian(
    list(list(dims = 0, diagonal = rep(1, at$n))), sparse_W, at$n),
  dimension_negative = function() .gt_d_sparse_hessian(
    list(list(dims = -1, diagonal = rep(1, at$n))), sparse_W, at$n),
  # Truncation would quietly select a neighbouring dimension.
  dimension_fractional = function() .gt_d_sparse_hessian(
    list(list(dims = 1.5, diagonal = rep(1, at$n))), sparse_W, at$n),
  dimension_nonfinite = function() .gt_d_sparse_hessian(
    list(list(dims = NA_real_, diagonal = rep(1, at$n))), sparse_W, at$n),
  dimension_infinite = function() .gt_d_sparse_hessian(
    list(list(dims = Inf, diagonal = rep(1, at$n))), sparse_W, at$n),
  # Accepted curvature that is not finite produces a Hessian that is not
  # finite, which every later step would inherit.
  diagonal_missing = function() .gt_d_sparse_hessian(
    list(list(dims = 1L, diagonal = replace(rep(1, at$n), 1L, NA_real_))), sparse_W, at$n),
  diagonal_infinite = function() .gt_d_sparse_hessian(
    list(list(dims = 1L, diagonal = replace(rep(1, at$n), 1L, Inf))), sparse_W, at$n))
for (name in names(malformed)) {
  said <- outcome(malformed[[name]]())
  expect(!identical(said, "accepted"), paste("sparse Hessian assembly refuses", name))
  # An explicit refusal, not an incidental indexing error from somewhere below.
  expect(grepl("curvature|sparse|observation", said),
         paste0("the refusal of ", name, " is the backend's own; it said: ", said))
}
# A fractional dimension must not be treated as the dimension it truncates to.
expect(!identical(outcome(.gt_d_sparse_hessian(
         list(list(dims = 1.5, diagonal = rep(1, at$n))), sparse_W, at$n)),
       outcome(.gt_d_sparse_hessian(
         list(list(dims = 1L, diagonal = rep(1, at$n))), sparse_W, at$n))),
       "a fractional dimension is refused rather than silently truncated")

cat("PASS: sparse Hessian assembly reproduces the dense matrix and the frozen targets.\n")
