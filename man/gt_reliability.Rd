\name{gt_reliability}
\alias{gt_reliability}
\alias{print.gt_reliability}
\title{Compute Balanced G and Phi Coefficients}
\description{Forms universe-score, relative-error, and absolute-error covariance matrices under a declared balanced averaging design.}
\usage{
gt_reliability(fit, scale = NULL, score = NULL, design = NULL, counts = NULL,
  fixed = character(), level = 0.95)
\method{print}{gt_reliability}(x, ..., digits = 4L, max_rows = 12L)
}
\arguments{
\item{fit}{A numerically accepted \code{gt_fit} with a complete balanced coded panel.}
\item{scale}{\code{"observed"} for Gaussian outcomes (default); explicitly request \code{"latent"} for binary/ordinal outcomes.}
\item{score}{Optional \code{gt_score} weights. Per-outcome results are always returned.}
\item{counts}{Optional named positive integer instrumentation counts overriding the fitted allocation. Unspecified counts retain their fitted values.}
\item{design}{Compatibility alias for \code{counts}. Supply only one of these arguments.}
\item{fixed}{Instrumentation facets whose universe of generalization is exactly their observed levels. Defaults to none, which is the fully random model. A fixed facet's count cannot be changed, and at least one facet must remain random.}
\item{level}{Confidence level for the reported coefficient intervals.}
\item{x}{A \code{gt_reliability} object.}
\item{digits}{Significant digits used when printing.}
\item{max_rows}{Maximum number of outcome rows to print.}
\item{...}{Reserved for additional print arguments.}
}
\value{A \code{gt_reliability} list containing per-outcome \code{Erho2} and \code{Phi} with their standard errors and interval bounds, optional composite coefficients, universe/relative-error/absolute-error covariance matrices, the role each source played in the decomposition, coefficient scale, allocation, fixed facets, extrapolation flag, the uncertainty record, and fit diagnostics. Standard errors and bounds are \code{NA} whenever the fit carries no usable parameter covariance matrix. Printing shows a concise coefficient table, omits all-missing interval columns, and returns the complete object invisibly.}
\details{The object main-effect covariance defines universe-score variation. Every object-containing error component contributes to relative error, and every non-object-main component contributes to absolute error. Each component is divided by the product of the instrumentation counts in its grouping term; the residual is also divided by declared cell replication.

Declaring a facet \code{fixed} selects the mixed model of Brennan (2001). The universe of generalization then contains exactly that facet's observed levels: its object interaction is averaged over those levels and added to universe-score variance, a source built only from fixed facets shifts every object equally and leaves the model, and every remaining source keeps its usual divisor. With no fixed facet this reduces exactly to the fully random decomposition. \code{$source_roles} records which role each source took.

Intervals use the delta method on the logit scale, propagating the fitted parameter covariance matrix through the source covariance entries. They are asymptotic Wald intervals conditional on the declared model and allocation; they carry no sampling uncertainty for the facet populations themselves, and Wald theory does not apply to a source resting on a variance boundary. The discrete engine supplies no parameter covariance matrix, so its coefficients remain point estimates.

Coefficients for discrete outcomes are identified latent-response coefficients. They describe the average latent response under the declared measurement design, not binary proportions, majority-vote labels, or observed ordinal scores. Scalar reliability for unordered categories, observed discrete reliability, and unbalanced decision-study integration are not implemented. Instrumentation facets are averaged as random sources unless \code{fixed} names them; the function never infers a fixed-facet score universe on its own.}
\references{Brennan, R. L. (2001). \emph{Generalizability Theory}. Springer. \doi{10.1007/978-1-4757-3456-0}}
\seealso{\code{\link{gt_score}}, \code{\link{gt_dstudy}}}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
gt_reliability(fit)$per_trait
gt_reliability(fit, counts = c(rater = 6))
}
