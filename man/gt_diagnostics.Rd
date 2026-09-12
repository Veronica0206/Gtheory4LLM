\name{gt_diagnostics}
\alias{gt_diagnostics}
\title{Inspect Numerical Acceptance and Backend Diagnostics}
\description{Reports optimizer completion separately from numerical acceptance and likelihood-approximation adequacy.}
\usage{
gt_diagnostics(fit)
}
\arguments{
\item{fit}{A \code{gt_fit} object.}
}
\value{A list with estimator, engine, optimizer and numerical acceptance status,
approximation status, engine-specific diagnostics, resolved aliases, and
data-validation notes. Shared diagnostic fields include:
\itemize{
\item \code{optimizer}: the selected optimization engine.
\item \code{optimization_trials}: the recorded trial count.
\item \code{selected_attempt}: the returned candidate's identifier.
\item \code{acceptance_failures}: reasons for rejecting the returned fit.
\item \code{attempt_failures}: recorded trial errors or rejections.
\item \code{boundary_sources}: zero or nearly singular covariance sources.
\item \code{parameter_bounds}: artificial parameter-bound contacts.
}}
\details{Gaussian diagnostics include independent likelihood reconstruction, covariance-scale stationarity, boundary components, and optional Hessian diagnostics. Discrete diagnostics include covariance- and parameter-scale stationarity, bound locations, and tighter-tolerance alternative-start stability. Passing these checks does not prove structural identification, a global optimum, or adequate approximation in sparse or strongly dependent data.

\code{selected_attempt} identifies the returned candidate using the engine's
recorded trial identifier. It is \code{NA} when the Gaussian native transcript
does not uniquely identify that trial. \code{acceptance_failures} gives reasons
for rejecting the returned fit; \code{attempt_failures} is a two-column data
frame of recorded attempt identifiers and error or rejection reasons, including
earlier attempts. An empty attempt-failure table does not certify every trial:
some native candidates have no independent acceptance assessment.

\code{boundary_sources} describes natural zero or nearly singular covariance
components and does not by itself imply rejection. \code{parameter_bounds}
lists artificial discrete-parameter bound contacts, which do prevent numerical
acceptance. These shared fields summarize existing engine decisions without
repeating or changing numerical checks. \code{summary(fit)} prints a concise
version while retaining full diagnostics for programmatic inspection.}
\seealso{\code{\link{gt_control}}, \code{\link{gt_fit}}}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
gt_diagnostics(fit)$numerically_accepted
}
