# Installed-package checks for Gaussian Wald standard errors, the delta-method
# mapping onto source covariance entries, and coefficient intervals. Every
# reference value below is computed independently of the engine that produced it.
library(Gtheory4LLM)
near <- function(a, b, tolerance = 1e-6, label = "comparison") {
  if (!isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)))
    stop(label, " failed: maximum absolute difference ", max(abs(a - b)))
}

set.seed(11)
items <- 24L
raters <- 6L
d <- expand.grid(rater = factor(seq_len(raters)), item = factor(seq_len(items)))
d$score <- 1.3 * rnorm(items)[d$item] + 0.4 * rnorm(raters)[d$rater] +
  rnorm(nrow(d), sd = 0.7)
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design)
stopifnot(fit$numerically_accepted, isTRUE(fit$uncertainty$available),
          !isTRUE(fit$uncertainty$restricted_to_interior))

# 1. The reconstructed parameter covariance matrix must reproduce OpenMx's own
# standard errors; the engine records that comparison itself.
stopifnot(is.finite(fit$uncertainty$openmx_standard_error_agreement),
          fit$uncertainty$openmx_standard_error_agreement < 1e-8)

# 2. For a crossed two-way random design with one observation per cell the
# classical mean-square variance formulas give the same standard errors.
squares <- anova(lm(score ~ item + rater, data = d))
mean_square_variance <- function(row) 2 * squares[row, "Mean Sq"]^2 / squares[row, "Df"]
expected <- c(
  item = sqrt((mean_square_variance("item") + mean_square_variance("Residuals")) / raters^2),
  rater = sqrt((mean_square_variance("rater") + mean_square_variance("Residuals")) / items^2),
  Residual = sqrt(mean_square_variance("Residuals")))
errors <- fit$component_standard_errors
stopifnot(identical(errors$component, c("item", "rater", "Residual")))
near(errors$std_error, expected[errors$component], 1e-4, "classical variance-component SE")
near(errors$variance, vapply(fit$covariance_components, function(x) x[1, 1], numeric(1)),
     1e-10, "reported variance")

# 3. The analytic entry Jacobian must match numerical differentiation of the
# covariance map, for a joint unstructured model where it is nontrivial.
set.seed(5)
joint <- expand.grid(rater = factor(seq_len(5)), item = factor(seq_len(20)))
latent <- matrix(rnorm(40), 20, 2) %*% chol(matrix(c(1.5, .5, .5, 1), 2))
joint$y1 <- latent[joint$item, 1] + rnorm(nrow(joint))
joint$y2 <- latent[joint$item, 2] + rnorm(nrow(joint))
joint_fit <- gt_fit(joint, c("y1", "y2"), design, covariance = "unstructured",
                    residual = "unstructured")
stopifnot(isTRUE(joint_fit$uncertainty$available),
          identical(unname(joint_fit$covariance_types),
                    rep("unstructured", 3L)))
mapping <- joint_fit$uncertainty
parameters <- colnames(mapping$jacobian)
at <- OpenMx::omxGetParameters(joint_fit$model)[parameters]
lower_index <- which(lower.tri(matrix(0, 2, 2), diag = TRUE), arr.ind = TRUE)
covariance_map <- function(values) {
  unlist(lapply(seq_along(joint_fit$covariance_types), function(j) {
    factor_matrix <- matrix(0, 2, 2)
    for (l in seq_len(nrow(lower_index)))
      factor_matrix[lower_index[l, 1L], lower_index[l, 2L]] <-
        values[[sprintf("G%02d_l%d", j, l)]]
    (factor_matrix %*% t(factor_matrix))[lower_index]
  }), use.names = FALSE)
}
numerical <- vapply(parameters, function(name) {
  step <- 1e-6
  up <- down <- at
  up[[name]] <- up[[name]] + step
  down[[name]] <- down[[name]] - step
  (covariance_map(up) - covariance_map(down)) / (2 * step)
}, numeric(nrow(mapping$entries)))
near(numerical, mapping$jacobian, 1e-6, "analytic entry Jacobian")
stopifnot(nrow(mapping$entry_covariance) == nrow(mapping$entries),
          max(abs(mapping$entry_covariance - t(mapping$entry_covariance))) < 1e-12)
# The variance table must line up component by component and trait by trait
# with the fitted matrices, not merely have the right number of rows.
joint_errors <- joint_fit$component_standard_errors
stopifnot(identical(joint_errors$component, rep(names(joint_fit$covariance_types), each = 2L)),
          identical(joint_errors$trait, rep(c("y1", "y2"), times = 3L)))
near(joint_errors$variance,
     unlist(lapply(joint_fit$covariance_components[names(joint_fit$covariance_types)], diag),
            use.names = FALSE), 1e-12, "joint variance ordering")
near(joint_errors$std_error,
     sqrt(diag(mapping$entry_covariance))[
       paste0(joint_errors$component, "[", joint_errors$trait, ",", joint_errors$trait, "]")],
     1e-12, "joint standard-error ordering")

