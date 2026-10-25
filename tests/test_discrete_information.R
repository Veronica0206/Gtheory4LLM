source("load_functions.R")

# A full nuisance/covariance quadratic exposes both a missing cross derivative
# and the erroneous factor of two from a -2 log likelihood convention.
H <- matrix(c(5, 1, 0.4, 1, 4, 0.7, 0.4, 0.7, 3), 3, 3)
at <- c(intercept = 0.2, item = 0.8, rater = 0.6)
objective <- function(x) drop(crossprod(x - at, H %*% (x - at))) / 2
stopifnot(max(abs(.gt_d_information_hessian(at, objective, 1e-3,
  rep(-Inf, 3), rep(Inf, 3)) - H)) < 1e-8)
prep <- list(q = 1L, dimensions = "y", start = c(intercept = 0))
groups <- list(item = list(), rater = list())
setup <- list(fixed = NULL, parameterization = "variance", sources = names(groups),
              q = 1L, per = 1L, positions = matrix(c(1L, 1L), 1), diagpos = TRUE)
control <- .gt_d_control(list(check_hessian = TRUE))
oracle <- function(parameters, prep, groups, setup, control, details)
  list(valid = TRUE, inner_converged = TRUE, nll = objective(parameters))
info <- .gt_d_information(at, prep, groups, setup, control, oracle,
  c(-15, 0, 0), rep(15, 3), TRUE)
stopifnot(info$available, max(abs(info$parameter_covariance - solve(H))) < 1e-7,
  max(abs(info$entry_covariance - solve(H)[2:3, 2:3])) < 1e-7,
  max(abs(info$entry_covariance - solve(H[2:3, 2:3]))) > 1e-3)
stopifnot(!.gt_d_information(at, prep, groups, setup, control, oracle,
  c(-15, 0, 0), rep(15, 3), FALSE)$available)

# A boundary source is held fixed and the rest of the information inverted:
# its coordinate and entries get no sampling covariance and no standard error.
held <- .gt_d_information(at, prep, groups, setup, control, oracle,
  c(-15, 0, 0), rep(15, 3), TRUE, "item")
block <- solve(H[c(1, 3), c(1, 3)])
stopifnot(held$available, held$restricted_to_interior, identical(held$fixed_components, "item"),
  identical(held$fixed_component_kinds, c(item = "singular_nonzero")),
  identical(held$information_coordinates, c("intercept", "rater")),
  max(abs(held$parameter_covariance[c(1, 3), c(1, 3)] - block)) < 1e-7,
  all(held$parameter_covariance[2, ] == 0), all(held$parameter_covariance[, 2] == 0),
  is.na(held$parameter_standard_errors[["item"]]), all(held$entry_covariance[1, ] == 0),
  abs(held$entry_covariance[2, 2] - block[2, 2]) < 1e-7, grepl("item held fixed", held$interpretation, fixed = TRUE))
at_zero <- replace(at, "item", 0)
held_zero <- .gt_d_information(at_zero, prep, groups, setup, control, oracle,
  c(-15, 0, 0), rep(15, 3), TRUE, "item")
stopifnot(held_zero$available, identical(held_zero$fixed_component_kinds, c(item = "zero")),
  grepl("item held at zero", held_zero$interpretation, fixed = TRUE))
# Zero means negligible on the latent scale, at most 1e-8, not exactly zero.
kind_at <- function(variance) .gt_d_information(replace(at, "item", variance), prep, groups, setup, control,
  oracle, c(-15, 0, 0), rep(15, 3), TRUE, "item")$fixed_component_kinds[["item"]]
stopifnot(identical(kind_at(1e-9), "zero"), identical(kind_at(1e-7), "singular_nonzero"))
# With every source on its boundary nothing remains to condition on.
every <- .gt_d_information(at, prep, groups, setup, control, oracle,
  c(-15, 0, 0), rep(15, 3), TRUE, c("item", "rater"))
stopifnot(!every$available, grepl("no interior block remains", every$reason, fixed = TRUE))

# A native inverse returning without error is not evidence it solves H X=I.
# Inject a positive definite but wrong inverse; no uncertainty may escape.
chol2inv <- function(x, ...) 1.01 * base::chol2inv(x, ...)
invalid <- .gt_d_information(at, prep, groups, setup, control, oracle,
  c(-15, 0, 0), rep(15, 3), TRUE)
rm(chol2inv)
stopifnot(!invalid$available, grepl("solve-validity", invalid$reason, fixed = TRUE),
  info$inverse_backward_error <= info$inverse_validity_bound)

# Natural covariance derivatives in an unstructured two-outcome model.
prep2 <- list(q = 2L, dimensions = c("a", "b"), start = c(nuisance = 0))
setup2 <- .gt_d_covariance_setup(groups, 2L, "unstructured",
  .gt_d_control(list(covariance_parameterization = "log_cholesky")), prep2$dimensions)
theta <- c(nuisance = 0.1, setup2$start)
theta[c(3, 6)] <- c(0.12, -0.17)
mapping <- .gt_d_information_mapping(theta, prep2, groups, setup2)
natural <- function(x) unlist(lapply(.gt_d_covariance_factors(x[-1], setup2), function(L) {
  S <- tcrossprod(L)
  S[lower.tri(S, diag = TRUE)]
}), use.names = FALSE)
for (i in seq_along(theta)) {
  plus <- minus <- theta
  plus[[i]] <- plus[[i]] + 1e-6
  minus[[i]] <- minus[[i]] - 1e-6
  stopifnot(max(abs((natural(plus) - natural(minus)) / 2e-6 - mapping$jacobian[, i])) < 1e-7)
}

# A real zero-random-variance binary model reduces to an intercept-only GLM.
data <- expand.grid(item = seq_len(12), rater = seq_len(4))
data$y <- rep(c(1, 0, 1, 0, 1, 1, 0, 1), 6)
fixed <- list(item = matrix(0, 1, 1), rater = matrix(0, 1, 1))
fit <- gt_fit(y ~ item + rater, data, measured = "item",
  family = gt_family("binary", link = "logit"),
  control = gt_control(discrete = list(fixed_covariance = fixed,
    optimizer = "nlminb", check_hessian = TRUE)))
reference <- stats::glm(y ~ 1, data = data, family = stats::binomial())
stopifnot(fit$numerically_accepted, fit$uncertainty$available,
  abs(fit$uncertainty$parameter_covariance[1, 1] - stats::vcov(reference)[1, 1]) < 1e-5,
  all(fit$uncertainty$entry_covariance == 0),
  all(fit$uncertainty$fixed_components %in% names(fixed)))
cat("Full-information nuisance, scaling, mapping, boundary and independent GLM checks passed.\n")
