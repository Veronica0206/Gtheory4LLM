# Statistical validation studies

These studies examine statistical behavior separately from routine implementation
tests. All generating data are synthetic. Protocols, seeds, source fingerprints,
environment records, individual attempts and summaries are retained. They do
not establish a general validated operating range for the package.

## Initial pilots, 2026-09-13

| Study | Executed scope | Main finding |
|---|---|---|
| [Gaussian coverage](gaussian-coverage/README.md) | 320 fits; four univariate settings, ML/REML, 40 replicates per setting/estimator | All accepted with intervals; observed coefficient coverage 90–100%, with wide Monte Carlo intervals. Boundary selection remains consequential. |
| [Discrete likelihood approximation](discrete-laplace/README.md) | 180 fixed-parameter panels; binary and ordinal logit/probit, nominal softmax | All references converged under refinement; 165 package comparisons, 15 unavailable because a declared category was absent. Nonzero variance produced nonzero Laplace error. |
| [Binary parameter recovery](discrete-recovery/README.md) | 40 fits; four settings, 10 replicates each | All accepted; variance estimates were highly variable in short panels, including boundary estimates. Numerical acceptance did not imply accurate recovery. |

The counts above describe different experiments and should not be added as
independent evidence for one validation claim. Gaussian ML and REML results are
paired on the same generated data. Discrete fixed-parameter comparisons do not
estimate parameters. Recovery results include finite-sample effects as well as
approximation effects; this pilot does not separate them.

The [real-data tutorial](../docs/REAL_DATA_WORKFLOW.md) separately audits the
three bundled annotation panels and explains their current fitting limits.

## Development 0.3.0 usability pilot

The [binary/ordinal pilot](discrete-030-usability-pilot/README.md) retained 40
predeclared fits from a separately fingerprinted 0.3.0.9000 development archive.
Thirty-eight were accepted, one was numerically rejected, and one failed because
a declared ordinal category was absent. Rare-outcome recovery was unstable;
acceptance is not evidence of close parameter or reliability recovery. All
attempts, Monte Carlo uncertainty, source identities and figures are retained.
This small public-dense-engine study does not qualify the private sparse backend.

## Defensive-mixture refinement, 2026-10-18

The [Laplace-refinement study](laplace-refinement/README.md) retains 80
fixed-parameter importance comparisons: 40 seeds at each of two draw budgets
on one three-item binary-logit fixture, against independent one-dimensional
integration references. The defensive mixture has finite weight moments;
all 80 comparisons were available and passed the empirical ESS screen in the
retained initial run. The reference lay in 40/40 and 39/40 nominal Monte Carlo
intervals, with wide uncertainty about those proportions. These results do not
establish general finite-sample calibration, performance for other outcome
families or designs, or coverage of fitted model-parameter intervals. The
protocol, all attempts, source identity and environment accompany the results.

## Object-bootstrap coverage, 2026-10-25

The [object-bootstrap coverage pilot](bootstrap-coverage/PROTOCOL.md) was
frozen before execution: 200 REML replicates in each of the Gaussian coverage
pilot's four item-by-rater settings, with percentile, BCa and delta-method
intervals on the same panels. All 800 fits and bootstraps completed. Percentile
intervals covered the population coefficients in 92.0–94.0% of panels for Erho2
and 89.5–92.5% for Phi, BCa intervals in 92.4–93.8% and 89.1–92.6% of the
panels where they were available (85–99%), and delta-method intervals in
96.0–97.0% and 95.0–96.5%; the [results](bootstrap-coverage/README.md) give each
setting with its Monte Carlo uncertainty. The pilot covers one Gaussian design
with 24 items; it does not establish coverage for discrete or multivariate fits.

## Reproduce without overwriting evidence

The [Gaussian pilot sensitivity illustration](gaussian-pilot-sensitivity/README.md)
retains 400 development-source refits over two variance scenarios and two pilot
rater counts. All attempts estimated a fixed four-rater protocol; all were
accepted with intervals, 98 of them conditional on estimated boundary components.
Its scenario-dependent precision summaries and Monte Carlo uncertainty do not
establish interval coverage or a generally sufficient pilot size.

From the repository root, use new output directories:

```sh
Rscript validation-studies/gaussian-coverage/run.R /tmp/gaussian-pilot-new
Rscript validation-studies/discrete-laplace/run.R /tmp/laplace-pilot-new
Rscript validation-studies/discrete-recovery/run.R /tmp/recovery-pilot-new
Rscript validation-studies/gaussian-pilot-sensitivity/run.R /tmp/planning-pilot-new
Rscript validation-studies/laplace-refinement/run.R /tmp/refinement-pilot-new /path/to/R/library
```

The refinement runner can also use `GT_STUDY_LIBRARY`; with an installed
library it runs without a repository checkout and retains its executed runner,
protocol, completion status and before/after fingerprints.

The individual protocols declare runtime budgets and incomplete-run behavior.
Results are outside the installable R package and are not automatically rerun
by ordinary tests. They remain available in the public source repository.
Files identify the base source commit and exact working code used; a commit ID
alone does not identify a newly added, then-uncommitted study runner.

## Dense/sparse equivalence qualification, 2026-10-26

The [frozen study](discrete-sparse-equivalence/PROTOCOL.md) was executed from
its reviewed judging implementation on macOS and Linux. The
[record](discrete-sparse-equivalence/results/README.md) is not passed under the
frozen rules: five fixed-parameter quantity checks exceed their tolerances, in
three case/platform outcomes. The record gives each difference.
- On macOS, the dense mode search at one C13 point stopped inside the inner
  tolerance but short of the mode that sparse reached.
- On Linux, the C08 and C13 mode scores at the common latent point differ in
  summation order by about 1e-14 relative, against an absolute rule.

Of the scored cases, 12 pass on macOS and 11 on Linux; C14 and C15 are
unsupported. No tolerance was changed.
[Amendment 1](discrete-sparse-equivalence/AMENDMENT-1.md) specifies stage 3
rules derived from numerical analysis: a floating-point summation bound for the
mode score, and a strong-convexity bound for the modes, with the solved
quantities compared at common modes, and each backend's returned objectives
checked against its own algebra, under the frozen tolerances. Its launcher
verifies reviewed runtime pins before anything runs. Its
[record](discrete-sparse-equivalence/results-amendment-1/README.md), executed on
2026-10-27, is not passed: every compared case passes stage 3, and C13 fails
stage 4 on both platforms because neither backend accepts its fit. The original
record stands unchanged.

## Work still needed

Larger predeclared campaigns must cover additional facets, fixed universes,
nesting, multivariate covariance, item-variance boundaries, rare outcomes and
realistic incomplete designs. Sparse discrete fitting, unbalanced Gaussian
reliability, and new D-study APIs are separate implementation work. No support
limits were relaxed in response to these pilots. See the
[validation matrix](../docs/VALIDATION_SCOPE.md) and
[remaining development work](../docs/DEVELOPMENT_STATUS.md).
