\name{gt_simulate}
\alias{gt_simulate}
\title{Simulate a New Gaussian or Categorical Annotation Panel}
\usage{
gt_simulate(fit, n_items, counts = NULL, seed, components = NULL,
  means = NULL, max_rows = 1000000L)
}
\arguments{
  \item{fit}{An explicitly numerically accepted \code{gt_fit} object for Gaussian
  outcomes or for binary, ordinal, and nominal categorical outcomes. Retain the
  covariance structures, family definitions and either modelled data or panel
  summary; categorical fits also need their latent-dimension mapping and any
  fitted thresholds. Gaussian and categorical outcomes cannot be mixed.}
  \item{n_items}{Number of new distinct objects, an integer of at least two.
  A categorical fit with modelled fixed calls retains its fitted item count and
  grouping; the coded objects receive fresh effects.}
  \item{counts}{Optional named positive integer instrumentation counts for a
  categorical future panel. Gaussian simulation still requires at least two
  levels per facet. Unspecified counts retain the fitted panel counts. Counts for a nested
  child describe its local coded levels within each parent combination.}
  \item{seed}{Required integer seed between zero and \code{.Machine$integer.max}.
  The caller's random-number generator kind and state are restored, including
  when no random seed existed before the call.}
  \item{components}{Optional complete named list of covariance matrices, one for
  every retained source. Gaussian models include \code{Residual}; categorical
  models have no Gaussian residual component. Each matrix must be symmetric,
  positive semidefinite, and preserve its fitted structure. Gaussian matrix axes
  identify outcomes; categorical axes identify the fitted latent dimensions,
  including one contrast per nonreference nominal category. Fully unnamed axes
  follow fitted order; labelled axes must name every axis exactly once. The
  fitted components are used when \code{NULL}.}
  \item{means}{Optional finite named numeric vector. Gaussian entries name every
  outcome; categorical entries name every fitted latent dimension. Defaults to
  the fitted means or intercepts. Ordinal intercepts must remain zero because
  their location is represented by the retained fitted thresholds.}
  \item{max_rows}{Maximum generated rows, between one and one million. A separate
  estimated 512 MiB workspace limit also applies. Neither limit changes fitting
  controls or permits an unsupported model.}
}
\description{
Generates a complete future coded panel under a fitted or specified parameter
scenario. Gaussian random effects preserve covariance between outcomes or
latent dimensions. Categorical observations use their fitted links, thresholds
and nominal reference contrasts, retaining the declared category labels.
Distinct item count and instrumentation allocation are separate inputs.
}
\details{
Gaussian simulation requires a complete balanced fitted panel with one outcome
vector per cell and no batch declaration. Categorical simulation supports
univariate and joint binary, ordinal and nominal outcomes, explicit random
sources, parent-scoped grouping terms and the declared equal cell replication.
Missing whole cells in an accepted categorical fit do not prevent generating a
complete future allocation; no original missing values are imputed. No globally
unique physical child labels are generated.
One future level of a categorical instrumentation facet is allowed, although
estimating that facet's variance in a pilot requires at least two observed
levels. \code{gt_pilot_plan()} therefore requires at least two levels in its
pilot grid while allowing one level in the separately specified target protocol.

For categorical models, source effects are Gaussian on the fitted latent
predictor scale. Binary probabilities use the fitted probit or logit link;
ordinal probabilities are adjacent cumulative-probability differences at the
fitted thresholds; nominal probabilities use reference-category softmax.
Observations and outcomes are independent conditional on those predictors;
between-outcome dependence arises from the source covariance matrices. Nominal
labels receive no arbitrary numeric scores. A mixed categorical model can have
different links and numbers of categories across its outcomes.

Modelled equal fixed calls are supported for categorical fits with one row per
cell. Each call effect is shared by its retained group of items under one
complete facet condition. Instrumentation counts can change, but item count,
group membership and batch size remain fixed. Recorded call and order columns
are generated when declared. Unmodelled batch declarations, positional effects,
variable calls and regrouping are refused.

Zero and singular positive semidefinite components are allowed. Only negative
eigenvalues within a relative numerical tolerance of \eqn{10^{-10}} (using a
unit minimum scale) are set to zero. No positive interior jitter is added. A
degenerate scenario can generate data that fitting subsequently refuses.

Every facet is sampled afresh; the function does not reuse estimated random
effects or condition on observed evaluator or item realizations. This is design
simulation. A fitted-model parameter scenario can also provide data for an
explicitly designed parametric-bootstrap analysis, but this function performs no
refitting, interval construction, boundary calibration, or coverage assessment.
}
\value{
A data frame with integer coded object and facet columns. Gaussian outcomes are
numeric; binary and nominal outcomes are factors, and ordinal outcomes are
ordered factors. All declared category levels are retained even if a simulated
sample contains no observations in one of them. Its \code{simulation} attribute
records the seed, counts, means, covariance matrices, covariance structures,
parameter source, and interpretation. Categorical results also record families,
thresholds, latent dimensions, replication and any fixed-call layout.
The generated covariance matrices, including numerical tolerance adjustments,
are recorded explicitly.
}
\examples{
set.seed(91)
panel <- expand.grid(item = 1:20, evaluator = 1:3)
panel$score <- rnorm(20)[panel$item] + rnorm(3)[panel$evaluator] +
  rnorm(nrow(panel))
fit <- gt_fit(panel, "score", gt_design("item", "evaluator"))
if (isTRUE(gt_diagnostics(fit)$numerically_accepted)) {
  simulated <- gt_simulate(fit, n_items = 30,
    counts = c(evaluator = 4), seed = 2026)
  head(simulated)
}
}
\seealso{\code{\link{gt_pilot_plan}}, \code{\link{gt_fit}}, \code{\link{gt_dstudy}}}
