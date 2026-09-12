# Gtheory4LLM: Generalizability Theory for LLM Subjective Tasks

Gtheory4LLM helps researchers study the reliability of subjective judgments
produced by large language models (LLMs), including annotations, ratings, and
LLM-as-a-judge evaluations. Specify which evaluator, prompt, and repeated-run
sources matter for your study, fit their variation, and compare projected
reliability across alternative numbers of evaluators and prompts.

Version **0.0.6** provides exact balanced Gaussian analyses and a bounded,
first-order Laplace implementation for small discrete models. Numerical checks
and supported coefficient scales are explicit. Passing a software check does
not establish parameter recovery, approximation accuracy, or the number of
LLMs needed in a real application.

## Install

R 4.2 or later and OpenMx are required. Install the source archive from the
[release page](https://github.com/Veronica0206/Gtheory4LLM/releases):

```r
install.packages("OpenMx")
install.packages("Gtheory4LLM_0.0.6.tar.gz", repos = NULL, type = "source")
library(Gtheory4LLM)
```

For a checkout, build and install with `R CMD build .` followed by
`R CMD INSTALL Gtheory4LLM_0.0.6.tar.gz`. CRAN availability is separate from
GitHub availability; this repository does not imply CRAN acceptance.

## A complete LLM reliability workflow

The installed tutorial creates synthetic continuous judgments for 24 items,
4 evaluators, 3 prompts, and 2 runs within each evaluator/prompt pair. It
completes design inspection, fitting, diagnostics, G/Phi calculation, and an
18-allocation decision study. It requires no API keys or external data.

```r
source(system.file("doc", "LLM-workflow.R",
                   package = "Gtheory4LLM", mustWork = TRUE))
```

Read the [illustrated guide](inst/doc/LLM-workflow.html) or locate the installed
HTML with `system.file("doc", "LLM-workflow.html", package = "Gtheory4LLM")`.
The main steps are:

```r
# llm_data and llm_design are created by the tutorial above.
gt_preflight(llm_data, "quality", llm_design)
summary(fit)
gt_diagnostics(fit)$numerically_accepted
gt_reliability(fit)$per_trait
gt_dstudy(fit, expand.grid(evaluator = c(2, 4, 6),
                          prompt = c(2, 3, 4), run = c(1, 2)))$results
```

G describes relative comparisons between items. Phi additionally includes
absolute shifts across the declared measurement conditions. Decision studies
average over specified random facet populations and hold fitted source
covariances fixed. More evaluators or prompts are meaningful projections only
if those populations and covariance assumptions remain appropriate. These are
point estimates, not accuracy guarantees or uncertainty intervals.

## Designs and outcome types

Facet names do not impose a hierarchy. Declare any nonempty subset of the
instrumentation facets to interact with the object, give other facets explicit
nesting parents, and choose higher-order interactions separately. With four
facets, all 15 nonempty crossed subsets are supported by the design interface.
An explicit random-source formula is also available. `gt_preflight()` reports
the requested and resolved sources, dimensions, replication, resource limits,
and downstream operations before optimization; it does not certify statistical
identification or successful fitting.

| Outcome | Fitting | Supported G/Phi and D studies |
|---|---|---|
| Gaussian | Exact balanced ML/REML, univariate or joint multivariate | Observed-score coefficients and explicitly weighted composites |
| Binary | Bernoulli probit/logit, univariate or joint | Explicitly requested latent-response coefficients |
| Ordinal | Cumulative probit/logit, univariate or joint | Explicitly requested latent-response coefficients |
| Unordered categorical | Reference-category multinomial softmax, univariate or joint | No scalar coefficient implemented |

Discrete observations follow their chosen response distributions; their latent
random effects remain Gaussian. Gaussian assumptions therefore remain part of
the model. Latent binary/ordinal reliability concerns an averaged latent
response, not observed proportions, majority votes, or category agreement.
Joint Gaussian-discrete models are not implemented.

Traditional method-of-moments (MoM) G theory already accommodates random
effects and crossed/nested designs. The package's contribution is the common
workflow for explicit source selection, joint covariance models, different
response families, and supported allocation comparisons. It does not claim
that random effects are novel or that likelihood is uniformly superior to
MoM. See [Brennan (2001)](https://doi.org/10.1007/978-1-4757-3456-0) and
[Jiang et al. (2020)](https://doi.org/10.3758/s13428-020-01399-z) for G theory
and earlier multivariate likelihood implementations.

## Numerical controls and limits

`gt_control()` exposes named starting values, reproducible additional fitting
attempts, and an optimizer held fixed across attempts. Discrete fits retain
rejected candidates and their reasons. `summary(fit)` reports acceptance,
selected attempt, boundary status, and approximation status without printing
model internals or observations; detailed records remain available.

The Gaussian engine requires a complete balanced Cartesian panel of coded
facet levels and one observation per full cell. Nested groups are scoped by
their parents and shared across objects; physical nesting with disjoint child
labels is outside this Gaussian preparation backend. Reliability and D studies
also require a complete balanced coded panel.

The dense discrete backend defaults to at most 1,200 rows, 200 random-effect
dimensions, and 80 parameters. Raising these limits does not validate the
approximation. Exact-zero variance parameters are available for univariate or
diagonal discrete models; general singular unstructured covariances are not
implemented. Numerical acceptance does not prove a global optimum or adequate
Laplace approximation. Rejected fits cannot produce coefficients.

Bootstrap, jackknife, general uncertainty intervals, observed-score discrete
reliability, and automatic minimum-allocation search are not provided.
Estimator recovery, interval coverage, and broad LLM evaluation performance
require further statistical validation.

## Example data and references

`gt_example()` lists eight outcome sets from three **entirely synthetic**
panels illustrating hate-speech, mental-health, and drug-review annotation
tasks. Each contains 576 hypothetical measurements, with no real texts, LLM
responses, clinical data, or source-study records. The legacy argument
`coding = "manuscript"` selects numeric-score compatibility only; it does not
reproduce any manuscript data or findings. The cited studies motivate task
types and supplied none of the synthetic observations. The installed manual describes their exact
origin, variables, response codings, and task literature:

```r
gt_example()
x <- gt_example("hate_speech")
help("gtheory_datasets", package = "Gtheory4LLM")
help("gtheory_hate_speech", package = "Gtheory4LLM")
help("gtheory_mental_health", package = "Gtheory4LLM")
help("gtheory_drug_review", package = "Gtheory4LLM")
```

The [task bibliography](inst/DATASET_REFERENCES.bib) is installed as
`system.file("DATASET_REFERENCES.bib", package = "Gtheory4LLM")`. Use
`citation("Gtheory4LLM")` for the software citation. Loading a table does not
establish that every design or full joint discrete fit is feasible.

## Validation and user feedback

A single release entrypoint checks sources and the distributed archive
separately:

```sh
python3 scripts/run_validation.py --scope all --as-cran
```

See [validation instructions](scripts/VALIDATION.md) for the locked environment,
minimum-R and Windows/macOS checks, source-only checks, and retained evidence.
The numerical suite includes independent dense Gaussian likelihoods,
binary/ordinal comparisons with lme4 and ordinal, likelihood/derivative
identities, joint covariance estimation, and coefficient aggregation. These
are specific numerical checks, not a substitute for simulation-based
statistical validation. A configured workflow is not evidence of a passing run.

Report installation failures, unclear design declarations, and numerical
problems through [GitHub issues](https://github.com/Veronica0206/Gtheory4LLM/issues).
Please include the package/R versions, a small synthetic example, the declared
family/design, and relevant diagnostics. Remove private observations and
credentials before posting. Maintainer: Jin Liu,
[Veronica.Liu0206@gmail.com](mailto:Veronica.Liu0206@gmail.com).

## License

Package code is licensed under [GPL-3](LICENSE). Public release files are
limited to the package, its documented examples, tests, and software release
artifacts. Unpublished manuscripts and research archives are excluded.
