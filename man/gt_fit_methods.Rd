\name{gt_fit_methods}
\alias{gt_fit_methods}
\alias{logLik.gt_fit}
\alias{nobs.gt_fit}
\alias{coef.gt_fit}
\alias{vcov.gt_fit}
\title{Standard Extractors for Fitted Generalizability Models}
\description{Log likelihood, observation count, fixed location estimates, and the sampling covariance of the estimated source covariances, following the usual R conventions where they apply and refusing where they do not.}
\usage{
\method{logLik}{gt_fit}(object, ...)
\method{nobs}{gt_fit}(object, ...)
\method{coef}{gt_fit}(object, ...)
\method{vcov}{gt_fit}(object, type = c("components", "parameters"), ...)
}
\arguments{
\item{object}{A fitted \code{gt_fit} object.}
\item{type}{Which covariance matrix to return. \code{"components"} gives the delta-method covariance of the unique source covariance entries, labelled \code{source[row,column]}; \code{"parameters"} gives the free optimizer-parameter covariance.}
\item{...}{Further method arguments; currently unused.}
}
\value{\code{logLik()} returns a \code{logLik} object carrying \code{df}, \code{nobs}, a \code{REML} flag, and a \code{likelihood} label. \code{nobs()} returns the number of measurement rows as an integer. \code{coef()} returns a named numeric vector of fixed location or contrast estimates. \code{vcov()} returns a labelled covariance matrix with \code{scope}, \code{method}, and \code{conditional_on_zero} attributes, or raises an error explaining why none exists.}
\details{\strong{Parameter counts.} Gaussian ML profiles one intercept per outcome. Those intercepts are estimated, so \code{df} counts them alongside the covariance parameters, and \code{AIC()} and \code{BIC()} then reproduce the fit's \code{ml_AIC} and \code{ml_BIC_response_vectors}. Gaussian REML uses a restricted likelihood whose \code{df} counts the covariance parameters only; the returned object sets \code{REML = TRUE} so nothing downstream mistakes it for an ML value, and \code{AIC()} reproduces \code{reml_AIC_variance_parameters}. A restricted-likelihood criterion compares models sharing the same fixed-effects structure. Every fit here has exactly one intercept per outcome, so covariance models remain comparable, but a REML value must never be compared with an ML value.

\strong{Observations.} \code{nobs()} counts measurement rows, which are the response vectors of the likelihood. A joint fit of D outcomes on N rows has N response vectors and not N * D independent observations, because the outcomes within a row share the same random sources. \code{BIC()} therefore uses N. The alternative N * D scalar-score convention and the archive's variance-only conventions remain in the fit object under explicit names; see \code{\link{gt_fit}}.

\strong{Discrete fits.} The log likelihood is a first-order Laplace approximation to the marginal log likelihood, labelled as such in the returned object. Comparing two Laplace-approximated values compares two approximations, not two exact likelihoods.

\strong{What \code{vcov()} is not.} It is not the covariance of \code{coef()}. Gaussian outcome means are profiled out of the likelihood rather than estimated as free parameters, so no curvature for them exists to report. The dense discrete engine computes no observed information for anything, so \code{vcov()} on a discrete fit always raises an error carrying the engine's own reason rather than returning zeros or an invented matrix. A Gaussian fit computed with \code{check_hessian = FALSE}, or one whose Hessian is not positive definite, raises the corresponding recorded reason. Where standard errors condition on a boundary component being held at zero, \code{conditional_on_zero} names those components.

\code{coef()} returns location parameters on their own scale: Gaussian profiled means; binary intercepts; ordinal thresholds, which are that model's location parameters, with the structurally zero dimension mean omitted; and one intercept per non-reference contrast for unordered categorical outcomes. Variance components are not coefficients; use \code{\link{gt_components}}.}
\seealso{\code{\link{gt_fit}}, \code{\link{gt_components}}, \code{\link{gt_diagnostics}}}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(retry_seed = 42)))
logLik(fit)
nobs(fit)
coef(fit)
AIC(fit)   # restricted-likelihood criterion for a REML fit
dimnames(vcov(fit))[[1L]]
}
