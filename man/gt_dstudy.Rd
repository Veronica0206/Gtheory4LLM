\name{gt_dstudy}
\alias{gt_dstudy}
\alias{plot.gt_dstudy}
\title{Evaluate Balanced Measurement Allocations}
\description{Computes supported G and Phi coefficients over a grid of instrumentation counts, validating the fitted context once.}
\usage{
gt_dstudy(fit, grid, scale = NULL, score = NULL)
\method{plot}{gt_dstudy}(x, coefficient = "Erho2", ...)
}
\arguments{
\item{fit}{A numerically accepted \code{gt_fit} with a complete balanced coded panel.}
\item{grid}{A nonempty data frame of positive integer facet counts. Columns name declared facets; omitted facets retain their fitted counts.}
\item{scale}{\code{"observed"} for Gaussian outcomes or explicitly \code{"latent"} for binary/ordinal outcomes.}
\item{score}{Optional composite weights created by \code{gt_score()}.}
\item{x}{A \code{gt_dstudy} object for plotting.}
\item{coefficient}{Plot \code{"Erho2"} (default) or \code{"Phi"}.}
\item{...}{Additional arguments passed to \code{graphics::plot()}.}
}
\value{A \code{gt_dstudy} list with completed allocation rows, coefficient results, measurements per object, scale, extrapolation flags, and fitting diagnostics. The plot method returns the object invisibly.}
\details{These are conditional design projections using fitted source covariances. They do not refit the model, represent sampling uncertainty, or establish that larger allocations preserve the same source distributions. Restrictions and coefficient definitions are those of gt_reliability().}
\seealso{\code{\link{gt_reliability}}, \code{\link{gt_score}}}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
study <- gt_dstudy(fit, data.frame(rater = c(2, 3, 6)))
study$results
plot(study)
}
