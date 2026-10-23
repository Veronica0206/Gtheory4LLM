\name{gt_categorical_target}
\alias{gt_categorical_target}
\alias{as.data.frame.gt_categorical_target}
\alias{print.gt_categorical_target}
\title{Integrate Explicit Repeated-Panel Categorical Targets}
\description{Projects observed-score, category-vector or plurality-decision
targets by drawing independent pairs of complete future panels from an
accepted categorical fit. The fit is held fixed.}
\usage{
gt_categorical_target(fit, target = c("score", "category_vector", "decision"),
  counts = NULL, scores = NULL, n_items = 200L, replications = 40L,
  seed, max_rows = 100000L, outcome = NULL)
\method{as.data.frame}{gt_categorical_target}(x, row.names = NULL,
  optional = FALSE, ...)
\method{print}{gt_categorical_target}(x, ..., digits = 4L)
}
\arguments{
\item{fit}{A numerically accepted binary, ordinal, nominal or joint categorical
\code{gt_fit}. Mixed Gaussian/categorical fits are not supported.}
\item{target}{\code{"score"} for the mean of explicitly scored responses,
\code{"category_vector"} for the vector of empirical category proportions,
or \code{"decision"} for repeated-panel plurality agreement.}
\item{counts}{Named future facet counts, each at least one; omitted facets
retain their fitted counts. All instrumentation facets are random.}
\item{scores}{Named numeric category scores for a single selected outcome,
or a named list of these vectors by outcome. Binary outcomes default to
0 and 1 in the declared level order. Ordinal outcomes require explicit,
strictly increasing scores. Nominal outcomes use the vector target.}
\item{n_items}{Objects drawn per integration panel, at least two. This
controls integration precision, not the amount of pilot information.
For modelled calls it must equal the fitted object count, retaining its
fixed equal call membership.}
\item{replications}{Independent panel pairs, from 2 to 10000. Two permits
computation but does not imply adequate integration precision.}
\item{seed}{Required nonnegative integer seed. The caller's RNG is restored.}
\item{max_rows}{Maximum rows per simulated panel, no greater than one million.
The function also limits all generated rows to ten million and estimated
workspace to 512 MiB.}
\item{outcome}{Exact outcome names to report; \code{NULL} selects all.
All fitted dimensions are simulated so their joint law is preserved.}
\item{x}{A \code{gt_categorical_target} object.}
\item{row.names}{Optional data-frame row names.}
\item{optional}{Accepted for generic compatibility.}
\item{digits}{Significant digits for printing.}
\item{...}{Reserved for generic compatibility.}
}
\details{
Each panel pair shares only the object's main latent random effect.
Instrumentation, object-by-instrumentation interactions, and modelled calls
are independently redrawn between panels. Dependence within a panel and
between outcomes is retained. This defines a population of exchangeable
objects and instrumentation levels under the fitted model; it does not
condition on fitted random-effect modes or on named observed raters.

For a scalar panel score \eqn{S}, the target is
\deqn{\mathrm{Var}\{\mathrm{E}(S\mid U)\}/\mathrm{Var}(S),}
where \eqn{U} is the stable object effect. Equivalently the numerator is
the covariance between independent repeat scores given \eqn{U}.
Random instrumentation shifts enter total variance. This is an absolute
repeated-panel score ratio, not the relative latent G coefficient.
Conditional response means and second moments are integrated analytically
given the sampled effects to reduce Monte Carlo noise.

For category-proportion vector \eqn{P}, replace each variance by the trace
of its covariance matrix. This ratio is invariant to a permutation of
category coordinates and assigns no artificial numeric distances to
unordered labels. It is not Krippendorff's alpha or a chance-corrected
agreement coefficient. Positive affine transformations of scalar scores
leave the score ratio unchanged.

The decision target is the probability that the plurality category agrees
between panels. Ties are broken uniformly and independently in each panel;
the tie randomness is integrated exactly. It reports the marginal decision
probabilities and \code{decision_diversity}, one minus their squared sum.
A constant decision can have agreement one and diversity zero. Agreement
is not discrimination, correctness, or validity against human judgments.
Other decision rules and fixed-facet targets are not implemented.

Monte Carlo standard errors use independent entire panel pairs as the
replication units, because items within one panel share instrumentation.
Ratio standard errors use a delta method on these replicate moments.
They quantify numerical integration error at the fitted parameter values,
not estimation uncertainty, coverage, or future-panel prediction.
No parameter confidence interval is returned. Ratios with unresolved
denominators or estimates outside [0,1] remain unavailable; their raw
estimates and reasons are retained. Increase integration precision and
inspect the model rather than treating a refused estimate as zero.

With weak positive object signal, a finite integration budget can return many
unavailable ratios. Summarizing only the available ratios can then select
upward-biased estimates, even when their conditional error bands appear
adequate. Retain every attempted seed and its availability; do not replace
refused runs or clip their raw estimates into [0,1]. More objects within a panel
cannot remove Monte Carlo variation from shared instrumentation. Independent
panel pairs are needed. As a pilot approximation, multiplying the pair count
by the squared ratio of the current to the desired Monte Carlo standard error
suggests a new budget, within the resource limits. Verify that budget with
independent seeds and report availability as well as precision; this scaling
rule is not a guarantee near zero signal or an unresolved denominator.

Future panels are complete. Using a fit from missing whole cells requires
the same exchangeability and ignorable observation assumptions as that fit;
the simulation does not impute historical labels or establish ignorability.
Modelled calls retain the fitted equal object membership and redraw call
effects at each future facet combination. Variable batches and sequential
carry-over effects are refused.
}
\value{
A \code{gt_categorical_target} object.
The data-frame method exports these fields:
\describe{
\item{\code{outcome}, \code{target}}{Outcome and estimand identifiers.}
\item{\code{estimate}, \code{raw_estimate}}{Accepted and raw numerical estimates.}
\item{\code{mc_se}}{Whole-panel integration standard error.}
\item{\code{signal_variance}}{Stable-object variance, absent for decisions.}
\item{\code{total_variance}}{Total score variance, absent for decisions.}
\item{\code{available}, \code{reason}}{Availability and any refusal reason.}
\item{\code{decision_diversity}}{Diversity of the marginal plurality decision.}
}
Exports also retain integration counts, batch status and a false
\code{parameter_uncertainty} flag.

Other list fields are:
\itemize{
\item \code{allocation}: projected object and facet counts.
\item \code{scores}: supplied category scores.
\item \code{decision_probabilities}: the marginal decision law.
\item \code{integration}: simulation settings.
\item \code{shared_sources}: effects retained between panels.
\item \code{redrawn_sources}: effects redrawn between panels.
\item \code{decision_rule}: the specified vote rule.
\item \code{interpretation}: the estimand definition.
\item \code{integration_moments}: the whole-panel moments.
}
For numerical stability, scalar-score moments use scores normalized to [0,1].
The reported signal and total variances use the original score units.

The \code{integration} metadata contain these additional entries:
\itemize{
\item \code{score_transform}: the offset and span.
\item \code{resource_budget}: estimated moment storage and peak working
storage, including one active panel pair and target calculation scratch.
}
The combined estimate must not exceed 512 MiB. This is a conservative
allocation guard, not a bound on the entire R process's memory use.
}
\seealso{\code{\link{gt_simulate}}, \code{\link{gt_reliability}},
\code{\link{gt_plan}}}
\examples{
d <- expand.grid(item = 1:8, rater = 1:3)
d$label <- rep(c(0, 1), length.out = nrow(d))
fit <- gt_fit(d, label ~ item + rater, measured = "item",
  family = gt_family("binary"),
  control = gt_control(discrete = list(optimizer = "nlminb",
    fixed_covariance = list(item = matrix(0, 1, 1),
      rater = matrix(0, 1, 1)))))
result <- gt_categorical_target(fit, "score", n_items = 20,
  replications = 5, seed = 91)
as.data.frame(result)
}
