\name{gt_batch_dstudy}
\alias{gt_batch_dstudy}
\alias{print.gt_batch_dstudy}
\alias{as.data.frame.gt_batch_dstudy}
\title{Compare Supplied Allocations for a Fixed Gaussian Batch Layout}
\description{
Apply \code{gt_batch_reliability} to a bounded grid of instrumentation counts,
retaining the same item grouping and the same explicitly weighted targets.
}
\usage{
gt_batch_dstudy(fit, grid, contrasts = NULL, aggregate = NULL, score = NULL)
\method{print}{gt_batch_dstudy}(x, ..., digits = 4L, max_rows = 12L)
\method{as.data.frame}{gt_batch_dstudy}(x, row.names = NULL,
  optional = FALSE, ...)
}
\arguments{
\item{fit}{An accepted shared-call Gaussian fit with a recorded fixed layout.}
\item{grid}{A nonempty data frame of named positive integer instrumentation
counts, with at most 1000 rows. Unspecified facets retain fitted counts.
Batch size and item count cannot be varied.}
\item{contrasts}{Named item contrast weights, as in \code{gt_batch_reliability}.}
\item{aggregate}{Named aggregate item weights, as in \code{gt_batch_reliability}.}
\item{score}{Optional \code{gt_score} outcome weights.}
\item{x}{A \code{gt_batch_dstudy} object.}
\item{digits}{Significant digits for printing.}
\item{max_rows}{Maximum number of printed rows.}
\item{row.names}{Optional row names for tabular export.}
\item{optional}{Accepted for generic compatibility; column names are preserved.}
\item{...}{Reserved for additional print or data-frame arguments.}
}
\details{
Every candidate uses the target and assumptions documented in
\code{\link{gt_batch_reliability}}. All instrumentation facets remain random;
this function cannot improve a projection by changing the universe to fixed
facets. It neither generates allocations nor optimizes costs. It returns
all supplied candidates, including repeated rows. No intervals are created.
At most one million source-contribution rows are permitted, bounding the
returned output size, checked before computing the first candidate. Annotations per item and total calls must remain below
\eqn{2^{53}} for exact integer accounting.
}
\value{
A \code{gt_batch_dstudy} list with \code{summary} and
\code{source_contributions} tables carrying a \code{design_id} referring
to the corresponding row of \code{grid}. The grid includes all fitted
instrumentation facets with unspecified counts filled in. The item layout,
target weights, original counts, batch size, point-only uncertainty record
and interpretation are retained. \code{as.data.frame()} returns the summary
with \code{allocation_<facet>} columns joined by \code{design_id}, including
unchanged fitted counts for unspecified facets. The prefix prevents facet
names from colliding with summary or context columns. Additional columns
retain \code{pilot_items}, \code{batch_size}, \code{annotations_per_item},
\code{projected_calls}, \code{extrapolated}, \code{scale},
\code{uncertainty_available}, \code{uncertainty_reason}, and
\code{interpretation} through a CSV roundtrip. \code{extrapolated} identifies
allocations with any instrumentation count larger than its fitted count.
Grid, interpretation and uncertainty attributes are retained for compatibility.
CSV does not preserve those attributes or the full item layout and target
weights; retain the original list, for example with \code{saveRDS()}, when
those details are needed to reproduce a weighted target.
}
\seealso{\code{\link{gt_batch_reliability}}, \code{\link{gt_dstudy}}}
\examples{
candidates <- expand.grid(rater = 2:4, repetition = 1:3)
# gt_batch_dstudy(fit, candidates,
#   contrasts = list(pair = c(item1 = 1, item2 = -1)))
}
