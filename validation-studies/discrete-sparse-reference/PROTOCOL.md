# Fixed-parameter reference for a sparse discrete backend

This directory freezes the numbers a sparse first-order-Laplace backend must
reproduce, and the refusals it must preserve, **before any sparse code exists**.
That ordering is the point. Tolerances chosen after seeing an implementation's
output are tolerances fitted to that implementation, and a qualification built
on them proves nothing. Issue #3 requires these targets to be prepared first
and states that they cannot be deferred.

There is no sparse implementation in this directory or in the change that
introduced it.

## Why fixed parameters

Every quantity is evaluated at a declared parameter vector. No outer optimizer
runs. This matters beyond tidiness: the outer optimizer has an open and
unresolved portability problem (#14), in which a hosted run returned its
starting values while reporting convergence. That code is not on the path to
any number recorded here, so these targets can be prepared and used while #14
is open.

The exemption is narrower than "#14 cannot reach these numbers", and it is
worth stating precisely. The outer optimizer cannot reach them. The inner
conditional-mode solver still does: the frozen mode, predictor, curvature and
objectives are all produced by it. If the portability problem turns out to live
in the inner solve rather than the outer search, it would reach these values
too. That these targets currently reproduce across Linux, macOS and Windows is
evidence for the inner solve being portable, not a proof of it.

The consequence is also a limit. Agreement here establishes that two backends
compute the same conditional problem, log determinant and marginal objective at
the same parameters. It does not establish that fitting agrees, and the fitted
comparisons in #3 and the full matrix in #4 still require #14 to be resolved
first.

## What is frozen

`reference.csv` holds one row per quantity as `case, quantity, value, kind`.
Eight cases cover binary logit and probit, ordinal logit and probit, a single
source and crossed sources, a deliberately tail-weighted ordinal panel where
threshold transforms are least stable, a source held at an exactly zero
covariance coordinate, and fixed covariance at ordinary interior values.

For each case the reference records the structure (observations, latent
dimensions, random dimension, parameter count, design-matrix shape and nonzero
count, source count), the evaluation point itself (every parameter and every
decoded covariance entry), and the conditional problem at the returned mode.

The conditional problem is recorded **coordinate-wise, not as summaries**: every
predictor entry, every mode coordinate, every penalised score entry, and the
full upper triangle of the conditional Hessian. Norms, maxima and traces are
seductive because they are compact, but two implementations that disagree
everywhere underneath can share all of them. Only elementwise targets make that
disagreement fail. The fixtures are small precisely so this is affordable:
1354 quantities across eight cases.

Scalar summaries are kept alongside, not instead: conditional objective,
marginal Laplace negative log likelihood, mode penalty, Hessian log determinant,
trace and smallest eigenvalue.

Two of those deserve care. The solver's marginal value is the response negative
log likelihood plus `sum(u^2)/2` plus `sum(log(diag(R)))`, while its
`conditional_nll` is the response term alone. Their difference is therefore the
mode penalty plus half the log determinant, **not** the log determinant, and an
earlier version of this reference recorded that difference under the latter
name. The two correction terms are now recorded separately and
`laplace_identity_residual` checks that they reconstruct the marginal value,
so the relationship is asserted rather than assumed. `hessian_asymmetry` is
recorded for the same reason: the upper triangle is frozen, so symmetry is
checked rather than taken on trust.

The zero-covariance case deserves its own note. Its design matrix keeps all
thirteen columns while its nonzero count falls to thirty. A sparse construction
that drops structurally zero columns would produce a different object with the
same likelihood, and this case exists so that difference is caught rather than
admired.

`rejections.csv` records what the dense implementation refuses and how, as an
outcome class rather than a message: `error`, `invalid`, `penalty`,
`not_converged`. Messages are wording; the contract is behaviour. A backend
that agrees on every calculation which succeeds is not qualified, and turning
an error into a penalty, or a penalty into an answer, is a behaviour change
however close the arithmetic.

`source-hashes.csv` records the digest of every file that produced these
numbers. The R sources are provenance, not assertions: they will legitimately
change as sparse work proceeds. The digest of `reference.csv` is checked, so
the provenance record cannot go stale while the reference moves.

## Tolerances, and where they come from

Declared here from the solver's own tolerances and double precision. None was
chosen by observing a disagreement.

| Kind | Relative | Absolute | Why |
|---|---|---|---|
| `exact` | — | — | Counts and shapes are combinatorial. A different integer is a different problem, not a rounding difference. |
| `algebraic` | `1e-12` | `1e-14` | The parameter vector and decoded covariance entries are a few operations from declared literals. Machine epsilon is about `2.2e-16`; this allows several orders for the decode. |
| `objective` | `1e-8` | `1e-10` | Sums over `n * q` terms and a Cholesky accumulate roughly `n * eps`, far below this. The objective is stationary at the mode, so a mode error of size `d` perturbs it by order `d^2`; with `d` at most the inner tolerance of `1e-7` that is about `1e-14`. Deliberately loose by several orders, because it must not fail on platform arithmetic. |
| `mode` | `1e-6` | `1e-6` | The mode is determined only to the inner gradient tolerance. A residual gradient `g` maps to a coordinate error near `g / lambda_min`; with `inner_tol = 1e-7` and the smallest recorded Hessian eigenvalue at least one, that is at most about `1e-7`. The absolute floor matches the relative figure because individual coordinates pass through zero, where a relative comparison says nothing. |
| `curvature` | `1e-6` | `1e-6` | Curvature is a smooth function of the predictor, so its error is first order in the mode error rather than second. Same reasoning, same floor. |
| `stationary` | — | `1e-6` | The intended value is zero, and a relative comparison against zero is meaningless. The assertion is that the residual is small, at ten times the inner tolerance. |
| `identity` | — | `1e-10` | `laplace_identity_residual` and `hessian_asymmetry` are algebraic identities, not stationarity residuals, and must not borrow the mode-gradient allowance. They reconstruct exactly up to rounding in the same sums the `objective` tolerance already covers, so they are held one order tighter than that absolute figure. Not tuned from the observed values, which sit near `1e-15`. |

The recorded stationary residuals are not uniform: the single-source case
solves to `2.2e-08` while the crossed cases reach `1e-12` to `1e-15`. That
spread is the inner tolerance showing through rather than a defect, and it is
why the mode and stationary tolerances are set from `inner_tol` instead of from
the smallest number observed.

`tests/test_discrete_reference.R` carries these tolerances as literals, so
widening one is an edit a reviewer sees rather than an argument quietly
changed.

## What counts as a pass

An implementation passes when, at every frozen evaluation point:

- every `exact` quantity matches outright;
- every other quantity is within the tolerance declared for its kind;
- every declared rejection still produces its recorded outcome class;
- no declared rejection returns an ordinary value;
- no case has been removed, and no quantity within a case has been dropped.

The test names all eight cases explicitly, so deleting a demanding one fails
rather than silently shrinking what the reference covers.

## What this does not establish

Not fitted agreement, not acceptance parity, not storage or runtime benefit,
not Laplace approximation accuracy, and not sparse qualification. Dense
agreeing with sparse says the implementations match; it says nothing about
whether first-order Laplace is adequate for the model. Those are #3's fitted
smoke matrix, #4's full qualification, and #8's benchmark, in that order.

## Regenerating

```
Rscript validation-studies/discrete-sparse-reference/run.R
```

Regenerating rewrites committed values and their digests. Do that when the
dense reference itself is deliberately changed, and say so. A sparse
implementation is made to meet these numbers; the numbers are not moved to meet
an implementation.
