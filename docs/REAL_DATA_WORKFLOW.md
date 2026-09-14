# Native LLM annotations: inspect the design, then decide what can be fitted

The three bundled datasets are useful for checking a real annotation design and choosing the response model. Their full native panels cannot currently be fitted by the dense discrete engine. This tutorial demonstrates that boundary directly, then uses separate synthetic fixtures to show how to respond to structural failures and numerical rejection. It reports no fitted reliability estimate for the real datasets.

## Run the complete example

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

The script sources the checkout's functions locally. For these standalone snippets, first run `source("load_functions.R")`, or attach the installed package with `library(Gtheory4LLM)`.

The `mental_health_7L` and `mental_health_3L` variants are numeric working scores, not established clinical severity scales. Replacing the nominal response with either score changes the scientific question; it is not a workaround for a blocked categorical model. The six native outcome sets above are alternative views of three datasets, not six independent datasets.

Binary/ordinal G and Phi, when supported by an accepted fit, concern averages of **latent responses**. They do not directly answer the reliability of majority votes or observed label proportions. No scalar categorical G/Phi is implemented. Define the intended decision before choosing a coefficient or planning the number of evaluators and prompts.

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

Raising a size limit does not resolve the unsupported source or provide a scalable implementation. Removing the full-cell term, other interactions, or outcomes changes the model. Such changes require a substantive design or outcome rationale. A smaller study must have a defensible sampling/conditioning rule and enough replication for its intended sources; selecting a subset because it yields a passing fit is not such a rule. Fitting the intended full native models remains backend work.

## Respond to failures without changing the question silently

| Situation | What the example shows | Appropriate response |
|---|---|---|
| One missing Gaussian cell | `gaussian_missing_cell$fitting_feasible` is false | Check collection/coding; use a method supporting the genuine incomplete design. Do not fill in judgments merely to pass the guard. |
| One missing discrete cell | The small repeated-item model remains feasible, but has no supported analytic reliability scale | A permitted likelihood fit does not imply that balanced-panel G/Phi or D-study formulas apply. |
| Gaussian full-cell alias | `gaussian_complete$aliased_terms` identifies `item:occasion`, combined with the residual | Interpret the combined component; do not report separately estimated full-cell and observation residual variances. |
| Discrete full-cell source | `discrete_full_cell` fails source resolution | Reconsider the intended source structure/replication or use a supporting method. `full_cell = FALSE` is an explicit model change, not an automatic repair. |
| Disabled restart checks | An optimizer-completed fit is numerically rejected | Retain the diagnostics; coefficients are blocked. Re-enable the required checks. |
| Other numerical rejection | The script retains fits, errors, warnings, and acceptance failures | Inspect the specific failed check. For the same model, assess admissible starts, optimizer choice, and iteration budgets without loosening acceptance criteria to obtain a result. |
| Accepted discrete fit with `NA` SE/CI | The synthetic coefficient is a point estimate | Do not interpret `NA` as zero uncertainty. Discrete intervals are not implemented. |
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

For a refit of exactly the same discrete model, `fit$parameters` supplies named optimizer coordinates for `gt_control(discrete = list(start = fit$parameters, ...))`. Keep links, category coding, source covariance structure, and parameterization unchanged when reusing that vector. `optimizer`, `maxit`, and `alternative_starts` control fitting; they do not correct a misspecified model or establish Laplace adequacy. See [control details](../man/gt_control.Rd).

## Recorded execution and sources

Executed on 2026-09-13 against the 0.0.7 source at base commit `137a9feb594aba648b55169b262e52298d694e25`, with this new example added. Environment: R 4.5.3, `aarch64-apple-darwin20`. The example completed in 1.66 seconds and exited successfully. Script SHA-256: `a20b65181e07746d3a9879fcc43865a5d30c878e54df8f55a4a2b5ce356734ac`.

Re-run on the `0.1.0.9000` development checkout after the engineering changes recorded in `NEWS.md`: the script is unchanged (same SHA-256), and every number on this page reproduced — the same six preflight rows, the same two numerical verdicts, and the same synthetic latent coefficient of 0.7044082.

Both synthetic optimizations completed. Disabling restart checks produced numerical rejection with `restart_or_tolerance_stability_failed`; the standard-check fit was accepted. Its latent G and Phi were both 0.7044082, with unavailable SEs and intervals. These are fixture outputs, not real-data results or acceptance targets for other platforms. The script preserves a different numerical verdict if one occurs and calculates no coefficient for a rejected fit. No full-panel discrete fit was attempted.

Dataset attribution, label definitions, and the three task-study references are in the [dataset overview](../man/gtheory_datasets.Rd), [Hate-Speech topic](../man/gtheory_hate_speech.Rd), [Mental-Health topic](../man/gtheory_mental_health.Rd), [Drug-Review topic](../man/gtheory_drug_review.Rd), and [bundled bibliography](../inst/DATASET_REFERENCES.bib). The public annotation source is identified by DOI `10.17605/OSF.IO/K9CAJ`; [data licensing and modifications](../inst/DATA_LICENSE.md) accompany the resources. This tutorial contains no manuscript, raw text, or private research archive. See [validation scope](VALIDATION_SCOPE.md) for the distinction between an executable workflow and scientific validation.
