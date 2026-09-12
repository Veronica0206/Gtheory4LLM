\name{gtheory_mental_health}
\alias{gtheory_mental_health}
\alias{mental_health_7L}
\alias{mental_health_3L}
\alias{mental_health_6flag}
\alias{mental_health_3group}
\alias{mental_health_nominal}
\docType{data}
\title{Synthetic Mental-Health Category and Flag Examples}
\description{Five toy outcome sets illustrating unordered categories, binary
flags, binary OR groups, and two numerical working-score mappings. All values
are synthetic. They are not clinical data, real text annotations, actual LLM
responses, or observations from the cited mental-health corpus.}
\format{Each call to \code{\link{gt_example}} returns a list with a
576-row \code{data} frame. Its shared factors identify 24 hypothetical items,
three generic evaluators, two prompts, two temperature settings, and two seeds.
See the \link[=gtheory_datasets]{dataset overview} for their levels.
Additional columns depend on the outcome set:
\describe{
\item{mental_health_nominal}{One unordered \code{label} factor with levels
NORMAL, STRESS, ANXIETY, DEPRESSION, BIPOLAR, PERSONALITY_DISORDER, SUICIDAL.
The categorical family uses softmax with NORMAL as reference. Native coding only.}
\item{mental_health_6flag}{Six integer 0/1 toy flags:
\itemize{
\item \code{depression}
\item \code{anxiety}
\item \code{suicidal}
\item \code{stress}
\item \code{bipolar}
\item \code{personality_disorder}
}
Native families are binary with probit links. A one is a simulated flag,
not evidence of symptoms or a diagnosis.}
\item{mental_health_3group}{Three integer 0/1 columns:
\itemize{
\item \code{stress}: the synthetic stress flag.
\item \code{anxiety_depression}: anxiety OR depression.
\item \code{bipolar_personality_suicidal}: bipolar OR personality-disorder
OR suicidal flags.
}
These groups may co-occur; they are not mutually exclusive categories.
Native families are binary with probit links.}
\item{mental_health_7L}{One integer \code{score}: NORMAL = 1, STRESS = 2,
ANXIETY = 3, DEPRESSION = 4, BIPOLAR = 5, PERSONALITY_DISORDER = 6,
SUICIDAL = 7. It is a Gaussian working score under both coding options.}
\item{mental_health_3L}{One integer \code{score}: NORMAL or STRESS = 1;
ANXIETY or DEPRESSION = 2; BIPOLAR, PERSONALITY_DISORDER, or SUICIDAL = 3.
It is a Gaussian working score under both coding options.}
}
Other list elements identify outcomes, families, design roles, coding, resource
path, notes, and synthetic provenance.}
\details{
The 7L/3L numerical mappings do not establish clinical severity order or equal
distances between categories. The nominal set preserves unordered identity.
The six binary flags are not diagnoses. The three-group binary set differs
from the single-outcome 3L working score.

For flags and groups, the legacy \code{coding = "manuscript"} option keeps
0/1 values but declares Gaussian working-score families. The 7L/3L sets are
Gaussian even under native coding. This compatibility argument applies to
synthetic values only and reproduces no manuscript observations or results.

The five representations share one hypothetical design. The nominal label
determines the 7L/3L mappings; the six generated flags determine the OR groups.
No observations, prevalence estimates, fitted parameters, texts, or actual
annotations were copied from any source study. These deterministic toy patterns
are not a parameter-recovery simulation. See \code{\link{gt_preflight}} for
structural and resource checks before fitting.
}
\source{Original synthetic observations authored by Jin Liu under GPL-3.
Public generator:
\preformatted{scripts/build_package_data.R}
The references below motivate
the affective-text annotation task and its corpus context. Neither supplied
observations for these synthetic tables. The common construction is described
in the \link[=gtheory_datasets]{dataset overview}.}
\references{
Sarkar, S. (n.d.). \emph{Sentiment Analysis for Mental Health}. Kaggle dataset;
accessed September 12, 2026.
\href{https://www.kaggle.com/datasets/suchintikasarkar/sentiment-analysis-for-mental-health}{Dataset record on Kaggle}.

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
groups <- gt_example("mental_health_3group")
str(groups$data[groups$outcomes])
working <- gt_example("mental_health_3L")
table(working$data$score)
}
\keyword{datasets}
