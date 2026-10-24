# Gtheory4LLM 1.0.0.9000 — Development

<!-- release-identity:start -->
Source version: **1.0.0.9000**.
For versioned archives, manuals and publication status, see the
[repository manifest](https://github.com/Veronica0206/Gtheory4LLM/blob/main/artifacts/manifest.json)
and [GitHub releases](https://github.com/Veronica0206/Gtheory4LLM/releases).
These repository records are excluded from the package archive; this source
version does not assert that a corresponding release has been published.
<!-- release-identity:end -->

This local development version retains the formula interface and historical
release evidence while adding the capabilities below. No numerical acceptance
threshold was loosened; where an optimizer path changed, the change is named.

## Engines

- Public dense/sparse selection for binary, ordinal, nominal and joint
  categorical Laplace fits, `gt_control(discrete = list(engine = "sparse"))`,
  including eligible equal fixed-call effects. Both engines calculate the same
  first-order Laplace objective under the same acceptance rules. Preflight
  applies the selected engine's memory budget; the default row,
  random-dimension and parameter limits remain in force.
- The sparse working-memory guard judges a declared `max_sparse_bytes` against
  the design's structural pattern instead of a dense square. The complete-fill
  bound is kept while it fits the budget; otherwise the exact count of the
  conditional Hessian's structural nonzeros, from the observed pairs of group
  levels, refuses before any pattern is built, or the structural pattern (every
  factor entry nonzero, every latent dimension of an observation coupled) is
  factorized once and the counted Hessian and factor entries give the
  estimate. The counted fill is a planning estimate with the multiplier as
  allowance, not a bound: the fit recomputes its own fill-reducing ordering.
  The old bound made the bundled joint native panels infeasible at their
  declared 8 GiB budget (dense squares of 32 and 73 GiB); the structural
  estimate reports what the design needs, which the joint 21,600-row panels
  still place above the 512 MiB default. Preflight records
  the method and the counts. A feasible factorization establishes neither
  acceptance nor approximation accuracy at that size.
- A compiled selected inverse of the sparse conditional Hessian's Cholesky
  factor (`src/gt_selected_inverse.c`, registered `.Call` entry points wrapped
  by `R/selected_inverse.R`): the inverse's entries on the factor's pattern,
  original-coordinate queries and traces, and per-observation local
  contractions, accumulated in long double. An entry outside the factor's
  pattern is refused, never read as zero, and every declared cap refuses by
  name. It is the first building block of the analytic Laplace gradient; no
  fit uses it yet, and the package now contains compiled code.
- Sparse conditional solves use a bounded derivative check when rounded
  function values block a full Newton step. Outside the small plateau window,
  the candidate must already meet the final score tolerance; final score,
  solve, factor and outer-fit acceptance requirements are unchanged.
- The sparse evaluator retries an evaluation whose cold conditional-mode solve
  ends as a classified convergence failure, once, from the fit's last valid
  mode, under unchanged tolerances, budgets and validity checks. A cold solve
  that failed a solve- or factor-validity invariant is never retried, and a
  retry that fails one is the recorded outcome. Rescued evaluations are marked
  and counted in the fit's evaluation record.
- Within an L-BFGS-B attempt, the sparse evaluator starts conditional solves
  from the attempt's centre mode. The fit supplies the finite-difference
  gradient itself, written out from `optim()`'s own rule so the optimizer's
  path is unchanged, and names each evaluation's role: function evaluations
  start from the centre mode and become the new centre, and every probe of one
  gradient starts from the mode at the point it differentiates. The
  conditional objective is strictly concave in the random effects, so a start
  changes the path to the mode and never the mode: on the frozen calibration
  points and the 21,600-row synthetic panel, warm and cold objectives agree
  within 4.4e-9 at the coarse tolerance and 1.9e-10 at the validation
  tolerance, and at the native 21,600-row panel's starting values within
  1.5e-7 (coarse) and 3.6e-12 (validation), while an evaluation needs about
  three Newton steps instead of seven or eight. Every attempt begins with a
  cold solve; the final checks, the stationarity probes, the information step
  and every `nlminb` evaluation remain cold solves from zero modes. A warm
  solve that stops short of the mode is replaced by the cold solve, which keeps
  the retry from the last valid mode. The evaluation record counts
  `warm_started` and `cold_fallbacks`. The sparse mode solver no longer
  computes the factor's fill counts on every Newton step; `.gt_d_sparse_factor()`
  computes them only when asked, which the diagnostics, tests and profile
  study still do.
- Sparse nominal fits no longer stop when rounding lifts a row of contrast
  probabilities a few dozen ulps above one, which happens where the reference
  category's probability is near zero. The sparse Hessian guard allowed 16
  ulps and stopped the evaluation while the dense assembly accepted the same
  rows; it now allows `sqrt(.Machine$double.eps)` and still refuses inputs that
  are not probabilities.
- Ordinal interval probabilities, scores and curvature retain small tail
  contributions and use a bounded, blocked normal-density quadrature for narrow
  probit intervals. Nominal losses, scores and both backends' curvature retain
  the complement of a dominant category. Binary logit losses, scores and
  curvature retain representable probabilities in the tails. These arithmetic
  repairs leave the first-order Laplace criterion and numerical acceptance
  tolerances unchanged; on a flat ridge an optimizer may stop at a slightly
  different accepted point.
- The exact Gaussian engine recovers once, after an ordinary attempt of a
  multivariate model with an unstructured covariance is refused while an
  attempt remains in the budget, from a bounded L-BFGS-B search on the
  square-root form of the same deviance: stratum covariance roots are QR
  factors of the stacked weighted source factors and the cross-products enter
  through roots taken from the contrast rows, so nearly singular strata are
  evaluated without forming and inverting their covariance. The search starts
  from the declared original coordinates, never from the refused endpoint, and
  its endpoint's covariance components seed the next ordinary attempt, through
  the same path as a user-supplied `start` so that the parameter scales are
  recomputed, only when the search converged, lies within the bounds, and the
  independent deviance reproduces its value within 1e-5. It consumes an existing attempt, adds none, and decides nothing;
  `gt_control(gaussian = list(initialization = "none"))` disables it, and
  `gt_diagnostics(fit)$initialization` records the outcome. An accepted
  primary attempt is identical under both settings. Continuation restarts now
  perturb the best attempt whose likelihood was independently reconstructed, or
  the original start when there is none; a result whose native objective the
  independent evaluation contradicted never seeds a restart, and the attempt
  table records this in `retry_anchor_eligible` and `retry_anchor_attempt`.
  The six-flag
  mental-health panel, whose default start led into a region where the
  algebraic objective was invalid, is what this repairs.
- The lme4 engine's restart check also requires the restart itself to
  complete with optimizer code 0 and no lme4 convergence warning; agreement
  with an incomplete or warned restart no longer counts as reproduction. The
  stability record names the restart's completion and warnings.
- An explicit observed-row univariate Gaussian route through lme4, with an
  independent dense ML/REML likelihood cross-check, covariance-kernel
  identification and row/memory guards. No missing cells are filled.
  `gt_dstudy(projection = "balanced")` projects to a separately declared
  complete allocation; reliability of the incomplete allocation and joint
  incomplete Gaussian fitting remain unsupported.

## Outcomes and targets

- Nominal (unordered categorical) outcomes have latent G and Phi.
  `gt_reliability()` and `gt_dstudy()` report the mean of the generalized
  eigenvalues of the universe covariance relative to universe plus error on
  the K - 1 category contrasts, with `Erho2_min`, `Erho2_max`, `Phi_min` and
  `Phi_max` giving their range and `latent_dimensions` the contrast count;
  the residual is `(pi^2/6)(I + 11')`, so two categories give the binary logit
  coefficient. Generalized eigenvalues are invariant to any change of the
  contrast basis, so the coefficients do not depend on the reference category;
  on a synthetic panel fitted under three references they agree to the
  optimizer's tolerance while a trace ratio moves by 0.005. The delta-method
  interval of the mean uses the observed information and matches a
  finite-difference gradient. A diagonal covariance on the contrasts is a
  different model for each reference, so its coefficient is refused, as is a
  weighted composite with a nominal outcome. Preflight identifies the
  supported nominal latent coefficients, and nominal D-studies use a symmetric
  eigenproblem and preserve unavailable rows at unresolved allocations.
- `covariance = "exchangeable"` for discrete fits with a nominal outcome:
  each source gives every category its own random utility with one variance,
  `sigma^2 (I + 11')` on the contrasts, one parameter per source and outcome
  instead of K(K - 1)/2, in exact-zero-capable variance coordinates; binary and
  ordinal outcomes in the same fit keep one variance each, and outcomes are
  independent within a source. Both engines, the stationarity check, the
  observed information, preflight and the Laplace check support it.
- Joint unstructured discrete fits default to Cholesky coordinates: the
  entries of each source's lower-triangular factor, with a nonnegative
  diagonal that can reach zero. Log-Cholesky coordinates can only approach a
  singular source matrix, and near one the other directions become
  ill-conditioned and the optimizer stalls short of stationarity; joint fits of
  the bundled panels whose evaluator and prompt covariances are singular were
  refused that way. A zero factor diagonal is a natural boundary, recorded with
  the zero-variance parameters, not an artificial bound contact. The
  stationarity check, restart comparison and boundary-interval policy already
  work on covariance matrices and are unchanged. `"log_cholesky"` remains
  available; the paths of joint unstructured fits under `"auto"` change.
  The characterization case `discrete_categorical`, one three-category nominal
  outcome, now reaches its rater covariance's singular boundary: -2 log
  likelihood falls by 1.0e-5, no variance moves by more than 0.14%, and rater
  joins item among the boundary sources. Its stored baseline was recaptured
  for that case only.
- Shared categorical simulation preserves fitted links, thresholds, nominal
  reference contrasts, joint covariance and eligible fixed-call layouts.
  `gt_categorical_target()` separately defines observed-score,
  relabeling-invariant category-vector and plurality-decision targets.
  Decision diversity accompanies agreement, and Monte Carlo errors describe
  integration uncertainty at fixed model parameters. Categorical shared-call
  refusals point to this repeated-panel target API.

## Uncertainty

- Optional discrete observed information includes nuisance intercepts or
  thresholds and covariance parameters. Component uncertainty and latent
  coefficient intervals require acceptance, interior estimated components,
  stable numerical differentiation and positive definite information.
  Unavailable results retain their reason; intervals inherit Laplace error.
  The two central-difference Hessians need `2 * (1 + 2 * p^2)` marginal
  likelihood evaluations for `p` stored parameters, all from cold conditional
  modes, so information can cost much more than point estimation.
- Interval guidance separates true from estimated boundaries, conditional
  coverage from all-attempt availability, and covering-interval yield from
  both. Small-panel Wald intervals can be overly conservative, unstructured
  models can frequently withhold intervals at estimated covariance boundaries,
  and withholding at an estimated boundary does not ensure coverage at a true
  one. Available-only summaries are not a calibration guarantee.

## Planning

- `gt_plan()` can screen the categorical targets over a bounded allocation
  grid using declared costs, and works on fits with nominal outcomes: it built
  one weight per outcome while the covariance matrices are indexed by latent
  dimension, so a three-category nominal outcome made every plan fail with
  non-conformable arguments; weights now follow the fit's latent dimensions,
  a nominal outcome is screened and costed on its mean generalized-eigenvalue
  coefficient, and its scalar universe and error variances and source
  contributions are `NA`, with `provenance$decomposition` saying why.
- Binary/ordinal pilot precision planning refits small complete pilots for
  latent intervals. A distinct categorical point-estimator route includes
  nominal and fixed-call pilots, with acceptance/availability rates,
  conditional bias and RMSE, and separately recorded reference and inner
  integration errors. It provides no parameter intervals or interval-width
  criterion. Near weak signals, selection of available targets can bias both;
  interpret them with all-attempt availability and never replace failed
  targets with new seeds.
- `gt_simulate()` and the categorical pilots refuse covariance overrides that
  break an exchangeable fit's structure: a nominal block must be
  `sigma^2 (I + 11')` and outcomes stay independent within a source; unequal
  diagonals, equal diagonals without the off-diagonal term, and covariance
  across outcomes were previously accepted and simulated under the fit's
  `"exchangeable"` label. Simulated score and category-vector noise use
  nonnegative variance sums instead of subtracting nearly equal moments, and
  item summaries align shuffled groups of unequal sizes and reject invalid
  group identifiers.

## Numerical acceptance and optimizer controls

- A coarse L-BFGS-B attempt whose first step collapses is rerun at the
  per-row scale. Every discrete coordinate has two finite bounds, so
  L-BFGS-B's first trial point is the start minus the raw gradient, a sum over
  rows: on the 21,600-row drug-review panel the default ordinal fits of
  efficacy, safety and burden put the item variance near 4,000, every
  conditional solve there failed, and the primary attempt stopped at its start
  after three evaluations, so the fits were refused. A coarse attempt that ends
  where it began after an invalid evaluation is now run again from the same
  start at a uniform parameter scale of `1/sqrt(rows)`, which makes the first
  step the per-row gradient; the collapsed run is kept in the attempt's
  `first_step_rescue` record. Attempts that move, attempts that ended in an
  optimizer exception, and attempts whose result is unusable are never rerun,
  so a failed attempt stays visible and no other path changes. Tight attempts
  and `nlminb` are not scaled.
- Discrete L-BFGS-B fits offer explicit `optimizer_scaling = "start"` for
  per-attempt coordinate preconditioning. Every metric is recorded; original
  finite-difference steps and independent acceptance checks are unchanged.
  The default optimizer paths remain unchanged.
- Discrete fits accept predeclared named `parameter_bounds` overrides for
  artificial optimizer coordinates. Fitting, preflight and saved-fit Laplace
  checks share the domain validation; natural zero boundaries, default domains
  and all acceptance thresholds remain unchanged. Requested and effective
  domains are recorded, and artificial-bound contact still refuses acceptance.
  Alternative starts remain inside narrowly declared domains; ordinary domains
  retain their existing start coordinates.
- Saved Laplace diagnostics use the fit's recorded covariance coordinates
  rather than a newer default, and `gt_laplace_check()` reads a fit's retained
  responses as the engine's encoding: a binary outcome fitted with labels other
  than `"0"`/`"1"` is retained as 0/1 integers, and the diagnostic refused
  those encodings as new data. Data supplied through `data =` is still
  validated as new data.
- Help defines the existing covariance-based restart comparison, distinguishes
  zero Cholesky pivots from zero marginal variances, and states when preflight
  skips resolved-domain checks after an earlier refusal.

## Interface, documentation and tooling

- Formula reconstruction preserves unusual column names. Formula updates
  refuse declarations whose explicit nesting or source-free facets would be
  lost; ordinary argument updates retain the design.
- `gt_reliability()` and `gt_dstudy()` without a projection on an observed-row
  Gaussian fit name `gt_dstudy(projection = "balanced")` in their refusal. The
  shipped example scripts and help examples read acceptance and attempt
  records through `gt_diagnostics()` rather than fit fields.
- Help and guides no longer say that no scalar nominal coefficient exists, the
  latent-scale guidance names nominal outcomes, and help clarifies stored
  information coordinates, quadratic information cost, and the distinction
  between missing cells and partially observed outcome vectors. The retained
  profiling harness's README says to create the lock's parent directory when
  the harness is copied outside the checkout.
- Validation summaries, package checks, artifact checks and public-content
  audits refuse reused evidence destinations; the manual builder protects
  both the existing PDF and prior build logs. New regressions ship with the
  installed package, including a nominal fit with estimated exchangeable
  covariance and independent coefficient checks, the ordinal and nominal tail
  contracts, the categorical-target moment contract, the two-stage sparse
  memory estimate and the square-root recovery; every test file is listed in
  `tests/README.md`.

Focused reference and refusal tests accompany these routes. This is not a
released or fully qualified 1.0 package: full-panel solver qualification,
approximation assessment, recovery and coverage studies, and final
cross-platform archive validation remain separate gates. Earlier version
records below apply only to their recorded source and archive identities.

# Gtheory4LLM 0.6.1 — Corrections

Four corrections to the 0.6.0 Model Interface release, found in an independent
review. The numerical engines, the acceptance tolerances and every estimate
of an accepted fit are unchanged.

- The lme4 engine's restart check now also requires the restart itself to
  complete with optimizer code 0 and no lme4 convergence warning; agreement
  with an incomplete or warned restart no longer counts as reproduction. The
  stability record names the restart's completion and warnings.
- `gt_laplace_check()` reads a fit's retained responses as the engine's
  encoding. A binary outcome fitted with labels other than `"0"`/`"1"` is
  retained as 0/1 integers, and the diagnostic refused those encodings as if
  they were new data; data supplied through `data =` is still validated.
- Discrete solutions selected from an alternative start keep their parameter
  names, so a warm-start refit from `fit$parameters` is accepted.
- `gt_laplace_check()` estimates its dense reconstruction and integration
  workspace and refuses, before allocating, a comparison whose estimate
  exceeds the discrete `max_dense_bytes` budget; the estimate is recorded as
  `resources`.

# Gtheory4LLM 0.6.0 — Model Interface



This version gives the interface the conventions of other R model objects. The published 0.5.0 archive, its numerical engines, acceptance rules
and every estimate are unchanged.

- The introductory workflow and README now lead with an explicit measurement
  object and model formula, while planning examples explain when a design
  declaration is required. Preflight dimension and factorial-strata fields are
  documented, and planning, pilot-planning and reliability-plot help pages have
  small self-contained runnable examples.
- `gt_fit()` and `gt_preflight()` accept a two-sided model formula in place of
  the outcome names and the design: `gt_fit(score ~ item * rater, data)` or
  `gt_fit(cbind(efficacy, safety) ~ item + rater, data)`, with the data frame
  before or after the formula and a family in the third position as `glm()`
  users expect, or under its own name as `formula =`. The object of
  measurement is named by `measured =`, or else is the first variable on the
  right-hand side, and every print of the fit or its design says which; the
  other variables are the facets. The resolved design is the one `gt_design()`
  builds, recorded with its formula in `fit$design$formula`. The source grammar
  gains `/`, so `question / item_code` declares `question + question:item_code`.
  Replicates, batches and the automatic nesting selectors still need
  `gt_design()`.
- `formula(fit)` returns the model formula of any fit, also one declared with
  `gt_design()`, and `update(fit, . ~ . + item:rater)` refits it from the
  recorded call with the object of measurement carried along; the recorded
  `fit$call` names each argument whichever order it was given in.
- Every fit has the class vector `c("gt_gaussian_fit", "gt_fit")` or
  `c("gt_discrete_fit", "gt_fit")`. The Gaussian engine's internal class label
  and the discrete engine's bare `"list"` no longer appear in `class(fit)`.
- `summary(fit)` carries a Gaussian fit's observed-score reliability at the
  fitted facet counts, or the reason none is reported, and prints it after the
  source variances. `deviance(fit)` returns the fitted objective for every fit,
  including one that failed numerical acceptance; `logLik()` still refuses one.
- A second Gaussian engine: `gt_control(gaussian = list(engine = "lme4"))`
  fits the declared sources as random intercepts with lme4, one outcome at a
  time and with the call source when a batch is modelled. The fit is accepted
  only when lme4's optimizer completes without a convergence warning, the
  package's own stationarity check on lme4's deviance function passes (lme4's
  Cholesky-scaled gradient statistic over interior parameters, and no inward
  one-sided derivative at a parameter on its zero bound), a restart reproduces
  the solution, and the exact balanced deviance evaluated at the estimates
  agrees with lme4's criterion. It computes no source-variance standard errors,
  so reliability-coefficient intervals are unavailable on this path. `gt_diagnostics()` now records
  engine, optimizer and approximation as three separate facts, and exposes the
  stationarity record and, for the lme4 engine, the likelihood agreement
  record at its top level.
- `gt_laplace_check(fit)` compares the first-order Laplace objective of a
  discrete fit, at its fitted parameters, with a refined numerical estimate of
  the marginal likelihood: adaptive Gauss-Hermite quadrature up to four
  random-effect dimensions, defensive-mixture importance sampling otherwise,
  with the Monte Carlo standard error and effective sample size. The mixture
  contains 90% Laplace Gaussian and 10% random-effect prior and uses the full
  mixture density for all weights; the prior component guarantees finite
  weight moments for the categorical probability likelihoods. Monte Carlo
  precision remains a finite-sample diagnostic, not an error bound.
  Limits are applied before anything is allocated, every new solve is
  verified, an unevaluable point makes the estimate unavailable rather than
  zero, and each result carries a usability verdict. The comparison estimates
  a fixed-parameter objective discrepancy, with finite-sample limitations; it
  does not assess parameter bias or refit the model.
- The lme4 engine maps boundary flags through the fitted grouping identities,
  so differing source order and group counts cannot label the wrong variance
  component as zero. `gt_diagnostics()` exposes a `parameter_map` linking each
  retained theta and derivative position to its scientific source and lme4
  parameter identity, including when the engine model is not retained. Existing
  numeric order, integer boundary positions and acceptance arithmetic are
  unchanged. The lme4 path returns source covariance estimates; its unavailable
  quantity is their sampling covariance, not those estimates.
- `gt_design()`, `gt_family()`, `gt_control()`, `gt_batch()`, `gt_score()` and
  `gt_example()` results print as short descriptions instead of raw lists, and
  `gt_pilot_plan()` returns a classed `gt_pilot_plan` with `print()` and
  `as.data.frame()` methods. The elements of every object are unchanged. Print methods wrap long sentences to the console width
  (`getOption("width")`), as R's own printing does.

# Gtheory4LLM 0.5.0 — Study Planning

This version adds bounded study-planning tools. Historical release assets and
the numerical acceptance rules are unchanged.

- `gt_batch_reliability()` and `gt_batch_dstudy()` project item-score, named
  contrast and aggregate error under a fitted equal fixed Gaussian batching
  layout. Targets are conditional on that layout; no new-batch-size effect or
  universal batch-adjusted G is inferred.
- `gt_plan()` enumerates supplied allocation grids and ranks them using dated,
  user-supplied cost assumptions, constraints and point or available lower-bound
  targets. It retains infeasible candidates, Pareto options and baseline
  marginal benefits without changing the declared score universe.
- `gt_simulate()` generates balanced Gaussian studies and `gt_pilot_plan()`
  refits prospective pilot designs, retaining all attempts, numerical refusals,
  interval availability and Monte Carlo uncertainty. These are model-based
  design simulations, not calibrated bootstrap intervals or coverage guarantees.
- Batch D-study data frames retain allocation counts and essential interpretation
  fields in ordinary columns, so CSV exports remain interpretable without R
  attributes. Pilot replicate ledgers retain numerical acceptance-failure codes
  and the selected refit attempt without retaining whole fit objects.
- Batch projections preserve distinct numeric item identifiers, including large
  adjacent values that have the same default printed representation. Use the
  returned `layout$item` keys to name contrast and aggregate weights. This
  corrects a false refusal after an otherwise valid fit; covariance estimation
  and projection arithmetic are unchanged.

# Gtheory4LLM 0.4.1



0.4.0 was tagged and its bundle staged, but it was not published or submitted:
its release check on R built without long double refused a fit on one machine
and the test could not say so. 0.4.1 is 0.4.0 with that test corrected and no
other change to the package.

- `tests/package-characterization.R` required every discrete case to be
  numerically accepted. On some machines the discrete optimizer reports
  completion without reaching a stationary point (#59), the engine refuses the
  fit through its stationarity and restart-stability safeguards, and the test
  then stopped at the coefficients it could not compute. The ordinal case, the
  one case observed to be refused this way, is now reported as that platform's
  outcome when it is refused by those two safeguards and by nothing else: its
  estimates are not compared there, but it must still carry every other
  recorded field, the same model terms and the same variance names. Any other
  case refused this way, a refusal for any other reason, or accepted numbers
  that moved still fail. The acceptance and completion flags are recorded as
  the engine set them, and a fit without a single TRUE or FALSE flag stops the
  test. The comparison and the recording are exercised with constructed
  records and fits before any fit is compared. The engine is unchanged.

# Gtheory4LLM 0.4.0

Changes since 0.2.0. The development line was versioned `0.3.0.9000` and then
`0.4.0.9000`; no 0.3.0 was released. For a design without a batch declaration,
every estimate, coefficient and acceptance decision in
`tests/package-characterization.R` reproduces its values: the fitting
arithmetic is untouched, and the changes add refusals, evidence and reporting.
The one new model is the shared call effect a Gaussian fit estimates for a
design that declares equal fixed batches, described first below.

## Check on R built without long double

- CRAN's check of 0.2.0 on R built without long double stopped in
  `tests/package-discrete-safety.R`, where one ordinal fit on a boundary panel
  was required to be numerically accepted. On that build the optimizer reports
  completion without leaving its starting values, and the fit is refused by
  the stationarity check. Refusing it is the correct outcome; requiring
  acceptance was the test's error.
- The test still asserts on every platform what it exists to guard: no
  evaluation at the variance boundary becomes an attempt error, and the fit
  uses variance coordinates. Accepted fits must reproduce the reference
  likelihood and variance components and yield a finite latent coefficient.
  Other fits must be explicitly rejected, with a nonempty set of reasons
  consisting only of the stationarity or restart/tolerance-stability
  safeguards. Movement away from the starting values does not establish
  numerical acceptance. Constructed records exercise both outcomes and reject
  missing acceptance flags, empty or unexpected reasons, boundary errors and
  accepted records with incorrect reference estimates.
- The optimizer is unchanged. That its search can stall in this way, when an
  unusable evaluation's penalty value enters a finite-difference gradient, is
  a limitation of the discrete engine and is not addressed by this release;
  it is tracked in [issue #59](https://github.com/Veronica0206/Gtheory4LLM/issues/59).

## Declared batches

- `gt_batch()` declares that items were annotated several to a call, and
  `gt_design()` carries the declaration to every function that receives the
  design or a fit. With none declared, items are independent given the
  declared sources and every result is what it was. By default a declaration
  assumes items in one call affect each other equally; `sequential` and
  `neighbor`, both off by default, declare that an item may be affected by a
  stated number of preceding items or of items on either side, at most one
  less than the batch size. `by` names a facet, such as the evaluator, across
  whose levels the dependence may differ.
- Which items shared a call is inferred or recorded. Without `id`, batches are
  cut from the item order and are the same in every condition; that is a
  reconstruction, and it cannot detect items removed after collection. With
  `id` naming a column that identifies each row's call, the calls are read
  from the data and may differ between conditions and in size.
- `gt_preflight()` audits a declaration: the batches, conditions and calls it
  implies or records, whether it describes the data, and, for inferred batches
  whose rows are stored call by call, whether that storage agrees with it.
  Implied calls count one for each batch, condition and declared replicate. A
  call with fewer items present than declared is reported, not treated as a
  mismatch. Recorded calls are counted from the rows supplied: the audit says
  that a call sent short and a call that lost rows afterwards look the same,
  that a call with no row left is not counted, and that positions are ranks
  among the items present, not necessarily the positions at which they were
  sent.
- A Gaussian fit models a declaration when the batches form a complete
  factorial with the facets: the same batches in every condition, each at the
  declared size. It estimates one shared call effect, reported as the source
  `Call` with its standard error, by the exact balanced likelihood, in which
  an item is a batch-by-slot cell. REML and ML fits match lme4's in criterion
  and variances, including a call variance of zero. `gt_preflight()` says
  beforehand whether a fit will model the batches, and why not when it will
  not; its source table, parameter counts and strata describe the sources the
  fit will estimate, the call among them. Whether the batches were modelled is
  recorded for each fit, so a fitted design reused for another outcome family
  does not carry the earlier fit's answer.
- A fit with a call effect has no reliability coefficients or decision study
  yet: the coefficient weights do not account for which items share a call,
  so `gt_reliability()` and `gt_dstudy()` refuse it. `sequential`, `neighbor`
  and `by` are recorded and not yet estimated.
- Every other declaration changes no estimate, and every result says what
  happened to a declaration: fits and diagnostics print the status,
  `not_declared`, `declared_not_modelled` with the reason, or `modelled`;
  coefficients and decision studies print it, their data-frame exports and
  `gt_dstudy_target()` carry `batch_status`, the plots state it where a
  caller's own subtitle cannot replace it, and `gt_report()` records it. The
  exports gain that one column for every design.

## Data checks, reporting and figures

- Outcome profiles describe category frequencies and representation across
  design groups, including absent declared categories and groups with no
  observed variation. These are descriptive summaries, not minimum-information
  rules or guarantees of accurate estimation. Example tables drop unsampled
  factor levels so bounded or empty tables do not retain hidden identifiers.
- Portable analysis reports collect model context, diagnostics, result tables
  and figures without refitting. Exports omit observations and group-level
  identifiers by default and distinguish retained fitting provenance from the
  environment used to generate the report. New discrete fits now record their
  fitting session before retention controls are applied; historical fits with
  no session record remain unknown.
- Preflight exposes bounded examples of missing cells and incorrect
  replication, without constructing the full Cartesian product or editing
  observations. Its panel-audit plot distinguishes complete, missing,
  under-replicated and over-replicated cells; a second view shows random-source
  dimensions. Counts are relative to observed coded levels.
- Reliability and D-study results have flat `as.data.frame()` methods.
  Allocation columns are prefixed, and D-study metadata is joined by design
  identity. Scale, extrapolation and uncertainty status travel with exported
  estimates, including unavailable intervals.
- `gt_dstudy_target()` screens one outcome or composite against an estimated
  G/Phi target within the supplied allocation grid. It preserves all candidates
  and ties; it does not search for a global or monetary optimum.
- Reliability forest plots show G/Phi and available estimation intervals.
  D-study plots add target references, series selection and extrapolation
  markers. These displays use base graphics and can be saved with ordinary
  PNG/PDF devices. The installed tutorial demonstrates the plots and exports.
- A separately frozen 40-fit binary/ordinal probit pilot retains every attempt:
  38 accepted, one numerical rejection and one missing-category error.
  Rare-outcome point recovery can be poor despite acceptance. This is a small
  dense-engine study with explicit Monte Carlo uncertainty, not sparse
  qualification, a coverage study or a general operating-range claim.

## Numerical safety

- The private sparse conditional solver enforces the same two validity
  invariants as the dense one (#46). The Newton step is checked against its own
  system by the shared backward-error rule, applied to the sparse Hessian
  without densifying it, and the final factor is probed with the same two fixed
  vectors before its log determinant enters the objective, through the factor
  object's permutation-aware solve. A violated invariant refuses with
  `sparse_newton_solve_invalid` or `sparse_final_factor_invalid`, exactly as the
  dense solver refuses; there is no fallback, regularization or looser
  tolerance. `tests/test_discrete_sparse_validity.R` injects a corrupted step
  and a factor of a different matrix and checks the refusal, its reason and
  its retained measurements, on the sparse mode solver and end to end through
  the private evaluator seam. The frozen fixed-parameter, conditional-mode and
  fitted sparse contracts reproduce unchanged with the checks in place.
- A discrete fit's starting-value refusal reports the evidence of the
  evaluation that refused (#43). The start is evaluated once, in detailed form,
  and there is no diagnostic replay: a second evaluation that happened to
  succeed would not be evidence that the first was valid, and one that failed
  would only describe itself. The established message and its `reason=`,
  `backward_error=`, `solve_validity_bound=`, `random_dimension=` and
  `probe_index=` fields are unchanged.
- Every objective evaluation the optimizer makes is performed in detailed form
  and reduced to its scalar by a bounded evaluation log, so an evaluation the
  optimizer could not use is described by its own record rather than by a
  recomputation. `fit$diagnostics$evaluations` records the count of
  evaluations, the count the optimizer could not use, the count of valid
  conditional solves that ended at the inner iteration budget, and, for at most
  eight invalid evaluations, the parameters asked about and the measurements
  reported; the conditional-mode diagnostic stage reports the three counts.
  The arithmetic is unchanged, because `details` selects what a mode solver
  returns and never what it computes.
- Setting the environment variable `GTHEORY_DISCRETE_SPECIMEN_DIR` to a
  directory writes a specimen file for each refused start and each retained
  invalid evaluation: the failed operation's matrix, right-hand side, step and
  factor where the failure produced them, the parameters, the measurements and
  the identity of the numerical environment, as numeric objects that can be
  reloaded and replayed. It holds no observations. Off by default; a failed
  write is reported in the refusal message and never masks the refusal.
  `SECURITY.md` says so.
- A conditional solve that did not converge records how it stopped:
  `inner_iterations`, whether the line search failed to improve the penalised
  objective (`inner_line_search_failed`) and whether the final factorization
  was unavailable. Previously a failed evaluation carried no iteration count,
  so the retained scale-risk profile could not attribute its invalid
  evaluations; see the replay recorded in
  `validation-studies/discrete-sparse-profile/results.md`. The profile's work
  pass now reports those stop causes.
- `scripts/replay_specimen.R` reads a specimen back and answers three
  questions separately: whether the stored step still fails the stored
  system, whether the stored factor still fails on this host, and whether a
  fresh factorization here fails too. Its verdict describes those observations
  without inferring a defective matrix, a responsible host, or portability
  from one replay. Reproducing the recorded backward error also requires
  agreement at numerical precision and the same solve-validity decision.
  `tests/test_specimen_replay.R` exercises it on dense and sparse specimens
  written through the real refusal site.
- The shared acceptance rule is mutation-checked in `tests/test_interface.R`:
  the FALSE-only rule it replaced accepts a discrete fixture whose flag is
  `NA`, and the test proves that its own assertion catches that.

## Corrections

- A specimen of a tightened evaluation records the inner tolerance that
  evaluation ran with. The evaluation log passed the coarse control to the
  specimen writer for every phase, so a `tight` specimen reported `1e-7` for an
  evaluation that ran at `1e-9`. The fit and its acceptance were unaffected.
- A solve- or factor-validity event is no longer lost behind routine
  non-converged evaluations. Retained records and specimens shared one
  allowance of eight, which an ordinary fit can use up on routine failures
  alone; a later validity event then left only a count. The evaluation log
  still retains the first eight invalid evaluations and now also retains later
  validity events until eight such events are held, so it holds at most
  sixteen records; `fit$diagnostics$evaluations$validity_events` counts every
  one. These limits and counts cover the optimizer's logged evaluations, not
  final checks.
- A final check that fails with a structured refusal keeps that refusal's
  reason, measurements and parameters in `fit$diagnostics$final_checks`, and
  writes its failed operation as a specimen when a directory is configured.
  Only a raised error's text was kept before, so a refusal returned without
  an error blocked acceptance and left no account of why.
- A refused stationarity probe keeps the refusing evaluation's record in the
  same way, in `fit$diagnostics$outer_stationarity$failure`, and writes its
  failed operation as a specimen when a directory is configured. Its retained
  error named only "invalid conditional mode"; for a solve- or
  factor-validity refusal it now also names the reason and its measurements.
  A probe that merely did not converge keeps the established message.
- The conditional-mode diagnostic stage reports the count of validity events
  beside its other evaluation counts.
- A preflight report no longer keeps the data in its recorded call. Called
  through `do.call()`, or with the data written inline, `gt_preflight()` stored
  the whole data frame in `$call`, unused columns included, whatever
  `max_examples` was. A `data` argument that is not a plain object name is now
  recorded as a marker, as a fit records it when its data is dropped.
- Fit summaries match variance-component standard errors and boundary flags
  by source and outcome separately. Names containing spaces can no longer
  make distinct source/outcome pairs select the same uncertainty row.
- The published `0.2.0` archive, manual, manifest and tag are retained
  unchanged.
- `plot()` on a decision study accepts `col`, `pch`, `ylim`, `xlab` and `ylab`
  through `...`. They were supplied explicitly before the dots were forwarded,
  so passing any of them failed with a duplicate-argument error; they are now
  defaults that a named argument replaces (#39, plotting).
- `logLik()`, and through it `AIC()` and `BIC()`, apply the same acceptance
  rule as `gt_reliability()` and `gt_dstudy()`, from one shared predicate: a
  Gaussian fit is refused on an explicit failure, and a discrete fit must carry
  an affirmative acceptance. A discrete object whose acceptance flag is missing
  or `NA` is refused rather than read as accepted. Freshly fitted objects are
  unaffected; every fitted discrete object carries the flag.
- A discrete fit produced through the private evaluator seam by a backend other
  than the dense one now reports that backend in its public `engine`
  (`sparse_joint_discrete_laplace`), derived from the retained
  `marginal_backend`, so a fit never describes itself as the dense engine when
  another implementation produced it. Dense fits are unchanged, and
  reliability, decision studies and preflight no longer key on the dense
  engine string. No public entry point selects the sparse backend.

## Qualification study

- Calibration case K05 (`cal_tail`) was built with the five-level tail-mass
  construction on a three-level scale, because the level selector recognised
  the exact geometry name while the panel builder recognised any name
  containing "tail": its categories were 15/60/165, with 68.75% of the panel in
  the top category. One explicit definition, `EQ_TAIL_GEOMETRIES`, now serves
  both, and the freeze test asserts the category composition of every
  tail-mass panel rather than only its digest. The original and corrected
  fixture identities are recorded as a pre-calibration amendment in
  `CALIBRATION.md`; the scored case C12 and every other fixture are unchanged,
  and no tolerance had been derived from the defective panel.
- The retained 2,400-row scale-risk specimen was replayed with the failed
  evaluations' own records: every invalid evaluation was conditional-mode
  non-convergence, none was a solve or factor validity event, and the
  backend disagreements were gradients straddling the relaxed final tolerance
  at the iteration budget in the tightened phase. Recorded in
  `validation-studies/discrete-sparse-profile/results.md`.
- The measurement warm starts are conditional on (#5) was taken on that
  specimen with `budget-experiment.R`: a doubled inner budget recovers 32 of
  the 48 unusable evaluations and all 40 marginal solves cold, and a warm
  start from the previous evaluation's mode recovers 38 of 48 at the ordinary
  budget in a median of 9 iterations; 16 evaluations do not converge cold
  within 300 iterations and are not a budget question. The roadmap and
  development status now state the 0.4.0 release gates and this line's
  position against them.

# Gtheory4LLM 0.2.0

Cut from the 0.2.0 development line for the CRAN resubmission. Every estimate,
coefficient and acceptance decision in `tests/package-characterization.R`
reproduces the 0.1.0 values within the tolerances recorded there. The one change
to fitting itself is the refusal of a dense conditional solve that does not
solve its own system, recorded under engineering below. Everything else is new
reporting, corrections, engineering behind private seams, and the release
maintenance that followed 0.1.0.

## Staged numerical diagnostics

- `gt_diagnostics()` gains a `stages` element summarising the numerical checks
  a fit passed through: optimizer completion, conditional mode, independent
  stationarity, restart and tolerance stability, numerical acceptance, and
  approximation assessment, each with a status, a reason and its supporting
  measurements, so a rejection names the stage responsible without the caller
  reading private optimizer records. The status is `passed`, `failed`,
  `not_assessed` for a check that did not run or does not apply to the engine,
  or `inconclusive` for one that ran without a clear verdict; absent evidence
  is never read as a pass. The summary is derived from evidence the fit already
  retained, including the tolerances that governed the retained solve: it never
  refits and never changes an acceptance decision. Print methods are registered
  for the stage summary and for a single stage.
- The conditional-mode diagnostic stage no longer reports `passed` when a
  record says its solve was tightened but does not retain the tolerance that
  governed it. That record now reports `inconclusive`, because the retained
  evidence cannot establish that the solve met what was asked of it. This
  changes reporting only, and only for incomplete or older fit objects: a fit
  produced by this version retains that tolerance. Fitting, numerical
  acceptance, and reliability and D-study eligibility are unchanged.

## Corrections

- README links to repository documents that the source archive does not ship
  (`docs/`, `scripts/VALIDATION.md`, `validation-studies/`, `artifacts/`,
  `SECURITY.md`, `LICENSE`) are now absolute repository URLs. CRAN's incoming
  check reported the relative `scripts/VALIDATION.md` and `LICENSE` links of
  the 0.0.6 submission as invalid file URIs; a test now refuses any README or
  NEWS link to a file that `.Rbuildignore` keeps out of the archive.
- `SECURITY.md` named a control that does not exist. The retention switch is
  `gt_control(retain = list(data = FALSE))`.
- `BIC()` on a REML fit is documented, and its convention, N response vectors
  with the covariance parameters only, is recorded as
  `reml_BIC_response_vectors_variance_parameters`. `help("gt_fit")` no longer
  says the generic criteria are unavailable for REML: the fit's own `AIC` and
  `BIC` elements are `NA`, the generics are not.
- `load_functions.R` sources `R/discrete_sparse_mode.R`, matching the Collate
  field; a test keeps the two lists equal.
- `print(gt_diagnostics(fit))` states the standard-error availability once.
- A Gaussian source flagged at the boundary is now classified as entirely zero
  or as singular but nonzero, and interior-block standard errors say which
  they condition on. A rank-deficient source with positive variances was
  described as "held at zero" in the fit's interpretation, its diagnostic
  issues and the printed coefficient note; it is now described as held fixed
  at its fitted covariance, from one shared clause. `gt_component_vcov()`
  adds `conditional_on_fixed` naming every fixed component, and
  `conditional_on_zero` now names only the zero ones. The boundary flag, the
  point estimates and the interval arithmetic are unchanged (#36).
- `logLik()`, and through it `AIC()` and `BIC()`, refuse a fit that failed
  numerical acceptance, as `gt_reliability()` already did; the objective
  stays in `minus2loglik` for diagnosis. The generics previously returned
  ordinary values while `print(fit)` called the estimates diagnostic only.
- `gt_control(retain = list(data = FALSE))` now removes every copy of the
  observations. The retained Gaussian OpenMx model carried the raw outcomes as
  summary metadata, so a fit saved after dropping the data still held them,
  and the recorded call held the whole data frame, unused columns included,
  when the fit came through `do.call()` or with the data written inline.
  The observations are stripped from the retained model, which nothing reads
  after fitting, the call's data argument is replaced by a marker, and a
  test hunts a sentinel observation and a sentinel unused column through the
  serialized fit for direct, programmatic and inline calls. `SECURITY.md`
  says so.
- Gaussian facet levels are matched by value rather than by their printed
  form. Distinct doubles that format alike, such as `1e15` and `1e15 + 1`,
  passed `gt_preflight()` and were then refused by `gt_fit()` as duplicate
  cells; they now fit (#39, facet identity).
- Gaussian outcomes are centred before the factorial contrasts are formed.
  The intercepts are profiled exactly in a balanced design, so no likelihood
  term changes, but a large common offset no longer enters the contrasts as
  differences of huge sums: an offset of `1e12` moved accepted estimates in
  their fifth digit and `1e15` in their second. A regression fits the same
  represented panel at the origin and at an offset of `1e12` and requires
  identical variances and deviance.
- `summary()` of an ordinal fit no longer lists the outcome's location under
  "Fixed location or contrast estimates": it is fixed at zero for
  identification and is now printed as such. Binary intercepts and
  categorical contrasts are still printed as estimates.
- A discrete fit's design notes, and so `gt_diagnostics()`, no longer carry
  the constructor's specification-only note after the engine's data checks
  have run; the discrete path now records its validation scope through the
  same step the Gaussian path uses.
- The limitations page states the balance requirement per engine: the
  Gaussian likelihood needs a complete balanced panel, the discrete Laplace
  likelihood accepts missing whole cells at the declared replication, and
  reliability and D studies need the complete panel in either case.
- `scripts/prepare_release.py --from-checked-candidate` refuses a candidate
  directory without a check report recording a successful R-devel check of
  exactly those archive bytes, and records the checking R version in the
  manifest's provenance.

## Engineering behind private seams

- The dense conditional solve now refuses a factorization that does not solve
  its own system (`dense_newton_solve_invalid`, `dense_final_factor_invalid`),
  reporting the backward error and its bound when the refusal happens at the
  starting values. A native Cholesky can return successfully and still hand
  back a factor of some other matrix; issue #14 captured one such instance on a
  hosted runner, and a returned factor is no longer treated as valid merely
  because no error was raised.
- The discrete engine is split into response-kernel, dense, mode and sparse
  modules without numerical change. `Matrix` and `methods` joined Imports for
  the private sparse random-design, Hessian, factorization and conditional-mode
  files behind a private evaluator seam. None of it is public API: no public
  entry point selects the sparse path, and every fit still runs through the
  dense engine. The compatibility matrix runs the sparse factorization test on
  every platform.

## Release maintenance after 0.1.0

- Keeps archive source-version summaries publication-neutral; publication
  updates only excluded repository metadata. Preparation rejects an already
  tagged or published version before building.
- Separates the development checkout from the published 0.1.0 archive and
  manual, whose files and tag remain unchanged.
- Updates installation instructions to the published GitHub release, records
  the configured branch protection and publication checks, and moves completed
  0.1.0 hardening out of the future roadmap.
- Distinguishes the rebuilt R-devel candidate from the published archive;
  candidate-check evidence applies to the file actually checked.
- Catches stale publication claims outside the release summary blocks and
  records the active rule preventing release-tag updates and deletions.

# Gtheory4LLM 0.1.0

First 0.1 release. An earlier 0.1.0 candidate was prepared locally but never
tagged or published, so this release is cut from the hardened sources instead
and supersedes it; the notes below cover both. The statistical models are
unchanged from that candidate: every estimate, coefficient and acceptance
decision in `tests/package-characterization.R` reproduces its values within the
tolerances recorded there.

## Numerical baseline

- Adds a characterization baseline over ten canonical cases (Gaussian ML and
  REML, multivariate, a variance boundary, fixed facets, a nested design,
  binary, ordinal and multinomial Laplace, and a deliberately rejected discrete
  fit). Optimizer-dependent quantities are compared with tolerances, acceptance
  decisions exactly. Regenerating it is deliberate and must be explained here.

## Nested designs

- Adds reliability, mixed fixed/nested weighting, and decision-study regression
  tests for `p x (i:h)` and for `p x (i:h) x r` with a fixed facet, with every
  expected coefficient written out from the published formulas rather than
  produced by the code under test. Nested designs were previously exercised only
  at the specification level: no nested model was fitted, and no nested
  reliability or decision study was computed.
- `help("gt_design")`, `help("gt_reliability")` and `help("gt_dstudy")` now
  define *balanced coded panel* explicitly, with a worked contrast between
  globally unique child labels and within-parent codes.

## Optimizer retrying

- Replaces transcript-parsing retry accounting with a retry controller that
  drives the optimizer directly, in `R/gaussian_retry.R`. Every attempt now
  records a real optimizer status; previously a trial run inside OpenMx's own
  retry loop could be recorded with an unknown status, and a change in OpenMx's
  message wording could fail an otherwise valid fit.
- `fit$retry_attempts` gains `start_type` (replacing `start`) and
  `optimizer_success`, and drops the transcript-specific `native_attempt`,
  `invocation`, `continuation_reason` and `native_returned_fit` columns.
  `attempt`, `optimizer`, `status`, `minus2loglik`, `external_accepted`,
  `external_rejection_reason`, `error` and `returned_fit` are unchanged.
  `fit$retry_settings$native_invocations` becomes `optimizer_runs`.
- The retry policy itself is unchanged: at most `extra_tries + 1` runs, each
  unsuccessful run followed by OpenMx's own bounded uniform perturbation of the
  best model so far, stopping at the first externally accepted run.

## Standard methods

- Adds `logLik()`, `nobs()` and `coef()` methods for `gt_fit`, and a print
  method for `gt_diagnostics()`, which now returns a classed object.
- `AIC()` and `BIC()` reproduce the fit's own recorded conventions: an ML fit's
  `ml_AIC` and `ml_BIC_response_vectors`, a REML fit's
  `reml_AIC_variance_parameters`. A REML `logLik` carries `REML = TRUE`; a
  discrete one is labelled as a first-order Laplace approximation.
- Adds `gt_component_vcov()` for the sampling covariance of the estimated source
  covariances, which is what `gt_reliability()` propagates into an interval.
- `vcov()` on a fit raises an error rather than returning that matrix. In R,
  `vcov(fit)` is the covariance of `coef(fit)`, and generic tooling relies on
  the pairing; this package does not estimate it, because Gaussian outcome means
  are profiled out of the likelihood and the discrete engine computes no
  observed information. The error names the reason and points at
  `gt_component_vcov()`.

## Controls

- `gt_control()` gains `retain`, choosing which optional components a fit keeps:
  `data`, `model`, `retry_log` and `session`. Every default is `TRUE`, so an
  existing call is unaffected. Dropping all four reduced a 600-row Gaussian fit
  from 525 KB to 64 KB with every reported result identical, including
  reliability, decision studies, diagnostics, correlations and the component
  covariance.
- Every fit now records a compact `panel` summary, so reliability and decision
  studies remain available when the modelled data was not kept. Where the data
  is kept it is still what the balanced-panel rules are checked against, so a
  panel edited after fitting is still caught.
- The discrete engine gains `max_dense_bytes` (default 512 MiB), checked before
  allocation. The other discrete limits bound counts; this bounds the dense
  algebra those counts imply, which is what protects a caller who raises them.
  The refusal names the estimate, the limit, the observation count, the random
  dimension, the size of the random-design matrix, and the alternatives. It does
  not bind for any model the existing count limits already allow.

## Release and repository

- `artifacts/manifest.json` declares `release_state`, and the marked README and
  NEWS blocks declare it too. Publication is now checked against git: a
  `published` claim requires the version tag, and a `prepared` claim fails once
  that tag exists. Nothing calls a bundle published before it is.
- Adds `scripts/prepare_release.py`, which derives every version from
  DESCRIPTION, validates, builds the archive and manual, writes the manifest,
  rewrites the release blocks, verifies the result, and stops. It never tags,
  pushes, uploads or submits.
- `scripts/check_public_contents.py` no longer hard-codes the version: the
  package name comes from DESCRIPTION and the bundle version from the manifest,
  which is what lets a development checkout retain the preceding bundle.
- Adds `docs/REPOSITORY_POLICY.md` with the required branch-protection state,
  `docs/branch-protection.json` as the exact payload, and
  `scripts/check_branch_protection.py` to verify it. The declared branch
  protection was applied to `main` after the release was published.
- Adds `SECURITY.md` and `CODEOWNERS`.
- The reference manual build falls back to plain `R CMD Rd2pdf` when R's
  generated LaTeX is not the layout its customized cover knows how to reflow,
  and reports which route it took and whether the overfull-box gate could run.
  The manual gate now requires both `pdflatex` and `makeindex` before claiming
  it can run, and names the missing tool when it skips.
- The renv bootstrap is described by `scripts/dependency-locks/renv-bootstrap.json`,
  verified by SHA-256 before installation, and preferentially taken from a cache
  that both locked workflows now keep. Pinning a version says which renv is
  used; the digest and the cache are what make retrieving it checkable and
  possible.

## Fixes

- `plot()` on a decision study now reports an invalid `coefficient` instead of
  failing on a zero-length condition.
- `gt_preflight()` and `gt_fit()` now share one definition of the covariance and
  residual rules, so a request one accepts is a request the other accepts.
  Previously preflight admitted a `Residual` covariance override that fitting
  refused, and fitting completed abbreviated residual names that preflight
  rejected. Both now refuse both, with the same message.
- A local variable named `T` in the discrete engine no longer shadows the `TRUE`
  alias.
- Four overfull boxes introduced by the new help pages are fixed in the Rd
  content rather than by relaxing the gate that found them, and the locked
  workflow now preserves the manual's LaTeX log and rendered PDF as build
  evidence: the log is the only place that says which box overflowed.
- The renv bootstrap digest is recorded and enforced. It was computed from an
  independent download of the pinned URL and matches the digest the locked
  workflow computed; a mismatch now refuses to install.
- During release preparation, the install instructions pointed to the local
  prepared bundle. The development notes above record their subsequent update
  to the published GitHub release.
- `docs/LIMITATIONS.md` collects every limitation in one place; the other
  documents link to it. `docs/ROADMAP.md` records planned work.
  `docs/DEVELOPMENT_STATUS.md` now holds only the current state.

## Release scope

The capability this release ships, unchanged from the earlier candidate.

- Consolidates the reviewed development API for univariate and multivariate
  Gaussian models and small binary, ordinal, and unordered categorical models.
  Designs support explicit crossed/nested random sources, selected item
  interactions, and source-specific covariance. The numerical engines and
  fitting limits are unchanged from 0.0.7.
- Retains exact balanced Gaussian ML/REML, Gaussian variance standard errors
  and coefficient intervals, supported fixed-facet reliability, and balanced
  decision studies. Discrete likelihood uses first-order Laplace integration
  with Gaussian random effects; binary/ordinal coefficients require the latent
  scale, and discrete uncertainty intervals are not implemented.
- Includes the three public LLM annotation panels and an executable real-data
  and failure tutorial explaining native outcomes, model choices, numerical
  diagnostics, and full-panel discrete fitting limits.

## Reproducible statistical pilots

- Adds protocols, seeds, source fingerprints, environment records, all
  attempted replicates, and summaries outside the installable package.
- Records 320 Gaussian fits across four univariate settings and ML/REML, with
  40 replicates per setting/estimator. Observed coefficient coverage was
  90--100%, with wide Monte Carlo intervals; these pilots do not establish a
  general coverage guarantee or validate boundary-conditioned inference.
- Records 180 fixed-parameter discrete panels across binary and ordinal
  logit/probit and nominal softmax models. Independently integrated references
  converged under refinement; 165 package comparisons were available and 15
  were unavailable because a declared category was absent. Nonzero Laplace
  errors are retained rather than treated as software-test failures.
- Records 40 binary recovery fits across four settings. All were numerically
  accepted, but short panels produced variable variance estimates and boundary
  solutions. Numerical acceptance does not establish accurate recovery.
- These results were generated against the recorded 0.0.7 source. Their
  original provenance remains unchanged; the 0.1.0 release does not imply a
  new simulation campaign or expanded statistical operating range.

## Release and validation infrastructure

- Corrects release-version prose and checks DESCRIPTION, the archive manifest,
  release summaries, and optionally the release tag for consistency.
- Covers all pull-request and main-branch changes in CRAN candidate readiness,
  pins external Actions to verified commits, and cancels superseded runs.
- Makes compatibility checks retrieve the recorded release source history
  needed to verify committed artifacts.
- Adds a documentation dependency lock and drift checks while preserving the
  numerical dependency versions. The locked workflow restores both stacks;
  current-R candidate checks retain their separate environment.
- Clarifies parameter uncertainty versus new-panel prediction, fixed-facet
  choices, and what temperature-specific agreement can establish.
- Adds contribution, release, and statistical-validation scope guidance.

The version change does not add sparse fitting, unbalanced Gaussian estimation
or reliability, cost-aware planning, bootstrap/jackknife, or discrete intervals.
GitHub publication and package checks are separate from CRAN submission and
acceptance.

# Gtheory4LLM 0.0.7

## Fixes found in review of this release

- The `variance` covariance coordinates, which `auto` now selects for every
  univariate or diagonal discrete model, treated any negative coordinate as an
  error. A bounded optimizer evaluates a few ulps outside a bound while
  projecting onto it, so a coordinate of -3.4e-17 recorded an attempt error,
  set `computation_failed`, and rejected the entire fit. Zero is this
  parameterization's natural domain boundary, so rounding noise is now
  projected onto it; a coordinate meaningfully below zero still stops. This
  rejected fits whose estimates were already correct, including the ordinal fit
  in `examples/standalone_usage.R`.
- The same rounding noise could also appear in the parameter vector a bounded
  optimizer returns, not only in the points it evaluates. A converged result
  reported a few ulps outside its bound was discarded as "no usable finite
  result", which failed the fit. Returned parameters are now projected onto
  their bounds with a tolerance that scales with each bound's own magnitude, so
  a point meaningfully outside is still refused.
- A source variance resting on the boundary now reports `NA` rather than a
  number whenever the joint Hessian happened to stay invertible, matching what
  it already reported when the Hessian did not. No symmetric interval follows
  from curvature at a boundary. The full entry covariance matrix is unchanged
  in `$uncertainty`, and coefficient intervals still use it.
- The interval caveat names at most three sources inline and otherwise gives a
  count and a pointer; on the bundled panels it listed all thirteen.
- Adding a vignette made `R CMD build` write `build/vignette.rds` and
  `inst/doc/` products into the archive, which no release gate expected. The
  public-content audit rejected the build index as an unexpected build file and
  then as a malformed example resource; the committed-artifact gate would have
  reported every generated vignette product as content missing from git at the
  next release. Both now account for them, and `inst/doc/` products are derived
  from the vignettes declared in the source commit rather than excused by
  prefix, so an unexpected file there still fails.
- When knitr, rmarkdown, or pandoc is absent, `R CMD check` failed the whole
  package on `Packages suggested but not available`, reporting a missing
  documentation toolchain as a package defect. The gate now checks with
  `_R_CHECK_FORCE_SUGGESTS_=false` in exactly that case, and accepts the single
  extra `--as-cran` line about a missing vignette index only when vignettes
  were genuinely skipped, so it can never excuse a real one.
- The locked Linux environment could not build rmarkdown because `fs` needs
  libuv headers, and `install.packages()` only warns when a build fails, so the
  step passed while the toolchain was absent. The workflow installs `libuv1-dev`
  and the step now asserts the result instead of reporting success either way.
- Clarifies that `fixed = "temp"` selects a reliability estimand after fitting;
  it does not alter the fitted variance model. A within-temperature analysis is
  one conditional sensitivity analysis when pooling is questionable.

## Uncertainty for Gaussian fits

- Reports asymptotic Wald standard errors for every Gaussian source variance.
  The engine already computed the restricted- or profile-likelihood Hessian for
  its diagnostics and discarded the result; it now forms the parameter
  covariance matrix `2 * H^-1` and keeps it. Reconstructed values match OpenMx's
  own standard errors to machine precision and match the classical mean-square
  formulas for a crossed two-way design to five significant figures.
- Adds delta-method standard errors and logit-scale intervals for G and Phi in
  `gt_reliability()` and `gt_dstudy()`, per outcome and for weighted composites.
  New `level` argument; new `Erho2_se`, `Erho2_lower`, `Erho2_upper`, `Phi_se`,
  `Phi_lower`, and `Phi_upper` columns. `plot.gt_dstudy()` draws the bounds.
  Deterministic tests check the delta-method mapping. A previously reported
  pilot coverage range has no reproducible protocol/results in the public
  repository and does not define a validated operating range.
- A zero-boundary variance can accompany unusable joint Hessian curvature,
  which previously removed every standard error. Standard errors are now computed on
  the interior block, conditional on the zero components being held at zero, and
  both the fit and the printed coefficients say so. A component held that way
  reports `NA`, never a structural zero that would read as certainty.
- Standard errors are unavailable, with a stated reason, when `check_hessian` is
  disabled or the curvature is unusable. The discrete Laplace engine computes no
  observed information and says so rather than leaving the field empty.

## Mixed-model fixed facets

- Adds `fixed` to `gt_reliability()` and `gt_dstudy()`, implementing the mixed
  model of Brennan (2001): the object-by-fixed-facet variance is averaged over
  that facet's levels and joins universe-score variance, a source built only
  from fixed facets shifts every object equally and leaves the model, and every
  other source keeps its usual divisor. With no fixed facet the decomposition is
  unchanged. `$source_roles` records the role each source took.
- A fixed facet's count cannot be changed and a decision study cannot project
  over it, because its universe is exactly its observed levels. Declaring every
  facet fixed is refused: that design has no estimable error variance.

## Designs and documentation

- Adds `full_cell` to `gt_design()`. `full_cell = FALSE` removes exactly the
  object-by-all-facets source and leaves every other requested source
  unchanged, which is how a binary or ordinal study with one observation per
  cell declares the default crossed design. The discrete rejection message now
  names that argument. The source is still never dropped automatically.
- Converts the installed tutorial into a real knitr vignette, so
  `browseVignettes("Gtheory4LLM")` finds it. `system.file("doc",
  "LLM-workflow.R")` and the installed HTML keep working.
- Makes `man/*.Rd` and `NAMESPACE` the only documentation source of truth. The R
  files previously carried roxygen blocks that were not the source of the richer
  hand-written Rd pages; running roxygen2 would have replaced them and dropped
  the S3 methods registered in `NAMESPACE`. Those blocks are now plain comments.
- Documents temperature and seed as study-design choices. Observed agreement
  differences across temperatures motivate diagnostics but do not by themselves
  prove heterogeneity of latent random-effect variances.
- States that the native discrete codings of the bundled panels exceed the dense
  discrete engine by more than an order of magnitude, and explains why the
  declared `R (>= 4.5.0)` floor comes from OpenMx's under-declared C API
  requirement rather than from this package's own code.
- Repairs two tests left inconsistent by the `covariance_parameterization`
  default change, and adds installed-package regression tests for standard
  errors, the delta-method mapping, coefficient intervals, mixed-model fixed
  facets, and `full_cell`.
- Stops the public-content audit from failing a working-tree scan on operating
  system metadata such as `.DS_Store`, which git already ignores and a desktop
  environment recreates. The exemption is by exact filename, is reported under
  `skipped_os_metadata`, and never applies inside an archive.
- The package build now knits the vignette, so `scripts/check_package.py` needs
  knitr, rmarkdown, and pandoc. When they are absent it records that, builds
  with `--no-build-vignettes`, checks with `--ignore-vignettes`, and the
  installed-tutorial stage prints `NOT RUN` rather than passing silently. The
  three workflows install the toolchain.

## Smaller interface and reporting changes

- Adds concise reliability and decision-study print methods while preserving
  complete results and diagnostics; resets coefficient row names.
- Adds `counts` to `gt_reliability()` with the existing `design` argument retained
  as a compatibility alias.
- Labels and retains Gaussian derivative-pass warnings separately from optimizer
  acceptance, and removes stale pre-fit validation notes after preparation.
- Improves unsupported full-cell and balanced/nested design guidance without
  changing the requested statistical model.
- Defaults discrete covariance coordinates to `auto`: direct variances for
  univariate/diagonal models and log-Cholesky for joint unstructured models.
  Explicit choices and numerical acceptance criteria remain available.
- Corrects the public package citation and explains full-panel discrete limits,
  mental-health preprocessing, and coefficient interpretation more directly.
- The 0.0.7 source archive and reference manual remain available in the
  [v0.0.7 GitHub release](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.0.7).

# Gtheory4LLM 0.0.6

- Prepares the package for its first public distribution under GPL-3.
- Bundles eight outcome sets and fifteen codings of three real, publicly
  archived LLM annotation panels. Preserves public-source checksums, CC BY 4.0
  data attribution, response mappings, and the three dataset reference chapters.
  Rebuilding modeling resources accepts explicitly supplied public-source CSVs;
  verification requires no external files or network access.
- Adds `gt_preflight()` to report resolved sources, covariance and random-effect
  dimensions, replication/completeness, resource limits, and supported scales.
- Adds an installed synthetic LLM tutorial completing fitting, diagnostics,
  G/Phi calculation, and an 18-allocation decision study.
- Makes installed example loading independent of ambient workspace variables;
  intentional directory overrides support RDS resources and source CSV files.
- Adds a concise classed fit summary and shared diagnostic fields for selected
  attempts, rejection reasons, natural covariance boundaries, and artificial
  parameter bounds. Existing estimates and numerical acceptance rules are
  unchanged.
- Preserves explicit starting values, fixed optimizer selection across fitting
  attempts, reproducible retry controls, and failed-fit safeguards.
- Requires R 4.5 or later because the supported OpenMx dependency uses an R 4.5 API.
- Adds minimum-R and Windows/macOS compatibility workflows beside the locked
  Linux numerical checks, plus one source-and-artifact release-check entrypoint.

Scope at 0.0.6 was exact balanced Gaussian likelihood and small-model
first-order Laplace discrete likelihood. Discrete latent random effects remain
Gaussian. Binary/ordinal reliability requires an explicit latent scale;
unordered categorical scalar reliability, observed-score discrete reliability,
joint Gaussian-discrete fitting, bootstrap/jackknife, and uncertainty intervals
of any kind were not implemented in that release. (The development version adds
asymptotic Wald standard errors and delta-method coefficient intervals for
Gaussian fits only; see above.) Numerical tests do not establish parameter
recovery, approximation adequacy, or application-wide statistical validity.
