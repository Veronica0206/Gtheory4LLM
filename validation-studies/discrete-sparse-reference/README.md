# Discrete sparse reference

Frozen fixed-parameter targets and declared rejections that a sparse
first-order-Laplace backend must reproduce. Prepared before any sparse
implementation exists, so the acceptance criterion cannot be fitted to the
thing it is meant to judge.

- `PROTOCOL.md` — what is frozen, the tolerances and where they come from, and
  what counts as a pass
- `cases.R` — the fixtures and their evaluation, shared by the generator and
  the test so the two cannot drift
- `run.R` — regenerates the frozen files
- `reference.csv` — 205 frozen quantities across 8 cases
- `rejections.csv` — 6 declared refusals, recorded as outcome classes
- `source-hashes.csv` — provenance for the files that produced them

Checked by `tests/test_discrete_reference.R`.
