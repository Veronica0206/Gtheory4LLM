# Dense/sparse equivalence qualification under Amendment 2: executed record

The study was executed under [Amendment 2](../AMENDMENT-2.md) on 2026-10-27,
from main at `5e0bb32c1df7005a05916d71cd365942f5a4f238`, after the amendment
was merged in #110. Stage 3 is judged under [Amendment 1](../AMENDMENT-1.md)
and stage 4 under Amendment 2. The amended launcher
`run-equivalence-amendment-2.R` verified its runtime pins before sourcing
anything, and each run's `environment.txt` lists the eight pinned files with
their digests.

The [original record](../results/README.md) and the
[Amendment 1 record](../results-amendment-1/README.md) are unchanged. Neither
passed, and no record replaces another.

The cases, fixtures, tolerances and judging implementation are byte-identical
to those of the earlier runs. Of the eight `R/` files the study sources, two
changed since the Amendment 1 run: `R/discrete_mode.R` and
`R/discrete_sparse_mode.R`. They carry the dense roundoff safeguard of #109,
which this commit contains. This record is therefore the first to measure the
dense solver that will be released. The `src/` tree is unchanged.

The study ran on two platforms, each from a clean clone of that commit with one
numerical thread:

| Platform | Environment | Run time |
|---|---|---|
| macOS | Apple M4 Max, R 4.5.3, Matrix 1.7.4, R's reference BLAS (`libRblas.0.dylib`), LAPACK 3.12.1 | 7 min 36 s |
| Linux | offline container `gtheory-linux-replication:4.5.2`, aarch64, R 4.5.2, Matrix 1.7.4, OpenBLAS 0.3.26, LAPACK 3.12.0 | 1 min 39 s |

## Outcome

**Executed, and passed under Amendment 2.** Every compared case passes on both
platforms, and the two platforms' verdicts are identical: their `summary.csv`
files are byte-identical.

The cases pass in two different ways, counted separately:

| | macOS | Linux |
|---|---|---|
| **Passed with accepted fits:** both backends accept the fit, and the fits agree | 12: C01–C12 | 12: same |
| **Passed with matching rejected fits:** both backends reject the fit for the same reasons, at agreeing estimates (rule B) | 1: C13 | 1: same |
| Unsupported under rule R3 | C14, C15 | same |
| Backend numerical-validity events (R1) | none | none |

A pass with matching rejected fits means the two backends reached the same
point and refused it for the same reasons. It does not mean the case produced
an accepted fit. No estimate, interval, coefficient or G/Φ is reported from a
rejected fit.

| Measurement | macOS | Linux |
|---|---|---|
| Stage 3 under Amendment 1, largest measurement as a share of its tolerance | 0.012 | 0.078 |
| Stage 4, the 12 accepted fits: objective, relative | within 6.3e-12 | within 6.3e-12 |
| Stage 4, the 12 accepted fits: parameter distance | within 5.6e-5 | within 5.6e-5 |
| Latent G/Φ, where defined (C03–C07, C11, C12) | largest difference 4.4e-6, against 0.01 | same |
| C13 rejected fits: acceptance failures | `outer_stationarity_failed` on both backends | same |
| C13 rejected fits: objective, relative | 4.0e-13, against 1e-6 | 1.2e-11 |
| C13 rejected fits: parameter distance | 1.3e-8, against 0.02 | 5.7e-8 |
| Equivariance transforms | T1–T5 pass | same |
| Negative overlays | N2, N3, N4, N5 produce their conditions and both backends decline acceptance; N1 and N6 do not produce their conditions | same |
| Approximation references (C01 glmer, C02 adaptive quadrature, C09 and C10 clmm) | all recorded | same |

Two results are new in this record:
- **C13 at stage 4.** Both backends reject its fit at a near-limit point. There
  the site source is near zero (standard deviation about 0.036), and its
  projected score of 1.32e-3 exceeds the frozen stationarity tolerance of 1e-3,
  as the [Amendment 1 investigation](../results-amendment-1/README.md) found.
  The refusal is the same on both backends, and the rejected fits agree.
- **C13's T5 transform.** The group-relabelling transform ran for the first
  time, because C13 now passes stage 4. It passes on both backends, with
  differences of about 1e-15.

## What is not covered

- **N1 and N6** did not produce the conditions they inject, as in every earlier
  run. Those two negative checks were therefore not exercised. They are recorded
  as `condition_not_produced`, not as passes.
- **The scope** is that of the frozen study. This record compares two
  implementations of the same first-order Laplace approximation across the
  frozen binary/ordinal envelope. Agreement between them says nothing about the
  approximation's accuracy; the stage 7 references report that separately. It
  does not cover:
  - sparse categorical or joint fitting (C14 and C15 are unsupported under R3);
  - public backend selection;
  - performance.
- **The earlier records** are not changed by this one. The frozen study did not
  pass, and neither did Amendment 1.

## Files

| Path | Content |
|---|---|
| `macos/`, `linux/` | The record of each run, as the launcher wrote it: `results.csv` (frozen schema, set `qualification_amendment_2`), `detail.csv` (every measurement, including both backends' acceptance failures for C13), `summary.csv` (one verdict per case, overlay and transform), `problems.txt` (none), `environment.txt` (with the runtime pins) and `session-info.txt`. The console output repeats `summary.csv` and is not retained |
| `run-provenance.txt` | The commit and tree identities, the digests of the launcher, the pins, both specifications, the three implementations, the cases, tolerances and pin files, the `R/` files changed since the Amendment 1 run, the image, the command, the start and end times, and the digests of each record |
