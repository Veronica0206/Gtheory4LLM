# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Standard R extractors for fitted G-theory models.
#
# These exist so that a fit behaves like other R model objects where that is
# honest, and refuses where the package has no implemented extractor. Gaussian
# source-covariance uncertainty is distinct from uncertainty in outcome means;
# the discrete engine computes no observed information for either.

.gt_require_fit <- function(object) {
  if (!inherits(object, "gt_fit")) stop("Expected a gt_fit object.", call. = FALSE)
  invisible(object)
}

.gt_is_gaussian <- function(object)
  all(vapply(object$families, `[[`, character(1), "family") == "gaussian")

# Number of measurement rows, which are the response vectors of the likelihood.
#
# A joint fit of D outcomes on N rows has N response vectors, not N * D
# independent observations: the outcomes in one row share the same random
# sources. BIC therefore uses N here. The N * D scalar-score convention is
# retained separately in the fit object under an explicit name.
nobs.gt_fit <- function(object, ...) {
  .gt_require_fit(object)
  as.integer(object$N)
}

# The model formula of any fit. A fit declared by formula returns that formula;
# a fit declared with gt_design() returns the equivalent one, built from its
# outcomes and requested sources, so update() has a model to edit either way.
.gt_formula_name <- function(x) ifelse(make.names(x) == x, x, paste0("`", x, "`"))

formula.gt_fit <- function(x, ...) {
  .gt_require_fit(x)
  text <- x$design$formula
  if (is.null(text)) {
    outcomes <- .gt_formula_name(x$outcomes)
    lhs <- if (length(outcomes) == 1L) outcomes else paste0("cbind(", paste(outcomes, collapse = ", "), ")")
    terms <- vapply(strsplit(x$design$terms_requested, ":", fixed = TRUE), function(parts)
      paste(.gt_formula_name(parts), collapse = ":"), character(1))
    text <- paste(lhs, "~", paste(terms, collapse = " + "))
  }
  stats::as.formula(text, env = globalenv())
}

# Refit with an edited model or edited arguments, as update() does for other
# model objects. The recorded call already names every argument, so a new
# formula replaces the outcomes and design it was fitted with, and the object
# of measurement is carried along explicitly so that re-ordering the formula
# cannot change the scientific target of the refit.
update.gt_fit <- function(object, formula., ..., evaluate = TRUE) {
  .gt_require_fit(object)
  call <- object$call
  if (!is.call(call)) stop("This fit does not record the call that produced it.", call. = FALSE)
  extras <- match.call(expand.dots = FALSE)$...
  if (identical(call[["data"]], as.name("<dropped>")) && is.null(extras[["data"]]))
    stop("This fit was stored without its data (retain = list(data = FALSE)); supply data = to update().",
         call. = FALSE)
  if (!missing(formula.)) {
    if (!is.null(object$design$batch) || !identical(as.integer(object$design$replicates), 1L))
      stop("A formula cannot carry a batch declaration or replicates; declare the new model with gt_design() and refit.",
           call. = FALSE)
    call[["formula"]] <- stats::update.formula(formula(object), formula.)
    # Removing an absent element from a call is an error, unlike for a list.
    for (name in intersect(c("outcomes", "design"), names(call))) call[[name]] <- NULL
    if (is.null(call[["measured"]])) call[["measured"]] <- object$design$object
  }
  if (length(extras)) {
    existing <- names(extras) %in% names(call)
    for (name in names(extras)[existing]) call[[name]] <- extras[[name]]
    if (any(!existing)) call <- as.call(c(as.list(call), extras[!existing]))
  }
  if (evaluate) eval(call, parent.frame()) else call
}

