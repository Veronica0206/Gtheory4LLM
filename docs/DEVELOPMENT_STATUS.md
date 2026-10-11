# Development status

Current release and development state. Version history is in [NEWS.md](../NEWS.md),
planned work is in [the roadmap](ROADMAP.md), and implementation boundaries are
in [limitations](LIMITATIONS.md).

## 0.5.0 Study Planning release preparation

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

## Release state

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
| Checkout version | `0.5.0` (Study Planning release). The development line was versioned `0.3.0.9000`, `0.4.0.9000` and `0.4.1.9000`; no 0.3.0 was released, `0.4.0` was tagged but not published, and `0.4.1` was published on GitHub only |
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

## Validation evidence

### 0.5.0 selected archive

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
