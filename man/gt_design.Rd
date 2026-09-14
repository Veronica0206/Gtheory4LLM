\name{gt_design}
\alias{gt_design}
\title{Declare a Generalizability-Theory Random-Source Design}
\description{Declares an object of measurement, any number of instrumentation facets, selected object interactions, and explicit parent-scoped nesting. This constructor preserves the requested source terms; fitting validates the observed data and resolves any residual alias.}
\usage{
gt_design(object, facets, crossed = facets, nested = NULL,
  item_interactions = "complete", instrument_interactions = "complete",
  item_nested = character(), random = NULL, full_cell = TRUE,
  replicates = 1L, max_terms = 4096L)
}
\arguments{
\item{object}{One column name for the object of measurement.}
\item{facets}{Unique instrumentation column names, excluding the object.}
\item{crossed}{A nonempty subset of facets allowed to form direct object interactions. Defaults to all facets.}
\item{nested}{A named list giving the instrumentation parents of every non-crossed facet. Multiple parents define their joint group. Ancestors are expanded recursively; cycles are rejected.}
\item{item_interactions}{\code{"complete"}, \code{"additive"}, or the maximum number of crossed instrumentation facets in an object interaction. The object itself is excluded from this order. Additive adds individual object-by-crossed-facet interactions.}
\item{instrument_interactions}{\code{"complete"}, \code{"additive"}, or a maximum interaction order among crossed instrumentation facets. Declared nested groups remain present.}
\item{item_nested}{Nested child names whose complete ancestor-expanded group should also interact with the object. This does not implicitly add other ancestor-by-object interactions.}
\item{random}{Optional explicit one-sided formula or character vector of source terms. Formula syntax is limited to names, \code{+}, \code{:}, \code{*}, parentheses, and 0/1. Cannot be combined with explicitly supplied automatic selectors.}
\item{full_cell}{Retain the object-by-all-facets source when the requested expansion contains it. \code{FALSE} removes exactly that one term and leaves every other requested source unchanged. Unlike the other selectors this may be combined with \code{random}.}
\item{replicates}{Positive integer observations per complete object-by-facets cell. Observed replication is checked during fitting.}
\item{max_terms}{Positive integer bound on source expansion, checked before expansion.}
}
\value{A \code{gt_design} list containing the object, facets, requested terms and their members, nesting metadata, and pending data-validation information.}
\details{The object main effect is always present. With all facets crossed, complete object and instrumentation interactions retain the full hierarchy. At one observation per cell, a Gaussian full-cell source is indistinguishable from a free residual and is combined with it during fitting. A requested observation-level source is rejected for discrete families, because it cannot be separated from the identified discrete observation model. It is never dropped silently: declare the reduced model with \code{full_cell = FALSE}, which removes only that source, or write the intended terms with \code{random}.

Nesting defines parent-scoped groups shared across objects. It does not establish that a physical sampling design is balanced or identifiable. Arbitrary design declaration does not imply that every backend supports every resulting model.

\strong{Balanced coded panel.} Gaussian fitting, \code{gt_reliability()} and \code{gt_dstudy()} all require one. It is the complete Cartesian product of the observed coded levels of the object and of every instrumentation facet, carrying exactly \code{replicates} rows in each of those cells, with no missing outcome. Nothing is imputed, aggregated or dropped to reach it.

\emph{Coded} is what makes a nested facet fit this description. A nested child is identified by its code within its parent, so child codes repeat across parents and the Cartesian product stays complete; the child's real identity is then the child-by-parent source, not the child column on its own. Globally unique child labels describe the same study but leave most child-by-parent cells structurally empty, and this backend rejects that panel instead of guessing which cells were never possible. The example below shows both codings of one six-item design.}
\seealso{\code{\link{gt_fit}}, \code{\link{gt_family}}}
\examples{
complete <- gt_design("item", c("evaluator", "prompt", "temp", "seed"))
length(complete$terms_requested)
selected <- gt_design("item", c("evaluator", "prompt", "temp", "seed"),
  crossed = c("evaluator", "prompt"),
  nested = list(temp = c("evaluator", "prompt"), seed = "temp"))
selected$terms_requested
reduced <- gt_design("item", c("rater", "occasion"), random = ~ item + rater)
reduced$terms_requested
# The same crossed design without the observation-level source, which a
# binary or ordinal fit at one observation per cell cannot identify. This is
# where a first discrete fit should start; see the worked script in
# system.file("examples", "discrete-first.R", package = "Gtheory4LLM").
discrete_ready <- gt_design("item", "rater", full_cell = FALSE)
discrete_ready$terms_requested

# Globally unique child labels versus within-parent codes, for six items
# nested in two questions and rated by four people.
coded_cells <- function(data, columns)
  prod(vapply(data[columns], function(x) length(unique(x)), integer(1)))
physical <- expand.grid(person = 1:4, item = 1:6)
physical$question <- 1 + (physical$item > 3)
# Unique labels 1-6 imply 48 coded cells but supply 24: item 4 never appears
# in question 1, so the coded panel is structurally incomplete.
c(rows = nrow(physical),
  cells = coded_cells(physical, c("person", "item", "question")))
physical$item_code <- physical$item - 3 * (physical$question - 1)
# The within-parent code describes the same six items as a complete panel.
c(rows = nrow(physical),
  cells = coded_cells(physical, c("person", "item_code", "question")))
nested_design <- gt_design("person", c("item_code", "question"),
  crossed = "question", nested = list(item_code = "question"))
nested_design$terms_requested   # item_code:question identifies the six items
nested_design$nested_groups
}
