\name{gt_diagnostics}
\alias{gt_diagnostics}
\alias{print.gt_diagnostics}
\alias{print.gt_diagnostic_stages}
\alias{print.gt_diagnostic_stage}
\title{Inspect Numerical Acceptance and Backend Diagnostics}
\description{Reports optimizer completion separately from numerical acceptance and likelihood-approximation adequacy.}
\usage{
gt_diagnostics(fit)
\method{print}{gt_diagnostics}(x, ...)
\method{print}{gt_diagnostic_stages}(x, ...)
\method{print}{gt_diagnostic_stage}(x, ...)
}
\arguments{
\item{fit}{A \code{gt_fit} object.}
\item{x}{A \code{gt_diagnostics}, \code{gt_diagnostic_stages} or \code{gt_diagnostic_stage} object.}
\item{...}{Reserved for additional print arguments.}
}
\value{A \code{gt_diagnostics} list with estimator, engine, optimizer and numerical acceptance status,
approximation status, engine-specific diagnostics, a staged summary, resolved aliases, and
data-validation notes.

The \code{stages} element summarises the numerical checks a fit passed through, so that a rejection names the stage responsible without the caller reading private optimizer records. Each stage reports \code{status}, a \code{reason} and supporting \code{measurements}. The status is one of \code{"passed"}, \code{"failed"}, \code{"not_assessed"} for a check that did not run or does not apply to this engine, or \code{"inconclusive"} for one that ran and neither clearly passed nor clearly failed. Absent evidence is reported as \code{"not_assessed"} and never as a pass. The summary is derived from evidence the fit already retained: it never refits, and it never changes an acceptance decision. In particular, optimizer completion reports what the optimizer reported; a retained attempt that never moved from its starting values is exposed through \code{max_abs_parameter_change} rather than by redefining completion. Shared diagnostic fields include:
\itemize{
\item \code{optimizer}: the selected optimization engine.
\item \code{optimization_trials}: the recorded trial count.
\item \code{selected_attempt}: the returned candidate's identifier.
\item \code{acceptance_failures}: reasons for rejecting the returned fit.
\item \code{attempt_failures}: recorded trial errors or rejections.
\item \code{boundary_sources}: zero or nearly singular covariance sources.
\item \code{parameter_bounds}: artificial parameter-bound contacts.
\item \code{standard_errors_available}: whether a usable parameter covariance matrix was obtained.
\item \code{standard_errors_unavailable_reason}: why it was not, when it was not.
\item \code{component_standard_errors}: per-source variance standard errors with a boundary flag.
}}
\details{Gaussian diagnostics include independent likelihood reconstruction, covariance-scale stationarity, boundary components, and optional Hessian diagnostics. Discrete diagnostics include covariance- and parameter-scale stationarity, bound locations, and tighter-tolerance alternative-start stability. Passing these checks does not prove structural identification, a global optimum, or adequate approximation in sparse or strongly dependent data.

\code{selected_attempt} identifies the returned candidate using the engine's
recorded trial identifier. It is \code{NA} when no trial is recorded as
having produced the returned fit. \code{acceptance_failures} gives reasons
for rejecting the returned fit; \code{attempt_failures} is a two-column data
frame of recorded attempt identifiers and error or rejection reasons, including
earlier attempts. An empty attempt-failure table means no recorded
trial reported an error or a rejection reason; it is not a statement about
trials that were never run.

\code{standard_errors_available} is \code{TRUE} only for a Gaussian fit whose
numerically differentiated Hessian was computed and is positive definite. The
Gaussian engine forms the parameter covariance matrix as \code{2 * H^-1} for the
\code{-2 log L} fit function and maps it to source covariance entries by the
delta method; \code{fit$uncertainty} retains that matrix, the entry Jacobian,
and the entry covariance matrix used by \code{gt_reliability()}. The discrete
Laplace engine computes no observed information, so its standard errors are
always unavailable and its coefficients remain point estimates. A component at
a variance boundary is flagged in \code{component_standard_errors}: Wald theory
does not apply there, and the reported number is not a usable standard error.

\code{boundary_sources} describes natural zero or nearly singular covariance
components and does not by itself imply rejection. \code{parameter_bounds}
lists artificial discrete-parameter bound contacts, which do prevent numerical
acceptance. These shared fields summarize existing engine decisions without
repeating or changing numerical checks. \code{summary(fit)} prints a concise
version while retaining full diagnostics for programmatic inspection.

Printing a \code{gt_diagnostics} object reports the same decisions in the same
words. It reads recorded fields only: no check is re-run, no rejection is
re-evaluated, and every field remains available in the returned list.}
\seealso{\code{\link{gt_control}}, \code{\link{gt_fit}}}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
gt_diagnostics(fit)$numerically_accepted
print(gt_diagnostics(fit))
}
