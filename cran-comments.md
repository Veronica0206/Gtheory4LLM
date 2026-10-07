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

On the checked noLD environment the boundary diagnostic remains explicitly
refused by stationarity and stability safeguards at both iteration budgets.
The completed checks therefore validate correct refusal, not a repaired optimizer.
That optimizer limitation remains tracked in issue #59:
<https://github.com/Veronica0206/Gtheory4LLM/issues/59>.

### Exact archive checked

REPLACE BEFORE SUBMISSION with the 0.4.1 candidate: archive name, size,
SHA-256, source commit and the completed workflow run that checked it on
R-devel and on R-devel without long double.

### Check environments and results

REPLACE BEFORE SUBMISSION with the environments in which the submitted 0.4.1
archive was checked and their results.

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
