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
| `package-standard-methods.R` | `logLik`/`nobs`/`coef`/`vcov`, criteria, retention controls, and unavailable sampling uncertainty for the lme4 engine |
| `package-discrete-controls.R` | Discrete control surface and trial budgets |
| `package-discrete-safety.R` | Discrete failure handling |
| `package-discrete-backend.R` | Independent dense matrix, curvature and mode contracts |
| `package-development.R` | Development API dispatch, fixed-zero information, categorical targets/planning, fixed call covariance and observed-row Gaussian projection |
| `package-discrete-information.R` | Estimated interior binary/ordinal covariance and full nuisance-parameter information, with latent coefficient SEs checked against `clmm`; uses the shipped fixture in `tests/fixtures/` |
| `package-sparse-estimated.R` | Estimated nominal and call covariance, positive and boundary components, dense likelihood parity and an independent `glmer` call reference |
| `package-categorical-target-numerics.R` | Nonzero analytic binary-probit target and Monte Carlo precision oracles, shared-facet decision variation and nominal relabeling invariance |
| `package-dense-memory-guard.R` | The dense working-memory guard |
| `package-binary-probabilities.R` | Binary tail probabilities |
| `package-stationarity-validity.R` | Rejection of invalid stationarity probes |
| `package-preflight.R` | Preflight reporting, including the installed tutorial |
| `package-outcome-profile.R` | Outcome category counts, group coverage and descriptive profile plots |
| `package-batch.R` | Batch declarations, inferred and recorded calls, their audit against the data, the shared call effect a Gaussian fit of equal fixed batches estimates, checked against a dense restricted likelihood, and the status carried by every output |
| `package-batch-reliability.R` | Dense observation-covariance contractions for fixed-layout item, contrast and aggregate targets; future counts, zero-call limit, retention and report privacy |
| `package-simulation.R` | Installed Gaussian generation and pilot-refitting smoke with a fixed target protocol and restored caller RNG |
| `package-analysis-report.R` | Portable reports, provenance, privacy and HTML export |
| `package-reporting.R` | Flat coefficient tables, allocation joins, target screening and D-study plots |
| `package-visualizations.R` | Reliability forest plots, unavailable uncertainty and graphical state preservation |
| `package-argument-parity.R` | Shared fitting/preflight argument validation; absent categories are additionally reported as blocked preflight objects |
| `package-tuple-keys.R` | Interaction keys that user labels must not collide with |
| `package-user-interface.R` | Printing, summaries, and what they must never leak |
| `package-engines.R` | The lme4 Gaussian engine against the exact engine and against lme4 itself: estimates, criteria, call effect, preflight, retention, and the acceptance logic on constructed inputs, including the scaled-gradient counterexample, unusable curvature, inward boundary derivatives and lme4 warnings; source-order boundary mapping and a public parameter map retained without the engine model |
| `package-laplace-check.R` | The Laplace comparison against an independent one-dimensional integration, defensive-mixture importance sampling against quadrature, full-mixture weights and their bound, correlated proposals, multiple seeds and budgets, the zero-variance identity, limits applied before computation, unavailable rather than zero contributions, and its refusals |
| `package-formula-interface.R` | The model-formula route of fitting and preflight: equivalence with `gt_design()`, both argument orders, the named `formula` and `measured` arguments, a family after the formula, class vectors, `formula()` and `update()`, and the refusals |

## Source-level tests

