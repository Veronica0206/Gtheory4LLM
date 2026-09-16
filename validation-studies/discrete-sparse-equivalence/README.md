# Dense/sparse equivalence qualification

Frozen protocol and case manifest for issue #4. No qualification results are
present in this directory; they arrive in a later change made against this
merged commit.

    PROTOCOL.md          the frozen contract: rules R1-R3, stage ordering,
                         tolerances, work metrics, record definition
    CALIBRATION.md       the separate non-scoring phase that establishes the
                         three not-yet-frozen tolerance rules
    cases.R              the frozen case manifest and deterministic fixtures
    freeze-fixtures.R    generates fixture-digests.csv and source-hashes.csv
    run-equivalence.R    the runner; executes nothing until calibration is
                         frozen
    results-schema.csv   column definition for the qualification record,
                         header only

Read PROTOCOL.md first. The two rules that matter most are R1, that a validity
failure is not an equivalence failure, and R2, that dense is the semantic
reference rather than an unconditional numerical oracle.
