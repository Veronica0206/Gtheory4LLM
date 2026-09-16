# Dense/sparse backend equivalence qualification

Frozen before any qualification case is executed. Nothing here may be revised
once this study is merged. Results arrive in a later change against this
merged, frozen commit; that ordering is what makes "frozen before execution"
auditable rather than a claim in prose.

## What this qualifies

Whether the sparse marginal evaluator reproduces the dense reference across the
supported binary/ordinal envelope: the same prepared design, the same
fixed-parameter quantities, the same fitted solutions and dispositions, the
same behaviour under permutation, and the same refusals.

## What this is not

It is not a claim about the accuracy of the first-order Laplace approximation.
Agreement between two implementations of the same approximation is not evidence
that the approximation is adequate; that question is answered only by the
independent references in stage 7, which are reported in their own columns.

It is not the fixed-parameter reference study
(`validation-studies/discrete-sparse-reference/`) nor the fitted smoke contract
(`validation-studies/discrete-sparse-fitted-smoke/`). Neither may be used to
satisfy this study's contract, and this study may not be used to satisfy
theirs.

It makes no claim about unbalanced designs, missing-cell estimation, sparse
categorical fitting, sparse joint outcomes, discrete uncertainty, public
backend selection, or performance.

## Frozen classification rules

**R1.** A case in which either backend fails an applicable backend-neutral
numerical-validity invariant is classified as a **backend numerical-validity
event**. It is not scored as a dense-sparse equivalence failure.

**R2.** Dense defines the established model semantics and default
implementation, but neither backend is an unconditional numerical oracle.
Cross-backend disagreement is interpreted only after both applicable
backend-local validity gates pass.

**R3.** `unsupported` is a support-envelope result. It is not a numerical pass,
not a numerical failure, and not an equivalence result, and it never enters a
pass denominator.

R1 and R2 exist because of issue #14. There the dense path produced the invalid
result, a native Cholesky returned successfully with a factor that did not
solve its own system, and the only thing that established which side was wrong
was a backend-neutral invariant rather than a comparison between the two.

## Stage ordering

Each stage runs only on cases that survived the previous one.

1. **Backend-neutral numerical-validity gate.** Each implementation
   independently satisfies its applicable invariants: the frozen solve-validity
   condition `eta <= 32 * random_dimension * eps`, factor and log-determinant
   validity, a finite conditional mode, a finite objective. Nothing is compared
   across backends here. A failure at this stage is an R1 event and the case
   stops.
2. **Prepared-design identity.** Identical prepared row, group and category
   mappings, parameter labels, bounds, and covariance matrices.
3. **Fixed-parameter equivalence.** Predictor, conditional objective, mode
   score, Hessian, mode, log determinant, and marginal negative log likelihood
   including constants.
4. **Fitted equivalence and disposition.** Source covariances, thresholds and
   intercepts, latent binary/ordinal G and Phi where defined, and the
   acceptance decision. `accepted`, `rejected` and `refused` must agree as
   dispositions, not merely as pass/fail.
5. **Equivariance, permutation, repeatability.** Row, group and outcome
   permutations; named covariance reordering; categorical reference
   transformation; repeated deterministic evaluation. This is a within-backend
   invariance question and carries its own tolerance, not dense/sparse parity.
6. **Negative and rejection conditions.** Failed mode solves, nonfinite probes,
   artificial-bound contact, zero restart budget, truncated optimizers, and
   malformed-factor refusal. A sparse path must not convert any of these into
   an accepted fit.
7. **Independent approximation references.** Dense-small adaptive integration,
   and `glmer`/`clmm` for identical models only. Mandatory to run where
   predeclared; they do NOT gate dense-sparse equivalence. Recorded in the
   `approximation_reference` and `approximation_error` columns. If dense and
   sparse agree while first-order Laplace differs materially from an
   independent reference, that is an approximation finding, not a
   sparse-equivalence failure; and backend parity never establishes
   approximation adequacy.

## Case matrix

Defined in `cases.R`: fifteen core cases, six negative overlays applied to
named bases, five equivariance/repeatability transforms on selected bases.
Chosen for coverage rather than as a Cartesian product.

Coverage: both binary links; both ordinal links; single, crossed (two and
three sources) and parent-scoped nested structures; diagonal, unstructured,
fixed, exact-zero-capable and log-Cholesky covariance coordinates; small,
medium and near-dense-limit geometries; and ordinal tail mass.

