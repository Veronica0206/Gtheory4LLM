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
| `package-planning.R` | Installed planning interface: accepted fit, public extraction, user cost model; equal final candidates keep their flags and cost |
| `package-installed-examples.R` | Every shipped example script still runs against the installed package |
| `package-gaussian-initialization.R` | Square-root recovery through the public interface: an accepted primary attempt is identical under both policies, the control is validated, the record is reported, and a one-iteration budget exercises a real recovery without relaxing acceptance |
| `package-selected-inverse.R` | The compiled selected inverse: every entry, query, trace and local contraction against dense inverses on eight reference matrices under shuffled orders with and without permutation, the engine's own Hessian geometry, thirty refusals, cap boundaries and collector safety |
| `package-sparse-resources.R` | The two-stage sparse memory estimate: complete-fill bound within budget, refusal on the exact structural count without a pattern, structural factorization containing an actual Hessian pattern, and preflight/fit refusals naming the method |
| `package-uncertainty.R` | Standard errors, the covariance Jacobian, coefficient derivatives |
| `package-mixed-model.R` | Brennan fixed facets, `full_cell = FALSE` |
| `package-nested-designs.R` | Nested reliability, mixed fixed/nested weighting, nested D studies |
| `package-retry-behavior.R` | Optimizer retry accounting, acceptance reporting, determinism |
| `package-standard-methods.R` | `logLik`/`nobs`/`coef`/`vcov`, criteria, retention controls, and unavailable sampling uncertainty for the lme4 engine |
| `package-discrete-controls.R` | Discrete control surface and trial budgets |
| `package-discrete-domain.R` | Declared numerical domains, unchanged likelihood outside default bounds, natural-boundary and overflow refusals, actual artificial contact, and serialized diagnostic reconstruction |
| `package-discrete-scaling.R` | Explicit per-attempt coordinate scaling against known curvature and independently accepted estimated dense/sparse fits |
| `package-discrete-safety.R` | Discrete failure handling |
| `package-discrete-backend.R` | Independent dense matrix, curvature and mode contracts |
| `package-development.R` | Development API dispatch, fixed-zero information, categorical targets/planning, fixed call covariance and observed-row Gaussian projection |
| `package-discrete-information.R` | Estimated interior binary/ordinal covariance and full nuisance-parameter information, with latent coefficient SEs checked against `clmm`; uses the shipped fixture in `tests/fixtures/` |
| `package-sparse-estimated.R` | Estimated nominal and call covariance, positive and boundary components, dense likelihood parity and an independent `glmer` call reference |
| `package-categorical-target-numerics.R` | Nonzero analytic binary-probit target and Monte Carlo precision oracles, shared-facet decision variation and nominal relabeling invariance |
| `package-nominal-reliability.R` | Estimated exchangeable nominal coefficients against a utility-scale oracle, singular-universe eigenvalues at large finite allocations, and unavailable projections without losing other rows |
| `package-dense-memory-guard.R` | The dense working-memory guard |
| `package-binary-probabilities.R` | Binary tail probabilities |
| `package-ordinal-tail.R` | Ordinal interval log probabilities, scores and curvature at fixed points against independently rounded 160-digit references: far tails, narrow intervals, crossing intervals, block joins and the joint response kernel |
| `package-response-third.R` | Third derivatives of the response loss and ordinal threshold partials against 160-digit references in every regime, finite differences of the kernel's own score and curvature, the binary one-cut identity with far-tail references, and refusals |
| `package-nominal-tails.R` | Nominal losses, scores and dominant-category complements against high-precision references where one category probability rounds to one |
| `package-categorical-target-moments.R` | Nonnegative category-vector and score variance sums, group alignment of shuffled unequal item groups and invalid-index refusals |
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
| `test_gaussian_observed.R` | Observed-row Gaussian route against an independent dense covariance construction, direct inversion and determinant |
| `test_gaussian_projection.R` | Intended balanced D-study projections from observed-row fits against an independent additive-intercept allocation definition |
| `test_batch_complete_scope.R` | Missing whole conditions cannot be hidden by valid recorded call identifiers in the remaining cells |
| `test_categorical_targets.R` | Analytic observed-scale and decision oracles (uniform-probability special case), relabeling invariance and degenerate targets |
| `test_categorical_planning.R` | Categorical planning on real small fits: declared target semantics, undefined targets kept as explained rows, cost accounting, call membership retained |
| `test_categorical_pilot_targets.R` | Point-estimator pilots: independent reference, all attempts retained, no fabricated interval, fixed-zero refitting constraints |
| `test_categorical_resources.R` | Categorical resource preflights by arithmetic and fault injection, never large matrices; guards fire before simulated panels or refits |
| `test_discrete_simulation.R` | Exact response-probability oracles and bounded simulation contracts from an accepted-fit fixture; category display order never changes a probability |
| `test_discrete_pilot.R` | Bounded latent pilot refits, reproducible errors and all-attempt accounting; a numerical refusal is an outcome, not grounds to change a seed |
| `test_discrete_information.R` | Full nuisance/covariance observed information: cross derivatives, the -2 log likelihood convention, and a wrong native inverse that must not leak uncertainty |
| `test_discrete_information_reference.R` | Observed information against an independently fitted Laplace likelihood on frozen panels; nominal covariance Jacobian from closed expressions |
| `test_information_public.R` | Public information extractor and report contracts on a genuine fitted record |
| `test_discrete_solve_validity.R` | The dense conditional-solve validity invariant |
| `test_discrete_sparse_public.R` | Public backend selection uses the shared numerical acceptance policy and the sparse memory budget |
| `test_discrete_sparse_joint_calls.R` | Small joint and call fixtures: sparse likelihoods against dense, recorded calls invariant to row order, size-one calls refused |
| `test_discrete_equivalence_freeze.R` | The frozen dense/sparse equivalence study: digests of its protocol, cases and calibrated tolerances |
| `test_laplace_check_development.R` | Small public sparse-fit regression: call reconstruction from recorded identifiers and the Laplace check's dense budget refusals |
| `test_preflight_development.R` | Structural and resource preflight checks for the development routes, without any optimization |
| `test_gaussian_initialization.R` | The square-root kernel against the exact and dense deviances with analytic gradients, the recovery controller with the optimizer injected, and the public policies |
| `test_discrete_sparse_resources.R` | Source entrypoint for the installed sparse-resource contract |
| `test_selected_inverse.R` | Source entrypoint for the installed selected-inverse contract; compiles `src/` through the loader |
| `test_gaussian_lme4_restart.R` | The lme4 restart rule: a restart counts only when it completes without a convergence warning and reproduces the solution |
| `test_discrete.R` | Probability and derivative identities, glmer/clmm comparisons |
| `test_discrete_acceptance.R` | Boundary, restart and stationarity acceptance |
| `test_discrete_domain.R` | Source entrypoint for the installed numerical-domain contract |
| `test_discrete_scaling.R` | Source entrypoint for the installed optimizer-scaling contract |
| `test_ordinal_tail.R` | Source entrypoint for the installed ordinal tail contract |
| `test_nominal_tails.R` | Source entrypoint for the installed nominal tail contract |
| `test_response_third.R` | Source entrypoint for the installed third-derivative contract |
| `test_categorical_target_moments.R` | Source entrypoint for the installed categorical-target moment contract |
| `test_interface.R` | Dispatch and reliability against dense aggregation |
| `test_staged_diagnostics.R` | Staged summary reports retained evidence without changing acceptance |
| `package-staged-diagnostics.R` | Staged summary is truthful on installed public fits |
| `test_discrete_reference.R` | Frozen fixed-parameter targets and declared rejections still hold |
| `test_discrete_sparse.R` | Sparse design construction reproduces the dense coordinate system |
| `test_discrete_sparse_hessian.R` | Sparse Hessian assembly reproduces the dense matrix and frozen targets |
| `test_discrete_sparse_factor.R` | Sparse factor solves and log determinants match the frozen targets |
| `test_discrete_sparse_mode.R` | Sparse conditional mode reproduces the dense solve and the frozen targets |
| `test_nominal_planning.R` | `gt_plan()` on nominal and joint nominal-and-binary fits: weights on latent dimensions, nominal plans screened on the coefficient `gt_dstudy()` reports with the scalar decomposition unavailable, and the binary outcome's decomposition reproducing its coefficient |
| `test_nominal_reliability.R` | Nominal latent coefficients: invariance to the reference category, the binary reduction, the exchangeable closed form and delta-method error, refusals of diagonal fits and composites, a D study, and a joint nominal-and-binary fit that factorizes |
| `test_discrete_sparse_warm_start.R` | A failed cold sparse solve is retried once from the fit's last valid mode; valid cold results are unchanged |
| `test_discrete_cholesky.R` | Cholesky coordinates for unstructured covariance: the 'auto' choice and bounds, exact zeros, the observed-information map against differences, and a rank-one rater panel fitted to an exactly singular accepted matrix at an objective no worse than log-Cholesky's |
| `test_discrete_first_step.R` | A collapsed first step of a coarse L-BFGS-B attempt is rerun at the per-row scale: the mechanism on a quadratic summed over rows, fits whose attempts move left untouched (nlminb too), and a 7,200-row drug-review subset whose default ordinal fit stopped at its start before the change |
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
`test_branch_protection.py`, `test_documentation_consistency.py`, `test_style.py`,
`test_compatibility_build_environment.py` (build prerequisites preserve numerical
pins and source bytes), `test_nold_evidence.py` (the no-long-double evidence gates
without a container or a fit) and `test_reference_blas.py` (the reference-backend
evidence gate with controlled runtime records).

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
against the current source archive separately from the unchanged retained
release bundle. A listing in this map is not evidence that a run passed.
