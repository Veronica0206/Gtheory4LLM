# Development status

Version history is in [NEWS](../NEWS.md); implementation boundaries are in
[limitations](LIMITATIONS.md). Historical checkpoints below retain their original
evidence and time-dependent statements. The delivered 0.6.0 release is identified
below; its earlier gates remain in [the detailed qualification record](#detailed-060-qualification-record).

## Delivered 0.6.0 GitHub release

[v0.6.0](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.6.0)
was published on 2026-10-21 at 23:04:27 UTC. The release is immutable. Public
downloads of its archive, reference manual and manifest matched the committed
bundle, and GitHub's signed release and three asset attestations verified.
The tag remains `6961e7bc37f0a73f1b544ef127f811cf166dad12`; the archive remains
the checked build from `352468d11ee7d09d7b0fba3e97cdf167dd6a75e7`.
No 0.6.0 CRAN submission is recorded. The 0.6.1 corrections and subsequent
1.0 development changes are separate source revisions, absent from that archive.

## 1.0.0.9000 local development

The development checkout adds public dense/sparse categorical fitting, eligible
equal fixed-call effects, optional full observed information, and a bounded
univariate observed-row Gaussian route through lme4. It also adds shared
categorical simulation, explicitly named observed-score, category-vector and
decision-agreement targets, cost screening for those targets, and binary/ordinal
pilot precision planning. A separate categorical point-estimator pilot route
includes nominal outcomes and eligible fixed calls, with all-attempt
availability and conditional error summaries. The formula interface is retained. The help pages
define each target, its guards and its unsupported combinations. Two repairs
from the 2026-10-23 review are integrated: the sparse memory guard now judges a
declared budget against the design's structural pattern (the exact structural
nonzero count, then one factorization of the pattern) instead of a dense square, which is what
kept the joint native panels unfittable at their declared 8 GiB budget (dense squares of 32 and
73 GiB); and the exact Gaussian
engine recovers once, after an ordinary refusal of a multivariate unstructured
model, from a bounded square-root search on the same deviance, which is what
the six-flag mental-health panel needed. Neither changes an acceptance rule or
an accepted primary attempt. The analytic Laplace gradient is integrated with its
tests: the compiled selected inverse, the response third derivatives, the
fixed-point assembler on the structural envelope, and an opt-in optimizer route
(`gradient = "analytic"`) for sparse L-BFGS-B fits in natural Cholesky or
log-Cholesky coordinates, whose observed information differences the analytic
gradient. The default fit is unchanged; the route's qualification so far is
recorded below.

## Analytic gradient qualification, 2026-10-25

The route's checks against the plan of 2026-10-24, through installed archives
of the merged units, on one core.

| Step | Scope | Result |
|---|---|---|
| Unit tests | Fixed-point gradient against finite differences on thirteen fixtures; the route on the discrete characterization panels and a joint panel; gradient-difference information against second differences | Pass on macOS and in the offline Linux container (R 4.5.2); full source gate and `R CMD check --as-cran` with only the development-version NOTE |
| Q1, fixed points on the native panels | Drug-review ordinal (four points) and mental-health binary (three points), four declared directions, two steps, criterion `3e-4 + 3e-7 * abs(g)` | 56/56 comparisons pass on macOS and on Linux; the two platforms' gradients agree within 1e-11 although long double is 53-bit on Apple Silicon macOS and 113-bit on aarch64 Linux |
| Q2, the T3 drug-review trial | 1,200 rows, four probit-ordinal outcomes, six sources, 68 parameters, automatic start, one alternative start, 600 iterations per attempt, `optimizer_scaling = "start"`, information off | Not accepted, as on 2026-10-23: every attempt reached the iteration cap still descending, the largest stationarity scores are on interior sources (item, item by evaluator, item by prompt), and evaluator, prompt and evaluator by prompt are singular with nonzero projected scores. The gradient itself was clean: 2,662 gradients, none refused, and agreement with the finite-difference fixed-effect score within 4e-9 at the selected point |
| Q3, the decision | Read with Q4 | Decided 2026-10-25. Version 1.0.0 qualifies the two reduced joint outcome sets of Q4, with all ten sources, as the whole-data joint categorical illustrations: the efficacy and safety aspects of `drug_review_4aspect` (the two best-balanced aspects; cost is neutral in 95.7% of rows) and `mental_health_3group`. Whole-data fits of all four drug-review aspects and of the six mental-health flags are not required for 1.0.0 and are listed in the roadmap |
| Q4, whole-data fits | All 21,600 rows, the requests' models and controls with the analytic route, observed information on and 2,000 iterations per attempt; macOS, one core | `drug_review_efficacy_safety` (the efficacy and safety aspects, two ordinal outcomes, 34 parameters) and `mental_health_3group` (three binary outcomes, 63 parameters) were refused on stationarity alone: every interior source passed, and two singular call-level sources (evaluator by prompt by temperature, and its seed source) had inward covariance scores. With `boundary_escape = "projected"` both are numerically accepted. Each start escaped in one round, the restarts agree within 1.6e-7 and 8.0e-11, and the deviances are 25904.024 and 30383.853, against 25911.346 and 30385.231 refused. Observed information is unavailable, because other sources are legitimately at zero. The four-aspect `drug_review_ordinal` fit, run without the escape, was stopped at iteration 240 of its first attempt (about 16 s per iteration); the six-flag `mental_health_binary` fit has not been run |
| Q5, cross-platform | The two accepted fits repeated from the gate's archive of the same commit in the offline Linux container (aarch64, R 4.5.2) | Running since 2026-10-25 |


