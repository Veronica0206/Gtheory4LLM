# Validation summary

What has been checked for each kind of model, and how far each result
reaches. Numerical acceptance, which every fit must pass before coefficients
are computed, establishes that the optimizer reached a stationary and
reproducible solution. It does not by itself establish parameter recovery,
interval coverage or Laplace accuracy; the studies below address those
questions for the designs they cover. The full records, with every attempt,
are in [validation-studies/](../validation-studies/README.md) and the
[development status](DEVELOPMENT_STATUS.md#statistical-qualification-record-2026-10-23);
[limitations](LIMITATIONS.md) lists what the package does not do.

## By model family

| Model | What was checked | Result | Reach |
|---|---|---|---|
| Gaussian, balanced, univariate or joint | Exact likelihood against `lme4` and a dense full-covariance likelihood; standard errors against `OpenMx` and mean-square formulas | Deviances agree to about 1e-5 or better | Any balanced design the engine accepts |
| Gaussian intervals | [Coverage pilot](../validation-studies/gaussian-coverage/README.md), 160 panels; [object-bootstrap pilot](../validation-studies/bootstrap-coverage/README.md), 800 panels | Delta method 96.0–97.0%, percentile 92.0–94.0%, BCa 92.4–93.8% for E rho^2 | One items-by-raters design with 24 items, Gaussian data |
| Binary and ordinal, latent coefficients | 2,000 panels per interior cell, both links | Conditional coverage 0.94–0.99 when an interval exists | One measurement facet, 24 x 4 and 80 x 8 designs |
| Binary and ordinal near a zero variance | 500 panels per cell | Intervals in 43–69% of panels; coverage 0.66–0.88 when available | As above |
| Binary and ordinal at a zero variance | 500 panels per cell | No available interval covers | As above |
| Nominal, exchangeable | 500 panels | Coverage 0.95 | One facet with replicates |
| Nominal, unstructured | 500 panels | Intervals in 211 of 467 accepted fits; coverage 0.99 when available | As above |
| Joint binary and ordinal | 500 panels | Coverage 0.93–0.96 | As above |
| Joint binary and nominal | 500 panels | Intervals in 125 of 470 accepted fits | As above |
| Laplace objective | [Fixed-parameter comparisons](../validation-studies/discrete-laplace/README.md) and the [defensive-mixture study](../validation-studies/laplace-refinement/README.md) | Objective differences reported per panel; references within Monte Carlo intervals | Small designs only; not the full annotation panels |
| Full hate-speech ordinal panel | Native refits on macOS and Linux from a 1.0 candidate archive | Accepted; 19 prespecified comparisons passed | That model only |
| Shared call effects | 300 panels per outcome type | Covariance recovery only | Equal fixed batches |
| Observed-scale Monte Carlo targets | Weak-signal integration study | Did not meet the prespecified availability criteria | Weak object signal |

## How to read these results

- Coverage is reported conditional on an interval being available, beside
  how often one was available. Near a zero variance, many fits have no
  interval; the ones that do cover less than nominally.
- None of these studies crosses several facets with categorical labels at
  the size of the bundled annotation panels. A coefficient from such a fit is
  numerically accepted, not validated in coverage.
- Delta-method intervals assume the homoscedastic model behind the
  likelihood curvature. Labels coded as numbers and analyzed as Gaussian
  scores can violate it, for example when some items receive nearly constant
  labels; the item bootstrap does not rely on it.
- A refused fit is not necessarily a poor one. `gt_diagnostics()` names the
  failed check, and `?gt_control` lists the settings that address each.
