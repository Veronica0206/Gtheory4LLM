# Gtheory4LLM: Generalizability Theory for LLM Subjective Tasks

Gtheory4LLM helps researchers study the reliability of subjective judgments
produced by large language models (LLMs), including annotations, ratings, and
LLM-as-a-judge evaluations. Specify which evaluator, prompt, and repeated-run
sources matter for your study, fit their variation, and compare projected
reliability across alternative numbers of evaluators and prompts.

This checkout is **0.0.7**. The files in `artifacts/` still describe the
previously submitted **0.0.6** release and are not rebuilt here. Build this
checkout to use the changes listed in `NEWS.md`.

The package provides exact balanced Gaussian analyses and a bounded,
first-order Laplace implementation for small discrete models. Numerical checks
and supported coefficient scales are explicit. Passing a software check does
not establish parameter recovery, approximation accuracy, or the number of
LLMs needed in a real application.

## Install

R 4.5 or later and OpenMx are required. Nothing in this package's own R code
needs R 4.5; the floor is inherited from OpenMx 2.22.11, which calls a C entry
point introduced in R 4.5.0 while declaring only `R (>= 3.5.0)` itself.
Declaring it here turns a later, unexplained compilation failure into a clear
refusal. Older pairings such as R 4.3 with OpenMx 2.21.11 have been reported to
pass these checks but are not part of the validated gate; to use one, install
from source with a relaxed floor, or `source("load_functions.R")`, which
imposes no version requirement. Install the source archive from the
[release page](https://github.com/Veronica0206/Gtheory4LLM/releases):

```r
install.packages("OpenMx")
install.packages("Gtheory4LLM_0.0.7.tar.gz", repos = NULL, type = "source")
library(Gtheory4LLM)
```

Use the archive name that the release page actually offers; older releases are
kept there. For a checkout, build and install with `R CMD build .` followed by
`R CMD INSTALL Gtheory4LLM_0.0.7.tar.gz`. Building the vignette needs knitr,
rmarkdown, and pandoc; nothing else does. CRAN availability is separate from
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

The same workflow is installed as a vignette: `browseVignettes("Gtheory4LLM")`,
or `vignette("LLM-workflow", package = "Gtheory4LLM")`. Its source is
[vignettes/LLM-workflow.Rmd](vignettes/LLM-workflow.Rmd). The main steps are:

```r
# llm_data and llm_design are created by the tutorial above.
gt_preflight(llm_data, "quality", llm_design)
summary(fit)
gt_diagnostics(fit)$numerically_accepted
gt_reliability(fit)
gt_dstudy(fit, expand.grid(evaluator = c(2, 4, 6),
                          prompt = c(2, 3, 4), run = c(1, 2)))
```

G describes relative comparisons between items. Phi additionally includes
absolute shifts across the declared measurement conditions. Decision studies
average over specified random facet populations and hold fitted source
covariances fixed. More evaluators or prompts are meaningful projections only
if those populations and covariance assumptions remain appropriate. These are
point estimates carrying an interval. For example, G = 0.80 describes the
universe-score share of variance for relative item comparisons under the
specified model; it is not 80% labeling accuracy or agreement with a human
reference. Phi additionally penalizes absolute panel shifts and is no larger
than G under this model.

Gaussian fits report an asymptotic standard error for every source variance and
a delta-method interval for G and Phi, both taken from the restricted-likelihood
curvature the fit already computes:

```r
summary(fit)$variances          # variance, std_error, boundary flag
gt_reliability(fit)$per_trait   # Erho2, Erho2_se, Erho2_lower, Erho2_upper, ...
```

These are asymptotic Wald quantities conditional on the declared model and
allocation. They describe estimation uncertainty in the fitted source
covariances, not sampling variation in the evaluator or prompt populations. A
source resting on a variance boundary has no Wald standard error; the fit says
so and, where the joint curvature is indefinite there, conditions the remaining
intervals on that source being held at zero. The discrete Laplace engine
computes no observed information and reports point estimates only.

### Fixed facets

A facet is random when the study generalizes to a population of its levels, and
fixed when the universe is exactly the levels used. Temperature is chosen, not
sampled, and a prompt set is often the whole set of interest. Declare those with
`fixed`, which applies the mixed model of Brennan (2001): the object-by-fixed
interaction is averaged over that facet's levels and joins universe-score
variance, and a source built only from fixed facets leaves the model.

```r
gt_reliability(fit, fixed = "temp")
```

A fixed facet's count cannot be changed, and a decision study may not project
over it.

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

At one observation per object-by-facets cell, a discrete fit cannot identify the
object-by-all-facets source that the default design requests, and that source is
never dropped silently. Declare the same design without it:

```r
binary_design <- gt_design("item", "rater", full_cell = FALSE)
```

`full_cell = FALSE` removes exactly that one term and leaves every other
requested source unchanged; `random = ~ item + rater` writes the reduced model
out in full. Either way the omission is an explicit modeling choice.

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
approximation. The default `covariance_parameterization = "auto"` uses exact-zero-capable
variance coordinates for univariate or diagonal discrete models and log-Cholesky
coordinates for joint unstructured models; general singular unstructured covariances are not
implemented. Numerical acceptance does not prove a global optimum or adequate
Laplace approximation. Rejected fits cannot produce coefficients.

Bootstrap, jackknife, discrete standard errors, observed-score discrete
reliability, and automatic minimum-allocation search are not provided. Gaussian
intervals are asymptotic and Wald; their coverage has been checked only on a
small set of crossed two-facet simulations, and estimator recovery and broad LLM
evaluation performance still require further statistical validation.

## Example data and references

`gt_example()` lists eight outcome sets from three **real LLM annotation
panels**: hate speech, mental health, and drug reviews. Each contains 21,600
measurements of 100 items crossed with four evaluators, three prompts, six
temperatures, and three seeds. These are alternative codings of three panels,
not eight independent datasets. The package includes design identifiers and
modeled annotations from the [public OSF deposit](https://doi.org/10.17605/OSF.IO/K9CAJ).
The original source CSV checksums match that deposit. Raw texts, original corpus
reference labels, and API metadata are omitted from the package tables.

The six discrete native outcome sets each contain 21,600 rows and exceed the
dense discrete engine limits by more than an order of magnitude; raising the
limits does not make the dense engine practical at that size. They are data resources, not full-panel discrete
fitting examples. Use a scientifically justified small design for this backend;
do not remove item interactions merely to obtain an accepted fit. The two
mental-health 7L/3L sets remain Gaussian working scores under both coding options.

Temperature and seed are also not exchangeable in the same way. Temperature is
a setting, so declare it `fixed` or analyse within one temperature. Seed is a
genuine replication facet, but its variation is strongly heteroscedastic: the
share of cells in which all three seeds agree falls from 0.92 to 0.73 (hate
speech), 0.91 to 0.68 (mental health), and 0.84 to 0.58 (drug reviews) between
temperature 0 and 1. A single seed variance pooled across all six temperatures
is misspecified for these panels. See `help("gtheory_datasets")`.

Other native codings preserve binary, ordinal, or unordered categorical outcomes;
`coding = "manuscript"` reproduces the seven historical Gaussian working-score
codings. Mental-health 7L/3L values are working scores, not established clinical
severity scales. The installed manual documents variables, category mappings,
preprocessing, source corpora, and the corresponding annotation studies. In
particular, the original mental-health preprocessing could default omitted items
within a parsed batch to NORMAL; these defaults cannot be distinguished in the
bundled tables. Interpret the labels with that limitation in mind:

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

Package code is licensed under [GPL-3](LICENSE). The real annotation tables
retain the **CC BY 4.0** license stated in the public deposit’s data codebook;
see [data attribution and license](inst/DATA_LICENSE.md). Synthetic tutorial
and test examples are covered by the code license. Public release files are
limited to the package, its documented examples, tests, and software release
artifacts. Unpublished manuscripts and research archives are excluded.
