## Update: 0.4.0

This update corrects the ERROR reported for 0.2.0 by the additional check
"noLD" (R-devel built without long double), which CRAN asked to have corrected
before 2026-10-26:
<https://www.stats.ox.ac.uk/pub/bdr/noLD/Gtheory4LLM.out>

It also carries the development since 0.2.0, listed in NEWS.md.

### The reported ERROR

`tests/package-discrete-safety.R` required one ordinal fit on a boundary panel
to be numerically accepted. On a build of R without long double, the
optimizer reports completion without leaving its starting values. The package
then refuses the fit through its stationarity check, which is the intended
behaviour, and the test stopped because it demanded acceptance.

The test now requires accepted fits to reproduce the reference likelihood and
variance components. A refused fit must have an explicit FALSE acceptance flag
and nonempty reasons drawn only from the stationarity or restart/tolerance
stability safeguards. Missing flags, arbitrary errors and incorrect accepted
estimates are covered by deterministic negative tests. Variance-coordinate and
boundary-projection checks remain unconditional. The optimizer is unchanged.

That the optimizer can stall in this way is a limitation of the discrete
engine. It is not addressed by this update and is tracked as
<https://github.com/Veronica0206/Gtheory4LLM/issues/59>.

### Other changes since 0.2.0

- Diagnostics, portable reports and figures for fitted models.
- A batch declaration, `gt_batch()`, for items annotated several to a call. A
  Gaussian fit of equal fixed batches estimates one shared call effect;
  reliability coefficients for such a fit are not implemented yet and are
  refused, as the help pages state.
- Corrections and additional refusals of numerically invalid results.

### How it was checked

The exact candidate workflow checks a single archive on ordinary Linux R-devel
with `--as-cran`, and on Linux x86-64 R-devel configured without long double.
Both jobs verify the archive SHA-256 and its source commit. The noLD check
includes vignettes, the PDF manual and all installed-package tests; every test
output and the platform description are retained.

The submission copy of these comments must accompany the completed evidence
for that exact archive; see docs/RELEASE_CHECKLIST.md. Source validation uses
a matching staged 0.4.0 bundle, preserving the published 0.2.0 assets.

## R CMD check results

The sole permitted incoming NOTE for this maintenance update is
"Days since last update", explicitly explained by CRAN's request to correct the
0.2.0 noLD ERROR before 2026-10-26. The actual NOTE count and request reason
remain in the check report. Errors, warnings, other NOTEs and incomplete checks
still fail qualification. The submission copy records the actual results and
archive identity from the completed checks.

## Reverse dependencies

No CRAN reverse dependencies were found in the CRAN package index checked on
2026-10-05 (Depends, Imports, LinkingTo, Suggests and Enhances).
