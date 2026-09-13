# Roadmap

Planned work, in the order it is planned, with the reason for that order. None
of it is done; what is done is in [NEWS.md](../NEWS.md) and
[development status](DEVELOPMENT_STATUS.md). Nothing here is a release date.

The ordering rule this follows is worth stating once, because it explains most
of the sequencing decisions below: **numerical refactoring, API changes, release
tooling, and new statistical capability do not travel together.** When a result
moves, it must be obvious which of those caused it.

| Release | Goal |
|---|---|
| 0.1.0 | Credible research beta: release identity, scope wording, governance, missing tests |
| 0.1.1 | Engineering hardening: retry controller, standard generics, retention controls, memory guard, release automation |
| 0.2.0 | Scalable discrete architecture: sparse backend, warm starts, gradients, modular engines, tiered diagnostics |
| 0.3.x | Broader statistical operating range: unbalanced designs, larger validation campaigns, cost-aware D studies, discrete uncertainty |
| 1.0 | Stable general research package: defined API stability, broad validation envelope, mature Gaussian and discrete implementations |

The sparse backend, unbalanced designs, and complete engine modularization are
deliberately **not** requirements for 0.1.x.

## Before anything else: the numerical baseline

`tests/package-characterization.R` pins what the current engines produce for ten
canonical cases — Gaussian ML and REML, multivariate, a variance boundary, fixed
facets, a nested design, binary, ordinal and multinomial Laplace, and a
deliberately rejected discrete fit. Optimizer-dependent quantities are compared
with tolerances; acceptance decisions are compared exactly.

Every refactor below is judged against it. Its purpose is to make one question
answerable: *did we change the statistical result on purpose, or by accident?*

## 0.2.0

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

`R/gaussian_retry.R` is the first of these, extracted in 0.1.1 because
replacing the retry accounting required it to be independently testable. The
rest follow the same rule: extract, show the characterization baseline is
unchanged, then build.

`load_functions.R` stays as a documented developer and source-mode compatibility
path through 0.1.x. It is deprecated once ordinary package-development workflows
cover the same use, and removed no earlier than 0.2.

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

TMB is the leading candidate, because sparse random-effects Laplace calculation
with automatic differentiation is what it exists for. It has to be weighed
against dependency weight and portability before it is adopted, not after.

Users must always be able to tell which backend produced a result.

### Warm starts and gradients

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

## 0.3.x and beyond

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

### D-study improvements

Automatic minimum-allocation search; budget-constrained designs; cost per
evaluator, prompt and run; Pareto frontiers of reliability against cost;
sensitivity to variance-component uncertainty; and constraints such as a minimum
number of evaluators or a fixed facet count. LLM measurement studies carry real
token, API and compute costs, so this is where the package could be most
distinctive.

### Discrete uncertainty

Not rushed. Only after the sparse likelihood and its approximation accuracy are
convincingly validated. Candidates: observed-information/Hessian uncertainty,
profile likelihood, parametric bootstrap, and simulation-based propagation to
reliability. For reliability coefficients specifically, a bootstrap is likely
more defensible than applying a Hessian-based delta method to every discrete
model. This is a 0.3+ feature.

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

## Documentation

Hand-written `NAMESPACE` and `man/*.Rd` are kept. They are richer than generated
pages would be, and roxygen would not solve the actual problem, which is
synchronization — that is what `tests/test_documentation_consistency.py` checks.
