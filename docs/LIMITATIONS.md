# Limitations and unsupported models

This is the authoritative list of what Gtheory4LLM does not do. Other documents
link here rather than restating it, so one page can be kept correct. For what
has actually been checked and what a future study still has to establish, see
[validation scope](VALIDATION_SCOPE.md). For the bundled panels and their
resource ceilings, see [the real-data workflow](REAL_DATA_WORKFLOW.md).

## What "supported" means here

Passing the package's own checks means one thing: the implementation completed
its numerical acceptance rules for that fit. It does not establish parameter
recovery, interval coverage, Laplace approximation accuracy, a global optimum,
statistical identification, or that the number of evaluators in a study is
scientifically sufficient. Those are separate questions with separate evidence.

## Designs and data

- **Balanced coded panel required.** Gaussian fitting, `gt_reliability()` and
  `gt_dstudy()` all require a complete Cartesian panel of the coded object and
  facet levels, with exactly the declared number of observations per full cell.
  Missing cells are never dropped, filled or aggregated.
- **Nested facets are parent-scoped codes, not globally unique labels.** A
  nested child is declared through a within-parent code so the coded panel stays
  complete; see `help("gt_design")` for the worked contrast between the two
  labelings. Physical nesting with disjoint globally unique child labels is
  outside this preparation backend.
- **Unbalanced designs are not supported for inference.** The Gaussian
  likelihood requires a complete balanced panel. The discrete Laplace
  likelihood fits a panel with missing whole cells at the declared replication,
  but reliability and D studies require a complete balanced panel in either
  case; there is no unbalanced reliability or D-study formula. Relabeling or
  padding data to satisfy the balance guard changes the study, not the
  software.
- **Within-cell replication** is declared through `replicates`, but the Gaussian
  backend currently fits one observation per full cell only.
- **Design size.** The exact Gaussian backend allows at most 12 factorial axes
  (the object plus 11 facets), which is 4096 strata.
- **Batches.** A batch declared with `gt_batch()` is modelled only by a
  Gaussian fit of equal fixed batches: the same batches in every condition,
  each at the declared size, one row in a cell. That fit estimates one shared
  call effect, the source `Call`. The ordinary coefficient API refuses this
  model. `gt_batch_reliability()` and `gt_batch_dstudy()` instead provide
  point projections for item-score, named contrast and aggregate targets
  conditional on its fixed layout. They do not provide estimation intervals,
  fixed-facet projections or effects of regrouping or changing batch size.
  `sequential`, `neighbor` and `by` are recorded and not estimated; the new batch
  projection functions refuse these additional unmodelled patterns. Every other declaration, including every binary, ordinal and
  unordered outcome, is recorded and audited, not modelled: coefficients and
  their intervals then treat items annotated in one call as independent, and
  every output carries the status `declared_not_modelled`. A modelled call
  effect describes the batches as they were composed, at the batch size used;
  it says nothing about the same items regrouped, and nothing about which
  batch size to use. Without a recorded call column the batches are
  inferred from the item order of the rows supplied; that reconstruction
  cannot detect items removed after collection, calls of other sizes, or
  regrouping between conditions. Recorded calls are counted from the rows
  supplied: the number of items a call was sent, calls with no row left, and
  the positions at which items were sent are not recovered from filtered
  data.

## Gaussian models

- Exact balanced ML/REML for univariate and jointly multivariate outcomes.
- Standard errors are asymptotic Wald quantities from the restricted (REML) or
  profile (ML) likelihood Hessian, with delta-method coefficient intervals on
  the logit scale. They describe estimation uncertainty under the fitted model
  and allocation. They are not prediction intervals for a newly sampled panel
  and do not cover model misspecification.
- A source resting on a variance boundary has no Wald standard error and reports
  `NA`. Where the joint curvature is indefinite there, the remaining intervals
  are conditional on that source being held fixed, and say which way: a source
  whose fitted covariance is entirely zero is held at zero, and a singular but
  nonzero source is held fixed at its fitted covariance. What is known about
  how either branch performs is in [validation scope](VALIDATION_SCOPE.md).
- `AIC()` and `BIC()` on a REML fit use the restricted likelihood with the
  covariance parameters only, so they compare covariance structures that share
  the same fixed-effects structure and never an ML value. The fit's own `AIC`
  and `BIC` elements are `NA` for REML; the restricted-likelihood criteria are
  recorded under explicit names; see `help("gt_fit")`.
- **No uncertainty for the location parameters.** Outcome means are profiled out
  of the likelihood rather than fitted as free parameters, so `vcov()` has
  nothing to return and says so. `gt_component_vcov()` gives the covariance that
  does exist, of the estimated source covariances.
- Numeric binary data fitted as Gaussian is an observed-score model, not a
  binary model.

## Discrete models

- The discrete engine is a **dense, first-order Laplace prototype for small
  models**. Defaults cap it at 1,200 rows, 200 random-effect dimensions and 80
  parameters. Raising a limit does not make the approximation valid or the
  dense algebra practical; the six native 21,600-row panels exceed these limits
  by more than an order of magnitude.
