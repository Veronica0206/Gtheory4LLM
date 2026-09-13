# Development status

Where this repository is right now. Version history is in [NEWS.md](../NEWS.md);
planned work is in [the roadmap](ROADMAP.md); what the software does not do is in
[limitations](LIMITATIONS.md). This file holds none of those.

## Release state

| Fact | Value |
|---|---|
| Checkout version | `0.1.0.9000` — development, past the prepared bundle |
| Bundle in `artifacts/` | `0.1.0`, **prepared**, not published |
| `v0.1.0` tag | Does not exist |
| GitHub release | None |
| CRAN | `0.0.6` submitted and confirmed, awaiting a decision; nothing since submitted |

These are separate states and are tracked separately.
`scripts/check_committed_artifact.py --check-release-identity` fails if the
prose and the git evidence disagree, in either direction.

The bundle in `artifacts/` was built from the source commit its
`manifest.json` names. The sources have moved on since; that is what the
`.9000` version says. Building a bundle from this checkout means choosing a
release version and running `scripts/prepare_release.py`.

## What is checked locally, and what is not

| Check | State |
|---|---|
| R test suite (source and installed) | Passing |
| Python regression suite | Passing |
| Release identity and committed-artifact integrity | Passing |
| Public-content audit | Passing |
| Reference manual | **Not run here**: `makeindex` is absent, so the gate is skipped and says so |
| Hosted current-R / R-devel candidate check | **Not run**: requires the CI workflows |
| Locked-environment full validation | **Not run here**: requires the restored lock |

A skipped check is not a passing check. `scripts/run_validation.py` records
which of these actually ran in its report, and names the missing tool when it
skips the manual.

## Outstanding before this can be called more than a research beta

These are blocking in the sense that the claims cannot be strengthened without
them, not in the sense that anything is broken.

- **Branch protection is not configured.** `main` currently has none: a direct
  push bypasses every workflow. The required state, the payload to apply it, and
  a verifier are in [repository policy](REPOSITORY_POLICY.md); applying it is a
  repository-admin action.
- **No release is published.** No `v0.1.0` tag, no GitHub release, no checksummed
  assets hosted anywhere.
- **No hosted CI evidence for the current sources.** The workflows are
  configured; configuring a workflow is not a passing run.
- **Scientific validation remains bounded.** The pilots are real but small. What
  they establish, and what they do not, is in
  [validation scope](VALIDATION_SCOPE.md).
- **The reference manual has not been rebuilt** since the engine changes in this
  development series, because no machine here can render it.

## Known limits of the current implementation

Not defects, and not a to-do list — the deliberate boundaries of what is
implemented. They are listed once in [limitations](LIMITATIONS.md): balanced
coded panels only, a dense small-model discrete engine, no discrete uncertainty,
no unbalanced designs, no joint Gaussian-discrete fitting, and no scalar
coefficient for unordered categorical outcomes.

Nothing in this repository claims a sparse backend, an expanded fitting limit,
an unbalanced coefficient formula, or a discrete interval method.
