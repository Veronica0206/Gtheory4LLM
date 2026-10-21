\name{gaussian_observed}
\alias{gaussian_observed}
\title{Bounded Gaussian Fitting with Missing Whole Cells}
\description{An explicit observed-row option fits one Gaussian outcome through lme4 and checks its ML or REML criterion against an independent dense covariance likelihood.}
\details{
Request \code{gt_control(gaussian = list(engine = "lme4", panel = "observed"))}.
The default \code{panel = "complete"} retains the balanced factorial-contrast
workflow. The observed-row option does not impute omitted cells, replace missing
outcomes, aggregate repeated observations, or alter the declared random sources.
Each retained full cell must contain exactly one finite numeric outcome.
The object and every instrumentation facet must have at least two observed
levels. Joint outcomes, unequal replication, within-cell replication and
declared batch effects are not supported by this option.

For observed rows, the model is
\deqn{y = X\beta + \sum_s Z_s u_s + \epsilon,\qquad
V = \sum_s \sigma_s^2 Z_s Z_s' + \sigma_e^2 I.}
There is one fixed intercept. Random-source grouping matrices follow the
declared source terms. ML profiles the intercept; REML additionally includes
\eqn{\log|X'V^{-1}X|} using the unscaled intercept column, matching lme4's
criterion. The check uses only retained rows and independent dense Cholesky
calculations, while lme4 uses its mixed-model representation.

The source and residual covariance kernels must be linearly independent in
the observation space after removing the intercept. A failed or numerically
near-dependent kernel check is a refusal before fitting. This algebraic check
does not establish adequate sample size, precision, recovery or interval
coverage. Numerical acceptance still requires optimizer completion without
convergence warnings, constrained stationarity, a reproducing restart, and
agreement with the independent likelihood at the fitted parameters.
The lme4 path does not compute source-variance standard errors or coefficient
intervals.

\strong{Resources.} \code{max_observed_rows = 1000} and
\code{max_preparation_bytes = 512 * 1024^2} bound the dense reference.
The allocation estimate includes covariance kernels and identification
working space, but excludes caller data and lme4 objects. Changing these
limits does not establish validated behavior at the larger size.

\strong{Interpretation.} Likelihood inference assumes the omitted whole cells
are ignorable for the declared Gaussian model. The software cannot establish
this assumption from the retained rows. In particular, omission depending on
unobserved outcomes can bias component estimates. Levels never observed
cannot be recovered by declaring them in a factor.

Fitting an incomplete panel does not supply analytic reliability for its
irregular observed allocation. Ordinary \code{gt_reliability()} remains
unavailable. A separately requested balanced D-study projection describes an
intended complete allocation in the same facet universes, assuming the same
source variances. It is not a coefficient for the incomplete observations.
The fit records this distinction and its assumptions in \code{projection},
and records \code{design$panel_type = "observed"}. Its prepared metadata retain
resource and kernel-identification diagnostics, without another copy of the
raw outcomes or dense kernels.
}
\seealso{\code{\link{gt_fit}}, \code{\link{gt_control}}, \code{\link{gt_dstudy}}}
\examples{
if (requireNamespace("lme4", quietly = TRUE)) {
  set.seed(1317)
  d <- expand.grid(item = 1:24, rater = 1:5)
  d$y <- 8 + rnorm(24, sd = 2)[d$item] +
    c(-2, -.8, .1, 1, 2.1)[d$rater] + rnorm(nrow(d), sd = .7)
  observed <- d[-seq(4L, nrow(d), by = 7L), ]
  fit <- gt_fit(observed, y ~ item + rater, measured = "item",
    control = gt_control(gaussian = list(engine = "lme4", panel = "observed")))
  gt_components(fit)
  gt_diagnostics(fit)
}
}
