# Roadmap

Release history and development priorities, with current implementation separated
from release qualification. The source is **0.4.1.9000**. The qualified published
0.4.1 archive remains unchanged; the planning additions below do not constitute
a 0.5.0 release or assert CRAN submission or acceptance. Completed source changes
are recorded in [NEWS.md](../NEWS.md), and source-identified run evidence belongs
in [development status](DEVELOPMENT_STATUS.md). Nothing here is a release date.

Numerical backend refactoring is reviewed separately from new statistical
targets. The current planning additions reuse the existing fit and acceptance
rules; they do not repair or replace the optimizer or expand sparse qualification.

| Version or workstream | State and scope |
|---|---|
| 0.1.0 and 0.2.0 | Historical published releases; their tagged archives remain immutable |
| 0.4.0 | Prepared and tagged but not published; superseded by 0.4.1 |
| 0.4.1 | Retained qualified maintenance archive, including the recorded noLD reference-backend correction and evidence |
| 0.4.1.9000 | Current development source: fixed-layout Gaussian batch projections, bounded cost-aware allocation search, and Gaussian pilot precision simulation; separate new-source qualification required |
| Future sparse milestone (previously planned as 0.5.0) | Public backend selection only after dense-sparse qualification and the declared full-panel resource benchmark; no release is implied by this target label |
| Further statistical development | Broader validation campaigns, unbalanced targets, discrete uncertainty and joint batch/cost planning |
| 1.0 | Future API stability and a substantially broader validated operating range |

## Current development: study planning

The intended next feature release is **0.5.0 Study Planning**, covering the
three additions below. The source remains development `0.4.1.9000` until a
separate final-version candidate is prepared and qualified. This scope does not
complete the former sparse milestone or joint batch/cost planning.

Three implemented additions separate pilot information, final annotations per
item and items per request:

- `gt_batch_reliability()` and `gt_batch_dstudy()` provide point projections for
  accepted equal fixed Gaussian batches. The estimands distinguish absolute
  item error, same- or different-batch contrasts and weighted aggregate error.
  Grouping and batch size stay fixed; every instrumentation facet remains random.
- `gt_plan()` searches a supplied finite grid under dated, user-supplied monetary
  costs and constraints. It retains all candidates, cost ties, Pareto status and
  baseline error contributions, with separate point or available-lower-bound
  screening. Modelled `Call` fits remain outside this cost planner.
- `gt_simulate()` and `gt_pilot_plan()` support Gaussian parameter scenarios and
  bounded pilot-refitting experiments. Pilot item/facet counts can change while
  one final target protocol stays fixed. Every failure remains in the ledger,
  and reported Monte Carlo errors use explicit denominators.

The implementation checks in [validation scope](VALIDATION_SCOPE.md) establish
specific numerical contracts, not a scientifically adequate pilot size or
calibrated interval coverage. The new [planning vignette](../vignettes/study-planning.Rmd)
is a synthetic software illustration.

Next planning work needs its own estimands and evidence: joint layout-aware cost
search; randomized batch-composition and position experiments with a collection
manifest; propagation of pilot-parameter uncertainty; discrete observed-decision
targets; calibrated precision/coverage campaigns; and independent human-reference
analyses. These are future work, not capabilities implied by the new interfaces.

The sparse backend, unbalanced designs and complete engine modularization remain
separate workstreams from the current planning additions.

