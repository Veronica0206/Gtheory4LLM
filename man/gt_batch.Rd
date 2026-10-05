\name{gt_batch}
\alias{gt_batch}
\title{Declare That Items Were Annotated Several to a Call}
\description{Declares that the object of measurement was submitted in calls of several items, so that items sharing a call are not independent. Without a declaration every function treats items as independent given the declared sources.}
\usage{
gt_batch(size, order = NULL, by = NULL, sequential = FALSE,
  neighbor = FALSE, id = NULL)
}
\arguments{
\item{size}{The number of items in a call: one integer of at least 2. With \code{id}, the most a call may hold.}
\item{order}{Optional name of a numeric column giving the order in which items were submitted. Without \code{id}, each item has one distinct value, the same in every condition, and \code{NULL} uses the order in which items first appear in the data. With \code{id}, it gives the position of each row's item in its call, and \code{NULL} uses the stored order of the rows of each call.}
\item{by}{Optional name of an instrumentation facet across whose levels the dependence may differ, for example the evaluator.}
\item{sequential}{\code{FALSE}, or how many preceding items may affect an item: a whole number from 1 to \code{size - 1}. \code{TRUE} means every preceding item in the call.}
\item{neighbor}{\code{FALSE}, or how many positions apart two items may be and still affect each other, in either direction: a whole number from 1 to \code{size - 1}. \code{TRUE} means any distance within the call.}
\item{id}{Optional name of a column identifying the call that produced each row. \code{NULL}, the default, infers the batches from the item order.}
}
\value{A \code{gt_batch} list holding the size, the order column, the facet named in \code{by}, the two reaches as integers with 0 for a pattern that is off, the call column, and the assumption they state in words.}
\details{A declaration is passed to \code{\link{gt_design}} and travels with the design to every function that receives it or a fit made from it.

By default items in one call are assumed to affect each other equally, whatever their order, and items in different calls are independent given the declared sources. That the dependence varies with position is a separate, optional claim, and two patterns fit it. In a sequential pattern an item is affected by items submitted before it. In a neighbour pattern items close together affect each other in either direction. Data in which every item keeps the same position cannot always tell the two apart, so each is declared on its own, and declaring one asks for it to be examined rather than asserting it.

\strong{Inferred and recorded calls.} Which items shared a call is either inferred or recorded. Without \code{id} it is inferred: the items present in the data are cut into batches of \code{size} in their order, the last holding what remains, and a batch is the same items, in the same order, in every condition. That is all that data without a call column allow, and it is a reconstruction. An item removed after collection moves every later item into another position and possibly another batch, and nothing in the data shows it; calls of other sizes and regrouping between conditions cannot be seen either. With \code{id} the calls are read from the data. They may then hold different items in different conditions and fewer items than \code{size}; a call may not span conditions, hold an item twice, or hold more than \code{size} items. Record the call when collecting data, and prefer \code{id} whenever that record exists.

Recorded calls are still read from the rows supplied, and three things follow. A call is counted by the items of it that are present, so a call that was sent \code{size} items and lost one afterwards looks the same as a call sent one item short. A call with no row left is not counted at all. And a position is a rank among the items present in a call: an \code{order} column holding 1, 3 and 4 gives positions 1, 2 and 3. Positions are the positions at which items were sent only when nothing was removed after collection, so a distance between two positions is not yet a distance in the call as it was sent. Keep the unfiltered rows, or the number of items sent in each call, if that distinction will matter.

\strong{Current scope.} A declaration is recorded and audited by \code{\link{gt_preflight}}, which reports the calls it implies or reads and whether the declaration describes the data. Estimates in this version still treat items in one call as independent. Every result made from a declaring design says so: fits, diagnostics, coefficients and decision studies print it, their data-frame exports carry \code{batch_status = "declared_not_modelled"}, and \code{\link{gt_report}} records it.}
\seealso{\code{\link{gt_design}}, \code{\link{gt_preflight}}}
\examples{
calls <- gt_batch(20)
calls$assumption
local <- gt_batch(20, by = "evaluator", sequential = 3, neighbor = TRUE)
c(sequential = local$sequential, neighbor = local$neighbor)

d <- expand.grid(item = 1:40, evaluator = 1:3, prompt = 1:2)
d$score <- sin(d$item) + d$evaluator / 5 + cos(d$item * d$prompt) / 4
design <- gt_design("item", c("evaluator", "prompt"), batch = calls)
report <- gt_preflight(d, "score", design)
report$batch_audit[c("membership", "batches", "conditions", "calls")]

# Calls recorded in the data are read, not reconstructed.
d$call <- paste(d$evaluator, d$prompt, (d$item - 1) \%/\% 20)
recorded <- gt_design("item", c("evaluator", "prompt"),
  batch = gt_batch(20, id = "call"))
gt_preflight(d, "score", recorded)$batch_audit[c("membership", "calls")]
}
