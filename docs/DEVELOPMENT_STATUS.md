# Development status

Current release and development state. Version history is in [NEWS.md](../NEWS.md),
planned work is in [the roadmap](ROADMAP.md), and implementation boundaries are
in [limitations](LIMITATIONS.md).

## Release state

| Fact | Value |
|---|---|
| Checkout version | `0.1.0.9000` (development) |
| Bundle in `artifacts/` | `0.1.0`, **published** |
| Bundle source commit | `1068ca8aa7211eaee1e3f5329e14517ff49cc0e0`, recorded in the manifest |
| `v0.1.0` tag | Publication commit `2332d40` |
| GitHub release | [v0.1.0](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.1.0), with checksummed archive and manual |
| Branch protection | Configured on `main`; the authenticated policy verifier passed |
| Release-tag protection | Active for `v*`; updates and deletions blocked with no bypass actors |
| CRAN | `0.0.6` submitted and confirmed, awaiting a decision; no subsequent submission |

The checkout, published bundle, GitHub release and CRAN submission are separate
states. Development changes do not rebuild the published archive or move its
tag. [The manifest](../artifacts/manifest.json) identifies the exact source and
SHA-256 hashes for both published files.

`scripts/check_committed_artifact.py --check-release-identity` checks the
checkout/release version relationship and publication claims against the tag.
The artifact check compares the archive with its recorded source commit, not
with later development changes.

## Validation evidence

All three publication-commit workflows passed at `2332d40`: compatibility,
locked-environment full validation, and CRAN candidate readiness. The release
assets match the committed manifest. Branch protection is checked separately
from workflow results; its required state and verifier are documented in
[repository policy](REPOSITORY_POLICY.md).

| Check | Verified state |
|---|---|
| R test suite, source and installed | Passed for the release sources |
| Python regression suite | Passed for the release sources |
| Release identity, committed-artifact integrity and public-content audit | Passed for the published bundle |
| Reference manual | Built with no overfull boxes |
| Hosted current-R / R-devel candidate check | Passed for a separately rebuilt candidate, including the manual |
| Locked-environment full validation | Passed at the publication commit |

**The successful R-devel candidate check did not use the published archive.**
The published archive's SHA-256 starts with `401a10b0`; the checked candidate's
starts with `38430d96`. Their R code, tests and datasets match, but documentation
and generated build files differ. An R-devel result for the candidate must not
be attributed to the published file. The exact published archive still needs a
separate R-devel check before such a claim is made.

A skipped check is not a passing check. `scripts/run_validation.py` records
which checks actually ran and names missing tools. Results for a previous
commit also do not establish that a later development checkout has passed.

## Current development priorities

- Keep release/version prose and installation instructions consistent with the
  published release and development checkout.
- Maintain release-tag protection and update pinned Actions to supported
  runtimes through a separate maintenance change.
- Check the exact published archive in R-devel. Keep the confirmed, pending
  0.0.6 CRAN submission separate from this validation work.
- Begin the sparse discrete backend against the existing dense reference and
  characterization tests, as described in [the roadmap](ROADMAP.md).

## Scientific scope

The package remains a research beta. Its statistical pilots are reproducible
but small; they do not establish broad recovery or coverage guarantees. Their
scope and limits are recorded in [validation scope](VALIDATION_SCOPE.md).

The current implementation uses balanced coded panels and a dense small-model
discrete engine. It does not implement discrete uncertainty, unbalanced-panel coefficients,
joint Gaussian-discrete fitting, or scalar nominal reliability. The complete
boundaries are in [limitations](LIMITATIONS.md). Repository governance and
passing package checks do not expand that statistical scope.
