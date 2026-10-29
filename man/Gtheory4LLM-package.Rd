\name{Gtheory4LLM-package}
\alias{Gtheory4LLM-package}
\alias{Gtheory4LLM}
\docType{package}
\title{Generalizability Theory for LLM Subjective Tasks}
\description{Studies the reliability and generalizability of subjective judgments produced by large language models (LLMs), including annotation, rating, and structured LLM-as-a-judge tasks. Supported balanced decision studies compare projected reliability across evaluator, prompt, and repeated-run allocations.}
\details{Use \code{gt_design()} to declare random sources, \code{gt_preflight()} to inspect design and resource limits, \code{gt_family()} to distinguish the observation family, and \code{gt_fit()} to estimate a model. Inspect \code{gt_diagnostics()} before interpreting coefficients, then use \code{gt_dstudy()} to compare an allocation grid with a substantively chosen reliability target.

The modeling interface supports selected item interactions, crossed and explicitly nested sources, and joint multivariate source covariances. Measurement roles are specified by the research design; facet names do not automatically impose nesting or remove item interactions. Traditional method-of-moments G theory already includes random effects and crossed/nested designs. This package integrates design-specific covariance models, outcome-appropriate likelihoods, and supported decision studies; superiority in estimation accuracy requires comparative validation.

Gaussian outcomes use exact balanced likelihood by default. A bounded univariate lme4 option fits missing whole cells and checks an independent observed-row Gaussian likelihood. Binary, ordinal, and unordered categorical outcomes use their specified observation distributions with Gaussian latent random effects, fitted by dense or sparse calculations of the same first-order Laplace approximation. Joint Gaussian models and joint discrete models are supported; a joint Gaussian-discrete likelihood is not implemented. Selecting sparse algebra does not establish full-panel performance or approximation accuracy.

Observed Gaussian reliability and latent binary, ordinal or nominal reliability are distinct estimands. A nominal outcome's latent coefficients are the mean and range of the generalized eigenvalues over its category contrasts, invariant to the reference category under an exchangeable or unstructured covariance. Ordinary analytic coefficients require a complete balanced coded panel; observed-row Gaussian fits instead require an explicit projection to an intended complete balanced allocation. Projections depend on fitted source covariances and the specified universes of evaluators and prompts. Adding arbitrarily chosen LLMs does not ensure those assumptions hold. Available delta-method intervals propagate component-estimation uncertainty under the declared model, not violations of facet exchangeability or annotation accuracy against human judgments. Coefficients alone do not select a minimum-cost allocation. Default discrete delta-method intervals require optional full observed information that passes numerical acceptance, boundary, step-stability and curvature checks; their asymptotic interpretation is conditional on first-order Laplace, with finite-sample coverage unestablished. An explicit \code{\link{gt_bootstrap}} instead supplies object-bootstrap intervals without observed information, conditional on the observed instrumentation levels and accepted refits.

The study-planning functions distinguish pilot item count, annotations per
item and items per request. Use \code{\link{gt_plan}} for bounded cost-aware
allocation search with explicit user-supplied prices, and
\code{\link{gt_batch_reliability}} for fixed-layout Gaussian batch targets.
\code{\link{gt_categorical_target}} separately defines observed-score,
relabeling-invariant category-vector and plurality-decision targets by repeated
panel simulation. Decision agreement is accompanied by decision diversity;
perfect agreement alone does not establish discrimination. Categorical target
planning holds parameters and any fitted call grouping fixed, and reports
Monte Carlo integration errors rather than parameter confidence intervals.
These do not infer annotation accuracy, optimal provider identities or a new
batch-size effect from an existing fit.

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

The OpenMx Gaussian path can report asymptotic Wald standard errors for source variance
components and delta-method intervals for G and Phi; the lme4 path does not. See
\code{\link{gt_reliability}}. Model-based Gaussian and categorical simulation
are available through \code{\link{gt_simulate}}.

Use \code{\link{gt_pilot_plan}} to study interval precision for Gaussian,
binary or ordinal outcomes. Its route for categorical point estimates also
supports nominal outcomes and fixed calls. It reports acceptance, availability
and conditional error summaries. This
route supplies no parameter intervals or interval-width criterion.
These functions do not provide calibrated bootstrap intervals.
\code{\link{gt_bootstrap}} resamples the objects of an accepted fit and gives
percentile or BCa intervals for components, coefficients and D studies,
conditional on the observed instrumentation levels; their coverage has been
assessed only in a Gaussian pilot, where it fell below the nominal level. Discrete observed information is opt-in, and unsupported or
unusable uncertainty remains explicitly unavailable rather than imputed.

\subsection{Why this package declares R (>= 4.5.0)}{
Nothing in this package's own R code needs R 4.5. The floor comes from
the OpenMx version it supports. OpenMx 2.22.11 calls \code{Rf_isDataFrame}, a C
entry point R introduced in 4.5.0, while declaring only \code{R (>= 3.5.0)}
for itself. Declaring the floor here is what prevents an
install on an older R from failing later with an unexplained compilation error.
Earlier combinations such as R 4.3 with OpenMx 2.21.11 have been reported to
run this package's checks; that pairing is not part of its validated gate. To
use one, install from source with a relaxed floor, or load the implementation
directly by sourcing \file{load_functions.R}, which imposes no version
requirement of its own.
}

The vignette \dQuote{How many evaluators, prompts, and runs?} demonstrates
fitting through reliability, intervals, fixed facets, and a decision study
using synthetic continuous judgments. Open it with \code{browseVignettes()}.
The installed \file{doc/LLM-workflow.R} is the same workflow as a script.}
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
