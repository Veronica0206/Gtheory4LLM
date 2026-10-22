# Run from the project directory with Rscript tests/test_nominal_reliability.R.
#
# Latent reliability for nominal outcomes and the category-exchangeable
# covariance. A nominal outcome with K categories has K - 1 contrast
# dimensions; its coefficients are the generalized eigenvalues of the universe
# covariance relative to universe plus error on those dimensions, reported as
# their mean with the smallest and largest. Checks:
#
#   * the arithmetic: invariance of generalized eigenvalues under a change of
#     reference category, where a trace ratio is not invariant; the K = 2 case
#     is the binary logit ratio; the delta-method error matches a finite
#     difference;
#   * the exchangeable structure: parameters, factors, refusals, preflight and
#     the information map;
#   * fitted models: the same coefficients under different reference
#     categories, for both the exchangeable and the unstructured covariance;
#     the exchangeable closed form; refusal of diagonal fits and of composites;
#     a D study; and a joint nominal-and-binary exchangeable fit whose binary
#     outcome reproduces a separate binary fit, because the joint likelihood
#     factorizes when outcomes are independent within each source.
source("load_functions.R")
suppressMessages(library(Matrix))
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
refuses <- function(expr, pattern) {
  message <- tryCatch({ force(expr); "" }, error = conditionMessage)
  grepl(pattern, message)
}

# --- arithmetic ------------------------------------------------------------------
set.seed(31L)
random_spd <- function(m) { x <- matrix(rnorm(m * m), m); crossprod(x) + diag(m) }
U <- random_spd(3L); E <- random_spd(3L)
# Changing the reference from category 1 to category 2 among four categories:
# contrasts (2-1, 3-1, 4-1) become (1-2, 3-2, 4-2).
A <- rbind(c(-1, 0, 0), c(-1, 1, 0), c(-1, 0, 1))
before <- .gt_nominal_eigenvalues(U, E)
after <- .gt_nominal_eigenvalues(A %*% U %*% t(A), A %*% E %*% t(A))
expect(max(abs(before - after)) < 1e-12, "generalized eigenvalues do not depend on the reference category")
trace_ratio <- function(U, E) sum(diag(U)) / sum(diag(U + E))
expect(abs(trace_ratio(U, E) - trace_ratio(A %*% U %*% t(A), A %*% E %*% t(A))) > 1e-3,
       "a trace ratio does depend on the reference category, which is why it is not used")
expect(all(before >= 0 & before <= 1), "every generalized eigenvalue lies in [0, 1]")
expect(abs(.gt_nominal_eigenvalues(matrix(0.8), matrix(0.3)) - 0.8 / 1.1) < 1e-15,
       "with one contrast the coefficient is the ratio of the binary case")
fake <- list(outcomes = "y", families = list(list(family = "categorical", link = "softmax", levels = c("a", "b"))),
             link_dimensions = data.frame(outcome = "y", family = "categorical", link = "softmax",
                                          dimension = "y::b_vs_a", stringsAsFactors = FALSE))
expect(abs(.gt_reliability_layout(fake, "categorical")$residual[1, 1] - pi^2 / 3) < 1e-15,
       "two categories have the logit residual pi^2/3, so K = 2 is exactly the binary logit coefficient")

# --- a small nominal panel ---------------------------------------------------------
labels <- c("a", "b", "c")
n_item <- 30L; n_rater <- 4L; n_rep <- 3L
panel <- expand.grid(item = factor(seq_len(n_item)), rater = factor(seq_len(n_rater)),
                     rep = factor(seq_len(n_rep)))
item_utility <- matrix(rnorm(n_item * 3L, sd = 0.9), n_item, 3L)
rater_utility <- matrix(rnorm(n_rater * 3L, sd = 0.4), n_rater, 3L)
utility <- item_utility[as.integer(panel$item), ] + rater_utility[as.integer(panel$rater), ] +
  matrix(-log(-log(runif(nrow(panel) * 3L))), nrow(panel), 3L)
panel$y <- factor(labels[max.col(utility)], levels = labels)
panel$z <- factor(ifelse(utility[, 2L] + rnorm(nrow(panel)) > 0.5, "1", "0"), levels = c("0", "1"))
design <- gt_design("item", "rater", random = c("item", "rater"), replicates = n_rep)
nominal_family <- function(reference)
  gt_family("categorical", levels = c(reference, setdiff(labels, reference)), reference = reference)
