# Native LLM annotations and reproducible scoped fits

The three bundled datasets support design audits and explicitly scoped native
response models. The installed workflow below defines the two joint models
reported to reach numerical acceptance with sparse fitting. The historical
full-hierarchy audit later on this page remains a separate demonstration of
unsupported requests; it does not fit those models.

## Run the scoped v1.0 workflow

Install the exact package archive into a dedicated library first. The workflow
uses only the installed package and its bundled public annotation tables:

For a full run, set `OMP_NUM_THREADS`, `OPENBLAS_NUM_THREADS`,
`MKL_NUM_THREADS` and `VECLIB_MAXIMUM_THREADS` to `1` in the environment that
launches R, before R starts. On macOS or Linux, for example:

```sh
env OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  VECLIB_MAXIMUM_THREADS=1 R --vanilla
```

On Windows, set the same four variables in the session that launches R. Full
mode refuses missing or different values. Setting them after R starts cannot
reliably change an already initialized numerical library. The synthetic smoke
mode does not require these full-replay prerequisites.

```r
library(Gtheory4LLM)
source(system.file("examples", "native_1_0_workflow.R", package = "Gtheory4LLM"))

# Small independently generated joint binary/ordinal example. This checks the
# reporting contract, not the native-data estimates or their computational cost.
gt_native_workflow(mode = "smoke", output_dir = "native-smoke-new")

# Explicit long run. Supply the same archive that was installed. The directory
# must be new so failures and previous results cannot be silently replaced.
gt_native_workflow(mode = "full", output_dir = "native-full-new",
  archive_path = "Gtheory4LLM_1.0.0.tar.gz")
```

Sourcing the script defines the workflow and does not launch a fit. The repository
wrapper is equivalent: `Rscript examples/native_1_0_workflow.R smoke NEW_DIR`;
for a full run append the archive path and, optionally, a single model ID.
Run full models sequentially with one numerical thread. Recorded development
runs required about 41 minutes and 131 minutes on the original Mac, and about
100 minutes and 426 minutes on the Linux environment, respectively. These are
historical measurements, not promised runtimes; the declared 8 GiB sparse
working-memory budget is a planning guard, not an operating-system memory cap.

| Model ID | Public input and modeled outcomes | Model |
|---|---|---|
| `drug_review_efficacy_safety` | `drug_review_4aspect`, efficacy and safety only, 21,600 rows | Two probit-ordinal outcomes with unstructured source covariance |
| `mental_health_3group` | `mental_health_3group`, all three binary groups, 21,600 rows | Three probit-binary outcomes with unstructured source covariance |

Both use the ten predeclared sources in this formula; for mental health the
left-hand side is replaced by its three group outcomes:

```r
cbind(efficacy, safety) ~ item * evaluator * prompt +
  evaluator:prompt:temp + evaluator:prompt:temp:seed +
  item:evaluator:prompt:temp
```

The measured object is explicitly `item`. The workflow uses native category
order, automatic starts and one alternative start, sparse L-BFGS-B, natural
Cholesky coordinates, analytic gradient, `optimizer_scaling = "start"`,
`boundary_escape = "projected"`, observed-information checking and a 2,000
iteration limit per attempt. It records the complete resolved controls instead
of relying on these prose summaries. Its row, dimension and parameter guards
permit these declared requests; acceptance tolerances are unchanged.

The two outcome choices are the scoped examples, not evidence that all four
drug aspects or six mental-health flags have been fitted. The original macOS
and Linux point fits lacked ordinary information at singular covariance
sources. The current implementation can instead form information on the
remaining coordinates while holding each affected source at its fitted matrix.
It names that conditioning explicitly and withholds standard errors for the
held matrices. A separate, later macOS computation applied this rule at the
saved estimates without refitting. Its three held drug-review sources and
five held mental-health sources were all singular and nonzero.

The helper uses public extractors to write preflight and acceptance decisions,
component and reliability tables, a balanced D study, a fitted object and an
HTML report. Warnings, refusals, missing information and conditional inference
remain visible. Supplying `archive_path` checks its package/version and records
its digest; the installation log and isolated-library record are still needed
to prove that this archive produced the loaded namespace.

