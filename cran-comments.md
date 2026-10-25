# Gtheory4LLM 1.0.0 submission preparation

This record concerns the 1.0.0 release candidate. Publication, CRAN upload,
maintainer confirmation and CRAN acceptance are separate steps. No submission
or acceptance is asserted by this source file.

## Changes since the CRAN release

The package adds the formula interface and conventional model methods, a bounded
lme4 Gaussian route, public sparse discrete fitting, optional observed
information including conditional calculations with boundary sources held fixed,
an analytic Laplace gradient and explicit projected boundary
escape, an object bootstrap with percentile and BCa intervals, and categorical
simulation/planning targets. `gt_example()` names its numeric coding
`"numeric"`; the former name `"manuscript"` still works with a deprecation
warning. The installed native-data
workflow defines the two scoped whole-data joint examples and their numerical
reproduction contract. NEWS.md and the help pages state the supported models
and numerical guards.

Discrete estimation remains first-order Laplace. The native joint illustrations
use efficacy/safety outcomes and three mental-health groups, not the full
four-aspect/six-flag sets. Numerical acceptance does not establish approximation
accuracy, general interval calibration or a global optimum. The earlier native
point fits lacked ordinary information; subsequent macOS calculations at their
saved estimates supplied conditional intervals by holding the named singular
nonzero source matrices fixed. Such intervals omit held-source estimation and
boundary-selection uncertainty. They have no demonstrated coverage or matching
Linux information calculation; unavailable uncertainty is still reported as
unavailable. The documented near-boundary/weak-signal limitations remain in force.
The 1.0.0 archive itself was not refit on the 21,600-row panels.
Included historical reference tables and synthetic workflow checks are not
claimed as a fresh whole-data qualification of the final archive.

## Current CRAN state and reverse dependencies

Read from the official CRAN package page, check page and PACKAGES.gz on
2026-10-25 at 18:47 UTC (14:47 America/New_York). CRAN lists version 0.5.0,
published 2026-10-11, with all thirteen check flavors OK and no Additional
issues section. This describes the currently listed version, not acceptance of
1.0.0 or administrative closure of earlier correspondence.

The source package index contained 25,559 records (25,529 distinct package
names). No package named Gtheory4LLM in its Depends, Imports, LinkingTo,
Suggests or Enhances fields. Thus there were zero listed reverse dependencies
across those five fields at this checkpoint. Repeat the survey if submission
occurs after this record becomes outdated.

## Exact candidate evidence

The submission copy of this file is completed after the final candidate has
been checked, using its recorded source commit, archive size and SHA-256, R
versions and dependency sessions, ordinary R-devel and no-long-double results,
PDF manual and vignette outcomes, platform compatibility, reverse dependencies
and any remaining NOTE dispositions. Development archives and older release
checks below are not substituted for those final records.

## Historical records

The following source and submission records are preserved as dated historical
evidence. Their versions, scope and checks do not describe the 1.0.0 candidate.

## Compiled code, for the next submission draft

Development since 0.6.0 adds the package's first compiled code. These facts
describe the source; they are not check results, and the next submission draft
records its own evidence.

- One C file, `src/gt_selected_inverse.c`, with no C++, Fortran, OpenMP or
  external library; it includes R's headers and the standard C headers
  `float.h`, `math.h`, `string.h` and `stdint.h`.
- Five routines are registered through `R_registerRoutines()` and reached
  only by `.Call` symbols; `R_useDynamicSymbols(FALSE)` and
  `R_forceSymbols(TRUE)` are set, and `NAMESPACE` uses
  `useDynLib(Gtheory4LLM, .registration = TRUE)`.
- Every input is validated in C (types, lengths, a lower-triangular sparse
  factor with sorted row indices, positive finite pivots), and declared caps on
  dimension, fill, recurrence work, queries, observations, local width, latent
  dimension and contraction work are checked before any allocation. Errors go
  through `Rf_error()`; no routine exits or prints.
- Accumulation uses `long double` where the platform provides it and is
  correct in double where it does not: the R-devel job without long double
  runs the compiled tests, and the macOS (53-bit) and aarch64 Linux (113-bit)
  results agree within 1e-11 on the native fixed-point checks.
- During development the compiled tests also ran under
  `-fsanitize=undefined -fno-sanitize-recover=all` on Linux without a report.

## Gtheory4LLM 0.6.0 — submission draft, not submitted

