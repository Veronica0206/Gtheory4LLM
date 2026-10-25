# Observed information from central differences of the analytic gradient,
# run from sources and from an installed archive. The reference is the
# finite-difference route's information, second differences of the objective,
# computed at the same parameters: on the frozen binary and ordinal information
# panels and on a joint interior panel the two Hessians must agree within 1e-6
# on the step-discrepancy scale. Fits on the two routes must agree on the
# source-covariance uncertainty and the latent coefficient standard errors;
# the analytic route must use 4p gradients, record its method and asymmetry,
# and refuse an asymmetric or refused gradient without falling back. At a
# boundary source both routes hold that source fixed and invert the rest; held
# at zero, the result must equal the information of the model without the
# source. An unaccepted fit is refused.
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
information_at <- function(problem, parameters, gradient = NULL, boundary = character())
  internal(".gt_d_information")(parameters, problem$prep, problem$groups, problem$setup, problem$validation,
    laplace = internal(".gt_d_sparse_evaluator")(), lower = problem$lower, upper = problem$upper,
    numerically_accepted = TRUE, boundary_components = boundary, gradient = gradient)
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
unaccepted <- fit_route(binary$data, "y", binary$family, "analytic", alternative_starts = 0L)$uncertainty
check(!unaccepted$available && grepl("numerically accepted", unaccepted$reason, fixed = TRUE),
      "an unaccepted fit refuses information on the analytic route")
cat("PASS: refusals\n")

# --- a source on its boundary ------------------------------------------------------
seeded <- function(seed) {
  suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rejection"))
  set.seed(seed)
}
conditional <- function(label, fits, held, kind, data, outcomes, families) {
  for (route in names(fits)) {
    u <- fits[[route]]$uncertainty
    errors <- fits[[route]]$component_standard_errors
    check(isTRUE(fits[[route]]$numerically_accepted) && identical(fits[[route]]$diagnostics$boundary_sources, held) &&
            isTRUE(u$available) && isTRUE(u$restricted_to_interior) && identical(u$fixed_components, held) &&
            identical(u$fixed_component_kinds, stats::setNames(kind, held)),
          paste(label, "holds", held, "fixed as", kind, "on the", route, "route"))
    coordinates <- names(fits[[route]]$parameters)
    owned <- startsWith(coordinates, paste0(held, "::"))
    check(identical(u$information_coordinates, coordinates[!owned]) && all(is.na(u$parameter_standard_errors[owned])) &&
            all(u$parameter_covariance[owned, ] == 0) && all(u$entry_covariance[u$entries$component == held, ] == 0) &&
            all(is.na(errors$std_error[errors$component == held])) && all(is.finite(errors$std_error[errors$component != held])),
          paste(label, "gives the held source no sampling variance and no standard error on the", route, "route"))
    table <- as.data.frame(gt_reliability(fits[[route]], scale = "latent"))
    check(all(table$Erho2_interval_available & table$Phi_interval_available) && all(table$uncertainty_conditional) &&
            all(table$uncertainty_conditioning == internal(".gt_conditioning_clause")(held, u$fixed_component_kinds)),
          paste(label, "has latent intervals that name the conditioning on the", route, "route"))
  }
  # The two methods at the same parameters, as for interior fits; the two
  # routes' fits stop at slightly different points, so they agree more loosely.
  problem <- problem_for(data, outcomes, gt_design("item", "rater", full_cell = FALSE), families)
  scalar <- information_at(problem, fits$analytic$parameters, boundary = held)
  difference <- normalized(fits$analytic$uncertainty$hessian, scalar$hessian)
  check(isTRUE(scalar$restricted_to_interior) && identical(rownames(scalar$hessian), rownames(fits$analytic$uncertainty$hessian)) &&
          difference < 1e-6,
        sprintf("%s: at the same parameters the two methods' conditional Hessians differ by %.3g", label, difference))
  vcov_difference <- max(abs(gt_component_vcov(fits$analytic) - gt_component_vcov(fits$finite_difference)) /
                           pmax(abs(gt_component_vcov(fits$finite_difference)), 1e-12))
  check(vcov_difference < 1e-3, sprintf("%s: the routes' fitted conditional uncertainty differs by %.3g relative", label, vcov_difference))
  difference
}

# A rater variance fitted at exactly zero is held at zero. There the objective
# is that of the model without a rater source, so the conditional information
# must equal that model's information at the same parameters.
seeded(9001L)
zero <- expand.grid(rater = factor(1:6), item = factor(1:18))
zero$label <- rbinom(nrow(zero), 1L, plogis(.3 + rnorm(18, sd = .9)[zero$item] + rnorm(6, sd = .5)[zero$rater]))
zero_fits <- lapply(c(analytic = "analytic", finite_difference = "finite_difference"), function(route)
  fit_route(zero, "label", gt_family("binary"), route, gt_design("item", "rater", full_cell = FALSE)))
zero_routes <- conditional("a zero rater variance", zero_fits, "rater", "zero", zero, "label", list(label = gt_family("binary")))
without <- problem_for(zero, "label", gt_design("item", "rater", random = "item"), list(label = gt_family("binary")))
check(identical(names(without$start), zero_fits$finite_difference$uncertainty$information_coordinates),
      "the model without the rater source has the held fit's remaining coordinates")
reference <- information_at(without, zero_fits$finite_difference$parameters[names(without$start)])
held_difference <- max(abs(zero_fits$finite_difference$uncertainty$parameter_covariance[names(without$start), names(without$start)] -
                             reference$parameter_covariance) / abs(reference$parameter_covariance))
check(isTRUE(reference$available) && held_difference < 1e-6,
      sprintf("held at zero, the information equals the model without the source (relative difference %.3g)", held_difference))

# A rank-one rater covariance in a joint binary-ordinal panel is held fixed at
# its fitted, singular but nonzero value.
seeded(9001L)
joint_panel <- expand.grid(rater = factor(1:6), item = factor(1:18))
joint_panel$label <- rbinom(nrow(joint_panel), 1L,
  plogis(.3 + rnorm(18, sd = .9)[joint_panel$item] + rnorm(6, sd = .5)[joint_panel$rater]))
seeded(4242L)
eta <- rnorm(18, sd = .8)[joint_panel$item] + rnorm(6, sd = .4)[joint_panel$rater] + rnorm(nrow(joint_panel))
joint_panel$grade <- ordered(c("low", "mid", "high")[1L + (eta > -.7) + (eta > .6)], levels = c("low", "mid", "high"))
joint_panel_families <- list(label = gt_family("binary"), grade = gt_family("ordinal"))
singular_fits <- lapply(c(analytic = "analytic", finite_difference = "finite_difference"), function(route)
  fit_route(joint_panel, c("label", "grade"), joint_panel_families, route, gt_design("item", "rater", full_cell = FALSE)))
singular_routes <- conditional("a rank-one rater covariance", singular_fits, "rater", "singular_nonzero",
                               joint_panel, c("label", "grade"), joint_panel_families)
check(min(eigen(singular_fits$analytic$covariance_components$rater, symmetric = TRUE, only.values = TRUE)$values) < 1e-6 &&
        max(eigen(singular_fits$analytic$covariance_components$rater, symmetric = TRUE, only.values = TRUE)$values) > 1e-2,
      "the joint panel's rater covariance is singular but nonzero")
cat(sprintf("PASS: boundary sources held fixed (same-point Hessian differences %.2e and %.2e; held at zero vs. the model without it %.2e)\n",
            zero_routes, singular_routes, held_difference))
