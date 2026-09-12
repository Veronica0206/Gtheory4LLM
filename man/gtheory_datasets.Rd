\name{gtheory_datasets}
\alias{Gtheory4LLM-datasets}
\alias{gtheory_datasets}
\docType{data}
\title{Synthetic LLM Task Examples: Design, Coding, and Background}
\description{Documents three synthetic task panels: Hate-Speech, Mental-Health,
and Drug-Review. Eight outcome sets and fifteen combinations of outcome set and
coding are available through \code{\link{gt_example}}. Every observation is
algorithmically simulated; none is an actual LLM response or source-study record.}
\details{
Each outcome set has 576 measurement rows: 24 hypothetical items crossed with
three generic evaluators, two generic prompts, two temperature-setting
identifiers, and two seed identifiers. Each item therefore has 24 measurements.
The rows are repeated measurements within a toy panel, not independent real
texts. The eight outcome sets are alternative representations of three
synthetic panels, not eight independent empirical samples.

The public generator uses deterministic bounded integer arithmetic. It does
not read source studies, fit models, draw from an estimated data-generating
distribution, call an LLM, or use observed prevalence or performance statistics.
These toy patterns demonstrate category handling and data structure. They are
not a parameter-recovery experiment or evidence about reliability in a real task.

No raw texts, human labels, clinical measurements, actual model identities,
prompt contents, API metadata, or private manuscript observations are included.
The task-specific papers and corpus references in the three dedicated help
topics motivate the task types only; they supplied none of the simulated rows.
}
\format{
Calling \code{gt_example(name)} returns a list. Its \code{data} element is a
data frame with five shared factor columns and the selected outcomes. Other
elements identify outcomes, families, design roles, coding, source, and notes.
Installed resources also contain \code{source_provenance}.
\describe{
\item{item}{24 hypothetical identifiers, \code{item_01} through \code{item_24}.}
\item{evaluator}{Three generic identifiers: \code{evaluator_1},
\code{evaluator_2}, and \code{evaluator_3}. These do not identify real models.}
\item{prompt}{Two generic identifiers: \code{prompt_1} and \code{prompt_2}.}
\item{temp}{Two factor levels: \code{temperature_1} and \code{temperature_2}.
These are abstract settings, not actual numeric generation temperatures.}
\item{seed}{Two factor levels: \code{seed_1} and \code{seed_2}. No random-number
generator was executed with these labels; they identify hypothetical repeats.}
}
}
\section{Outcome sets and coding}{
The \link[=gtheory_hate_speech]{Hate-Speech topic} describes one ordinal set.
The \link[=gtheory_mental_health]{Mental-Health topic} describes five sets:
unordered labels, six binary flags, three binary OR groups, and two Gaussian
working-score representations. The \link[=gtheory_drug_review]{Drug-Review
topic} describes holistic ordinal sentiment and four ordinal aspects.

\code{coding = "native"} preserves the declared binary, ordinal, or unordered
categories. The Mental-Health 7L/3L variants are explicitly Gaussian working
scores under both options, not validated clinical severity scales. The legacy
name \code{coding = "manuscript"} selects numeric-score compatibility for
seven sets. It does not retrieve manuscript observations or reproduce any
manuscript findings. The nominal set has native coding only.

Use \code{gt_example()} to list the catalog. Successful loading does not prove
fitting feasibility: random dimensions can exceed the dense discrete backend's
limits even in a 576-row panel. Inspect \code{\link{gt_preflight}} with the
intended family and source design. Reliability scales and numerical acceptance
requirements are described in \code{\link{gt_reliability}}.
}
\source{
Original synthetic data authored by Jin Liu, distributed under GPL-3.
The public repository script \file{scripts/build_package_data.R} regenerates
the resources using deterministic integer arithmetic. Its \code{--verify-only}
option checks expected objects and the manifest without modifying files.
Generator identity is stored in \code{source_provenance}; resource checksums
are recorded in the installed \file{extdata/manifest.csv}.

The installed \file{DATASET_REFERENCES.bib} contains six background references:
three task-specific annotation papers and three corpus references. These
references are not data provenance for the synthetic observations.
}
\seealso{\code{\link{gt_example}}, \code{\link{gtheory_hate_speech}},
\code{\link{gtheory_mental_health}}, \code{\link{gtheory_drug_review}}}
\examples{
gt_example()
x <- gt_example("hate_speech")
dim(x$data)
vapply(x$data[c(x$object, x$facets)], nlevels, integer(1))
x$source_provenance$data_kind
system.file("DATASET_REFERENCES.bib", package = "Gtheory4LLM")
}
\keyword{datasets}
