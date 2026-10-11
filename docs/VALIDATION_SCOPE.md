# Validation scope

This document separates implemented checks from the scientific validation still needed. It is about *evidence*: what has been checked, how, and what that does not establish. The catalogue of what the software does not do is [limitations](LIMITATIONS.md), and is not repeated here. It describes source version 0.5.0, including the study-planning functions. The published 0.4.1 archive is unchanged. Historical pilot results retain their recorded source versions and do not validate every subsequent addition. This is not a new test-run report, evidence of publication, or a supported operating envelope. See [validation entrypoints](../scripts/VALIDATION.md) for run evidence and environment requirements.

## What the existing checks establish

| Area | Implemented checks | What remains unestablished |
|---|---|---|
| Gaussian likelihood | [Full-covariance references](../tests/test_gaussian.R), [lme4 comparisons and transformations](../tests/test_gaussian_review.R), balanced ML/REML, row/outcome invariance, resource guards | Accuracy under an incorrect covariance model; general unbalanced designs |
| Gaussian call effect | [Independent lme4 ML/REML comparisons](../tests/test_gaussian_call_effect.R), including zero call variance, recorded calls and item relabelling; [batch audit, source accounting and coefficient guards](../tests/package-batch.R) | Call-effect recovery and interval coverage across batch designs; effects of regrouping items or choosing a different batch size |
| Fixed-layout batch projections | [Independent observation-covariance contractions](../tests/package-batch-reliability.R) for per-item, contrast and aggregate targets; shared-call cancellation; future counts; multivariate composites; zero-call limit; labels, retention and report privacy | Sampling uncertainty for these projections; fixed facets; generalization to new groupings or batch sizes |
| Cost-aware planning | [Finite-grid reference comparisons](../tests/test_planning.R), retained candidates, cost ties, Pareto dominance, constraints, baseline error contributions and unavailable-bound handling | Accuracy of user-supplied costs; future-panel performance; modelled shared-call cost optimization; simultaneous post-search interval coverage |
| Gaussian pilot simulation | [Independent nested multivariate moments](../tests/test_simulation.R), zero/singular sources, fixed target protocol, seed/replay behavior, all-attempt failure accounting and Monte Carlo denominators; [installed smoke](../tests/package-simulation.R) | Broad precision or coverage calibration; uncertainty in a fitted parameter scenario; a guaranteed pilot size; discrete or batched pilot simulation |
| Gaussian uncertainty | [OpenMx SE comparison, classical mean-square SE formulas, covariance Jacobian, and independent coefficient derivatives](../tests/package-uncertainty.R) | Broad repeated-sampling coverage, especially near boundaries and with few facet levels |
| Fixed facets | [Explicit random/mixed-model formulas and fixed-count guards](../tests/package-mixed-model.R) | Broad inferential coverage for combinations of fixed facets, nesting, multivariate outcomes, or extrapolation |
| Discrete likelihood | [Probability/derivative identities and matched glmer/clmm checks](../tests/test_discrete.R); [one nonzero-variance adaptive-integration reference](../tests/test_discrete_acceptance.R) | General Laplace accuracy or parameter recovery; matching another Laplace fit is not a higher-accuracy reference |
| Discrete acceptance | [Boundary, restart, and stationarity checks](../tests/test_discrete_acceptance.R), [invalid-probe rejection](../tests/package-stationarity-validity.R), [failure handling](../tests/package-discrete-safety.R) | A global optimum, adequate approximation, or structural identification in every design |

