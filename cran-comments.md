## Update: Gtheory4LLM 0.4.1

This update corrects the test ERROR reported for 0.2.0 in CRAN's additional
noLD check, as requested before 2026-10-26. It also includes the development
since 0.2.0 described in NEWS.md.

### Correction of the reported noLD ERROR

Two tests are corrected, both only in how they report a refused fit.

The ordinal boundary test previously demanded numerical acceptance when the
optimizer did not satisfy the acceptance safeguards. The corrected test requires
accepted fits to reproduce the reference likelihood and variance components.
A refused fit must have an explicit FALSE acceptance flag and nonempty reasons
limited to stationarity or restart/tolerance stability. Deterministic negative
cases reject missing flags, empty or unexpected reasons and incorrect accepted
estimates. Variance-coordinate and boundary-projection checks remain unconditional.
The production optimizer and acceptance thresholds are unchanged.

The characterization test, which reproduces ten canonical fits against a
stored baseline, required its accepted-reference ordinal case to be numerically
accepted; the suite also includes an intentionally refused discrete control.
On one check of the tagged but unpublished 0.4.0, a noLD runner
refused its ordinal case through the same safeguards. That ordinal case, the
one case observed to be refused this way, is now reported as the machine's
outcome when it is refused by those two safeguards and by nothing else: its
estimates are not compared there, but it must still carry every other
recorded field, the same model terms and the same variance names. Any other
case refused this way, a refusal for any other reason, or accepted numbers
that moved still fail, and the acceptance flags are recorded as the engine
set them rather than coerced. The comparison and the recording are exercised
with constructed records and fits before any fit is compared. That test
change is the only difference from 0.4.0.

On the checked noLD environment the boundary diagnostic remains explicitly
refused by stationarity and stability safeguards at both iteration budgets.
The completed checks therefore validate correct refusal, not a repaired optimizer.
That optimizer limitation remains tracked in issue #59:
<https://github.com/Veronica0206/Gtheory4LLM/issues/59>.

### Exact archive checked

- Archive: Gtheory4LLM_0.4.1.tar.gz
- Size: 482,151 bytes
- SHA-256: 8261b2d8084a54fa69a4bb3b7ae0caac3eefcc75ba83969d09422d525460e554
- Source commit: 9b59788ad9bfc6068faea9115b62ea920d58e745
- Completed ordinary R-devel and noLD workflow:
  <https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37701136749>

The archive was built with R 4.6.1 from that commit, the head of `main` once
the 0.4.1 test correction and its tightening were integrated, and adopted
unchanged from the checked candidate. The downloaded candidate manifest and the
noLD evidence record the same bytes, SHA-256 and source commit. An earlier
0.4.1 candidate built from 63079ab, SHA-256 `c70c38b4…`, passed the same
checks but was superseded by this one before any publication or submission.

### Check environments and results (2026-10-07 UTC)

- Linux x86-64 (Ubuntu 24.04), R-devel 4.7.0 (2026-10-06 r90643),
  `R CMD check --as-cran`: 0 errors, 0 warnings, 1 NOTE. All 27 package test
  files, examples, vignettes and the PDF manual passed for the exact archive
  above.
- Linux x86-64 (Ubuntu 22.04, OpenBLAS 0.3.20), R-devel (2026-10-03 r90638)
  configured without long double (`capabilities("long.double") == FALSE`,
  sizeof long double 0): full `R CMD check --no-stop-on-test-error` of the
  same archive, 0 errors, 0 warnings, 0 notes. All 27 package test files,
  vignettes and the PDF manual passed, and a separate installed-package test
  run completed all 27 files with zero failures. On that runner the ordinal boundary diagnostic was refused at both iteration budgets by the stationarity and restart/tolerance stability safeguards, while the characterization baseline reproduced all ten canonical cases.
- Ubuntu 22.04, R 4.5.0 with verified reference BLAS/LAPACK 3.10.0;
  Windows Server 2022, R 4.6.1 (ucrt); macOS arm64, R 4.6.1: all three
  compatibility suites passed 20 of 20 stages, with 0 errors, 0 warnings and
  0 notes in their package checks, which did not use `--as-cran`. Reference
  manuals were checked separately.
- Full locked numerical validation passed all 29 stages at the source commit,
  including the independent OpenMx, lme4 and ordinal comparisons; its source
  package check under `--as-cran` reported the same single NOTE. The 173
  Python regressions include one platform-specific skip per platform.
- Local preparation on macOS arm64 with R 4.5.3 adopted the checked archive,
  built the manual above and passed the source validation scope; a local full
  validation of the staged bundle then passed all 29 stages, including the
  fresh-library install and smoke test of the archive, with the same single
  NOTE.

R's external system-clock check (`_R_CHECK_SYSTEM_CLOCK_`) was disabled in
every environment above: the hosted runners set it to FALSE through
`r-lib/actions/setup-r`, the noLD check does not run it, and locally it was
disabled because both of R's time services were unreachable from that machine.
No check reported here verified the system clock against an external service;
the file-timestamp check itself passed everywhere.

The single ordinary R-devel NOTE is incoming feasibility:
"Days since last update: 3", counted on 2026-10-07 from CRAN's publication of
0.2.0 on 2026-10-04. This is a CRAN-requested maintenance update to correct
the 0.2.0 noLD ERROR before 2026-10-26. The NOTE count and this explicit
reason are retained in the validation report and archive provenance; other
NOTEs, warnings, errors and incomplete checks are not permitted by this policy.

### Other corrections and qualification limits

This update also corrects batch-audit metadata name collisions and wide HTML
report table layout, and updates validation and release documentation.

The minimum-R qualification above uses explicitly verified reference libraries.
On 2026-10-08, a fixed twelve-runner investigation reproduced two captured
native solve failures on Intel Xeon 6973P-C with the pinned noLD build and
OpenBLAS 0.3.20's Cooperlake dispatch. Native backward substitution reproduced
the saved wrong answers in all 240 paired solves in each default arm. On the
same machine, forced NEHALEM and reference BLAS/LAPACK each passed 240/240;
restoring the default restored the failures. Scalar residuals and hybrid
solves independently localized this execution-path dependency. The other
eleven allocated runners passed the same replay protocol:
<https://github.com/Veronica0206/Gtheory4LLM/actions/runs/37787174962>.

The package rejects these invalid starting steps under its unchanged
backward-error bound before returning a fitted result. This is separate from
the optimizer refusal in issue #59. The noLD CI remedy explicitly selects and
verifies reference BLAS/LAPACK before dependency compilation, checks both saved
systems, and rechecks loaded libraries and their identities after dependencies
are loaded and after the package checks. This environment remedy does not
modify the published archive, repair OpenBLAS, or establish that all Intel or
noLD configurations fail. Full qualification of the unchanged archive on the
affected Intel CPU is recorded separately when complete. The active native
investigation is issue #66; issue #43 records the earlier capture scope:
<https://github.com/Veronica0206/Gtheory4LLM/issues/66>.

Gaussian equal-fixed-batch call effects are supported within the documented
scope. Batch-aware reliability and D studies, broader sparse qualification and
the remaining development roadmap are not claimed by this maintenance work.

### CRAN status and reverse dependencies

CRAN's check results retrieved on 2026-10-07 list published 0.2.0 as OK on
all nine ordinary flavors reported, with noLD as its only additional issue:
<https://cran.r-project.org/web/checks/check_results_Gtheory4LLM.html>.

The CRAN source package index retrieved on 2026-10-07 at 17:28 UTC contained
25,370 package records. No reverse dependencies on Gtheory4LLM were found in
Depends, Imports, LinkingTo, Suggests or Enhances.
