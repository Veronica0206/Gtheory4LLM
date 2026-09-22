# Gtheory4LLM: Generalizability Theory for LLM Subjective Tasks

Gtheory4LLM provides exact balanced Gaussian generalizability-theory models and
a bounded experimental Laplace engine for small discrete G-theory models used in
LLM annotation and evaluation studies. Specify which evaluator, prompt, and
repeated-run sources matter for your study, fit their variation, and compare
projected reliability across alternative numbers of evaluators and prompts.

This is a research beta. Passing the package's numerical acceptance checks does
**not** establish parameter recovery, interval coverage, Laplace approximation
quality, or a scientifically sufficient number of evaluators. Read
[docs/LIMITATIONS.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/LIMITATIONS.md) before quoting a coefficient, and
[docs/VALIDATION_SCOPE.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/VALIDATION_SCOPE.md) for what has actually been
validated.

<!-- release-identity:start -->
Source version: **0.2.0**.
For versioned archives, manuals and publication status, see the
[repository manifest](https://github.com/Veronica0206/Gtheory4LLM/blob/main/artifacts/manifest.json)
and [GitHub releases](https://github.com/Veronica0206/Gtheory4LLM/releases).
These repository records are excluded from the package archive; this source
version does not assert that a corresponding release has been published.
<!-- release-identity:end -->

## Install

R 4.5 or later and OpenMx are required. Nothing in this package's own R code
needs R 4.5; the floor is inherited from OpenMx 2.22.11, which calls a C entry
point introduced in R 4.5.0 while declaring only `R (>= 3.5.0)` itself.
Declaring it here turns a later, unexplained compilation failure into a clear
refusal. Older pairings such as R 4.3 with OpenMx 2.21.11 have been reported to
pass these checks but are not part of the validated gate; to use one, install
from source with a relaxed floor, or `source("load_functions.R")`, which
imposes no version requirement.

For example, install the versioned [v0.1.0 archive](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.1.0):

```r
install.packages("OpenMx")
install.packages(
  "https://github.com/Veronica0206/Gtheory4LLM/releases/download/v0.1.0/Gtheory4LLM_0.1.0.tar.gz",
  repos = NULL, type = "source"
)
library(Gtheory4LLM)
```

The repository keeps checksummed release files in [`artifacts/`](https://github.com/Veronica0206/Gtheory4LLM/tree/main/artifacts).
To install this source version, run `R CMD build .`, then
`R CMD INSTALL Gtheory4LLM_0.2.0.tar.gz`, the versioned archive it creates. Building the vignette
needs knitr, rmarkdown, and pandoc; using the installed package does not.
CRAN availability is separate from GitHub availability. Current submission
status is recorded in the repository [development status](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/DEVELOPMENT_STATUS.md).

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

Gaussian fits report asymptotic standard errors and delta-method intervals
where the likelihood curvature and boundary rules permit them. They use the
restricted (REML) or profile (ML) likelihood Hessian:

```r
summary(fit)$variances          # variance, std_error, boundary flag
gt_reliability(fit)$per_trait   # Erho2, Erho2_se, Erho2_lower, Erho2_upper, ...
logLik(fit); AIC(fit); gt_component_vcov(fit)
```

These are asymptotic Wald quantities conditional on the declared model and
allocation. A source resting on a variance boundary has no Wald standard error,
and the discrete Laplace engine computes no observed information at all. What
those intervals do and do not cover is stated once in
[docs/LIMITATIONS.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/LIMITATIONS.md).

### Fixed facets

A facet is random when the study generalizes to a population of its levels, and
fixed when the universe is exactly the levels used. A chosen temperature or
prompt set may be fixed when inference is restricted to those conditions; the
choice follows the intended generalization, not the facet name. Declare it with
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

A first discrete fit, start to finish — the guard above, preflight, binary and
ordinal fits, diagnostics, latent reliability and a decision study — is
installed as a runnable script:

```r
source(system.file("examples", "discrete-first.R", package = "Gtheory4LLM"))
```

`system.file("examples", "discrete-boundary.R", package = "Gtheory4LLM")` shows
the companion case: a constructed panel whose zero object variance is a
legitimate optimum rather than evidence about reliability.

## Numerical controls and limits

`gt_control()` exposes named starting values, reproducible additional fitting
attempts, an optimizer held fixed across attempts, the discrete resource limits,
and which optional components a fit keeps. Discrete fits retain rejected
candidates and their reasons. `summary(fit)` reports acceptance, selected
attempt, boundary status, and approximation status without printing model
internals or observations; detailed records remain available.

Two limits decide whether a model can be fitted at all. The Gaussian engine
requires a complete balanced coded panel, as do `gt_reliability()` and
`gt_dstudy()`. The dense discrete backend is bounded by row, dimension,
parameter, and working-memory limits, and refuses before allocating rather than
after allocation fails. `gt_preflight()` reports both before any optimization.

**Every limitation is listed once, in
[docs/LIMITATIONS.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/LIMITATIONS.md)** — what the designs, the Gaussian
engine and the discrete engine do and do not support, which combinations are
not implemented, and what "supported" means here. Read it before quoting a
coefficient. What has actually been checked, and what a future study still has
to establish, is in [docs/VALIDATION_SCOPE.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/VALIDATION_SCOPE.md); the
initial [statistical pilots](https://github.com/Veronica0206/Gtheory4LLM/blob/main/validation-studies/README.md) preserve their
coverage, approximation and recovery results, including boundaries and
unavailable comparisons.

## Example data and references

The [real-data workflow](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/REAL_DATA_WORKFLOW.md) audits the native outcome
types and full designs of all three panels, then demonstrates how to interpret
unsupported requests and numerical failures.

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

Temperature-specific seed agreement is a useful descriptive diagnostic. Lower
agreement at higher temperatures may reflect changes in category probabilities,
latent variances, or both; agreement alone does not identify which changed.

Use `fixed = "temp"` when the coefficient is intended to average over exactly
the observed temperatures. This changes the reliability estimand after fitting;
it cannot repair misspecification in the fitted variance model. If pooling
across temperatures is questionable, a within-temperature analysis is one
sensitivity analysis, with its own conditional estimand. It is not the only
possible model and does not generalize across temperatures automatically.
See `help("gtheory_datasets")`.

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

See [validation instructions](https://github.com/Veronica0206/Gtheory4LLM/blob/main/scripts/VALIDATION.md) for the locked environment,
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

Package code is licensed under [GPL-3](https://github.com/Veronica0206/Gtheory4LLM/blob/main/LICENSE). The real annotation tables
retain the **CC BY 4.0** license stated in the public deposit’s data codebook;
see [data attribution and license](inst/DATA_LICENSE.md). Synthetic tutorial
and test examples are covered by the code license. Public release files are
limited to the package, its documented examples, tests, and software release
artifacts. Unpublished manuscripts and research archives are excluded.

## Where to read what

Each document has one job, so that nothing has to be kept true in two places.

| Document | What it covers |
|---|---|
| This README | Install, a complete worked workflow, and what the package is for |
| [vignettes/LLM-workflow.Rmd](vignettes/LLM-workflow.Rmd) | The end-to-end tutorial, installed and runnable |
| [docs/LIMITATIONS.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/LIMITATIONS.md) | Everything the package does not do, listed once |
| [docs/VALIDATION_SCOPE.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/VALIDATION_SCOPE.md) | What has been checked, how, and what that does not establish |
| [docs/REAL_DATA_WORKFLOW.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/REAL_DATA_WORKFLOW.md) | The bundled panels, their native outcomes, and their resource ceilings |
| [docs/DEVELOPMENT_STATUS.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/DEVELOPMENT_STATUS.md) | The current release state and what is being worked on |
| [docs/ROADMAP.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/ROADMAP.md) | Planned work beyond this release, in the order it is planned |
| [docs/DISCRETE_BACKEND_CONTRACT.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/DISCRETE_BACKEND_CONTRACT.md) | Private dense response, matrix and mode interfaces |
| [NEWS.md](NEWS.md) | Version history |
| [docs/CONTRIBUTING.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/CONTRIBUTING.md), [docs/RELEASE_CHECKLIST.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/RELEASE_CHECKLIST.md), [docs/REPOSITORY_POLICY.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/REPOSITORY_POLICY.md), [SECURITY.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/SECURITY.md) | Working on the package itself |

## Development and release checks

See the [contribution guide](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/CONTRIBUTING.md) for setup and statistical
change requirements, and the [release checklist](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/RELEASE_CHECKLIST.md) for
version, tag, archive, and manual correspondence. Software checks and scientific
validation are reported separately. The [development status](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/DEVELOPMENT_STATUS.md)
tracks completed work and remaining extensions.