The ordinal boundary regression requires accepted fits to reproduce its reference
likelihood and variances. Otherwise it requires an explicit rejection by only
the named stationarity or restart/tolerance-stability safeguards. Its variance
projection checks apply to both outcomes, and constructed records exercise the
assertion contract independently of the host's optimizer behavior. This does
not fix the platform-sensitive optimizer limitation tracked in
[issue #59](https://github.com/Veronica0206/Gtheory4LLM/issues/59), change a
numerical acceptance threshold, or establish that a final archive passed a
particular CRAN platform. Such qualification needs that archive's check evidence.

The minimum-R compatibility job qualifies R 4.5.0 on Ubuntu 22.04 with explicitly
selected reference BLAS and LAPACK runtime and linker libraries. Its preflight requires R's loaded
library paths to match those selections and retains the environment evidence.
A successful run does not establish compatibility with every BLAS implementation.
The captured Ubuntu 22.04/OpenBLAS 0.3.20 native solve failure was reproduced
on Intel Xeon 6973P-C with Cooperlake dispatch. Controlled same-machine
comparisons isolate native backward substitution: both saved systems fail
with the default, pass with reference BLAS/LAPACK or NEHALEM, and fail again
when the default is restored. The package continues to reject the invalid
starting step under the unchanged bound, without rescue or retry. See
[the evidence and remaining limits](DEVELOPMENT_STATUS.md#intelnold-native-backend).

The noLD job now selects reference runtime and linker libraries before
dependency compilation. A standalone probe checks the exact saved systems,
loaded library paths, process mappings and runtime-file identities before
dependency installation, with the installed numerical dependencies, and after
the complete package check and installed-test loop. An unexpected OpenBLAS
mapping, library change, inaccurate solve or incomplete check fails the gate.
This qualifies the explicitly recorded backend when its full run passes; it
does not repair OpenBLAS, establish general Intel/noLD failure, qualify the
unexecuted sparse path, or demonstrate higher-order approximation accuracy.
Current-R full validation on Ubuntu 24.04 retains its separately recorded
backend. Configuration alone is not evidence that any archive has passed.

The discrete acceptance test includes six sparse-group replicates to exercise numerical behavior, not assess recovery or coverage. Separate [versioned pilot studies](../validation-studies/README.md) now retain 320 Gaussian fits, 180 discrete fixed-parameter likelihood comparisons and 40 binary recovery fits. Their protocols and individual records are public. These bounded initial studies do not establish a general operating range; no observed pilot coverage range is adopted as a guarantee.

The additional [0.3.0 development pilot](../validation-studies/discrete-030-usability-pilot/README.md)
retains 40 binary/ordinal probit attempts from the public dense engine. It reports
38 accepted fits, one numerical rejection and one missing-category error;
rare-outcome settings show substantial recovery error. Its ten replicates per
setting give imprecise Monte Carlo estimates. The frozen archive identity,
all failures and accepted-only recovery denominators are recorded separately
from routine tests and dense-sparse qualification.

What the Gaussian intervals are, and what boundary contact does to them, is stated once in [limitations](LIMITATIONS.md). What remains unestablished about them is this document's subject: neither the full-curvature branch nor the interior-block branch has a demonstrated unconditional coverage rate after boundary selection, and no study here has estimated one. Inspect `$uncertainty`, not merely whether interval endpoints are finite.

Likelihood uncertainty reflects estimation under the fitted random-effects sampling model. It is distinct from prediction variation in a fresh evaluator panel and does not quantify an incorrectly specified facet population. The [synthetic vignette](../vignettes/LLM-workflow.Rmd) demonstrates workflow and interpretation, not empirical method validity or labeling accuracy.

## Choose the model before evaluating its output

- Match the response: numeric continuous score to Gaussian; two categories to binary; ordered categories to ordinal; unordered categories to categorical. A deliberate numeric working score changes the estimand and needs justification.
- Declare the object, relevant source interactions, actual replication, and intended score universe. A facet is fixed when inference concerns exactly its observed levels; its name or being researcher-selected does not decide this automatically.
- `fixed` changes coefficient aggregation after fitting. It does not repair an incorrect G-study covariance model, identify aliased components, or allow changing the fixed set in a D study.
- Run `gt_preflight()` before fitting. A blocked full-cell discrete term requires an explicit scientific model decision; `full_cell = FALSE` is not an automatic repair. A blocked dense model calls for a defensible smaller design or another implementation, not simply higher limits.
- Inspect `gt_diagnostics()`. Rejected fits do not support coefficients. Accepted discrete fits with random variation still report unassessed first-order Laplace adequacy. Binary/ordinal coefficients are latent; scalar categorical and observed discrete reliability remain unsupported.
- Gaussian fitting and analytic coefficients require the documented balanced panel. Do not fill missing judgments or relabel physical nesting merely to pass a guard. Extrapolated allocations hold source covariances fixed and need exchangeability assumptions.
- A Gaussian fit with a modelled `Call` source uses `gt_batch_reliability()` or `gt_batch_dstudy()` for explicit fixed-layout item, contrast and aggregate targets. Ordinary `gt_reliability()`, `gt_dstudy()` and `gt_plan()` refuse that model. The new projections do not establish what happens under regrouping or a different batch size. Unmodelled declarations retain their independent-item interpretation and explicit status.

## Interpreting the planning checks

The new source tests verify computation and reporting contracts. Their small
simulation budgets are not recommendations for a real pilot. The Gaussian
simulator is compared with an independently assembled observation covariance;
the pilot planner then holds the eventual target protocol constant while varying
the amount of pilot information. Refusals, fitting errors and unavailable
intervals remain visible, and conditional width summaries state their denominator.
This does not calibrate the inherited asymptotic intervals or integrate uncertainty
in the original fitted components.

The separate [pilot sensitivity illustration](../validation-studies/gaussian-pilot-sensitivity/README.md)
predeclares 400 univariate Gaussian refits: interior versus near-boundary rater
variance crossed with two versus four pilot raters, holding the final four-rater
protocol fixed. It retains every attempt, numerical diagnostics, interval
availability, conditional intervals, widths, all-attempt precision rates and
Monte Carlo uncertainty. All 400 attempts in the recorded local run were accepted
with intervals; 98 intervals were conditional on estimated boundary components.
This is a bounded local scenario illustration, not a coverage or noLD study.

Batch projection tests use an independent dense `A V A'` reference, while the
implementation contracts source kernels without that dense observation matrix.
This checks the declared fixed-layout estimand. It does not validate transfer of
shared-call variance to a newly randomized grouping or another batch size.

Cost-planning tests check the supplied search space and mathematical dominance
rules. A minimum-cost label means minimum among the eligible supplied candidates
under the entered cost model. It does not validate provider prices, a different
set of evaluators, or a future collection outcome. Lower-bound screening retains
pointwise and conditional-boundary qualifications.

A successful focused check is not a completed full source gate, hosted CI run,
release qualification or new statistical campaign. Use source-identified run
reports to make those claims; this catalogue records which checks are implemented.

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

Store further studies separately from routine tests, with a protocol, configuration, independent generator/reference code, all replicate results, summary, source commit, and environment record. Large simulations and performance benchmarks should have explicit execution budgets. The initial pilots are complete; larger campaigns need separately declared configurations and budgets. This matrix does not promise a release date or expanded statistical support.


## Outcome profiles and portable reports

Outcome category frequencies, parent-scoped group coverage and no-variation
counts are descriptive summaries. Tests compare them with independently counted
small panels and preserve refusal of fitting when a declared category is absent.
They do not define a minimum-information threshold or extend supported designs.

Portable reports test association of supplied coefficient projections, separation
of retained fitting and generation provenance, omission of observations and group
identifiers, HTML escaping, embedded figures and protection of existing files.
These checks establish reporting behavior for the tested inputs; they do not
provide statistical operating-range evidence or anonymize aggregate results.
The profile/report additions do not rerun the statistical pilots or complete
sparse qualification.
