# Object-bootstrap coverage pilot results

All 800 planned replicates ran under the [protocol](PROTOCOL.md), which was
committed before execution. Every fit was numerically accepted, every bootstrap
reached its 500 accepted refits in 500 attempts, and every leave-one-out set was
complete. Each table row summarizes 200 generated panels of 24 items; the three
interval methods are computed on the same panels, so they are paired, not
independent, comparisons.

| Setting | Erho2 delta | Erho2 percentile | Erho2 BCa | Phi delta | Phi percentile | Phi BCa |
|---|---:|---:|---:|---:|---:|---:|
| Interior components, six raters | 97.0% | 94.0% | 93.3% (193) | 95.5% | 92.0% | 89.1% (174) |
| Three raters | 97.0% | 92.5% | 92.4% (198) | 95.0% | 89.5% | 89.2% (194) |
| Rater variance 0.001 | 96.0% | 93.5% | 93.8% (193) | 95.5% | 92.5% | 90.6% (170) |
| Rater variance exactly zero | 96.0% | 92.0% | 93.2% (192) | 96.5% | 91.0% | 92.6% (176) |

Coverage is the share of available intervals that contain the population
coefficient. Delta-method and percentile intervals were available in all 200
panels; the BCa denominators are in parentheses, the rest having an endpoint
beyond the replicates' support. Each proportion has a Monte Carlo standard
error of about 1.5 to 2 percentage points; the [summary](results/summary.csv)
gives exact binomial intervals, all-attempt interval yields and mean widths.

Percentile and BCa intervals fell below the nominal 95% in every setting. The
shortfall also occurs at exactly zero rater variance, where holding the observed
raters fixed omits no variance, so it is not explained by the fixed raters
alone; with 24 items, the object resample itself undercovers. Delta-method
intervals covered at or above the nominal level. In panels of this size the
bootstrap intervals therefore complement the model-based intervals rather than
replace them. These are pilot proportions for one Gaussian design; they do not
establish coverage for other designs, larger panels, discrete families or
multivariate models.

## Source identity

The run executed a frozen copy of source commit `a962a4d`, recorded in
[run-metadata.csv](results/run-metadata.csv) with the
[source fingerprints](results/source-files.csv). That commit preceded the
release history and is not published. These are historical pilot results, not
an execution of the current submission archive.

Against the adopted `403aa86` source, 29 of the 41 fingerprinted files are
identical. The twelve differences are:

- `R/discrete.R`, `R/discrete_boundary_escape.R` and `R/preflight.R`: the
  discrete boundary-escape trial budget and preflight coordinate check, which
  Gaussian fits do not reach;
- `R/discrete_mode.R` and `R/discrete_sparse_mode.R`: the shared roundoff
  safeguard and its use by the dense solver, outside the Gaussian path;
- `R/bootstrap.R`: restoration of labeled binary responses; a guard requiring
  the same instrumentation layout for every object; correction of the
  recorded Gaussian retry seed; and the submission-review checks that supplied
  data and refit controls belong to the fit, which change neither the resample
  nor the refit. The pilot uses complete panels and an explicit
  retry seed. That explicit seed already governed the original refits; the
  later correction records it accurately rather than changing the seed used;
- `R/fit.R`: the observation identity `gt_fit()` records before retention, an
  additional field of the fit that enters no estimate;
- `R/discrete_gradient.R`: the nominal tail curvature products of the analytic
  gradient, which Gaussian fits do not reach;
- `R/report.R`: report validation of bootstrap results; the runner builds no
  report;
- `R/examples.R`: the `numeric` coding name and its `manuscript` alias; the
  runner loads no bundled dataset;
- `DESCRIPTION`: the version;
- `summarize.R`: extended after the run to read the consolidated
  `replicates.csv`; the summarizer that ran is retained as
  [summarize-executed.R](results/summarize-executed.R).

Those submission-review checks do not turn this historical pilot into a fresh
coverage assessment of the changed source. Its recorded undercoverage and
scope restrictions remain applicable cautions; the pilot has not been rerun
for the adopted candidate.

The executed runner, [run-executed.R](results/run-executed.R), is identical to
[run.R](run.R). [summarize.R](summarize.R) rebuilds `replicates.csv` and
`summary.csv`, either from the committed `replicates.csv` or from a run's
per-replicate rows. On the run's platform (macOS arm64, R 4.5.3) both files are
rebuilt byte for byte from the committed `replicates.csv`. Elsewhere, compare
`summary.csv` numerically: on Linux (aarch64, R 4.5.2) `replicates.csv` is
identical and one mean interval width differs in its last printed digit
(0.186163659435287 against 0.186163659435286, relative difference 5e-15).
From this directory,
`summarize_run("results", "summary-check")` writes into an existing empty
`summary-check` directory and leaves the records unchanged. The run used R 4.5.3
and OpenMx 2.22.11 on macOS (arm64) with 13 worker processes; fitting took 714
cumulative seconds and bootstrapping 68,028.