| File | Area |
|---|---|
| `test_design.R` | Design construction and the formula grammar |
| `test_gaussian.R` | Independent dense Gaussian likelihood references |
| `test_gaussian_review.R` | lme4 comparisons and transformations |
| `test_gaussian_call_effect.R` | Call-effect fits against lme4 under REML and ML, with recorded calls, shuffled rows and relabelled slots |
| `test_batch_reliability.R` | Source entrypoint for the installed independent batch-projection suite |
| `test_planning.R` | Bounded cost search, Pareto and minimum-cost ties, constraints, source error changes, fixed-universe and unavailable-bound guards |
| `test_simulation.R` | Independent nested multivariate generation moments, scenario guards, fixed-protocol refit precision, deterministic replay, failure ledgers and Monte Carlo denominators |
| `test_gaussian_retry.R` | The retry controller, with the optimizer injected |
| `test_gaussian_lme4_restart.R` | The lme4 restart rule: a restart counts only when it completes without a convergence warning and reproduces the solution |
| `test_discrete.R` | Probability and derivative identities, glmer/clmm comparisons |
| `test_discrete_acceptance.R` | Boundary, restart and stationarity acceptance |
| `test_interface.R` | Dispatch and reliability against dense aggregation |
| `test_staged_diagnostics.R` | Staged summary reports retained evidence without changing acceptance |
| `package-staged-diagnostics.R` | Staged summary is truthful on installed public fits |
| `test_discrete_reference.R` | Frozen fixed-parameter targets and declared rejections still hold |
| `test_discrete_sparse.R` | Sparse design construction reproduces the dense coordinate system |
| `test_discrete_sparse_hessian.R` | Sparse Hessian assembly reproduces the dense matrix and frozen targets |
| `test_discrete_sparse_factor.R` | Sparse factor solves and log determinants match the frozen targets |
| `test_discrete_sparse_mode.R` | Sparse conditional mode reproduces the dense solve and the frozen targets |
| `test_nominal_reliability.R` | Nominal latent coefficients: invariance to the reference category, the binary reduction, the exchangeable closed form and delta-method error, refusals of diagonal fits and composites, a D study, and a joint nominal-and-binary fit that factorizes |
| `test_discrete_sparse_warm_start.R` | A failed cold sparse solve is retried once from the fit's last valid mode; valid cold results are unchanged |
| `test_discrete_sparse_warm_policy.R` | Within an optimizer attempt, sparse solves start from the attempt's centre mode: cold first solve, finite-difference probes share the centre, reset per attempt, short warm solves fall back to cold, and the fit's final evaluation is cold |
| `test_laplace_check_retained_data.R` | `gt_laplace_check()` reads a fit's retained encoded responses as the encoding they are; new data still passes the strict resolver |
| `test_discrete_attempt_names.R` | Every discrete attempt, including alternative starts and the selected solution, keeps its parameter names; a warm-start refit from them is accepted |
| `test_laplace_check_resources.R` | `gt_laplace_check()` refuses, before allocation, a comparison whose workspace estimate exceeds the dense budget |
| `test_discrete_sparse_roundoff.R` | Narrow/wider function-window conditions, independent quadratic derivatives, score-bound refusals and dense mode agreement |
| `test_discrete_full_panel_roundoff.R` | Five fixed-parameter conditional solves from refused synthetic full-panel fits, checked with independent ordinal-probit arithmetic; no full-fit or scale qualification claim |
| `test_discrete_sparse_validity.R` | Sparse solve-validity invariants: the dense rule on sparse storage, both refusal reasons, end-to-end containment, backend identity |
| `test_specimen_replay.R` | `scripts/replay_specimen.R` reads specimens back and judges the stored factor and a fresh one separately, on both storage forms |
| `test_discrete_fitted_smoke.R` | Frozen fitted smoke cases reproduce their dense class contract |
| `test_discrete_fitted_sparse.R` | Frozen fitted matrix reproduces through the sparse marginal evaluator |
| `test_examples.R` | Bundled example loading |

## Tooling tests

`test_committed_artifact.py`, `test_release_identity.py`, `test_prepare_release.py`,
`test_public_contents.py`, `test_cran_readiness.py`, `test_package_validation.py`,
`test_validation_runner.py`, `test_validation_bundle.py`, `test_workflow_contract.py`,
`test_documentation_lock.py`, `test_dependency_bootstrap.py`,
`test_branch_protection.py`, `test_documentation_consistency.py`, `test_style.py`.

## Conventions

- An expected value is derived independently of the code that produces it.
  A test that re-runs the implementation's own formula shares its mistakes.
- Numerical comparisons state a tolerance and a reason for it. Decisions on
  controlled inputs — accepted, rejected, which check failed — are compared
  exactly. Platform-sensitive optimizer outcomes are checked against the same
  documented numerical gates; a saved acceptance flag from another platform
  is not a universal expected result.
- A test that cannot run says so rather than passing quietly.

Run one file directly while developing:

```sh
Rscript --vanilla tests/test_design.R
```

Installed-package tests need the package installed; do not mistake a globally
installed older version for the source under review. The full source gate is
`python3 scripts/run_validation.py --scope source`.

The current planning suites describe computation under development version 1.0.0.9000.
Their small simulation runs exercise software contracts; they do not recommend
a pilot size or establish confidence-interval coverage. Run the full source gate
against the current source archive separately from the unchanged published
0.5.0 release artifact. A listing in this map is not evidence that a run passed.
