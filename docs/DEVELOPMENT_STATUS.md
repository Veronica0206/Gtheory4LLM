# Development status

Current release and development state. Version history is in [NEWS.md](../NEWS.md),
planned work is in [the roadmap](ROADMAP.md), and implementation boundaries are
in [limitations](LIMITATIONS.md).

## Release state

The 0.4.0 publication uses the checked candidate without rebuilding the package.
The following records identify the selected bundle and the completed
pre-publication checkpoint on 2026-10-06; they do not assert later delivery or
CRAN acceptance.

| Fact | Value |
|---|---|
| Checkout version | `0.4.0`. The development line was versioned `0.3.0.9000` and then `0.4.0.9000`; no 0.3.0 was released |
| Bundle in `artifacts/` | `0.4.0`, adopted unchanged from the checked candidate; the archive and manual identities are recorded below and in the manifest |
| Bundle source commit | `e054422554499a7da54820a5072bb79b798da46c` |
| Manifest publication state | Read `release_state` in [the manifest](../artifacts/manifest.json). `prepared` records staging; `published` records the publication commit/tag identity. Neither field alone proves a GitHub upload or CRAN submission |
| `v0.4.0` identity | The release-identity gate requires the tag to contain the published manifest and to preserve the candidate source in its ancestry. A tag alone does not establish asset delivery |
| GitHub delivery | Completion requires a non-draft, immutable [v0.4.0 release](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.4.0) with exactly the archive, manual and manifest, verified against the committed bytes. This document does not substitute for that delivery record |
| Historical releases | [v0.2.0](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.2.0) is immutable with three assets; its archive, manual, manifest and tag remain unchanged. `v0.1.0` identifies publication commit `2332d40`; that older release remains `immutable: false` |
| Repository protection checkpoint | On 2026-10-06, `main` required seven check contexts including noLD, and the authenticated policy verifier passed. Release-tag protection blocked updates and deletions of `v*` with no bypass actors |
| CRAN checkpoint | On 2026-10-06 before 0.4.0 publication/submission, CRAN distributed `0.2.0`, published on 2026-10-04. Its additional noLD check reported an ERROR in `tests/package-discrete-safety.R`; CRAN requested a correction before 2026-10-26. Submission receipt, maintainer confirmation and CRAN acceptance/publication are separate subsequent events |

The selected archive is `Gtheory4LLM_0.4.0.tar.gz`, 479,899 bytes, SHA-256
`a43a4cccbf2cd363625f36bad692e57aa0bde113be0492f642194c9c50362d65`.
The selected `Gtheory4LLM-manual.pdf` is 234,915 bytes, SHA-256
`22ed5c30ee15f3f5619a39c64c443cc161400018c7c001d0b73ecc8272afebd7`.
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

## Validation evidence

### 0.4.0 selected archive and integrated sources

The [ordinary R-devel and noLD qualification run](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37400601899)
used the same selected archive identified above, built with R 4.6.1 from
`e054422554499a7da54820a5072bb79b798da46c`.

- Ordinary Linux R-devel 4.7.0, r90638, completed `R CMD check --as-cran` with
  **0 errors, 0 warnings and 1 NOTE**, “Days since last update: 2”. The recorded
  CRAN-requested maintenance disposition permits this timing-only NOTE; it is
  retained in the manifest provenance rather than reported as a zero-NOTE run.
  All 27 package test files, examples, vignettes and the PDF manual passed.
- noLD R-devel at the same R revision, with long-double support verified absent,
  checked that exact archive with **0 errors, 0 warnings and 0 notes**. All 27
  package test files passed, as did a separate installed-test loop of 27/27
  files, vignette rebuilds and the PDF manual.
