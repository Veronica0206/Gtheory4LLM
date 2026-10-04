\name{gt_dstudy}
\alias{gt_dstudy}
\alias{plot.gt_dstudy}
\alias{print.gt_dstudy}
\alias{as.data.frame.gt_dstudy}
\alias{gt_dstudy_target}
\title{Evaluate Balanced Measurement Allocations}
\description{Computes supported G and Phi coefficients over a grid of instrumentation counts, validating the fitted context once.}
\usage{
gt_dstudy(fit, grid, scale = NULL, score = NULL, fixed = character(),
  level = 0.95)
\method{print}{gt_dstudy}(x, ..., digits = 4L, max_rows = 12L)
\method{as.data.frame}{gt_dstudy}(x, row.names = NULL, optional = FALSE, ...)
gt_dstudy_target(x, target, coefficient = "Erho2", outcome = NULL,
  kind = "outcome")
\method{plot}{gt_dstudy}(x, coefficient = "Erho2", interval = TRUE, ...,
  target = NULL, outcome = NULL, kind = NULL)
}
\arguments{
\item{fit}{A numerically accepted \code{gt_fit} with a complete balanced coded panel.}
\item{grid}{A nonempty data frame of positive integer facet counts. Columns name declared facets; omitted facets retain their fitted counts.}
\item{scale}{\code{"observed"} for Gaussian outcomes or explicitly \code{"latent"} for binary/ordinal outcomes.}
\item{score}{Optional composite weights created by \code{gt_score()}.}
\item{fixed}{Instrumentation facets treated as fixed, as in \code{gt_reliability()}. A fixed facet may not appear in \code{grid}: its universe is exactly its observed levels.}
\item{level}{Confidence level for the reported coefficient intervals.}
\item{x}{A \code{gt_dstudy} object.}
\item{coefficient}{Plot or screen \code{"Erho2"} (default) or \code{"Phi"}.}
\item{interval}{Draw the interval bounds as vertical segments when the fit supplies them.}
\item{target}{One finite coefficient threshold from 0 to 1, chosen and justified
by the user. Required for screening. Optional in plotting, where \code{NULL}
omits the reference line.}
\item{outcome}{One exact reported outcome name. Screening requires it when
more than one outcome exists within the selected kind. Plotting defaults to
all outcomes.}
\item{kind}{\code{"outcome"} for measured outcomes or \code{"composite"} for
the weighted composite. Screening defaults to \code{"outcome"}. Plotting
defaults to both kinds; specify the kind when an explicitly selected outcome
label also names a composite.}
\item{row.names}{Optional row names for the exported data frame.}
\item{optional}{Accepted for generic compatibility. Exported column names are
always preserved without syntactic name repair.}
\item{digits}{Significant digits used when printing.}
\item{max_rows}{Maximum number of coefficient rows to print.}
\item{...}{Additional arguments passed to \code{graphics::plot()}. A named argument such as \code{col}, \code{pch}, \code{ylim}, \code{xlab} or \code{ylab} replaces the corresponding default rather than duplicating it. Reserved in the print and data-frame methods.}
}
\value{A \code{gt_dstudy} list with completed allocation rows, coefficient results including standard errors and interval bounds, measurements per object, scale, fixed facets, the uncertainty record, extrapolation flags, and fitting diagnostics. The print method shows allocations and coefficients without expanding fitting diagnostics. Both methods return the object invisibly.}
\details{\strong{Tabular export.} \code{as.data.frame()} returns an ordinary
data frame joining each coefficient row to its allocation by the recorded
\code{design_id}, even for multivariate results or reordered coefficient
rows. It preserves coefficient-row order. \code{kind} remains
\code{"outcome"} or \code{"composite"}; a measured outcome named
\code{"composite"} is distinct from a weighted composite.
Export fields follow the reliability data-frame method documented in
\code{\link{gt_reliability}}. All columns are atomic vectors
suitable for \code{write.csv()}; additional R attributes must be retained
separately when exporting to CSV.

\strong{Screening supplied candidates.} \code{gt_dstudy_target()} returns an
ordinary data frame with every supplied allocation for the selected outcome
and kind, preserving coefficient-row order. The added fields are:
\itemize{
\item \code{coefficient} and \code{target}: the chosen criterion.
\item \code{estimate}: the selected coefficient value.
\item \code{meets_target}: the point-estimate comparison.
\item \code{fewest_measurements}: the qualifying minimum-count flag.
}
\code{meets_target} compares the point estimate with the target using
\code{>=}. It does not screen a confidence limit. An unavailable estimate
gives \code{NA}, not \code{FALSE}. Among candidates known to meet the target,
\code{fewest_measurements} marks all ties at the smallest measurement count,
including duplicated supplied allocations. Unknown coefficients retain
\code{NA} in this flag. If no known candidate meets the target, no row is
marked \code{TRUE}. The \code{target_context} attribute records the chosen
coefficient, target, outcome, kind, scale, point-estimate comparison, and
restriction to supplied candidates. Other export context is retained.

Counts at or above \code{2^53}, or overflowing to infinity, cannot be ranked
as exact integer totals. Their \code{measurement_count_exact} flag is
\code{FALSE}. If no qualifying candidate has a smaller exactly represented
total, \code{fewest_measurements} remains \code{NA} for these qualifying
candidates rather than reporting a potentially false tie. If a qualifying
exact small total exists, these larger totals cannot be the minimum.

This helper does not generate allocations, refit models, use monetary costs,
or find a global optimum. The target is a criterion applied to conditional
point projections, not a guarantee of reliability in a new panel. Examine
available intervals, extrapolation flags, and the model's generalization
assumptions alongside the screen. Latent discrete coefficients remain point
estimates with no intervals.

\strong{Plotting.} By default allocations are unconnected points against
measurements per object; different allocations can have the same count.
Colours identify outcome/composite series, and open symbols distinguish
allocations exceeding fitted facet counts from filled symbols within them.
An optional target appears as a dashed horizontal line and is included in
automatic vertical limits. Explicit graphical settings remain authoritative,
including \code{pch} and \code{ylim}. Series filters do not change the
returned object: plotting returns the full original study invisibly.

\strong{Balanced coded panel.} This is the complete Cartesian product of the observed coded levels of the object and of every instrumentation facet, carrying exactly the declared number of rows in each of those cells, with no missing outcome. For a nested facet, \emph{coded} means the child's within-parent code rather than a globally unique label, so the child's identity is the child-by-parent source; \code{\link{gt_design}} works both codings through. A panel that is not balanced in this sense has no analytic coefficient here, and none is approximated.

These are conditional design projections using fitted source covariances. They do not refit the model or establish that larger allocations preserve the same source distributions. Reported intervals propagate estimation uncertainty in the fitted source covariances under the declared random-effects sampling model. They are not prediction intervals for the realized scores of a newly drawn panel, and they do not quantify failure of exchangeability when extending to new facet levels. Boundary and conditional-inference caveats are retained from the fitted model. Intervals are unavailable for discrete fits. Restrictions and coefficient definitions are those of gt_reliability().

A nested child's count may be projected like any other random facet. Its own source and every source containing it are then divided by the joint count of child and parent, while sources built from the parent alone keep the parent count: adding children therefore reduces less error than adding an equal number of levels of a fully crossed facet. A fixed facet may not appear in \code{grid}, but its random children still may.}
\seealso{\code{\link{gt_reliability}}, \code{\link{gt_score}}}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
study <- gt_dstudy(fit, data.frame(rater = c(2, 3, 6)))
as.data.frame(study)
gt_dstudy_target(study, target = 0.80, coefficient = "Phi")
plot(study, coefficient = "Phi", target = 0.80)
}
