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
# A variance resting on the boundary reports NA whether or not the joint Hessian
# stayed invertible: no symmetric interval follows from curvature there. Every
# other row must equal the entry covariance matrix's own diagonal.
interior_rows <- !joint_errors$at_boundary
stopifnot(any(interior_rows), all(is.na(joint_errors$std_error[!interior_rows])))
near(joint_errors$std_error[interior_rows],
     sqrt(diag(mapping$entry_covariance))[
       paste0(joint_errors$component, "[", joint_errors$trait, ",", joint_errors$trait, "]")][interior_rows],
     1e-12, "joint standard-error ordering")
# The raw curvature is still retained for anyone who wants it, and coefficient
# intervals still use it because the joint Hessian was invertible here.
stopifnot(!isTRUE(joint_fit$uncertainty$restricted_to_interior),
          all(is.finite(diag(mapping$entry_covariance))),
          all(is.finite(unlist(gt_reliability(joint_fit)$per_trait[c("Erho2_se", "Phi_se")]))))

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
  stopifnot(grepl("held at zero", note), grepl(zero[[1L]], note, fixed = TRUE))
  cat("PASS: interior-block standard errors with", length(zero),
      "zero-variance component(s) held fixed.\n")
} else {
  cat("NOTE: no zero-variance component arose; the interior-block branch was not exercised.\n")
}
# 10. The caveat names a few sources inline and switches to a count and a
# pointer past that. On the bundled panels 13 sources rest on the boundary, and
# a caveat nobody finishes reading is not a caveat.
name_sources <- get(".gt_name_sources", envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
stopifnot(identical(name_sources(c("a", "b"), "boundary_components"), "a, b"),
          identical(name_sources(c("a", "b", "c"), "boundary_components"), "a, b, c"),
          identical(name_sources(letters[1:13], "fixed_components"),
                    "13 sources (see $uncertainty$fixed_components)"))
cat("PASS: Gaussian Wald standard errors, entry Jacobian, delta-method coefficient intervals, and unavailability reporting.\n")

# 11. Issue #36. A flagged source is either entirely zero or singular while
# carrying positive variance, and the interior-block branch must say which it
# conditions on. The branch is reached deliberately, through a controlled
# Hessian that is indefinite on one source and positive definite elsewhere, so
# this fails if the branch is not taken rather than passing vacuously.
classify <- get(".gt_gaussian_boundary_kinds", envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
uncertainty_record <- get(".gt_gaussian_uncertainty", envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
observed <- joint_fit$prepared$observed_variances
scale <- sqrt(outer(observed, observed))
kinds <- classify(list(zero = matrix(0, 2, 2), rank_one = matrix(c(1, 2, 2, 4), 2, 2) * scale,
                       one_zero = diag(c(1.5, 0)) * scale,
                       healthy = matrix(c(1, .3, .3, 1), 2, 2) * scale), observed)
stopifnot(identical(unname(kinds$boundary), c(TRUE, TRUE, TRUE, FALSE)),
          identical(unname(kinds$kind), c("zero", "singular_nonzero", "singular_nonzero", NA_character_)))
algebra <- setNames(sprintf("G%02d", seq_along(joint_fit$covariance_types)),
                    names(joint_fit$covariance_types))
hessian <- joint_fit$diagnostics$hessian
rater_parameters <- startsWith(rownames(hessian), paste0(algebra[["rater"]], "_"))
stopifnot(sum(rater_parameters) == 3L)
controlled <- hessian
controlled[rater_parameters, ] <- 0
controlled[, rater_parameters] <- 0
diag(controlled)[rater_parameters] <- -1
stopifnot(min(eigen(controlled, symmetric = TRUE, only.values = TRUE)$values) < 0)
nonzero_wording <- "held fixed at its fitted singular but nonzero covariance"
cases <- list(
  zero = list(rater = matrix(0, 2, 2), kind = "zero", wording = "held at zero"),
  one_zero = list(rater = diag(c(1.5, 0)) * scale, kind = "singular_nonzero", wording = nonzero_wording),
  rank_one = list(rater = matrix(c(1, 2, 2, 4), 2, 2) * scale, kind = "singular_nonzero",
                  wording = nonzero_wording))
for (name in names(cases)) {
  case <- cases[[name]]
  components <- joint_fit$covariance_components
  components$rater <- case$rater
  flags <- classify(components, observed)
  stopifnot(identical(names(which(flags$boundary)), "rater"),
            identical(unname(flags$kind[["rater"]]), case$kind))
  record <- uncertainty_record(joint_fit$model, algebra, joint_fit$covariance_types,
                               joint_fit$outcomes, components, controlled, NULL,
                               boundary = flags$boundary, boundary_kind = flags$kind,
                               estimator_label = "REML restricted likelihood", check_hessian = TRUE)
  stopifnot(isTRUE(record$available), isTRUE(record$restricted_to_interior),
            identical(record$fixed_components, "rater"),
            identical(unname(record$fixed_component_kinds), case$kind))
  # The interior block is inverted on its own; the fixed source carries no
  # curvature-based uncertainty, in the parameter and the entry covariance alike.
  interior <- !rater_parameters
  near(record$parameter_covariance[interior, interior],
       2 * solve(controlled[interior, interior]), 1e-8, paste(name, "interior parameter covariance"))
  stopifnot(all(record$parameter_covariance[rater_parameters, ] == 0),
            all(record$parameter_covariance[, rater_parameters] == 0))
  rater_entries <- record$entries$component == "rater"
  stopifnot(all(record$entry_covariance[rater_entries, ] == 0),
            all(diag(record$entry_covariance)[!rater_entries] > 0))
  errors <- record$variances
  stopifnot(all(is.na(errors$std_error[errors$component == "rater"])),
            all(is.finite(errors$std_error[errors$component != "rater"])))
  # Every extractor must carry the same reading, and a positive fitted
  # covariance is never called zero anywhere a user can read it.
  spliced <- joint_fit
  spliced$covariance_components <- components
  spliced$uncertainty <- record
  spliced$component_standard_errors <- record$variances
  spliced$diagnostics$boundary_components <- flags$boundary
  reliability_report <- paste(capture.output(print(gt_reliability(spliced))), collapse = "\n")
  for (text in c(record$interpretation, reliability_report)) {
    stopifnot(grepl(case$wording, text, fixed = TRUE), grepl("rater", text, fixed = TRUE))
    if (case$kind != "zero")
      stopifnot(!grepl("held at zero", text, fixed = TRUE), !grepl("zero-variance", text, fixed = TRUE))
  }
  entry_vcov <- gt_component_vcov(spliced)
  stopifnot(identical(attr(entry_vcov, "conditional_on_fixed"), "rater"),
            identical(attr(entry_vcov, "conditional_on_zero"),
                      if (case$kind == "zero") "rater" else character(0)))
  intervals <- gt_reliability(spliced)$per_trait
  stopifnot(all(is.finite(intervals$Erho2_se)), all(is.finite(intervals$Erho2_lower)),
            all(is.finite(intervals$Erho2_upper)))
}
cat("PASS: interior-block conditioning names zero and singular-but-nonzero sources correctly.\n")
