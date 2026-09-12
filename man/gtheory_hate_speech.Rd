\name{gtheory_hate_speech}
\alias{gtheory_hate_speech}
\alias{hate_speech}
\docType{data}
\title{LLM Hate-Speech Annotations of HateXplain Texts}
\description{An ordinal outcome set containing repeated LLM judgments of 100
HateXplain text items. The installed package includes the modeling table and
source provenance, accessed through \code{\link{gt_example}}.}
\format{The loader returns a list; its \code{data} element is a data frame with
21,600 rows and six columns. Each item has 216 measurements in the complete
item-by-evaluator-by-prompt-by-temperature-by-seed panel.
\describe{
\item{item}{Factor identifying the 100 text items.}
\item{evaluator, prompt, temp, seed}{Factors identifying the four evaluators,
three prompt conditions, six temperatures, and three replicate seeds. Their
stored levels and interpretation are documented in
the \link[=gtheory_datasets]{dataset overview}.}
\item{score}{With \code{coding = "native"}, an ordered factor with levels
\code{1}, \code{2}, \code{3}: NORMAL, OFFENSIVE, and HATE, respectively.
With \code{coding = "manuscript"}, the same values are numeric Gaussian
working scores.}
}
The remaining list elements identify the outcome, family, object, facets,
coding, source, and interpretation notes; installed resources also provide
\code{source_provenance}.}
\details{The native family is ordinal with a probit link. The category order
expresses the study's normal/offensive/hate distinction; using numeric
manuscript scores additionally treats the category steps as equally spaced.

These outcomes are the repeated LLM annotations used in the G-theory study,
not the original HateXplain crowdworker labels. The data table contains design
identifiers and the modeled outcome only; original posts, crowdworker labels,
probability vectors, prompts, and API metadata are not included.

Every modeling row has a recorded value after the original study's
preprocessing. That pipeline could assign NORMAL to items omitted from an
otherwise parsed response batch. The package preserves the stored outcomes
and does not separately identify such defaults. Completeness of the modeling
table therefore does not imply that every original response was complete.

The full table exceeds the current dense discrete fitting limits. The examples
below describe the data without fitting the full panel; see
the \link[=gtheory_datasets]{dataset overview} for the shared design and fitting
scope.}
\source{Derived from \file{hate_labeling_final.csv} in the public OSF annotation
deposit (Liu, 2026), \doi{10.17605/OSF.IO/K9CAJ}. HateXplain is the original text corpus (Mathew et al.,
2021); Liu (2026) describes the related rubric-conditioned annotation study.
These references concern corpus and annotation provenance, respectively.
The common G-theory source is cited in the
\link[=gtheory_datasets]{dataset overview}.}
\references{
Mathew, B., Saha, P., Yimam, S. M., Biemann, C., Goyal, P., and Mukherjee, A.
(2021). HateXplain: A Benchmark Dataset for Explainable Hate Speech Detection.
\emph{Proceedings of the AAAI Conference on Artificial Intelligence},
35(17), 14867--14875. \doi{10.1609/aaai.v35i17.17745}.

Liu, J. (2026). Rubric-conditioned large language model labeling: Agreement,
uncertainty, and label consistency in subjective text annotation.
\emph{Computers in Human Behavior}, 181, 108988.
\doi{10.1016/j.chb.2026.108988}.
}
\seealso{\link[=gtheory_datasets]{Dataset overview}, \code{\link{gt_example}},
\code{\link{gt_family}}}
\examples{
hate <- gt_example("hate_speech")
dim(hate$data)
str(hate$data)
table(hate$data$score)

# The historical numeric coding represents the same stored judgments.
working <- gt_example("hate_speech", coding = "manuscript")
str(working$data$score)
}
\keyword{datasets}
