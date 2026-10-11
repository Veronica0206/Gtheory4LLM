## Gtheory4LLM 0.5.0

This submission contains the correction CRAN requested before 2026-10-26 for the
0.2.0 ERROR in CRAN's additional noLD check, together with the development since
0.2.0 described in NEWS.md. 0.4.0 and 0.4.1 were tagged on GitHub but never
submitted to CRAN; 0.5.0 is the first CRAN submission after 0.2.0.

### Correction of the reported noLD ERROR

Two tests were corrected, both only in how they report a refused fit.
`tests/package-discrete-safety.R` required numerical acceptance of an ordinal
boundary fit that the optimizer's safeguards correctly refuse on R built without
long double; it now requires accepted fits to reproduce the reference values and
refused fits to be refused by exactly the stationarity or restart-stability
safeguards. `tests/package-characterization.R` reports the one ordinal case
observed to stall as that platform's outcome under the same conditions. The
production optimizer and acceptance thresholds are unchanged; the optimizer
limitation remains tracked in issue #59.

### New functionality since 0.2.0

Batch declarations with a preflight audit and a shared call effect for Gaussian
fits of equal fixed batches; fixed-layout batch projections, bounded cost-aware
allocation comparisons and Gaussian pilot-precision simulation, with unambiguous
item keys for numeric item identifiers; staged numerical diagnostics, portable
HTML reports and base-graphics figures; specimen capture for refused discrete
solves. Details are in NEWS.md.

### Exact archive checked

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

### Check environments and results (2026-10-10 and 2026-10-11 UTC)

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

### Known limitations that this release does not claim to fix

Two numerical limitations remain tracked separately and are unchanged by this
release: the discrete optimizer can report completion without reaching a
stationary point on some machines, which the engine refuses rather than
accepts (issue #59), and a native backward substitution under OpenBLAS 0.3.20
on one Intel CPU model returned an incorrect Newton step, which the package's
backward-error bound rejects before any fit is returned (issue #66). The noLD
results above were obtained with verified reference BLAS/LAPACK.

### CRAN status and reverse dependencies

CRAN's package index retrieved on 2026-10-10 lists 0.2.0 as the current
version. No reverse dependencies on Gtheory4LLM were found in Depends,
Imports, LinkingTo, Suggests or Enhances among the 25,366 package records.
