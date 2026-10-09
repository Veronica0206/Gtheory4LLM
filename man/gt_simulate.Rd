\name{gt_simulate}
\alias{gt_simulate}
\title{Simulate a New Balanced Gaussian Annotation Panel}
\usage{
gt_simulate(fit, n_items, counts = NULL, seed, components = NULL,
  means = NULL, max_rows = 1000000L)
}
\arguments{
  \item{fit}{An explicitly numerically accepted Gaussian \code{gt_fit} object,
  retaining its covariance structures and either modelled data or panel summary.}
  \item{n_items}{Number of new distinct objects, an integer of at least two.}
  \item{counts}{Optional named integer counts of at least two for instrumentation
  facets. Unspecified counts retain the fitted panel counts. Counts for a nested
  child describe its local coded levels within each parent combination.}
  \item{seed}{Required integer seed between zero and \code{.Machine$integer.max}.
  The caller's random-number generator kind and state are restored, including
  when no random seed existed before the call.}
  \item{components}{Optional complete named list of covariance matrices, one for
  every retained source including \code{Residual}. Each matrix must be symmetric,
  positive semidefinite, and preserve its fitted diagonal, unstructured, or pooled
  structure. Fully unnamed axes use outcome order; labelled axes must name every
  outcome exactly once. The fitted components are used when \code{NULL}.}
  \item{means}{Optional finite numeric vector naming every outcome exactly once.
  Defaults to the fitted outcome means.}
  \item{max_rows}{Maximum generated rows, between one and one million. A separate
  estimated 512 MiB workspace limit also applies. Neither limit changes fitting
  controls or permits an unsupported model.}
}
\description{
Generates fresh independent Gaussian random effects for objects, instrumentation
levels, source interactions, and residuals under a fitted or specified parameter
scenario. Distinct item count and instrumentation allocation are separate inputs.
}
\details{
The initial scope is a complete balanced coded panel with one outcome vector per
cell and no batch declaration. Univariate and multivariate Gaussian models,
explicit random sources, and declared parent-scoped grouping terms are supported.
Discrete outcomes, incomplete panels, within-cell replication, and batch layouts
are refused. These restrictions match the supported Gaussian preparation model;
globally unique physical child labels are not generated.

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
A data frame with integer coded object and facet columns and numeric outcome
columns. Its \code{simulation} attribute records the seed, counts, means,
covariance matrices, covariance structures, parameter source, and interpretation.
The generated covariance matrices, including numerical tolerance adjustments,
are recorded explicitly.
}
\examples{
set.seed(91)
panel <- expand.grid(item = 1:20, evaluator = 1:3)
panel$score <- rnorm(20)[panel$item] + rnorm(3)[panel$evaluator] +
  rnorm(nrow(panel))
fit <- gt_fit(panel, "score", gt_design("item", "evaluator"))
if (isTRUE(fit$numerically_accepted)) {
  simulated <- gt_simulate(fit, n_items = 30,
    counts = c(evaluator = 4), seed = 2026)
  head(simulated)
}
}
\seealso{\code{\link{gt_pilot_plan}}, \code{\link{gt_fit}}, \code{\link{gt_dstudy}}}
