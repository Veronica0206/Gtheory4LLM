# Development status

Current release and development state. Version history is in [NEWS.md](../NEWS.md),
planned work is in [the roadmap](ROADMAP.md), and implementation boundaries are
in [limitations](LIMITATIONS.md).

## Release state

| Fact | Value |
|---|---|
| Checkout version | `0.4.0`, a release version whose bundle has not been prepared. The development line was versioned `0.3.0.9000` and then `0.4.0.9000`; no 0.3.0 was released |
| Bundle in `artifacts/` | `0.2.0`, **published**; the archive is the exact candidate built from the recorded release source commit and checked with R-devel, adopted unchanged. It is retained independently of the newer development sources; earlier release files and tags are unchanged |
| Bundle source commit | `a4dd59c50f54dd951bba89d86d4c32a3699a5597`, recorded in the manifest |
| `v0.1.0` tag | Publication commit `2332d40` |
| `v0.2.0` tag | The publication commit, which flips the manifest to published and rewrites `artifacts/README.md` |
| GitHub release | [v0.2.0](https://github.com/Veronica0206/Gtheory4LLM/releases/tag/v0.2.0), immutable, with three assets: archive, manual and manifest; no development release is published |
| Branch protection | Configured on `main`; the authenticated policy verifier passed |
| Release-tag protection | Active for `v*`; updates and deletions blocked with no bypass actors |
| Future GitHub releases | Immutable releases enabled; existing 0.1.0 remains `immutable: false` |
| CRAN | `0.2.0`, published by CRAN on 2026-10-04. CRAN's record carries the `Packaged` stamp of the archive in `artifacts/`; the file CRAN distributes has its own checksum, so the manifest's SHA-256 identifies the GitHub release asset rather than CRAN's copy. The earlier `0.0.6` submission had been returned for two README links (`scripts/VALIDATION.md`, `LICENSE`) to files the archive does not ship. CRAN's additional check on R built without long double (`noLD`) reports an ERROR for `0.2.0` in `tests/package-discrete-safety.R`, and CRAN asked for a correction before 2026-10-26. `0.4.0` carries that correction; it has not been submitted |

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

### 0.2.0 candidate

All three workflows passed at the 0.2.0 source commit `a4dd59c`:
[exact CRAN candidate readiness](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/35814612564),
[full numerical validation](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/35814607691) and
[R and platform compatibility](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/35814607707).
The readiness workflow built the candidate with R 4.6.1 and checked that
exact archive with R-devel 4.7.0 under `R CMD check --as-cran`: zero errors,
zero warnings and the single expected new-submission NOTE, with the PDF manual
generated. The archive in `artifacts/`, SHA-256 `910286884cbb…`, is that checked
file, adopted unchanged by `scripts/prepare_release.py --from-checked-candidate`
after its check report was verified, rather than rebuilt; the manifest records
its origin and the R versions that built and checked it. So, unlike 0.1.0
below, the prepared archive and the R-devel-checked archive are one identity.
The local preparation additionally passed archive correspondence with the
source commit, the full source validation scope with the staged manifest, the
manual's overfull-box gate and the public-content audit; the committed bundle
then passed the artifact integrity and fresh-library install and smoke checks.

### 0.1.0 publication

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

The development interface now adds bounded panel-audit examples,
outcome-information profiles, tabular coefficient exports, supplied-grid target
screening and base-R figures. Portable offline HTML reports collect model
context, diagnostics and results while excluding observations and group labels. The installed synthetic workflow demonstrates them; the
[visualization guide](VISUALIZATION.md) describes their scope. A separate
[40-fit binary/ordinal pilot](../validation-studies/discrete-030-usability-pilot/README.md)
records unstable rare-outcome recovery despite high numerical acceptance.
These additions do not make the private sparse implementation public or
complete the full native-panel qualification benchmark.

- Keep release/version prose and installation instructions consistent with the
  published release and development checkout.
- Maintain release-tag protection and update pinned Actions to supported
  runtimes through a separate maintenance change.
- Finish qualifying the private sparse discrete backend for 0.5.0 against
  the release gates in [the roadmap](ROADMAP.md); 0.2.0 ships it only as a
  private prototype. On the development line since 0.2.0 (see the top of
  [NEWS.md](../NEWS.md)): the sparse solver enforces the dense validity
  invariants, failed evaluations are recorded with their own evidence and can
  be captured as specimens, calibration case K05 is corrected before any
  calibration run, and the retained 2,400-row scale-risk specimen is
  characterised as inner-budget non-convergence rather than a validity
  defect. Still open, in order: the equivalence measurement layer,
  calibration, the qualification runner, public backend selection with a
  shared resource contract, and the full native-panel benchmark.

## Scientific scope

The package remains a research beta. Its statistical pilots are reproducible
but small; they do not establish broad recovery or coverage guarantees. Their
scope and limits are recorded in [validation scope](VALIDATION_SCOPE.md).

The current implementation uses balanced coded panels and a dense small-model
discrete engine. It does not implement discrete uncertainty, unbalanced-panel coefficients,
joint Gaussian-discrete fitting, or scalar nominal reliability. The complete
boundaries are in [limitations](LIMITATIONS.md). Repository governance and
passing package checks do not expand that statistical scope.
