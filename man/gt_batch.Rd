\name{gt_batch}
\alias{gt_batch}
\title{Declare That Items Were Annotated Several to a Call}
\description{Declares that the object of measurement was submitted in calls of several items, so that items sharing a call are not independent. Without a declaration every function treats items as independent given the declared sources.}
\usage{
gt_batch(size, order = NULL, by = NULL, sequential = FALSE,
  neighbor = FALSE)
}
\arguments{
\item{size}{The number of items in a call: one integer of at least 2.}
\item{order}{Optional name of a numeric column giving the order in which items were submitted. Each item has one distinct value, the same in every condition. \code{NULL} uses the order in which items first appear in the data.}
\item{by}{Optional name of an instrumentation facet across whose levels the dependence may differ, for example the evaluator.}
\item{sequential}{\code{FALSE}, or how many preceding items may affect an item: a whole number from 1 to \code{size - 1}. \code{TRUE} means every preceding item in the call.}
\item{neighbor}{\code{FALSE}, or how many positions apart two items may be and still affect each other, in either direction: a whole number from 1 to \code{size - 1}. \code{TRUE} means any distance within the call.}
}
\value{A \code{gt_batch} list holding the size, the order column, the facet named in \code{by}, the two reaches as integers with 0 for a pattern that is off, and the assumption they state in words.}
\details{A declaration is passed to \code{\link{gt_design}} and travels with the design to every function that receives it or a fit made from it.

By default items in one call are assumed to affect each other equally, whatever their order, and items in different calls are independent given the declared sources. That the dependence varies with position is a separate, optional claim, and two patterns fit it. In a sequential pattern an item is affected by items submitted before it. In a neighbour pattern items close together affect each other in either direction. Data in which every item keeps the same position cannot always tell the two apart, so each is declared on its own, and declaring one asks for it to be examined rather than asserting it.

A batch is fixed: the same items, in the same order, in every condition. The last call may not be smaller than the others.

\strong{Current scope.} A declaration is recorded and audited by \code{\link{gt_preflight}}, which reports the calls it implies and whether it describes the data. Estimates in this version still treat items in one call as independent, and every fit made from a declaring design says so in its notes.}
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
report$batch_audit[c("batches", "conditions", "calls", "consistent")]
}
