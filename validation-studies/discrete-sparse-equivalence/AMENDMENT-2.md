# Amendment 2: stage 4 when both backends reject a fit

Specified on 2026-10-27, after the Amendment 1 record was executed and recorded
(`results-amendment-1/README.md`), and before any execution under this
amendment. Like the protocol and Amendment 1, it is frozen when merged. Its
execution is reported separately as "Amendment 2". The original record and the
Amendment 1 record are retained unchanged, and no record replaces another.

## Why an amendment

Under Amendment 1 every compared case passes stage 3. C13 fails stage 4 on both
platforms because both backends reject its fit.

The merged stage 4 (`equivalence-runner-impl.R`) compares the fitted layout,
objective and parameters only when both fits are accepted. Otherwise it records
them as not measured, and a quantity that is not measured fails the case. So a
case whose fit both backends reject, for the same reasons and at the same
point, can never pass stage 4, however closely the backends agree. Yet two
implementations that reach the same point and refuse it for the same reasons
agree there.

This amendment was specified after the Amendment 1 record and its
investigation. Those showed that the rejected C13 fits agree closely once the
dense line search has the roundoff safeguard of #109: to 4.0e-13 relative in
the objective on macOS and 1.2e-11 on Linux. The rule is nevertheless general.
It applies to every case whose fits both backends reject, and it can fail.
Before #109, the macOS dense and sparse fits of C13 were rejected for different
reasons and ended 4.33 apart in the objective, and this rule would have failed
them.

## What changes

Only stage 4, and only when both backends reject the fit, that is, each returns
a fit that is not numerically accepted. The merged stage 4 judges every other
case unchanged:
- both fits accepted;
- dispositions that differ;
- either fit refused (no fit returned).

Stage 3 is judged under Amendment 1 (A1, A2a, A2b and A2c), unchanged. Every
other stage, rule, tolerance, case, fixture, fixed point, control, injection,
transform and reference stays as frozen.

### B1. The same refusal

The dispositions agree (`disposition_agreement`, as frozen), and both are
`rejected`. In addition, the two fits must report identical acceptance failures:
the sorted set of acceptance checks each fit failed. This is recorded as
`rejection_reason_agreement`, with tolerance 0 (identical). Both sets are
written to `detail.csv`.

### B2. The same rejected fit

Given B1, the two rejected fits are compared as the merged rule compares
accepted ones, from their final estimates and under the frozen tolerances:
- `rejected_fit_layout`: the same parameter names, covariance dimensions and
  names, link dimensions, counts and parameter number, identical (tolerance 0);
- `rejected_fit_objective_relative`: |nll_dense − nll_sparse| / max(|nll_dense|,
  |nll_sparse|), against the frozen `fitted_objective_relative`, 1e-6;
- `rejected_fit_parameter_distance`: the frozen scaled parameter distance,
  against the frozen `fitted_parameter_distance`, 0.02.

If B1 fails, these three are not measured, and the case fails. The merged
`fitted_layout`, `fitted_objective_relative` and `fitted_parameter_distance`
rows are recorded as not applicable, with the reason, and do not gate.

Latent G and Φ are judged as frozen. Where they are defined, they still need
accepted public fits, so an eligible case whose fits are rejected still fails
there.

### What B does not establish

A rejected fit is not an estimate. Agreement under B says that the two backends
reached the same point and refused it for the same reasons. It says nothing
about whether that point is a maximum or whether the refusal is correct, and no
interval, coefficient or G/Φ is reported from it. A case that passes stage 4
under B is reported as passing with rejected fits, and its record shows the B
quantities. It then continues to stages 5 to 7 like any passing case.

## Execution and reporting

1. **Implementation.** `amendment-2-impl.R` replaces only the stage 4
   judgment. It is sourced after `equivalence-runner-impl.R` and
   `amendment-1-impl.R`, and hands every case outside B to the merged stage 4.
   The launcher is `run-equivalence-amendment-2.R`. Before it sources anything,
   it verifies `amendment-2-pins.csv` against the digest written in the
   launcher, and every file it lists against its pin. Those files are both
   specifications, the three implementations, `tolerances.csv`,
   `fixture-digests.csv` and `source-hashes.csv`.

   The entry point repeats the check and parses the tolerance table from the
   bytes it verified. It refuses any supplied table that differs, and refuses an
   existing record before writing anything. It appends the pins to the new
   run's `environment.txt`. The launcher is the supported invocation, because
   only it authenticates the manifest. The study's freeze test pins the
   launcher, the manifest and the files it lists.
2. **Before execution.** The amendment is merged after review. Until then no
   scored case is evaluated under it. The rules need no new calibration: B1 is
   an identity, and B2 uses the frozen fitted tolerances. The implementation's
   exercise on the non-scoring calibration panels, on macOS and on Linux, is
   reported in its review.
3. **Execution.** From the merged commit, on macOS and in the offline Linux
   container, with one numerical thread, into `results-amendment-2/<platform>/`.
   That commit contains the dense line-search safeguard of #109, so the record
   measures the code to be released.
4. **Reporting.** In its own change, labelled "Amendment 2", beside the
   unchanged original and Amendment 1 records. Any failure under these rules is
   recorded as such; a further change would need a further amendment.

## What this amendment does not do

It does not:
- change stage 3, where Amendment 1's rules apply, or any stage other than 4;
- change any tolerance, since the rejected-fit comparisons use the frozen fitted tolerances;
- treat agreement on a refusal as an accepted estimate, or as evidence about the refused point;
- compare fits when either backend returns no fit, or when the dispositions or the acceptance failures differ;
- add or remove cases, or change the injections;
- address approximation accuracy, sparse categorical or joint fitting, public backend selection or performance.

A pass under this amendment means the two backends agree within the frozen
tolerances, including on the cases whose fits both refuse for the same reasons.
It does not mean that the original study or Amendment 1 passed.
