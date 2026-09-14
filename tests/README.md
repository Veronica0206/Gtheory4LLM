# Test map

Three kinds of test live here, distinguished by filename rather than by
directory. The naming is load-bearing: `R CMD check` runs **only** the top-level
`.R` files of a built package's `tests/`, so the installed tests cannot be moved
into subdirectories without silently removing them from the release gate.

| Pattern | What it is | Where it runs |
|---|---|---|
| `package-*.R` | Installed-package tests, shipped in the archive | `R CMD check`, and the source gate |
| `test_*.R` | Source-level tests that `source()` files from `R/` | The source gate only; `.Rbuildignore`d |
| `test_*.py` | Tooling, release, and documentation checks | The source gate only; `.Rbuildignore`d |

## Installed-package tests

| File | Area |
|---|---|
| `package-smoke.R` | Exports, S3 registration, bundled resources |
| `package-characterization.R` | Frozen numerical baseline for ten canonical cases |
| `package-properties.R` | Invariance, equivariance and monotonicity properties |
| `package-fuzz-inputs.R` | Parsers, validators and resource guards under hostile input |
| `package-gaussian-starts.R` | Gaussian starting values and their matching rules |
| `package-uncertainty.R` | Standard errors, the covariance Jacobian, coefficient derivatives |
| `package-mixed-model.R` | Brennan fixed facets, `full_cell = FALSE` |
| `package-nested-designs.R` | Nested reliability, mixed fixed/nested weighting, nested D studies |
| `package-retry-behavior.R` | Optimizer retry accounting, acceptance reporting, determinism |
| `package-standard-methods.R` | `logLik`/`nobs`/`coef`/`vcov`, criteria, retention controls |
| `package-discrete-controls.R` | Discrete control surface and trial budgets |
| `package-discrete-safety.R` | Discrete failure handling |
| `package-discrete-backend.R` | Independent dense matrix, curvature and mode contracts |
| `package-dense-memory-guard.R` | The dense working-memory guard |
| `package-binary-probabilities.R` | Binary tail probabilities |
| `package-stationarity-validity.R` | Rejection of invalid stationarity probes |
| `package-preflight.R` | Preflight reporting, including the installed tutorial |
| `package-argument-parity.R` | Preflight and fitting accept and reject the same requests |
| `package-tuple-keys.R` | Interaction keys that user labels must not collide with |
| `package-user-interface.R` | Printing, summaries, and what they must never leak |

## Source-level tests

| File | Area |
|---|---|
| `test_design.R` | Design construction and the formula grammar |
| `test_gaussian.R` | Independent dense Gaussian likelihood references |
| `test_gaussian_review.R` | lme4 comparisons and transformations |
| `test_gaussian_retry.R` | The retry controller, with the optimizer injected |
| `test_discrete.R` | Probability and derivative identities, glmer/clmm comparisons |
| `test_discrete_acceptance.R` | Boundary, restart and stationarity acceptance |
| `test_interface.R` | Dispatch and reliability against dense aggregation |
| `test_staged_diagnostics.R` | Staged summary reports retained evidence without changing acceptance |
| `package-staged-diagnostics.R` | Staged summary is truthful on installed public fits |
| `test_discrete_reference.R` | Frozen fixed-parameter targets and declared rejections still hold |
| `test_discrete_sparse.R` | Sparse design construction reproduces the dense coordinate system |
| `test_discrete_sparse_hessian.R` | Sparse Hessian assembly reproduces the dense matrix and frozen targets |
| `test_examples.R` | Bundled example loading |

## Tooling tests

`test_committed_artifact.py`, `test_release_identity.py`, `test_prepare_release.py`,
`test_public_contents.py`, `test_cran_readiness.py`, `test_package_validation.py`,
`test_validation_runner.py`, `test_workflow_contract.py`,
`test_documentation_lock.py`, `test_dependency_bootstrap.py`,
`test_branch_protection.py`, `test_documentation_consistency.py`, `test_style.py`.

## Conventions

- An expected value is derived independently of the code that produces it.
  A test that re-runs the implementation's own formula shares its mistakes.
- Numerical comparisons state a tolerance and a reason for it. Decisions —
  accepted, rejected, which check failed — are compared exactly.
- A test that cannot run says so rather than passing quietly.

Run one file directly while developing:

```sh
Rscript --vanilla tests/test_design.R
```

Installed-package tests need the package installed; do not mistake a globally
installed older version for the source under review. The full source gate is
`python3 scripts/run_validation.py --scope source`.
