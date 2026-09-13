\name{gtheory_datasets}
\alias{Gtheory4LLM-datasets}
\alias{gtheory_datasets}
\docType{data}
\title{Three LLM Annotation Datasets: Design, Coding, and Sources}
\description{Documents the Hate-Speech, Mental-Health, and Drug-Review modeling
panels distributed with Gtheory4LLM. The three underlying datasets provide eight
outcome sets and fifteen combinations of outcome set and coding through
\code{\link{gt_example}}.}
\details{
Each dataset contains a 100-item crossed LLM annotation panel from the public
OSF annotation deposit (Liu, 2026). Task definitions and
annotation protocols are described in the three task-specific studies cited
in the dedicated dataset topics. HateXplain, Sentiment Analysis for Mental
Health, and Drugs.com reviews supplied the original text material.

Items were selected using screening-pass entropy stratification. Each of the
100 items was evaluated under all combinations of four evaluators, three
prompt types, six temperatures, and three seeds, yielding 216 rows per item
and 21,600 rows per outcome set. These are repeated measurements on 100 text
objects; the row count is not the number of independent texts. The selected
items and evaluator panel define the scope of these examples.

The installed resources contain design identifiers and modeled LLM outcomes.
The source study's parsing and post-processing are retained, including default
labels for omitted items within successfully parsed batches. There are no
missing modeling values in the stored panels; this does not establish that
every original API response supplied a usable item annotation. Raw texts,
prompt text, original corpus reference labels, and API metadata are outside
these minimal modeling tables.
}
\format{
Calling \code{gt_example(name)} returns a list. Its \code{data} element is a
data frame containing the five shared factor columns below and the selected
outcome column(s). The other elements identify the outcomes, observation
families, object and facets, coding, source, and interpretation notes.
Installed resources also include \code{source_provenance}.
\describe{
\item{item}{100 text-object identifiers retained from the corresponding
public annotation table.}
\item{evaluator}{Four stored run identifiers:
\itemize{
\item \code{gemini-2.5-flash}
\item \code{gpt-4o-mini}
\item \code{llama-70b} (Llama-3.3-70B)
\item \code{mistral-small} (Mistral-Small-24B)
}}
\item{prompt}{Three prompt identifiers: \code{cot}, \code{minimal}, and
\code{rubric}. The \code{cot} condition adds a structured reasoning checklist.}
\item{temp}{Six temperature levels: \code{0}, \code{0.2}, \code{0.4},
\code{0.6}, \code{0.8}, and \code{1}. They are stored as factor levels.}
\item{seed}{Three replicate-run identifiers: \code{1001}, \code{2001}, and
\code{3001}. A repeated seed does not guarantee identical provider output.}
}
}

