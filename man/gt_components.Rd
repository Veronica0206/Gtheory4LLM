\name{gt_components}
\alias{gt_components}
\title{Extract Source Covariances or Correlations}
\description{Returns source-specific matrices on their modeled scale without transforming latent variances into observed-score variances.}
\usage{
gt_components(fit, correlation = FALSE, tolerance = 1e-8)
}
\arguments{
\item{fit}{A \code{gt_fit} object.}
\item{correlation}{Whether to return correlation matrices instead of covariances.}
\item{tolerance}{Nonnegative relative variance threshold for reporting correlations. Entries involving a variance at or below this threshold times the reference variance scale are NA.}
}
\value{A named list of matrices, with scale and interpretation attributes. Correlation extraction adds the threshold and boundary policy.}
\details{Gaussian correlation checks use observed outcome variances as the reference scales. When those are unavailable, the largest variance within each source matrix is the reference. Covariances for discrete outcomes refer to identified latent predictors or category contrasts. Correlations involving negligible source variances are suppressed rather than presented as stable estimates.}
\seealso{\code{\link{gt_fit}}, \code{\link{gt_diagnostics}}}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
gt_components(fit)
}
