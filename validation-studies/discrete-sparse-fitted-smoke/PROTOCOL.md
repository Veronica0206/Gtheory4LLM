# Fitted smoke contract for a sparse discrete backend

Frozen before any sparse fitted objective exists. Nothing here may be revised
once this study is merged.

## What this qualifies

The smoke matrix qualifies fitted dense↔sparse agreement for the bounded
binary/ordinal Matrix prototype. Layer 1 asserts evaluator equivalence at both
fitted endpoints using the already-qualified `1e-10` backend-parity tolerance.
Layer 2 asserts that independently optimized fits reach the same solution using
the package's pre-existing restart-stability definitions: relative objective
difference at most `1e-6` and `.gt_d_fit_distance()` at most `0.02`. Layer 3
requires identical numerical acceptance and predeclared rejection-stage
outcomes. The stability tolerances do not claim coordinatewise fitted-parameter
reproduction.

## What this is not

It is not the fixed-parameter reference. That study lives in
`validation-studies/discrete-sparse-reference/`, runs no outer optimizer, and
makes no claim about fitted agreement. Neither study may be used to satisfy the
other's contract.

It is not a claim about the accuracy of the first-order Laplace approximation,
about sparse categorical or joint fitting, about public backend selection, or
about performance. Storage figures are recorded as evidence, not as a claim.

## The three layers

| Layer | Requirement |
| --- | --- |
| 1 — same function | At both the dense-selected and the sparse-selected fitted parameter vectors, evaluate the dense and sparse marginal objectives at the same tight validation inner tolerance; require parity within `1e-10`. |
| 2 — same solution | Compare the independently fitted solutions: relative objective difference at most `1e-6`, and `.gt_d_fit_distance()` at most `0.02`. |
| 3 — same behaviour | Disposition and declared class match exactly. `accepted`, `rejected` and `refused` are not interchangeable and carry no tolerance. |

Layer 1 is evaluated at **both** endpoints on purpose. Agreement only at the
dense optimum would leave open that the sparse evaluator differs somewhere the
sparse optimizer actually visited.

Layer 2 reuses `stability_objective_tol = 1e-6` and
`stability_parameter_tol = 0.02`, which `gt_fit` already uses to decide whether
a restart from a different start reached the same solution.
`.gt_d_fit_distance()` compares fixed parameters on a scaled basis and compares
the decoded covariance **matrices**, not the raw Cholesky coordinates. If the
two backends agree within them, they have reached the same solution by the
package's existing standard. Anything tighter would be a new contract; anything
looser would be weaker than the package's own definition.

Layer 3 compares categorical outcomes only. Diagnostic prose, gradient values,
optimizer messages and attempt labels are measurements, not verdicts, and are
not compared.

## Panels are frozen rows, not a recipe

`panels.csv` is authoritative. `freeze-panels.R` records how those rows were
produced and is not run during qualification.

The issue #14 portability work established that `set.seed()` does not imply
bitwise identical continuous draws across architectures: the same seed produced
different `rnorm()` bytes on x86_64 and arm64, while the derived integer panel
happened to be identical. A study that regenerated its panels would therefore,
on some platforms, be comparing two backends on two different datasets. Loading
frozen rows makes the comparison "same data, same controls, different backend".

It also makes the negative controls literal: each reuses an accepted panel by
name, so the outcome is attributable to the one control that changed.

## What the dense baseline does and does not freeze

`dense-baseline.csv` marks every entry as `class` or `provenance`.

`class` entries are the cross-platform contract: disposition, panel, row count,
acceptance failure set, and the optimizer, acceptance, inner-convergence and
tight-mode stage states. A future run on any platform must reproduce them.

`provenance` entries are fitted coordinates, objectives and timings recorded
from one machine on one day. They are review material. They are **not** a
golden vector, and a future platform is not required to reproduce them. A fit
is reached by an optimizer taking finite-difference gradients, and a `1e-15`
objective difference perturbs an FD gradient by roughly `1e-15/h` with
`h ~ 1e-8`, so two backends can follow measurably different paths to the same
optimum. Requiring reproduction of these coordinates would assert precisely
what the layered tolerances exist to avoid asserting.

