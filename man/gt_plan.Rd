\name{gt_plan}
\alias{gt_plan}
\alias{print.gt_plan}
\alias{as.data.frame.gt_plan}
\title{Rank a Bounded Set of D-Study Allocations by User-Supplied Cost}
\description{
Exhaustively evaluates a declared set of balanced facet counts under one fitted
model. It retains every candidate, screens a reliability target, identifies
minimum-cost ties and a cost--performance Pareto set, and explains changes in
error contributions relative to a declared baseline candidate.
}
\usage{
gt_plan(fit, candidates, cost, currency, cost_date, study_items, target,
        coefficient = "Erho2", outcome = NULL, kind = "outcome",
        screening = c("point", "lower"), baseline = 1L,
        constraints = NULL, scale = NULL, score = NULL,
        fixed = character(), level = 0.95, max_candidates = 10000L,
        cost_description = NULL, integration = list())

\method{as.data.frame}{gt_plan}(x, row.names = NULL, optional = FALSE, ...)

\method{print}{gt_plan}(x, ..., digits = 4L, max_rows = 12L)
}
\arguments{
\item{fit}{An accepted \code{gt_fit} supporting analytic balanced reliability,
or a categorical fit supporting \code{\link{gt_categorical_target}} for an
explicit observed or decision target. Modelled categorical calls retain their
fitted item count and layout; analytic planning still refuses call effects.}
\item{candidates}{A nonempty numeric data frame of instrumentation facet counts,
or a named list of count vectors expanded to their full Cartesian product.
Omitted facets retain their fitted counts. Counts must be positive integers
below \eqn{2^{53}}. Duplicate rows remain distinct candidates.}
\item{cost}{A numeric data frame of nonnegative, finite monetary cost components,
with one row per candidate, or a function called once with a planning data frame.
The planning frame contains \code{design_id}, \code{allocation_} prefixed facet
counts, \code{annotations_per_item}, \code{study_items}, and
\code{total_annotations}. It has an \code{allocation_columns} attribute mapping
column names to the original facets.

The function returns a cost-component data frame or a list containing
\code{costs}. Such a list can also be supplied directly. Its optional entries are:
\itemize{
\item \code{resources}: a nonnegative numeric data frame.
\item \code{assumptions}: character text.
}

Components are summed: do not include an already summed total as an extra
component. Prices, usage assumptions, overhead, retry costs, evaluator setup
and human-review costs are entirely user supplied.}
\item{currency}{One three-letter uppercase currency code; all cost components
must already use that same currency. No exchange conversion is performed.}
\item{cost_date}{The date of the supplied cost assumptions, as \code{Date} or
\code{"YYYY-MM-DD"} text.}
\item{study_items}{The number of distinct items to be costed. This is a positive
integer held constant across candidates. It multiplies annotations and costs;
it does not change reliability coefficients or estimate pilot-study precision.}
\item{target}{A number from zero to one for the selected coefficient.}
\item{coefficient}{The coefficient or repeated-panel target to screen:
\itemize{
\item \code{"Erho2"}: relative comparisons.
\item \code{"Phi"}: absolute decisions.
\item \code{"observed_score"}: categorical score target.
\item \code{"category_vector"}: category-proportion target.
\item \code{"decision_agreement"}: plurality-decision agreement.
}
The last three use \code{\link{gt_categorical_target}}. Its corresponding
target names are \code{"score"}, \code{"category_vector"} and
\code{"decision"}, respectively.}
\item{outcome}{The outcome to screen. Required when multiple outcomes are
reported.}
\item{kind}{\code{"outcome"} or \code{"composite"}; a composite requires
\code{score}. Categorical target planning permits only \code{"outcome"}.}
\item{screening}{\code{"point"} screens the projected point estimate.
\code{"lower"} separately screens its available lower confidence bound at
\code{level}. Missing bounds remain unavailable and do not pass the screen.
Categorical observed and decision targets permit point screening only.}
\item{baseline}{The one-based candidate row identifying the comparison protocol;
default is row 1. Its complete allocation and cost are retained. The baseline
can be infeasible: it remains a comparison, not a recommendation.}
\item{constraints}{Optional function applied to the joined candidate, coefficient,
cost and resource table, or a row-aligned logical vector/data frame supplied
directly. A function returns a logical vector or a data frame of named logical
checks. \code{FALSE} excludes a candidate; \code{NA} records unknown feasibility.
The checks and their reasons are retained. Cost components use the prefix
\code{cost_component_}; resource columns use \code{resource_}.}
\item{scale, score, fixed, level}{As in \code{\link{gt_reliability}}. The score and
fixed-facet universe are declared once for all candidates. A fixed facet must
retain its observed count; it is never selected or changed by the optimizer.}
\item{max_candidates}{Positive integer upper limit checked before Cartesian
expansion; default 10,000. The caller defines the search bounds.}
\item{cost_description}{Optional explanatory text recording the source and units
of the cost model. Supply additional assumptions through the cost record.}
\item{integration}{For categorical target planning only, a uniquely named list
with an explicitly supplied \code{seed}; optional \code{n_items} (default 200),
\code{replications} (default 40 independent panel pairs, range 2--10,000),
\code{max_rows} (default 100,000 per panel, maximum 1,000,000), and \code{scores}.
For a modelled call layout, \code{n_items} defaults to and must equal the fitted
item count, as must \code{study_items}. Category scores follow
\code{\link{gt_categorical_target}} and must be explicit for ordinal outcomes.
Use \code{scale = "observed"} for score/vector targets or
\code{scale = "decision"} for decision agreement. Composite \code{score}
objects and fixed facets are not supported on this route. Every candidate
facet count must be at least one. All candidates together are limited to
ten million generated rows, counting both panels in every replication;
this guard is checked before simulation begins.}
\item{x}{A \code{gt_plan} object.}
\item{row.names, optional}{Standard data-frame conversion arguments.}
\item{...}{Reserved for S3 compatibility.}
\item{digits, max_rows}{Printing precision and maximum displayed rows.}
}
\details{
\strong{Three distinct sizes.} \code{study_items} counts distinct study items.
\code{annotations_per_item} is the product of facet counts and the fitted equal
within-cell replication. \code{total_annotations} is their product. Items per
request, request counts and retry counts may be supplied as cost resources;
they are not statistically interchangeable with repetitions per item. Total
annotations must remain exactly representable integers below \eqn{2^{53}}.

\strong{What is optimized.} All allocations use the same accepted fit, source
covariances, score, outcome scale and declared facet universe. Counts represent
exchangeable levels under that model. The function does not replace an expensive
evaluator with a cheaper identity, refit an evaluator subset, change a random
facet into a fixed facet, or alter a batching layout to improve a coefficient.
A heterogeneous cost model must still describe costs under that same statistical
sampling universe. Evaluator-identity selection needs separate model evidence.
Adding a human-review cost does not by itself model a reliability benefit.

\strong{Search and missing values.} A candidate is eligible when all constraints
are satisfied and the selected screening value reaches the target. Minimum-cost
flags retain every exact cost tie among eligible candidates. Pareto status
compares cost with the selected performance measure among feasible candidates
having an available screening value, independently of the target. A design is
dominated when another is no more expensive and performs at least as well, with
at least one strict improvement. Exact duplicate cost--performance ties remain
non-dominated. Unknown feasibility or performance has \code{NA} Pareto status;
known infeasible rows have \code{FALSE}. An unavailable lower bound is not
replaced by its point estimate or a zero standard error. A missing lower bound
cannot qualify even if the point estimate exceeds the target.

\strong{Interpretation of intervals.} The available Gaussian intervals retain
the parent reliability calculation's model and any conditional boundary
qualification. They are pointwise estimates of uncertainty, not simultaneous
coverage guarantees after searching many designs and not future-panel prediction
bounds. Discrete latent intervals require an available observed-information
calculation; unavailable intervals keep their reason. For categorical observed
and decision targets, \code{mc_se} measures numerical integration error at
fixed fitted parameters. It is never substituted for parameter uncertainty,
a lower confidence bound, or uncertainty after selecting a design.

\strong{Batching boundary.} Analytic planning refuses modelled \code{Call}
effects. Categorical target planning simulates the fitted equal fixed layout,
retaining the item-to-batch membership and fitted item count while allowing
new exchangeable facet levels. It does not optimize batch size, item grouping,
or ordering effects. Request batching in a cost callback does not itself
introduce shared-call dependence into a fit without a call source.

\strong{Categorical targets.} The selected outcome and category scoring remain
fixed across candidates; all dimensions of a joint fit are still simulated.
The planner uses the same explicit seed for each candidate, which preserves
duplicate allocations exactly. This does not supply paired-comparison
inference between candidates. Minimum-cost and Pareto results rank Monte Carlo
point estimates, so small changes can reflect integration error. Increase
integration precision when that affects a decision. Decision agreement is
repeatability of the declared vote rule, not discrimination or correctness;
its decision-diversity diagnostic is retained beside agreement.
Before integration starts, a 512 MiB estimated working-storage guard accounts
for all retained candidate moment matrices plus the largest active integration
workspace. The moments remain available in \code{target_projections}; the
estimate is recorded as \code{integration_resource_budget} in \code{provenance}.

\strong{Marginal explanations.} Changes are candidate minus baseline for cost
and coefficients, and baseline minus candidate for relative/absolute error
variance. Negative reductions therefore identify increased error. Per-source
reductions add to their corresponding total error reductions. These are
conditional projections, not causal effects, empirical accuracy, or a promise
that future estimates will attain the target. Categorical target planning
reports \code{target_gain} relative to the baseline, without a Gaussian
source-error decomposition or invented \eqn{G}/\eqn{\Phi} columns.
}
\value{
A \code{gt_plan} list. \code{results} (also \code{as.data.frame(x)}) retains all
candidate allocations, coefficients and intervals, cost components/resources,
constraint status/reasons, target status, minimum-cost and Pareto indicators,
cost rank among feasible rows, and baseline cost/error/coefficient changes.

\code{source_contributions} reports universe, relative-error and absolute-error
contributions and the error reductions per source. The input allocations and
full coefficient tables remain in \code{allocations} and \code{all_coefficients}.
Cost and resource records remain in \code{cost_breakdown} and \code{resources}.
The \code{constraint_checks} element preserves every check. The \code{baseline}
element records the chosen comparison.

\code{provenance} records the currency, date, cost assumptions and callback
text. It also records the search scope, target, score, facet universe, interval
qualifications, original fitted counts and selected baseline.
\code{fit_diagnostics} retains the fitted numerical diagnostics.
No request is executed and no provider price is queried.

On the categorical route, \code{results} retains the target estimate,
\code{mc_se}, availability and reason, raw ratio and target-specific moments
or decision diversity. \code{target_projections} retains each underlying
target object or its failure record; \code{source_contributions} is empty.
Integration settings, aggregate simulation work, and the uncertainty
interpretation are retained in \code{provenance}. Missing candidate targets
remain in the table and cannot qualify for minimum cost or Pareto status.
}
\seealso{\code{\link{gt_reliability}}, \code{\link{gt_dstudy}},
\code{\link{gt_dstudy_target}}, \code{\link{gt_categorical_target}}}
\examples{
# Small synthetic Gaussian example; no data or prices are downloaded.
d <- expand.grid(item = 1:12, evaluator = 1:3)
d$quality <- sin(d$item) + d$evaluator / 5 +
  cos(d$item * d$evaluator) / 4
fit <- gt_fit(quality ~ item + evaluator, d, measured = "item",
  control = gt_control(gaussian = list(retry_seed = 42)))
plan <- gt_plan(fit,
  candidates = list(evaluator = 2:4),
  cost = function(d) list(
    costs = data.frame(annotation = 0.01 * d$total_annotations,
                       setup = 2 * d$allocation_evaluator),
    resources = data.frame(request_count = d$total_annotations),
    assumptions = "Illustrative monetary units; one item per request."),
  currency = "USD", cost_date = "2026-10-09", study_items = 1000,
  target = 0.80, coefficient = "Phi", baseline = 1,
  constraints = function(d) data.frame(
    budget = d$total_cost <= 150,
    requests = d$resource_request_count <= 10000),
  cost_description = "Illustrative costs; not provider prices.")
plan
subset(as.data.frame(plan), minimum_cost \%in\% TRUE)
plan$source_contributions
}
