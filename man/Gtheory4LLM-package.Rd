\name{Gtheory4LLM-package}
\alias{Gtheory4LLM-package}
\alias{Gtheory4LLM}
\docType{package}
\title{Generalizability Theory for LLM Subjective Tasks}
\description{Studies the reliability and generalizability of subjective judgments produced by large language models (LLMs), including annotation, rating, and structured LLM-as-a-judge tasks. Supported balanced decision studies compare projected reliability across evaluator, prompt, and repeated-run allocations.}
\details{Use \code{gt_design()} to declare random sources, \code{gt_preflight()} to inspect design and resource limits, \code{gt_family()} to distinguish the observation family, and \code{gt_fit()} to estimate a model. Inspect \code{gt_diagnostics()} before interpreting coefficients, then use \code{gt_dstudy()} to compare an allocation grid with a substantively chosen reliability target.

The modeling interface supports selected item interactions, crossed and explicitly nested sources, and joint multivariate source covariances. Measurement roles are specified by the research design; facet names do not automatically impose nesting or remove item interactions. Traditional method-of-moments G theory already includes random effects and crossed/nested designs. This package integrates design-specific covariance models, outcome-appropriate likelihoods, and supported decision studies; superiority in estimation accuracy requires comparative validation.

Gaussian outcomes use exact balanced likelihood. Binary, ordinal, and unordered categorical outcomes use their specified observation distributions with Gaussian latent random effects, fitted by a dense first-order Laplace approximation. Joint Gaussian models and joint discrete models are supported; a joint Gaussian-discrete likelihood is not implemented.

Observed Gaussian reliability and latent binary or ordinal reliability are distinct estimands. Scalar nominal reliability is not implemented. Decision studies require a complete balanced coded panel. Their projections depend on fitted source covariances and the specified universes of evaluators and prompts. Adding arbitrarily chosen LLMs does not ensure those assumptions hold. Gaussian projections carry delta-method intervals for estimation uncertainty in the fitted source covariances; they do not quantify sampling uncertainty in the facet populations, automatically find a minimum allocation, or establish annotation accuracy against human judgments. Discrete projections are point estimates only.

Three publicly archived LLM annotation panels cover hate-speech, mental-health,
and drug-review tasks, with eight outcome sets and fifteen response codings.
The \link[=gtheory_datasets]{dataset overview} and dedicated
\link[=gtheory_hate_speech]{Hate-Speech},
\link[=gtheory_mental_health]{Mental-Health}, and
\link[=gtheory_drug_review]{Drug-Review} topics describe variables, category
mappings, preprocessing, and source and annotation-study references.
The package contains design identifiers and modeled annotations from the
public OSF deposit, \doi{10.17605/OSF.IO/K9CAJ}.

Package code is distributed under GPL-3; real annotation data retain the
CC BY 4.0 license in the public deposit's codebook. See \file{DATA_LICENSE.md}.
Numerical acceptance does not establish
Laplace approximation adequacy, a global optimum, or empirical validity.

Gaussian fits report asymptotic Wald standard errors for their source variance
components and delta-method intervals for G and Phi; see
\code{\link{gt_reliability}}. Bootstrap and jackknife intervals are not
implemented, and the discrete Laplace engine reports point estimates only.

\subsection{Why this package declares R (>= 4.5.0)}{
Nothing in this package's own R code needs R 4.5. The floor is inherited from
its supported OpenMx version: OpenMx 2.22.11 calls the \code{Rf_isDataFrame} C
entry point that R introduced in 4.5.0, while declaring only
\code{R (>= 3.5.0)} itself. Declaring the floor here is what prevents an
install on an older R from failing later with an unexplained compilation error.
Earlier combinations such as R 4.3 with OpenMx 2.21.11 have been reported to
run this package's checks; that pairing is not part of its validated gate. To
use one, install from source with a relaxed floor, or load the implementation
directly with \code{source("load_functions.R")}, which imposes no version
requirement of its own.
}

The vignette \dQuote{How many evaluators, prompts, and runs?} demonstrates
fitting through reliability, intervals, fixed facets, and a decision study
using synthetic continuous judgments; \code{browseVignettes("Gtheory4LLM")}
opens it, and \file{doc/LLM-workflow.R} is the same workflow as a runnable
script.}
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
