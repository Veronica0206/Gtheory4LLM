# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Standard R extractors for fitted G-theory models.
#
# These exist so that a fit behaves like other R model objects where that is
# honest, and refuses where it is not. The refusals are the point: the Gaussian
# outcome means are profiled rather than freely estimated, and the discrete
# engine computes no observed information at all, so neither has a sampling
# covariance matrix to hand back. Inventing one would be worse than an error.

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
  attr(value, "conditional_on_zero") <- record$fixed_components
  value
}

# The covariance of coef(), which this implementation does not estimate.
#
# Gaussian outcome means are profiled out of the likelihood rather than fitted
# as free parameters, so there is no curvature for them to report; the discrete
# engine computes no observed information for anything. Rather than return a
# different matrix under a name that promises this one, this says so and points
# at the function that does have a covariance matrix to give. Defining the
# method at all is deliberate: without it, vcov() would reach vcov.default and
# fail with a message about a missing summary component instead.
vcov.gt_fit <- function(object, ...) {
  .gt_require_fit(object)
  detail <- if (.gt_is_gaussian(object))
    paste("Gaussian outcome means are profiled out of the likelihood rather than",
          "estimated as free parameters, so this engine computes no curvature for them.") else
    paste("The dense first-order Laplace engine computes no observed information,",
          "so its location parameters are point estimates only.")
  stop("The sampling covariance of coef() is not available for a gt_fit: ", detail,
       " For the covariance of the estimated source covariances, which is what",
       " gt_reliability() propagates, use gt_component_vcov(fit).", call. = FALSE)
}

print.gt_diagnostics <- function(x, ...) {
  cat("G-theory fit diagnostics |", if (length(x$engine)) x$engine else "engine not recorded", "\n")
  cat("Estimator:", x$estimator, "\n")
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
