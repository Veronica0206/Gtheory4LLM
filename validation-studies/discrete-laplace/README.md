# Discrete likelihood approximation pilot results

The [protocol](PROTOCOL.md) generated 180 tiny panels across 60 settings.
All 180 higher-accuracy references met the declared refinement criterion.
The package could evaluate 165 panels; 15 retained panels lacked an observed
declared category and were rejected during preparation. These are unavailable
comparisons, not successful agreement checks.

| Family/link | Compared / planned | Largest absolute NLL difference at variance 2 |
|---|---:|---:|
| Binary logit | 35 / 36 | 0.12454 |
| Binary probit | 29 / 36 | 0.22323 |
| Ordinal logit | 36 / 36 | 0.13147 |
| Ordinal probit | 30 / 36 | 0.21222 |
| Nominal softmax | 35 / 36 | 0.22705 |

At zero variance, the largest discrepancy among available comparisons was
below 1.3e-13. Nonzero variance produced approximation error even when conditional
mode checks succeeded. There is no universal acceptable NLL discrepancy;
these differences alone do not quantify parameter bias, interval coverage or
the adequacy of a design for an application.

Eight unavailable panels lacked one binary category; seven lacked an ordinal
or nominal category. Their reference values and generated observations remain
in [results.csv](results.csv) and [generated-data.csv](generated-data.csv).
[summary.csv](summary.csv) retains each scenario's denominators and errors,
including errors per observation. There are only three panels per setting;
maxima are descriptive and do not establish population error bounds.

Binary and ordinal references use independent adaptive integration. Nominal
references use independently constructed two-dimensional Gaussian quadrature
with increasing order. Refinement agreement establishes numerical stability
under this protocol, not a rigorous mathematical error bound. Likelihoods use
the same individual-trial constants and generating covariance/parameters.

The complete 180-panel calculation took about four seconds in the recorded
environment. After adding an overwrite guard to the runner, a fresh replay
reproduced every numerical and status field exactly. The checked-in records
come from that replay; [metadata](metadata.txt) and
[source fingerprints](source-hashes.csv) identify it. All record-level signed
NLL differences and source fingerprints were independently checked. The
package's R implementation was unchanged.

Run [run.R](run.R) from the repository root with a new destination. The default
refuses to overwrite these results. Parameter recovery is examined separately
in the [binary pilot](../discrete-recovery/README.md).