# 4. The reported coefficient standard error must equal a delta-method value
# recomputed from the entry covariance matrix by an independent gradient.
coefficient_se <- function(fit, counts) {
  components <- fit$covariance_components
  universe <- components[[fit$design$object]][1, 1]
  error <- components$Residual[1, 1] / prod(counts)
  for (term in setdiff(fit$design$terms, fit$design$object)) {
    members <- fit$design$term_members[[term]]
    if (fit$design$object %in% members)
      error <- error + components[[term]][1, 1] /
        prod(counts[setdiff(members, fit$design$object)])
  }
  total <- universe + error
  record <- fit$uncertainty
  gradient <- numeric(nrow(record$entries))
  for (k in seq_len(nrow(record$entries))) {
    component <- record$entries$component[[k]]
    members <- if (component == "Residual") names(counts) else
      setdiff(fit$design$term_members[[component]], fit$design$object)
    weight <- if (component == fit$design$object) 0 else 1 / prod(counts[members])
    if (component != fit$design$object &&
        !fit$design$object %in% fit$design$term_members[[component]] &&
        component != "Residual") weight <- 0
    universe_part <- as.numeric(component == fit$design$object)
    gradient[[k]] <- (universe_part * error - universe * weight) / total^2
  }
  sqrt(drop(crossprod(gradient, record$entry_covariance %*% gradient)))
}
reliability <- gt_reliability(fit)
near(reliability$per_trait$Erho2_se, coefficient_se(fit, c(rater = raters)),
     1e-8, "independent delta-method G standard error")

# 5. Intervals stay inside the unit interval and bracket the point estimate.
with(reliability$per_trait, stopifnot(
  Erho2_lower > 0, Erho2_upper < 1, Erho2_lower < Erho2, Erho2 < Erho2_upper,
  Phi_lower < Phi, Phi < Phi_upper, Phi_se > 0))
study <- gt_dstudy(fit, data.frame(rater = c(1, 3, 6, 12)))
stopifnot(nrow(study$results) == 4L, all(is.finite(study$results$Erho2_se)),
          all(diff(study$results$Erho2) > 0),
          all(diff(study$results$Erho2_se) < 0),
          identical(rownames(study$results), as.character(seq_len(4))))

# 6. A wider level must produce a wider interval around the same estimate.
wide <- gt_reliability(fit, level = 0.99)
near(wide$per_trait$Erho2, reliability$per_trait$Erho2, 1e-12, "level-invariant estimate")
stopifnot(wide$per_trait$Erho2_lower < reliability$per_trait$Erho2_lower,
          wide$per_trait$Erho2_upper > reliability$per_trait$Erho2_upper)
for (bad in list(0, 1, -0.5, c(0.9, 0.95), NA_real_)) {
  error <- tryCatch(gt_reliability(fit, level = bad), error = identity)
  stopifnot(inherits(error, "error"), grepl("strictly between 0 and 1", conditionMessage(error)))
}

# 7. Disabling derivative diagnostics must remove the standard errors and say so.
plain <- gt_fit(d, "score", design,
                control = gt_control(gaussian = list(check_hessian = FALSE)))
stopifnot(!isTRUE(plain$uncertainty$available),
          grepl("check_hessian", plain$uncertainty$reason),
          all(is.na(gt_reliability(plain)$per_trait$Erho2_se)),
          all(is.na(gt_reliability(plain)$per_trait$Erho2_lower)))
report <- paste(capture.output(print(gt_reliability(plain))), collapse = "\n")
stopifnot(grepl("No intervals", report), !grepl("Erho2_se", report))

# 8. The discrete engine reports point estimates only, with an explicit reason.
binary <- expand.grid(occasion = factor(seq_len(8)), item = factor(seq_len(16)))
set.seed(3)
binary$y <- rbinom(nrow(binary), 1, plogis(rnorm(16)[binary$item]))
binary_fit <- gt_fit(binary, "y", gt_design("item", "occasion", full_cell = FALSE),
                     gt_family("binary", "logit"),
                     control = gt_control(discrete = list(maxit = 200L)))
stopifnot(binary_fit$numerically_accepted, !isTRUE(binary_fit$uncertainty$available),
          grepl("point estimates only", binary_fit$uncertainty$reason))
latent <- gt_reliability(binary_fit, scale = "latent")
stopifnot(is.na(latent$per_trait$Erho2_se), is.na(latent$per_trait$Erho2_lower),
          is.finite(latent$per_trait$Erho2))

# 9. A component pinned at zero makes the joint Hessian indefinite. Standard
# errors must then condition on that component rather than disappear.
flat <- expand.grid(rater = factor(seq_len(8)), item = factor(seq_len(30)))
set.seed(19)
flat$score <- 2 * rnorm(30)[flat$item] + rnorm(nrow(flat), sd = 0.5)
flat_design <- gt_design("item", "rater")
flat_fit <- gt_fit(flat, "score", flat_design)
zero <- names(which(vapply(flat_fit$covariance_components,
                           function(x) x[1, 1] <= 1e-10, logical(1))))
if (length(zero)) {
  stopifnot(isTRUE(flat_fit$uncertainty$available),
            isTRUE(flat_fit$uncertainty$restricted_to_interior),
            setequal(flat_fit$uncertainty$fixed_components, zero))
  held <- flat_fit$component_standard_errors
  stopifnot(all(is.na(held$std_error[held$component %in% zero])),
            all(is.finite(held$std_error[!held$component %in% zero])))
  note <- paste(capture.output(print(gt_reliability(flat_fit))), collapse = "\n")
  stopifnot(grepl("being held at zero", note))
  cat("PASS: interior-block standard errors with", length(zero),
      "zero-variance component(s) held fixed.\n")
} else {
  cat("NOTE: no zero-variance component arose; the interior-block branch was not exercised.\n")
}
cat("PASS: Gaussian Wald standard errors, entry Jacobian, delta-method coefficient intervals, and unavailability reporting.\n")