Focused synthetic reference tests and refusal tests accompany the new routes;
they do not qualify a full native panel, establish Laplace accuracy or calibrate
interval coverage. Default categorical row, dimension and parameter caps remain
unchanged. The incomplete Gaussian route is univariate and projects to an
explicit intended balanced allocation; it does not infer reliability of the
observed irregular allocation. Nominal outcomes have latent G/Phi as the mean
and range of the generalized eigenvalues over their category contrasts, with a
category-exchangeable or unstructured source covariances; an arbitrary numeric-score ratio is not
supported.

This is continued local development, not a 1.0 publication or final-archive
qualification. Qualification gaps are listed under current priorities below.
The historical checkpoints that follow retain their original source, archive,
platform and run identities; their passing results do not apply to this
development checkout.

## Statistical qualification record, 2026-10-23

The local qualification campaign (`Development/1.0/qualification-20261022T211319Z`,
candidate-v1 source for the statistical studies, candidate-v6 archive for the
native fits; final tables in
`statistical-campaigns/analysis/final-current-qualification-tables/`, created
2026-10-23 07:57 UTC) completed every planned primary panel. These are its
dispositions, with attempted / accepted / interval-available / covered counts;
coverage is conditional on an available interval and the all-attempt yield is
reported beside it. They qualify the declared fixtures only.

| Scenario (2,000 panels each unless noted) | Accepted | Intervals | Covered | Conditional coverage | Covering yield |
|---|---:|---:|---:|---:|---:|
| Binary logit, interior, pilot / larger | 1,980 / 1,994 | 1,875 / 1,994 | 1,838 / 1,902 | 0.980 / 0.954 | 0.919 / 0.951 |
| Binary probit, interior, pilot / larger | 1,987 / 1,916 | 1,984 / 1,916 | 1,977 / 1,842 | 0.996 / 0.961 | 0.989 / 0.921 |
| Ordinal probit, interior, pilot / larger | 2,000 / 2,000 | 1,998 / 2,000 | 1,975 / 1,883 | 0.988 / 0.942 | 0.988 / 0.942 |
| Ordinal logit, interior, pilot / larger | 1,999 / 1,997 | 1,921 / 1,997 | 1,880 / 1,892 | 0.979 / 0.947 | 0.940 / 0.946 |
| Nominal exchangeable, mean G / Phi (500) | 499 | 493 | 468 / 467 | 0.949 / 0.947 | 0.936 / 0.934 |
| Nominal unstructured, mean G / Phi (500) | 467 | 211 | 210 / 209 | 0.995 / 0.991 | 0.420 / 0.418 |
| Joint binary + ordinal, outcomes y, z and composite (500) | 496 | 435 | 414, 405, 417 (G) | 0.952, 0.931, 0.959 | 0.828, 0.810, 0.834 |
| Joint binary + nominal, outcomes y, z (500) | 470 | 125 | 120, 124 (G) | 0.960, 0.992 | 0.240, 0.248 |
| Near-boundary cells (binary/ordinal, both links; 500 each) | 427–499 | 216–345 (availability 0.43–0.69) | 143–304 | 0.66–0.88 | 0.29–0.61 |
| Exact-boundary cells (true variance zero; 500 each) | 400–500 | 192–227 | 0 | 0.00 | 0.00 |
| Categorical call covariance, binary / ordinal / nominal (300 each) | 300 / 300 / 300 | information 262 / 276 / 201 | — | covariance recovery only | — |
| Observed-row Gaussian projections, MCAR and design-dependent deletion (500 each) | 500 | point projections only | — | — | — |

Reading: interior latent coefficients are covered close to nominally when an
interval exists; small-panel Wald intervals are conservative; near a boundary
roughly half the panels have no interval and the rest cover 66–88 %; at a true
zero no available logit-Wald interval covers; crossed nominal-unstructured and
joint binary–nominal models withhold most intervals. The weak-signal
observed-score Monte Carlo targets failed their prespecified availability and
error-calibration criteria (availability 58.6 % and 67.8 % at the two budgets,
upward selection bias among available estimates;
`statistical-campaigns/analysis/candidate-v1-mc-weak-signal/REPORT.md`). The
full 21,600-row hate-speech ordinal probit fit (ten sources, 9,507 random
effects, sparse engine, log-Cholesky coordinates) was accepted with information
on macOS and Linux from the same candidate-v6 archive and passed its 19
prespecified comparisons (latent G 0.9588 [0.9421, 0.9707], Phi 0.9545
[0.9349, 0.9684]); this qualifies that model only. The joint binary and joint
ordinal native panels were refused by the former memory guard, and the six-flag
Gaussian panel was accepted only from an externally supplied start; both
findings are addressed in this source and await their own prospective runs.

## 0.6.1 corrections

Source version 0.6.1 carries four corrections to the 0.6.0 interface release
found in an independent review: the lme4 restart must itself complete without
a convergence warning, `gt_laplace_check()` reads retained responses as the
engine's encoding, alternative-start discrete solutions keep their parameter
names, and the Laplace check refuses a comparison whose workspace estimate
exceeds the dense budget. No engine, tolerance or estimate changes; the 0.6.0
qualification records below apply to the 0.6.0 archive and are not rerun here.

## Historical 0.6.0 qualification checkpoint

