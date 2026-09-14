# Run from the project directory with Rscript tests/test_discrete_sparse_factor.R.
#
# Sparse factorization, solves and log determinant at fixed parameters. The
# conditional Hessian is assembled by the already-qualified sparse path and
# taken as input; what is under test is the factor object, not how the Hessian
# was built and not how a mode would be found.
#
# Two properties are treated as first class rather than incidental. A
# fill-reducing permutation is where this step goes quietly wrong: a solve can
# return a correctly sized, plausible vector in the wrong order. And the log
# determinant must come from the factor rather than from a dense copy of it.
source(file.path("validation-studies", "discrete-sparse-reference", "cases.R"))
source(file.path("R", "discrete_sparse.R"))

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
outcome <- function(expr) tryCatch({ force(expr); "accepted" }, error = conditionMessage)
DIRECTORY <- file.path("validation-studies", "discrete-sparse-reference")
frozen <- read.csv(file.path(DIRECTORY, "reference.csv"), stringsAsFactors = FALSE)
# The tolerance the reference declared for objective quantities, restated so
# that loosening it is an edit rather than an argument.
OBJECTIVE_TOLERANCE <- c(relative = 1e-8, absolute = 1e-10)

hessian_at <- function(case) {
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
  W <- .gt_d_sparse_backend(groups, factors, prep$n, prep$q)$W
  .gt_d_sparse_hessian(kernel$curvature, W, prep$n)
}

set.seed(77)
for (case in cases) {
  H <- hessian_at(case)
  label <- paste0("case ", case$key)
  want <- frozen$value[frozen$case == case$key &
                         frozen$quantity == "hessian_log_determinant"]
  expect(length(want) == 1L, paste(label, "has a frozen log determinant"))

  permuted <- .gt_d_sparse_factor(H, permute = TRUE)
  natural <- .gt_d_sparse_factor(H, permute = FALSE)

  # --- Log determinant against the frozen target ------------------------------
  got <- .gt_d_sparse_logdet(permuted)
  difference <- abs(got - want)
  ok <- difference <= OBJECTIVE_TOLERANCE[["absolute"]] ||
    (want != 0 && difference / abs(want) <= OBJECTIVE_TOLERANCE[["relative"]])
  expect(ok, paste0(label, " log determinant: frozen ", format(want, digits = 17),
                    ", sparse factor ", format(got, digits = 17)))

  # The permutation must not change the value it is a permutation of.
  expect(abs(.gt_d_sparse_logdet(natural) - got) <= 1e-9,
         paste(label, "log determinant is invariant to the fill-reducing permutation"))

  # --- Solves -----------------------------------------------------------------
  # Round-trip against the matrix that was factorized, not against the factor:
  # a solve that ignored the permutation would satisfy neither.
  b <- rnorm(nrow(H))
  x <- .gt_d_sparse_solve(permuted, b)
  residual <- max(abs(as.numeric(H %*% x) - b))
  expect(residual <= 1e-8, paste0(label, " solve residual max|Hx - b| = ",
                                  format(residual, digits = 3)))
  # And the two permutations must agree on the answer, not merely each be
  # self-consistent.
  expect(max(abs(x - .gt_d_sparse_solve(natural, b))) <= 1e-8,
         paste(label, "the solution does not depend on the permutation chosen"))
  # Against an independent dense solve of the same system.
  expect(max(abs(x - solve(as.matrix(H), b))) <= 1e-8,
         paste(label, "the sparse solve agrees with an independent dense solve"))

  # Fill against the triangle the factor corresponds to, not against the
  # symmetric matrix stored in both triangles.
  expect(permuted$factor_entries >= permuted$hessian_triangle_entries -
           permuted$dimension,
         paste(label, "the factor is not smaller than the triangle it factorizes"))
  cat(sprintf("  %-34s logdet %12.8f  tril(H) %4d  factor %4d  fill %+.0f%%\n",
              case$key, got, permuted$hessian_triangle_entries, permuted$factor_entries,
              100 * (permuted$factor_entries / permuted$hessian_triangle_entries - 1)))
}

