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
- Corrects the temperature guidance. Declaring `fixed = "temp"` fixes the
  estimand but not the misspecification: the G study has already pooled one
  seed variance across all six temperatures before any coefficient is formed.
  Only fitting within a single temperature removes that, and a study affected
  by both should do both.

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
  Simulated coverage of the G interval was 0.94-0.96 across three crossed
  two-facet designs; this is a limited check, not general coverage evidence.
- When a variance component rests on zero the joint Hessian is indefinite, which
  previously removed every standard error. Standard errors are now computed on
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
- Documents that temperature is a chosen setting rather than a sampled level,
  and that seed agreement in the bundled panels falls monotonically with
  temperature (0.92 to 0.73 for hate speech, 0.91 to 0.68 for mental health,
  0.84 to 0.58 for drug reviews), so one seed variance pooled across all six
  temperatures is misspecified.
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
- The previously submitted 0.0.6 archive and its reference manual are unchanged;
  `artifacts/` still describes that frozen release, not this version.

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
