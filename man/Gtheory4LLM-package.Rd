\name{Gtheory4LLM-package}
\alias{Gtheory4LLM-package}
\alias{Gtheory4LLM}
\docType{package}
\title{Generalizability Theory for LLM Subjective Tasks}
\description{Studies the reliability and generalizability of subjective judgments produced by large language models (LLMs), including annotation, rating, and structured LLM-as-a-judge tasks. Supported balanced decision studies compare projected reliability across evaluator, prompt, and repeated-run allocations.}
\details{Use \code{gt_design()} to declare random sources, \code{gt_preflight()} to inspect design and resource limits, \code{gt_family()} to distinguish the observation family, and \code{gt_fit()} to estimate a model. Inspect \code{gt_diagnostics()} before interpreting coefficients, then use \code{gt_dstudy()} to compare an allocation grid with a substantively chosen reliability target.

The modeling interface supports selected item interactions, crossed and explicitly nested sources, and joint multivariate source covariances. Measurement roles are specified by the research design; facet names do not automatically impose nesting or remove item interactions. Traditional method-of-moments G theory already includes random effects and crossed/nested designs. This package integrates design-specific covariance models, outcome-appropriate likelihoods, and supported decision studies; superiority in estimation accuracy requires comparative validation.

Gaussian outcomes use exact balanced likelihood. Binary, ordinal, and unordered categorical outcomes use their specified observation distributions with Gaussian latent random effects, fitted by a dense first-order Laplace approximation. Joint Gaussian models and joint discrete models are supported; a joint Gaussian-discrete likelihood is not implemented.

Observed Gaussian reliability and latent binary or ordinal reliability are distinct estimands. Scalar nominal reliability is not implemented. Decision studies require a complete balanced coded panel. Their projections depend on fitted source covariances and the specified universes of evaluators and prompts. Adding arbitrarily chosen LLMs does not ensure those assumptions hold. Projections do not quantify sampling uncertainty, automatically find a minimum allocation, or establish annotation accuracy against human judgments.

Three synthetic example panels illustrate hate-speech, mental-health, and
drug-review annotation tasks, with eight outcome sets. These are software
examples, not real LLM outputs, source-study records, or clinical data.
The \link[=gtheory_datasets]{dataset overview} and dedicated
\link[=gtheory_hate_speech]{Hate-Speech},
\link[=gtheory_mental_health]{Mental-Health}, and
\link[=gtheory_drug_review]{Drug-Review} topics describe variables,
category mappings, generation, and the task literature. The cited studies
provide background only; they supplied none of the simulated observations.

This package is distributed under GPL-3. Numerical acceptance does not establish
Laplace approximation adequacy, a global optimum, or empirical validity.
Bootstrap, jackknife, and general uncertainty intervals are not implemented.
The installed \file{doc/LLM-workflow.R} tutorial demonstrates fitting through
reliability and a decision study using synthetic continuous judgments.}
\references{
Brennan, R. L. (2001). \emph{Generalizability Theory}. Springer.
\doi{10.1007/978-1-4757-3456-0}.

Jiang, Z., Raymond, M., Shi, D., and DiStefano, C. (2020).
Using a linear mixed-effect model framework to estimate multivariate
generalizability theory parameters in R. \emph{Behavior Research Methods},
52, 2383--2393. \doi{10.3758/s13428-020-01399-z}.
}
\author{Jin Liu (author and maintainer), \email{Veronica.Liu0206@gmail.com}}
\seealso{\code{\link{gt_design}}, \code{\link{gt_preflight}}, \code{\link{gt_fit}}, \code{\link{gt_dstudy}}, \code{\link{gt_example}}, \code{\link[stats]{glm}}}
