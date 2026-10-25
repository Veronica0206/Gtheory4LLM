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
release history and is not published. Against the 1.0.0 source, its
fingerprinted R files are identical except `R/discrete.R`,
`R/discrete_boundary_escape.R` and `R/preflight.R`, which differ only by the
discrete boundary-escape trial budget and preflight coordinate check; Gaussian
fits do not reach those lines. `DESCRIPTION` differs in its version.
The executed runner, [run-executed.R](results/run-executed.R), is identical to
[run.R](run.R). [summarize.R](summarize.R) rebuilds `replicates.csv` and
`summary.csv` byte for byte from the retained per-replicate rows. The run used
R 4.5.3 and OpenMx 2.22.11 on macOS (arm64) with 13 worker processes; fitting
took 714 cumulative seconds and bootstrapping 68,028.
