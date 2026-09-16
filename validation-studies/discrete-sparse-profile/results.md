# Recorded measurements

## 1. Qualified prototype evidence

Not restated here. The frozen studies hold it: fixed-parameter algebra in
`../discrete-sparse-reference/`, fitted dense-sparse agreement across ten cases
with accepted, rejected and refused parity in
`../discrete-sparse-fitted-smoke/`. Both were frozen before the implementations
they judge existed.

## 2. Engineering profile

Panel: 1200 rows, 112 random coordinates, 5-category ordinal logit, crossed item
and rater, 6 parameters. Chosen because it sits exactly at `max_observations`
and well inside `max_random_dimension`, so **both backends run under default
limits** and neither guard is raised to obtain a comparison. Both fits are
numerically accepted and both select `primary_tight`.

    panel_md5 = 09b195b3002a4d0e38b8bfd598d1169e

Recorded as provenance, not as a frozen fixture: these numbers came from exactly
this generated panel. The issue #14 work established that a seed alone does not
pin generated data across architectures.

### Environment

    R 4.5.3, Matrix 1.7.4
    platform aarch64-apple-darwin20, Darwin, arm64
    BLAS    .../lib/libRblas.0.dylib
    LAPACK  .../lib/libRlapack.dylib (3.12.1)
    threads OMP_NUM_THREADS unset, OPENBLAS_NUM_THREADS unset,
            MKL_NUM_THREADS unset, VECLIB_MAXIMUM_THREADS unset

### Measurements

One backend per process, via `profile-medium.sh`.

| | dense | sparse | ratio |
| --- | ---: | ---: | ---: |
| elapsed | 83.26 s | 12.19 s | 6.8x |
| ms per evaluation | 108.62 | 15.72 | 6.9x |
| marginal evaluations | 765 | 765 | — |
| evaluator share of fit | 100% | 99% | — |
| peak RSS (process) | 707 MB | 483 MB | 1.5x |
| `Rprofmem` recorded allocation (>= 1 KB) | 26,412 MB | 11,885 MB | 2.2x |
| largest single recorded allocation | 1.03 MB | 0.07 MB | 15x |
| design storage | 134,400 cells | 2,400 nnz | 56x |
| curvature storage | — | 2,512 nnz | — |
| factor entries / triangle | — | 1,378 / 1,312 | — |
| work-pass evaluations: valid / invalid | 760 / 5 | 761 / 4 | — |
| valid-solve inner iterations mean / p90 / max | 7.30 / 13 / 60 | 7.64 / 14 / 60 | — |
| valid solves ending at iteration 60 | 1 | 3 | — |

Raw peak-RSS lines, as the OS utility reported them, in bytes on this platform:

    dense    740966400  maximum resident set size   ->  707 MB
    sparse   506888192  maximum resident set size   ->  483 MB

Peak RSS varies a few percent between runs. Across three runs of this panel the
figures were 707-751 MB for dense and 466-504 MB for sparse, so the table
records one run with its raw line rather than presenting a single value as
exact. The ratio is stable at roughly 1.5x.

Peak RSS is the primary memory figure. It cannot be measured from inside the
process being measured, which is why `profile-medium.sh` exists and why the raw
line and its unit are recorded rather than only a converted number: the utility
reports bytes on macOS and kilobytes on Linux.

`Rprofmem` is complementary rather than a substitute, because Matrix and CHOLMOD
allocate natively and those bytes are not fully represented in R's own
accounting. Its total is **recorded allocation at or above the 1000-byte
threshold**, not all R allocation. No `gc()`-derived figure is reported: locating
"max used MB" by a fixed column index is not robust, and three weaker measures
add nothing to peak RSS, `Rprofmem` and the storage counts.

### What the inner-iteration figures mean

They describe **valid solves only**. Both mode solvers return
`list(valid = FALSE, inner_converged, inner_gradient)` for an evaluation they
could not complete, with no `inner_iterations` field, so a failed evaluation
cannot contribute an iteration count and this profiler cannot attribute its
cause. Valid and invalid calls are counted separately for that reason.

"Valid solves ending at iteration 60" is therefore not the same as "evaluations
that exhausted the budget": the latter would also include some of the 5 dense
and 4 sparse invalid evaluations, and nothing here establishes how many.

### What the evaluation counts do and do not show

Both fits used **765 marginal evaluations**, so the timing difference is **not
explained by a difference in evaluation count**. Optimizer-path identity is not
asserted: two optimizations can perform the same number of evaluations while
visiting different parameter sequences. Establishing path equivalence is #4's
work, not this profile's.

The largest single recorded allocation differs by 15x while total recorded
allocation differs by 2.2x, which is the shape expected when the saving is one
large dense object rather than many small ones.

No speedup threshold is asserted, and none should be added. This is evidence,
not a performance test. On the much smaller fitted smoke panels (300-400 rows)
sparse is *slower* than dense, because those panels are sized so dense remains
available as the reference and there is nothing for sparsity to save.

## 3. Known scale-risk characterization

    panel_md5 = bad937e27a0ce3ee587b47ca1ae41b25
    2400 rows, 166 random coordinates, same generator family

**This is not a sparse qualification failure**, and it is excluded from every
performance figure above.

A sparse full fit at this size was **rejected**: `optimizer_incomplete`,
`validation_computation_failed`, `outer_stationarity_failed` and
`restart_or_tolerance_stability_failed`, with `alternative_1_tight` returning
L-BFGS-B code 52, `ABNORMAL_TERMINATION_IN_LNS`.

No supported full dense fit was attempted, because 2400 rows exceeds
`max_observations = 1200` and the dense guard was not raised to obtain a
comparison. What was compared instead:

At the selected final point, the two evaluators agree essentially exactly.

    dense  nll 3371.46439355   inner_iterations 6   inner_gradient 2.55e-15
    sparse nll 3371.46439355   inner_iterations 6   inner_gradient 2.89e-15
    max|dense - sparse|  mode 4.44e-16   eta 6.66e-16   nll 0

The final mode is healthy: `inner_converged` TRUE, `tight_final_mode` TRUE.

The failure is generated upstream. Of **632 evaluations, 584 were valid and 48
invalid**, and **40 of the valid solves ended at iteration 60**. The invalid
evaluations return the sentinel and put discontinuities into the outer
objective; their cause is not attributable from this instrumentation, and in
particular is not established to be budget exhaustion. Sampling those specific
parameter points and replaying them through the dense evaluator shows dense
reaching the same budget at the same points, and in two of eight sampled points
dense returned invalid where sparse still produced a finite value.

The evidence therefore supports a cold conditional-solve limitation that is not
sparse-specific. Stated that way rather than as "shared by both backends",
because dense was sampled at selected points rather than subjected to a
supported full 2400-row fit.

It is retained as risk evidence for #4 and #8. It is a post-discovery
characterization specimen: its behaviour was observed before any expectation was
frozen, so it must not be presented as a predeclared result.

Two notes carried forward.

The budget-hitting behaviour is a gradient rather than a cliff. At 1200 rows,
where both backends are accepted, dense already hits the budget once and sparse
three times.

**Cross-issue hypothesis, not a finding.** The captured #14 failure also showed
an inner solve reaching the 60-iteration boundary. Whether the same underlying
conditioning mechanism is involved is unknown, and #14's downstream behaviour
differs materially: there the outer optimizer reported convergence without
moving from its starting values, which is not what happens here.
