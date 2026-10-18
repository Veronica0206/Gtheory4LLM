\name{gt_pilot_plan}
\alias{gt_pilot_plan}
\alias{print.gt_pilot_plan}
\alias{as.data.frame.gt_pilot_plan}
\title{Evaluate Pilot Precision under a Gaussian Parameter Scenario}
\usage{
gt_pilot_plan(fit, grid, nsim, seed, coefficient = "Erho2", outcome = NULL,
  score = NULL, kind = "outcome", width_target = NULL, level = 0.95,
  target_counts = NULL, components = NULL, means = NULL,
  control = fit$control, max_rows = 1000000L)
\method{print}{gt_pilot_plan}(x, ..., digits = 4L, max_rows = 12L)
\method{as.data.frame}{gt_pilot_plan}(x, row.names = NULL, optional = FALSE, ...)
}
\arguments{
  \item{fit}{An accepted Gaussian fit supported by \code{\link{gt_simulate}}.}
  \item{grid}{A numeric data frame with one proposed pilot per row. The required
  \code{n_items} column gives the object count. Optional facet columns give the
  pilot's facet counts. All counts must be integers of at least two.

  At most 100 rows are accepted. Unspecified facets retain the original counts.
  A facet called \code{n_items} must first be renamed to avoid ambiguity.}
  \item{nsim}{Number of attempted replicates per candidate. The total across
  all candidates must not exceed 10000. Small values are software illustrations,
  not precise planning evidence.}
  \item{seed}{Required integer seed. Each attempted replicate receives a recorded
  deterministic data seed and a separate \code{retry_seed} for its refit.
  An explicitly supplied Gaussian retry seed is preserved. Otherwise a separate
  seed is assigned and recorded for each refit.

  The caller's random-number state and kind are restored.}
  \item{coefficient}{\code{"Erho2"} or \code{"Phi"}.}
  \item{outcome}{One reported outcome. Required for multivariate outcome results.}
  \item{score}{Optional explicit composite weights from \code{\link{gt_score}}.}
  \item{kind}{\code{"outcome"} or \code{"composite"}; select one coefficient.}
  \item{width_target}{Optional desired total interval width in \eqn{(0, 1]}.
  A precision success requires an available interval no wider than this value.}
  \item{level}{Interval confidence level passed unchanged to
  \code{\link{gt_reliability}}.}
  \item{target_counts}{Named positive integer instrumentation counts defining
  the eventual annotation protocol whose coefficient is estimated in every
  replicate. Unspecified counts, including all counts when \code{NULL}, use the
  original fit's counts. They do not change with the pilot candidate. Counts of
  one are allowed here even though fitting a pilot needs at least two levels.}
  \item{components, means}{Optional parameter scenario overrides as documented
  for \code{\link{gt_simulate}}.}
  \item{control}{Refitting controls from \code{\link{gt_control}}; default is
  the original fit's controls. No numerical acceptance rule or limit is relaxed.}
  \item{max_rows}{Maximum generated rows per replicate, as for
  \code{\link{gt_simulate}}, and in the print method the number of
  candidate pilots shown.}
  \item{x}{A \code{gt_pilot_plan} object.}
  \item{digits}{Significant digits in the printed table.}
  \item{row.names, optional}{As for \code{\link{as.data.frame}}; \code{row.names}
  replaces the row names of the returned data frame and \code{optional} is ignored.}
  \item{...}{Further method arguments; currently unused.}
}
\description{
Simulates and refits proposed balanced Gaussian pilot panels, then records
precision of a coefficient for one fixed target annotation protocol. Increasing
pilot item count changes estimation information; changing the target allocation
changes the coefficient being estimated. These two choices remain explicit.
}
\details{
The original estimator and resolved source covariance structures are preserved
on every refit. New items and all instrumentation levels are sampled independently.
The initial scope uses fully random facets, with no batch declaration. No claim
is made about incomplete layouts, discrete outcomes, or reuse of specific fixed
evaluator realizations.

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
}
\value{
A list with \code{allocations}, one row per proposed pilot;
\code{replicates}, one row per attempted simulation/refit;
\code{summary}, rates, denominators, Monte Carlo standard errors, and conditional
width summaries; \code{scenario}, the parameters, target protocol, estimator,
coefficient, seeds, and controls; and \code{interpretation}. The object has
class \code{gt_pilot_plan}: \code{print()} shows each candidate's allocation
beside its acceptance, interval and precision rates, and \code{as.data.frame()}
returns one row per candidate, joining \code{allocations} with \code{summary}.

\code{accepted} counts accepted fits even when coefficient extraction fails.
\code{interval_unavailable} counts successful coefficient extraction without a
finite interval. \code{reliability_errors} counts extraction failures separately.
The \code{interval_available} count is the denominator of conditional width
summaries. \code{conditional_intervals} reports how many available intervals
hold boundary components fixed. The complete replicate table is authoritative
for further stratified summaries.

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
structures. Earlier replicate failures or optimizer retries do not alter later
replicates' random streams.
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
\seealso{\code{\link{gt_simulate}}, \code{\link{gt_reliability}}, \code{\link{gt_dstudy}}}
