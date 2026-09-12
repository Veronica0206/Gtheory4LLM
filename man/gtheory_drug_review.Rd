\name{gtheory_drug_review}
\alias{gtheory_drug_review}
\alias{drug_review}
\alias{drug_review_4aspect}
\docType{data}
\title{LLM Drug-Review Sentiment and Four Aspect Annotations}
\description{Two outcome sets from repeated LLM judgments of 100 medication
reviews: five-category holistic sentiment and four three-category aspects.
The modeling tables are accessed with \code{\link{gt_example}}.}
\format{Each call returns a list whose \code{data} element has 21,600 rows.
The five shared factor columns are \code{item}, \code{evaluator}, \code{prompt},
\code{temp}, and \code{seed}: 100 reviews crossed with four evaluators, three
prompts, six temperatures, and three replicate seeds. Their stored levels
are documented in the \link[=gtheory_datasets]{dataset overview}.
\describe{
\item{drug_review}{One \code{score} column. Native coding is an ordered factor:
1 = VERY_NEGATIVE, 2 = NEGATIVE, 3 = NEUTRAL, 4 = POSITIVE,
5 = VERY_POSITIVE. These are holistic sentiment categories, even though the
source CSV calls its score column \code{severity}.}
\item{drug_review_4aspect}{Four outcome columns: \code{efficacy},
\code{safety}, \code{burden}, and \code{cost}. Each is an ordered factor with
levels NEGATIVE, NEUTRAL, POSITIVE under native coding.}
}
The native families are ordinal with probit links. For either set,
\code{coding = "manuscript"} returns numerical Gaussian working scores:
1--5 for holistic sentiment and 1--3 for each aspect.
The loader also returns outcome names, families, design roles, coding, source,
and notes; installed resources include \code{source_provenance}.}
\details{The aspect annotations summarize the review's sentiment about:
\describe{
\item{efficacy}{Whether the treatment helped or worked (positive) or did not
work or worsened the problem (negative).}
\item{safety}{Tolerability or absence of side effects (positive) versus side
effects or adverse events (negative).}
\item{burden}{Convenience or ease of use (positive) versus inconvenience,
adherence difficulty, or regimen complexity (negative).}
\item{cost}{Affordability or coverage (positive) versus expense, coverage
denial, or high out-of-pocket costs (negative).}
}
The study's rubric assigned NEUTRAL when an aspect was unclear, unmentioned,
or mixed. This category should not uniformly be read as an explicitly neutral
patient opinion. Aspects can disagree with the holistic sentiment response.

These are LLM-generated annotations of reviews drawn from the UCI Drug Review
corpus, collected from Drugs.com. They are not the original patient-provided
1--10 ratings. The installed tables omit review text, medication and condition
metadata, source ratings, probability vectors, and API metadata.

Every modeling row is complete after the source study's preprocessing, which
allowed NEUTRAL defaults for items omitted from an otherwise parsed response
batch. The package preserves these stored annotations and does not identify
defaults separately. The two sets share the same sampled reviews and design;
they are not independent datasets. The complete discrete tables exceed current
dense backend limits; the examples below only load and summarize them.}
\source{Derived from \file{drug_labeling_final.csv} in the public OSF annotation
deposit (Liu, 2026), \doi{10.17605/OSF.IO/K9CAJ}. \enc{Gräßer}{Grasser} et al. (2018) describe the source
drug-review data; Liu (2026) describes the related aspect-level LLM annotation
study. The common G-theory source is cited in the
\link[=gtheory_datasets]{dataset overview}.}
\references{
\enc{Gräßer}{Grasser}, F., Kallumadi, S., Malberg, H., and Zaunseder, S.
(2018). Aspect-Based Sentiment Analysis of Drug Reviews Applying Cross-Domain
and Cross-Data Learning. \emph{Proceedings of the 2018 International Conference
on Digital Health}, 121--125. \doi{10.1145/3194658.3194677}.

Liu, J. (2026). Learning to Fuse Aspect-Level LLM Annotations for Low-Quality
Ordinal Sentiment Supervision. \emph{SSRN working paper}, 6244519;
revised June 17, 2026.

\doi{10.2139/ssrn.6244519}.
}
\seealso{\link[=gtheory_datasets]{Dataset overview}, \code{\link{gt_example}},
\code{\link{gt_family}}}
\examples{
holistic <- gt_example("drug_review")
str(holistic$data$score)
table(holistic$data$score)

aspects <- gt_example("drug_review_4aspect")
str(aspects$data[aspects$outcomes])
table(aspects$data$efficacy, aspects$data$safety)
}
\keyword{datasets}