This draft records qualification as of 2026-10-20 21:00 America/New_York
(2026-10-21 01:00 UTC), before publication or CRAN submission, for the integrated
Model Interface source
`352468d11ee7d09d7b0fba3e97cdf167dd6a75e7`. It adds formula-based fitting and
preflight, conventional model classes/methods, an independently checked lme4
Gaussian engine, and fixed-parameter Laplace approximation checks. NEWS.md
describes the changes and documented limits. Public sparse categorical fitting, categorical
uncertainty, and expanded categorical planning remain future work.

### Selected archive and completed checks

- Archive: `Gtheory4LLM_0.6.0.tar.gz`, 570,725 bytes.
- SHA-256: `d9a592b7b40b73dab9b6d051b4abbe2eff5cf54b1a22d15c58c7ec1d46aef5bd`.
- [Candidate workflow](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861542):
  built with R 4.6.1; ordinary Linux R-devel 4.7.0 (2026-10-18 r90707)
  `R CMD check --as-cran` completed with **0 errors, 0 warnings, 0 notes**, with
  the PDF manual and all 33 packaged tests checked. The archive is adopted
  unchanged.
- The same candidate run's Linux x86-64/Ubuntu 22.04 noLD job used R-devel
  (2026-10-03 r90638), with long double verified absent and reference
  BLAS/LAPACK on AMD EPYC 7763. `R CMD check --no-stop-on-test-error` of the
  **same archive** completed with **0 errors, 0 warnings, 0 notes**, the PDF
  manual and all **33 packaged tests** passed, and the separate installed-test
  loop passed **33/33**. Reference-library probes at setup, with dependencies
  loaded, and after all tests each passed **80/80 native solves**. Retained
  identity records match the source commit, size, and SHA-256 above.
- [Full locked validation](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861801):
  **32/32 stages** at the integrated source.
- [Compatibility](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861768):
  **20/20 stages per platform** on Windows/R release, macOS/R release, and
  Ubuntu 22.04/R 4.5.0. These are source qualification with per-platform bundles.
- Local macOS arm64/R 4.5.3 full locked validation passed **32/32 stages**.
  The locally rebuilt source archive's `--no-manual --as-cran` check reported
  **0 errors, 0 warnings, 0 notes**; the manual was checked separately. The
  selected archive also passed fresh-library installation/smoke and source
  correspondence checks. Local remote incoming and external system-clock
  checks were disabled (`_R_CHECK_CRAN_INCOMING_REMOTE_=false`,
  `_R_CHECK_SYSTEM_CLOCK_=false`). Hosted ordinary R-devel provides remote
  incoming evidence for the selected archive. No external-clock verification
  is claimed.

### Pending before submission

The ordinary/noLD evidence for the selected archive has been independently
audited. Earlier PR evidence belongs to synthetic merge
`9f7ff6239bfd7a2f7958869ce97f50cf2dcb6a92` and remains a distinct historical
candidate; it is not substituted for the source/archive above.

