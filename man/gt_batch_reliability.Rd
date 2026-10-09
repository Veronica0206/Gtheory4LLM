\name{gt_batch_reliability}
\alias{gt_batch_reliability}
\alias{print.gt_batch_reliability}
\alias{as.data.frame.gt_batch_reliability}
\title{Project Gaussian Score Error Conditional on a Fixed Batch Layout}
\description{
Compute annotation error for absolute item scores, named item contrasts,
and weighted aggregates under an accepted shared-call Gaussian model.
The calculation contracts source kernels directly without forming an
observation covariance matrix.
}
\usage{
gt_batch_reliability(fit, counts = NULL, contrasts = NULL,
  aggregate = NULL, score = NULL)
\method{print}{gt_batch_reliability}(x, ..., digits = 4L, max_rows = 12L)
\method{as.data.frame}{gt_batch_reliability}(x, row.names = NULL,
  optional = FALSE, ...)
}
\arguments{
\item{fit}{An accepted Gaussian \code{gt_fit} that models equal, fixed batches
and records its item-to-batch layout. Older saved fits without this record
must be refitted; membership is never guessed.}
\item{counts}{Optional named positive integer instrumentation counts.
Unspecified facets retain their fitted counts. Item count and batch size
cannot be changed. All instrumentation facets remain random.}
\item{contrasts}{A numeric vector named by item identifiers and summing to
zero, or a named list of such vectors. Omitted items have weight zero.
For example, \code{list(within = c(item1 = 1, item2 = -1))} declares an item
difference. Identifiers refer to the fitted layout.}
\item{aggregate}{A numeric vector named by item identifiers, or a named
list of such vectors. Every vector must have nonnegative weights summing
to one. Omitted items have weight zero; weights are not normalized.}
\item{score}{Optional \code{gt_score} weights for a composite across outcomes.
Per-outcome results are also returned.}
\item{x}{An object returned by this function.}
\item{digits}{Significant digits for printing.}
\item{max_rows}{Maximum number of rows printed.}
\item{row.names}{Optional row names for the exported data frame.}
\item{optional}{Accepted for generic compatibility; column names are preserved.}
\item{...}{Reserved for additional print or data-frame arguments.}
}
\details{
\strong{Target and scope.} The universe score is the object main effect.
Each final item score averages a complete panel of all instrumentation
conditions with equal weights. The fitted object grouping is held fixed.
Facet counts may change under the model's exchangeability assumptions,
but every planned condition must retain that same item grouping.
The helper does not generalize over randomized regrouping or predict a
change in shared-call variance when batch size changes. It does not support
fixed instrumentation facets, unequal observation weights, incomplete
panels, within-cell replication, or declared positional or facet-varying
batch patterns that the fitted model did not estimate.

\strong{Error contractions.} For a supplied item-weight vector \eqn{w}, a
source containing the object contributes its variance times
\eqn{\sum_i w_i^2}; an instrumentation-only source contributes its variance
times \eqn{(\sum_i w_i)^2}. Each is divided by the product of planned counts
of the instrumentation facets in its grouping term. Residual variance is
multiplied by \eqn{\sum_i w_i^2} and divided by the number of annotations per
item. The shared-call contribution is its variance times
\eqn{\sum_b (\sum_{i \in b} w_i)^2}, divided by the number of annotations per
item. For a multivariate score, each source variance is the corresponding
quadratic form in \code{score}'s outcome weights.

Thus a shared call shift cancels from a same-batch item difference, remains
in a between-batch difference, and remains in an absolute item score. A
weighted aggregate depends on how its weights are distributed across
batches. Instrumentation-only sources remain in an aggregate even as the
number of averaged items increases. There is no universal batch penalty.

\strong{Interpretation of ratios.} Absolute item rows report \code{Phi}.
Contrast rows report \code{contrast_reliability}, and aggregate rows report
\code{aggregate_dependability}. Each is the model-implied universe variance
of that exact weighted target divided by its universe plus annotation-error
variance. A contrast ratio is not a single G coefficient for every possible
item ranking. Aggregate error conditions on the selected items and excludes
corpus-sampling uncertainty. It is not uncertainty about an unknown
population mean. Zero total variance returns \code{NA}. All results are
point projections; no sampling standard errors or confidence bounds are
provided. \code{error_sd} is the model-implied annotation-error standard
deviation, not a standard error of an estimated coefficient.

At most one million source-contribution rows are permitted, checked before
materializing target results. Nonfinite quadratic forms and numerically
unrepresentable weight scales are refused; rescale extreme target weights.

The fitted layout and returned target weights contain item identifiers.
Treat these objects as analysis data. Portable \code{gt_report(fit)} output
does not include the layout; this result is not silently inserted into it.
}
\value{
A \code{gt_batch_reliability} list. \code{summary} has one row per target
and outcome, plus requested composites, with universe variance, error
variance, error standard deviation, ratio and its explicit name.
\code{source_contributions} records each source's role, kernel contraction,
divisor and variance contribution. \code{layout} and \code{target_weights}
record the item grouping and weighted targets. Other fields record fitted
and planned facet counts, pilot-item count, annotations per item, projected
calls, unchanged batch size, extrapolation, scale and interpretation.
\code{uncertainty$available} is \code{FALSE}. \code{as.data.frame()} returns
\code{summary} and retains counts, interpretation and uncertainty as
attributes; CSV output does not retain those attributes.
}
\seealso{\code{\link{gt_batch}}, \code{\link{gt_batch_dstudy}},
\code{\link{gt_reliability}}, \code{\link{gt_score}}}
\examples{
# Weights identify the target explicitly; use fitted item IDs in an analysis.
within_pair <- c(item1 = 1, item2 = -1)
corpus_weights <- c(item1 = 0.25, item2 = 0.25, item3 = 0.5)
# gt_batch_reliability(fit, contrasts = list(within = within_pair),
#   aggregate = list(corpus = corpus_weights))
}
