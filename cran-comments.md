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

The correction is to that test. It still asserts on every platform what it
exists to guard, that no evaluation at the variance boundary becomes an
attempt error. It asserts acceptance at the reference estimates where the
search moves, and refusal by the stationarity check where no attempt leaves
its starting values.

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

REPLACE BEFORE SUBMISSION with the environments in which the submitted archive
was checked, and their results.

## R CMD check results

REPLACE BEFORE SUBMISSION with the result of `R CMD check --as-cran` on the
submitted archive.

## Reverse dependencies

There are none on CRAN.
