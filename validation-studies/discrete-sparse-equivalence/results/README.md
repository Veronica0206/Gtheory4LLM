# Dense/sparse equivalence qualification: executed record

The frozen study was executed on 2026-10-26 from main at
`bec56126d997bf3de8a209c7a02df09232cdd4e1`, which is the reviewed judging
implementation merged in #103. The launcher `run-equivalence.R`, the cases, the
fixtures and the tolerances were the frozen ones. That commit's `R/` and `src/`
trees are identical to those of `e0944b6`, the source of the 1.0.0 release
archive, so the record measures the code being released.

The study ran on two platforms, each from a clean clone of that commit with one
numerical thread:

| Platform | Environment | Run time |
|---|---|---|
| macOS | Apple M4 Max, R 4.5.3, Matrix 1.7.4, R's reference BLAS (`libRblas.0.dylib`), LAPACK 3.12.1 | 3 min 50 s |
| Linux | offline container `gtheory-linux-replication:4.5.2`, aarch64, R 4.5.2, Matrix 1.7.4, OpenBLAS 0.3.26, LAPACK 3.12.0 | 59 s |

## Outcome

**Executed, and not passed under the frozen rules.** Three fixed-parameter
(stage 3) comparisons exceed their tolerances: one case on macOS and two on
Linux. Every other comparison that ran is within tolerance.

| | macOS | Linux |
|---|---|---|
| Scored cases compared | 13: 12 pass; C13 fails at stage 3 | 13: 11 pass; C08 and C13 fail at stage 3 |
| Unsupported under rule R3 | C14, C15 | C14, C15 |
| Backend numerical-validity events (R1) | none | none |
| Negative overlays | N2, N3, N4, N5 produce their conditions and both backends decline acceptance; N1 and N6 do not produce their conditions | same |
| Equivariance transforms | T1–T4 pass; T5 (base C13) not run | T1–T3 pass; T4 (base C08) and T5 not run |
| Latent G/Φ, where defined (C03–C07, C11, C12) | all within 0.01; largest difference 4.4e-6 | same |
| Approximation references (C01 glmer, C02 adaptive quadrature, C09 and C10 clmm) | all converged and recorded | same |

A case that fails a stage stops there. Stages 4–7 did not run for C13 on either
platform, nor for C08 on Linux, and the record marks each skipped stage as not
run.

## The three failures

`investigation/investigate-stage3.R` re-evaluates every C08 and C13 fixed point
with the same code. Its output on each platform is in `investigation/`. It
explains the failures; it is not a verdict and changes no rule.

**macOS, C13 at `displaced_negative`: the solved quantities.**
- The conditional mode differs by 5.5e-10, against 1e-13 (symmetric relative).
- The log determinant differs by 9.7e-9, against 4.1e-11.
- The marginal objective differs by 4.9e-9, against the inherited 1e-10.

The dense mode solve stopped after 12 Newton steps with mode gradient 7.4e-8,
inside the production inner tolerance of 1e-7. The sparse solve reached 1e-14
in 6 steps. Dense solves of the same point tightened to 1e-9 move toward the
sparse value: after 31 steps the tightened objective is 4.8e-9 below the
production dense one and within 4e-11 of the sparse one, which is still the
lowest. A tightening to 1e-10 does not converge within 500 steps. So at this
point the sparse value is the more accurate, and the dense search reaches it
only slowly. Rule R2 anticipates this: dense defines the semantics but is not a
numerical oracle. On Linux the dense solve of the same point takes 6 steps and
agrees with sparse within 1.1e-13, and the other two C13 points agree on macOS.
The disagreement therefore belongs to the dense search's path at this point on
this platform.

**Linux, C08 and C13: the mode score at the common latent point.**
- C08 differs by 4.5e-13 and C13 by 2.1e-12, against an absolute 1e-13.

At latent zero the score's entries are 92–146 in size, and the dense (OpenBLAS)
and sparse products sum them in different orders. Relative to the score's size,
the differences are 2.9e-15 to 1.6e-14. On macOS the two products are
bit-identical. The calibration that set this tolerance also ran on macOS,
observed zero, and so set the value from its floor.

## What was not changed

No tolerance, metric, case, fixture, injection or control was changed, and the
calibrated values remain those of `tolerances.csv`. The protocol forbids
widening a tolerance after results are seen. A result of "passed" could
therefore come only from a separately specified and reviewed amendment, made
prospectively and followed by a new execution reported as amended, not from
this record.

## Scope

This record compares two implementations of the same first-order Laplace
approximation across the frozen binary/ordinal envelope. Agreement between them
says nothing about the approximation's accuracy; the stage 7 references report
that separately. The record does not cover:
- sparse categorical or joint fitting (C14 and C15 are unsupported under R3);
- public backend selection;
- performance.

## Files

| Path | Content |
|---|---|
| `macos/`, `linux/` | The record of each run, as the launcher wrote it: `results.csv` (frozen schema, case × backend × stage × quantity), `detail.csv` (every measurement, every point, overlay evidence), `summary.csv` (one verdict per case, overlay and transform), `problems.txt`, `environment.txt` and `session-info.txt`. The console output repeats `summary.csv` and is not retained |
| `run-provenance.txt` | The commit and tree identities, the digests of the launcher, implementation, cases and tolerances, the command, and start and end times |
| `investigation/` | The stage 3 investigation script and its output on each platform |
