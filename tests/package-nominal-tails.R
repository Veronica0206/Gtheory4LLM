# High-precision references run from sources and installed archives.
if (identical(Sys.getenv("GT_NOMINAL_TAIL_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
# Independent 100-digit references: logit, loss, selected score, other score,
# and entries H11,H12,H22 of I+W'C W for W=1e8 I.
reference <- rbind(
  c(35, 1.2610233520293971e-15, -1.2610233520293963e-15, 6.3051167601469813e-16, 13.610233520293948, -6.3051167601469738, 7.3051167601469773),
  c(40, 8.4967085105831777e-18, -8.4967085105831777e-18, 4.2483542552915889e-18, 1.0849670851058317, -0.042483542552915886, 1.042483542552916),
  c(100, 7.4401519520416722e-44, -7.4401519520416722e-44, 3.7200759760208361e-44, 1, -3.720075976020836e-28, 1),
  c(700, 1.9719353087519542e-304, -1.9719353087519542e-304, 9.8596765437597708e-305, 1, -9.8596765437597713e-289, 1))

kernel <- internal(".gt_d_response_kernel")
dense <- internal(".gt_d_dense_hessian")
sparse <- internal(".gt_d_sparse_hessian")
compare <- function(actual, expected, tolerance = 2e-13) {
  stopifnot(all(is.finite(actual)),
    all(abs(actual - expected) <= tolerance * pmax(abs(expected), 1e-300)))
}
W <- diag(1e8, 2)
for (i in seq_len(nrow(reference))) {
  ref <- reference[i, ]
  for (observed in 1:3) {
    prep <- list(n = 1L, q = 2L, blocks = list(list(family = "categorical", dims = 1:2, y = observed)))
    response <- kernel(matrix(c(ref[1], 0), 1), numeric(), prep)
    stopifnot(response$valid)
    expected_loss <- if (observed == 2L) ref[2] else ref[1] + ref[2]
    expected_gradient <- c(if (observed == 2L) ref[3] else 1 + ref[3],
                           if (observed == 3L) ref[4] - 1 else ref[4])
    compare(response$nll, expected_loss)
    compare(response$gradient, expected_gradient)
    expected_hessian <- matrix(c(ref[5], ref[6], ref[6], ref[7]), 2)
    compare(dense(response$curvature, W, 1L), expected_hessian)
    compare(as.matrix(sparse(response$curvature, Matrix::Matrix(W, sparse = TRUE), 1L)), expected_hessian)
  }
  # Make the almost-certain category the reference category instead.
  prep$blocks[[1]]$y <- 1L
  response <- kernel(matrix(rep(-ref[1], 2), 1), numeric(), prep)
  compare(response$nll, ref[2])
  compare(response$gradient, rep(ref[4], 2))
}
prep$blocks[[1]]$y <- 2L
response <- kernel(matrix(c(40, 0), 1), numeric(), prep)
bad <- response$curvature
bad[[1]]$maximum_complement <- -1
for (assembler in list(function(x) dense(x, W, 1L),
                       function(x) sparse(x, Matrix::Matrix(W, sparse = TRUE), 1L))) {
  error <- tryCatch({ assembler(bad); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl("complement", conditionMessage(error), fixed = TRUE))
}
eta <- matrix(c(-2, .4, 1.2, -.3, .1, -1.7), ncol = 2)
prep <- list(n = 3L, q = 2L, blocks = list(list(family = "categorical", dims = 1:2, y = 1:3)))
response <- kernel(eta, numeric(), prep)
prob <- cbind(1, exp(eta)); prob <- prob / rowSums(prob)
compare(response$nll, -sum(log(prob[cbind(1:3, 1:3)])))
for (i in 1:3) {
  block <- list(dims = 1:2, probability = prob[i, -1, drop = FALSE])
  expected <- diag(2) + diag(as.vector(block$probability)) - tcrossprod(as.vector(block$probability))
  compare(dense(list(block), diag(2), 1L), expected)
}
cat("PASS: nominal tail loss, scores and dense/sparse curvature match independent high-precision references.\n")