- The boundary diagnostic explicitly refused the fit at both tested iteration
  budgets, naming stationarity and restart/tolerance stability safeguards.
  The corrected regression accepts either a verified reference fit or an
  explicit refusal under the named safeguards. These results confirm the
  acceptance/refusal contract; they do not demonstrate a repaired optimizer or
  relaxed acceptance thresholds. [Issue #59](https://github.com/Veronica0206/Gtheory4LLM/issues/59)
  remains a separate limitation.

[PR #61](https://github.com/Veronica0206/Gtheory4LLM/pull/61) integrated the repair
by fast-forward at `9e7627c10b4740ca3472a4e8930e019a9016dfe7`, preserving the
candidate's ancestry. All 88 packaged source files at that head are
byte-identical to the candidate source. Its completed post-merge checks were:

- [Full numerical validation](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37413313276):
  **29/29 stages**, with a source package check under `--as-cran` reporting
  0 errors, 0 warnings and the documented timing-only NOTE. The reference manual
  was checked separately.
- [R and platform compatibility](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37413313286):
  **20/20 stages on each of Windows, macOS and minimum R 4.5.0**. These package
  checks did not use `--as-cran`; each reported 0 errors, 0 warnings and 0 notes,
  with the reference manual checked separately.

Those post-merge workflows staged their own bundles from `9e7627c`; their
results qualify the integrated source and those staged artifacts. The ordinary
R-devel/noLD run above supplies the exact selected-archive qualification.
Later publication-PR checks also require their own recorded results; this
checkpoint does not predict their outcomes. The previously completed local
29-stage validation did not use `--as-cran`. A later local `--as-cran` attempt
on 2026-10-06 passed the numerical tests, installed-package tests and manual,
but failed the strict gate because R could not reach its external clock
services, adding an "unable to verify current time" NOTE. The failure is
retained; neither clock verification nor NOTE handling was relaxed. Publication
requires the hosted full `--as-cran` gate with the committed selected bundle to
pass before the GitHub release is published.

Minimum-R compatibility explicitly selects and verifies reference BLAS and
LAPACK. This does not establish a fix for the previously captured inaccurate
native triangular solve under Ubuntu 22.04/R 4.5.0/OpenBLAS 0.3.20. The production
solver, backward-error refusal bound and no-rescue policy remain unchanged;
[issue #43](https://github.com/Veronica0206/Gtheory4LLM/issues/43) records the
native-operation limitation. Passing these checks does not qualify the deferred
public sparse backend or broaden the scientific claims below.

### 0.2.0 candidate

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

### 0.1.0 publication

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

## Current development priorities

The development interface now adds bounded panel-audit examples,
outcome-information profiles, tabular coefficient exports, supplied-grid target
screening and base-R figures. Portable offline HTML reports collect model
context, diagnostics and results while excluding observations and group labels. The installed synthetic workflow demonstrates them; the
[visualization guide](VISUALIZATION.md) describes their scope. A separate
[40-fit binary/ordinal pilot](../validation-studies/discrete-030-usability-pilot/README.md)
records unstable rare-outcome recovery despite high numerical acceptance.
These additions do not make the private sparse implementation public or
complete the full native-panel qualification benchmark.

- Keep release/version prose and installation instructions consistent with the
  published release and development checkout.
- Maintain release-tag protection and update pinned Actions to supported
  runtimes through a separate maintenance change.
- Finish qualifying the private sparse discrete backend for 0.5.0 against
  the release gates in [the roadmap](ROADMAP.md); 0.2.0 ships it only as a
  private prototype. On the development line since 0.2.0 (see the top of
  [NEWS.md](../NEWS.md)): the sparse solver enforces the dense validity
  invariants, failed evaluations are recorded with their own evidence and can
  be captured as specimens, calibration case K05 is corrected before any
  calibration run, and the retained 2,400-row scale-risk specimen is
  characterised as inner-budget non-convergence rather than a validity
  defect. Still open, in order: the equivalence measurement layer,
  calibration, the qualification runner, public backend selection with a
  shared resource contract, and the full native-panel benchmark.

## Scientific scope

The package remains a research beta. Its statistical pilots are reproducible
but small; they do not establish broad recovery or coverage guarantees. Their
scope and limits are recorded in [validation scope](VALIDATION_SCOPE.md).

The current implementation uses balanced coded panels and a dense small-model
discrete engine. It does not implement discrete uncertainty, unbalanced-panel coefficients,
joint Gaussian-discrete fitting, or scalar nominal reliability. The complete
boundaries are in [limitations](LIMITATIONS.md). Repository governance and
passing package checks do not expand that statistical scope.
