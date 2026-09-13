# Gaussian coverage pilot results

All 320 planned fits completed in 80.62 cumulative fit seconds under the
[protocol](PROTOCOL.md). Every fit was numerically accepted and supplied both
coefficient intervals. Each table row below represents 40 generated panels;
ML and REML use paired panels, so their results are not independent replicates.

| Setting | ML G coverage | REML G coverage | ML Phi coverage | REML Phi coverage |
|---|---:|---:|---:|---:|
| Interior components, six raters | 100% | 100% | 100% | 100% |
| Three raters | 97.5% | 97.5% | 97.5% | 97.5% |
| Rater variance 0.001 | 92.5% | 92.5% | 90% | 90% |
| Rater variance exactly zero | 95% | 95% | 95% | 95% |

These are pilot proportions, not coverage guarantees. For example, 36/40
coverage has an exact 95% binomial interval of 76.3–97.2%, while 40/40 has an
interval of 91.2–100%. The estimated Monte Carlo SE is zero at an observed 100%
rate; that does not mean zero uncertainty. Forty replicates cannot establish
that the nominal 95% procedure performs adequately in a scenario.

Near-zero rater variance was classified at a boundary in 25/40 fits for each
estimator. Four in each case used conditional interior-block inference. At
exactly zero rater variance, boundary counts were 28/40 for ML and 26/40 for
REML, with five interior-block calculations each. Thus even when every fit
supplies an interval, its inferential conditions can differ.

The full [summary](results/summary.csv) includes bias, RMSE, interval widths,
coverage denominators, Monte Carlo SEs, and binomial intervals. The
[boundary-stratified summary](results/boundary-summary.csv) is descriptive
after-selection information. [Source recovery](results/recovery.csv),
[every fit](results/replicates.csv), and the [planned schedule](results/schedule.csv)
remain available. No failures or boundary estimates were removed.

## Execution and reporting correction

The original runner completed all 320 fits and saved their rows, then failed
while parsing its reporting section because a function-closing brace was
missing. Its environment metadata also needed explicit character conversion
of the R version. Neither problem changed any generated data, fit, interval
or stored estimate. We retained that exact runner as
[run-executed.R](results/run-executed.R), fixed the reproduction runner, and
regenerated descriptive tables from the saved rows using [summarize.R](summarize.R).
The environment record was corrected to R 4.5.3. No numerical fits were repeated
or selected in making those repairs.

[Source fingerprints](results/source-files.csv) identify the original execution
snapshot, corrected runner, and postprocessor separately. Independent checks
recomputed all 16 coverage numerators and denominators from the raw rows and
verified the recorded fingerprints. Base package source was 0.0.7 at commit
`137a9feb594aba648b55169b262e52298d694e25`; OpenMx was 2.22.11.
The corrected runner also completed an isolated eight-fit smoke run through
every summary, without altering the retained 320-fit results.

Use the corrected [runner](run.R) with a new output directory to reproduce the
study. Larger simulations, additional facet structures and multivariate
coverage remain outside this pilot.
