# Gtheory4LLM 0.2.0

Cut from the 0.2.0 development line for the CRAN resubmission. Every estimate,
coefficient and acceptance decision in `tests/package-characterization.R`
reproduces the 0.1.0 values within the tolerances recorded there. The one change
to fitting itself is the refusal of a dense conditional solve that does not
solve its own system, recorded under engineering below. Everything else is new
reporting, corrections, engineering behind private seams, and the release
maintenance that followed 0.1.0.

## Staged numerical diagnostics

- `gt_diagnostics()` gains a `stages` element summarising the numerical checks
  a fit passed through: optimizer completion, conditional mode, independent
  stationarity, restart and tolerance stability, numerical acceptance, and
  approximation assessment, each with a status, a reason and its supporting
  measurements, so a rejection names the stage responsible without the caller
  reading private optimizer records. The status is `passed`, `failed`,
  `not_assessed` for a check that did not run or does not apply to the engine,
  or `inconclusive` for one that ran without a clear verdict; absent evidence
  is never read as a pass. The summary is derived from evidence the fit already
  retained, including the tolerances that governed the retained solve: it never
  refits and never changes an acceptance decision. Print methods are registered
  for the stage summary and for a single stage.
- The conditional-mode diagnostic stage no longer reports `passed` when a
  record says its solve was tightened but does not retain the tolerance that
  governed it. That record now reports `inconclusive`, because the retained
  evidence cannot establish that the solve met what was asked of it. This
  changes reporting only, and only for incomplete or older fit objects: a fit
  produced by this version retains that tolerance. Fitting, numerical
  acceptance, and reliability and D-study eligibility are unchanged.

## Corrections

- README links to repository documents that the source archive does not ship
  (`docs/`, `scripts/VALIDATION.md`, `validation-studies/`, `artifacts/`,
  `SECURITY.md`, `LICENSE`) are now absolute repository URLs. CRAN's incoming
  check reported the relative `scripts/VALIDATION.md` and `LICENSE` links of
  the 0.0.6 submission as invalid file URIs; a test now refuses any README or
  NEWS link to a file that `.Rbuildignore` keeps out of the archive.
- `SECURITY.md` named a control that does not exist. The retention switch is
  `gt_control(retain = list(data = FALSE))`.
- `BIC()` on a REML fit is documented, and its convention, N response vectors
  with the covariance parameters only, is recorded as
  `reml_BIC_response_vectors_variance_parameters`. `help("gt_fit")` no longer
  says the generic criteria are unavailable for REML: the fit's own `AIC` and
  `BIC` elements are `NA`, the generics are not.
- `load_functions.R` sources `R/discrete_sparse_mode.R`, matching the Collate
  field; a test keeps the two lists equal.
