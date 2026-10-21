# Gtheory4LLM: Generalizability Theory for LLM Subjective Tasks

Gtheory4LLM provides exact balanced Gaussian generalizability-theory models,
a bounded univariate Gaussian route for missing cells, and dense or sparse
first-order Laplace models for categorical outcomes in LLM annotation and
evaluation studies. Specify which evaluator, prompt, and
repeated-run sources matter for your study, fit their variation, and compare
projected reliability across alternative numbers of evaluators and prompts.

This is a research beta. Passing the package's numerical acceptance checks does
**not** establish parameter recovery, interval coverage, Laplace approximation
quality, or a scientifically sufficient number of evaluators. Read
[docs/LIMITATIONS.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/LIMITATIONS.md) before quoting a coefficient, and
[docs/VALIDATION_SCOPE.md](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/VALIDATION_SCOPE.md) for what has actually been
validated.

<!-- release-identity:start -->
Source version: **1.0.0.9000**.
For versioned archives, manuals and publication status, see the
[repository manifest](https://github.com/Veronica0206/Gtheory4LLM/blob/main/artifacts/manifest.json)
and [GitHub releases](https://github.com/Veronica0206/Gtheory4LLM/releases).
These repository records are excluded from the package archive; this source
version does not assert that a corresponding release has been published.
<!-- release-identity:end -->

## Development toward 1.0

This local development version adds sparse categorical estimation and fixed
call effects, optional information-based uncertainty, incomplete univariate
Gaussian panels, shared categorical simulation, and explicitly named observed,
decision and category-vector targets. Cost planning can screen those simulated
targets. Pilot planning assesses latent binary/ordinal interval precision or
point-estimator behavior for the observed, vector and decision targets.
The formula interface and historical release artifacts are retained.

These bounded implementations are not a released or fully qualified 1.0 package.
Full-panel solver performance, approximation accuracy, interval coverage and
cross-platform release qualification remain separate work; see
[development status](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/DEVELOPMENT_STATUS.md).

## Install

R 4.5 or later and OpenMx are required. Nothing in this package's own R code
needs R 4.5; the floor is inherited from OpenMx 2.22.11, which calls a C entry
point introduced in R 4.5.0 while declaring only `R (>= 3.5.0)` itself.
Declaring it here turns a later, unexplained compilation failure into a clear
refusal. Older pairings such as R 4.3 with OpenMx 2.21.11 have been reported to
pass these checks but are not part of the validated gate; to use one, install
from source with a relaxed floor, or `source("load_functions.R")`, which
imposes no version requirement.

The current CRAN release, which can be older than this source version, installs
with its dependencies:

```r
install.packages("Gtheory4LLM")
```

A specific release can also be installed from its versioned archive, for example
the [v0.6.0 archive](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.6.0),
`Gtheory4LLM_0.6.0.tar.gz`:

```r
install.packages("OpenMx")
install.packages(
  "https://github.com/Veronica0206/Gtheory4LLM/releases/download/v0.6.0/Gtheory4LLM_0.6.0.tar.gz",
  repos = NULL, type = "source"
)
library(Gtheory4LLM)
```

The repository keeps checksummed release files in [`artifacts/`](https://github.com/Veronica0206/Gtheory4LLM/tree/main/artifacts).
A 0.4.0 bundle, `Gtheory4LLM_0.4.0.tar.gz`, was prepared and tagged but never published; 0.4.1 supersedes it.
To install this source version, run `R CMD build .`, then
`R CMD INSTALL Gtheory4LLM_1.0.0.9000.tar.gz`, the archive it creates.
For the exact checked release archive, use the versioned GitHub release and
verify its accompanying manifest. Building the vignette
needs knitr, rmarkdown, and pandoc; using the installed package does not.
CRAN availability is separate from GitHub availability. The version CRAN
carries is recorded in the repository [development status](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/DEVELOPMENT_STATUS.md).

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
# llm_data is created by the tutorial above.
llm_formula <- quality ~ item * (evaluator + prompt) + evaluator:prompt:run
gt_preflight(llm_formula, llm_data, measured = "item")
fit <- gt_fit(llm_formula, llm_data, measured = "item")
summary(fit)
gt_diagnostics(fit)$numerically_accepted
as.data.frame(gt_reliability(fit))
dstudy <- gt_dstudy(fit, expand.grid(evaluator = c(2, 4, 6),
  prompt = c(2, 3, 4), run = c(1, 2)))
as.data.frame(dstudy)
```

The formula names outcomes and random sources in one call. Use `gt_design()`
when a facet appears in no random-source term, or when declaring within-cell
replication or batches; those declarations have no formula syntax. The
study-planning vignette retains explicit designs for these cases.

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

The default Gaussian engine reports asymptotic standard errors and delta-method intervals
where the likelihood curvature and boundary rules permit them. They use the
restricted (REML) or profile (ML) likelihood Hessian:

```r
summary(fit)$variances          # Documented source-variance summary table.
subset(as.data.frame(gt_reliability(fit)), kind == "outcome")
logLik(fit); AIC(fit); gt_component_vcov(fit)
```

These are asymptotic Wald quantities conditional on the declared model and
allocation. A source resting on a variance boundary has no Wald standard error.
For discrete fits, `gt_control(discrete = list(check_hessian = TRUE))` requests
full observed information in nuisance and covariance parameters; intervals are
available only when the accepted fit also passes the information and boundary
checks. They remain conditional on the Laplace approximation, with coverage
unestablished. What those intervals do and do not cover is stated once in
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
gt_reliability(fit, fixed = "prompt")
```

A fixed facet's count cannot be changed, and a decision study may not project
over it.

### Tables and figures

`as.data.frame()` exports reliability or D-study results with allocation,
coefficient scale, uncertainty status and extrapolation recorded alongside each
estimate. `gt_dstudy_target()` identifies supplied allocations meeting an
estimated target and preserves ties for the fewest measurements among them.
It does not optimize beyond the supplied grid or guarantee future reliability.

```r
reliability <- gt_reliability(fit)
as.data.frame(reliability)
plot(reliability, target = 0.80)
```

Preflight plots show cell completeness and replication, random-source
dimensions, or category representation across design groups. Outcome profiles
include category counts and groups with no observed variation; they do not
certify adequate information. D-study plots show coefficients against measurements per object,
with optional target lines and extrapolation markers. Figures use base R
graphics, so standard PNG/PDF devices can save them. The installed
`LLM-workflow` vignette demonstrates these views and CSV export;
[the visualization guide](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/VISUALIZATION.md)
explains their interpretation.

A portable report combines retained model context, diagnostics, result tables
and figures without rerunning optimization:

```r
report <- gt_report(fit, reliability = reliability)
# Writes a standalone offline HTML file; existing files are protected.
# gt_export_report(report, "analysis-report.html")
```

Reports exclude observations and group-level identifiers, while retaining
variable/source names and aggregate results. Review those names before sharing.
Unavailable fitting provenance stays unavailable; the report-generation
session is recorded separately. See the [reporting guide](https://github.com/Veronica0206/Gtheory4LLM/blob/main/docs/ANALYSIS_REPORT.md).

## Plan an annotation study

Study planning separates three quantities: **distinct pilot items**
provide estimation information, **annotations per item** define the final score,
and **items per request** define shared context and request overhead. Increasing
one does not substitute for increasing another. These workflows are included in
the package since version 0.5.0; their statistical boundaries are described below.

The [study-planning vignette](vignettes/study-planning.Rmd) runs synthetic examples
of all three additions. Its monetary amounts are illustrative user inputs.

- `gt_batch_reliability()` and `gt_batch_dstudy()` project absolute item-score
  error, explicitly named item differences and weighted aggregate error for
  supported Gaussian shared-call fits. A call shift cancels from a same-batch
  difference but remains in an absolute score. Targets condition on the recorded
  fixed item grouping; all instrumentation facets remain random. These are point
  projections, with no sampling intervals, regrouping or batch-size optimization.
- `gt_plan()` evaluates a supplied bounded grid using dated, user-supplied costs
  and constraints. It retains every candidate, minimum-cost ties, the cost versus
  reliability Pareto set, and changes in error contributions from a declared
  baseline. It screens a point estimate or, separately, an available lower
  confidence bound. Missing bounds stay unavailable. It does not choose evaluator
  identities or change a facet from random to fixed to improve a result.
  Categorical observed and decision targets use point screening and report
  Monte Carlo integration error separately from parameter uncertainty.
- `gt_simulate()` draws Gaussian or categorical panels under a fitted or
  explicit parameter scenario. `gt_pilot_plan()` refits bounded Gaussian or
  binary/ordinal pilots, including joint outcomes, to assess interval precision
  for observed Gaussian or latent binary/ordinal coefficients. Pilot item/facet counts
  may vary while `target_counts` holds the eventual annotation protocol constant.
  The planner records every attempt, refusal and unavailable interval, with
  Monte Carlo errors and conditional interval-width summaries. This evaluates
  model-based precision, not calibrated coverage or guaranteed study adequacy.
  For categorical observed-score, category-vector or decision targets, a
  separate point-estimator route reports acceptance, target availability,
  bias and RMSE against an independently integrated scenario reference. It
  includes nominal outcomes and eligible fixed calls, retains every failed
  attempt, and reports reference and inner integration errors separately.

For example, after fitting an accepted model without a shared-call source:

```r
plan <- gt_plan(fit,
  candidates = list(evaluator = 2:4, prompt = 1:3),
  cost = function(d) data.frame(annotation = 0.01 * d$total_annotations,
                                setup = 2 * d$allocation_evaluator),
  currency = "USD", cost_date = "2026-10-09", study_items = 1000,
  target = 0.80, coefficient = "Phi")
subset(as.data.frame(plan), minimum_cost %in% TRUE)
```

The analytic cost-planning route refuses modelled `Call` fits. The categorical
target route supports the fitted equal fixed-call layout, with unchanged item
count and group membership; it does not optimize batch size or regroup items.
Use the separate batch projection functions for Gaussian call targets.
Supplying request costs for an independent-item model does not account for
shared-call error, and adding human-review costs does not itself model a benefit
from review. Pilot interval-width planning refuses batch declarations and
nominal outcomes; their point-target route supplies no parameter intervals
or coverage. See the function manuals for the remaining scope and limits.

A new shared-call fit retains compact item-to-batch labels even with
`retain = list(data = FALSE)`: the layout is necessary for named comparisons.
Batch projection objects contain those labels and supplied target weights.
`gt_report(fit)` and its HTML export exclude the labels; share a projection object
only when its identifiers are appropriate to disclose. Older fits lacking the
layout must be refitted rather than having their grouping guessed.

## Designs and outcome types

Facet names do not impose a hierarchy. Declare any nonempty subset of the
instrumentation facets to interact with the object, give other facets explicit
nesting parents, and choose higher-order interactions separately. With four
facets, all 15 nonempty crossed subsets are supported by the design interface.
An explicit random-source formula is also available, and `gt_fit()` and
`gt_preflight()` accept a two-sided model formula such as `score ~ item * rater`
in place of the outcome names and the design. `gt_preflight()` reports
the requested and resolved sources, dimensions, replication, resource limits,
and downstream operations before optimization; it does not certify statistical
identification or successful fitting.

| Outcome | Fitting | Coefficients and explicit projection targets |
|---|---|---|
| Gaussian | Exact balanced ML/REML, univariate or joint; bounded observed-row ML/REML for incomplete univariate panels | Observed-score G/Phi and explicit composites; incomplete fits require an intended balanced projection |
| Binary | Dense or sparse Bernoulli probit/logit, univariate or joint | Latent G/Phi; separate observed-score, category-vector and decision targets |
| Ordinal | Dense or sparse cumulative probit/logit, univariate or joint | Latent G/Phi; separate declared-score, category-vector and decision targets |
| Unordered categorical | Dense or sparse reference-category multinomial softmax, univariate or joint | Category-vector and decision targets; no analytic scalar G/Phi or arbitrary numeric-score ratio |

`gt_family()` records category order and reference categories explicitly, beyond
the distribution and link in a base R family object. Named lists match these
specifications to joint outcomes. Gaussian and discrete outcomes cannot be
combined in one joint fit.

Gaussian fits use the exact balanced likelihood through OpenMx by default.
For univariate Gaussian models, `gt_control(gaussian = list(engine = "lme4"))`
fits the same sources through lme4. Acceptance requires completion,
stationarity and restart checks, plus agreement between the two deviance
calculations at the lme4 estimates. These checks do not prove global
optimality. This alternative does not supply source-variance standard errors
or coefficient intervals.

To fit missing whole cells in a univariate Gaussian panel, explicitly select
`gt_control(gaussian = list(engine = "lme4", panel = "observed"))`.
The route checks an independent dense observed-row ML/REML likelihood and
covariance-kernel identification, with a default limit of 1,000 observed rows
and a preparation-memory guard. It fills no cells and assumes missingness is
ignorable for the specified covariance model. Ordinary reliability of that
incomplete allocation remains unavailable. `gt_dstudy(..., projection = "balanced")`
instead requires every intended facet count and projects to that complete
future allocation with all facets random; no coefficient intervals are supplied.

Discrete fits use a first-order Laplace likelihood. Select sparse algebra with
`gt_control(discrete = list(engine = "sparse"))`; dense remains the default.
Both routes support binary, ordinal and nominal outcomes, joint categorical
models and eligible equal fixed-call layouts. Shared row, dimension and parameter
guards still apply, alongside the selected engine's memory guard. Sparse algebra
does not by itself qualify a large model or improve the approximation. An integrated external
engine adapter for these outcomes is not implemented. `gt_laplace_check(fit)`
compares its objective at the fitted parameters with numerical quadrature or
importance sampling. The latter uses a defensive mixture of 90% Laplace
Gaussian and 10% random-effect prior, with the full mixture density in every
weight. This guarantees finite weight moments for the supported categorical
probability likelihoods; it does not guarantee adequate precision from a
finite sample. The Monte Carlo standard error and empirical effective sample
size are diagnostics, and the comparison does not estimate parameter bias.

Discrete observations follow their chosen response distributions; their latent
random effects remain Gaussian. Gaussian assumptions therefore remain part of
the model. Latent binary/ordinal reliability concerns an averaged latent
response, not observed proportions, majority votes, or category agreement.
Joint Gaussian-discrete models are not implemented.

`gt_categorical_target()` defines those other targets explicitly using paired
future panels that share object effects and redraw instrumentation effects.
Its score target is the absolute repeated-panel variance ratio; ordinal scores
must be declared. Its category-vector target uses category proportions and is
invariant to relabeling unordered categories. Decision agreement uses plurality
votes with uniform tie-breaking and reports decision diversity: a constant label
can have perfect agreement and no discrimination. These targets hold fitted
parameters fixed and report simulation error, not parameter confidence intervals.
They require no model refits. `gt_plan()` can compare them using
`coefficient = "observed_score"`, `"category_vector"` or `"decision_agreement"`,
with an explicit scale and seeded integration controls; see `help("gt_plan")`.

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

The default Gaussian route and ordinary analytic coefficients require a complete
balanced coded panel. The explicitly selected observed-row Gaussian route and
intended balanced projection have separate guards described above. Both discrete
engines are bounded by row, dimension, parameter and working-memory limits;
sparse requests use the sparse memory budget rather than the dense budget.
`gt_preflight()` reports these structural and resource checks before optimization.

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
Use `gt_example()` rather than `data()` to load an outcome set: it returns the
chosen coding, its family specification, and provenance together with the data.

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
| [vignettes/LLM-workflow.Rmd](vignettes/LLM-workflow.Rmd) | The end-to-end reliability tutorial, installed and runnable |
| [vignettes/study-planning.Rmd](vignettes/study-planning.Rmd) | Fixed-layout batch targets, monetary allocation search and Gaussian pilot precision |
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
