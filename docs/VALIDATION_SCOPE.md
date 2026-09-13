# Validation scope

This document separates implemented checks from the scientific validation still needed. It describes the v0.0.7 implementation; it is not a new test-run report or a supported operating envelope. See [validation entrypoints](../scripts/VALIDATION.md) for run evidence and environment requirements.

## What the existing checks establish

| Area | Implemented checks | What remains unestablished |
|---|---|---|
| Gaussian likelihood | [Full-covariance references](../tests/test_gaussian.R), [lme4 comparisons and transformations](../tests/test_gaussian_review.R), balanced ML/REML, row/outcome invariance, resource guards | Accuracy under an incorrect covariance model; general unbalanced designs |
| Gaussian uncertainty | [OpenMx SE comparison, classical mean-square SE formulas, covariance Jacobian, and independent coefficient derivatives](../tests/package-uncertainty.R) | Broad repeated-sampling coverage, especially near boundaries and with few facet levels |
| Fixed facets | [Explicit random/mixed-model formulas and fixed-count guards](../tests/package-mixed-model.R) | Broad inferential coverage for combinations of fixed facets, nesting, multivariate outcomes, or extrapolation |
| Discrete likelihood | [Probability/derivative identities and matched glmer/clmm checks](../tests/test_discrete.R); [one nonzero-variance adaptive-integration reference](../tests/test_discrete_acceptance.R) | General Laplace accuracy or parameter recovery; matching another Laplace fit is not a higher-accuracy reference |
| Discrete acceptance | [Boundary, restart, and stationarity checks](../tests/test_discrete_acceptance.R), [invalid-probe rejection](../tests/package-stationarity-validity.R), [failure handling](../tests/package-discrete-safety.R) | A global optimum, adequate approximation, or structural identification in every design |

The discrete acceptance test includes six sparse-group replicates to exercise numerical behavior. It explicitly makes no recovery or coverage claim. The Gaussian uncertainty tests use reproducible reference fixtures, not a repeated-sampling coverage study. The public test sources do not include a versioned Gaussian coverage campaign with replicate-level results; no numerical coverage range is adopted here.

Gaussian intervals use a Wald/delta approximation. Boundary variance rows have unavailable SEs. If the joint curvature cannot support inference and the implementation uses an interior block, the remaining intervals are conditional on listed boundary components being held at zero. If full curvature remains usable, boundary caveats still apply. Neither branch establishes unconditional coverage after boundary selection. Inspect `$uncertainty`, not merely whether interval endpoints are finite.

Likelihood uncertainty reflects estimation under the fitted random-effects sampling model. It is distinct from prediction variation in a fresh evaluator panel and does not quantify an incorrectly specified facet population. The [synthetic vignette](../vignettes/LLM-workflow.Rmd) demonstrates workflow and interpretation, not empirical method validity or labeling accuracy.

## Choose the model before evaluating its output

- Match the response: numeric continuous score to Gaussian; two categories to binary; ordered categories to ordinal; unordered categories to categorical. A deliberate numeric working score changes the estimand and needs justification.
- Declare the object, relevant source interactions, actual replication, and intended score universe. A facet is fixed when inference concerns exactly its observed levels; its name or being researcher-selected does not decide this automatically.
- `fixed` changes coefficient aggregation after fitting. It does not repair an incorrect G-study covariance model, identify aliased components, or allow changing the fixed set in a D study.
- Run `gt_preflight()` before fitting. A blocked full-cell discrete term requires an explicit scientific model decision; `full_cell = FALSE` is not an automatic repair. A blocked dense model calls for a defensible smaller design or another implementation, not simply higher limits.
- Inspect `gt_diagnostics()`. Rejected fits do not support coefficients. Accepted discrete fits with random variation still report unassessed first-order Laplace adequacy. Binary/ordinal coefficients are latent; scalar categorical and observed discrete reliability remain unsupported.
- Gaussian fitting and analytic coefficients require the documented balanced panel. Do not fill missing judgments or relabel physical nesting merely to pass a guard. Extrapolated allocations hold source covariances fixed and need exchangeability assumptions.

## Planned scientific validation matrix — not results

| Campaign | Factors to vary | Primary comparisons and outcomes |
|---|---|---|
| Gaussian coverage | ML/REML; object and facet counts; higher-order sources; low/high reliability; extreme variance ratios | Source and coefficient bias/RMSE; SE versus empirical SD; interval width/coverage; Hessian and acceptance failures |
| Gaussian boundaries | Exactly zero, near-zero, and interior components; few facet levels | Boundary selection, interval availability, conditional interior-block versus full-curvature behavior; unconditional procedure performance reported separately |
| Fixed universe | None, one, and supported combinations of fixed facets; crossed/nested source structures; fixed observed set | Independently derived target coefficients and source roles; unchanged fixed levels/weights; uncertainty for the stated target |
| Multivariate Gaussian | Diagonal/unstructured sources; weak/strong outcome correlation; near-singular matrices; composite weights | Covariance and composite recovery; joint parameter mapping; per-outcome/composite interval coverage |
| Discrete approximation | Binary logit/probit, ordinal, nominal; rare/sparse categories; group sizes; large variances; multiple outcomes and covariance boundaries | Tiny-model marginal likelihoods against converged higher-accuracy integration; matched thresholds, contrasts, covariance matrices, and latent coefficients where defined |
| Discrete recovery | Independently generated data across the approximation matrix; exact-zero and nonzero sources | Bias/RMSE and empirical variability; numerical acceptance and boundary rates; no interval-coverage claim until an interval procedure exists |

For each campaign, predeclare the generating model, estimand, design grid, seeds, replicate budget, reference method/tolerance, and numerical-versus-scientific acceptance criteria. Check that the reference has the same link, covariance structure, likelihood constants, and categorical reference convention. Refine integration until the reference error is smaller than the comparison of interest.

Retain every attempted replicate and distinguish optimizer failure, numerical rejection, unavailable interval, and usable result. Report totals and acceptance/availability rates before bias or coverage among usable fits. Accepted-fit summaries alone can conceal selection. Report Monte Carlo SEs: for a mean, replicate SD divided by the square root of its replicate count; for a coverage proportion p, sqrt(p(1-p)/B), using the stated denominator and a binomial interval when appropriate. Report how interval availability affects overall procedure performance.

Choose replicate counts for predeclared Monte Carlo precision. Assess coverage against nominal coverage with that uncertainty; avoid an arbitrary universal cutoff. Preserve poor-performing regions instead of broadening a claim from successful cells.

Store future studies separately from routine tests, with a protocol, configuration, independent generator/reference code, all replicate results, summary, source commit, and environment record. Large simulations and performance benchmarks should have explicit execution budgets. This matrix authorizes no new study runs and makes no promise of a release date or expanded statistical support.