- `print(gt_diagnostics(fit))` states the standard-error availability once.
- A Gaussian source flagged at the boundary is now classified as entirely zero
  or as singular but nonzero, and interior-block standard errors say which
  they condition on. A rank-deficient source with positive variances was
  described as "held at zero" in the fit's interpretation, its diagnostic
  issues and the printed coefficient note; it is now described as held fixed
  at its fitted covariance, from one shared clause. `gt_component_vcov()`
  adds `conditional_on_fixed` naming every fixed component, and
  `conditional_on_zero` now names only the zero ones. The boundary flag, the
  point estimates and the interval arithmetic are unchanged (#36).
- `logLik()`, and through it `AIC()` and `BIC()`, refuse a fit that failed
  numerical acceptance, as `gt_reliability()` already did; the objective
  stays in `minus2loglik` for diagnosis. The generics previously returned
  ordinary values while `print(fit)` called the estimates diagnostic only.
- `gt_control(retain = list(data = FALSE))` now removes every copy of the
  observations. The retained Gaussian OpenMx model carried the raw outcomes as
  summary metadata, so a fit saved after dropping the data still held them,
  and the recorded call held the whole data frame, unused columns included,
  when the fit came through `do.call()` or with the data written inline.
  The observations are stripped from the retained model, which nothing reads
  after fitting, the call's data argument is replaced by a marker, and a
  test hunts a sentinel observation and a sentinel unused column through the
  serialized fit for direct, programmatic and inline calls. `SECURITY.md`
  says so.
- Gaussian facet levels are matched by value rather than by their printed
  form. Distinct doubles that format alike, such as `1e15` and `1e15 + 1`,
  passed `gt_preflight()` and were then refused by `gt_fit()` as duplicate
  cells; they now fit (#39, facet identity).
- Gaussian outcomes are centred before the factorial contrasts are formed.
  The intercepts are profiled exactly in a balanced design, so no likelihood
  term changes, but a large common offset no longer enters the contrasts as
  differences of huge sums: an offset of `1e12` moved accepted estimates in
  their fifth digit and `1e15` in their second. A regression fits the same
  represented panel at the origin and at an offset of `1e12` and requires
  identical variances and deviance.
- `scripts/prepare_release.py --from-checked-candidate` refuses a candidate
  directory without a check report recording a successful R-devel check of
  exactly those archive bytes, and records the checking R version in the
  manifest's provenance.

## Engineering behind private seams

- The dense conditional solve now refuses a factorization that does not solve
  its own system (`dense_newton_solve_invalid`, `dense_final_factor_invalid`),
  reporting the backward error and its bound when the refusal happens at the
  starting values. A native Cholesky can return successfully and still hand
  back a factor of some other matrix; issue #14 captured one such instance on a
  hosted runner, and a returned factor is no longer treated as valid merely
  because no error was raised.
- The discrete engine is split into response-kernel, dense, mode and sparse
  modules without numerical change. `Matrix` and `methods` joined Imports for
  the private sparse random-design, Hessian, factorization and conditional-mode
  files behind a private evaluator seam. None of it is public API: no public
  entry point selects the sparse path, and every fit still runs through the
  dense engine. The compatibility matrix runs the sparse factorization test on
  every platform.

## Release maintenance after 0.1.0

- Keeps archive source-version summaries publication-neutral; publication
  updates only excluded repository metadata. Preparation rejects an already
  tagged or published version before building.
- Separates the development checkout from the published 0.1.0 archive and
  manual, whose files and tag remain unchanged.
- Updates installation instructions to the published GitHub release, records
  the configured branch protection and publication checks, and moves completed
  0.1.0 hardening out of the future roadmap.
- Distinguishes the rebuilt R-devel candidate from the published archive;
  candidate-check evidence applies to the file actually checked.
- Catches stale publication claims outside the release summary blocks and
  records the active rule preventing release-tag updates and deletions.

<!-- release-identity:start -->
Source version: **0.2.0**.
For versioned archives, manuals and publication status, see the
[repository manifest](https://github.com/Veronica0206/Gtheory4LLM/blob/main/artifacts/manifest.json)
and [GitHub releases](https://github.com/Veronica0206/Gtheory4LLM/releases).
These repository records are excluded from the package archive; this source
version does not assert that a corresponding release has been published.
<!-- release-identity:end -->

# Gtheory4LLM 0.1.0

First 0.1 release. An earlier 0.1.0 candidate was prepared locally but never
tagged or published, so this release is cut from the hardened sources instead
and supersedes it; the notes below cover both. The statistical models are
unchanged from that candidate: every estimate, coefficient and acceptance
decision in `tests/package-characterization.R` reproduces its values within the
tolerances recorded there.

## Numerical baseline

- Adds a characterization baseline over ten canonical cases (Gaussian ML and
  REML, multivariate, a variance boundary, fixed facets, a nested design,
  binary, ordinal and multinomial Laplace, and a deliberately rejected discrete
  fit). Optimizer-dependent quantities are compared with tolerances, acceptance
  decisions exactly. Regenerating it is deliberate and must be explained here.

## Nested designs

- Adds reliability, mixed fixed/nested weighting, and decision-study regression
  tests for `p x (i:h)` and for `p x (i:h) x r` with a fixed facet, with every
  expected coefficient written out from the published formulas rather than
  produced by the code under test. Nested designs were previously exercised only
  at the specification level: no nested model was fitted, and no nested
  reliability or decision study was computed.
- `help("gt_design")`, `help("gt_reliability")` and `help("gt_dstudy")` now
  define *balanced coded panel* explicitly, with a worked contrast between
  globally unique child labels and within-parent codes.

## Optimizer retrying

- Replaces transcript-parsing retry accounting with a retry controller that
  drives the optimizer directly, in `R/gaussian_retry.R`. Every attempt now
  records a real optimizer status; previously a trial run inside OpenMx's own
  retry loop could be recorded with an unknown status, and a change in OpenMx's
  message wording could fail an otherwise valid fit.
- `fit$retry_attempts` gains `start_type` (replacing `start`) and
  `optimizer_success`, and drops the transcript-specific `native_attempt`,
  `invocation`, `continuation_reason` and `native_returned_fit` columns.
  `attempt`, `optimizer`, `status`, `minus2loglik`, `external_accepted`,
  `external_rejection_reason`, `error` and `returned_fit` are unchanged.
  `fit$retry_settings$native_invocations` becomes `optimizer_runs`.
- The retry policy itself is unchanged: at most `extra_tries + 1` runs, each
  unsuccessful run followed by OpenMx's own bounded uniform perturbation of the
  best model so far, stopping at the first externally accepted run.

## Standard methods

- Adds `logLik()`, `nobs()` and `coef()` methods for `gt_fit`, and a print
  method for `gt_diagnostics()`, which now returns a classed object.
- `AIC()` and `BIC()` reproduce the fit's own recorded conventions: an ML fit's
  `ml_AIC` and `ml_BIC_response_vectors`, a REML fit's
  `reml_AIC_variance_parameters`. A REML `logLik` carries `REML = TRUE`; a
  discrete one is labelled as a first-order Laplace approximation.
- Adds `gt_component_vcov()` for the sampling covariance of the estimated source
  covariances, which is what `gt_reliability()` propagates into an interval.
- `vcov()` on a fit raises an error rather than returning that matrix. In R,
  `vcov(fit)` is the covariance of `coef(fit)`, and generic tooling relies on
  the pairing; this package does not estimate it, because Gaussian outcome means
  are profiled out of the likelihood and the discrete engine computes no
  observed information. The error names the reason and points at
  `gt_component_vcov()`.

## Controls

- `gt_control()` gains `retain`, choosing which optional components a fit keeps:
  `data`, `model`, `retry_log` and `session`. Every default is `TRUE`, so an
  existing call is unaffected. Dropping all four reduced a 600-row Gaussian fit
  from 525 KB to 64 KB with every reported result identical, including
  reliability, decision studies, diagnostics, correlations and the component
  covariance.
- Every fit now records a compact `panel` summary, so reliability and decision
  studies remain available when the modelled data was not kept. Where the data
  is kept it is still what the balanced-panel rules are checked against, so a
  panel edited after fitting is still caught.
- The discrete engine gains `max_dense_bytes` (default 512 MiB), checked before
  allocation. The other discrete limits bound counts; this bounds the dense
  algebra those counts imply, which is what protects a caller who raises them.
  The refusal names the estimate, the limit, the observation count, the random
  dimension, the size of the random-design matrix, and the alternatives. It does
  not bind for any model the existing count limits already allow.

## Release and repository

- `artifacts/manifest.json` declares `release_state`, and the marked README and
  NEWS blocks declare it too. Publication is now checked against git: a
  `published` claim requires the version tag, and a `prepared` claim fails once
  that tag exists. Nothing calls a bundle published before it is.
- Adds `scripts/prepare_release.py`, which derives every version from
  DESCRIPTION, validates, builds the archive and manual, writes the manifest,
  rewrites the release blocks, verifies the result, and stops. It never tags,
  pushes, uploads or submits.
- `scripts/check_public_contents.py` no longer hard-codes the version: the
  package name comes from DESCRIPTION and the bundle version from the manifest,
  which is what lets a development checkout retain the preceding bundle.
- Adds `docs/REPOSITORY_POLICY.md` with the required branch-protection state,
  `docs/branch-protection.json` as the exact payload, and
  `scripts/check_branch_protection.py` to verify it. The declared branch
  protection was applied to `main` after the release was published.
- Adds `SECURITY.md` and `CODEOWNERS`.
- The reference manual build falls back to plain `R CMD Rd2pdf` when R's
  generated LaTeX is not the layout its customized cover knows how to reflow,
  and reports which route it took and whether the overfull-box gate could run.
  The manual gate now requires both `pdflatex` and `makeindex` before claiming
  it can run, and names the missing tool when it skips.
- The renv bootstrap is described by `scripts/dependency-locks/renv-bootstrap.json`,
  verified by SHA-256 before installation, and preferentially taken from a cache
  that both locked workflows now keep. Pinning a version says which renv is
  used; the digest and the cache are what make retrieving it checkable and
  possible.

## Fixes

- `plot()` on a decision study now reports an invalid `coefficient` instead of
  failing on a zero-length condition.
- `gt_preflight()` and `gt_fit()` now share one definition of the covariance and
  residual rules, so a request one accepts is a request the other accepts.
  Previously preflight admitted a `Residual` covariance override that fitting
  refused, and fitting completed abbreviated residual names that preflight
  rejected. Both now refuse both, with the same message.
- A local variable named `T` in the discrete engine no longer shadows the `TRUE`
  alias.
- Four overfull boxes introduced by the new help pages are fixed in the Rd
  content rather than by relaxing the gate that found them, and the locked
  workflow now preserves the manual's LaTeX log and rendered PDF as build
  evidence: the log is the only place that says which box overflowed.
- The renv bootstrap digest is recorded and enforced. It was computed from an
  independent download of the pinned URL and matches the digest the locked
  workflow computed; a mismatch now refuses to install.
- During release preparation, the install instructions pointed to the local
  prepared bundle. The development notes above record their subsequent update
  to the published GitHub release.
- `docs/LIMITATIONS.md` collects every limitation in one place; the other
  documents link to it. `docs/ROADMAP.md` records planned work.
  `docs/DEVELOPMENT_STATUS.md` now holds only the current state.

## Release scope

The capability this release ships, unchanged from the earlier candidate.

- Consolidates the reviewed development API for univariate and multivariate
  Gaussian models and small binary, ordinal, and unordered categorical models.
  Designs support explicit crossed/nested random sources, selected item
  interactions, and source-specific covariance. The numerical engines and
  fitting limits are unchanged from 0.0.7.
- Retains exact balanced Gaussian ML/REML, Gaussian variance standard errors
  and coefficient intervals, supported fixed-facet reliability, and balanced
  decision studies. Discrete likelihood uses first-order Laplace integration
  with Gaussian random effects; binary/ordinal coefficients require the latent
  scale, and discrete uncertainty intervals are not implemented.
- Includes the three public LLM annotation panels and an executable real-data
  and failure tutorial explaining native outcomes, model choices, numerical
  diagnostics, and full-panel discrete fitting limits.

## Reproducible statistical pilots

- Adds protocols, seeds, source fingerprints, environment records, all
  attempted replicates, and summaries outside the installable package.
- Records 320 Gaussian fits across four univariate settings and ML/REML, with
  40 replicates per setting/estimator. Observed coefficient coverage was
  90--100%, with wide Monte Carlo intervals; these pilots do not establish a
  general coverage guarantee or validate boundary-conditioned inference.
- Records 180 fixed-parameter discrete panels across binary and ordinal
  logit/probit and nominal softmax models. Independently integrated references
  converged under refinement; 165 package comparisons were available and 15
  were unavailable because a declared category was absent. Nonzero Laplace
  errors are retained rather than treated as software-test failures.
- Records 40 binary recovery fits across four settings. All were numerically
  accepted, but short panels produced variable variance estimates and boundary
  solutions. Numerical acceptance does not establish accurate recovery.
- These results were generated against the recorded 0.0.7 source. Their
  original provenance remains unchanged; the 0.1.0 release does not imply a
  new simulation campaign or expanded statistical operating range.

## Release and validation infrastructure

- Corrects release-version prose and checks DESCRIPTION, the archive manifest,
  release summaries, and optionally the release tag for consistency.
- Covers all pull-request and main-branch changes in CRAN candidate readiness,
  pins external Actions to verified commits, and cancels superseded runs.
- Makes compatibility checks retrieve the recorded release source history
  needed to verify committed artifacts.
- Adds a documentation dependency lock and drift checks while preserving the
  numerical dependency versions. The locked workflow restores both stacks;
  current-R candidate checks retain their separate environment.
- Clarifies parameter uncertainty versus new-panel prediction, fixed-facet
  choices, and what temperature-specific agreement can establish.
- Adds contribution, release, and statistical-validation scope guidance.

The version change does not add sparse fitting, unbalanced Gaussian estimation
or reliability, cost-aware planning, bootstrap/jackknife, or discrete intervals.
GitHub publication and package checks are separate from CRAN submission and
acceptance.

# Gtheory4LLM 0.0.7

## Fixes found in review of this release

- The `variance` covariance coordinates, which `auto` now selects for every
  univariate or diagonal discrete model, treated any negative coordinate as an
  error. A bounded optimizer evaluates a few ulps outside a bound while
  projecting onto it, so a coordinate of -3.4e-17 recorded an attempt error,
  set `computation_failed`, and rejected the entire fit. Zero is this
  parameterization's natural domain boundary, so rounding noise is now
  projected onto it; a coordinate meaningfully below zero still stops. This
  rejected fits whose estimates were already correct, including the ordinal fit
  in `examples/standalone_usage.R`.
- The same rounding noise could also appear in the parameter vector a bounded
  optimizer returns, not only in the points it evaluates. A converged result
  reported a few ulps outside its bound was discarded as "no usable finite
  result", which failed the fit. Returned parameters are now projected onto
  their bounds with a tolerance that scales with each bound's own magnitude, so
  a point meaningfully outside is still refused.
- A source variance resting on the boundary now reports `NA` rather than a
  number whenever the joint Hessian happened to stay invertible, matching what
  it already reported when the Hessian did not. No symmetric interval follows
  from curvature at a boundary. The full entry covariance matrix is unchanged
  in `$uncertainty`, and coefficient intervals still use it.
- The interval caveat names at most three sources inline and otherwise gives a
  count and a pointer; on the bundled panels it listed all thirteen.
- Adding a vignette made `R CMD build` write `build/vignette.rds` and
  `inst/doc/` products into the archive, which no release gate expected. The
  public-content audit rejected the build index as an unexpected build file and
  then as a malformed example resource; the committed-artifact gate would have
  reported every generated vignette product as content missing from git at the
  next release. Both now account for them, and `inst/doc/` products are derived
  from the vignettes declared in the source commit rather than excused by
  prefix, so an unexpected file there still fails.
- When knitr, rmarkdown, or pandoc is absent, `R CMD check` failed the whole
  package on `Packages suggested but not available`, reporting a missing
  documentation toolchain as a package defect. The gate now checks with
  `_R_CHECK_FORCE_SUGGESTS_=false` in exactly that case, and accepts the single
  extra `--as-cran` line about a missing vignette index only when vignettes
  were genuinely skipped, so it can never excuse a real one.
- The locked Linux environment could not build rmarkdown because `fs` needs
  libuv headers, and `install.packages()` only warns when a build fails, so the
  step passed while the toolchain was absent. The workflow installs `libuv1-dev`
  and the step now asserts the result instead of reporting success either way.
- Clarifies that `fixed = "temp"` selects a reliability estimand after fitting;
  it does not alter the fitted variance model. A within-temperature analysis is
  one conditional sensitivity analysis when pooling is questionable.

## Uncertainty for Gaussian fits

- Reports asymptotic Wald standard errors for every Gaussian source variance.
  The engine already computed the restricted- or profile-likelihood Hessian for
  its diagnostics and discarded the result; it now forms the parameter
  covariance matrix `2 * H^-1` and keeps it. Reconstructed values match OpenMx's
  own standard errors to machine precision and match the classical mean-square
  formulas for a crossed two-way design to five significant figures.
- Adds delta-method standard errors and logit-scale intervals for G and Phi in
  `gt_reliability()` and `gt_dstudy()`, per outcome and for weighted composites.
  New `level` argument; new `Erho2_se`, `Erho2_lower`, `Erho2_upper`, `Phi_se`,
  `Phi_lower`, and `Phi_upper` columns. `plot.gt_dstudy()` draws the bounds.
  Deterministic tests check the delta-method mapping. A previously reported
  pilot coverage range has no reproducible protocol/results in the public
  repository and does not define a validated operating range.
- A zero-boundary variance can accompany unusable joint Hessian curvature,
  which previously removed every standard error. Standard errors are now computed on
  the interior block, conditional on the zero components being held at zero, and
  both the fit and the printed coefficients say so. A component held that way
  reports `NA`, never a structural zero that would read as certainty.
- Standard errors are unavailable, with a stated reason, when `check_hessian` is
  disabled or the curvature is unusable. The discrete Laplace engine computes no
  observed information and says so rather than leaving the field empty.

## Mixed-model fixed facets

- Adds `fixed` to `gt_reliability()` and `gt_dstudy()`, implementing the mixed
  model of Brennan (2001): the object-by-fixed-facet variance is averaged over
  that facet's levels and joins universe-score variance, a source built only
  from fixed facets shifts every object equally and leaves the model, and every
  other source keeps its usual divisor. With no fixed facet the decomposition is
  unchanged. `$source_roles` records the role each source took.
- A fixed facet's count cannot be changed and a decision study cannot project
  over it, because its universe is exactly its observed levels. Declaring every
  facet fixed is refused: that design has no estimable error variance.

## Designs and documentation

- Adds `full_cell` to `gt_design()`. `full_cell = FALSE` removes exactly the
  object-by-all-facets source and leaves every other requested source
  unchanged, which is how a binary or ordinal study with one observation per
  cell declares the default crossed design. The discrete rejection message now
  names that argument. The source is still never dropped automatically.
- Converts the installed tutorial into a real knitr vignette, so
  `browseVignettes("Gtheory4LLM")` finds it. `system.file("doc",
  "LLM-workflow.R")` and the installed HTML keep working.
- Makes `man/*.Rd` and `NAMESPACE` the only documentation source of truth. The R
  files previously carried roxygen blocks that were not the source of the richer
  hand-written Rd pages; running roxygen2 would have replaced them and dropped
  the S3 methods registered in `NAMESPACE`. Those blocks are now plain comments.
- Documents temperature and seed as study-design choices. Observed agreement
  differences across temperatures motivate diagnostics but do not by themselves
  prove heterogeneity of latent random-effect variances.
- States that the native discrete codings of the bundled panels exceed the dense
  discrete engine by more than an order of magnitude, and explains why the
  declared `R (>= 4.5.0)` floor comes from OpenMx's under-declared C API
  requirement rather than from this package's own code.
- Repairs two tests left inconsistent by the `covariance_parameterization`
  default change, and adds installed-package regression tests for standard
  errors, the delta-method mapping, coefficient intervals, mixed-model fixed
  facets, and `full_cell`.
- Stops the public-content audit from failing a working-tree scan on operating
  system metadata such as `.DS_Store`, which git already ignores and a desktop
  environment recreates. The exemption is by exact filename, is reported under
  `skipped_os_metadata`, and never applies inside an archive.
- The package build now knits the vignette, so `scripts/check_package.py` needs
  knitr, rmarkdown, and pandoc. When they are absent it records that, builds
  with `--no-build-vignettes`, checks with `--ignore-vignettes`, and the
  installed-tutorial stage prints `NOT RUN` rather than passing silently. The
  three workflows install the toolchain.

## Smaller interface and reporting changes

- Adds concise reliability and decision-study print methods while preserving
  complete results and diagnostics; resets coefficient row names.
- Adds `counts` to `gt_reliability()` with the existing `design` argument retained
  as a compatibility alias.
- Labels and retains Gaussian derivative-pass warnings separately from optimizer
  acceptance, and removes stale pre-fit validation notes after preparation.
- Improves unsupported full-cell and balanced/nested design guidance without
  changing the requested statistical model.
- Defaults discrete covariance coordinates to `auto`: direct variances for
  univariate/diagonal models and log-Cholesky for joint unstructured models.
  Explicit choices and numerical acceptance criteria remain available.
- Corrects the public package citation and explains full-panel discrete limits,
  mental-health preprocessing, and coefficient interpretation more directly.
- The 0.0.7 source archive and reference manual remain available in the
  [v0.0.7 GitHub release](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.0.7).

# Gtheory4LLM 0.0.6

- Prepares the package for its first public distribution under GPL-3.
- Bundles eight outcome sets and fifteen codings of three real, publicly
  archived LLM annotation panels. Preserves public-source checksums, CC BY 4.0
  data attribution, response mappings, and the three dataset reference chapters.
  Rebuilding modeling resources accepts explicitly supplied public-source CSVs;
  verification requires no external files or network access.
- Adds `gt_preflight()` to report resolved sources, covariance and random-effect
  dimensions, replication/completeness, resource limits, and supported scales.
- Adds an installed synthetic LLM tutorial completing fitting, diagnostics,
  G/Phi calculation, and an 18-allocation decision study.
- Makes installed example loading independent of ambient workspace variables;
  intentional directory overrides support RDS resources and source CSV files.
- Adds a concise classed fit summary and shared diagnostic fields for selected
  attempts, rejection reasons, natural covariance boundaries, and artificial
  parameter bounds. Existing estimates and numerical acceptance rules are
  unchanged.
- Preserves explicit starting values, fixed optimizer selection across fitting
  attempts, reproducible retry controls, and failed-fit safeguards.
- Requires R 4.5 or later because the supported OpenMx dependency uses an R 4.5 API.
- Adds minimum-R and Windows/macOS compatibility workflows beside the locked
  Linux numerical checks, plus one source-and-artifact release-check entrypoint.

Scope at 0.0.6 was exact balanced Gaussian likelihood and small-model
first-order Laplace discrete likelihood. Discrete latent random effects remain
Gaussian. Binary/ordinal reliability requires an explicit latent scale;
unordered categorical scalar reliability, observed-score discrete reliability,
joint Gaussian-discrete fitting, bootstrap/jackknife, and uncertainty intervals
of any kind were not implemented in that release. (The development version adds
asymptotic Wald standard errors and delta-method coefficient intervals for
Gaussian fits only; see above.) Numerical tests do not establish parameter
recovery, approximation adequacy, or application-wide statistical validity.