Qualification checkpoint: 2026-10-20 21:00 America/New_York
(2026-10-21 01:00 UTC). Pending items describe that checkpoint; subsequent
publication needs separate tag and delivery evidence. [PR #75](https://github.com/Veronica0206/Gtheory4LLM/pull/75)
was integrated by protected fast-forward at
`352468d11ee7d09d7b0fba3e97cdf167dd6a75e7`; no protection setting was relaxed.
The prepared bundle adopts the integrated source's checked archive unchanged:
`Gtheory4LLM_0.6.0.tar.gz`, 570,725 bytes, SHA-256
`d9a592b7b40b73dab9b6d051b4abbe2eff5cf54b1a22d15c58c7ec1d46aef5bd`.
The [manifest](../artifacts/manifest.json) is the bundle identity; its state
alone does not establish delivered assets or CRAN submission.

- [Ordinary R-devel](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861542):
  selected archive, `--as-cran`, **0 errors, 0 warnings, 0 notes**, PDF manual
  checked, all **33 packaged tests** passed. The same archive's noLD check
  also reported **0 errors, 0 warnings, 0 notes**, with the PDF manual and
  all 33 tests; its separate installed-test loop passed **33/33**. Reference
  BLAS/LAPACK probes passed **80/80 at each** of setup, loaded dependencies,
  and final stages. The independent evidence audit confirmed identical source,
  size, and hash records and fingerprinted 368 retained files.
- [Main full validation](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861801):
  **32/32 stages**. [Main compatibility](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861768):
  **20/20 stages each** on Windows, macOS, and minimum-R Ubuntu.
- Local locked validation: **32/32 stages**, including selected-archive
  installation/smoke. Its separately rebuilt source check reported **0 errors,
  0 warnings, 0 notes**. Local remote incoming and external-clock checks were
  disabled; hosted ordinary R-devel supplies remote incoming evidence. The
  separate 66-page manual passed its overfull gate and visual review.

Pending at this checkpoint: qualify and integrate bundle/publication metadata;
finish sequential manuscript reproduction from the
selected bytes and PDF review; verify immutable GitHub delivery. CRAN submission
is a separate maintainer action and is not established by these records. The
previous PR's synthetic-merge archive and earlier manuscript archives remain
historical evidence, not substitutes for the selected archive's checks.

Companion analyses use the qualified 0.6.0 archive. Future sparse
categorical estimation, uncertainty, incomplete panels, observed/decision/vector
targets, categorical calls, and planning require a separate development line,
explicit statistical contracts, and qualification before each release. No new
capability or 1.0.0 commitment is asserted here.

## Detailed 0.6.0 qualification record

Qualification checkpoint: 2026-10-20 21:00 America/New_York
(2026-10-21 01:00 UTC). The selected bundle was prepared at this checkpoint.
Pending items below describe that time; later publication requires separate
tag, manifest, and delivery evidence. This document does not establish CRAN
submission. The integrated source is
`352468d11ee7d09d7b0fba3e97cdf167dd6a75e7`, preserved through the protected
fast-forward of [PR #75](https://github.com/Veronica0206/Gtheory4LLM/pull/75).
Branch protection was not relaxed.

### Scope

The Model Interface release adds formula-based fitting and preflight with an
explicit object of measurement, consistent fit classes and model methods,
an independently checked lme4 Gaussian engine, and `gt_laplace_check()` for
fixed-parameter approximation comparisons. Its refinements add the defensive importance mixture and improve
source/boundary diagnostic mapping, documentation, and runnable examples. The public workflow leads with the formula where
the design grammar supports it; explicit design declarations remain available.
See [NEWS](../NEWS.md) and [limitations](LIMITATIONS.md).

Public sparse categorical fitting, categorical intervals, new categorical
observed-score, decision and vector targets, incomplete-panel inference,
categorical call effects, and expanded planning are future work. This release does not claim those capabilities or
eliminate platform-sensitive numerical acceptance decisions. Companion analyses use the qualified 0.6.0 archive; later development requires
separate qualification.

### Selected bundle

The archive was built with R 4.6.1 and adopted unchanged from the integrated
source's checked candidate. Publication metadata must not rebuild it.

| File | Bytes | SHA-256 |
|---|---:|---|
| `Gtheory4LLM_0.6.0.tar.gz` | 570,725 | `d9a592b7b40b73dab9b6d051b4abbe2eff5cf54b1a22d15c58c7ec1d46aef5bd` |
| `Gtheory4LLM-manual.pdf` | 351,150 | `43d10fb565787bd1e985f11db341e554681b3b0e3a7eac417e4bfa18b0dc2cb9` |

The separately built reference manual has 66 pages; its overfull-box gate and
visual review passed. The [manifest](../artifacts/manifest.json) records the
selected source, artifact identities, preparation/publication state, and
checked-candidate provenance. The ordinary check report's SHA-256 is
`7eebb80746c0daaec681cd4207c5d1fb81801f1c059d508f2b7f8b08da0846d2`.

### Completed qualification

- [Integrated-source candidate run](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861542):
  ordinary Linux R-devel 4.7.0 (2026-10-18 r90707), `R CMD check --as-cran`,
  **0 errors, 0 warnings, 0 notes** for the selected archive, including the
  PDF manual and all **33 packaged tests**.
- The same candidate run's Linux x86-64 noLD job, R-devel (2026-10-03 r90638)
  on AMD EPYC 7763 with long-double support verified absent, checked the
  **same archive bytes** using `R CMD check --no-stop-on-test-error`:
  **0 errors, 0 warnings, 0 notes**, PDF manual and all **33 packaged tests**.
  The separate installed-test loop passed **33/33**. Reference BLAS/LAPACK
  probes at setup, after loading numerical dependencies, and after all tests
  each completed **80 native solves with 0 invalid**. An independent audit
  matched the ordinary/noLD source, size and hash records and fingerprinted
  all **368 downloaded evidence files**. Native probes were audited from
  retained records; the evidence audit did not rerun numerical operations.
- [Integrated-source full validation](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861801):
  **32/32 stages**, locked scope `all`, including independent OpenMx, lme4 and
  ordinal comparisons and a staged-bundle artifact check.
- [Integrated-source compatibility](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861768):
  **20/20 stages on each** of Windows/R release, macOS/R release, and
  Ubuntu 22.04/R 4.5.0. These source checks are not checks of one identical
  archive across those platforms.
- Local macOS arm64, R 4.5.3: full locked validation against the selected
  staged manifest passed **32/32 stages**, including source checks, the manual
  gate, and a fresh-library install/smoke of the selected archive. Its source
  package check rebuilt a local archive and reported **0 errors, 0 warnings,
  0 notes** under `--no-manual --as-cran`; the manual was checked separately.
  Local remote incoming lookups (`_R_CHECK_CRAN_INCOMING_REMOTE_=false`) and
  external system-clock checks (`_R_CHECK_SYSTEM_CLOCK_=false`) were disabled.
  Hosted ordinary R-devel supplies the selected archive's remote incoming
  check evidence. No external-clock verification is claimed.

The earlier [PR candidate run](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39511869200)
qualified synthetic merge `9f7ff6239bfd7a2f7958869ce97f50cf2dcb6a92`, including
noLD and 33/33 installed tests. Its 570,728-byte archive, SHA-256
`5aa05e122d467657908595a78fd277ad33f1d31b85bbcd20dc9bf673dfc11ae3`, is
historical PR evidence, not the selected release archive. Canceled duplicate
push checks were rerun successfully before the protected fast-forward.

### Gates still pending at this checkpoint

1. Integrate the reviewed bundle/publication metadata through its own required
   checks; verify the new tag and published manifest without moving the tag.
2. Complete sequential macOS/Linux manuscript reproduction from this selected
   archive, then review and synchronize the PDFs and records. Previous
   manuscript runs remain separately identified historical evidence.
3. Verify the complete draft's archive, manual and manifest bytes, publish, and
   verify immutable delivery and release attestations.

CRAN upload, maintainer confirmation, CRAN review, and CRAN acceptance are
separate from these steps. No 0.6.0 CRAN submission or current reverse-dependency
survey is established here. Historical release assets, tags, and records remain
unchanged; later results must identify their own exact commit and bytes.

## 0.6.0 interface and estimation scope

Source version 0.6.0 gives the interface the conventions of other R model
objects, integrated through PR #73 and PR #74 on 2026-10-17 and 2026-10-18.
`gt_fit()` and `gt_preflight()` accept a two-sided model formula with an
explicit object of measurement (`measured`), every fit has one class vector
per engine, `summary()` carries the Gaussian reliability at the fitted counts,
`deviance()`, `formula()` and `update()` are available, and every declaration
prints as a description. Two pieces of new estimation code arrive with their
own acceptance and availability rules: the lme4 Gaussian engine, accepted only
when lme4's optimizer completes without a convergence warning, the package's
stationarity check on lme4's deviance function passes, a restart from a
different point reproduces the solution, and the exact balanced deviance
agrees with lme4's criterion at the estimates (the published 0.6.0 archive
checks only that the restart reproduces the solution; the requirement that the
restart itself complete with optimizer code 0 and no convergence warning is the
0.6.1 correction recorded above); and `gt_laplace_check()`, which compares a discrete fit's Laplace
objective with a refined numerical estimate and reports when that estimate is
unavailable or unusable. The exact Gaussian fitting engine, the dense Laplace
fitting engine and their numerical acceptance rules are unchanged from 0.5.0.

Corrections following the initial 0.6.0 source freeze give the importance
comparison a 90% Laplace Gaussian / 10% prior mixture and evaluate the full
mixture density for every draw. The prior component bounds the importance
weights for categorical likelihoods, establishing finite weight moments;
finite-sample precision and empirical ESS remain diagnostics, not accuracy
guarantees. The [bounded refinement study](../validation-studies/laplace-refinement/README.md)
retains 80 fixed-parameter comparisons on one binary-logit fixture. It does not
establish general calibration or parameter recovery.

The lme4 path maps boundary flags through fitted grouping identities and exposes
an explicit parameter-to-source map while preserving engine order and boundary
indices. It returns estimated source covariance matrices, but does not compute
their sampling covariance or the resulting source-variance standard errors and
reliability intervals. The test map records the corresponding regressions.

Manuscript replays on macOS and Linux have demonstrated that optimizer paths,
near-threshold acceptance decisions and interval branches can differ across
numerical environments. The same documented gates must be checked against each
run's diagnostics; exact decisions from a previous environment are not a
universal replication target. Validation reports must identify the actual
archive, environment, command and check mode. In particular, an ordinary
`R CMD check` result does not establish a `--as-cran` result, and validation
of the initial freeze does not qualify later working-tree corrections.

## Historical 0.5.0 and earlier checkpoints

The following sections preserve the previous record. Statements such as
"current", "pending", "release state", and "development priorities" belong to
those checkpoints; the current 0.6.0 state is above. Their numerical results,
archive identities, limitations, and evidence links are retained. Historical
0.5.0 CRAN/status assertions have not been refreshed by this release audit.

### 0.5.0 Study Planning release preparation

Source version 0.5.0 contains the reviewed fixed-layout Gaussian batch targets,
cost-aware allocation planning and Gaussian pilot precision simulation. After
the initial freeze, independent review identified a false refusal of valid
batch fits whose distinct numeric item identifiers share a default printed
representation. The focused correction preserves typed item identity and
provides unambiguous keys for named target weights. Covariance estimation,
projection arithmetic and numerical acceptance rules are unchanged.

The initial candidate from `3b40219f3fec6e3ae672259e1baf8324b4b0bff8`
(531,305 bytes, SHA-256
`e71cbb295505908c2aca4a173839ab60ecb919584a94784082a92a8aa861d317`)
is superseded and retained as historical evidence. Its ordinary R-devel check
reported 0 errors, 0 warnings and the recent-update timing NOTE; its noLD check
passed with verified reference BLAS/LAPACK on AMD EPYC 7763. Those results do
not qualify the corrected source. The replacement candidate must pass its own
ordinary R-devel, noLD, compatibility and full staged-bundle gates before
publication. CRAN submission remains a separate maintainer action.

The preceding PR #69 development head
`776a50048b0fa489eed8f843154a229b123c01f0` passed all seven check contexts on
2026-10-09. The [full gate](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37949434330)
completed 32 stages and 186 Python tests with one platform-specific skip.
[Candidate readiness](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37949434420)
checked the same 531,403-byte development archive, SHA-256
`674784339d973daa432fdb63ad8e8f8ef591fb0f3996bb4f7b20453b18a14331`,
from synthetic merge `48b1b36034f58c94dfa2bd4bf7c8423e91797b46`.
Ordinary R-devel reported 0 errors, 0 warnings and 1 incoming NOTE; noLD with
verified reference BLAS/LAPACK reported 0 errors, 0 warnings and 0 notes.
Both checks completed all 30 package tests, both vignettes and the PDF manual;
the separate noLD installed-test loop passed 30/30. These are development
qualification results, not final-version release evidence.

The incoming-NOTE policy was not extended to 0.5.0. On 2026-10-11 UTC, once the
seven-day timing window after the 0.2.0 CRAN publication had passed, the
corrected candidate's ordinary R-devel job was rerun on the same built archive
and reported 0 errors, 0 warnings and 0 notes. PR #70 was then integrated into
`main` by fast-forward at `854e5e792b5dfcbacc88c2a32c0c9792b2d3772d`, and that
checked candidate was adopted unchanged as the 0.5.0 bundle recorded below.

### Release state

The 0.5.0 bundle uses the checked candidate without rebuilding the package.
The records below identify the selected bundle and the pre-publication
checkpoint on 2026-10-11; they do not assert later delivery or CRAN
acceptance. 0.4.1 was published as an immutable GitHub release on 2026-10-08
and was never submitted to CRAN; 0.5.0 carries its noLD test correction
together with the study-planning additions. 0.4.0 was tagged `v0.4.0` on
2026-10-06 but never published or submitted: the no-long-double check of that
tagged commit refused a discrete fit on one runner, and
`tests/package-characterization.R` could not report that as a platform outcome.

| Fact | Value |
|---|---|
| Checkout version | `0.6.0` (Model Interface release candidate). The development line after 0.5.0 was versioned `0.5.0.9000`; earlier development versions were `0.3.0.9000`, `0.4.0.9000` and `0.4.1.9000`; no 0.3.0 was released, `0.4.0` was tagged but not published, and `0.4.1` was published on GitHub only |
| Bundle in `artifacts/` | `0.5.0`, adopted unchanged from the checked candidate; the archive and manual identities are recorded below and in the manifest |
| Bundle source commit | `854e5e792b5dfcbacc88c2a32c0c9792b2d3772d` |
| Manifest publication state | Read `release_state` in [the manifest](../artifacts/manifest.json). `prepared` records staging; `published` records the publication commit/tag identity. Neither field alone proves a GitHub upload or CRAN submission |
| `v0.5.0` identity | The release-identity gate requires the tag to contain the published manifest and to preserve the candidate source in its ancestry. A tag alone does not establish asset delivery |
| GitHub delivery | Completion requires a non-draft, immutable [v0.5.0 release](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.5.0) with exactly the archive, manual and manifest, verified against the committed bytes. This document does not substitute for that delivery record |
| Historical releases | [v0.4.1](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.4.1) is immutable with three assets and was never submitted to CRAN. [v0.2.0](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.2.0) is immutable with three assets; its archive, manual, manifest and tag remain unchanged. `v0.4.0` identifies the withdrawn 0.4.0 publication-metadata commit and carries no release assets. `v0.1.0` identifies publication commit `2332d40`; that older release remains `immutable: false` |
| Repository protection checkpoint | On 2026-10-07, `main` required seven check contexts including noLD, and the authenticated policy verifier passed. Release-tag protection blocked updates and deletions of `v*` with no bypass actors. On 2026-10-11 PR #70 was integrated by fast-forward with all seven required checks green |
| CRAN checkpoint | On 2026-10-10, before any 0.5.0 submission, CRAN distributed `0.2.0`, published on 2026-10-04; its additional noLD check reported an ERROR in `tests/package-discrete-safety.R`, for which CRAN requested a correction before 2026-10-26. 0.4.1 was never submitted, so 0.5.0 is the submission that carries that correction. No reverse dependencies were found in the index of 25,366 packages. Submission receipt, maintainer confirmation and CRAN acceptance/publication are separate subsequent events |

The selected archive is `Gtheory4LLM_0.5.0.tar.gz`, 534,035 bytes, SHA-256
`10d501afc114335d6e5f1ddd4f933673726db50979b973549f1d1c893a873cc8`.
The selected `Gtheory4LLM-manual.pdf` is 320,150 bytes, SHA-256
`9660dbd7d11a083ef5b915391bb2d47b7dfab41b3eef16bb670c17a59607fc33`.
Publication metadata changes do not alter either file or the package source.

The checkout, bundle manifest, tag, GitHub release and CRAN submission are
separate states. `scripts/check_committed_artifact.py --check-release-identity`
checks the checkout/release version relationship, source ancestry and manifest
publication claims against the tag. The artifact check compares the archive
with its recorded source commit, not with later development changes.
README/NEWS source summaries link this excluded repository metadata so that
archives retain the same source prose before and after publication.

CRAN may distribute a repackaged file with its own checksum: a GitHub asset's
manifest hash does not identify CRAN's copy. The earlier `0.0.6` submission was
returned for two README links (`scripts/VALIDATION.md`, `LICENSE`) to files the
archive did not ship; that history is separate from the 0.2.0 noLD correction.

### Validation evidence

#### 0.5.0 selected archive

The [ordinary R-devel and noLD qualification run](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/38014263622)
built the selected archive with R 4.6.1 from
`854e5e792b5dfcbacc88c2a32c0c9792b2d3772d`, the head of `main` once
[PR #70](https://github.com/Veronica0206/Gtheory4LLM/pull/70) was integrated by
fast-forward, and checked those exact bytes twice.

- Ordinary Linux R-devel 4.7.0, 2026-10-09 r90655, completed `R CMD check --as-cran`
  with **0 errors, 0 warnings and 0 notes** on 2026-10-11 UTC. The first attempt
  of the same job on 2026-10-10 reported only "Days since last update: 6", which
  the 0.5.0 policy does not excuse; the job was rerun on the same built archive
  once that window had passed. All 30 package test files, examples, both
  vignettes and the PDF and HTML manuals passed.
- noLD R-devel, 2026-10-03 r90638, with long-double support verified absent, on
  an Intel Xeon Platinum 8370C runner with verified reference BLAS/LAPACK before,
  during and after the check, checked the same archive with **0 errors,
  0 warnings and 0 notes**: all 30 package test files, vignette rebuilds and the
  PDF manual passed, the separate installed-test loop completed 30/30 files, and
  the reference probes recorded 80 native solves with 0 invalid. On that runner
  the ordinal boundary diagnostic was refused by the stationarity and
  restart/tolerance stability safeguards, while the characterization baseline
  reproduced all ten canonical cases.

The two push-triggered workflows on the same commit qualified the integrated
source with bundles staged from it:

- [Full numerical validation](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/38014250354):
  **32/32 stages**, including the rehearsal-bundle artifact stage, with a source
  package check under `--as-cran` reporting 0 notes after the rerun. The 186
  Python regressions include one platform-specific skip.
- [R and platform compatibility](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/38014250352):
  **20/20 stages on each of Windows (R 4.6.1), macOS (R 4.6.1) and Ubuntu 22.04
  with minimum R 4.5.0 and verified reference BLAS/LAPACK**.

The bundle was prepared locally on macOS arm64 with R 4.5.3 by
`scripts/prepare_release.py --dry-run --from-checked-candidate` with no
maintenance exception: the archive was adopted unchanged, the manual was built
with its overfull-box gate, and the source validation scope passed with
0 errors, 0 warnings and 0 notes. A local `run_validation.py --scope all
--as-cran` against the committed bundle then passed all 32 stages,
including the fresh-library install and smoke test of the archive. Both local
runs disabled R's remote incoming lookups (`_R_CHECK_CRAN_INCOMING_REMOTE_=false`)
because github.com answered HTTP 503 to this machine's link checks after
repeated runs; the hosted R-devel check above performed the full remote
incoming check, including every README link, on the same bytes.

R's external system-clock check (`_R_CHECK_SYSTEM_CLOCK_`) was disabled in
every environment recorded here, as for 0.4.1; the local runs evaluated the
incoming date rule in UTC. No check recorded here verified the system clock
against an external service.

Later publication-PR checks require their own recorded results; this
checkpoint does not predict their outcomes.

#### Intel/noLD native backend

On 2026-10-08 a [fixed twelve-runner investigation](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37787174962)
reached the affected Intel Xeon 6973P-C (family 6, model 173). On that machine,
the pinned R-devel/noLD image and OpenBLAS 0.3.20 selected Cooperlake with one
thread. Both captured 28-by-28 systems reproduced their original incorrect
steps exactly. Each default arm failed all 240 native paired solves; NEHALEM
and reference BLAS/LAPACK each passed all 240. Restoring the default restored
the failures. Hybrid native/scalar solves localized the fault to native backward
substitution; accurate forward solves and Cholesky factors did not prevent it.
Independent scalar regrading agreed with every recorded validity verdict.
The eleven other allocations passed; they do not clear the affected default.

The noLD CI remedy selects verified reference BLAS and LAPACK runtime/linker
libraries before dependency compilation, retains both captured systems as exact
hexadecimal R fixtures, and checks the actual loaded backend and runtime-file
identities before dependencies, after loading the installed numerical stack,
and after the full check and installed-test loop. The three workflows and all
seven required check contexts remain. No packaged source, numerical threshold,
release archive, manifest or tag changes as part of this environment remedy.

The [full affected-CPU qualification](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37795948041)
completed on 2026-10-08 at qualification commit
`2317cdda8a39da7207f4fae8d173036820d6bb65`. Its fixed 24-slot acquisition panel
found one affected machine (slot 6); the other 23 records are acquisition-only,
not package qualifications. On that same Xeon 6973P-C, the original Cooperlake
backend failed all 80 planned native solves and reproduced the saved steps.
Reference BLAS/LAPACK 3.10.0-2ubuntu1 passed all 80 solves at each of four
checkpoints: initial setup, loaded dependencies, installed archive, and final
verification. Independent evidence review checked all 24 artifact ZIP digests
and 213 runtime, mapping and identity assertions for the affected machine.

The exact published archive (`8261b2d8...`, source `9b59788`) passed the complete
R-devel/noLD check with **0 errors, 0 warnings and 0 notes**, including all 27
package test files, examples, vignette rebuilds and the PDF manual. A separate
installed-test sweep passed **27/27**. The boundary diagnostic still refused
both iteration budgets because restart/tolerance stability failed; this is
correct refusal and does not resolve #59. Archive, manual, manifest and all 88
packaged source files remained unchanged. The [qualification record](qualification/intel-nold-0.4.1.json),
[full check log](qualification/intel-nold-0.4.1-check.log),
[boundary diagnosis](qualification/intel-nold-0.4.1-boundary.txt) and
[reference-library record](qualification/intel-nold-0.4.1-reference.txt)
preserve the identities, outcomes and limits alongside the repository.

This qualifies the frozen archive on the observed affected CPU with the recorded
reference backend. It does not establish a repaired upstream kernel, a CPU
hardware defect, noLD causation, or compatibility with every native backend.
[Issue #66](https://github.com/Veronica0206/Gtheory4LLM/issues/66) tracks the native issue; #43's completed scope was capture. The separate
optimizer/stationarity limitation remains in #59. The package rejects these
invalid starting steps before returning a fit; its scalar/sparse/Gaussian
coverage is not broadened by this result.

GitHub published the immutable 0.4.1 release on 2026-10-08 with the three assets
matching the committed bundle. The maintainer confirmed on 2026-10-08 that it
has not been submitted to CRAN. The historical qualification below remains
attributed to its original source, archive and environment.

#### 0.4.1 selected archive

The [ordinary R-devel and noLD qualification run](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37701136749)
built the selected archive identified above with R 4.6.1 from
`9b59788ad9bfc6068faea9115b62ea920d58e745`, the head of `main` once
[PR #63](https://github.com/Veronica0206/Gtheory4LLM/pull/63) and
[PR #65](https://github.com/Veronica0206/Gtheory4LLM/pull/65) were integrated,
and checked those exact bytes twice. An earlier 0.4.1 candidate from `63079ab`
passed the same checks on 2026-10-07 and was superseded by this one, after the
second independent review, before any publication or submission.

- Ordinary Linux R-devel 4.7.0, 2026-10-06 r90643, completed `R CMD check --as-cran`
  with **0 errors, 0 warnings and 1 NOTE**, "Days since last update: 3". The
  recorded CRAN-requested maintenance disposition permits this timing-only NOTE;
  it is retained in the manifest provenance rather than reported as a zero-NOTE
  run. All 27 package test files, examples, vignettes and the PDF manual passed.
- noLD R-devel, 2026-10-03 r90638, with long-double support verified absent,
  checked the same archive with **0 errors, 0 warnings and 0 notes**: all 27
  package test files, vignette rebuilds and the PDF manual passed, and a
  separate installed-test loop completed 27/27 files. On that runner the ordinal boundary diagnostic was refused at both iteration budgets by the stationarity and restart/tolerance stability safeguards, while the characterization baseline reproduced all ten canonical cases.
  Which discrete fits stall varies between machines
  ([issue #59](https://github.com/Veronica0206/Gtheory4LLM/issues/59)); the
  tests report either outcome for the cases observed to stall, and neither
  result demonstrates a repaired optimizer or relaxed acceptance thresholds.

The two push-triggered workflows on the same commit qualified the integrated
source with bundles staged from it:

- [Full numerical validation](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37701137130):
  **29/29 stages**, with a source package check under `--as-cran` reporting
  0 errors, 0 warnings and the documented timing-only NOTE. The reference manual
  was checked separately.
- [R and platform compatibility](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37701136844):
  **20/20 stages on each of Windows (R 4.6.1), macOS (R 4.6.1) and Ubuntu 22.04
  with minimum R 4.5.0 and verified reference BLAS/LAPACK**. These package
  checks did not use `--as-cran`; each reported 0 errors, 0 warnings and
  0 notes, with the reference manual checked separately.

The bundle was prepared locally on macOS arm64 with R 4.5.3 by
`scripts/prepare_release.py --dry-run --from-checked-candidate`: the archive
was adopted unchanged, the manual was built with its overfull-box gate, and the
source validation scope passed with the same single NOTE. A local
`run_validation.py --scope all --as-cran` against the staged manifest then
passed all 29 stages, including the fresh-library install and smoke test of the
staged archive.

R's external system-clock check (`_R_CHECK_SYSTEM_CLOCK_`) was disabled in
every environment recorded here. The hosted runners receive it as FALSE from
`r-lib/actions/setup-r`, the noLD check does not run that step, and the local
runs disabled it because both of R's time services were unreachable from that
machine, which had added an "unable to verify current time" NOTE on the first
local attempt. No check recorded here verified the system clock against an
external service; the file-timestamp check itself passed in every environment,
and no NOTE handling was relaxed.

Later publication-PR checks require their own recorded results; this
checkpoint does not predict their outcomes.

#### 0.4.0 checkpoint, withdrawn

0.4.0 was prepared from `e054422554499a7da54820a5072bb79b798da46c`, qualified
by the same two R-devel checks in
[run 37400601899](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37400601899),
integrated through [PR #61](https://github.com/Veronica0206/Gtheory4LLM/pull/61)
and tagged on 2026-10-06. The push-triggered
[candidate run](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37472366041)
on the tagged commit then failed: its noLD runner refused the ordinal
characterization fit through the same two safeguards, and the 0.4.0 test
treated that as an error. The bundle was withdrawn before any GitHub release
or CRAN submission; the protected tag remains, without assets.

Minimum-R compatibility explicitly selects and verifies reference BLAS and
LAPACK. This does not establish a fix for the previously captured inaccurate
native triangular solve under Ubuntu 22.04/R 4.5.0/OpenBLAS 0.3.20. The production
solver, backward-error refusal bound and no-rescue policy remain unchanged;
[issue #43](https://github.com/Veronica0206/Gtheory4LLM/issues/43) records the
native-operation limitation. Passing these checks does not qualify the deferred
public sparse backend or broaden the scientific claims below.

#### 0.2.0 candidate

All three workflows passed at the 0.2.0 source commit `a4dd59c`:
[exact CRAN candidate readiness](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/35814612564),
[full numerical validation](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/35814607691) and
[R and platform compatibility](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/35814607707).
The readiness workflow built the candidate with R 4.6.1 and checked that
exact archive with R-devel 4.7.0 under `R CMD check --as-cran`: zero errors,
zero warnings and the single expected new-submission NOTE, with the PDF manual
generated. The historical 0.2.0 release archive, SHA-256 `910286884cbb…`, is that
checked file, adopted unchanged by `scripts/prepare_release.py --from-checked-candidate`
after its check report was verified, rather than rebuilt; its retained manifest
records its origin and the R versions that built and checked it. So, unlike 0.1.0
below, the prepared archive and the R-devel-checked archive are one identity.
The local preparation additionally passed archive correspondence with the
source commit, the full source validation scope with the staged manifest, the
manual's overfull-box gate and the public-content audit; the committed bundle
then passed the artifact integrity and fresh-library install and smoke checks.

#### 0.1.0 publication

All three publication-commit workflows passed at `2332d40`: compatibility,
locked-environment full validation, and CRAN candidate readiness. The release
assets match the committed manifest. Branch protection is checked separately
from workflow results; its required state and verifier are documented in
[repository policy](REPOSITORY_POLICY.md).

| Check | Verified state |
|---|---|
| R test suite, source and installed | Passed for the release sources |
| Python regression suite | Passed for the release sources |
| Release identity, committed-artifact integrity and public-content audit | Passed for the published bundle |
| Reference manual | Built with no overfull boxes |
| Hosted current-R / R-devel candidate check | Passed for a separately rebuilt candidate, including the manual |
| Locked-environment full validation | Passed at the publication commit |

**The successful R-devel candidate check did not use the published archive.**
The published archive's SHA-256 starts with `401a10b0`; the checked candidate's
starts with `38430d96`. Their R code, tests and datasets match, but documentation
and generated build files differ. An R-devel result for the candidate must not
be attributed to the published file. No exact published-archive R-devel pass is
claimed for 0.1.0; later-version checks do not supply that missing historical
evidence.

A skipped check is not a passing check. `scripts/run_validation.py` records
which checks actually ran and names missing tools. Results for a previous
commit also do not establish that a later development checkout has passed.

### Current development priorities

Before a 1.0 release, the development capabilities need qualification beyond
their bounded implementation tests:

- Measure dense/sparse equivalence and solver acceptance across binary,
  ordinal, nominal, joint and call-effect designs, including boundary cases.
  Qualify inner solves and the complete acceptance cost at scale before
  claiming support for the full native panels. Historical accepted and refused
  scale specimens remain evidence for their original runs, not a current pass.
- Assess Laplace approximation error separately from numerical convergence,
  and calibrate parameter recovery and optional information-based intervals
  using the shared simulator. The existing
  [40-fit binary/ordinal pilot](../validation-studies/discrete-030-usability-pilot/README.md)
  preserves unstable rare-outcome recovery despite high numerical acceptance.
- Check incomplete Gaussian recovery under declared missingness scenarios and
  distinguish an intended balanced projection from reliability of an irregular
  observed panel. Joint incomplete Gaussian fitting remains future work.
- Qualify categorical targets and planning under varied category frequencies,
  dependence and low-discrimination scenarios; assess Monte Carlo precision
  separately from parameter uncertainty. Keep pilot refitting at a declared,
  feasible scale. Their point-estimator pilot route is implemented; nominal
  and call-effect pilot interval planning is not implemented.
- Finish source and installed-package checks, documentation/examples, and
  sequential macOS/Linux checks from one final archive. Preserve all historical
  evidence and the separate release/publication gates. A development source
  version is not evidence of publication, CI success or CRAN acceptance.

### Scientific scope

The package remains a research beta. Its statistical pilots are reproducible
but small; they do not establish broad recovery or coverage guarantees. Their
scope and limits are recorded in [validation scope](VALIDATION_SCOPE.md).

The current development implementation offers exact balanced Gaussian models,
bounded univariate observed-row Gaussian likelihoods, and dense/sparse
first-order Laplace models. Optional discrete intervals are conditional on
accepted, stable interior information and retain the Laplace qualification.
Observed-score, category-vector and decision targets are explicit simulation
estimands with model parameters held fixed. Joint Gaussian-discrete fitting,
joint incomplete Gaussian fitting, reliability of an irregular observed
allocation, observed-score ratios for unordered labels (which have no score) and variable-call models remain
unsupported. The complete boundaries are in [limitations](LIMITATIONS.md).
Repository governance and passing package checks do not expand that scope.
