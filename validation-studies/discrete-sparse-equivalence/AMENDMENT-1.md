# Amendment 1: stage 3 rules

Specified on 2026-10-26, after the original frozen study was executed and
recorded (`results/README.md`), and before any execution under these rules.
Like the protocol, it is frozen when merged. Its execution is reported
separately as "Amendment 1". The original record, failures included, is
retained unchanged, and neither record replaces the other.

## Why an amendment

The original record does not pass. Five stage 3 quantity checks exceeded their
tolerances, in three case/platform outcomes, and the investigation traces each
to how a rule was built rather than to either backend:

1. **Linux, C08 and C13, mode score at the common latent point.** The score is
   a sum over up to 1,080 rows with entries of size 92 to 146. Dense (OpenBLAS)
   and sparse arithmetic add the terms in different orders, so the results
   differ at the level of rounding: 2.9e-15 to 1.6e-14 relative. The frozen rule
   is an absolute 1e-13. Its value came from a macOS calibration in which the
   two sums were bit-identical, so the floor of the calibration set it. A fixed
   absolute limit does not bound summation error, which grows with the number
   and size of the terms.
2. **macOS, C13, solved quantities.** Stage 3 compares the mode, log determinant
   and marginal objective as each backend's own solve returns them. The
   production inner tolerance accepts any mode whose gradient is within 10 ×
   1e-7. The dense solve stopped at gradient 7.4e-8 and the sparse at 1e-14, so
   the two compared quantities came from two different points. The frozen
   tolerances (1e-13 relative for the mode, 1e-10 for the objective) are
   calibrated for identical arithmetic at one point. They are not calibrated
   for two acceptable stopping points of an iterative solver.

The amendment replaces those rules with bounds derived from numerical analysis.
No bound is fitted to a value observed in the scored record. While the rules
were developed, only the non-scoring calibration panels were evaluated.

## What changes

Only stage 3, and only the quantities listed here. Every other stage, rule,
tolerance, case, fixture, fixed point, control, injection, transform and
reference stays as frozen.

### A1. The mode score at the common latent point

The score at latent zero is s = W′g. At latent zero both predictors equal
the fixed baseline, and A1 requires them to be identical (it is not measured
otherwise). The two backends then share the kernel gradient g, and W is
identical in both (stage 2). A sum
x′y of n terms computed in floating point, in any order and with or without
fused multiply-add, satisfies

    |fl(x′y) − x′y| ≤ γ_n Σ_i |x_i y_i|,   γ_n = n u / (1 − n u),   u = 2^-53

(Higham, *Accuracy and Stability of Numerical Algorithms*, 2nd ed., §3.1).
Hence, for each coordinate j of the score, with n the number of rows of W,

    |s_dense,j − s_sparse,j| ≤ 2 γ_n Σ_i |W_ij g_i|.

The rule is that this holds for every coordinate. The recorded measurement is
the largest ratio of |s_dense,j − s_sparse,j| to its bound, and the tolerance
is 1. If the shared-predictor precondition fails, the quantity is not measured.

The Hessian at the common latent point is also a sum, but its frozen rule (1e-13
symmetric relative) did not fail and is not changed.

### A2. The solved quantities

The conditional objective is f(u) = ℓ(baseline + W u) + ‖u‖²/2. For binary and
ordinal outcomes with logit or probit links, ℓ is convex in the predictor,
because those category probabilities are log-concave in it. The Hessian of f
is therefore at least the identity, so f is strongly convex with modulus 1. For
any point u with true gradient ∇f(u), the distance to the exact mode u* then
satisfies ‖u − u*‖₂ ≤ ‖∇f(u)‖₂.

**A2a: the conditional mode.** Each backend reports g_b = ‖∇f(u_b)‖_∞, the
gradient at its returned mode u_b, computed in floating point. Write e_b for
that computation's rounding bound, γ_{n+1} max_j (Σ_i |W_ij ĝ_i| + |u_b,j|)
from the A1 argument, where ĝ is the kernel gradient at u_b. With d the
random dimension,

    ‖u_dense − u_sparse‖_∞ ≤ √d (g_dense + e_dense + g_sparse + e_sparse).

This is measured in the frozen metric for the mode, the symmetric relative
difference with floor 1, so the bound is divided by the same denominator,
1 + max(‖u_dense‖_∞, ‖u_sparse‖_∞). The recorded measurement is the ratio of
the observed difference to that bound, and the tolerance is 1. This tests that
the two solves agree as closely as their own convergence guarantees. It is
not a test of identical arithmetic.

**A2b: the arithmetic at a common mode.** At each of the two returned modes,
m = u_dense and then m = u_sparse, each backend evaluates three quantities with
its own design matrix and factorization:
- the conditional objective ℓ(baseline + W m) + ‖m‖²/2;
- the log determinant of I + W′C(m)W;
- the marginal objective, the first plus half the second.

The dense and sparse values are compared under the **frozen** metrics and
tolerances: the inherited absolute 1e-10 for the conditional and marginal
objectives, and the calibrated 1000 · d · eps for the log determinant. Each
quantity's measurement is the larger of its two values, one per common mode.
This keeps the frozen arithmetic standard while comparing the backends at the
same point.

The original "as produced" comparisons of the solved quantities are still
computed. They are recorded in `detail.csv` for transparency, and are not used
in the verdict.

## Execution and reporting

1. **Implementation.** `amendment-1-impl.R` replaces only the stage 3 judgment.
   It is sourced after `equivalence-runner-impl.R`, whose rulers it does not
   redefine. `run-equivalence-amendment-1.R` is the launcher. It verifies the
   frozen sources, the calibrated tolerances and both implementation files, as
   the frozen launcher does.
2. **Before execution.** Merged after review; until then no scored case is
   evaluated under these rules. The rules need no new calibration: A1 and A2a
   are a-priori bounds, and A2b uses the frozen tolerances. The
   implementation's exercise on the non-scoring calibration panels, on macOS
   and on Linux, is reported in its review.
3. **Execution.** From the merged commit, on macOS and in the offline Linux
   container, with one numerical thread, into `results-amendment-1/<platform>/`.
4. **Reporting.** In its own change, labelled "Amendment 1", alongside the
   unchanged original record. Any failure under these rules is recorded as
   such; a further change would need a further amendment.

## What this amendment does not do

It does not:
- loosen any stage 1, 2, 4, 5, 6 or 7 rule;
- change any arithmetic tolerance used at a common point;
- add or remove cases;
- change the injections, so N1 and N6 may again not produce their conditions;
- address approximation accuracy, sparse categorical or joint fitting, public
  backend selection or performance.

A pass under this amendment means the two backends agree within their solvers'
own convergence guarantees and to frozen arithmetic precision at common
points. It does not mean the original frozen study passed.
