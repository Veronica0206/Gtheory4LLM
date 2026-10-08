# Development status

Current release and development state. Version history is in [NEWS.md](../NEWS.md),
planned work is in [the roadmap](ROADMAP.md), and implementation boundaries are
in [limitations](LIMITATIONS.md).

## Release state

The 0.4.1 publication uses the checked candidate without rebuilding the
package. The records below identify the selected bundle and the completed
pre-publication checkpoint on 2026-10-07; they do not assert later delivery or
CRAN acceptance. 0.4.0 was tagged `v0.4.0` on 2026-10-06 but never published or
submitted: the no-long-double check of that tagged commit refused a discrete
fit on one runner, and `tests/package-characterization.R` could not report that
as a platform outcome. 0.4.1 corrects that test and nothing else in the package.

| Fact | Value |
|---|---|
| Checkout version | `0.4.1`. The development line was versioned `0.3.0.9000` and then `0.4.0.9000`; no 0.3.0 was released, and `0.4.0` was tagged but not published |
| Bundle in `artifacts/` | `0.4.1`, adopted unchanged from the checked candidate; the archive and manual identities are recorded below and in the manifest |
| Bundle source commit | `9b59788ad9bfc6068faea9115b62ea920d58e745` |
| Manifest publication state | Read `release_state` in [the manifest](../artifacts/manifest.json). `prepared` records staging; `published` records the publication commit/tag identity. Neither field alone proves a GitHub upload or CRAN submission |
| `v0.4.1` identity | The release-identity gate requires the tag to contain the published manifest and to preserve the candidate source in its ancestry. A tag alone does not establish asset delivery |
| GitHub delivery | Completion requires a non-draft, immutable [v0.4.1 release](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.4.1) with exactly the archive, manual and manifest, verified against the committed bytes. This document does not substitute for that delivery record |
| Historical releases | [v0.2.0](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.2.0) is immutable with three assets; its archive, manual, manifest and tag remain unchanged. `v0.4.0` identifies the withdrawn 0.4.0 publication-metadata commit and carries no release assets. `v0.1.0` identifies publication commit `2332d40`; that older release remains `immutable: false` |
| Repository protection checkpoint | On 2026-10-07, `main` required seven check contexts including noLD, and the authenticated policy verifier passed. Release-tag protection blocked updates and deletions of `v*` with no bypass actors |
| CRAN checkpoint | On 2026-10-07 before 0.4.1 publication/submission, CRAN distributed `0.2.0`, published on 2026-10-04, as OK on all nine ordinary flavors reported. Its additional noLD check reported an ERROR in `tests/package-discrete-safety.R`; CRAN requested a correction before 2026-10-26. Submission receipt, maintainer confirmation and CRAN acceptance/publication are separate subsequent events |

The selected archive is `Gtheory4LLM_0.4.1.tar.gz`, 482,151 bytes, SHA-256
`8261b2d8084a54fa69a4bb3b7ae0caac3eefcc75ba83969d09422d525460e554`.
The selected `Gtheory4LLM-manual.pdf` is 234,911 bytes, SHA-256
`9c866b0876c1ac0575af2e9c2c670922b782138d41bdc7c4e1ff1e7efb0bc8c1`.
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

### Intel/noLD native backend

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

The full affected-CPU qualification of the unchanged published 0.4.1 archive is
pending. The replay establishes a remedy for the captured operations, not a
full package pass, a repaired upstream kernel, a CPU hardware defect, or noLD
causation. [Issue #66](https://github.com/Veronica0206/Gtheory4LLM/issues/66)
tracks the native issue; #43's completed scope was capture. The separate
optimizer/stationarity limitation remains in #59. The package rejects these
invalid starting steps before returning a fit; its scalar/sparse/Gaussian
coverage is not broadened by this result.

GitHub published the immutable 0.4.1 release on 2026-10-08 with the three assets
matching the committed bundle. The maintainer confirmed on 2026-10-08 that it
has not been submitted to CRAN. The historical qualification below remains
attributed to its original source, archive and environment.

### 0.4.1 selected archive

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

### 0.4.0 checkpoint, withdrawn

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
