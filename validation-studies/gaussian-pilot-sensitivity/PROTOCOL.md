# Gaussian pilot sensitivity illustration

Declared on 2026-10-09, before numerical execution. The configuration and runner
are fingerprinted before generating study panels. This is a bounded illustration
of the planning workflow, not a coverage study or an automatic recommendation
for a minimum pilot size. Do not alter scenarios or seeds after seeing results.

## Scientific question and model

For a fixed final protocol of four independently sampled random raters, how do
the interval width and fitting outcomes change when a pilot contains two or four
raters, under interior or near-boundary generating variance components?

All panels follow the univariate crossed model
`score[item,rater] = item_effect + rater_effect + residual`, with independent
zero-mean Gaussian effects and one observation per cell. Every pilot has 40 new
items and entirely new rater levels. There is no call effect, fixed facet,
missingness, nesting, outcome transformation, or parameter reuse across panels.

The [configuration](config.csv) fixes four independent cells, each with 100
replicates. Item and residual variances are both 1. Rater variance is 0.25 in the
interior scenario and 0.0001 in the near-boundary scenario. These labels describe
generating parameters; an interior scenario can still yield boundary estimates.
The four cell seeds, in the displayed order, are 61091, 61092, 61093, and 61094.
The package records separate data-generation and optimizer-retry seeds for each
replicate. There are 400 planned study refits, with no selective reruns.

The estimand is absolute dependability, `Phi`, for the same final four-rater
protocol in every cell. Its generating value is
`1 / (1 + (var_rater + 1) / 4)`: approximately 0.761905 and 0.799984, respectively.
These truths provide context, not a criterion for selecting or excluding fits.

## Accepted template and explicit parameter scenarios

`gt_pilot_plan()` requires an accepted fitted model. The runner creates the
existing deterministic source-test fixture: seed 199, 24 items, four raters,
independent generating standard deviations 2, 0.5, and 1. It fits REML with
diagonal random-source covariance and a pooled residual, then requires numerical
acceptance and convergence. Failure stops the experiment; no replacement seed
or parameter search is allowed. Fitted component values and acceptance are saved.

The template supplies the declared model and fitting settings only. Both study
scenarios pass all three generating variances and the zero mean explicitly, so
the study does not depend on the template's estimated variance magnitudes. REML,
CSOLNP, one thread, 3000 maximum iterations, tolerance `1e-12`, nine extra tries,
and Hessian checking apply to the template and every study refit. Default
acceptance rules are unchanged. Each replicate has its own retry seed.

## Outcomes and denominators

Retain every attempted refit, including errors, numerical refusals, unavailable
intervals, warnings, acceptance failure codes, and selected optimizer attempt.
Do not extract a coefficient from an unaccepted refit. Preserve boundary and
conditional-interior inference indicators.

Report acceptance, refusal, interval availability, conditional intervals, and
precision success by cell. Precision success means a finite nominal 95% interval
for the fixed target protocol with width at most 0.20. Its denominator is all
100 planned attempts per completed cell; an error, refusal, or missing interval
is a non-success. Mean interval width and its Monte Carlo standard error (MCSE)
condition on interval availability. Also report success among available
intervals, with that smaller denominator explicitly named.

Rate MCSE is `sqrt(p * (1-p) / n)` with the corresponding denominator. At an
observed zero or one rate, the plug-in MCSE is zero; it does not establish a
zero underlying risk. Exact 95% binomial intervals accompany the all-attempt
rates. No empirical coverage, ranking test, calibrated power, or universal
pilot-size recommendation is claimed. Width comparisons retain conditional
intervals but cannot validate boundary coverage.

## Execution, preservation, and limits

The runner refuses to overwrite a nonempty output directory. It records the
source commit, working-tree status, SHA-256 fingerprints of executable R sources
and protocol files, package/dependency versions, platform, R RNG, and timings.
The package source must be committed and unchanged at execution. It verifies
fingerprints again at the end and retains partial completed cells if a later
cell fails. A 600-second budget is checked between cells; an incomplete run must
be reported as incomplete, never filled by selected replacement fits.

An optional two-replicate-per-cell smoke run may check the runner's bookkeeping
in a separate output directory. It cannot change the fixed configuration or
contribute to reported study results. The full run is separate from routine
package checks. The results apply only to these four balanced univariate
Gaussian settings on the recorded local environment; they do not establish
coverage, multivariate behavior, batch-aware pilot planning, or noLD behavior.

For archive-based reproduction, set `GT_STUDY_LIBRARY` to an isolated library
containing the installed package. This mode fingerprints the installed package
files and study files, records its mode explicitly, and relies on the caller's
separate archive identity record. It makes no source-commit identity claim.