Sparse qualification therefore compares a dense fit and a sparse fit produced
together in the same run, never a sparse fit against these recorded numbers.

## Cases

Seven accepted, two rejected, one refused.

| Case | Panel | Structure | Disposition |
| --- | --- | --- | --- |
| `fit_binary_logit_single_source` | 300 rows | binary logit, one source | accepted |
| `fit_binary_probit_crossed` | 300 rows | binary probit, crossed | accepted |
| `fit_binary_logit_zero_source` | 300 rows | binary logit, crossed, zero-variance source | accepted |
| `fit_ordinal_logit_crossed` | 300 rows | ordinal logit, crossed, 3 categories | accepted |
| `fit_ordinal_probit_crossed` | 300 rows | ordinal probit, crossed, 3 categories | accepted |
| `fit_ordinal_logit_tail_mass` | 400 rows | ordinal logit, crossed, 5 categories with 5% tails | accepted |
| `fit_binary_probit_fixed_covariance` | 300 rows | binary probit, crossed, fixed covariance | accepted |
| `refuse_truncated_inner_solve` | reuses `fit_binary_probit_crossed` | `inner_maxit = 1` | refused |
| `reject_truncated_outer_optimizer` | reuses `fit_ordinal_logit_crossed` | `maxit = 1` | rejected |
| `reject_zero_restart_budget` | reuses `fit_binary_logit_single_source` | `alternative_starts = 0` | rejected |

Panels are an order of magnitude larger than the fixed-parameter fixtures,
enough to estimate variance components, and far below `max_observations`
(1200) and `max_random_dimension` (200) so dense is unquestionably available
as the reference. The near-dense-limit overlap band is a #4 obligation and is
deliberately not attempted here.

Ordinal categories are cut at predeclared empirical quantiles of the simulated
latent score rather than at fixed population thresholds, which guarantees every
category is occupied. The proportions are frozen before any sparse work.

## Why the inner negative control is a refusal

Declared as `rejected` in the first draft. Dense behaviour, measured before any
sparse work, showed that was the wrong declaration:

    inner_maxit 1-2   refused, the conditional mode is unsolvable everywhere
    inner_maxit 3     rejected, tight_final_mode_unavailable
    inner_maxit 4-6   rejected, but inner_gradient is 1e-14 to 1e-16 and
                      tight_final_mode is TRUE, so the inner solve has in fact
                      converged and the rejection is an outer or stability
                      failure rather than a conditional-mode one
    inner_maxit 8     accepted

The conditional-mode rejection band is one iteration wide, and at that single
value `inner_converged` passes by 16% (`8.37e-07` against `1e-06`). A contract
pinned there would sit against the refusal boundary with no margin, so a small
platform difference could change the outcome class. The refusal fails by
several orders of magnitude and is two iterations wide.

The refusal is also the stronger control: a sparse backend that returned a fit
where dense refuses to produce one is exactly what these cases exist to catch.
Fitted rejection parity is still covered, by the truncated outer optimizer and
the zero restart budget.

Measuring the narrow rejection band belongs in #4.

## Storage evidence

Structural facts only, recorded per case and per backend. No speedup or memory
factor is asserted; performance claims wait for profiling and #8.

    sparse W remains sparse
    nnz(W), and the dense element count for comparison
    nnz(H)
    factor entries and fill
    random dimension
    no factor densification

## What counts as a pass

All ten cases meet their declared disposition and class; Layer 1 within
`1e-10`; Layer 2 within the stability tolerances; Layer 3 exact; storage
evidence recorded; the separate fixed-parameter reference still byte-identical;
green on Linux, Windows and macOS.

## A note on the fixed-parameter reference's prose

That study's `PROTOCOL.md` states that fitted work requires #14 to be fully
resolved. #14 remains unresolved. The bounded-risk decision recorded on that
issue — no recurrence in 30 instrumented exact-tree PR-context executions —
unblocks fitted engineering while leaving #14 open and in the milestone. That
decision is documented here rather than by editing the frozen reference study.
