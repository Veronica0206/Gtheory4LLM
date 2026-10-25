# The boundary escape after tight attempts, run from sources and from an
# installed archive. A joint binary-ordinal panel is fitted from a supplied
# start whose item factor has an exact zero column. On the analytic route the
# objective's derivative along that column is exactly zero, so both primary
# attempts stay singular and the fit is refused on restart stability. With
# boundary_escape = "projected" the primary tight attempt is stepped off the
# boundary and rerun, and the fit is accepted at the reference optimum. Fits
# that need no escape are unchanged, the partial covariance scores equal the
# full check's, the records say what was done, and the refusals name their
# reason.
if (identical(Sys.getenv("GT_BOUNDARY_ESCAPE_TEST_SOURCE"), "true")) {
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
}

# --- controls and the factor helper ---------------------------------------------
control <- internal(".gt_d_control")
check(identical(control(list())$boundary_escape, "none"), "the escape is off by default")
for (bad in list(NULL, NA, 1, "always", c("none", "projected")))
  expect_error(control(list(boundary_escape = bad)), "boundary_escape must be", "a malformed escape control is refused")
psd_cholesky <- internal(".gt_d_psd_cholesky")
singular <- tcrossprod(cbind(c(1, 0.5, 0.2), c(0, 0.8, -0.3)))
L <- psd_cholesky(singular)
check(!is.null(L) && all(L[upper.tri(L)] == 0) && all(diag(L) >= 0) && max(abs(tcrossprod(L) - singular)) < 1e-12 &&
        L[3, 3] == 0, "a singular PSD matrix has a lower-triangular factor with a zero pivot")
check(is.null(psd_cholesky(matrix(c(1, 2, 2, 1), 2))), "an indefinite matrix has no such factor")
cat("PASS: controls and factor helper\n")

# --- the stuck fixture -----------------------------------------------------------
seeded <- function(seed) {
  suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rejection"))
  set.seed(seed)
}
seeded(9001L)
d <- expand.grid(rater = factor(1:6), item = factor(1:18))
eta <- .3 + rnorm(18, sd = .9)[d$item] + rnorm(6, sd = .5)[d$rater]
d$label <- rbinom(nrow(d), 1L, plogis(eta))
seeded(4242L)
e <- expand.grid(rater = factor(1:6), item = factor(1:18))
eta <- rnorm(18, sd = .8)[e$item] + rnorm(6, sd = .4)[e$rater] + rnorm(nrow(e))
d$grade <- ordered(c("low", "mid", "high")[1L + (eta > -.7) + (eta > .6)], levels = c("low", "mid", "high"))
families <- list(label = gt_family("binary"), grade = gt_family("ordinal"))
design <- gt_design("item", "rater", full_cell = FALSE)
fit_with <- function(...) suppressWarnings(gt_fit(d, c("label", "grade"), design, families,
  control = gt_control(discrete = list(engine = "sparse", maxit = 300L, covariance_parameterization = "cholesky", ...))))
reference <- fit_with(gradient = "analytic")
check(isTRUE(reference$numerically_accepted) && identical(reference$diagnostics$boundary_escape, list(route = "none")),
      "the reference fit is accepted and records no escape")
start <- reference$parameters
start[["item::chol[grade,grade]"]] <- 0

stuck <- fit_with(gradient = "analytic", start = start)
primary <- Filter(function(a) startsWith(a$label, "primary"), stuck$diagnostics$attempts)
check(!isTRUE(stuck$numerically_accepted) &&
        identical(stuck$diagnostics$acceptance_failures, "restart_or_tolerance_stability_failed") &&
        all(vapply(primary, function(a) a$parameters[["item::chol[grade,grade]"]] == 0, logical(1))),
      "without the escape both primary attempts stay on the zero column and the fit is refused")

escaped <- fit_with(gradient = "analytic", start = start, boundary_escape = "projected")
labels <- vapply(escaped$diagnostics$attempts, `[[`, character(1), "label")
check(isTRUE(escaped$numerically_accepted) && length(escaped$diagnostics$acceptance_failures) == 0L,
      "with the escape the fit is accepted")
check(identical(labels, c("primary", "primary_tight", "primary_tight_escape_1", "alternative_1", "alternative_1_tight")) &&
        identical(escaped$diagnostics$selected_attempt, "primary_tight_escape_1"),
      "the escaped rerun is an attempt of its own and is selected")
check(abs(escaped$minus2loglik - reference$minus2loglik) < 1e-6 &&
        max(abs(unlist(escaped$covariance_components) - unlist(reference$covariance_components))) < 1e-4,
      "the escaped fit reaches the reference optimum")
record <- escaped$diagnostics$boundary_escape
first <- record$attempts$primary_tight$rounds[[1L]]
check(identical(record$route, "projected") && identical(first$reason, "stepped") && "item" %in% first$singular &&
        first$scores[["item"]] > 1e-3 && isTRUE(first$steps$item$taken) && first$objective_change < 0 &&
        first$evaluations > 0L && identical(record$attempts$primary_tight$final_label, "primary_tight_escape_1"),
      "the record names the singular source, its score, the step and its objective change")
