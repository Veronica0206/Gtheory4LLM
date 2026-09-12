\name{gtheory_mental_health}
\alias{gtheory_mental_health}
\alias{mental_health_7L}
\alias{mental_health_3L}
\alias{mental_health_6flag}
\alias{mental_health_3group}
\alias{mental_health_nominal}
\docType{data}
\title{LLM Mental-Health Text Annotations in Five Outcome Sets}
\description{Five representations of repeated LLM annotations of the same
100 text items from the Sentiment Analysis for Mental Health corpus: unordered
labels, six binary flags, three binary groups, and two historical working-score
codings. Load each modeling table with \code{\link{gt_example}}.}
\format{Each call returns a list whose \code{data} element has 21,600 rows.
The five shared factor columns are \code{item}, \code{evaluator}, \code{prompt},
\code{temp}, and \code{seed}: 100 items crossed with four evaluators, three
prompts, six temperatures, and three replicate seeds. Stored factor levels
are documented in the \link[=gtheory_datasets]{dataset overview}.
Additional columns depend on the requested set:
\describe{
\item{mental_health_nominal}{One \code{label} column, an unordered factor with
levels NORMAL, STRESS, ANXIETY, DEPRESSION, BIPOLAR, PERSONALITY_DISORDER, and
SUICIDAL. The categorical family uses a softmax link and NORMAL as reference.
Only \code{coding = "native"} is available.}
\item{mental_health_6flag}{Six integer 0/1 columns:
\itemize{
\item \code{depression}
\item \code{anxiety}
\item \code{suicidal}
\item \code{stress}
\item \code{bipolar}
\item \code{personality_disorder}
}
A value of one indicates the corresponding LLM-assigned evidence flag.
Native families are binary with probit links.}
\item{mental_health_3group}{Three integer 0/1 columns:
\itemize{
\item \code{stress}: the original stress flag.
\item \code{anxiety_depression}: anxiety OR depression.
\item \code{bipolar_personality_suicidal}: the logical OR of bipolar,
personality-disorder, and suicidal flags.
}
The groups may co-occur; they are not mutually exclusive categories.
Native families are binary with probit links.}
\item{mental_health_7L}{One integer \code{score} column: NORMAL = 1,
STRESS = 2, ANXIETY = 3, DEPRESSION = 4, BIPOLAR = 5,
PERSONALITY_DISORDER = 6, SUICIDAL = 7. This is a Gaussian working score under
both coding options.}
\item{mental_health_3L}{One integer \code{score} column: NORMAL or STRESS = 1;
ANXIETY or DEPRESSION = 2; BIPOLAR, PERSONALITY_DISORDER, or SUICIDAL = 3.
This is a Gaussian working score under both coding options.}
}
The loader also returns outcome names, families, design roles, coding, source,
and interpretation notes; installed resources include \code{source_provenance}.}
\details{The 7L and 3L codings reproduce study-defined numerical analyses.
They do not establish a clinical severity order or equal distances between
mental-health categories. The nominal set preserves the unordered label
identity. The six flags describe requested textual evidence and are not
clinical diagnoses or a set of mutually exclusive classifications. The
three-group binary set differs from the single-outcome 3L working score.

For the six-flag and three-group sets, \code{coding = "manuscript"} retains
the same 0/1 values but declares Gaussian working-score families. The two
working-score sets remain Gaussian even with \code{coding = "native"}.

All sets reuse LLM-generated annotations of the same sampled items, not
independent samples or the original corpus's reference status labels.
Original texts, corpus reference labels, probability vectors, and API
metadata are not bundled. The stored tables have no missing modeling values
after the original preprocessing, which allowed NORMAL defaults for items
omitted from an otherwise parsed batch. Defaults are not separately identified
in these modeling resources. See the \link[=gtheory_datasets]{dataset overview}
for common provenance and the full-panel discrete fitting limit.}
\source{Derived from \file{mh_labeling_final.csv} in the public OSF annotation
deposit (Liu, 2026).

\doi{10.17605/OSF.IO/K9CAJ}.

Sarkar's corpus is the original text source. Liu's
public annotation study describes the associated multi-view labeling
work; its current title is listed below. The common G-theory source is cited
in the \link[=gtheory_datasets]{dataset overview}.}
\references{
Sarkar, S. (n.d.). \emph{Sentiment Analysis for Mental Health}. Kaggle dataset;
accessed September 12, 2026.
The original source URL is retained in the installed task bibliography.

Liu, J. (2025). LLM-Based Annotation as Multi-View Supervision for Affective
Text Classification: Soft Labels, Multi-Task Decomposition, and Entropy
Diagnostics. \emph{SSRN working paper}, 5964738; revised March 19, 2026.
\doi{10.2139/ssrn.5964738}.
}
\seealso{\link[=gtheory_datasets]{Dataset overview}, \code{\link{gt_example}},
\code{\link{gt_family}}, \code{\link{gt_score}}}
\examples{
nominal <- gt_example("mental_health_nominal")
str(nominal$data$label)
table(nominal$data$label)

flags <- gt_example("mental_health_6flag")
str(flags$data[flags$outcomes])
table(flags$data$depression, flags$data$anxiety)

groups <- gt_example("mental_health_3group")
str(groups$data[groups$outcomes])
working <- gt_example("mental_health_3L")
table(working$data$score)
}
\keyword{datasets}
