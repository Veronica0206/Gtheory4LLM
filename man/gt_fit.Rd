\name{gt_fit}
\alias{gt_fit}
\alias{print.gt_fit}
\alias{summary.gt_fit}
\title{Fit Univariate or Joint Multivariate Generalizability Models}
\description{Fits selected random-source covariance models using an exact balanced Gaussian likelihood or a dense first-order Laplace likelihood for discrete outcomes.}
\usage{
gt_fit(data, outcomes, design, family = gt_family("gaussian"),
  estimator = NULL, covariance = "unstructured", residual = NULL,
  control = gt_control())
\method{print}{gt_fit}(x, ...)
\method{summary}{gt_fit}(object, ...)
}
\arguments{
\item{data}{Data frame containing the object, all declared instrumentation columns, and outcomes. Missing values are not silently dropped.}
\item{outcomes}{One or more unique outcome column names.}
\item{design}{A declaration created by \code{gt_design()}.}
\item{family}{One \code{gt_family} object for all outcomes, or a named list matching outcomes exactly. Multiple discrete families can be modeled jointly. Joint Gaussian-discrete likelihoods are not implemented.}
\item{estimator}{Gaussian: \code{"REML"} (default) or \code{"ML"}. Discrete: \code{"ML_Laplace"}.}
\item{covariance}{\code{"unstructured"} or \code{"diagonal"}; Gaussian also accepts named source overrides, with unspecified sources using diagonal covariance. Discrete source covariance uses the common requested structure.}
\item{residual}{The Gaussian residual structure. Choose \code{"unstructured"}, \code{"diagonal"}, or \code{"pooled"}; pooled gives equal outcome variances. Omit for discrete outcomes.}
\item{control}{A \code{gt_control} object.}
\item{x, object}{A fitted \code{gt_fit} object for the print or summary method.}
\item{...}{Further method arguments; currently unused.}
}
\value{A \code{gt_fit} object containing source covariance matrices, estimates, likelihood and parameter counts, the resolved design and observation families, modeled data, and numerical diagnostics. Gaussian objects also retain the OpenMx model, prepared sufficient statistics, an \code{uncertainty} record holding the parameter covariance matrix and its delta-method mapping to source covariance entries, and a \code{component_standard_errors} table. Discrete objects include thresholds or category contrasts and conditional probabilities evaluated at the random-effect mode. \code{print()} returns the fit invisibly. \code{summary()} returns a \code{summary.gt_fit} list with estimates, a source-variance table carrying standard errors and a boundary flag where they are available, full covariance components, and diagnostics. Its \link[=print.summary.gt_fit]{print method} displays a concise report of numerical acceptance, selected attempts, boundaries, and estimates.}
\details{The Gaussian backend requires a complete coded Cartesian panel with one observation per cell and at most 4096 factorial strata. Implicit normalized Helmert contrasts avoid quadratic allocation along a large object axis. Gaussian ML profiles one fixed intercept per outcome; REML includes the unscaled-intercept constant D * log(N). Gaussian ML AIC counts covariance parameters and profiled means. Its generic BIC uses N response vectors; \code{ml_BIC_scalar_scores} explicitly provides the alternative N * D convention. \code{legacy_AIC} and \code{legacy_BIC} preserve the archive's variance-only parameter convention. Generic Gaussian REML AIC/BIC are unavailable; explicitly named restricted-likelihood criteria are retained.

Discrete models use binary links, ordinal thresholds, or unordered reference-category softmax contrasts. They do not estimate a free Gaussian observation residual. Probit latent residual variance is identified as 1; logit as pi^2 / 3. Unsupported observation-level sources, aliased free source kernels, missing categories, and resource-limit violations are rejected.

Returned binary probabilities evaluate each tail directly, preserving small
representable probabilities and the declared category order. These are
conditional probabilities at the random-effect mode, not population-marginal
probabilities.

Gaussian fitting also computes asymptotic Wald standard errors for the source variance components from the numerically differentiated restricted- or profile-likelihood Hessian. These are large-sample quantities conditional on the declared model; they do not establish coverage in small designs and do not apply to a component resting on a variance boundary. \code{check_hessian = FALSE} disables them along with the other derivative diagnostics.

Numerical acceptance includes optimizer completion and independent stationarity, bound, and tighter-tolerance restart checks. First-order stationarity does not establish a global optimum. A numerically accepted Laplace fit still requires an assessment of approximation adequacy for the intended analysis. Reliability and decision studies reject fits that fail numerical acceptance.}
\seealso{\code{\link{gt_design}}, \code{\link{gt_control}}, \code{\link{gt_diagnostics}}. A worked first discrete fit is installed as \code{system.file(\"examples\", \"discrete-first.R\", package = \"Gtheory4LLM\")}.}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
print(fit)
summary(fit)$minus2loglik
# A discrete outcome at one observation per cell: declare the design without
# the object-by-all-facets source, which no discrete fit there can identify.
b <- expand.grid(rater = 1:4, item = 1:10)
b$label <- as.integer((b$item + 2 * b$rater) \%\% 5 > 1)
binary_fit <- gt_fit(b, "label", gt_design("item", "rater", full_cell = FALSE),
  gt_family("binary"))
gt_diagnostics(binary_fit)$numerically_accepted
}
