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

## Reproduce without overwriting evidence

From the repository root, use new output directories:

```sh
Rscript validation-studies/gaussian-coverage/run.R /tmp/gaussian-pilot-new
Rscript validation-studies/discrete-laplace/run.R /tmp/laplace-pilot-new
Rscript validation-studies/discrete-recovery/run.R /tmp/recovery-pilot-new
```

The individual protocols declare runtime budgets and incomplete-run behavior.
Results are outside the installable R package and are not automatically rerun
by ordinary tests. They remain available in the public source repository.
Files identify the base source commit and exact working code used; a commit ID
alone does not identify a newly added, then-uncommitted study runner.

## Work still needed

Larger predeclared campaigns must cover additional facets, fixed universes,
nesting, multivariate covariance, item-variance boundaries, rare outcomes and
realistic incomplete designs. Sparse discrete fitting, unbalanced Gaussian
reliability, and new D-study APIs are separate implementation work. No support
limits were relaxed in response to these pilots. See the
[validation matrix](../docs/VALIDATION_SCOPE.md) and
[remaining development work](../docs/DEVELOPMENT_STATUS.md).
