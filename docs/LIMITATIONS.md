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

- **Default balanced coded panel.** The default Gaussian route and ordinary
  analytic coefficients require a complete Cartesian panel of the coded object
  and facet levels, with exactly the declared observations per full cell.
  Missing cells are never filled or aggregated to satisfy that requirement.
  An explicit univariate observed-row Gaussian route and an intended balanced
  D-study projection have the separate scope described below.
- **Nested facets are parent-scoped codes, not globally unique labels.** A
  nested child is declared through a within-parent code so the coded panel stays
  complete; see `help("gt_design")` for the worked contrast between the two
  labelings. Physical nesting with disjoint globally unique child labels is
  outside the balanced preparation backend. The observed-row Gaussian route
  forms kernels from the supplied grouping terms without inferring physical
  nesting or relabeling the data.
- **Incomplete panels have bounded support.** Explicit
  `gt_control(gaussian = list(engine = "lme4", panel = "observed"))` fits
  univariate Gaussian panels with missing whole cells, one row per observed
  cell and no batch declaration. It checks covariance-kernel identification and
  an independent observed-row ML/REML likelihood. Missingness must be ignorable
  for that specified model; joint incomplete Gaussian inference is unsupported.
  The discrete likelihood also permits missing whole cells with declared equal
  replication. Neither route defines analytic reliability of the irregular
  observed allocation. The Gaussian route can explicitly project to an intended
  complete balanced allocation; categorical simulation targets can generate a
  complete future allocation. No original outcomes are imputed.
- **Within-cell replication** is declared through `replicates`, but the Gaussian
  backend currently fits one observation per full cell only.
- **Design size.** The exact Gaussian backend allows at most 12 factorial axes
  (the object plus 11 facets), which is 4096 strata.
- **Batches.** Eligible Gaussian and dense/sparse categorical fits model
  equal fixed batches: the same batches in every condition,
  each at the declared size, one row in a cell. That fit estimates one shared
  call effect, the source `Call`. The ordinary coefficient API refuses this
  model. For Gaussian fits, `gt_batch_reliability()` and `gt_batch_dstudy()` provide
  point projections for item-score, named contrast and aggregate targets
  conditional on its fixed layout. They do not provide estimation intervals,
  fixed-facet projections or effects of regrouping or changing batch size.
  For categorical fits, `gt_categorical_target()` simulates repeated panels
  under the fitted item grouping and size, with new call effects. Its target
  and integration error differ from analytic G/Phi and parameter intervals.
  The observed-row Gaussian route refuses batch declarations.
  `sequential`, `neighbor` and `by` are recorded and not estimated; batch
  projection and categorical simulation functions refuse these additional
  unmodelled patterns. Unsupported batch layouts are recorded and audited,
  not modelled: coefficients and
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
- The lme4 route supplies no source-component covariance or coefficient
  intervals. Its observed-row option defaults to at most 1,000 rows and a
  512 MiB preparation budget for the independent dense likelihood. Structural
  checks refuse duplicate cells, aliased covariance kernels, batches and
  jointly multivariate outcomes; increasing a resource budget changes none of
  these contracts.
- **Square-root recovery is a start, not an estimate.** After an ordinary
  refusal of a multivariate unstructured model, one bounded search on the
  square-root form of the same deviance may supply the next attempt's starting
  components (`gt_control(gaussian = list(initialization = "none"))` disables
  it). It consumes an existing attempt, adds none, and the ordinary optimizer,
  stationarity and independent-likelihood checks decide acceptance unchanged.
  It does not repair an objective that is unstable at the returned point, and
  a fit it rescues is a numerical acceptance, not evidence of a global optimum.
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
- **No location-parameter covariance extractor.** Gaussian outcome means are
  profiled out and their sampling covariance is not currently computed by
  `vcov()`. `gt_component_vcov()` extracts the available covariance of source
  components; it does not stand in for the different `coef()` estimand.
- Numeric binary data fitted as Gaussian is an observed-score model, not a
  binary model.

## Discrete models

- The discrete engines use **the same first-order Laplace approximation** with
  dense or sparse algebra. Dense is the default; select sparse with
  `gt_control(discrete = list(engine = "sparse"))`. Both support univariate and
  joint binary, ordinal and nominal outcomes, subject to the same numerical
  acceptance rules. Defaults remain 1,200 rows, 200 random-effect dimensions
  and 80 parameters, plus the selected engine's 512 MiB memory guard. The sparse
  estimate keeps a complete-fill bound while that fits the budget; otherwise it
  refuses on the exact count of the conditional Hessian's structural nonzeros
  or factorizes the structural pattern once and counts the fill, so a declared
  larger budget is judged against the design's actual sparsity rather than a
  dense square; the counted fill is a planning estimate, with the multiplier
  as allowance, because the fit recomputes its own ordering. Raising limits does not qualify full-panel solver
  performance or approximation accuracy; the native 21,600-row panels exceed
  the default caps, and the joint native panels need an explicitly declared
  budget above the default.
