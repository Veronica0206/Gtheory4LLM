# Dense/sparse equivalence qualification under Amendment 1: executed record

The study was executed under [Amendment 1](../AMENDMENT-1.md) on 2026-10-27,
from main at `dfb396a3bae5850f0ce96a97e185b84b405d1b61`, after the amendment
was merged in #106. The amended launcher `run-equivalence-amendment-1.R`
verified its runtime pins before sourcing anything. Each run's
`environment.txt` lists the six pinned files with their digests. The original
[record](../results/README.md) is unchanged, and neither record replaces the
other.

The cases, fixtures, tolerances and judging implementation are byte-identical
to those of the original run. Of the package code, the study sources eight
files of `R/`, and they are identical to the original run's at `bec5612`. The
only change to `R/` since then is `R/bootstrap.R` (#107), which the study does
not use. The `src/` tree is unchanged.

The study ran on two platforms, each from a clean clone of that commit with one
numerical thread:

| Platform | Environment | Run time |
|---|---|---|
| macOS | Apple M4 Max, R 4.5.3, Matrix 1.7.4, R's reference BLAS (`libRblas.0.dylib`), LAPACK 3.12.1 | 22 min 53 s |
| Linux | offline container `gtheory-linux-replication:4.5.2`, aarch64, R 4.5.2, Matrix 1.7.4, OpenBLAS 0.3.26, LAPACK 3.12.0 | 2 min 27 s |

## Outcome

**Executed, and not passed under Amendment 1.** Every compared case passes
stage 3 under the amended rules, on both platforms. C13 fails stage 4 on both
platforms, because neither backend accepts its fit. The two platforms' verdicts
are identical: their `summary.csv` files are byte-identical.

| | macOS | Linux |
|---|---|---|
| Scored cases compared | 13: 12 pass; C13 fails at stage 4 | same |
| Unsupported under rule R3 | C14, C15 | same |
| Backend numerical-validity events (R1) | none | none |
| Stage 3 under Amendment 1 | all 13 pass; the largest measurement is 0.011 of its tolerance | all 13 pass; the largest is 0.078 |
| Stage 4, fitted comparisons of the 12 accepted cases | objective within 6.3e-12 relative, parameters within 5.6e-5 | same |
| Latent G/Φ, where defined (C03–C07, C11, C12) | all within 0.01; largest difference 4.4e-6 | same |
| Negative overlays | N2, N3, N4, N5 produce their conditions and both backends decline acceptance; N1 and N6 do not produce their conditions | same |
| Equivariance transforms | T1–T4 pass; T5 (base C13) not run | same |
| Approximation references (C01 glmer, C02 adaptive quadrature, C09 and C10 clmm) | all recorded | same |

Under the amended rules, the three stage 3 failures of the original record
pass: C13 on macOS, and C08 and C13 on Linux. C08 therefore runs its later
stages on Linux for the first time, and they pass. C13 now reaches stage 4,
which it never reached in the original record.

## The stage 4 failure: C13

Both backends reject C13's fit, on both platforms, so the dispositions agree
and `disposition_agreement` passes. With no accepted fit, the frozen stage 4
code (`equivalence-runner-impl.R`, unchanged by the amendment) records the
fitted layout, fitted objective and fitted parameter distance as not measured.
A quantity that is not measured fails the case. The reasons for the
rejections were not part of the record. The investigation below refits C13
exactly as stage 4 does to find them.

**Why no backend accepts C13.** Three fits take the same path: both backends
on Linux, and the sparse backend on macOS.
- Each ends where L-BFGS-B stops on relative reduction.
- At that point the site source is near zero: `site::chol` −3.32, a standard deviation of about 0.036.
- Its projected score is 1.32e-3. The frozen stationarity tolerance is 1e-3, so the fit is refused for outer stationarity.
- The two Linux fits agree to 6.4e-12 relative in the objective, and the macOS sparse fit is within 1.4e-10 of them.

The refusal is the acceptance rule working as specified at a near-limit point.
It is not a difference between the backends.

**Why the macOS dense fit takes another path.** The dense fit on macOS ends
somewhere else:
- L-BFGS-B stops with code 52, `ABNORMAL_TERMINATION_IN_LNSRCH`.
- It records 200 unusable evaluations, and 85 more that are usable but used the whole inner step budget.
- Its objective is 4.33 worse.
- It fails four acceptance checks rather than one.

The investigation traces this to the dense conditional-mode solve:

1. **The rounding-blocked Newton step.** Near the conditional mode the Newton
   decrease falls below the objective's rounding resolution: 1.3e-13 at
   evaluation 12, against eps × objective = 2.6e-13. The dense line search
   accepts a step only if the objective falls by at least the Armijo
   amount less a fixed absolute slack of 1e-12. On macOS the full step's
   objective rounds above that bound, by 4.5e-12 at evaluation 12 and 1.2e-10
   at evaluation 15. The step is then halved up to 23 times and the solve
   crawls to its 60-step budget.

   On Linux the same full step rounds below the bound. The next gradient is
   4.7e-14 and 1.2e-8, and the solve converges in 6 steps. Both platforms take
   the same four full Newton steps first. The difference is in the last bits of
   the objective at the fifth, from the different BLAS.
2. **Where the paths part.** The macOS dense solve first used its whole budget
   at evaluation 5, then needed 16 steps at evaluation 8 and the whole budget
   at evaluation 12. Each of those evaluations stayed usable, but its
   objective was up to 8.2e-8 from the sparse value. The fits ask for the same
   parameters through evaluation 12 and different ones from evaluation 13.
   Evaluation 15 is the first that the macOS dense solve cannot use: its final
   gradient is 1.7e-5, against a usability limit of 1e-6. At the same
   parameters, the Linux dense solve converges in 6 steps.
3. **How the penalties reach the optimizer.** An unusable evaluation returns
   the penalty value 1e100. The logger sees 201 unusable evaluations; the
   fit's own count, 200, covers only the optimizer's evaluations. Of the 201,
   181 stopped at the 60-step budget and 20 at a failed line search. Their median final gradient
   is 1.2e-6, just above the usability limits.

   The finite-difference gradient evaluated 561 pairs, which hold 180 of the
   unusable evaluations. In 134 pairs the penalty is on one side only, so that
   gradient component is about 1e102 to 1e104. In 23 pairs both sides were
   unusable and the penalties cancelled. This is the mechanism of issue #59.
4. **The sparse solver's safeguard.** The sparse solve already accepts a full
   Newton step whose decrease is within rounding when its derivative check
   passes (`.gt_d_roundoff_descent()`). It did so at evaluations 12 and 15 on
   macOS. The dense solve has no equivalent.
5. **Counterfactual.** In one R session only, the dense line search was given
   that safeguard, and C13 was refitted. On macOS the dense fit then has no
   unusable evaluation and no budget stop. It ends at objective 824.2785100132,
   within 4.0e-13 relative of the sparse fit and 1.3e-8 in parameter distance.
   Like the sparse fit, it is refused only for outer stationarity. On Linux
   nothing changes in kind. The rounding-blocked step therefore explains the
   whole difference of the macOS dense path.

So the macOS dense fit reaches the same rejection as the others, by a path
that #59 describes. Even with the safeguard, the frozen stage 4 rule would
still record C13's fitted comparisons as not measured, because no backend
accepts its fit. The record would not pass either way.

## What was not changed

No rule, tolerance, metric, case, fixture, injection or control was changed,
in the study or in the package. The counterfactual changes the dense solver in
memory only. The dense backend is the package's default discrete engine, and
any change to it belongs in its own reviewed package change. Under the
protocol, a different verdict could come only from a further prospective
amendment and a new execution.

## Scope

This record compares two implementations of the same first-order Laplace
approximation across the frozen binary/ordinal envelope, under the stage 3
rules of Amendment 1. Agreement between the implementations says nothing about
the approximation's accuracy; the stage 7 references report that separately.
The record does not cover:
- sparse categorical or joint fitting (C14 and C15 are unsupported under R3);
- public backend selection;
- performance.

## Files

| Path | Content |
|---|---|
| `macos/`, `linux/` | The record of each run, as the launcher wrote it: `results.csv` (frozen schema, case × backend × stage × quantity, set `qualification_amendment_1`), `detail.csv` (every measurement, every point, overlay evidence), `summary.csv` (one verdict per case, overlay and transform), `problems.txt`, `environment.txt` (with the runtime pins) and `session-info.txt`. The console output repeats `summary.csv` and is not retained |
| `run-provenance.txt` | The commit and tree identities, the digests of the launcher, the pins, the specification, both implementations, the cases, tolerances and pin files, the image, the command, the start and end times, and the digests of each record |
| `investigation/investigate-c13-fits.R` | Refits C13 with both backends as stage 4 does, through a logger around each evaluator. It reports the rejection reasons, the stationarity record, the unusable evaluations and the finite-difference pairs. Output per platform: `c13-fits-macos.txt`, `c13-fits-linux.txt` |
| `investigation/replay-dense-newton.R` | Replays the dense Newton steps at evaluations 12 and 15 of the macOS dense fit, with their exact parameters. Output: `newton-replay-macos.txt`, `newton-replay-linux.txt` |
| `investigation/dense-roundoff-counterfactual.R` | The counterfactual. Output: `counterfactual-macos.txt`, `counterfactual-linux.txt` |