step_record <- escaped$diagnostics$attempts[[3L]]$boundary_escape
check(identical(step_record$reason, "stepped"), "the rerun attempt carries the step that started it")
# The reported allowance covers every retained attempt: a coarse and a tight
# attempt per start, plus three possible reruns per tight attempt with the
# escape on; the staged diagnostics report the same allowance.
staged_budget <- function(fit) unlist(lapply(gt_diagnostics(fit)$stages, function(s) s$measurements$optimization_trial_budget))
check(escaped$diagnostics$optimization_trials == 5L && escaped$diagnostics$optimization_trial_budget == 10L &&
        escaped$diagnostics$optimization_trials <= escaped$diagnostics$optimization_trial_budget &&
        identical(as.integer(staged_budget(escaped)), 10L),
      "the escaped fit's trials lie within its reported budget, also in the staged diagnostics")
check(reference$diagnostics$optimization_trials == 4L && reference$diagnostics$optimization_trial_budget == 4L,
      "a fit without the escape keeps its budget of two attempts per start")
last <- record$attempts$primary_tight$rounds[[length(record$attempts$primary_tight$rounds)]]
check(identical(last$reason, "every singular source is stationary"), "the escape ends when every singular source is stationary")
cat(sprintf("PASS: stuck fixture (score %.3g, alpha %g, objective change %.4f; -2 log L difference %.2e)\n",
            first$scores[["item"]], first$steps$item$alpha, first$objective_change,
            abs(escaped$minus2loglik - reference$minus2loglik)))

# --- fits that need no escape are unchanged ------------------------------------------
for (route in c("analytic", "finite_difference")) {
  plain <- fit_with(gradient = route)
  with_escape <- fit_with(gradient = route, boundary_escape = "projected")
  check(identical(plain$parameters, with_escape$parameters) && identical(plain$minus2loglik, with_escape$minus2loglik) &&
          identical(vapply(plain$diagnostics$attempts, `[[`, character(1), "label"),
                    vapply(with_escape$diagnostics$attempts, `[[`, character(1), "label")) &&
          all(vapply(with_escape$diagnostics$boundary_escape$attempts, function(a)
            identical(a$rounds[[1L]]$reason, "every singular source is stationary"), logical(1))),
        paste("a fit at a legitimate boundary is unchanged by the escape on the", route, "route"))
}
cat("PASS: no-op at a legitimate boundary on both routes\n")

# --- the partial covariance scores equal the full check's ------------------------------
problem <- internal(".gt_d_laplace_problem")(d, c("label", "grade"), design, families,
  control = list(engine = "sparse", covariance_parameterization = "cholesky"))
validation <- problem$control
validation$inner_tol <- min(validation$inner_tol, validation$validation_inner_tol)
validation$reltol <- min(validation$reltol, validation$validation_reltol)
evaluator <- internal(".gt_d_sparse_evaluator")()
at <- reference$parameters
centre <- evaluator(at, problem$prep, problem$groups, problem$setup, validation, details = TRUE)
stationarity <- internal(".gt_d_stationarity")
full <- stationarity(at, problem$prep, problem$groups, problem$setup, validation, centre, laplace = evaluator)
part <- stationarity(at, problem$prep, problem$groups, problem$setup, validation, centre, laplace = evaluator,
                     fixed_effects = FALSE, sources = "rater")
check(identical(part$covariance_projected_scores$rater, full$covariance_projected_scores$rater) &&
        identical(names(part$covariance_projected_scores), "rater") && isFALSE(part$stationary_within_tolerance) &&
        isTRUE(full$stationary_within_tolerance),
      "a partial check returns the full check's scores for its source and is never an acceptance")
cat("PASS: partial covariance scores\n")

# --- refusals ----------------------------------------------------------------------
expect_error(suppressWarnings(gt_fit(d, "label", design, gt_family("binary"),
  control = gt_control(discrete = list(engine = "sparse", boundary_escape = "projected")))),
  "natural Cholesky", "variance coordinates are refused")
expect_error(suppressWarnings(gt_fit(d, c("label", "grade"), design, families,
  control = gt_control(discrete = list(engine = "sparse", covariance_parameterization = "log_cholesky",
                                       boundary_escape = "projected")))),
  "natural Cholesky", "log-Cholesky coordinates are refused")
# Preflight applies the fit's coordinate rule before fitting.
escape_row <- function(pre) pre$checks[pre$checks$check == "boundary_escape_coordinates", , drop = FALSE]
for (case in list(list(outcomes = "label", family = gt_family("binary"), parameterization = "auto", passes = FALSE),
                  list(outcomes = c("label", "grade"), family = families, parameterization = "log_cholesky", passes = FALSE),
                  list(outcomes = c("label", "grade"), family = families, parameterization = "cholesky", passes = TRUE))) {
  pre <- gt_preflight(d, case$outcomes, design, case$family, control = gt_control(discrete = list(engine = "sparse",
    covariance_parameterization = case$parameterization, boundary_escape = "projected")))
  row <- escape_row(pre)
  check(nrow(row) == 1L && identical(row$passed, case$passes) && identical(isTRUE(pre$fitting_feasible), case$passes),
        paste("preflight reports the escape's coordinate rule for", case$parameterization, "coordinates"))
}
plain <- gt_preflight(d, c("label", "grade"), design, families,
  control = gt_control(discrete = list(engine = "sparse", covariance_parameterization = "cholesky")))
check(nrow(escape_row(plain)) == 0L, "preflight without the escape has no escape check")
cat("PASS: refusals and preflight\n")
