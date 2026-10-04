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
that exhausted the budget": the latter could also include invalid evaluations,
but nothing here establishes how many, or whether any did.

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

## 4. Replay of the scale-risk specimen with the failed evaluations' own records

Recorded 2026-09-23 with `replay-scale-risk.R`, after the mode solvers began
returning `inner_iterations` and `inner_line_search_failed` for a solve that did
not converge, and after the sparse solver gained the dense solve-validity and
final-factor invariants (#46). Same panel: the regenerated digest equals
`bad937e27a0ce3ee587b47ca1ae41b25`. Same environment family as section 2
(R 4.5.3, Matrix 1.7.4, arm64 macOS). Characterization, not qualification, and
not a predeclared result.

The sparse fit reproduced section 3 exactly: **632 evaluations, 584 valid, 48
invalid, 40 valid solves ending at iteration 60**, the same four acceptance
failures, and `alternative_1_tight` again the rejected candidate. The fit's own
evaluation log counted 625 evaluations with 47 invalid; the seven it does not
count are the start and the final-validation and stationarity evaluations,
which its scope note excludes.

Every one of the 48 invalid evaluations and the 40 at-budget valid solves was
replayed through both evaluators at the same parameters and tolerance.

| | invalid (48) | valid at budget (40) |
| --- | ---: | ---: |
| phase: tightened (`inner_tol = 1e-9`) / coarse (`1e-7`) | 34 / 14 | 39 / 1 |
| sparse solve- or factor-validity reason | 0 | — |
| sparse stopped at the iteration budget, not converged | 44 | — |
| sparse stopped because the line search could not improve | 4 | — |
| sparse replay reproduces the recorded verdict | 48 of 48 | — |
| dense at the same point: invalid / valid | 40 / 8 | 7 / 33 |
| dense solve- or factor-validity reason | 0 | 0 |

What this establishes, stated at its true strength:

- **None of the invalid evaluations is an arithmetic-validity event.** Neither
  backend refuses any of these points by the backward-error or final-factor
  invariant. The #46 checks do not fire on this specimen, and the specimen is
  not evidence about them.
- **The failure is conditional-mode non-convergence, dominated by the
  iteration budget.** 44 of the 48 sparse-invalid evaluations ran all 60 inner
  iterations and ended above the relaxed final tolerance; 4 stopped earlier
  because the line search could not improve the penalised objective. In the 40
  cases dense also refuses, its final gradients range from 2e-6 to 186 at the
  same points, so these are solves that had not approached the mode, not
  solves a hair short of it.
- **Every backend disagreement is gradient straddling at the budget in the
  tightened phase.** At the 8 points where dense is valid and sparse is not,
  both solvers reached iteration 60 (one dense solve stopped at 48) with final
  gradients between 6.5e-10 and 8e-8 against the relaxed threshold of 1e-8;
  sparse sat just above it, dense just below. At the 7 points where sparse is
  valid and dense is not, the same picture holds with the roles reversed
  (sparse 1.0e-9 to 9.5e-9, dense 1.4e-8 to 4.9e-8). Where both are valid at
  the budget, the marginal values agree to 5.6e-11.
- **The tightened phase is where the budget binds.** 34 of the 48 invalid and
  39 of the 40 at-budget evaluations belong to the tightened objective
  (`validation_inner_tol = 1e-9`), whose relaxed threshold of 1e-8 the
  60-iteration solve reaches only marginally at this size.

What it does not establish: why the outer optimizer visits parameter regions
whose conditional solves stall, whether a larger inner budget or a warm start
would make those solves converge rather than merely continue, and anything
about panels of other shapes. Those are the questions #4 and #8 will have to
put to measurement; this replay only removes the hypothesis that the recorded
invalid evaluations were factorization defects, and separates budget
exhaustion from line-search failure in the record.

### Work pass re-run with stop causes (2026-09-24)

The work pass of `profile-medium.R` now splits its invalid evaluations by how
the solve stopped. Re-run on the section 2 panel, same environment family;
the timing pass and its peak-RSS figures were not re-run and stand as
recorded.

| | dense | sparse |
| --- | ---: | ---: |
| work-pass evaluations: valid / invalid | 760 / 5 | 761 / 4 |
| invalid: ran the inner budget without converging | 1 | 0 |
| invalid: line search could not improve | 4 | 4 |
| invalid: other (response, factorization, validity reason) | 0 | 0 |
| valid solves ending at iteration 60 | 1 | 3 |

At this size the few invalid evaluations are line-search stalls, not budget
exhaustion, and no validity invariant fires on either backend.

## 5. Inner budget and warm start, measured on the scale-risk specimen

Recorded 2026-09-24 with `budget-experiment.R`, on the same regenerated panel
(digest `bad937e27a0ce3ee587b47ca1ae41b25`, same 632 / 584 / 48 / 40
evaluation counts). The roadmap makes warm starts conditional on measured
need; this is the measurement, and it is characterization on one specimen,
not a design decision and not a feature. The experiment solver is a copy of
the production sparse loop with a starting vector, and it reproduces the
production solver exactly from a zero start on recorded points.

Two questions were asked, separately, of every evaluation the fit could not
use and every valid solve that ended at the budget, at the recorded parameters
and tolerance:

| | invalid (48) | valid at budget (40) |
| --- | ---: | ---: |
| cold, budget 60 (production): converged | 0 | 40 (all at iteration 60) |
| cold, budget 120: converged | 32 | 40 |
| iterations to converge at budget 120, median / max | 77 / 120 | 69 / 92 |
| cold, budget 300: converged | 32 (max 137 iterations) | 40 |
| cold, budget 300: still not converged | 8 at the budget, 8 line-search stalls | 0 |
| warm from the previous evaluation's mode, budget 60: converged | 38 | 40 |
| iterations to converge, warm, median / max | 9 / 60 | 3 / 60 |
| previous evaluation's own cold solve had converged | 23 of 48 | 37 of 40 |
| max abs parameter change from the previous evaluation, median / max | 2e-4 / 250 | 1.5e-4 / 250 |

What this establishes:

- **The 40 marginal solves are a budget artefact.** Every one converges by
  iteration 92 cold, and in a median of 3 iterations warm. The 60-iteration
  budget with the tenfold relaxed final tolerance is what made them marginal.
- **Two thirds of the invalid evaluations are the same artefact.** 32 of 48
  converge cold with the budget doubled, at a median of 77 iterations, and
  none needs more than 137. A warm start recovers 38 of 48 at the ordinary
  budget, in a median of 9 iterations, because the outer optimizer's
  consecutive evaluations are finite-difference neighbours: the median
  parameter move between them is 2e-4.
- **A residual set is not a budget question.** 16 of the 48 do not converge
  cold within 300 iterations, 8 of them because the line search stops
  improving, and 10 remain unrecovered warm. These are parameter points the
  outer optimizer visits where the conditional problem itself is hard; a
  larger budget lets them run longer without converging. The maximum
  parameter move of 250 belongs to an alternative-start jump, where a warm
  start is a cold start.
- **Neither remedy changes the objective.** A larger budget and a warm start
  both change only where the conditional solve stops; the mode they converge
  to, where they converge, is the same mode, and the marginal value at it is
  the same value. What they change is which evaluations the optimizer can
  use, which is what decides whether this fit is accepted.

What it does not establish: that a warm start is safe as a production policy
(the roadmap's requirement of an independent cold validation of the selected
solution stands), what budget the tightened phase should have in general, or
that the residual stalls are harmless. Those belong to #5, decided on this
evidence rather than assumed, and to #4 and #8.
