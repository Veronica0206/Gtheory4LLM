# Development status

Current release and development state. Version history is in [NEWS.md](../NEWS.md),
planned work is in [the roadmap](ROADMAP.md), and implementation boundaries are
in [limitations](LIMITATIONS.md).

## Release state

| Fact | Value |
|---|---|
| Checkout version | `0.2.0` |
| Bundle in `artifacts/` | `0.2.0`, **prepared**, built from these sources; it replaces the published `0.1.0` bundle, whose release files and tag are unchanged |
| Bundle source commit | `f24af76ecdc379e2431fbb2e0063f739b6c9d903`, recorded in the manifest |
| `v0.1.0` tag | Publication commit `2332d40` |
| `v0.2.0` tag | Does not exist yet |
| GitHub release | [v0.1.0](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.1.0), with checksummed archive and manual; none yet for 0.2.0 |
| Branch protection | Configured on `main`; the authenticated policy verifier passed |
| Release-tag protection | Active for `v*`; updates and deletions blocked with no bypass actors |
| Future GitHub releases | Immutable releases enabled; existing 0.1.0 remains `immutable: false` |
| CRAN | `0.0.6` submission returned by CRAN: two README links (`scripts/VALIDATION.md`, `LICENSE`) pointed at files the archive does not ship; fixed in these sources, and 0.2.0 is the resubmission candidate |

The checkout, published bundle, GitHub release and CRAN submission are separate
states. Development changes do not rebuild the published archive or move its
tag. [The manifest](../artifacts/manifest.json) identifies the exact source and
SHA-256 hashes for both bundled files.

`scripts/check_committed_artifact.py --check-release-identity` checks the
checkout/release version relationship and manifest publication claims against the tag.
README/NEWS source summaries now link this excluded repository metadata; future
archives keep the same source prose before and after publication.
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
be attributed to the published file. No exact published-archive R-devel pass is claimed. That separate check is
deferred until the CRAN resubmission.

A skipped check is not a passing check. `scripts/run_validation.py` records
which checks actually ran and names missing tools. Results for a previous
commit also do not establish that a later development checkout has passed.

## Current development priorities

- Keep release/version prose and installation instructions consistent with the
  published release and development checkout.
- Maintain release-tag protection and update pinned Actions to supported
  runtimes through a separate maintenance change.
- Resubmit 0.2.0 to CRAN once the exact-candidate workflow has passed on the
  release sources and the bundle is published.
- Finish qualifying the private sparse discrete backend (dense/sparse
  equivalence calibration, then public dispatch) for the next minor release,
  as described in [the roadmap](ROADMAP.md); 0.2.0 ships it only as a private
  prototype.

## Scientific scope

The package remains a research beta. Its statistical pilots are reproducible
but small; they do not establish broad recovery or coverage guarantees. Their
scope and limits are recorded in [validation scope](VALIDATION_SCOPE.md).

The current implementation uses balanced coded panels and a dense small-model
discrete engine. It does not implement discrete uncertainty, unbalanced-panel coefficients,
joint Gaussian-discrete fitting, or scalar nominal reliability. The complete
boundaries are in [limitations](LIMITATIONS.md). Repository governance and
passing package checks do not expand that statistical scope.
