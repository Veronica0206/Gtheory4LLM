\name{gt_pilot_plan}
\alias{gt_pilot_plan}
\alias{print.gt_pilot_plan}
\alias{as.data.frame.gt_pilot_plan}
\title{Evaluate Pilot Precision or Categorical Point-Estimator Performance}
\usage{
gt_pilot_plan(fit, grid, nsim, seed, coefficient = "Erho2", outcome = NULL,
  score = NULL, kind = "outcome", width_target = NULL, level = 0.95,
  target_counts = NULL, components = NULL, means = NULL,
  control = fit$control, max_rows = 1000000L, scale = NULL,
  integration = list())
\method{print}{gt_pilot_plan}(x, ..., digits = 4L, max_rows = 12L)
\method{as.data.frame}{gt_pilot_plan}(x, row.names = NULL, optional = FALSE, ...)
}
\arguments{
  \item{fit}{An accepted fit supported by \code{\link{gt_simulate}}.
  Interval precision for Gaussian, binary or ordinal outcomes additionally
  requires \code{\link{gt_reliability}}.

  Categorical point targets require
  \code{\link{gt_categorical_target}}, including nominal and modelled fixed-call
  fits. Joint categorical models retain their complete joint law while reporting
  one selected outcome.}
  \item{grid}{A numeric data frame with one proposed pilot per row. The required
  \code{n_items} column gives the object count. Optional facet columns give the
  pilot's facet counts. All counts must be integers of at least two.

  At most 100 rows are accepted. Unspecified facets retain the original counts.
  A facet called \code{n_items} must first be renamed to avoid ambiguity.
  Modelled calls require the original item count and group membership in every
  pilot; only instrumentation counts may change.}
  \item{nsim}{Number of attempted replicates per candidate. The total across
  all candidates must not exceed 10000. Small values are software illustrations,
  not precise planning evidence.}
  \item{seed}{Required integer seed. Each attempted replicate receives a recorded
  deterministic data seed and a separate \code{retry_seed} for its refit.
  An explicitly supplied Gaussian retry seed is preserved. Otherwise a separate
  seed is assigned and recorded for each refit. A categorical refit uses its
  recorded \code{retry_seed} as an isolated RNG scope without changing the
  engine's deterministic starts or numerical acceptance controls.

  Point-target pilots additionally receive an independent \code{integration_seed}
  per attempt and a separate recorded \code{reference_seed} for the generating
  scenario. All these seeds are derived from the master seed before refitting.
  The caller's random-number state and kind are restored.}
  \item{coefficient}{Choose the quantity to evaluate:
  \itemize{
  \item \code{"Erho2"} or \code{"Phi"}: interval precision.
  \item \code{"observed_score"}: observed-score point estimates.
  \item \code{"category_vector"}: category-vector point estimates.
  \item \code{"decision_agreement"}: decision-agreement point estimates.
  }
  The last three use the corresponding targets in
  \code{\link{gt_categorical_target}} and supply no parameter intervals.}
  \item{outcome}{One reported outcome. Required for multivariate outcome results.}
  \item{score}{Optional explicit composite weights from \code{\link{gt_score}}
  for interval precision. Must be \code{NULL} for categorical point targets;
  supply category scores as the \code{scores} entry of \code{integration}.}
  \item{kind}{\code{"outcome"} or \code{"composite"}; select one coefficient.
  Categorical point-target pilots require \code{"outcome"}.}
  \item{width_target}{Optional desired total interval width in \eqn{(0, 1]}.
  A precision success requires an available interval no wider than this value.
  Must be \code{NULL} for categorical point targets; integration error is not
  used to construct a parameter confidence interval.}
  \item{level}{Interval confidence level passed unchanged to
  \code{\link{gt_reliability}}. Unused by categorical point targets.}
  \item{target_counts}{Named positive integer instrumentation counts defining
  the eventual annotation protocol whose coefficient is estimated in every
  replicate. Unspecified counts, including all counts when \code{NULL}, use the
  original fit's counts. They do not change with the pilot candidate. Counts of
  one are allowed here even though fitting a pilot needs at least two levels.}
  \item{components, means}{Optional parameter scenario overrides as documented
  for \code{\link{gt_simulate}}.}
  \item{control}{Refitting controls from \code{\link{gt_control}}; default is
  the original fit's controls. No numerical acceptance rule or limit is relaxed.
  Categorical intervals require a fit with available full observed information;
  request \code{discrete = list(check_hessian = TRUE)} when appropriate.
  Information failures and boundary fits remain explicitly unavailable.
  Any supplied fixed-covariance controls remain fixed during refitting.}
  \item{max_rows}{Maximum generated rows per replicate, as for
  \code{\link{gt_simulate}}, and in the print method the number of
  candidate pilots shown.}
  \item{x}{A \code{gt_pilot_plan} object.}
  \item{scale}{Must be explicitly \code{"latent"} for binary or ordinal interval precision.
  Gaussian fits use \code{NULL} or \code{"observed"}. The latent target is not
  reliability of observed category scores or repeated label decisions.
  Categorical point targets require \code{"observed"} for observed-score or
  category-vector ratios and \code{"decision"} for decision agreement.}
  \item{integration}{For categorical point targets only, a uniquely named list:
  \code{n_items} (default 200, at least two), \code{replications} (default 40),
  \code{reference_replications} (default 400), \code{max_rows} (default 100000),
  and optional \code{scores}. Both replication counts must be between 2 and
  10000. These defaults are computation settings, not a precision guarantee.
  Scores follow \code{\link{gt_categorical_target}} and must be explicit for
  ordinal observed-score targets. Integration seeds are generated from the
  master seed and must not be supplied here. With fixed calls, \code{n_items}
  defaults to and must equal the original item count. Instrumentation counts
  for both reference and refitted targets are always \code{target_counts}.
  Leave this list empty for Gaussian or latent interval precision.}
  \item{digits}{Significant digits in the printed table.}
  \item{row.names, optional}{As for \code{\link{as.data.frame}}; \code{row.names}
  replaces the row names of the returned data frame and \code{optional} is ignored.}
  \item{...}{Further method arguments; currently unused.}
}
\description{
Simulates and refits proposed complete pilot panels. Records interval precision
or the performance of point estimates for one fixed target annotation protocol.
Increasing
pilot item count changes estimation information; changing the target allocation
changes the coefficient being estimated. These two choices remain explicit.
}
\details{
The original estimator and resolved source covariance structures are preserved
on every refit. Fresh object effects and instrumentation levels are sampled
under the declared source law.
The scope uses fully random facets without reuse of specific fixed evaluator
realizations. Interval-precision pilots refuse batch declarations.
Gaussian pilots retain one outcome vector
per complete coded cell. Binary and ordinal pilots retain their fitted links,
thresholds, joint source covariance and declared equal cell replication. They
target explicitly selected latent-response coefficients when \code{coefficient}
is \code{"Erho2"} or \code{"Phi"}. The original fitted
thresholds define simulation; thresholds and intercepts are reestimated in each
refit. Parameter overrides change the generating scenario, not the specified
refitting constraints. No missing values are imputed.

Categorical pilot planning is additionally limited to one million generated rows
across all attempted refits. Per-fit numerical and workspace limits still apply;
this is not a runtime or acceptance guarantee. Samples with absent categories
retain all declared levels and are recorded as fitting errors, without recoding
or discarding the attempt.
Interval pilots also repeat the full information calculation for eligible
accepted refits. Its likelihood-evaluation cost grows quadratically with the
number of stored parameters; see \code{\link{gt_control}}. A feasible large-panel
point fit does not qualify interval-pilot computation at the same size.

\strong{Categorical point targets.} Observed-score, category-vector and decision
targets evaluate the finite numerical estimator rather than interval width.
First, the specified generating scenario, including parameter overrides, is
integrated independently to obtain one fixed reference estimate. It is a
numerical reference, not exact truth; its integration standard error is retained.
An undefined or unavailable reference stops the calculation before any refits.
Each attempted pilot is then simulated, refitted and evaluated at the same
\code{target_counts}, with a separate inner integration seed. Nominal categories
retain their labels and reference contrasts. Fixed calls retain item count,
membership and batch size in both pilot and target panels, while resampling
call effects. Variable or newly assigned groups are unsupported.

Available-only bias and RMSE can be affected by numerical-target selection near
weak signals. Interpret them together with all-attempt target availability and
reference integration error; a missing target must not be replaced by a new
seed. See \code{\link{gt_categorical_target}} for precision limitations.

This route limits all generated rows, including the reference, every pilot,
and every planned inner integration, to ten million before calculation starts.
The separate one-million pilot-row limit also applies. Reference and inner
integrations are both preflighted against the 512 MiB estimated target
working-storage limit, including moment matrices. Only the reference estimate
and integration metadata are retained during refitting, so its moment matrix
does not accumulate with the inner integration workspace. Failed attempts do not
cause replacement attempts. Samples from a fit with omitted whole cells are
complete future panels under that fitted model and its ignorability assumptions;
the procedure does not simulate an unprovided missingness mechanism.

Every planned replicate has a record, including simulation errors, preparation
or fitting errors, numerical refusals, reliability errors, and unavailable
intervals. Warnings are retained in that record. Error, refusal, and unavailability
are not silently deleted from rate denominators. Width summaries condition on
an available interval and show their denominator. Precision success rates use
all attempted replicates, so failures and unavailable intervals are non-successes;
they do not imply a true coefficient or width of zero.

Reported Monte Carlo standard errors for rates use
\eqn{\sqrt{p(1-p)/B}}, where \eqn{B} is the number of attempted replicates
for unconditional rates. The explicitly conditional precision rate and its
Monte Carlo standard error instead use the number of available intervals.
The mean-width Monte Carlo standard error uses the sample standard deviation
divided by the square root of the number of available intervals. A zero plug-in
rate standard error after no failures or all failures is not evidence that the
underlying probability is known exactly. Increase replicate counts and examine
parameter scenarios before making a collection decision.

Intervals retain the fitting engine's asymptotic delta-method interpretation.
Conditional boundary intervals are explicitly flagged. This procedure evaluates
model-based plug-in precision, not calibrated coverage, a parametric-bootstrap
confidence interval, or guaranteed performance in the actual annotation study.
It does not select an optimal pilot automatically.
Categorical intervals inherit the fitted Laplace approximation. Their precision
does not establish approximation accuracy or interval coverage. Fixed covariance
components contribute no estimated variance uncertainty; this conditional
scenario must not be interpreted as the precision of estimating those components.

For point targets, bias and RMSE compare available estimates with the recorded
reference and use only the available-target denominator. Unavailable estimates
are not zeros. Empirical standard deviation includes both estimation variation
and inner integration noise; the latter is not subtracted automatically.
Bias and RMSE Monte Carlo standard errors condition on the recorded reference,
whose separate MCSE is shared across every comparison. For \eqn{A} available
estimates, the bias MCSE is their sample standard deviation divided by
\eqn{\sqrt A}; the RMSE MCSE uses the sample standard deviation of squared
errors divided by \eqn{2\,\mathrm{RMSE}\sqrt A}. These two standard errors require
at least two available estimates, and the RMSE MCSE additionally requires positive
RMSE. Neither is a confidence interval for the fitted target or evidence of
unconditional accuracy after numerical selection.
}
\value{
A list with \code{allocations}, one row per proposed pilot;
\code{replicates}, one row per attempted simulation/refit;
\code{summary}, rates, denominators, Monte Carlo standard errors, and conditional
width summaries; \code{scenario}, the parameters, target protocol, estimator,
coefficient, scale, seeds, and controls; and \code{interpretation}. Categorical
scenarios additionally retain families, thresholds and the source covariance
structure. The object has
class \code{gt_pilot_plan}: \code{print()} shows each candidate's allocation
beside the applicable precision or point-target summaries, and \code{as.data.frame()}
returns one row per candidate, joining \code{allocations} with \code{summary}.

\code{accepted} counts accepted fits even when coefficient extraction fails.
\code{interval_unavailable} counts successful coefficient extraction without a
finite interval. \code{reliability_errors} counts extraction failures separately.
The \code{interval_available} count is the denominator of conditional width
summaries. \code{conditional_intervals} reports how many available intervals
hold boundary components fixed. The complete replicate table is authoritative
for further stratified summaries.

Point-target results additionally contain:
\itemize{
\item \code{reference}: a one-row target table.
\item \code{reference_integration}: its integration settings and seed.
}
The replicate table adds:
\itemize{
\item \code{integration_seed}: the inner integration seed.
\item \code{target_available}: target availability.
\item \code{target_raw_estimate}: the untruncated point estimate.
\item \code{target_mc_se}: its integration MCSE.
\item \code{error_vs_reference}: the estimate minus the reference.
}
Interval columns remain unavailable.

The summary reports acceptance and availability rates with MCSEs using all
attempts, together with these target counts and reference fields:
\itemize{
\item \code{target_available}: the number of available target estimates.
\item \code{target_unavailable}: unavailable target calculations.
\item \code{target_errors}: target-integration errors.
\item \code{reference_estimate}: the recorded reference estimate.
\item \code{reference_mc_se}: the reference integration MCSE.
}
Conditional summaries use the following fields:
\itemize{
\item \code{mean_estimate_given_available}: mean available estimate.
\item \code{bias_vs_reference_given_available}: bias relative to the reference.
\item \code{rmse_vs_reference_given_available}: RMSE relative to the reference.
\item \code{empirical_sd_given_available}: empirical standard deviation.
\item \code{mean_inner_mc_se_given_available}: mean inner integration MCSE.
\item \code{bias_mcse_given_reference}: conditional bias MCSE.
\item \code{rmse_mcse_given_reference}: conditional RMSE MCSE.
}
Counts and rates distinguish simulation errors, fitting errors, numerical
refusals, target-integration errors and unavailable target calculations.
No precision-success or coverage claim is supplied for this route.

Two character columns retain diagnostics from each refit.
The \code{acceptance_failures} column contains failure codes separated by
\code{|}. The \code{selected_attempt} column identifies the returned optimizer
attempt. These columns survive ordinary CSV export; whole fit objects are
not retained. A missing code or identifier is \code{NA}, including when no
fit was returned. Accepted fits usually have no failure codes, while their
selected attempt is retained when recorded. Reliability errors and unavailable
intervals retain diagnostics from the completed refit. Missing diagnostics do
not imply acceptance; the \code{accepted} column remains authoritative.

To replay a replicate, generate data with its recorded \code{seed}, copy
\code{scenario$control}, replace the copied Gaussian \code{retry_seed} with
the recorded refit seed, and refit with the recorded estimator and covariance
structures. For categorical replay, use the retained families and source
covariance structure and run the refit under its recorded \code{retry_seed};
there is no Gaussian retry setting to insert. Earlier replicate failures or optimizer retries do not alter later
replicates' random streams. For a point target, evaluate the replayed fit with
the recorded \code{integration_seed}, fixed \code{target_counts}, outcome,
category scores and integration settings. The reference uses the generating
parameters, \code{scenario$reference_seed}, and \code{reference_replications}.
}
\examples{
# Small synthetic panel and four refits to demonstrate the interface only.
d <- expand.grid(item = 1:12, evaluator = 1:3)
d$quality <- sin(d$item) + d$evaluator / 5 +
  cos(d$item * d$evaluator) / 4
fit <- gt_fit(quality ~ item + evaluator, d, measured = "item",
  control = gt_control(gaussian = list(retry_seed = 42)))
# Each pilot estimates the same three-evaluator protocol.
plan <- gt_pilot_plan(fit,
  grid = data.frame(n_items = c(8, 12), evaluator = c(2, 3)),
  nsim = 2, seed = 2026, coefficient = "Phi", width_target = 0.15,
  target_counts = c(evaluator = 3))
plan
as.data.frame(plan)
plan$replicates
# Two simulations per candidate cannot support a pilot-size recommendation.
}
\seealso{\code{\link{gt_simulate}}, \code{\link{gt_reliability}},
\code{\link{gt_categorical_target}}, \code{\link{gt_dstudy}}}
