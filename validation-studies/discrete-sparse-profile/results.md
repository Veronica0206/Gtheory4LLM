# Recorded measurements

## 1. Qualified prototype evidence

Not restated here. The frozen studies hold it: fixed-parameter algebra in
`../discrete-sparse-reference/`, fitted dense-sparse agreement across ten cases
with accepted, rejected and refused parity in
`../discrete-sparse-fitted-smoke/`. Both were frozen before the implementations
they judge existed.

## 2. Engineering profile

Panel: 1200 rows, 112 random coordinates, 5-category ordinal logit, crossed
item and rater, 6 parameters. Chosen because it sits exactly at
`max_observations` and well inside `max_random_dimension`, so **both backends
run under default limits** and neither guard is raised to obtain a comparison.
Both fits are numerically accepted and both select `primary_tight`.

Measured on macOS arm64, R 4.5.3, Matrix 1.7.4, one backend per process.

| | dense | sparse | ratio |
| --- | ---: | ---: | ---: |
| elapsed | 83.22 s | 12.26 s | 6.8x |
| ms per evaluation | 108.57 | 15.81 | 6.9x |
| marginal evaluations | 765 | 765 | — |
| evaluator share of fit | 100% | 99% | — |
| peak RSS (process) | 751 MB | 466 MB | 1.6x |
| R-visible allocation (`Rprofmem`) | 26,412 MB | 11,885 MB | 2.2x |
| largest single allocation | 1.03 MB | 0.07 MB | 15x |
| design storage | 134,400 cells | 2,400 nnz | 56x |
| curvature storage | — | 2,512 nnz | — |
| factor entries / triangle | — | 1,378 / 1,312 | — |
| inner iterations mean / p90 / max | 7.30 / 13 / 60 | 7.64 / 14 / 60 | — |
| evaluations hitting `inner_maxit` | 1 | 3 | — |

Peak RSS is the primary memory figure. `Rprofmem` is complementary rather than a
substitute: Matrix and CHOLMOD allocate natively, and those bytes are not fully
represented in R's own accounting. The `gc()` peak is recorded by the script but
is not used as an allocation claim.

Two observations that are not speedup claims. The evaluation counts are
identical at 765, so the difference is cost per evaluation rather than a
different optimizer path. And the largest single allocation differs by 15x while
total allocation differs by only 2.2x, which is the shape expected when the
saving is one large dense object rather than many small ones.

No speedup threshold is asserted. On the much smaller fitted smoke panels
(300-400 rows) sparse is *slower* than dense, because those panels are sized so
dense remains available as the reference and there is nothing for sparsity to
save.

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

The failure is generated upstream. Of 584 evaluations, **40 exhausted the
60-iteration inner budget**, returning the invalid-evaluation sentinel and
putting discontinuities into the outer objective. Sampling those specific
parameter points and replaying them through the dense evaluator shows dense
reaching the same budget at the same points, and in two of eight sampled points
dense returned invalid where sparse still produced a finite value.

So this is a limitation of the cold conditional-mode solve as the outer
optimizer explores parameter space, shared by both backends, not an artefact of
sparse algebra.

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
