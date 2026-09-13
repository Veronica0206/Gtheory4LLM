\name{gt_dstudy}
\alias{gt_dstudy}
\alias{plot.gt_dstudy}
\alias{print.gt_dstudy}
\title{Evaluate Balanced Measurement Allocations}
\description{Computes supported G and Phi coefficients over a grid of instrumentation counts, validating the fitted context once.}
\usage{
gt_dstudy(fit, grid, scale = NULL, score = NULL, fixed = character(),
  level = 0.95)
\method{print}{gt_dstudy}(x, ..., digits = 4L, max_rows = 12L)
\method{plot}{gt_dstudy}(x, coefficient = "Erho2", interval = TRUE, ...)
}
\arguments{
\item{fit}{A numerically accepted \code{gt_fit} with a complete balanced coded panel.}
\item{grid}{A nonempty data frame of positive integer facet counts. Columns name declared facets; omitted facets retain their fitted counts.}
\item{scale}{\code{"observed"} for Gaussian outcomes or explicitly \code{"latent"} for binary/ordinal outcomes.}
\item{score}{Optional composite weights created by \code{gt_score()}.}
\item{fixed}{Instrumentation facets treated as fixed, as in \code{gt_reliability()}. A fixed facet may not appear in \code{grid}: its universe is exactly its observed levels.}
\item{level}{Confidence level for the reported coefficient intervals.}
\item{x}{A \code{gt_dstudy} object.}
\item{coefficient}{Plot \code{"Erho2"} (default) or \code{"Phi"}.}
\item{interval}{Draw the interval bounds as vertical segments when the fit supplies them.}
\item{digits}{Significant digits used when printing.}
\item{max_rows}{Maximum number of coefficient rows to print.}
\item{...}{Additional arguments passed to \code{graphics::plot()}, or reserved for printing.}
}
\value{A \code{gt_dstudy} list with completed allocation rows, coefficient results including standard errors and interval bounds, measurements per object, scale, fixed facets, the uncertainty record, extrapolation flags, and fitting diagnostics. The print method shows allocations and coefficients without expanding fitting diagnostics. Both methods return the object invisibly.}
\details{These are conditional design projections using fitted source covariances. They do not refit the model or establish that larger allocations preserve the same source distributions. Reported intervals propagate estimation uncertainty in the fitted source covariances under the declared random-effects sampling model. They are not prediction intervals for the realized scores of a newly drawn panel, and they do not quantify failure of exchangeability when extending to new facet levels. Boundary and conditional-inference caveats are retained from the fitted model. Intervals are unavailable for discrete fits. Restrictions and coefficient definitions are those of gt_reliability().}
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