At the dated qualification checkpoint, publication metadata/tag checks and
immutable GitHub delivery remained pending. Refresh those statuses and the
submission date before using this draft for an actual CRAN submission.
No 0.6.0 CRAN submission, maintainer confirmation, or acceptance is claimed.
Refresh the CRAN status and reverse-dependency survey before an actual
submission; the 2026-10-10 survey below is historical. See
[the 0.6.0 qualification record](docs/DEVELOPMENT_STATUS.md#detailed-060-qualification-record).

## Historical 0.5.0 submission comments

The following text is preserved from the preceding submission record. Its
relative timing, status, dependency counts, and first-submission statements
refer to that historical checkpoint, not to the 0.6.0 draft above.

### Gtheory4LLM 0.5.0

This submission contains the correction CRAN requested before 2026-10-26 for the
0.2.0 ERROR in CRAN's additional noLD check, together with the development since
0.2.0 described in NEWS.md. 0.4.0 and 0.4.1 were tagged on GitHub but never
submitted to CRAN; 0.5.0 is the first CRAN submission after 0.2.0.

#### Correction of the reported noLD ERROR

Two tests were corrected, both only in how they report a refused fit.
`tests/package-discrete-safety.R` required numerical acceptance of an ordinal
boundary fit that the optimizer's safeguards correctly refuse on R built without
long double; it now requires accepted fits to reproduce the reference values and
refused fits to be refused by exactly the stationarity or restart-stability
safeguards. `tests/package-characterization.R` reports the one ordinal case
observed to stall as that platform's outcome under the same conditions. The
production optimizer and acceptance thresholds are unchanged; the optimizer
limitation remains tracked in issue #59.

#### New functionality since 0.2.0

Batch declarations with a preflight audit and a shared call effect for Gaussian
fits of equal fixed batches; fixed-layout batch projections, bounded cost-aware
allocation comparisons and Gaussian pilot-precision simulation, with unambiguous
item keys for numeric item identifiers; staged numerical diagnostics, portable
HTML reports and base-graphics figures; specimen capture for refused discrete
solves. Details are in NEWS.md.

#### Exact archive checked

- Archive: Gtheory4LLM_0.5.0.tar.gz
- Size: 534,035 bytes
- SHA-256: 10d501afc114335d6e5f1ddd4f933673726db50979b973549f1d1c893a873cc8
- Source commit: 854e5e792b5dfcbacc88c2a32c0c9792b2d3772d
- Ordinary R-devel and noLD workflow run:
  <https://github.com/Veronica0206/Gtheory4LLM/actions/runs/38014263622>

The archive was built with R 4.6.1 from that commit, the head of `main` once
the 0.5.0 source was integrated, and adopted unchanged from the checked
candidate. The candidate manifest and the noLD evidence record the same bytes,
SHA-256 and source commit.

#### Check environments and results (2026-10-10 and 2026-10-11 UTC)

- Linux x86-64 (Ubuntu 24.04), R-devel 4.7.0 (2026-10-09 r90655),
  `R CMD check --as-cran`: 0 errors, 0 warnings, 0 notes. All 30 package test
  files, examples, both vignettes and the PDF and HTML manuals passed for the
  exact archive above. An earlier attempt of the same job on 2026-10-10
  reported one NOTE, "Days since last update: 6", and nothing else.
- Linux x86-64 (Ubuntu 22.04), R-devel (2026-10-03 r90638) configured without
  long double (`capabilities("long.double") == FALSE`, sizeof long double 0),
  with verified reference BLAS/LAPACK before, during and after the check: full
  `R CMD check --no-stop-on-test-error` of the same archive, 0 errors,
  0 warnings, 0 notes. All 30 package test files, vignettes and the PDF manual
  passed, and a separate installed-package test run completed all 30 files
  with zero failures. On that runner the ordinal boundary diagnostic was
  refused by the stationarity and restart/tolerance stability safeguards,
  while the characterization baseline reproduced all ten canonical cases.
- Ubuntu 22.04, R 4.5.0 with verified reference BLAS/LAPACK; Windows Server
  2022, R 4.6.1 (ucrt); macOS arm64, R 4.6.1: all three compatibility suites
  passed 20 of 20 stages, with 0 errors, 0 warnings and 0 notes in their
  package checks, which did not use `--as-cran`.
- Full locked numerical validation (R 4.5.3, Ubuntu 24.04) passed all 32
  stages at the source commit, including the independent OpenMx, lme4 and
  ordinal comparisons and the rehearsal-bundle artifact stage; its source
  package check under `--as-cran` reported 0 notes. The 186 Python
  regressions include one platform-specific skip per platform.
- Local preparation on macOS arm64 with R 4.5.3 adopted the checked archive
  unchanged, built the manual above and passed the source validation scope
  with 0 errors, 0 warnings and 0 notes; a local full validation of the
  staged bundle then passed all 32 stages, including the fresh-library
  install and smoke test of the archive. Both local runs disabled R's remote
  incoming lookups (`_R_CHECK_CRAN_INCOMING_REMOTE_=false`) because github.com
  answered HTTP 503 to this machine's link checks after repeated runs; the
  hosted R-devel check above performed the full remote incoming check,
  including every README link, on the same bytes.

R's external system-clock check (`_R_CHECK_SYSTEM_CLOCK_`) was disabled in
every environment above: the hosted runners set it to FALSE through
`r-lib/actions/setup-r`, the noLD check does not run it, and locally it was
disabled because both of R's time services are unreachable from that machine.
No check reported here verified the system clock against an external service;
the file-timestamp check itself passed everywhere.

#### Known limitations that this release does not claim to fix

Two numerical limitations remain tracked separately and are unchanged by this
release: the discrete optimizer can report completion without reaching a
stationary point on some machines, which the engine refuses rather than
accepts (issue #59), and a native backward substitution under OpenBLAS 0.3.20
on one Intel CPU model returned an incorrect Newton step, which the package's
backward-error bound rejects before any fit is returned (issue #66). The noLD
results above were obtained with verified reference BLAS/LAPACK.

#### CRAN status and reverse dependencies

CRAN's package index retrieved on 2026-10-10 lists 0.2.0 as the current
version. No reverse dependencies on Gtheory4LLM were found in Depends,
Imports, LinkingTo, Suggests or Enhances among the 25,366 package records.