\section{Temperature, seed, and the intended universe}{
Temperature is a controlled setting. Whether it is treated as fixed or random
in a reliability analysis depends on the intended universe of generalization.
If inference concerns exactly the observed temperature settings, an analyst
can declare \code{gt_reliability(fit, fixed = "temp")}. Generalizing beyond
those settings instead requires an explicit population and exchangeability
assumptions; selection by the researcher alone does not determine the choice.

The observed agreement among seed replicates changes across temperature.
The table gives the proportion of item-by-evaluator-by-prompt cells in which
all three seeds return the same label:

\tabular{lcccccc}{
  \strong{temperature} \tab 0 \tab 0.2 \tab 0.4 \tab 0.6 \tab 0.8 \tab 1 \cr
  Hate-Speech  \tab 0.915 \tab 0.862 \tab 0.837 \tab 0.817 \tab 0.780 \tab 0.733 \cr
  Mental-Health (nominal) \tab 0.914 \tab 0.842 \tab 0.835 \tab 0.789 \tab 0.749 \tab 0.678 \cr
  Drug-Review  \tab 0.840 \tab 0.767 \tab 0.711 \tab 0.686 \tab 0.631 \tab 0.581 \cr
}

These are descriptive observed-label agreement rates. Their differences
motivate checking the response and covariance model, but do not by themselves
establish that a latent seed variance is heterogeneous. For discrete outcomes,
changes in category probabilities can change observed agreement even with
constant latent random-effect variance. Agreement is below one at temperature
0, so that setting does not guarantee identical recorded labels across runs.

Declaring \code{fixed = "temp"} changes the reliability estimand after fitting;
it does not change the G-study likelihood or correct covariance misspecification.
A scientifically defined analysis within one temperature is one possible
sensitivity analysis. In that case, omit the now-constant temperature column
from the fitted facet declaration while recording the conditioned setting in
the analysis. A model explicitly allowing variation by temperature is another
possible approach, provided its implementation and assumptions are justified.
Neither treatment is selected automatically from this descriptive table.
}
\section{Dataset topics and outcome sets}{
\describe{
\item{Hate-Speech}{One ordinal outcome set. See the
\link[=gtheory_hate_speech]{Hate-Speech data topic} for category definitions
and the original corpus and annotation-study references.}
\item{Mental-Health}{Five outcome sets. See the
\link[=gtheory_mental_health]{Mental-Health data topic} for working-score
mappings, binary flags, unordered labels, and source references.}
\item{Drug-Review}{Two ordinal outcome sets. See the
\link[=gtheory_drug_review]{Drug-Review data topic} for holistic sentiment,
four aspect definitions, and source references.}
}
}
\section{Coding and use}{
The default \code{coding = "native"} preserves the binary, ordinal, or
unordered categorical endpoint where defined. The Mental-Health 7L and 3L
variants remain explicitly Gaussian working scores under both coding options;
they are not established clinical severity scales. Seven outcome sets also
support \code{coding = "manuscript"}, which reproduces the original Gaussian
working-score analysis. The nominal Mental-Health set has native coding only.
The eight sets are alternative views of three panels, not eight independent
datasets.

Use \code{gt_example()} to list the catalog and \code{gt_example(name)$data}
to access a table. Each panel has 21,600 rows, so every native discrete coding
exceeds the dense discrete engine's default limits by more than an order of
magnitude, and raising the limits does not make the dense engine practical at
that size. These are data resources, not full-panel discrete fitting examples:
use \code{gt_preflight()} before requesting a discrete fit, and do not remove
item interactions merely to obtain an accepted fit. Discrete demonstrations require a scientifically specified small
panel and supported source structure; successful loading alone does not
establish fitting feasibility. Numerical model assumptions and coefficient
scales are described in \code{\link{gt_fit}} and \code{\link{gt_reliability}}.
}
\source{
Liu's public OSF annotation deposit:

\doi{10.17605/OSF.IO/K9CAJ}.

The source files are:
\itemize{
\item \file{hate_labeling_final.csv}
\item \file{mh_labeling_final.csv}
\item \file{drug_labeling_final.csv}
}
Their checksums match the public deposit. Package resources retain only design
identifiers and modeled annotations; category types, working-score mappings,
and grouped flags are defined by \code{gt_example()}.

The deposit's data codebook licenses derived artifacts under CC BY 4.0.
The installed supporting files are:
\itemize{
\item \file{DATA_LICENSE.md}: attribution and modification details.
\item \file{extdata/manifest.csv}: source and resource checksums.
\item \file{DATASET_REFERENCES.bib}: the complete task bibliography.
}
}
\references{
Liu, J. (2026). \emph{LLM Annotation Reliability: A Generalizability Theory
Analysis of Hate Speech, Mental Health, and Drug Review Tasks}.
Open Science Framework, public annotation dataset.

\doi{10.17605/OSF.IO/K9CAJ}.

The three dedicated dataset topics provide the original corpus and related
annotation-study references.
}
\seealso{\code{\link{gt_example}},
\link[=gtheory_hate_speech]{Hate-Speech data},
\link[=gtheory_mental_health]{Mental-Health data},
\link[=gtheory_drug_review]{Drug-Review data}}
\examples{
gt_example()
x <- gt_example("hate_speech")
dim(x$data)
vapply(x$data[x$facets], nlevels, integer(1))
x$outcomes
system.file("DATASET_REFERENCES.bib", package = "Gtheory4LLM")
}
\keyword{datasets}