- `approximation_adequacy` stays `not_assessed_first_order_laplace` for any fit
  with random variation. Numerical acceptance is not integration accuracy.
- **No discrete uncertainty.** The engine computes no observed information.
  Discrete coefficients are point estimates; standard errors, confidence
  intervals, bootstrap and jackknife are not implemented. `NA` means unavailable,
  never zero uncertainty.
- Binary and ordinal reliability is defined on an **averaged latent response**.
  It is not the reliability of observed proportions, majority votes, category
  agreement, or ordinal score averages, and must be requested explicitly with
  `scale = "latent"`.
- **Unordered categorical outcomes have no implemented scalar G/Phi.** Category
  contrasts are not separate measured outcomes.
- At one observation per cell the object-by-all-facets source is not identified
  for a discrete outcome. It is never dropped silently; declare the reduced
  model with `full_cell = FALSE` or an explicit `random =` specification.
- General singular unstructured source covariances are not implemented.
  `covariance_parameterization = "auto"` uses exact-zero-capable variance
  coordinates for univariate or diagonal models and log-Cholesky coordinates for
  joint unstructured models.
- Rejected fits cannot produce coefficients. `gt_reliability()` and
  `gt_dstudy()` require `gt_diagnostics(fit)$numerically_accepted`, and there is
  deliberately no override argument.
- Missing outcomes and declared-but-unobserved categories are rejected.

## Combinations that are not implemented

- Joint Gaussian **and** discrete outcomes in one fit.
- REML for discrete outcomes.
- Observed-score reliability for discrete outcomes.
- Joint optimization of modelled shared-call dependence, request grouping and
  monetary costs; the cost planner currently accepts ordinary reliability models
  without a modelled `Call` source.
- Sensitivity analysis for variance-component uncertainty in extrapolated
  allocations: D studies hold the fitted source covariances fixed.

## Decision studies

- Allocations are balanced and average over the declared random facet
  populations. A fixed facet's count cannot be changed and cannot be projected
  over.
- Extrapolating beyond the fitted counts holds the fitted source covariances
  fixed and assumes the same facet populations remain appropriate. The result is
  a point projection under those assumptions.

## Study planning and data retention

- `gt_plan()` searches only the supplied bounded candidate grid. Costs and
  constraints are user supplied and dated; no provider prices, request execution,
  evaluator-identity selection or empirically established human-review benefit
  are built in. `study_items` scales costs, not per-item reliability or pilot
  estimation precision. Fixed facets retain one declared universe across every
  candidate. Request batching in a cost model does not add shared-call variation
  to a fit that treats items as independent.
- Lower-bound screening uses only available pointwise coefficient intervals.
  They are not simultaneous bounds after searching many allocations or prediction
  guarantees for a future annotation panel. Unavailable intervals cannot pass
  the lower-bound screen. Boundary qualifications remain attached to results.
- `gt_simulate()` and `gt_pilot_plan()` initially support balanced Gaussian
  panels without a batch declaration, with one outcome vector per cell and all
  instrumentation facets random. Pilot fitting requires at least two levels on
  each axis. `target_counts` may specify a different final protocol, including a
  facet count of one, held constant across pilot candidates.
- Pilot precision summaries depend on a fitted or explicitly supplied parameter
  scenario. They do not account automatically for parameter uncertainty, prove
  interval coverage, provide bootstrap confidence intervals, or select a
  scientifically adequate pilot size. Every attempted replicate stays in the
  rate denominators; width summaries condition on interval availability.
  Conditional boundary intervals are labelled and need separate calibration.
- Supported shared-call fits retain item-to-batch labels as design metadata even
  with `retain = list(data = FALSE)`. Batch projection objects also expose these
  labels and target weights. Retention removes observations, not this layout;
  portable `gt_report()` and HTML output exclude the labels. An old fit without
  the recorded layout must be refitted for batch projections.

These planning additions are development source 0.4.1.9000. They do not alter the
qualified 0.4.1 archive or establish qualification of a new release.

## Infrastructure

- **Native numerical backend.** On the tested Intel Xeon 6973P-C/noLD stack,
  OpenBLAS 0.3.20's Cooperlake path reproducibly returned incorrect backward
  solves for two captured systems. The same machine passed with reference
  BLAS/LAPACK and with forced NEHALEM dispatch. The noLD CI environment uses
  verified reference BLAS/LAPACK; it does not repair the faulty OpenBLAS path
  or make all native arithmetic trustworthy. The package's existing guards
  reject the captured invalid starting steps before returning a fit. See
  [the backend investigation and qualification record](DEVELOPMENT_STATUS.md#intelnold-native-backend)
  and [issue #66](https://github.com/Veronica0206/Gtheory4LLM/issues/66).
- R 4.5.0 or later is required, inherited from OpenMx rather than from this
  package's own code. The README's install section explains why, and what to do
  if you must use an older pairing.
- The reported release state distinguishes a locally prepared bundle from a
  published release; see [the release checklist](RELEASE_CHECKLIST.md).
- A configured CI workflow is not a passing run, a passing check is not
  scientific validation, and neither implies CRAN acceptance.