# --- The sqrt default is pinned, not inherited --------------------------------
# Matrix::determinant() on a factor defaults to returning the determinant of
# the factor rather than of the matrix, which is half the value wanted, and
# warns that the default may change. If it flips and this code relied on it,
# every log determinant would silently double. Check against an independent
# eigenvalue computation so that such a change fails here.
case <- cases[[2L]]
H <- hessian_at(case)
factorization <- .gt_d_sparse_factor(H)
independent <- sum(log(eigen(as.matrix(H), symmetric = TRUE, only.values = TRUE)$values))
expect(abs(.gt_d_sparse_logdet(factorization) - independent) <= 1e-8,
       paste0("the log determinant is of the Hessian, not of its factor: got ",
              format(.gt_d_sparse_logdet(factorization), digits = 12), ", independent ",
              format(independent, digits = 12)))
half <- as.numeric(Matrix::determinant(factorization$factor, logarithm = TRUE,
                                       sqrt = TRUE)$modulus)
expect(abs(half - independent / 2) <= 1e-8,
       "the factor's own determinant really is half, so the default would be wrong here")

# --- The factor is never densified --------------------------------------------
# Densifying restores the allocation this path exists to avoid, and would do so
# while still producing the right number.
source_lines <- readLines(file.path("R", "discrete_sparse.R"))
start <- grep("^\\.gt_d_sparse_logdet <- function", source_lines)
body <- source_lines[start:(start + which(source_lines[start:length(source_lines)] == "}")[1] - 1)]
code <- body[!grepl("^\\s*#", body)]
for (forbidden in c("as.matrix", "matrix(", "expand(", "diag("))
  expect(!any(grepl(forbidden, code, fixed = TRUE)),
         paste("the log determinant never reaches for", forbidden))
expect(any(grepl("determinant", code, fixed = TRUE)),
       "the log determinant comes from the factor object")

# --- A matrix with no Cholesky factor is refused ------------------------------
indefinite <- Matrix::forceSymmetric(Matrix::sparseMatrix(
  i = c(1, 2, 1), j = c(1, 2, 2), x = c(1, -4, 2), dims = c(2, 2)))
# CHOLMOD warns on its way to failing here, which is expected for a matrix
# deliberately chosen to have no factor; suppressing it keeps a successful run
# from printing something that reads like a defect.
expect(grepl("positive definite", suppressWarnings(outcome(.gt_d_sparse_factor(indefinite)))),
       "an indefinite Hessian is refused rather than factorized into nonsense")

# --- Malformed input ----------------------------------------------------------
good <- .gt_d_sparse_factor(hessian_at(cases[[1L]]))
malformed <- list(
  dense_hessian = function() .gt_d_sparse_factor(as.matrix(diag(3))),
  not_square = function() .gt_d_sparse_factor(Matrix::sparseMatrix(i = 1, j = 1, x = 1,
                                                                  dims = c(2, 3))),
  bad_permute = function() .gt_d_sparse_factor(hessian_at(cases[[1L]]), permute = NA),
  logdet_of_nothing = function() .gt_d_sparse_logdet(list()),
  solve_of_nothing = function() .gt_d_sparse_solve(list(), 1),
  solve_wrong_length = function() .gt_d_sparse_solve(good, c(1, 2)),
  solve_nonfinite = function() .gt_d_sparse_solve(good, rep(NA_real_, good$dimension)))
for (name in names(malformed)) {
  said <- outcome(malformed[[name]]())
  expect(!identical(said, "accepted"), paste("sparse factorization refuses", name))
  expect(grepl("sparse|square|permutation|factoriz|right-hand|definite", said),
         paste0("the refusal of ", name, " is the backend's own; it said: ", said))
}

cat("PASS: sparse factor solves and log determinants match the frozen targets, ",
    "independent of the permutation.\n", sep = "")
