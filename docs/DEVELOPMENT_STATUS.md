# Development status

Where this repository is right now. Version history is in [NEWS.md](../NEWS.md);
planned work is in [the roadmap](ROADMAP.md); what the software does not do is in
[limitations](LIMITATIONS.md). This file holds none of those.

## Release state

| Fact | Value |
|---|---|
| Checkout version | `0.1.0` |
| Bundle in `artifacts/` | `0.1.0`, **prepared**, built from these sources |
| `v0.1.0` tag | Does not exist yet |
| GitHub release | None yet |
| CRAN | `0.0.6` submitted and confirmed, awaiting a decision; nothing since submitted |

These are separate states and are tracked separately.
`scripts/check_committed_artifact.py --check-release-identity` fails if the
prose and the git evidence disagree, in either direction: it refuses to call a
bundle published while no version tag exists, and refuses to call one prepared
once that tag does.

The bundle in `artifacts/` is built from the source commit its `manifest.json`
names. An earlier 0.1.0 bundle was prepared locally and never published; this
one supersedes it and is cut from the hardened sources.

## What is checked locally, and what is not

| Check | State |
|---|---|
| R test suite (source and installed) | Passing |
| Python regression suite | Passing |
| Release identity and committed-artifact integrity | Passing |
| Public-content audit | Passing |
| Reference manual | Passing, with no overfull boxes |
| Hosted current-R / R-devel candidate check | Passing in CI, including the PDF manual |
| Locked-environment full validation | Passing in CI |

A skipped check is not a passing check. `scripts/run_validation.py` records
which of these actually ran in its report, and names the missing tool when a
machine cannot render the manual.

## Outstanding before this can be called more than a research beta

These are blocking in the sense that the claims cannot be strengthened without
them, not in the sense that anything is broken.

- **Branch protection is not configured.** `main` currently has none: a direct
  push bypasses every workflow. The required state, the payload to apply it, and
  a verifier are in [repository policy](REPOSITORY_POLICY.md); applying it is a
  repository-admin action, and it has to wait until after the release commits
  and tag, or it locks the maintainer out of publishing.
- **No release is published.** No `v0.1.0` tag, no GitHub release, no checksummed
  assets hosted anywhere.
- **Scientific validation remains bounded.** The pilots are real but small. What
  they establish, and what they do not, is in
  [validation scope](VALIDATION_SCOPE.md). This is what keeps the package a
  research beta, rather than anything about the code's reliability.

## Known limits of the current implementation

Not defects, and not a to-do list — the deliberate boundaries of what is
implemented. They are listed once in [limitations](LIMITATIONS.md): balanced
coded panels only, a dense small-model discrete engine, no discrete uncertainty,
no unbalanced designs, no joint Gaussian-discrete fitting, and no scalar
coefficient for unordered categorical outcomes.

Nothing in this repository claims a sparse backend, an expanded fitting limit,
an unbalanced coefficient formula, or a discrete interval method.