- `approximation_adequacy` stays `not_assessed_first_order_laplace` for any fit
  with random variation. Numerical acceptance is not integration accuracy.
  `gt_laplace_check()` compares the Laplace objective of one fitted model
  with a refined numerical estimate at the same parameters; it does not change
  this label, does not refit, and says nothing about bias in the estimates.
- **Discrete uncertainty is optional and conditional.** Request
  `check_hessian = TRUE` in discrete controls to compute numerical observed
  information over nuisance intercepts/thresholds and covariance parameters.
  The full negative-log-likelihood Hessian is inverted before propagating
  covariance uncertainty. Availability requires numerical acceptance, interior
  estimated covariance components, positive definite information and agreement
  between finite-difference steps. Boundaries, unstable curvature or failed
  conditional modes leave uncertainty unavailable with a recorded reason.
  Components supplied as fixed have no estimated uncertainty; intervals then
  condition on those values. Available latent coefficient intervals inherit
  first-order Laplace error; general finite-sample calibration remains
  unestablished. Small-panel Wald intervals can be overly conservative, and
  unstructured models can frequently withhold intervals at estimated covariance
  boundaries. Report coverage among available intervals separately from the
  fractions of all attempted panels yielding accepted fits, available intervals
  and intervals covering the truth. Good conditional coverage alone does not
  establish useful interval availability or unconditional coverage.
  Withholding at an estimated boundary does not ensure coverage at a true
  boundary: a positive interior estimate can arise when the true variance is
  zero, and its logit-Wald coefficient interval excludes zero.
  The default does not compute information. Bootstrap and jackknife intervals
  are not implemented; `NA` means unavailable, never zero uncertainty.
  On the finite-difference route the two central-difference Hessians require
  `2 * (1 + 2 * p^2)` marginal likelihood evaluations for `p` stored
  parameters when all evaluations complete; the analytic route needs `4 * p`
  gradients instead. These conditional modes start cold. Full information, and pilot
  studies that repeatedly request it, can cost much more than point estimation.
  Sparse factorization feasibility does not qualify full-native joint fitting
  or uncertainty; size-specific computational and statistical evidence is needed.
