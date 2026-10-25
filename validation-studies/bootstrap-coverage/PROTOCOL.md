# Object-bootstrap interval coverage: bounded pilot

This pilot measures how often the object-bootstrap intervals of
`gt_bootstrap()` cover the population G and Phi coefficients, beside the
delta-method intervals computed on the same generated panels. Two hundred
replicates per scenario give an approximate Monte Carlo standard error of
0.015 at 95% coverage. The pilot cannot establish nominal coverage or a general
operating range, and it says nothing about discrete or multivariate models.

## Data-generating process and estimands

The generator, scenarios and targets are those of the
[Gaussian coverage pilot](../gaussian-coverage/PROTOCOL.md). For each complete
item-by-rater panel, independently generate
`y[i,r] = mean + a[i] + b[r] + e[i,r]` with mutually independent, centered
Gaussian effects and the variances in `config.csv`, drawing new item and rater
effects in every replicate. The targets are the population coefficients for a
score averaged over `n_raters` new random raters:

```
Erho2 = var_item / (var_item + var_residual / n_raters)
Phi   = var_item / (var_item + (var_rater + var_residual) / n_raters)
```

Each replicate redraws the raters as well as the items, so these targets
include rater sampling. The object bootstrap resamples items only and holds the
observed raters in every resample. Its intervals therefore do not reflect rater
sampling, and Phi, which depends on the rater variance, is expected to be
covered less often than Erho2 where that variance is not zero. The pilot
measures by how much; it does not assume an answer.

## Frozen run specification

- Four scenarios in `config.csv`, 200 replicates each. Data seed
  `seed_base + replicate`, so the first 40 panels of each scenario are those of
  the Gaussian coverage pilot; optimizer retry seed `data_seed + 500000`;
  bootstrap seed `data_seed + 1000000`.
- REML, the package default, only. Diagonal source and pooled residual
  covariance with CSOLNP, one thread, 3000 iterations, tolerance 1e-12, nine
  extra trials and Hessian diagnostics, as in the Gaussian coverage pilot.
- For every numerically accepted fit:
  `gt_bootstrap(fit, replicates = 500, seed, jackknife = TRUE, cores = 1)`
  with the default attempt budget of 1000, then 95% intervals from
  `gt_reliability()`: delta method (`interval_type` default), percentile and
  BCa.
- Run from a frozen copy of one committed source tree loaded with
  `load_functions.R`. Replicates run in parallel processes; each writes its
  own row as it finishes, and every replicate is attempted. No outcome-driven
  change to scenarios, seeds, intervals or the analysis.

## Retention and reporting

`replicates.csv` keeps every attempted replicate: fit status, boundary sources
and interior-block conditioning of the delta method, the three intervals for
each coefficient, the bootstrap's accepted and attempted refits and
leave-one-out completeness, and timing. For each scenario, coefficient and
method, `summary.csv` reports the replicates attempted, fits accepted,
intervals available, intervals covering the target, coverage among available
intervals with its Monte Carlo SE and exact Clopper-Pearson interval, the
fraction of all attempts yielding an interval and a covering interval, and the
mean interval width. Unavailable intervals are never counted as covering.
Source-file fingerprints, the source commit, package versions and run metadata
accompany the results.

## Reproduction

From the repository root, with an empty results directory and a worker count:

```
Rscript validation-studies/bootstrap-coverage/run.R /path/to/empty-results 4
```