The future sparse-backend work is tracked as separate reviewable changes:
[engine extraction](https://github.com/Veronica0206/Gtheory4LLM/issues/2),
[sparse prototype](https://github.com/Veronica0206/Gtheory4LLM/issues/3),
[dense-sparse equivalence](https://github.com/Veronica0206/Gtheory4LLM/issues/4),
[warm starts](https://github.com/Veronica0206/Gtheory4LLM/issues/5),
[automatic differentiation](https://github.com/Veronica0206/Gtheory4LLM/issues/6),
[staged diagnostics](https://github.com/Veronica0206/Gtheory4LLM/issues/7), and
[the full native-panel benchmark](https://github.com/Veronica0206/Gtheory4LLM/issues/8).
The first extraction moves the discrete response functions unchanged; sparse
fitting begins only after that baseline is preserved.

The [GitHub milestone](https://github.com/Veronica0206/Gtheory4LLM/milestone/1) groups
this work; issue state and milestone naming should be checked live before a
release decision.
Issue #2 includes both the mechanical move in PR #11 and the remaining dense
backend interface; the move alone does not complete it. Issue #3 then builds
the prototype with its own fixed-parameter parity and limited fitted/rejection
checks. Issue #4 follows with full qualification, so #3 does not depend on #4.
Diagnostics can follow the interface independently. The full-panel benchmark
requires qualification and diagnostics, plus warm-start or AD qualification only
if those features are used.

Warm starts and automatic differentiation are **conditional** for the future sparse milestone, not
required. They enter the release only if the benchmark shows the cold sparse
implementation cannot meet its declared resource envelope, and the measurement
decides which — conditional-mode iteration and outer finite differences are
different bottlenecks with different answers. Adopting either unmeasured would
be optimizing a cost nobody has observed.

Complete Gaussian engine modularization is likewise not a requirement for that sparse milestone.
The required scope is the sparse prototype, dense-sparse qualification, staged
diagnostics, the full-panel benchmark, and the resolution of the numerical
portability issue those results depend on.

## Existing numerical baseline

`tests/package-characterization.R` pins what the current engines produce for ten
canonical cases — Gaussian ML and REML, multivariate, a variance boundary, fixed
facets, a nested design, binary, ordinal and multinomial Laplace, and a
deliberately rejected discrete fit. Optimizer-dependent quantities are compared
with tolerances; acceptance decisions are compared exactly.

Every refactor below is judged against it. Its purpose is to make one question
answerable: *did we change the statistical result on purpose, or by accident?*

## Future sparse backend: qualification gates

### Release gates

Five gates decide readiness, each with evidence tied to the exact source
identity, and a failed gate is recorded rather than re-scoped:

| Gate | Required evidence |
|---|---|
| Numerical safety | Sparse and dense enforce the same solve-validity and final-factor invariants, with deterministic injected-failure tests; original-evaluation evidence and opt-in specimens for failures (done on this line, see NEWS) |
| Qualification | The frozen dense-sparse equivalence study executed end to end: measurement layer, calibrated tolerances committed in their own change, the reviewed runner, and a record that reports planned, unsupported, validity-event and compared cases separately |
| Public usability | An explicit backend selector with a resource contract shared by `gt_preflight()` and `gt_fit()`; an explicit sparse request runs sparse or refuses, never substitutes; the backend identity survives retention and serialization |
| Scalability | One predeclared nine-source full-row native binary or ordinal panel accepted within a resource budget declared before the run, from a freshly installed archive |
| Interpretation and provenance | Latent-only coefficients, no discrete intervals, and a support table whose claims match the retained records |

Warm starts remain conditional on the measured need recorded in
`validation-studies/discrete-sparse-profile/results.md`; automatic
differentiation is deferred by default.

### Extract the engines into ordinary modules

The two large engines become ordinary namespace components before anything is
built on top of them, and the closure-factory construction is phased out once
the characterization tests cover what it does.

```
gaussian_prepare.R   gaussian_strata.R    gaussian_parameters.R
gaussian_likelihood.R  gaussian_optimizer.R  gaussian_acceptance.R
gaussian_uncertainty.R

discrete_prepare.R   discrete_response.R  discrete_covariance.R
discrete_mode.R      discrete_laplace.R   discrete_optimizer.R
discrete_acceptance.R
```

`R/gaussian_retry.R` is the first of these, extracted in 0.1.0 because
replacing the retry accounting required it to be independently testable. The
rest follow the same rule: extract, show the characterization baseline is
unchanged, then build.

`load_functions.R` remains a documented developer and source-mode compatibility
path in the current development source. Any future deprecation needs an explicit
announcement and an equivalent supported workflow.

### A sparse discrete backend

The dense engine is not stretched to 21,600 rows by raising limits. A separate
sparse backend is built beside it, and the dense one **remains available as a
reference implementation**: it is the thing a small example is checked against.

```
family likelihood
  -> random-source covariance representation
    -> sparse design representation
      -> conditional-mode solver
        -> Laplace marginal likelihood
          -> outer optimizer / automatic differentiation
            -> independent acceptance diagnostics
```

The prototype now on this line uses `Matrix` (CHOLMOD) sparse storage,
factorization and solves behind a private marginal-evaluator seam, so the
outer optimizer, restarts and acceptance stay single-sourced with the dense
path. TMB was weighed for its automatic differentiation and set aside on
dependency weight and portability; AD remains conditional, as stated above.

Users must always be able to tell which backend produced a result.

### Warm starts and gradients

Conditional work, adopted only on measured evidence; see the sparse scope above.

The dense engine starts the conditional mode from zero at every likelihood
evaluation. A sparse backend should cache the previous mode and start from it
when the parameters have not moved far — while **always retaining a zero-start
validation path**, so that a warm-start history cannot conceal a bad local mode.

For the outer problem, prefer automatic differentiation or verified analytic
gradients over hand-maintained finite differences. Finite-difference
stationarity then survives as an *independent* check rather than as the
optimizer's own machinery: optimize with AD, verify locally with a finite
difference that shares none of its code.

### External comparison suite

For the subsets where the model structures genuinely coincide: `lme4::glmer`,
`ordinal::clmm`, adaptive quadrature for small univariate cases, the existing
dense engine, and independent low-dimensional numerical integration. These are
references for those subsets. None of them is treated as universal truth.

### Success criterion

> At least one full 21,600-row native binary or ordinal panel passes preflight
> and fits within documented resource requirements.

Not every joint model, and not immediately.

### Tiered discrete diagnostics

The current binary accept/reject does not become "warn and continue". It gains
states, so that a rejection says which stage failed:

```
optimization_completed
conditional_mode_valid
stationary
restart_stable
numerically_accepted
approximation_validated
```

reported as, for example:

```
optimizer:                       passed
conditional mode:                passed
stationarity:                    passed
restart stability:               inconclusive
numerical acceptance:            failed
Laplace approximation validation: not assessed
```

The default rule is unchanged: `gt_reliability()` requires
`numerically_accepted == TRUE`. If an expert override is ever added it must be
explicit and uncomfortable — an `allow_unaccepted = FALSE` argument with a
prominent warning — and it is not added in 0.1.x.

## Further scientific development

### Scientific validation program

This matters more for 1.0 than any remaining code-cleanliness item. Simulation
matrices vary: number of objects; facet levels (2, 3, 5, 10+); variance ratios
(zero, near-zero, balanced, dominant); reliability (low, medium, high); boundary
frequency; univariate and multivariate outcomes; none, one and several fixed
facets; crossed, nested and mixed structures; discrete prevalence (rare,
balanced); random-effect variance; and cluster size.

Gaussian models are assessed on bias, RMSE, coverage, boundary behaviour,
likelihood accuracy, and reliability bias and interval coverage. Discrete models
are assessed separately on parameter recovery, reliability recovery, numerical
acceptance rate, Laplace approximation error, boundary behaviour, convergence
rate, and runtime and memory.

Every study distinguishes four different things that are easy to conflate:

> optimizer failure · numerical acceptance failure · approximation error ·
> statistical estimation error

[Validation scope](VALIDATION_SCOPE.md) already records the design rules these
campaigns must follow: predeclared generating model and estimand, retained
attempts, acceptance rates reported before bias, and Monte Carlo standard errors.

### Unbalanced designs

Only after the Gaussian engine is modular. The exact balanced decomposition is
one of this package's real strengths and is not weakened by forcing unbalanced
observations through the same algebra. Instead there are two named backends:

- `balanced_exact` — today's decomposition, unchanged
- `unbalanced_mixed` — a separately identified estimator

and the fit always says which produced it. Reliability semantics for unbalanced
designs need defining first; this is not a data-preparation feature.

### Remaining D-study research

Finite-grid monetary search, user constraints, Pareto status and baseline error
explanations are implemented by `gt_plan()`. Work beyond that scope includes
joint optimization of statistically modelled batch layouts and cost, uncertainty
propagation across parameter scenarios, evaluator-identity selection under a
matching model, and prediction for a future annotation panel. Lower-bound
screening of inherited pointwise intervals does not complete those tasks.

### Discrete uncertainty

Not rushed. Only after the sparse likelihood and its approximation accuracy are
convincingly validated. Candidates: observed-information/Hessian uncertainty,
profile likelihood, parametric bootstrap, and simulation-based propagation to
reliability. For reliability coefficients specifically, a bootstrap is likely
more defensible than applying a Hessian-based delta method to every discrete
model. This remains future research; the Gaussian pilot helper does not implement it.

## Test infrastructure

Migrating to a test framework is not the priority; the independent numerical
coverage is. Property-based tests (`tests/package-properties.R`) and fuzz tests
(`tests/package-fuzz-inputs.R`) are in place, and `tests/README.md` is the map.

Grouping the tests into per-area directories was considered and **not** done,
for a concrete reason: `R CMD check` runs only the top-level `.R` files of a
built package's `tests/`, so moving the installed `package-*.R` tests into
subdirectories would silently remove them from the release gate. Moving only the
source-only tests would leave a half-and-half layout that is harder to navigate
than the current naming convention. Revisit this if the installed and source
test sets are ever separated for another reason.

Remaining:

1. Keep the standalone independent numerical scripts even if a framework is
   introduced. They matter precisely because package internals do not generate
   both the result and its supposedly independent reference.
2. Extend the property set as models are added: an unbalanced backend and a
   sparse discrete backend each need their own invariances, and the two discrete
   backends must agree with each other on the cases both can fit.
3. Mutation testing as a routine gate for the important numerical guards: invert
   an inequality or remove a rank check, and a test must fail. Individual
   mutants have been checked by hand against the weighting code, the retry
   controller and the fuzz harness; the gap is automation, not intent.

## Repository maintenance

- Update the pinned GitHub Actions to majors whose runtime is natively
  supported. The runners already execute the current pins on Node 24, so this
  is maintenance rather than a fix; [repository policy](REPOSITORY_POLICY.md)
  records the pinned and current majors and what an upgrade has to touch.
- Maintain the configured branch and `v*` tag protection and verify them after
  policy changes. The active tag rule blocks updates and deletions with no
  bypass actors; see [repository policy](REPOSITORY_POLICY.md).
- Sign release commits and tags. Nothing depends on it today, and the artifact
  manifest already ties a bundle to a source commit, but a signature is the
  cheapest provenance improvement available once a release process is stable.

## Documentation

Hand-written `NAMESPACE` and `man/*.Rd` are kept. They are richer than generated
pages would be, and roxygen would not solve the actual problem, which is
synchronization — that is what `tests/test_documentation_consistency.py` checks.