`sparse_supported` is frozen in the manifest rather than discovered during
execution. `.gt_d_sparse_hessian()` explicitly refuses categorical curvature,
and sparse joint outcomes are outside the 0.2 envelope, so C14 and C15 are
recorded `unsupported` under rule R3. They appear in the matrix rather than
being omitted, so the support boundary is visible in the record.

Fixtures are built arithmetically with no random number generation. `rnorm`
after a fixed seed is not bit-reproducible across architectures, so a seeded
fixture would be a different matrix on arm64 than on x86_64 and could not
separate an implementation difference from a fixture difference. Panels are
asserted non-degenerate at construction: a panel whose objects all share one
mean sits at the zero-variance boundary and qualifies nothing.

## Tolerances

Set before any result is recorded, and never widened afterwards. A disagreement
above tolerance is investigated or labelled unsupported; it is never
accommodated.

Inherited unchanged from already-frozen contracts:

    marginal negative log likelihood        1e-10                 (#3 / #30)
    conditional objective                   1e-10                 (#3 / #30)
    fitted objective relative agreement     1e-6
    fitted parameter distance               0.02
    solve-validity invariant                32 * random_dimension * eps  (#34)

**Where the inherited 1e-10 applies, and where it does not.** The existing
parity contract covers the marginal negative log likelihood and the conditional
objective at fixed parameters, which is what #3 and #30 qualified. It is not
extended to every stage 3 quantity. The mode score is near zero at the mode, so
a relative rule is undefined there; the log determinant is a sum whose
attainable agreement grows with dimension. The exact split is frozen in
`cases.R` as `EQ_INHERITED_PARITY` and `EQ_CALIBRATED_QUANTITIES`, so the
boundary cannot be redrawn during execution.

Established by the separate calibration phase in `CALIBRATION.md` before any
qualification case runs: the remaining stage 3 quantities, the stage 4 latent
G/Phi rule, and the stage 5 equivariance rule. Those are quantity-specific
mixed absolute/relative or normwise rules, not one blanket number.

If calibration appears to require widening an inherited limit, execution stops
and the discrepancy is investigated. The limit is not widened.

## Diagnostic work metrics

Recorded for every case and excluded from every pass/fail rule:

    inner evaluation count
    invalid evaluation count
    valid solves terminating at inner_maxit
    solve-validity failures, by reason and backend

These preserve the cold-solve scale-risk signal as an observation. Folding them
into equivalence tolerances would contaminate the tolerances and destroy the
signal. Invalid evaluations carry no `inner_iterations` field, so "terminated
at the budget" and "returned invalid" are counted separately and are not
interchangeable.

The 2,400-row cold-solve specimen stays outside this matrix. It remains
characterization evidence, not a qualification case.

## Frozen numerical choices

`cases.R` additionally freezes everything the runner would otherwise choose
after results become possible: the control settings (`EQ_CONTROL`), the three
stage 3 evaluation points and the deterministic rule that produces them
(`EQ_FIXED_POINT_LABELS`, `.eq_fixed_points`), C05's fixed source matrices
(`EQ_C05_FIXED_COVARIANCE`), C06's exact-zero coordinate (`EQ_C06_ZERO`), the
exact injection for every negative overlay (`EQ_NEGATIVE_INJECTION` — "a
saturating intercept with a large factor" is not a specification, -15 and 20
are), the case-to-reference assignment for stage 7 (`EQ_REFERENCE`), and the
scope of each transform (`EQ_TRANSFORM_SCOPE`).

**T3 is frozen as a dense-only equivariance check.** It transforms the
categorical case, which sparse does not support, so sparse is recorded
`unsupported` under rule R3 and contributes no equivalence result there. The
runner does not decide this.

Random dimensions and kernel ranks are recorded per case in
`fixture-digests.csv` and pinned by the study's test, so the near-limit cases
cannot quietly shrink: C08 is 187 and C13 is 185 against the 200 ceiling.

## Record

`results-schema.csv` defines the columns. Granularity is frozen as
**case x backend x stage x quantity**, with `row_kind` distinguishing:

    quantity          one measured difference against one tolerance
    case_disposition  the case-level accepted/rejected/refused/unsupported outcome
    validity_event    an R1 backend numerical-validity event

Stage 3 alone contributes seven quantities per backend, so a single row per
case cannot carry the result. Fixing the granularity here stops the execution
change from choosing it.

Numerical equivalence and approximation error occupy separate columns and are
never combined into a single verdict.
