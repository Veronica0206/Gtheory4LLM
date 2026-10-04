\name{plot.gt_reliability}
\alias{plot.gt_reliability}
\title{Plot Reliability Coefficients and Available Intervals}
\description{Draws a forest plot of the already calculated relative and absolute
coefficients, with available estimation intervals and explicit outcome labels.}
\usage{
\method{plot}{gt_reliability}(x, coefficient = c("Erho2", "Phi"),
  interval = TRUE, target = NULL, ...)
}
\arguments{
\item{x}{A result from \code{gt_reliability()}.}
\item{coefficient}{One or both of \code{"Erho2"} and \code{"Phi"}, without duplicates.}
\item{interval}{Whether to draw available interval bounds. Missing bounds are
never replaced by a zero-width interval.}
\item{target}{Optional reference line at one number between zero and one.
It is a descriptive target, not a confidence statement.}
\item{...}{Named graphical arguments passed to \code{graphics::plot()}, such as
\code{col}, \code{pch}, \code{main}, \code{xlim}, or \code{sub}, replacing defaults.
The coefficient coordinates are supplied by the method.}
}
\value{Returns \code{x} invisibly.}
\details{Outcome rows and a weighted composite have distinct labels.
The horizontal axis names the observed or latent coefficient scale. The default
subtitle identifies unavailable or hidden intervals, conditional uncertainty,
and extrapolation. A caller overriding the subtitle should preserve the
interpretation relevant to their analysis. Unavailable estimates keep their
label but have no plotted point. Changing the graphic does not refit the model
or alter any acceptance or inference decision.

On narrow devices, long labels are shortened with an ellipsis and a bracketed
row number referring to \code{as.data.frame(x)}. Full outcome names remain in
that table. Margins are restored after plotting.

Discrete fits have point estimates only. Their latent-response coefficients
do not describe observed label proportions or majority votes. Gaussian interval
and boundary qualifications are described in \code{\link{gt_reliability}}.
The plotting method uses base graphics; PDF and PNG devices can save the
same figure without additional plotting dependencies.}
\seealso{\code{\link{gt_reliability}}, \code{\link{gt_dstudy}},
\code{\link{gt_preflight}}}
