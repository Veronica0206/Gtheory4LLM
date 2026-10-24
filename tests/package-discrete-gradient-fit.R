# The analytic gradient inside the fit's L-BFGS-B attempts, run from sources
# and from an installed archive. The reference is the same fit on the
# finite-difference route: the discrete characterization panels and a joint
# panel are fitted on the sparse engine in natural Cholesky coordinates on both
# routes and must reach the same acceptance decisions, acceptance failures and
# boundary sources, with likelihoods, source variances and coefficients within
# the characterization tolerances. The analytic route's own record is checked:
# its ledger, the reuse of the objective's record, the selected-point
# comparison with the stationarity check's finite-difference score, an injected
# refusal that ends every attempt with no finite-difference fallback, the
# control and fit-start refusals, declared scaling, and the preflight report.
if (identical(Sys.getenv("GT_DISCRETE_GRADIENT_FIT_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
check <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label, call. = FALSE)
expect_error <- function(expr, text, label) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  check(inherits(error, "error") && grepl(text, conditionMessage(error), fixed = TRUE),
        paste0(label, " (", if (inherits(error, "error")) conditionMessage(error) else "no error", ")"))
  invisible(error)
}

# --- controls -------------------------------------------------------------------
control <- internal(".gt_d_control")
check(identical(control(list())$gradient, "finite_difference"), "the default route is finite differences")
for (bad in list(NULL, NA, 1, "exact", c("analytic", "finite_difference")))
  expect_error(control(list(engine = "sparse", gradient = bad)), "gradient must be",
               "a malformed gradient control is refused")
expect_error(control(list(gradient = "analytic")), "requires engine = 'sparse'",
             "the analytic route is refused on the dense engine")
expect_error(control(list(engine = "sparse", optimizer = "nlminb", gradient = "analytic")),
             "requires engine = 'sparse'", "the analytic route is refused with nlminb")
cat("PASS: controls\n")

# --- panels: the discrete characterization seeds -----------------------------------
seeded <- function(seed) {
  suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rejection"))
  set.seed(seed)
}
data_binary <- function() {
  seeded(9001L)
  d <- expand.grid(rater = factor(1:6), item = factor(1:18))
  eta <- .3 + rnorm(18, sd = .9)[d$item] + rnorm(6, sd = .5)[d$rater]
  d$label <- rbinom(nrow(d), 1L, plogis(eta))
  d
}
data_ordinal <- function() {
  seeded(4242L)
  d <- expand.grid(rater = factor(1:6), item = factor(1:18))
  eta <- rnorm(18, sd = .8)[d$item] + rnorm(6, sd = .4)[d$rater] + rnorm(nrow(d))
  d$grade <- ordered(c("low", "mid", "high")[1L + (eta > -.7) + (eta > .6)],
                     levels = c("low", "mid", "high"))
  d
}
data_categorical <- function() {
  seeded(606L)
  d <- expand.grid(rater = factor(1:6), item = factor(1:16))
  shift <- rnorm(16, sd = .8)[d$item]
  utility <- cbind(0, .2 + shift, -.3 + shift / 2) +
    matrix(-log(-log(runif(3 * nrow(d)))), nrow(d), 3)
  d$topic <- factor(c("a", "b", "c")[max.col(utility)], levels = c("a", "b", "c"))
  d
}
data_joint <- function() {
  d <- data_binary()
  d$grade <- data_ordinal()$grade
  d
}
design <- function() gt_design("item", "rater", full_cell = FALSE)
settings <- function(route, ...) gt_control(discrete = list(engine = "sparse", maxit = 200L,
  covariance_parameterization = "cholesky", gradient = route, ...))
fit_route <- function(data, outcomes, family, route, ...)
  suppressWarnings(gt_fit(data, outcomes, design(), family, control = settings(route, ...)))

# The characterization tolerances (tests/package-characterization.R).
LIKELIHOOD_TOLERANCE <- 1e-4
VARIANCE_TOLERANCE <- 1e-4
VARIANCE_FLOOR_FRACTION <- 1e-6
COEFFICIENT_TOLERANCE <- 1e-5
STALL_REFUSALS <- c("outer_stationarity_failed", "restart_or_tolerance_stability_failed")
long_double <- isTRUE(capabilities("long.double"))

# Two criteria. The characterization panels use the characterization
# tolerances, the regression net the package keeps for these fits. A panel
# outside that set uses the fit's own restart-stability rule, the comparison by
# which the package calls two restarts one solution: relative objective
# difference within stability_objective_tol and scaled parameter distance within
# stability_parameter_tol (their defaults, 1e-6 and 0.02).
resolve_families <- internal(".gt_resolve_families")
resolve_design <- internal(".gt_resolve_design")
stability_distance <- function(fd, an, data, outcomes, family) {
  resolved <- resolve_families(data[c("item", "rater", outcomes)], outcomes, family)
  problem <- internal(".gt_d_laplace_problem")(resolved$data, outcomes,
    resolve_design(resolved$data, design(), "discrete"), resolved$families,
    control = list(engine = "sparse", covariance_parameterization = "cholesky"))
  check(identical(names(problem$start), names(fd$parameters)), "the restart-stability problem has the fit's coordinates")
  internal(".gt_d_fit_distance")(an$parameters, fd$parameters, problem$prep, problem$setup)
}

compare <- function(label, fd, an, reliability = FALSE, stall_exception = FALSE, stability = NULL) {
  failures <- function(fit) sort(as.character(gt_diagnostics(fit)$acceptance_failures), method = "radix")
  # On a platform without long double the finite-difference ordinal fit has
  # been refused by the stall safeguards (#59; tests/package-characterization.R).
  # The same refusal on either route is reported there, not compared.
  stalled <- function(fit) !isTRUE(fit$numerically_accepted) && length(failures(fit)) &&
    all(failures(fit) %in% STALL_REFUSALS)
  if (stall_exception && !long_double && (stalled(fd) || stalled(an))) {
    cat(sprintf("NOTE: %s refused by the stall safeguards on this platform without long double (finite difference [%s], analytic [%s])\n",
                label, paste(failures(fd), collapse = ","), paste(failures(an), collapse = ",")))
    return(invisible(NULL))
  }
  check(identical(fd$numerically_accepted, an$numerically_accepted) &&
          identical(fd$optimizer_completed, an$optimizer_completed),
        paste(label, "reaches the same acceptance decision on both routes"))
  check(identical(failures(fd), failures(an)), paste(label, "has the same acceptance failures"))
  check(identical(sort(fd$diagnostics$boundary_sources), sort(an$diagnostics$boundary_sources)),
        paste(label, "has the same boundary sources"))
  if (is.null(stability))
    check(abs(fd$minus2loglik - an$minus2loglik) < LIKELIHOOD_TOLERANCE,
          sprintf("%s: -2 log L differs by %.3g", label, abs(fd$minus2loglik - an$minus2loglik)))
  # Source variances are compared at accepted points. A refused fit can stop
  # anywhere on a flat valley: in natural Cholesky coordinates the gradient of a
  # variance near zero vanishes in proportion to its factor entry, and without
  # an alternative start neither route is asked to settle it.
  variances <- function(fit) unlist(lapply(fit$covariance_components, diag))
  vf <- variances(fd)
  va <- variances(an)
  scale <- pmax(abs(vf), VARIANCE_FLOOR_FRACTION * max(abs(vf)))
  check(identical(names(vf), names(va)), paste(label, "has the same sources"))
  if (!is.null(stability)) {
    objective <- abs(fd$minus2loglik - an$minus2loglik) / 2 / max(1, abs(fd$minus2loglik) / 2)
    distance <- stability(fd, an)
    check(objective <= 1e-6 && distance <= 0.02,
          sprintf("%s: relative objective difference %.3g, scaled parameter distance %.3g", label, objective, distance))
    cat(sprintf("  %s: relative objective difference %.2e, scaled parameter distance %.2e; -2 log L finite difference %.10f, analytic %.10f\n",
                label, objective, distance, fd$minus2loglik, an$minus2loglik))
  } else if (isTRUE(fd$numerically_accepted))
    check(all(abs(va - vf) <= VARIANCE_TOLERANCE * scale),
          sprintf("%s: source variances differ by up to %.3g relative", label, max(abs(va - vf) / scale)))
  if (reliability && isTRUE(fd$numerically_accepted)) {
    rf <- gt_reliability(fd, scale = "latent")$per_trait
    ra <- gt_reliability(an, scale = "latent")$per_trait
    check(max(abs(c(rf$Erho2 - ra$Erho2, rf$Phi - ra$Phi))) < COEFFICIENT_TOLERANCE,
          paste(label, "has the same coefficients"))
  }
  g <- an$diagnostics$gradient
  check(identical(fd$diagnostics$gradient, list(route = "finite_difference")),
        paste(label, "records the finite-difference route"))
  check(identical(g$route, "analytic") && g$gradient_evaluations > 0L && g$refusals == 0L &&
          g$evaluated_before_gradient == 0L && length(g$retained_refusals) == 0L,
        paste(label, "records an analytic ledger whose every gradient reused its objective record"))
  check(identical(gt_diagnostics(an)$gradient, g), paste(label, "exposes the ledger through gt_diagnostics()"))
  check(an$diagnostics$evaluations$count < fd$diagnostics$evaluations$count,
        paste(label, "needs fewer objective evaluations on the analytic route"))
  if (isTRUE(an$numerically_accepted))
    check(isTRUE(g$selected_point$available) && g$selected_point$max_scaled_fixed_difference < 1e-5,
          sprintf("%s: the analytic and finite-difference fixed-effect scores at the selected point differ by %.3g",
                  label, g$selected_point$max_scaled_fixed_difference))
  cat(sprintf("PASS: %s (accepted %s; -2 log L difference %.2e; largest relative variance difference %.2e; evaluations %d against %d; %d gradients)\n",
              label, an$numerically_accepted, abs(fd$minus2loglik - an$minus2loglik), max(abs(va - vf) / scale),
              an$diagnostics$evaluations$count, fd$diagnostics$evaluations$count, g$gradient_evaluations))
  invisible(list(fd = fd, an = an))
}

both <- function(label, data, outcomes, family, reliability = FALSE, stall_exception = FALSE,
                 criterion = "characterization", ...)
  compare(label, fit_route(data, outcomes, family, "finite_difference", ...),
          fit_route(data, outcomes, family, "analytic", ...), reliability, stall_exception,
          if (identical(criterion, "stability"))
            function(fd, an) stability_distance(fd, an, data, outcomes, family))

binary <- both("binary logit, one source at zero", data_binary(), "label", gt_family("binary"), reliability = TRUE)
both("ordinal logit", data_ordinal(), "grade", gt_family("ordinal"), reliability = TRUE, stall_exception = TRUE)
both("nominal, three categories", data_categorical(), "topic", gt_family("categorical"))
both("binary logit without an alternative start", data_binary(), "label", gt_family("binary"),
     alternative_starts = 0L)
both("joint binary and ordinal", data_joint(), c("label", "grade"),
     list(label = gt_family("binary"), grade = gt_family("ordinal")), stall_exception = TRUE,
     criterion = "stability")

# Declared scaling: optim() rescales a supplied gradient itself, so the route
# returns stored-coordinate gradients and each attempt keeps its own metric.
scaled <- both("binary logit with optimizer_scaling = 'start'", data_binary(), "label", gt_family("binary"),
               optimizer_scaling = "start")
check(all(vapply(scaled$an$diagnostics$attempts, function(a)
  identical(a$optimizer_control$parscale, pmax(1, abs(a$start)) / sqrt(nrow(data_binary()))), logical(1))),
  "each analytic attempt keeps the metric of its own start")

# The printed diagnostics name the route.
printed <- capture.output(print(gt_diagnostics(binary$an)))
check(any(grepl("Outer gradient: analytic", printed, fixed = TRUE)), "printing names the analytic route")
check(!any(grepl("Outer gradient", capture.output(print(gt_diagnostics(binary$fd))), fixed = TRUE)),
      "printing a finite-difference fit is unchanged")

# --- fit-start refusals ----------------------------------------------------------
expect_error(suppressWarnings(gt_fit(data_binary(), "label", design(), gt_family("binary"),
  control = gt_control(discrete = list(engine = "sparse", gradient = "analytic")))),
  "covariance_parameterization = 'cholesky'", "variance coordinates are refused at fit start")
expect_error(suppressWarnings(gt_fit(data_categorical(), "topic", design(), gt_family("categorical"),
  covariance = "exchangeable", control = gt_control(discrete = list(engine = "sparse", gradient = "analytic")))),
  "exchangeable covariance", "exchangeable coordinates are refused at fit start")
cat("PASS: fit-start refusals\n")

# --- the retained record ---------------------------------------------------------
# A record is reused only at the same parameters and phase; a different point, a
# different phase or a cleared route evaluates the objective first.
problem <- internal(".gt_d_laplace_problem")(data_binary(), "label", gt_design("item", "rater"),
  list(label = gt_family("binary")), control = list(engine = "sparse", covariance_parameterization = "cholesky"))
evaluator <- internal(".gt_d_sparse_evaluator")()
route <- internal(".gt_d_gradient_route")(problem$prep, problem$groups, problem$setup, problem$context,
                                         problem$envelope, names(problem$start))
evaluations <- 0L
objective <- function(phase) function(p) {
  evaluations <<- evaluations + 1L
  value <- evaluator(p, problem$prep, problem$groups, problem$setup, problem$control, details = TRUE)
  route$retain(p, value, phase)
  value$nll
}
coarse <- route$callback("coarse", objective("coarse"), problem$control)
tight <- route$callback("tight", objective("tight"), problem$control)
at <- problem$start
other <- at + 0.05
invisible(objective("coarse")(at))
g_at <- coarse(at)
check(evaluations == 1L, "a gradient at the retained point reuses its record")
invisible(tight(at))
check(evaluations == 2L, "a gradient for another phase evaluates first")
invisible(objective("coarse")(other))
invisible(coarse(at))
check(evaluations == 4L, "a later evaluation replaces the record")
route$clear()
check(identical(coarse(at), g_at) && evaluations == 5L, "a cleared route evaluates first and returns the same gradient")
ledger <- route$summary()
check(ledger$gradient_evaluations == 4L && ledger$evaluated_before_gradient == 3L && ledger$refusals == 0L,
      "the ledger counts gradients and evaluations made for them")
cat("PASS: retained record\n")

# --- an injected refusal ends every attempt; there is no fallback ------------------
# The attempt evaluations of this evaluator carry a corrupted linear predictor,
# so the response kernel at their modes is invalid and every gradient refuses;
# evaluations outside attempts are untouched.
injected_data <- data_binary()
resolved <- resolve_families(injected_data[c("item", "rater", "label")], "label", gt_family("binary"))
injected_design <- resolve_design(resolved$data, design(), "discrete")
sparse <- internal(".gt_d_sparse_evaluator")()
corrupting <- function(parameters, prep, groups, setup, control, details = FALSE, factors_override = NULL) {
  value <- sparse(parameters, prep, groups, setup, control, details = details,
                  factors_override = factors_override)
  if (details && !is.null(control$inner_start) && isTRUE(value$valid)) value$eta[] <- NA_real_
  value
}
attr(corrupting, "reset") <- attr(sparse, "reset")
refused <- tryCatch(internal(".gt_fit_discrete")(resolved$data, "label", injected_design, resolved$families,
  control = list(engine = "sparse", covariance_parameterization = "cholesky", gradient = "analytic", maxit = 50L),
  .laplace = corrupting, .engine = "sparse_marginal_laplace"), error = identity)
check(inherits(refused, "gt_discrete_numerical_failure"), "a fit whose every gradient refuses ends without a candidate")
messages <- vapply(refused$attempts, function(a) if (is.null(a$error)) "" else a$error, character(1))
check(length(messages) == 4L && all(grepl("Analytic gradient refused at gradient", messages, fixed = TRUE)) &&
        all(grepl("invalid_response", messages, fixed = TRUE)),
      "every attempt ended on the named refusal")
cat("PASS: injected refusal\n")

# --- preflight ---------------------------------------------------------------------
joint_preflight <- gt_preflight(data_joint(), c("label", "grade"), design(),
  list(label = gt_family("binary"), grade = gt_family("ordinal")),
  control = gt_control(discrete = list(engine = "sparse", gradient = "analytic")))
rows <- joint_preflight$checks
check(isTRUE(joint_preflight$fitting_feasible) &&
        all(rows$passed[rows$check %in% c("analytic_gradient_caps", "analytic_gradient_coordinates")]) &&
        sum(rows$check %in% c("analytic_gradient_caps", "analytic_gradient_coordinates")) == 2L,
      "preflight reports the analytic route's caps and coordinates")
check(isTRUE(joint_preflight$resources$analytic_gradient$passed) &&
        joint_preflight$resources$analytic_gradient$measurements[["dimension"]] == joint_preflight$random_dimension,
      "preflight records the measured caps")
variance_preflight <- gt_preflight(data_binary(), "label", design(), gt_family("binary"),
  control = gt_control(discrete = list(engine = "sparse", gradient = "analytic")))
check(!isTRUE(variance_preflight$fitting_feasible) &&
        !variance_preflight$checks$passed[variance_preflight$checks$check == "analytic_gradient_coordinates"],
      "preflight refuses variance coordinates for the analytic route")
plain <- gt_preflight(data_binary(), "label", design(), gt_family("binary"),
  control = gt_control(discrete = list(engine = "sparse")))
check(!any(grepl("analytic", plain$checks$check)) && is.null(plain$resources$analytic_gradient),
      "a finite-difference preflight is unchanged")
cat("PASS: preflight\n")
