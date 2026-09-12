\name{print.summary.gt_fit}
\alias{print.summary.gt_fit}
\title{Print a Concise Generalizability Model Summary}
\description{Displays model scope, numerical acceptance, likelihood, source variances, and fixed estimates without printing the fitted backend model or observation data.}
\usage{
\method{print}{summary.gt_fit}(x, ..., digits = max(3L,
  getOption("digits") - 3L))
}
\arguments{
\item{x}{A \code{summary.gt_fit} object returned by \code{summary(fit)}.}
\item{...}{Additional arguments; currently unused.}
\item{digits}{Number of significant digits for printed estimates, from 1 to 22.}
}
\value{Returns \code{x} invisibly. The summary object remains a list with outcome and family specifications, source covariance matrices, a source-variance table, means or coefficients, thresholds, likelihood, and diagnostics.}
\details{The printed summary reports the selected attempt, recorded failed attempts,
acceptance failures, natural covariance boundaries, artificial parameter bounds,
and likelihood-approximation status separately. If the native Gaussian transcript
does not identify a unique selected trial, the output says \dQuote{not identified}.
An accepted fit can have earlier failed attempts or a natural covariance boundary.
A rejected fit's estimates are printed for diagnosis only; it remains ineligible
for reliability or decision-study calculations.

The printed variance table shows at most 20 rows and the attempt-failure table at
most 6 rows. Complete tables and covariance matrices remain in the summary.

Use \code{gt_diagnostics(fit)} for full diagnostic details.

Fixed location or contrast estimates are printed on the fitted family's scale.
Numerical acceptance and first-order
Laplace approximation adequacy remain separate; the summary makes no additional
claim of statistical validation.}
\seealso{\code{\link{gt_fit}}, \code{\link{gt_diagnostics}}, \code{\link{gt_components}}}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
s <- summary(fit)
print(s, digits = 3)
s$variances
}