- **The analytic outer gradient is opt-in and bounded.**
  `gradient = "analytic"` requires the sparse engine, L-BFGS-B and the
  package's compiled routines. It supports natural Cholesky, log-Cholesky and
  fixed source covariances; direct and exchangeable variance coordinates are
  refused at fit start, so a univariate or diagonal model needs
  `covariance_parameterization = "cholesky"` and an exchangeable nominal
  covariance stays on finite differences. The design must lie within the
  compiled selected inverse's declared caps: 60,000 random-effect dimensions,
  25,000 observations, 8 latent dimensions, 128 local coordinates per
  observation (sources times latent dimensions), 15 million factor entries and
  stated recurrence, query and contraction work; `gt_preflight()` reports the
  caps it can read before fitting, and the rest refuse at the first gradient.
  A refused gradient ends its attempt; there is no finite-difference fallback.
  The route changes only the optimizer's search direction. Acceptance is still
  decided by the finite-difference stationarity check, restarts and bounds, so
  a faster search does not make a fit acceptable. In natural Cholesky
  coordinates the derivative along an exact zero factor column vanishes, so
  the analytic route cannot move the optimizer off a singular source whose
  covariance-direction score still points into the interior (the
  finite-difference route's one-sided difference at the bound can); such a fit
  ends refused by the stationarity check rather than accepted. The opt-in
  `boundary_escape = "projected"` steps such sources off the boundary along the
  projected covariance score and reruns the tight attempt, at most three times
  per attempt. It is not a general covariance-space optimizer: a fit whose
  escape does not reach a stationary point, or whose starts escape to
  different points, is still refused.
- Binary and ordinal reliability is defined on an **averaged latent response**.
  It is not the reliability of observed proportions, majority votes, category
  agreement, or ordinal score averages, and must be requested explicitly with
  `scale = "latent"`.
- **Nominal (unordered categorical) reliability is a latent coefficient on the
  category contrasts.** It is the mean of the generalized eigenvalues of the
  universe covariance relative to universe plus error on the K - 1 contrasts,
  reported with their range; it does not depend on the reference category,
  but only under `covariance = "exchangeable"` or `"unstructured"`, and is
  refused under a diagonal covariance on the contrasts, which is a different
  model for each reference. It is not the reliability of observed labels or
  of category proportions, has no numeric-score composite, and inherits the
  first-order Laplace approximation. The separate `category_vector` target
  uses observed category proportions and is invariant to category relabeling.
- At one observation per cell the object-by-all-facets source is not identified
  for a discrete outcome. It is never dropped silently; declare the reduced
  model with `full_cell = FALSE` or an explicit `random =` specification.
- `covariance_parameterization = "auto"` uses exact-zero-capable variance
  coordinates for univariate or diagonal models and Cholesky coordinates, whose
  nonnegative factor diagonal can reach zero, for joint unstructured models, so
  a singular source covariance is represented exactly. Explicit log-Cholesky
  coordinates can only approach one. Boundary estimates carry no Wald
  intervals. The exchangeable nominal covariance uses variance
  coordinates and keeps outcomes independent within each source.
- Rejected fits cannot produce coefficients. `gt_reliability()` and
  `gt_dstudy()` require `gt_diagnostics(fit)$numerically_accepted`, and there is
  deliberately no override argument.
- Missing outcomes and declared-but-unobserved categories are rejected.

## Combinations that are not implemented

- Joint Gaussian **and** discrete outcomes in one fit.
- REML for discrete outcomes.
- Joint incomplete Gaussian fitting and analytic reliability of an irregular
  observed allocation.
- Fixed-facet categorical simulation targets, arbitrary decision rules and
  nominal numeric-score ratios. Binary/ordinal observed-score, category-vector
  and plurality-decision targets instead require explicit assumptions; none is
  inferred by requesting latent G/Phi.
- Joint optimization of modelled shared-call dependence, request grouping and
  monetary costs. Categorical target cost planning may preserve the fitted
  fixed-call layout, but does not optimize batch size or regrouping. Analytic
  reliability cost planning still refuses modelled `Call` sources.
- Automatic sensitivity analysis for changing source covariances as an
  allocation changes. Analytic intervals can propagate available estimation
  uncertainty; they do not model a different facet population or covariance
  structure in the future protocol.

## Decision studies

- Allocations are balanced and average over the declared random facet
  populations. A fixed facet's count cannot be changed and cannot be projected
  over.
- Extrapolating beyond the fitted counts holds the fitted source covariances
  fixed and assumes the same facet populations remain appropriate. The result is
  a projection under those assumptions; available analytic intervals describe
  estimation uncertainty, not whether those extrapolation assumptions hold.
- For an observed-row Gaussian fit, `gt_dstudy(projection = "balanced")`
  requires every intended facet count and all facets random. This projects
  coefficients for that complete future allocation, not the incomplete fitted
  panel. The lme4 route supplies no coefficient intervals.
- Categorical simulation targets pair future panels sharing only the object
  main effects and redrawing instrument, interaction and eligible call effects.
  The score and category-vector ratios are absolute repeated-panel targets;
  they are not relative G coefficients. Ordinal score values must be specified.
  Plurality decisions use independent uniform tie-breaking and report decision
  diversity: a constant label has perfect agreement but no discrimination.
  Targets and their Monte Carlo errors hold fitted parameters fixed. They are
  not chance-corrected agreement, parameter confidence intervals or evidence of
  annotation accuracy.
- Weak positive object signal can produce frequent unavailable Monte Carlo
  ratios. Available-only summaries can then be biased upward even when their
  conditional error bands appear adequate. Retain every attempted seed and
  refusal; do not replace refused runs or clip raw ratios into [0,1]. Increasing
  objects per panel does not remove variation from shared instrumentation.
  Precision planning needs independent panel pairs, an explicit budget within
  the resource limits, and verification of both availability and numerical
  precision at that budget. The usual inverse-square-root budget scaling is
  a pilot approximation, not a guarantee near zero signal.

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
  Categorical observed and decision target planning permits point screening
  only. Its Monte Carlo standard errors cannot be used as parameter confidence
  bounds; integration precision is a separate planning requirement.
- `gt_simulate()` supports balanced Gaussian panels without batches and
  univariate or joint categorical panels, including eligible fixed-call layouts.
  It preserves fitted families, thresholds and covariance structures. All
  instrumentation facets are sampled afresh. Generated rows and estimated
  workspace have explicit caps; simulation does not refit or assess coverage.
- The interval-width route of `gt_pilot_plan()` supports Gaussian and binary/ordinal outcomes, including
  joint outcomes, without a batch declaration. It refuses nominal and
  call-effect pilot precision. Binary/ordinal precision uses latent coefficients
  and requires optional usable information for intervals. Pilot fitting needs
  at least two levels on each axis. `target_counts` can specify a different
  final protocol, including a facet count of one, held constant across pilot
  candidates. The total generated rows and attempted refits are bounded; these
  are pilot-scale scenarios, not qualification of a full-panel refitting campaign.
- Categorical point-target pilots also support nominal and eligible fixed-call
  models. They compare available estimates with one independently integrated
  scenario reference. Bias/RMSE condition on target availability and the
  recorded reference; empirical variability includes inner integration noise.
  Near weak signals, selection of available targets can affect both bias and
  RMSE. Interpret these with all-attempt availability, without replacing failed
  targets with new seeds.
  Reference MC error is reported separately. They supply no parameter
  intervals or coverage, and refuse an interval-width criterion. The target
  protocol is fixed across pilots; fixed-call membership and object count
  cannot change. Combined reference, pilot and inner simulation work is bounded.
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

These additional capabilities are in local development source version
1.0.0.9000. Their implementation and statistical limitations are described
above; full-scale and interval-coverage qualification remain open. Source
versioning does not establish final-archive qualification, GitHub publication
or CRAN acceptance; see [development status](DEVELOPMENT_STATUS.md) for the
corresponding evidence.

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
