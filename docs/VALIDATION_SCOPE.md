# Validation scope

This document separates implemented checks from the scientific validation still needed. The catalogue of unsupported combinations is [limitations](LIMITATIONS.md). The source targets the 1.0.0 release candidate; its publication status and archive checks are separate. Historical pilot results retain their recorded source versions and do not validate subsequent additions. This is not a test-run report, evidence of publication, or a supported operating envelope. See [validation entrypoints](../scripts/VALIDATION.md) for run evidence and environment requirements.

## Scoped native examples and numerical reproduction

The [28 October 2026 candidate records](DEVELOPMENT_STATUS.md#100-release-gates)
report numerical acceptance on macOS and Linux for two whole-data requests:

| Native request | Retained observations and model | What the reported result establishes |
|---|---|---|
| Drug-review efficacy and safety | All 21,600 rows, the two named ordinal aspects of `drug_review_4aspect`, and ten declared sources | Accepted fits on macOS/Linux; conditional information holds three fitted singular nonzero source matrices fixed |
| Mental-health three groups | All 21,600 rows of `mental_health_3group`, three binary outcomes, and ten declared sources | Accepted fits on macOS/Linux; conditional information holds five fitted singular nonzero source matrices fixed |

The public installed [native workflow](../inst/examples/native_1_0_workflow.R)
and [guide](REAL_DATA_WORKFLOW.md) declare these requests and retain their
diagnostics and comparison policy. The full mode is explicit and separate from
the small synthetic smoke mode. A passing smoke check demonstrates the code
path, not either native fit. New source or archive bytes require their own run
record; the presence of the script does not transfer the project's earlier
numerical results to a new build.

The earlier macOS saved-point calculations supplied conditional intervals at the original accepted
estimates, using 25 of 34 information coordinates for drug review and 33 of 63
for mental health. They changed neither the data nor the fitted point. The
ordinary information refusal remains the historical result; it is not a reason
to suppress the newly implemented conditional route. Conversely, arithmetic
success conditional on fixed matrices does not measure uncertainty in those
matrices or the decision to hold them. The candidate built from `2b31e84`
(archive SHA-256
`8e4854ee1ac0a9d2c3893528cb0c37ad9f5d741811c0fbddcc3ca91cd2fe6a45`)
was subsequently refit on both panels on macOS and Linux on 28 October 2026.
In every platform/model pair, numerical acceptance was retained, unrounded
point estimates met both historical platform references, and conditional
uncertainty met the saved macOS information reference. No interval-coverage
campaign is supplied by these runs.
The subsequent bootstrap data/model-association repairs and nominal analytic
gradient tail-product correction have their own package tests; these historical
native runs are not fresh full-data fits of the replacement submission archive.
The tail correction applies to nominal outcomes, which neither native request
uses. Its tests compare curvature products and both gradient correction paths
with explicit stable-matrix references. They establish arithmetic agreement,
not nominal-model recovery, interval coverage or approximation accuracy.

Neither request supplies a result for all four drug-review aspects or the six
mental-health flags. Neither establishes first-order Laplace adequacy, a global
optimum, repeated-sampling interval coverage, or a general operating range for
other datasets. Unavailable intervals stay unavailable. The statistical campaign
records in [development status](DEVELOPMENT_STATUS.md#statistical-qualification-record-2026-10-23)
also retain failed and poorly calibrated scenarios; successful interior cases
must not be generalized to boundaries, weak signals or other outcome models.

Reproduction has two levels. First, replay the exact data, coding, model,
controls and seeds with the recorded source archive and numerical environment.
Second, compare another platform using tolerances specified before the rerun
on matched unrounded quantities. Preserve numerical-acceptance and
uncertainty-availability decisions as well as estimates. Any changed decision
or failed comparison must be reported, even when rounded values agree. Record
R, package and dependency versions, BLAS/LAPACK, platform and thread settings;
seeds alone do not guarantee identical floating-point optimization. The native
workflow's tolerances apply only to its declared comparison, not every model or
every future package version.

## Development additions and their checks

| Area | Independent or refusal checks | What they do not establish |
|---|---|---|
| Sparse categorical likelihood and calls | [Dense/sparse and independent glmer comparisons](../tests/test_discrete_sparse_joint_calls.R), [public selection and resource guards](../tests/test_discrete_sparse_public.R), [conditional-mode rounding and strict refusal](../tests/test_discrete_sparse_roundoff.R), [warm-start retry of failed cold solves](../tests/test_discrete_sparse_warm_start.R) | Full native-panel qualification, global optimality or approximation accuracy |
| Observed-row Gaussian likelihood | [Direct covariance inverse/determinant and lme4 comparisons](../tests/test_gaussian_observed.R), [balanced projection algebra](../tests/test_gaussian_projection.R) | Joint incomplete fitting, nonignorable missingness correction or reliability of the irregular observed panel |
| Discrete information | [Full nuisance-information and Jacobian checks](../tests/test_discrete_information.R), [independent clmm information and coefficient derivatives](../tests/test_discrete_information_reference.R), [conditional information and held-source checks](../tests/package-discrete-gradient-information.R), [public uncertainty contracts](../tests/test_information_public.R) | Coverage after choosing boundary sources, unconditional inference for held matrices, or correction for Laplace approximation error |
| Categorical targets and cost planning | [Analytic probit moments, whole-panel MC error and nominal relabeling](../tests/test_categorical_targets.R), [cost and candidate accounting](../tests/test_categorical_planning.R) | Predictive accuracy, decision discrimination, parameter confidence intervals or automatic integration precision |
| Categorical simulation and pilots | [Shared effects, labels, RNG and calls](../tests/test_discrete_simulation.R), [latent pilot accounting](../tests/test_discrete_pilot.R), [independent point-target reference and all-attempt ledger](../tests/test_categorical_pilot_targets.R) | Broad recovery/coverage calibration, a guaranteed pilot size or qualification of full-panel refitting |

New source and installed tests must pass on the actual proposed archive. Their
presence here is not a passing-run claim. Scale studies, interval coverage and
platform checks are separate qualification gates; historical successes cannot
be transferred by version number. The catalogue below describes the checks
already present before these additions and retains its original evidence scope.

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
| Discrete acceptance | [Boundary, restart, and stationarity checks](../tests/test_discrete_acceptance.R), [invalid-probe rejection](../tests/package-stationarity-validity.R), [failure handling](../tests/package-discrete-safety.R), [dense conditional-mode rounding](../tests/test_discrete_dense_roundoff.R) | A global optimum, adequate approximation, or structural identification in every design |

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
- Run `gt_preflight()` before fitting. A blocked full-cell discrete term requires an explicit scientific model decision; `full_cell = FALSE` is not an automatic repair. A blocked dense request may use an explicitly selected sparse engine under its declared resource limits and the same model and acceptance checks. Sparse algebra does not qualify a large panel; otherwise use a scientifically defensible smaller design or another implementation.
- Inspect `gt_diagnostics()`. Rejected fits do not support coefficients. Accepted discrete fits with random variation still report unassessed first-order Laplace adequacy. Binary and ordinal G/Phi are latent coefficients; nominal latent coefficients summarize generalized eigenvalues under exchangeable or unstructured source covariance. Binary/ordinal observed-score targets, category-vector targets and decision agreement require an explicit `gt_categorical_target()` request. These separate targets hold fitted parameters fixed and report Monte Carlo error, not parameter confidence intervals.
- For missing whole cells, the available Gaussian route is univariate lme4 with `panel = "observed"`, subject to its documented guards. Use `gt_dstudy(projection = "balanced")` only for a declared complete future allocation; the irregular fitted allocation has no analytic coefficient. Do not fill missing judgments or relabel physical nesting merely to pass a guard. Extrapolated allocations hold source covariances fixed and need exchangeability assumptions.
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
| Discrete recovery | Independently generated data across the approximation matrix; exact-zero and nonzero sources | Bias/RMSE and empirical variability; numerical acceptance and boundary rates; interval availability, coverage conditional on an available interval, and the all-attempt probability of returning a covering interval under the implemented optional-information procedure; assess Laplace approximation error separately |

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