# Minus twice the fitted objective: the restricted log likelihood under REML,
# the profile log likelihood under ML, and the first-order Laplace
# approximation for discrete outcomes.
#
# Unlike logLik(), this is returned for a fit that failed numerical
# acceptance. The objective where the optimizer stopped is what a user reads
# to see how far a refused fit got, and reporting it is not a verdict:
# model selection goes through logLik(), which refuses such a fit.
deviance.gt_fit <- function(object, ...) {
  .gt_require_fit(object)
  value <- object$minus2loglik
  if (!is.numeric(value) || length(value) != 1L || !is.finite(value))
    stop("This fit does not record a finite objective value.", call. = FALSE)
  as.numeric(value)
}

# Log likelihood with the parameter count each estimator actually fitted.
#
# Gaussian ML profiles one intercept per outcome; those are estimated, so they
# are counted. Gaussian REML is a restricted likelihood: it is not the full-data
# likelihood, and criteria built from it compare covariance models that share
# the same fixed-effects structure. Every fit in this package has exactly one
# intercept per outcome, so that comparison is available, and the returned
# object carries REML = TRUE so nothing downstream mistakes it for an ML value.
# The discrete value is a first-order Laplace approximation to the marginal log
# likelihood, and says so.
logLik.gt_fit <- function(object, ...) {
  .gt_require_fit(object)
  # A fit that failed numerical acceptance keeps its objective for diagnosis in
  # minus2loglik, but a likelihood that did not pass its own checks is not a
  # basis for model selection. The generics refuse it by the same rule
  # gt_reliability() applies, .gt_fit_usable(), so a discrete fit needs an
  # affirmative acceptance here too, rather than letting AIC() and BIC() read
  # as ordinary values on missing evidence.
  if (!.gt_fit_usable(object))
    stop("Model-selection generics require a numerically accepted fit; this fit's likelihood is ",
         "diagnostic only. Inspect gt_diagnostics(fit). The retained objective is fit$minus2loglik.",
         call. = FALSE)
  gaussian <- .gt_is_gaussian(object)
  reml <- gaussian && identical(object$estimator, "REML")
  df <- if (!gaussian) object$npar else
    if (reml) object$n_variance_parameters else object$n_model_parameters
  if (!is.numeric(df) || length(df) != 1L || !is.finite(df))
    stop("This fit does not record a usable parameter count.", call. = FALSE)
  value <- -object$minus2loglik / 2
  structure(value, class = "logLik", df = as.integer(df), nobs = nobs.gt_fit(object),
            REML = reml,
            likelihood = if (!gaussian) "first_order_laplace_marginal" else
              if (reml) "restricted" else "profile_ml")
}

# Fixed location and contrast estimates on their own scale.
#
# Gaussian: one profiled mean per outcome. Binary: one intercept per outcome.
# Ordinal: the ordered thresholds, which are the location parameters of that
# model; its dimension mean is structurally zero and is not reported as an
# estimate. Unordered categorical: one intercept per non-reference contrast.
# These are never variance components; use gt_components() for those.
coef.gt_fit <- function(object, ...) {
  .gt_require_fit(object)
  if (.gt_is_gaussian(object)) return(object$means)
  ordinal <- vapply(object$families, function(f) identical(f$family, "ordinal"), logical(1))
  mapping <- object$link_dimensions
  drop <- if (is.data.frame(mapping) && any(ordinal))
    mapping$dimension[mapping$outcome %in% object$outcomes[ordinal]] else character()
  location <- object$means[setdiff(names(object$means), drop)]
  thresholds <- object$thresholds
  if (!length(thresholds)) return(location)
  named <- unlist(lapply(names(thresholds), function(outcome)
    stats::setNames(thresholds[[outcome]],
                    paste0(outcome, "::", names(thresholds[[outcome]])))),
    use.names = TRUE)
  c(location, named)
}

