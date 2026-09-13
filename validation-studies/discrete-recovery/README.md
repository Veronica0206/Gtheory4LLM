# Binary-logit recovery pilot results

All 40 planned fits completed and were numerically accepted, in about two
cumulative fit seconds. Each setting has only ten replicates. This is a pilot
of estimation behavior, not evidence of acceptable recovery over an operating
range. See the [predeclared generating model and targets](PROTOCOL.md).

| Repetitions per item | True variance | Mean estimated variance | MCSE of mean | Accepted boundary estimates |
|---|---:|---:|---:|---:|
| 3 | 0.1 | 0.317 | 0.122 | 4 / 10 |
| 12 | 0.1 | 0.160 | 0.079 | 4 / 10 |
| 3 | 2 | 3.865 | 2.352 | 1 / 10 |
| 12 | 2 | 1.592 | 0.201 | 0 / 10 |

Short panels showed large variability, especially at variance 2. The high
MCSE there makes a precise bias claim inappropriate. Mean latent coefficient
estimates were 0.179, 0.244, 0.496 and 0.839 in the same row order, compared with
the generating targets 0.084, 0.267, 0.646 and 0.879. These are coefficients for
the explicitly assumed item-only random-intercept model, not reliability of
the full real annotation panels or majority votes.

Numerical acceptance did not ensure accurate recovery in each replicate.
Finite-sample effects and Laplace error both contribute to these results;
separating them requires higher-accuracy estimation on the same generated
panels and a larger replication budget. There are no discrete SEs or intervals,
so this is not an interval-coverage study.

The [complete records](results/replicates.csv) retain all planned attempts,
estimates, numerical decisions, warnings and boundaries. The
[summary](results/summary.csv) reports accepted-fit bias/RMSE, empirical SD,
MCSE and denominators. [Metadata](results/metadata.txt) and
[source fingerprints](results/source-files.csv) identify the explicit checkout
and environment. Use [run.R](run.R) with an empty output directory to reproduce.
