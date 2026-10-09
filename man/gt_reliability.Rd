\name{gt_reliability}
\alias{gt_reliability}
\alias{print.gt_reliability}
\alias{as.data.frame.gt_reliability}
\title{Compute Balanced G and Phi Coefficients}
\description{Forms universe-score, relative-error, and absolute-error covariance matrices under a declared balanced averaging design.}
\usage{
gt_reliability(fit, scale = NULL, score = NULL, design = NULL, counts = NULL,
  fixed = character(), level = 0.95)
\method{print}{gt_reliability}(x, ..., digits = 4L, max_rows = 12L)
\method{as.data.frame}{gt_reliability}(x, row.names = NULL,
  optional = FALSE, ...)
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
\item{row.names}{Optional row names for the exported data frame.}
\item{optional}{Accepted for generic compatibility. Exported column names are
always preserved without syntactic name repair.}
\item{...}{Reserved for additional print or data-frame arguments.}
}
\value{A \code{gt_reliability} list containing per-outcome \code{Erho2} and \code{Phi} with their standard errors and interval bounds, optional composite coefficients, universe/relative-error/absolute-error covariance matrices, the role each source played in the decomposition, coefficient scale, allocation, fixed facets, extrapolation flag, the uncertainty record, and fit diagnostics. Standard errors and bounds are \code{NA} whenever the fit carries no usable parameter covariance matrix. Printing shows a concise coefficient table, omits all-missing interval columns, and returns the complete object invisibly.}
\details{\strong{Tabular export.} \code{as.data.frame()} returns an ordinary
data frame with one row per outcome and an additional row for a requested
weighted composite. \code{design_id} is 1 for this single allocation.
\code{kind} is \code{"outcome"} or \code{"composite"}; use it together with
\code{outcome}, because a measured outcome may itself be named
\code{"composite"}. Coefficients retain the names \code{Erho2} and \code{Phi},
with their \code{_se}, \code{_lower}, and \code{_upper} columns, including
missing values when uncertainty is unavailable.

Allocation columns prepend \code{allocation_} to each exact facet name.
The mapping attribute is named \code{allocation_columns}.
It maps exported names back to the original facets, protecting coefficient
fields from similarly named facets. The table also includes:
\itemize{
\item \code{scale} and \code{interval_level}: coefficient interpretation.
\item \code{uncertainty_available}: covariance availability.
\item \code{uncertainty_reason}: the recorded reason.
\item \code{uncertainty_conditional}: the conditional-inference flag.
\item \code{uncertainty_conditioning}: what was held fixed.
\item \code{Erho2_interval_available}: relative interval availability.
\item \code{Phi_interval_available}: absolute interval availability.
\item \code{fixed_facets}: the declared fixed universe.
\item \code{composite_weights}: weights for composite rows.
\item \code{measurements_per_object}: the allocation total.
\item \code{measurement_count_exact}: integer precision status.
\item \code{extrapolated}: extension beyond fitted facet counts.
\item \code{batch_status}: whether the design declared batches.
}
\code{uncertainty_available} describes availability of the fitted covariance
used for propagation; individual intervals can still be missing, for example
at a coefficient boundary. The conditional flag records inference restricted
to the interior parameter block, and the conditioning text identifies what
was held fixed, distinguishing zero from singular nonzero covariance.
The per-coefficient availability flags indicate that the estimate and both
interval bounds are finite in that particular row. Fixed facets are listed with quoted,
escaped labels, separated by semicolons; an empty string means none.
Composite rows carry similarly quoted outcome labels and numerical weights;
\code{composite_weights} is \code{NA} for measured-outcome rows.
\code{measurement_count_exact} is \code{TRUE} for finite allocation totals
below \code{2^53}, the range in which consecutive integers have exact double
representations. Larger totals are retained for reporting but not treated as
exact counts when comparing candidate minima.
\code{batch_status} is \code{"not_declared"}, or
\code{"declared_not_modelled"} for a design made with
\code{\link{gt_batch}} whose batches the fit did not model: the coefficients in
that row treat items annotated in one call as independent. Printing and
plotting say the same. A fit that does model a call effect is refused by these
ordinary methods. Use \code{\link{gt_batch_reliability}} and
\code{\link{gt_batch_dstudy}} for explicit targets conditional on the fitted
fixed Gaussian batching layout; no universal batch-adjusted G is assumed.

Columns are atomic vectors suitable for CSV output.
Additional attributes retain the fixed-facet declaration, a compact uncertainty
record, the structured score, the batch status and the interpretation. Their
names are \code{fixed_facets}, \code{uncertainty}, \code{score}, \code{batch}
and \code{interpretation}.
CSV does not preserve R attributes; keep these
alongside a CSV when reporting the full analysis context. Conversion does
not refit the model or create new uncertainty estimates.

\strong{Balanced coded panel.} This is the complete Cartesian product of the observed coded levels of the object and of every instrumentation facet, carrying exactly the declared number of rows in each of those cells, with no missing outcome. For a nested facet, \emph{coded} means the child's within-parent code rather than a globally unique label, so the child's identity is the child-by-parent source; \code{\link{gt_design}} works both codings through. A panel that is not balanced in this sense has no analytic coefficient here, and none is approximated.

In the fully random model, the object main-effect covariance defines universe-score variation. Every object-containing error component contributes to relative error, and every non-object-main component contributes to absolute error. Each component is divided by the product of the instrumentation counts in its grouping term; the residual is also divided by declared cell replication.

Declaring a facet \code{fixed} selects the mixed model of Brennan (2001). The universe of generalization then contains exactly that facet's observed levels: an object interaction containing only fixed instrumentation facets is averaged over those levels and added to universe-score variance; a source built only from fixed instrumentation facets shifts every object equally and leaves the comparison; every remaining source keeps its usual divisor. With no fixed facet this reduces exactly to the fully random decomposition. \code{$source_roles} records which role each source took. Fixed versus random treatment follows the intended universe of generalization, not a facet name or whether its levels were researcher-selected. The option changes coefficient aggregation after fitting; it does not repair a misspecified G-study covariance model.

Intervals use the delta method on the logit scale, propagating the fitted parameter covariance matrix through the source covariance entries. They are asymptotic Wald intervals for estimation uncertainty under the declared random-effects model and allocation. Finite sampling of facet levels is part of that model; the intervals are not prediction intervals for the realized scores of a new panel and do not quantify misspecification of the facet populations. Wald theory does not generally apply to a source resting on a variance boundary. When inference uses an interior parameter block, the remaining intervals condition on the listed fixed components, and the fit says which way: a source whose fitted covariance is entirely zero is held at zero, and a singular but nonzero source is held fixed at its fitted covariance, which is a different statement. Unconditional coverage after that selection has not been established. The discrete engine supplies no parameter covariance matrix, so its coefficients remain point estimates.

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
as.data.frame(gt_reliability(fit))
}
