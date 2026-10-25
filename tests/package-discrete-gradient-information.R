# Observed information from central differences of the analytic gradient,
# run from sources and from an installed archive. The reference is the
# finite-difference route's information, second differences of the objective,
# computed at the same parameters: on the frozen binary and ordinal information
# panels and on a joint interior panel the two Hessians must agree within 1e-6
# on the step-discrepancy scale. Fits on the two routes must agree on the
# source-covariance uncertainty and the latent coefficient standard errors;
# the analytic route must use 4p gradients, record its method and asymmetry,
# refuse an asymmetric or refused gradient without falling back, and keep the
# boundary and acceptance refusals.
if (identical(Sys.getenv("GT_GRADIENT_INFORMATION_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
check <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label, call. = FALSE)

# The frozen response fixture shipped with the installed tests.
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
test_directory <- "."
if (length(script_arg) == 1L) {
  script_path <- sub("^--file=", "", script_arg)
  if (!file.exists(script_path)) script_path <- gsub("~+~", " ", script_path, fixed = TRUE)
  test_directory <- dirname(normalizePath(script_path, mustWork = TRUE))
}
fixture <- file.path(test_directory, "fixtures", "discrete-information-panels.csv")
if (!file.exists(fixture)) fixture <- file.path("tests", "fixtures", "discrete-information-panels.csv")
check(file.exists(fixture), "the frozen information fixture is available")
panels <- read.csv(fixture, stringsAsFactors = FALSE)
panel <- function(family) {
  name <- if (family == "binary") "binary_logit_single_source" else "ordinal_logit_crossed"
  data <- panels[panels$panel == name, c("item", "rater", "y")]
  levels <- if (family == "binary") c("0", "1") else paste0("c", 1:3)
  data$y <- if (family == "binary") as.integer(data$y) else ordered(data$y, levels = levels)
  list(data = data, family = gt_family(family, "logit", levels = levels))
}

settings <- function(route, ...) list(engine = "sparse", check_hessian = TRUE, maxit = 300L,
                                      covariance_parameterization = "cholesky", gradient = route, ...)
fit_route <- function(data, outcomes, family, route, design = gt_design("item", "rater", random = "item"), ...)
  suppressWarnings(gt_fit(data, outcomes, design, family, control = gt_control(discrete = settings(route, ...))))

# The finite-difference route's information at given parameters, through the
# same internal function the fit calls, with the fit's validation settings.
problem_for <- function(data, outcomes, design, families) {
  problem <- internal(".gt_d_laplace_problem")(data, outcomes, design, families,
    control = list(engine = "sparse", covariance_parameterization = "cholesky", check_hessian = TRUE))
  problem$validation <- problem$control
  problem$validation$inner_tol <- min(problem$control$inner_tol, problem$control$validation_inner_tol)
  problem$validation$reltol <- min(problem$control$reltol, problem$control$validation_reltol)
  problem
}
information_at <- function(problem, parameters, gradient = NULL)
  internal(".gt_d_information")(parameters, problem$prep, problem$groups, problem$setup, problem$validation,
    laplace = internal(".gt_d_sparse_evaluator")(), lower = problem$lower, upper = problem$upper,
    numerically_accepted = TRUE, gradient = gradient)
normalized <- function(A, B) max(abs(A - B) / pmax(1, sqrt(outer(abs(diag(B)), abs(diag(B))))))

compare <- function(label, data, outcomes, family, families, design = gt_design("item", "rater", random = "item"),
                    reliability = TRUE) {
  an <- fit_route(data, outcomes, family, "analytic", design)
  fd <- fit_route(data, outcomes, family, "finite_difference", design)
  check(isTRUE(an$numerically_accepted) && isTRUE(fd$numerically_accepted) &&
          isTRUE(an$uncertainty$available) && isTRUE(fd$uncertainty$available),
        paste(label, "is accepted with observed information on both routes"))
  u <- an$uncertainty
  p <- length(an$parameters)
  check(identical(u$hessian_method, "analytic_gradient_differences") &&
          identical(fd$uncertainty$hessian_method, "objective_second_differences") &&
          is.na(fd$uncertainty$hessian_asymmetry),
        paste(label, "records the information method of each route"))
  check(u$information_gradient_evaluations == 4L * p, paste(label, "uses 4p gradients"))
  check(is.finite(u$hessian_asymmetry) && u$hessian_asymmetry < 1e-5 && isSymmetric(unname(u$hessian)),
        sprintf("%s: asymmetry %.3g before symmetrization", label, u$hessian_asymmetry))
  problem <- problem_for(data, outcomes, design, families)
  check(identical(names(problem$start), names(an$parameters)), paste(label, "has the fit's coordinates"))
  scalar <- information_at(problem, an$parameters)
  difference <- normalized(u$hessian, scalar$hessian)
  check(isTRUE(scalar$available) && difference < 1e-6,
        sprintf("%s: gradient-difference and objective-difference Hessians differ by %.3g", label, difference))
  vcov_difference <- max(abs(gt_component_vcov(an) - gt_component_vcov(fd)) / pmax(abs(gt_component_vcov(fd)), 1e-12))
  check(vcov_difference < 1e-4, sprintf("%s: source-covariance uncertainty differs by %.3g relative", label, vcov_difference))
  if (reliability) {
    ra <- as.data.frame(gt_reliability(an, scale = "latent"))
    rf <- as.data.frame(gt_reliability(fd, scale = "latent"))
    check(max(abs(ra$Erho2_se - rf$Erho2_se), abs(ra$Phi_se - rf$Phi_se)) < 1e-5,
          paste(label, "has the same latent coefficient standard errors"))
  }
  cat(sprintf("PASS: %s (%d coordinates, %d gradients; same-point Hessian difference %.2e; asymmetry %.2e; uncertainty difference %.2e)\n",
              label, p, u$information_gradient_evaluations, difference, u$hessian_asymmetry, vcov_difference))
  invisible(list(an = an, fd = fd, problem = problem))
}

binary <- panel("binary")
ordinal <- panel("ordinal")
binary_fits <- compare("binary logit, one source", binary$data, "y", binary$family, list(y = binary$family))
compare("ordinal logit, one source", ordinal$data, "y", ordinal$family, list(y = ordinal$family))
joint <- binary$data
joint$z <- ordinal$data$y[match(paste(joint$item, joint$rater), paste(ordinal$data$item, ordinal$data$rater))]
check(!anyNA(joint$z), "the joint panel pairs every binary row with an ordinal row")
joint_families <- list(y = binary$family, z = ordinal$family)
compare("joint binary and ordinal, one unstructured source", joint, c("y", "z"), joint_families, joint_families,
        reliability = FALSE)

# --- refusals ---------------------------------------------------------------------
# A refused gradient makes information unavailable with its reason; the
# objective-difference method is not substituted.
problem <- binary_fits$problem
at <- binary_fits$an$parameters
calls <- 0L
refusing <- function(x) { calls <<- calls + 1L; stop("An information gradient was refused (injected).", call. = FALSE) }
refused <- information_at(problem, at, refusing)
check(!isTRUE(refused$available) && grepl("refused (injected)", refused$reason, fixed = TRUE) &&
        is.na(refused$method) && calls == 1L,
      "a refused information gradient ends the information step without a fallback")
# An asymmetric difference matrix is refused before it is symmetrized.
route <- internal(".gt_d_gradient_route")(problem$prep, problem$groups, problem$setup, problem$context,
                                         problem$envelope, names(problem$start))
evaluator <- internal(".gt_d_sparse_evaluator")()
exact <- function(x) {
  record <- evaluator(x, problem$prep, problem$groups, problem$setup, problem$validation, details = TRUE)
  route$at(x, record, problem$validation)$gradient
}
reference <- information_at(problem, at, exact)
check(isTRUE(reference$available), "the exact gradient supplies information")
# A cross term of a fifth of the curvature scale in one triangle only: an
# asymmetry of 0.2 on the discrepancy scale, above the default tolerance 0.05.
skew <- 0.2 * max(1, sqrt(abs(reference$hessian[1L, 1L] * reference$hessian[2L, 2L])))
skewed <- function(x) {
  g <- exact(x)
  g[[1L]] <- g[[1L]] + skew * (x[[2L]] - at[[2L]])
  g
}
asymmetric <- information_at(problem, at, skewed)
check(!isTRUE(asymmetric$available) && grepl("not symmetric", asymmetric$reason, fixed = TRUE),
      "an asymmetric gradient-difference matrix is refused")
# The boundary and acceptance refusals are those of the finite-difference route.
seeded <- function(seed) {
  suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rejection"))
  set.seed(seed)
}
seeded(9001L)
zero <- expand.grid(rater = factor(1:6), item = factor(1:18))
zero$label <- rbinom(nrow(zero), 1L, plogis(.3 + rnorm(18, sd = .9)[zero$item] + rnorm(6, sd = .5)[zero$rater]))
boundary <- lapply(c("analytic", "finite_difference"), function(route)
  fit_route(zero, "label", gt_family("binary"), route, gt_design("item", "rater", full_cell = FALSE))$uncertainty)
check(!boundary[[1L]]$available && identical(boundary[[1L]]$reason, boundary[[2L]]$reason) &&
        grepl("boundary", boundary[[1L]]$reason, fixed = TRUE),
      "a boundary source refuses information on both routes with the same reason")
unaccepted <- fit_route(zero, "label", gt_family("binary"), "analytic", gt_design("item", "rater", full_cell = FALSE),
                        alternative_starts = 0L)$uncertainty
check(!unaccepted$available && grepl("numerically accepted", unaccepted$reason, fixed = TRUE),
      "an unaccepted fit refuses information on the analytic route")
cat("PASS: refusals\n")
