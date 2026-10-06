## Update: Gtheory4LLM 0.4.0

This update corrects the test ERROR reported for 0.2.0 in CRAN's additional
noLD check, as requested before 2026-10-26. It also includes the development
since 0.2.0 described in NEWS.md.

### Correction of the reported noLD ERROR

The ordinal boundary test previously demanded numerical acceptance when the
optimizer did not satisfy the acceptance safeguards. The corrected test requires
accepted fits to reproduce the reference likelihood and variance components.
A refused fit must have an explicit FALSE acceptance flag and nonempty reasons
limited to stationarity or restart/tolerance stability. Deterministic negative
cases reject missing flags, empty or unexpected reasons and incorrect accepted
estimates. Variance-coordinate and boundary-projection checks remain unconditional.
The production optimizer and acceptance thresholds are unchanged.

On the checked noLD environment the boundary diagnostic remains explicitly
refused by stationarity and stability safeguards at both iteration budgets.
The completed checks therefore validate correct refusal, not a repaired optimizer.
That optimizer limitation remains tracked in issue #59:
<https://github.com/Veronica0206/Gtheory4LLM/issues/59>.

### Exact archive checked

- Archive: Gtheory4LLM_0.4.0.tar.gz
- Size: 479,899 bytes
- SHA-256: a43a4cccbf2cd363625f36bad692e57aa0bde113be0492f642194c9c50362d65
- Source commit: e054422554499a7da54820a5072bb79b798da46c
- Completed ordinary R-devel and noLD workflow:
  <https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37400601899>

The archive was adopted unchanged from that checked candidate. All 88 packaged
source files are also byte-identical at repair head
9e7627c10b4740ca3472a4e8930e019a9016dfe7; its later changes concern excluded
CI configuration, validation documentation and Python tests.

### Check environments and results (2026-10-06 UTC)

- Linux x86-64, R-devel 4.7.0 (2026-10-03 r90638), `R CMD check --as-cran`:
  0 errors, 0 warnings, 1 NOTE. All 27 installed-package test files, examples,
  vignettes and PDF manual checks passed for the exact archive above.
- Linux x86-64, the same R-devel revision configured without long double
  (`capabilities("long.double") == FALSE`, sizeof long double 0):
  full `R CMD check --no-stop-on-test-error`, 0 errors, 0 warnings, 0 notes.
  All 27 installed-package test files, vignettes and PDF manual passed.
  A separate installed-test run also completed all 27 files with zero failures.
- Ubuntu 22.04, R 4.5.0, verified reference BLAS/LAPACK 3.10.0;
  Windows/current R 4.6.1; macOS/current R 4.6.1:
  all three compatibility suites passed, with 0 errors, 0 warnings and 0 notes
  in their package checks. Reference manuals were checked separately.
- Full locked numerical validation passed all 29 stages, including independent
  OpenMx, lme4 and ordinal comparisons. Local final-bundle validation also passed
  all 29 stages. The 173 Python regressions include one platform-specific skip
  per platform; the corresponding native setup test runs on its target system.

The single ordinary R-devel NOTE is incoming feasibility:
"Days since last update: 2". This is a CRAN-requested maintenance update to
correct the 0.2.0 noLD ERROR before 2026-10-26. The NOTE count and this explicit
reason are retained in the validation report and archive provenance; other
NOTEs, warnings, errors and incomplete checks are not permitted by this policy.

### Other corrections and qualification limits

This update also corrects batch-audit metadata name collisions and wide HTML
report table layout, and updates validation and release documentation.

The minimum-R qualification above uses explicitly verified reference libraries.
A separate captured native solve failure under Ubuntu 22.04/OpenBLAS 0.3.20
remains under investigation: the stored step does not solve its system even
though the stored factor is accurate. The package refuses that operation under
its unchanged backward-error bound, without rescue or retry. Passing with the
reference backend is not a claim that the older native-library failure is fixed.
The failure evidence has been retained durably. Issue #43 records the capture:
<https://github.com/Veronica0206/Gtheory4LLM/issues/43>.

Gaussian equal-fixed-batch call effects are supported within the documented
scope. Batch-aware reliability and D studies, broader sparse qualification and
the remaining development roadmap are not claimed by this maintenance work.

### CRAN status and reverse dependencies

The CRAN check page refreshed on 2026-10-06 lists published 0.2.0 with eight
ordinary platforms OK and noLD as its only Additional issue:
<https://cran.r-project.org/web/checks/check_results_Gtheory4LLM.html>.

The CRAN source package index retrieved on 2026-10-06 at 13:01 UTC contained 25,341 package
records. No reverse dependencies on Gtheory4LLM were found in Depends, Imports,
LinkingTo, Suggests or Enhances.
