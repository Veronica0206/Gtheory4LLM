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
after results become possible.

`EQ_CONTROL` is the CURRENT PRODUCTION NUMERICAL POLICY, field for field, not a
more generous budget. A larger inner or outer budget, or an extra restart, can
turn a default rejection into an accepted result, which is the disposition
change this study exists to detect rather than engineer away.
`EQ_CHARACTERIZATION_CONTROL` exists for separately recorded evidence only and
never produces a qualification verdict.

`EQ_COVARIANCE_PROFILE` maps the manifest's covariance column onto the actual
production arguments. `covariance=` accepts only "diagonal" or "unstructured",
the parameterization is a separate control, and "auto" resolves a q = 1 model to
"variance" -- so C08 and C13 would never exercise log-Cholesky coordinates if
that mapping were left to the runner.

`.eq_fixed_points()` is bounds-aware. Variance coordinates have a lower bound of
exactly zero and start at 0.16, so an unclamped displacement would leave every
such coordinate out of bounds, not merely a declared zero. Points are clamped
strictly inside the declared bounds, because sitting exactly on a bound is
artificial-bound contact and that is overlay N6's job. Coordinates named in
`EQ_ZERO_SOURCES` stay exactly zero at all three points.

Also frozen: C05's fixed source matrices (`EQ_C05_FIXED_COVARIANCE`), the exact
injection for every negative overlay (`EQ_NEGATIVE_INJECTION` -- "a saturating
intercept with a large factor" is not a specification, -15 and 20 are), the
stage 7 case-to-reference assignment (`EQ_REFERENCE`) together with its
quadrature settings (`EQ_REFERENCE_SETTINGS`, since glmer and clmm both default
to nAGQ = 1, which is itself Laplace and would not be an independent
higher-accuracy reference), the scope of each transform
(`EQ_TRANSFORM_SCOPE`), and the exact transformation each applies
(`EQ_TRANSFORM_DETAIL`), and the family specification per case
(`.eq_families`).

**T3 is frozen as a dense-only equivariance check.** It transforms the
categorical case, which sparse does not support, so sparse is recorded
`unsupported` under rule R3 and contributes no equivalence result there. The
runner does not decide this.

Random dimensions and kernel ranks are recorded per case in
`fixture-digests.csv` and pinned by the study's test, so the near-limit cases
cannot quietly shrink: C08 is 187 and C13 is 185 against the 200 ceiling.

`random_dimension` is the PRODUCTION quantity, `sum(group levels) * prep$q`,
which is what `.gt_fit_discrete()` checks `max_random_dimension` against. The
per-latent source-level count is recorded separately as `source_levels`. The
two differ only where q > 1, which is exactly the categorical and joint rows:
C14 is 26 rather than 13, and C15 is 56 rather than 28.

## The ruler is frozen before anything measures with it

`cases.R` freezes the comparison mathematics, not only the case list.
Calibration establishes the tolerance VALUES; it does not choose the formulas
those values attach to, and neither does the later runner implementation.

**Where stage 3 is evaluated.** `EQ_STAGE3_LATENT_POINT` is exactly zero.
Predictor, conditional objective, mode score and Hessian are compared at that
same latent point in BOTH backends. Comparing them at each backend's own
conditional mode would compare two different problems and then report the
agreement as a property of the implementations. The solved quantities --
conditional mode, log determinant, marginal negative log likelihood -- are
compared as each backend produces them, which is the point of solving.

**The exact metric.** `EQ_METRIC` and `.eq_difference()` fix the formula per
quantity. Every relative form uses a SYMMETRIC denominator: scaling by one
backend's magnitude would make the ruler asymmetric in exactly the way rule R2
forbids. Every relative form carries an explicit absolute floor, so a near-zero
quantity cannot inflate the ratio. The mode score, log determinant and latent
G/Phi are absolute, and the inherited contract from #3 and #30 is recorded as
the ABSOLUTE 1e-10 difference it was actually qualified as, not as a relative
one.

**Stage 1 validity witnesses.** `EQ_VALIDITY` fixes the exact backend-local
formula and bound for each. Each is evaluated on ONE backend against algebra,
never against the other backend. All three numerical bounds use the same
scale-aware ruler already justified in #34, `32 * random_dimension * eps`: one
rule measured once, rather than three constants chosen separately. This is the
R1/R2 classification boundary, which #14 proved must not be decided after a
disagreement appears.

## The runner is a launcher

`run-equivalence.R` is frozen and contains NO comparison logic. It enforces the
ordering -- tolerances frozen, fixtures pinned, implementation present -- and
then sources `equivalence-runner-impl.R`, which is absent here and arrives in
its own separately reviewed change.

The separation is structural rather than procedural. The code that judges the
cases must be reviewable on its own before it can produce the record it
reports, and if the judging logic lived in the frozen launcher it could only be
added by editing a file this protocol says may never move. The implementation
inherits the rulers above and the calibrated values, and may redefine neither.

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