fit_nominal <- function(reference, covariance, hessian = FALSE)
  suppressWarnings(gt_fit(panel, "y", design = design, family = nominal_family(reference),
    covariance = covariance, control = gt_control(discrete = list(check_hessian = hessian))))

# --- the exchangeable structure ------------------------------------------------------
prep <- .gt_d_prepare(panel, "y", list(list(family = "categorical", link = "softmax",
                                            levels = labels, reference = "a")))
groups <- list(item = .gt_d_group(panel, "item"), rater = .gt_d_group(panel, "rater"))
control <- .gt_d_control(list())
setup <- .gt_d_covariance_setup(groups, prep$q, "exchangeable", control, prep$dimensions, prep$blocks)
expect(identical(setup$parameterization, "exchangeable") &&
         identical(names(setup$start), c("item::exchangeable[y]", "rater::exchangeable[y]")) &&
         all(setup$lower == 0),
       "one exact-zero-capable variance per source for the nominal outcome")
factors <- .gt_d_covariance_factors(c(0.49, 0.16), setup)
expect(max(abs(tcrossprod(factors$item) - 0.49 * (diag(2) + matrix(1, 2, 2)))) < 1e-14,
       "a source's covariance is sigma^2 (I + 11') on the contrasts")
expect(all(factors$rater[upper.tri(factors$rater)] == 0) && all(.gt_d_covariance_factors(c(0, 0), setup)$item == 0),
       "factors are lower triangular, and a zero variance gives a zero factor")
mapping <- .gt_d_information_mapping(c(prep$start, item = 0.49, rater = 0.16), prep, groups, setup)
expect(max(abs(mapping$jacobian[mapping$entries$component == "item", length(prep$start) + 1L] -
                 c(2, 1, 2))) < 1e-15, "the information map differentiates the covariance along I + 11'")
binary_prep <- .gt_d_prepare(panel, "z", list(list(family = "binary", link = "logit", levels = c("0", "1"))))
expect(refuses(.gt_d_covariance_setup(groups, 1L, "exchangeable", control, "z", binary_prep$blocks), "nominal"),
       "exchangeable is refused when no outcome is nominal")
expect(refuses(.gt_d_covariance_setup(groups, prep$q, "exchangeable",
                 .gt_d_control(list(covariance_parameterization = "log_cholesky")), prep$dimensions, prep$blocks),
               "variance coordinates"), "exchangeable refuses log-Cholesky coordinates")
fixed <- .gt_d_control(list(fixed_covariance = list(item = diag(2), rater = diag(2))))
expect(refuses(.gt_d_covariance_setup(groups, prep$q, "exchangeable", fixed, prep$dimensions, prep$blocks),
               "fixed_covariance"), "fixed covariance matrices are not combined with exchangeable")
check <- gt_preflight(panel, "y", design = design, family = nominal_family("a"), covariance = "exchangeable")
expect(isTRUE(check$fitting_feasible), "preflight admits an exchangeable nominal model")

# --- fitted coefficients ---------------------------------------------------------------
exchangeable_a <- fit_nominal("a", "exchangeable", hessian = TRUE)
exchangeable_c <- fit_nominal("c", "exchangeable")
unstructured_a <- fit_nominal("a", "unstructured")
unstructured_c <- fit_nominal("c", "unstructured")
expect(all(vapply(list(exchangeable_a, exchangeable_c, unstructured_a, unstructured_c),
                  function(f) isTRUE(f$numerically_accepted), logical(1))), "every nominal fit is accepted")
expect(abs(exchangeable_a$logLik - exchangeable_c$logLik) < 1e-6 &&
         abs(unstructured_a$logLik - unstructured_c$logLik) < 1e-6,
       "both covariance structures are the same model under every reference category")
expect(unstructured_a$logLik >= exchangeable_a$logLik - 1e-6, "exchangeable is nested in unstructured")
coefficient <- function(f) gt_reliability(f, scale = "latent")$per_trait
ra <- coefficient(exchangeable_a); rc <- coefficient(exchangeable_c)
ua <- coefficient(unstructured_a); uc <- coefficient(unstructured_c)
for (column in c("Erho2", "Erho2_min", "Erho2_max", "Phi", "Phi_min", "Phi_max")) {
  expect(abs(ra[[column]] - rc[[column]]) < 1e-4, paste("exchangeable", column, "is the same under references a and c"))
  expect(abs(ua[[column]] - uc[[column]]) < 1e-4, paste("unstructured", column, "is the same under references a and c"))
}
expect(identical(ra$latent_dimensions, 2L) && abs(ra$Erho2_min - ra$Erho2_max) < 1e-12,
       "under the exchangeable structure every eigenvalue coincides")
