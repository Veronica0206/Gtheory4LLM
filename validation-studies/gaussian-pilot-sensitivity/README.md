# Gaussian pilot sensitivity illustration

All 400 predeclared study refits completed in 80.978 seconds on local arm64 R
4.5.3 with OpenMx 2.22.11. Every refit was numerically accepted and returned a
finite interval; there were no errors or numerical refusals. The complete
[protocol](PROTOCOL.md), [configuration](config.csv), [replicate ledger](results/replicates.csv),
[summary](results/summary.csv), and [execution record](results/execution.json)
remain available.

Every pilot contained 40 items. The two pilot allocations used two or four
random raters (80 or 160 observations). Every coefficient estimates the same
final four-rater protocol, so the table changes pilot information while holding
the final estimand fixed. The independent generating effects have item variance
1 and residual variance 1; rater variance is 0.25 or 0.0001.

| Generating scenario | Pilot raters | Mean Phi interval width (MCSE) | Width at most 0.20, out of 100 (rate MCSE) | Conditional intervals | Boundary fits |
|---|---:|---:|---:|---:|---:|
| Interior | 2 | 0.4079 (0.0180) | 12 (0.0325) | 12 | 22 |
| Interior | 4 | 0.2620 (0.0070) | 23 (0.0421) | 0 | 2 |
| Near boundary | 2 | 0.3352 (0.0142) | 14 (0.0347) | 55 | 73 |
| Near boundary | 4 | 0.2171 (0.0054) | 44 (0.0496) | 31 | 59 |

Each row includes all 100 attempts, and every row supplied 100 finite intervals.
An observed 100% acceptance/availability rate has plug-in MCSE zero, but its
exact 95% binomial interval is 0.9638 to 1; zero observed refusals has interval
0 to 0.0362. The full summary also supplies exact binomial intervals for the
precision-success rates. Generating Phi is approximately 0.761905 in the
interior scenario and 0.799984 near the boundary, so these are separate
parameter scenarios rather than exchangeable replicates.

With four rather than two pilot raters, mean widths were smaller in both
scenarios. The near-boundary scenario nevertheless used conditional
interior-block inference frequently (55 and 31 of 100 intervals). An interior
generating parameter can also produce a boundary estimate; those estimates
were retained. Boundary classification and conditional interval calculation
are different indicators, which is why their counts differ. The observed
widths describe precision under these settings, not coverage, calibrated
boundary inference, a formal comparison between cells, or a minimum pilot-size
recommendation. This arm64 experiment does not add noLD qualification evidence.

## Provenance and verification

The package was development version 0.4.1.9000 at source commit
`aaf2c672d5121d101b48bdf251203401474cbff9`. The runner and configuration were
prepared before execution but were then uncommitted study additions;
[source status](results/source-status.txt) states this explicitly. Exact
[SHA-256 fingerprints](results/source-files.csv) identify the package R files,
runner, configuration, and protocol. Their
[postrun fingerprints](results/postrun-source-files.csv) are identical.

The [template record](results/template.json) documents the accepted, genuinely
fitted synthetic model used to supply structure. All study means and covariance
components were explicitly overridden by the protocol; no template estimate was
substituted for a declared generating parameter. Seeds were predeclared, and
the detailed ledger retains data and retry seeds, optimizer-attempt identifiers,
failure fields, warnings, and interval conditions. No selective reruns occurred.

The separate eight-fit bookkeeping smoke completed successfully before the
full run, in its own temporary output directory. It is excluded from every
reported count. Independent Python checks recomputed all four-cell counts,
mean widths, and Monte Carlo errors from the 400 retained records and verified
unique data/retry seeds and matching source fingerprints.

Editorial clarification: the frozen protocol's phrase "no parameter reuse
across panels" refers to independent random-effect realizations and sampled
levels. The generating means and variances are deliberately fixed within each
scenario. The protocol bytes and their recorded fingerprints are preserved;
this clarification changes no design setting, execution or result.

## Reproduction

Run from this repository against committed package sources, using a new output
directory:

```sh
Rscript --vanilla validation-studies/gaussian-pilot-sensitivity/run.R /tmp/pilot-sensitivity-new
```

The runner refuses to overwrite nonempty results. To run the same protocol
against an isolated installed package, set `GT_STUDY_LIBRARY` to its library
directory. That mode fingerprints installed package files and reports the
installed-package execution mode; record the originating archive identity
separately. The protocol, configuration, and runner must remain together.
Neither mode is automatically run by ordinary package checks.
