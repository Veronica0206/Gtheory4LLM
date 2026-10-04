# Executed pilot results

Acceptance and disposition counts are primary. Every planned row is retained.

| Setting | Accepted / attempted | Rejected | Errors | Timeouts | Unstarted | 95% Wilson Monte Carlo interval |
|---|---:|---:|---:|---:|---:|---|
| Binary: balanced / 24 items | 10 / 10 | 0 | 0 | 0 | 0 | 72.2%–100.0% |
| Binary: rare / 12 items | 10 / 10 | 0 | 0 | 0 | 0 | 72.2%–100.0% |
| Ordinal: balanced / 24 items | 9 / 10 | 1 | 0 | 0 | 0 | 59.6%–98.2% |
| Ordinal: rare / 12 items | 9 / 10 | 0 | 1 | 0 | 0 | 59.6%–98.2% |

Recovery below is **conditional on numerical acceptance and a finite estimate**. MCSEs use the usable n in each row; ten or fewer repetitions give poor precision.

| Setting | Estimand | Usable n | Truth | Mean | Bias (MCSE) | RMSE (MCSE) |
|---|---|---:|---:|---:|---:|---:|
| Binary: balanced / 24 items | variance | 10 | 0.500 | 0.332 | -0.168 (0.033) | 0.195 (0.036) |
| Binary: balanced / 24 items | reliability | 10 | 0.800 | 0.709 | -0.091 (0.028) | 0.125 (0.039) |
| Binary: rare / 12 items | variance | 10 | 0.500 | 0.243 | -0.257 (0.123) | 0.450 (0.059) |
| Binary: rare / 12 items | reliability | 10 | 0.750 | 0.356 | -0.394 (0.109) | 0.513 (0.083) |
| Ordinal: balanced / 24 items | variance | 9 | 0.500 | 0.440 | -0.060 (0.064) | 0.191 (0.023) |
| Ordinal: balanced / 24 items | reliability | 9 | 0.800 | 0.755 | -0.045 (0.027) | 0.088 (0.017) |
| Ordinal: rare / 12 items | variance | 9 | 0.500 | 2.942 | 2.442 (1.213) | 4.210 (1.110) |
| Ordinal: rare / 12 items | reliability | 9 | 0.750 | 0.781 | 0.031 (0.077) | 0.220 (0.059) |

Bias MCSE = sd(error)/sqrt(n). RMSE MCSE is a delta-method approximation using squared errors. These describe simulation noise, not uncertainty intervals for individual fitted parameters.

Inspect `attempts.csv` for every error, rejection, warning, category count and runtime; `details/` keeps returned numerical diagnostics locally; those RDS files are not included in the public checkout. See the [public evidence inventory](../PUBLICATION_NOTE.md). No failed panel was replaced or rerun. The displayed estimates are not selected by closeness to truth.

This small pilot neither identifies a reliable operating range nor separates finite-sample and first-order Laplace approximation bias. The few-group setting also changes replication and rarity. No interval-coverage, observed-score reliability, sparse-backend, or production-readiness conclusion follows.

![Acceptance and conditional recovery](pilot.png)

The left panel uses attempted-fit denominators and Wilson 95% Monte Carlo intervals. Filled points are accepted fits; open crosses in the variance panel are rejected diagnostic estimates. Dashed marks show generating truths. Latent reliability is extracted only for accepted fits.
