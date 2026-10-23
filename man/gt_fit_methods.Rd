\name{gt_fit_methods}
\alias{gt_fit_methods}
\alias{logLik.gt_fit}
\alias{deviance.gt_fit}
\alias{nobs.gt_fit}
\alias{formula.gt_fit}
\alias{update.gt_fit}
\alias{coef.gt_fit}
\alias{vcov.gt_fit}
\alias{gt_component_vcov}
\title{Standard Extractors for Fitted Generalizability Models}
\description{Log likelihood, deviance, observation count, model formula, refitting with \code{update()}, fixed location estimates, and the sampling covariance of the estimated source covariances, following the usual R conventions where they apply and refusing where they do not.}
\usage{
\method{logLik}{gt_fit}(object, ...)
\method{deviance}{gt_fit}(object, ...)
\method{nobs}{gt_fit}(object, ...)
\method{formula}{gt_fit}(x, ...)
\method{update}{gt_fit}(object, formula., ..., evaluate = TRUE)
\method{coef}{gt_fit}(object, ...)
\method{vcov}{gt_fit}(object, ...)
gt_component_vcov(fit, type = c("components", "parameters"), ...)
}
\arguments{
\item{object, x}{A fitted \code{gt_fit} object.}
\item{fit}{A fitted \code{gt_fit} object.}
\item{formula.}{Changes to the model formula in the notation of \code{\link[stats]{update.formula}}, such as \code{. ~ . + item:rater}; omit it to change other arguments only.}
\item{evaluate}{Whether to refit. \code{FALSE} returns the updated call instead.}
\item{type}{Which covariance matrix to return. \code{"components"} gives the delta-method covariance of the unique source covariance entries. Each is labelled by its source and matrix position. \code{"parameters"} gives the free optimizer-parameter covariance instead.}
\item{...}{For \code{update()}, arguments of \code{\link{gt_fit}} to add or replace in the recorded call, for example \code{estimator = "ML"} or \code{measured = "item"}. Otherwise unused.}
}
\value{\code{formula()} returns the model formula: the one the fit was declared with, or for a fit declared through \code{gt_design()} the source formula built from its outcomes and requested sources. Additional declaration metadata, such as facets absent from all sources, is not represented in that formula. \code{update()} returns the refitted \code{gt_fit}, or the call when \code{evaluate = FALSE}. \code{logLik()} returns a \code{logLik} object carrying \code{df}, \code{nobs}, a \code{REML} flag, and a \code{likelihood} label. \code{nobs()} returns the number of measurement rows as an integer. \code{deviance()} returns minus twice the fitted objective as a plain number: the restricted log likelihood under REML, the profile log likelihood under ML, and the first-order Laplace approximation for discrete outcomes. \code{coef()} returns a named numeric vector of fixed location or contrast estimates. \code{gt_component_vcov()} returns a labelled covariance matrix with \code{scope}, \code{method}, and \code{conditional_on_zero} attributes, or raises an error explaining why none exists. \code{vcov()} always raises an error; see below.}
\details{\strong{Parameter counts.} Gaussian ML profiles one intercept per outcome. Those intercepts are estimated, so \code{df} counts them alongside the covariance parameters, and \code{AIC()} and \code{BIC()} then reproduce the fit's \code{ml_AIC} and \code{ml_BIC_response_vectors}. Gaussian REML uses a restricted likelihood whose \code{df} counts the covariance parameters only; the returned object sets \code{REML = TRUE} so nothing downstream mistakes it for an ML value, and \code{AIC()} reproduces \code{reml_AIC_variance_parameters}. \code{BIC()} on a REML fit uses N response vectors with that same parameter count, which the fit records as \code{reml_BIC_response_vectors_variance_parameters}; the N * D scalar-score convention remains \code{reml_BIC_scalar_scores_variance_parameters}. A restricted-likelihood criterion compares models sharing the same fixed-effects structure. Every fit here has exactly one intercept per outcome, so covariance models remain comparable, but a REML value must never be compared with an ML value.

\strong{Observations.} \code{nobs()} counts measurement rows, which are the response vectors of the likelihood. A joint fit of D outcomes on N rows has N response vectors and not N * D independent observations, because the outcomes within a row share the same random sources. \code{BIC()} therefore uses N. The alternative N * D scalar-score convention and the archive's variance-only conventions remain in the fit object under explicit names; see \code{\link{gt_fit}}.

\strong{Rejected fits.} A fit that failed numerical acceptance is refused by \code{logLik()}, and through it by \code{AIC()} and \code{BIC()}, just as \code{\link{gt_reliability}} refuses it. The two apply one rule: a Gaussian fit is refused on an explicit failure, and a discrete fit must carry an affirmative acceptance, so a discrete object whose acceptance flag is missing or \code{NA} is refused rather than read as accepted. Its objective is retained in \code{minus2loglik} for diagnosis, but a likelihood that did not pass the fit's own numerical checks is not a basis for model selection.

\strong{Formula and update.} \code{formula()} gives every fit a formula, so \code{update()} can edit the model of a fit declared either way: the recorded call is re-evaluated in the caller's environment with the formula under \code{formula}, the previous \code{outcomes} and \code{design} removed, and the object of measurement carried along in \code{measured} so that an edited formula cannot change the scientific target by re-ordering. A design that declares replicates, a batch, explicit nesting, or a facet absent from every random source cannot be expressed completely as a formula, so such a fit refuses a formula change and must be refit from a new \code{gt_design()}; arguments other than the formula can still be updated. For these designs, \code{formula()} displays the requested sources only and does not replace the original declaration. Column names containing backticks or backslashes are preserved as names in reconstructed formulas. A fit stored without its data (\code{retain = list(data = FALSE)}) needs \code{data =} supplied to \code{update()}.

\strong{Deviance.} \code{deviance()} returns the objective for every fit, including one that failed numerical acceptance, because the value where the optimizer stopped is what a user reads to see how far a refused fit got. It describes the fit and is not a verdict on it: model selection goes through \code{logLik()}, \code{AIC()} and \code{BIC()}, which refuse such a fit.

\strong{Discrete fits.} The log likelihood is a first-order Laplace approximation to the marginal log likelihood, labelled as such in the returned object. Comparing two Laplace-approximated values compares two approximations, not two exact likelihoods.

\strong{Why \code{vcov()} refuses.} In R, \code{vcov(fit)} is the covariance matrix of \code{coef(fit)}, and generic tooling relies on that pairing. The package does not expose that covariance through this method. Its OpenMx path profiles the Gaussian outcome means and currently computes uncertainty only for source covariances; profiling does not make mean uncertainty mathematically unavailable. The retained lme4 model can provide its own fixed-effect covariance, but that engine-specific extractor has not been integrated into this package method. Optional discrete observed information includes location and covariance parameters in stored parameter coordinates, unaffected by optimizer scaling. In particular, ordinal log-gap coordinates differ from the natural thresholds returned by \code{coef()}, and a matching location-covariance extractor is not implemented. Returning a different matrix under that name would be surprising however carefully it were documented, so \code{vcov()} raises an error naming the reason and pointing at \code{gt_component_vcov()}.

\code{gt_component_vcov()} returns available sampling covariance of the source covariance entries, which \code{\link{gt_reliability}} propagates into coefficient intervals. OpenMx Gaussian fits can provide it under their curvature checks. Discrete fits require explicit \code{check_hessian = TRUE}, numerical acceptance, interior estimated covariance components, stable finite differences and usable positive-definite full information. The default discrete fit and the lme4 Gaussian path provide no such matrix. When unavailable the accessor raises an error carrying the fit's recorded reason, rather than inventing uncertainty. For discrete fits, the \code{approximation} and \code{hessian_scale} attributes identify the first-order Laplace qualification and negative-log-likelihood scale. These do not claim finite-sample coverage.

With \code{type = "parameters"}, Gaussian covariance is \eqn{2H^{-1}} for a Hessian on the minus-twice-log-likelihood scale. Discrete covariance is \eqn{H^{-1}} for the full negative-log-likelihood Hessian, including nuisance intercepts and threshold coordinates. The component matrix is obtained from that full inverse through the covariance-parameter Jacobian; nuisance location parameters are not fixed during extraction. Specified fixed discrete source covariances correctly have zero sampling covariance conditional on those assumptions, and \code{conditional_on_fixed} names them. These zero entries do not represent estimated components with no uncertainty. Gaussian intervals may also condition on boundary components held fixed; \code{conditional_on_zero} names the components fixed at zero by that boundary policy, while a singular but nonzero source remains fixed at its fitted covariance.

\code{coef()} returns location parameters on their own scale: Gaussian profiled means; binary intercepts; ordinal thresholds, which are that model's location parameters, with the structurally zero dimension mean omitted; and one intercept per non-reference contrast for unordered categorical outcomes. Variance components are not coefficients; use \code{\link{gt_components}}.}
\seealso{\code{\link{gt_fit}}, \code{\link{gt_components}}, \code{\link{gt_diagnostics}}}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(retry_seed = 42)))
logLik(fit)
deviance(fit)
nobs(fit)
formula(fit)
# Refit the crossed model from the recorded call; at one observation per
# cell the item:rater source is combined with the residual.
crossed <- update(fit, . ~ . + item:rater)
crossed$design
coef(fit)
AIC(fit)   # restricted-likelihood criterion for a REML fit
# The covariance of the estimated source covariances. vcov() deliberately
# refuses: this package does not estimate the covariance of coef().
dimnames(gt_component_vcov(fit))[[1L]]
}