# Sampling covariance of the estimated source covariances.
#
# This is deliberately a package-specific function rather than vcov(). R's
# convention is that vcov(fit) is the covariance of coef(fit), and generic
# tooling relies on that pairing; returning something else under that name
# would be surprising however carefully it were documented.
#
# type = "components" gives the delta-method covariance of the unique source
# covariance entries, labelled source[row,column]; this is what a coefficient
# interval is built from. type = "parameters" gives the underlying free
# optimizer-parameter covariance, 2 H^-1 on the -2 log likelihood scale.
gt_component_vcov <- function(fit, type = c("components", "parameters"), ...) {
  .gt_require_fit(fit)
  type <- match.arg(type)
  record <- fit$uncertainty
  if (!is.list(record) || !isTRUE(record$available)) {
    reason <- if (is.list(record) && length(record$reason) && !is.na(record$reason))
      record$reason else "This fit carries no parameter covariance matrix."
    stop("No source-covariance uncertainty is available for this fit: ", reason,
         " Use gt_components(fit) for the point estimates.", call. = FALSE)
  }
  value <- if (type == "components") record$entry_covariance else record$parameter_covariance
  if (!is.matrix(value))
    stop("This fit does not carry a ", type, " covariance matrix.", call. = FALSE)
  attr(value, "scope") <- if (type == "components")
    "Unique source covariance entries." else "Free optimizer parameters."
  attr(value, "method") <- record$method
  # Every fixed component is named; the zero subset is named separately so the
  # older attribute keeps meaning exactly what it says.
  kinds <- record$fixed_component_kinds
  attr(value, "conditional_on_fixed") <- record$fixed_components
  attr(value, "conditional_on_zero") <- record$fixed_components[
    unname(kinds[record$fixed_components]) %in% "zero"]
  value
}

# The covariance of coef(), which this implementation does not estimate.
#
# Profiling Gaussian means does not prevent their uncertainty from being
# estimated, but this package does not implement that extractor, including for
# the lme4 engine. The discrete engine computes no observed information. Rather than return a
# different matrix under a name that promises this one, this says so and points
# at the function that does have a covariance matrix to give. Defining the
# method at all is deliberate: without it, vcov() would reach vcov.default and
# fail with a message about a missing summary component instead.
vcov.gt_fit <- function(object, ...) {
  .gt_require_fit(object)
  detail <- if (.gt_is_gaussian(object) && identical(object$engine, "lme4_gaussian_mixed_model"))
    "The lme4 model's fixed-effect covariance is not exposed by this package's vcov() method." else
    if (.gt_is_gaussian(object))
    paste("This package computes source-covariance uncertainty where available,",
          "but has no implemented covariance extractor for the profiled outcome means.") else
    paste("The dense first-order Laplace engine computes no observed information,",
          "so its location parameters are point estimates only.")
  stop("The sampling covariance of coef() is not available for a gt_fit: ", detail,
       " For the covariance of the estimated source covariances, which is what",
       " gt_reliability() propagates, use gt_component_vcov(fit).", call. = FALSE)
}

print.gt_diagnostics <- function(x, ...) {
  cat("G-theory fit diagnostics |", if (length(x$engine)) x$engine else "engine not recorded", "\n")
  cat("Estimator:", x$estimator, "| approximation:",
      if (length(x$approximation)) x$approximation else "not recorded", "\n")
  .gt_print_fit_status(x)
  # The staged summary is the reason a reader does not have to reconstruct the
  # numerical pathway from private records, so printing has to show it.
  if (inherits(x$stages, "gt_diagnostic_stages")) {
    cat("\nNumerical stages:\n")
    print(x$stages)
  }
  if (length(x$declared_aliases))
    cat("Declared aliases:", paste(x$declared_aliases, collapse = ", "), "\n")
  if (length(x$data_validation) && !is.na(x$data_validation))
    cat("Data validation:", x$data_validation, "\n")
  # The shared status printer above already names the reason when one was
  # recorded, so this line is for a record that carries none.
  reason <- x$standard_errors_unavailable_reason
  if (isFALSE(x$standard_errors_available) && !(length(reason) && !is.na(reason[[1L]])))
    cat("Standard errors: unavailable.\n")
  else if (isTRUE(x$standard_errors_available))
    cat("Standard errors: available for source variance components.\n")
  cat("Engine records remain in the returned list; printing never re-runs a check.\n")
  invisible(x)
}
