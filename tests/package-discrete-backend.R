# Independent matrix and conditional-objective checks for the private backend.
library(Gtheory4LLM)
internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
prepare <- internal(".gt_d_prepare")
make_backend <- internal(".gt_d_dense_backend")
kernel <- internal(".gt_d_response_kernel")
evaluate <- internal(".gt_d_dense_evaluate")
mode <- internal(".gt_d_dense_mode")
control <- internal(".gt_d_control")
near <- function(a, b, tolerance = 1e-8)
  stopifnot(max(abs(a - b)) < tolerance)
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
}

# The same observation can contain Bernoulli, ordered and nominal responses.
# Non-diagonal factors and repeated groups expose column-ordering mistakes.
panel <- data.frame(binary = c(0, 1, 1, 0),
  ordinal = ordered(c("low", "mid", "high", "low"), levels = c("low", "mid", "high")),
  category = factor(c("a", "b", "c", "b"), levels = c("a", "b", "c")))
families <- list(list(family = "binary", link = "logit"),
  list(family = "ordinal", link = "probit"), list(family = "categorical", link = "softmax"))
prep <- prepare(panel, names(panel), families)
groups <- list(item = list(index = c(1L, 1L, 2L, 2L), nlevels = 2L),
               rater = list(index = c(1L, 2L, 1L, 2L), nlevels = 2L))
factors <- list(item = matrix(c(.4, .1, -.1, .2, 0, .3, .1, 0,
                                0, 0, .5, .2, 0, 0, 0, .6), 4L),
                rater = diag(c(.2, .3, .1, 0)))
backend <- make_backend(groups, factors, prep$n, prep$q)
# Independent Kronecker-product construction; the implementation fills entries.
reference_W <- do.call(cbind, lapply(seq_along(groups), function(j) {
  incidence <- outer(groups[[j]]$index, seq_len(groups[[j]]$nlevels), `==`) * 1
  kronecker(factors[[j]], incidence)
}))
near(backend$W, reference_W, 1e-14)
stopifnot(ncol(backend$W) == 16L) # Zero columns are retained, never dropped.

u <- seq(-.3, .4, length.out = ncol(backend$W))
baseline <- internal(".gt_d_baseline")(prep$start, prep)
eta <- baseline + matrix(reference_W %*% u, prep$n, prep$q)
response <- kernel(eta, prep$start, prep)
assembled <- evaluate(eta, prep$start, prep, backend)
stopifnot(response$valid, assembled$valid, is.null(response$H),
          identical(response, assembled[names(response)]))
# Differentiate the scalar conditional objective in random-effect coordinates.
# This catches missing prior curvature and off-diagonal multinomial terms.
objective <- function(at) {
  e <- baseline + matrix(reference_W %*% at, prep$n, prep$q)
  kernel(e, prep$start, prep)$nll + sum(at^2) / 2
}
epsilon <- 2e-4
gradient <- numeric(length(u))
H <- matrix(0, length(u), length(u))
for (a in seq_along(u)) {
  da <- numeric(length(u)); da[a] <- epsilon
  gradient[a] <- (objective(u + da) - objective(u - da)) / (2 * epsilon)
  for (b in seq_along(u)) {
    db <- numeric(length(u)); db[b] <- epsilon
    H[a, b] <- (objective(u + da + db) - objective(u + da - db) -
                 objective(u - da + db) + objective(u - da - db)) / (4 * epsilon^2)
  }
}
near(as.vector(crossprod(reference_W, response$gradient)) + u, gradient, 1e-7)
near(assembled$H, H, 2e-7)

# The backend carries design matrices only; solves restart from zero and cannot
# consume a hidden previous mode. Unrelated evaluations cannot change a solve.
ctl <- control(list())
first <- mode(prep$start, prep, backend, ctl, details = TRUE)
invisible(mode(prep$start + .1, prep, backend, ctl, details = TRUE))
second <- mode(prep$start, prep, backend, ctl, details = TRUE)
stopifnot(first$valid, identical(first, second),
          identical(names(backend), c("W", "n", "q")))
# Return conventions stay scalar for optimization and structured for diagnosis.
near(mode(prep$start, prep, backend, ctl), first$nll, 1e-14)
truncated <- mode(prep$start, prep, backend,
                  control(list(inner_maxit = 1L, inner_tol = 1e-12)), details = TRUE)
stopifnot(!truncated$valid, !truncated$inner_converged)
stopifnot(mode(prep$start, prep, backend,
  control(list(inner_maxit = 1L, inner_tol = 1e-12))) == 1e100)

bad_groups <- groups; bad_groups$item$nlevels <- 2
expect_error(make_backend(bad_groups, factors, prep$n, prep$q), "group indices")
bad_groups <- groups; bad_groups$item$index[1] <- 3L
expect_error(make_backend(bad_groups, factors, prep$n, prep$q), "group indices")
expect_error(make_backend(groups, factors[-1], prep$n, prep$q), "source factors")
bad_factors <- factors; bad_factors$item <- matrix(1, 2L, 2L)
expect_error(make_backend(groups, bad_factors, prep$n, prep$q), "covariance factor")
bad_prep <- prep; bad_prep$n <- prep$n + 1L
expect_error(mode(prep$start, bad_prep, backend, ctl), "prepared response dimensions")
bad_backend <- backend; bad_backend$W <- backend$W[-1L, , drop = FALSE]
expect_error(mode(prep$start, prep, bad_backend, ctl), "Invalid matrix")
bad_control <- ctl; bad_control$inner_tol <- NA_real_
expect_error(mode(prep$start, prep, backend, bad_control), "parameters or controls")
cat("PASS: dense backend matrix ordering, joint curvature, deterministic modes and invalid inputs.\n")