expect(ua$Erho2_min < ua$Erho2 && ua$Erho2 < ua$Erho2_max, "the unstructured coefficients have a range")
sigma2 <- exchangeable_a$covariance_components$item[1, 1] / 2
expect(abs(ra$Erho2 - sigma2 / (sigma2 + (pi^2 / 6) / (n_rater * n_rep))) < 1e-12,
       "the exchangeable coefficient is sigma^2 / (sigma^2 + (pi^2/6)/n) in category-utility units")

# --- delta-method error against a finite difference ------------------------------------
expect(isTRUE(exchangeable_a$uncertainty$available), "observed information is available for the interior fit")
context <- .gt_reliability_context(exchangeable_a, "latent")
mean_eigenvalue <- function(components)
  mean(.gt_nominal_eigenvalues(components$item, components$Residual / (n_rater * n_rep)))
entries <- exchangeable_a$uncertainty$entries
gradient <- vapply(seq_len(nrow(entries)), function(r) {
  shifted <- context$components
  s <- entries$component[[r]]; a <- entries$row[[r]]; b <- entries$column[[r]]
  shifted[[s]][a, b] <- shifted[[s]][a, b] + 1e-6
  if (a != b) shifted[[s]][b, a] <- shifted[[s]][b, a] + 1e-6
  (mean_eigenvalue(shifted) - mean_eigenvalue(context$components)) / 1e-6
}, numeric(1))
finite_difference <- sqrt(drop(crossprod(gradient, exchangeable_a$uncertainty$entry_covariance %*% gradient)))
expect(abs(ra$Erho2_se - finite_difference) / finite_difference < 1e-4,
       "the delta-method error of the mean eigenvalue matches a finite-difference gradient")
expect(is.finite(ra$Erho2_lower) && ra$Erho2_lower < ra$Erho2 && ra$Erho2 < ra$Erho2_upper,
       "the mean eigenvalue has an interval when information is available")

# --- refusals, D study and summaries ------------------------------------------------------
diagonal <- fit_nominal("a", "diagonal")
expect(refuses(gt_reliability(diagonal, scale = "latent"), "different model"),
       "a diagonal covariance on the contrasts has no coefficient")
expect(refuses(gt_reliability(exchangeable_a, scale = "latent", score = gt_score(c(y = 1))), "nominal outcome"),
       "a weighted composite with a nominal outcome is refused")
study <- gt_dstudy(exchangeable_a, data.frame(rater = c(1, 4, 10)), scale = "latent")$results
expect(all(diff(study$Erho2) > 0) && all(c("Erho2_min", "Erho2_max", "latent_dimensions") %in% names(study)),
       "a nominal D study increases with raters and reports the range")
expect(abs(study$Erho2[[2L]] - ra$Erho2) < 1e-12, "the D study at the fitted allocation reproduces the coefficient")
expect(any(grepl("generalized eigenvalues", capture.output(print(gt_reliability(exchangeable_a, scale = "latent"))))),
       "the printed coefficients explain the nominal mean and range")

# --- a joint nominal-and-binary exchangeable fit ---------------------------------------------
joint <- suppressWarnings(gt_fit(panel, c("y", "z"), design = design,
  family = list(y = nominal_family("a"), z = gt_family("binary", "logit", levels = c("0", "1"))),
  covariance = "exchangeable"))
binary_alone <- suppressWarnings(gt_fit(panel, "z", design = design,
  family = gt_family("binary", "logit", levels = c("0", "1")), covariance = "diagonal"))
joint_coefficients <- gt_reliability(joint, scale = "latent")$per_trait
expect(isTRUE(joint$numerically_accepted) && identical(joint_coefficients$latent_dimensions, c(2L, 1L)),
       "the joint fit is accepted and reports two contrast dimensions and one binary dimension")
expect(abs(joint$logLik - (exchangeable_a$logLik + binary_alone$logLik)) < 1e-4,
       "with outcomes independent within each source the joint likelihood is the sum of the two fits")
expect(abs(joint_coefficients$Erho2[[2L]] - coefficient(binary_alone)$Erho2) < 1e-4 &&
         abs(joint_coefficients$Erho2[[1L]] - ra$Erho2) < 1e-4,
       "each outcome's coefficient in the joint fit reproduces its separate fit")
cat("PASS: nominal coefficients are invariant to the reference category, reduce to the binary ratio,",
    "match the exchangeable closed form and a finite-difference error; exchangeable setup, refusals,",
    "D study and a factorizing joint fit.\n")
