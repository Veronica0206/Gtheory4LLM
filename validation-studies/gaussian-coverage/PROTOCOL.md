# Gaussian coefficient interval coverage: bounded pilot

This pilot checks the simulation and reporting workflow and looks for regions
that merit a larger study. Forty replicates per scenario and estimator give an
approximate Monte Carlo standard error of 0.034 at 95% coverage. They cannot
establish nominal coverage or a general validated operating range.

## Data-generating process and estimands

For each complete item-by-rater panel, independently generate
`y[i,r] = mean + a[i] + b[r] + e[i,r]`, with mutually independent, centered
Gaussian effects and variances in `config.csv`. Generate new item and rater
effects in every replicate. Fit the specified item, rater, and residual sources;
one observation per cell makes the residual the combined cell-level error.
The package receives no true variances or starting values. This pilot has no
fixed facets, no missing cells, and no within-cell replication.

The target is the population reliability of a score averaged across `n_raters`
new random raters. Its independently specified coefficients are

```
Erho2 = var_item / (var_item + var_residual / n_raters)
Phi   = var_item / (var_item + (var_rater + var_residual) / n_raters)
```

These targets describe the generating population, not the realized sample
variance of the generated effects. ML and REML estimate the same population
targets; neither is assumed to yield unbiased coefficient estimates. Near-zero
and zero rater variance probe selection onto a nuisance variance boundary while
keeping both true coefficients strictly inside (0, 1).

## Frozen initial run specification

- Four scenarios in `config.csv`: interior, three raters, near-zero rater
  variance, and exactly zero rater variance; forty replicates each.
- Both ML and REML use the same generated panel in a replicate. Data seed is
  `seed_base + replicate`, and optimizer retry seed is that value plus 500000.
  The paired estimators and common seed construction are recorded explicitly.
- Source the current checkout with `load_functions.R`; do not use an installed
  copy of the package. Fit diagonal source and pooled residual covariance with
  CSOLNP, one thread, 3000 iterations, tolerance 1e-12, nine extra trials, and
  Hessian diagnostics enabled. These are the current Gaussian defaults apart
  from making the univariate covariance form explicit.
- Use the package's 95% delta-method intervals transformed to the logit scale.
  Keep its boundary and conditional-interior inference policy unchanged.
- Attempt scenarios round-robin within each replicate, then ML and REML. Stop
  before starting another fit when cumulative fit time reaches 240 seconds.
  This is a between-fit budget, not an interrupt of native optimizer code. Save
  the full schedule, including any unattempted rows, so early stopping is visible.
- No outcome-driven changes to scenarios, seeds, intervals, or stopping rules.
  Each invocation must use an empty results directory, preserving prior runs.

## Retention and reporting

`replicates.csv` retains every attempted fit, accepted or rejected, including
optimizer status, boundary sources, restricted-interior inference, warnings,
issues, unavailable-interval reasons, point estimates, intervals, and timing.
`schedule.csv` also records every planned fit and whether it was attempted.
Exact source-file MD5 fingerprints, source Git commit, package versions, RNG
settings, and run metadata accompany the results. MD5 is used for reproducibility
identification, not as a security or authenticity claim. No raw fitted models or
machine-specific library paths are published.

For each scenario, estimator, and coefficient, `summary.csv` reports planned,
attempted, accepted, usable-point, and usable-interval counts. Bias and RMSE use
only accepted finite point estimates. Mean-estimate Monte Carlo error is the
replicate standard deviation divided by the square root of that count. Coverage
uses accepted fits with finite, ordered intervals; its denominator is always
reported. Also report the fraction of all attempts that yield a usable interval
and the fraction that yield an interval covering truth. This last fraction is
procedure success, not conditional interval coverage. Proportions include
binomial standard errors and exact 95% Clopper-Pearson intervals. Zero estimated
binomial standard error at an observed rate of zero or one does not mean zero
uncertainty; inspect the binomial interval.

`boundary-summary.csv` additionally stratifies accepted fits by whether any
variance is classified at a boundary and whether the interval calculation
conditions on an interior block. These post-fit strata are descriptive, not
preselected populations or independent validation scenarios. `recovery.csv`
reports source-variance bias and RMSE among accepted finite estimates. Warnings
and rejected fits are never silently omitted or counted as covered intervals.

## Reproduction

From the repository root:

```
Rscript validation-studies/gaussian-coverage/run.R /tmp/gaussian-coverage-rerun
```

The default destination is `validation-studies/gaussian-coverage/results` and
must be empty. Source/config changes require a separately retained run. A broader
campaign needs more replicates and designs: multiple facets, fixed sets, nested
sources, multivariate covariance, low reliability, item-variance boundaries, and
near-singular matrices are outside this pilot.
