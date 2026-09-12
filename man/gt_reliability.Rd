\name{gt_reliability}
\alias{gt_reliability}
\title{Compute Balanced G and Phi Coefficients}
\description{Forms universe-score, relative-error, and absolute-error covariance matrices under a declared balanced averaging design.}
\usage{
gt_reliability(fit, scale = NULL, score = NULL, design = NULL)
}
\arguments{
\item{fit}{A numerically accepted \code{gt_fit} with a complete balanced coded panel.}
\item{scale}{\code{"observed"} for Gaussian outcomes (default); explicitly request \code{"latent"} for binary/ordinal outcomes.}
\item{score}{Optional \code{gt_score} weights. Per-outcome results are always returned.}
\item{design}{Optional named positive integer instrumentation counts overriding the fitted allocation. Unspecified counts retain their fitted values.}
}
\value{A list containing per-outcome \code{Erho2} and \code{Phi}, optional composite coefficients, universe/relative-error/absolute-error covariance matrices, coefficient scale, allocation, extrapolation flag, and fit diagnostics.}
\details{The object main-effect covariance defines universe-score variation. Every object-containing error component contributes to relative error, and every non-object-main component contributes to absolute error. Each component is divided by the product of the instrumentation counts in its grouping term; the residual is also divided by declared cell replication.

Coefficients for discrete outcomes are identified latent-response coefficients. They describe the average latent response under the declared measurement design, not binary proportions, majority-vote labels, or observed ordinal scores. Scalar reliability for unordered categories, observed discrete reliability, and unbalanced decision-study integration are not implemented. Instrumentation facets are averaged as random sources; the function does not infer an arbitrary fixed-facet score universe.}
\seealso{\code{\link{gt_score}}, \code{\link{gt_dstudy}}}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
gt_reliability(fit)$per_trait
gt_reliability(fit, design = c(rater = 6))$per_trait
}