The two numerical comparisons deliberately have different evidence scopes:

- Point estimates must pass **both** historical platform references, matching
  source/outcome keys and numerical acceptance. Absolute deviance error must be
  at most `0.01`; each component error is divided by `max(1, abs(reference))`
  and must be at most `0.02`. G and Phi at both observed and single-measurement
  allocations use an absolute tolerance of `1e-4`.
- Conditional uncertainty is checked separately against the saved **macOS
  information-only** reference. Availability, conditional status, held-source
  membership and finite interval metadata must agree; SEs and interval endpoints
  at both allocations use an absolute tolerance of `0.001`. The criterion was
  declared before the replay; it is not a coverage result.

The coefficient and interval limits were declared for this public replay; only
the deviance/component limits belonged to the original Q5 comparison. The
script never widens any limit after a failure. A new optimizer run can match
the point references while missing the conditional-information reference, and
that difference is reported as `uncertainty_mismatch` rather than success.

The included references document calculations on earlier source revisions.
The 1.0.0 candidate built from `2b31e84` was replayed in full mode on
2026-10-28 on macOS and Linux and met both comparisons
([release gates](DEVELOPMENT_STATUS.md#100-release-gates)); smoke mode and
saved-point arithmetic do not replace such a replay. That evidence belongs to
the recorded candidate bytes, before the subsequent bootstrap association
repairs; it is not a full-data replay of a later replacement archive. Neither comparison
demonstrates a global optimum, integration accuracy or calibrated confidence
intervals after boundary selection.

## Historical full-hierarchy audit and failure examples

From the repository root:

```sh
Rscript examples/real_data_workflow.R
```

Or use `source("examples/real_data_workflow.R")` in R. The returned `gt_real_data_workflow` object retains every preflight, category count, fit or error, warning, and diagnostic. The script reads only the bundled modeling tables; it writes no files, downloads nothing, and needs no package installation. The small binary demonstrations use base R; OpenMx is not needed for this script.

```r
source("examples/real_data_workflow.R")
result <- gt_real_data_workflow
result$audit$mental_health_nominal$types
result$audit$drug_review_4aspect$frequency
result$audit$hate_speech$preflight$sources
result$audit$hate_speech$preflight$checks
```

The development workflow also retains bounded cell-audit examples and
plot-ready preflight objects for every native panel:

```r
result$audit$hate_speech$preflight$panel_audit$summary
plot(result$audit$hate_speech$preflight, type = "cells")
plot(result$audit$hate_speech$preflight, type = "sources")
```

For the separately labelled synthetic binary example, an accepted fit now
also supplies `coefficient_table`, `decision_study` and `target_screen`.
These remain `NULL` if that fit is rejected. They demonstrate table exports,
latent-reliability figures and candidate screening without presenting a
synthetic estimate as a result from the bundled annotation datasets.

```r
if (!is.null(result$decision_study)) {
  result$coefficient_table
  result$target_screen
  plot(result$latent_coefficient, target = .8)
  plot(result$decision_study, coefficient = "Phi", outcome = "y", target = .8)
}
```

The installed scoped workflow above is the native fit-and-report entry point.
The following historical example deliberately retains its different 31-source
dense request and size guards; its blocked requests do not contradict the
reported sparse ten-source fits.

Category proportions describe recorded annotation rows, which are repeated measurements on the same items. They are not accuracy estimates or independent-text prevalences. The modeling tables omit original reference labels and raw text. Their preprocessing retains the source study's defaults for omitted items in successfully parsed batches; a complete table does not prove that every API response contained a usable annotation.

## Keep the outcome and estimand explicit

| Outcome set | Native response model | Interpretation |
|---|---|---|
| `hate_speech` | Ordinal, one outcome | Three ordered task labels |
| `mental_health_6flag` | Binary, six outcomes | Six separate presence indicators, potentially correlated |
| `mental_health_3group` | Binary, three outcomes | Prespecified grouped indicators; a different outcome definition from six flags |
| `mental_health_nominal` | Unordered categorical, one outcome | Seven labels, represented by six nonreference contrasts |
| `drug_review` | Ordinal, one outcome | Five ordered holistic sentiment categories |
| `drug_review_4aspect` | Ordinal, four outcomes | Efficacy, safety, burden, and cost; each has three ordered categories |

Use the returned `families` list so that category order and the nominal reference are retained:

```r
x <- gt_example("drug_review_4aspect", coding = "native")
design <- gt_design(x$object, x$facets)
report <- gt_preflight(x$data, x$outcomes, design, family = x$families)
print(report)
```

The script sources the checkout's functions locally. For these standalone snippets, first run `source("load_functions.R")`, which compiles the package's C code and so needs a C toolchain (Rtools on Windows, the Xcode command-line tools on macOS), or attach the installed package with `library(Gtheory4LLM)`.

The `mental_health_7L` and `mental_health_3L` variants are numeric working scores, not established clinical severity scales. Replacing the nominal response with either score changes the scientific question; it is not a workaround for a blocked categorical model. The six native outcome sets above are alternative views of three datasets, not six independent datasets.

Binary, ordinal and nominal G and Phi, when supported by an accepted fit, concern averages of **latent responses**. They do not directly answer the reliability of majority votes or observed label proportions. A nominal outcome's G and Phi are the mean and range of the generalized eigenvalues over its category contrasts, under exchangeable or unstructured covariance; observed-score ratios for unordered labels are not defined, because the labels have no score. Define the intended decision before choosing a coefficient or planning the number of evaluators and prompts.

## What the actual full-panel preflight reports

Every panel contains 100 items × 4 evaluators × 3 prompts × 6 temperatures × 3 seeds = 21,600 measurements. The example explicitly requests the full crossed hierarchy: 31 random sources including `item:evaluator:prompt:temp:seed`. This is a reference specification, not a claim that every interaction belongs in every study.

For that request, the observed output is:

| Outcome set | Predictor dimensions | Requested random dimensions | Free source covariance parameters | Dense allocation lower bound, GiB |
|---|---:|---:|---:|---:|
| Hate-Speech | 1 | 56,559 | 31 | 32.936 |
| Mental-Health six flags | 6 | 339,354 | 651 | 1,185.696 |
| Mental-Health three groups | 3 | 169,677 | 186 | 296.424 |
| Mental-Health nominal | 6 | 339,354 | 651 | 1,185.696 |
| Drug-Review holistic | 1 | 56,559 | 31 | 32.936 |
| Drug-Review four aspects | 4 | 226,236 | 310 | 526.976 |

All six panels pass the complete/balanced description, but all six fitting requests are blocked. There are two distinct issues:

1. At one observation per full cell, the requested observation-level random source is unsupported by the discrete engine. Source resolution fails; reported dimensions then describe the **requested model**, not a fitted model. No source is removed by this tutorial.
2. The full panels exceed the default 1,200-observation and 200-random-dimension limits. Joint requests also exceed the 80-parameter limit, and all six exceed the default `max_dense_bytes` working-memory limit, which is checked before anything is allocated. The byte estimate in the table above covers only one dense design matrix and one random-effect Hessian; `$resources$dense_working_bytes_estimate` adds the temporaries that forming the Hessian materializes and a planning multiplier, and is the figure the guard compares. Neither is peak memory or a runtime prediction. Kernel checks are explicitly skipped after these earlier failures.

Raising a size limit does not resolve the unsupported source or qualify the requested model at scale. Removing the full-cell term, other interactions, or outcomes changes the model. Such changes require a substantive design or outcome rationale. A smaller study must have a defensible sampling/conditioning rule and enough replication for its intended sources; selecting a subset because it yields a passing fit is not such a rule. Public sparse selection addresses storage, while acceptance and approximation adequacy still need evidence for each intended full native model.

## Respond to failures without changing the question silently

| Situation | What the example shows | Appropriate response |
|---|---|---|
| One missing Gaussian cell | `gaussian_missing_cell$fitting_feasible` is false | Check collection/coding; use a method supporting the genuine incomplete design. Do not fill in judgments merely to pass the guard. |
| One missing discrete cell | The small repeated-item model remains feasible, but has no supported analytic reliability scale | A permitted likelihood fit does not imply that balanced-panel G/Phi or D-study formulas apply. |
| Gaussian full-cell alias | `gaussian_complete$aliased_terms` identifies `item:occasion`, combined with the residual | Interpret the combined component; do not report separately estimated full-cell and observation residual variances. |
| Discrete full-cell source | `discrete_full_cell` fails source resolution | Reconsider the intended source structure/replication or use a supporting method. `full_cell = FALSE` is an explicit model change, not an automatic repair. |
| Disabled restart checks | An optimizer-completed fit is numerically rejected | Retain the diagnostics; coefficients are blocked. Re-enable the required checks. |
| Other numerical rejection | The script retains fits, errors, warnings, and acceptance failures | Inspect the specific failed check. For the same model, assess admissible starts, optimizer choice, and iteration budgets without loosening acceptance criteria to obtain a result. |
| Accepted discrete fit with `NA` SE/CI | This example requests a point estimate | Do not interpret `NA` as zero uncertainty. Development fits can request `check_hessian = TRUE`; unstable information remains unavailable, and a source on its boundary makes the intervals conditional on it. |
| Accepted first-order Laplace fit | `approximation_adequacy` remains `not_assessed_first_order_laplace` | Numerical acceptance does not establish integration accuracy or repeated-sampling performance; consult the separate validation studies. |

The binary fixture has 8 items and 12 exchangeable repetitions with an explicitly item-only random-intercept model. Omitting an occasion effect is an assumption of this separate illustration, not a reduction of the LLM design. It is a hand-constructed diagnostic example and supports no empirical recovery or coverage claim.

Inspect both decisions and retained attempts:

```r
result$fit_status
result$fits$restart_check_disabled$warnings
result$diagnostics$diagnostics$attempts
result$diagnostics$standard_errors_unavailable_reason
result$rejected_coefficient_message
result$unsupported_observed_message
```

For a refit of exactly the same discrete model, `fit$parameters` supplies named stored parameter coordinates for `gt_control(discrete = list(start = fit$parameters, ...))`. Keep links, category coding, source covariance structure, and parameterization unchanged when reusing that vector. `optimizer`, `maxit`, and `alternative_starts` control fitting; they do not correct a misspecified model or establish Laplace adequacy. See [control details](../man/gt_control.Rd).

## Recorded execution and sources

Executed on 2026-09-13 against the 0.0.7 source at base commit `137a9feb594aba648b55169b262e52298d694e25`, with this new example added. Environment: R 4.5.3, `aarch64-apple-darwin20`. The example completed in 1.66 seconds and exited successfully. Script SHA-256: `a20b65181e07746d3a9879fcc43865a5d30c878e54df8f55a4a2b5ce356734ac`.

Re-run on the `0.1.0.9000` development checkout after the engineering changes recorded in `NEWS.md`: the script is unchanged (same SHA-256), and every number on this page reproduced — the same six preflight rows, the same two numerical verdicts, and the same synthetic latent coefficient of 0.7044082.

Both synthetic optimizations completed. Disabling restart checks produced numerical rejection with `restart_or_tolerance_stability_failed`; the standard-check fit was accepted. Its latent G and Phi were both 0.7044082, with unavailable SEs and intervals. These are fixture outputs, not real-data results or acceptance targets for other platforms. The script preserves a different numerical verdict if one occurs and calculates no coefficient for a rejected fit. No full-panel discrete fit was attempted.

Dataset attribution, label definitions, and the three task-study references are in the [dataset overview](../man/gtheory_datasets.Rd), [Hate-Speech topic](../man/gtheory_hate_speech.Rd), [Mental-Health topic](../man/gtheory_mental_health.Rd), [Drug-Review topic](../man/gtheory_drug_review.Rd), and [bundled bibliography](../inst/DATASET_REFERENCES.bib). The public annotation source is identified by DOI `10.17605/OSF.IO/K9CAJ`; [data licensing and modifications](../inst/DATA_LICENSE.md) accompany the resources. This tutorial contains no manuscript, raw text, or private research archive. See [validation scope](VALIDATION_SCOPE.md) for the distinction between an executable workflow and scientific validation.
