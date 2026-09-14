# Repository protection and required checks

The three workflows in `.github/workflows/` run on every push and pull request.
GitHub branch protection enforces the required checks and review on `main`,
including for administrators. The authenticated verifier confirmed the settings
below after v0.1.0 publication. This file declares the required state, how to
apply it, and how to verify it; repository files alone cannot enforce settings.

`scripts/check_branch_protection.py` compares the live settings with the table
below. It reads the GitHub API through `gh` and changes nothing.

```sh
python3 scripts/check_branch_protection.py            # report
python3 scripts/check_branch_protection.py --require  # fail if it does not match
```

The script cannot verify what it cannot reach. Without `gh`, without
authentication, or without admin rights on the repository it reports
`unverified` and says why. An unverified report is not a passing report.

## Required state for `main`

| Setting | Required value | Why |
|---|---|---|
| Required status checks | The six contexts below, strict (branch up to date) | A merge must be validated against what it will actually become |
| Required pull request reviews | 1 approving review, stale reviews dismissed | Statistical changes need a reader, not only a green check |
| Conversation resolution | Required | A raised numerical concern cannot be merged past silently |
| Force pushes | Blocked | Published release history is the artifact manifest's anchor |
| Deletions | Blocked | Tags and release commits must stay reachable |
| Linear history | Required | A release manifest names one source commit |
| Enforce for administrators | Enabled | The maintainer is the most likely person to bypass this |

### Required status check contexts

These are the job names GitHub reports, not the workflow names:

```
validate
build-release
check-devel
windows-latest / R release
macos-latest / R release
ubuntu-22.04 / R 4.5.0
```

`validate` is the locked numerical gate, `build-release` and `check-devel` are
the exact CRAN candidate jobs, and the three matrix entries are the platform
compatibility checks. If a workflow's job name or matrix changes, update this
list and the workflow in the same change: a required context that no job
produces blocks every merge, and a job whose context is not required stops
being a gate without anyone noticing.

## Applying it

Run once, as a repository administrator:

```sh
gh api -X PUT repos/Veronica0206/Gtheory4LLM/branches/main/protection \
  --input docs/branch-protection.json
```

`docs/branch-protection.json` is the exact payload for the table above. Review
it before applying; it is the settings, not a suggestion about them.

### Reviewed action runtimes

Verified against official release tags and the `action.yml` at each immutable
commit on 2026-09-15. The five GitHub-maintained actions below declare
`runs.using: node24`; upgrading the action runtime does not change our R or
Python versions, dependency locks, required job names, or candidate archives.

| Action | Reviewed version | Full commit SHA |
|---|---|---|
| `actions/checkout` | [v7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1) | `3d3c42e5aac5ba805825da76410c181273ba90b1` |
| `actions/setup-python` | [v7.0.0](https://github.com/actions/setup-python/releases/tag/v7.0.0) | `5fda3b95a4ea91299a34e894583c3862153e4b97` |
| `actions/cache` | [v6.1.0](https://github.com/actions/cache/releases/tag/v6.1.0) | `55cc8345863c7cc4c66a329aec7e433d2d1c52a9` |
| `actions/upload-artifact` | [v7.0.1](https://github.com/actions/upload-artifact/releases/tag/v7.0.1) | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` |
| `actions/download-artifact` | [v8.0.1](https://github.com/actions/download-artifact/releases/tag/v8.0.1) | `3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c` |
| `r-lib/actions/*` | [v2](https://github.com/r-lib/actions/tree/465b7d8e732ca3921382b1674c59bada9cbf3399) (unchanged) | `465b7d8e732ca3921382b1674c59bada9cbf3399` |

The R setup actions `setup-r`, `setup-tinytex`, and `setup-pandoc` already
specify Node 24 at the retained commit. `setup-r-dependencies` is a composite
action, not a Node action: its nested cache action is pinned at
[`27d5ce7f`](https://github.com/actions/cache/blob/27d5ce7f107fe9357f9df03efb73ab90386fccae/action.yml)
and its optional nested pandoc action at
[`9f58233a`](https://github.com/r-lib/actions/blob/9f58233a78a2a9fd874714be10f8bba627233339/setup-pandoc/action.yml),
both declaring Node 24. Its conditional Quarto installer is not used by the
current repository, which has no Quarto documents. This is a review of our
active actions, not a claim about every action in those upstream repositories.

Relevant upgrade behavior was reviewed:

- Checkout v7 restricts unsafe fork checkouts under `pull_request_target` and
  `workflow_run`. Our ordinary `pull_request`, push, and manual triggers remain
  supported; we do not enable its unsafe-checkout override.
- Setup-python v7 removes the `pip-install` input; we do not use it. Python
  remains 3.12. Node 24 requires runner v2.327.1 or newer; these workflows use
  GitHub-hosted runners.
- Upload-artifact v7 retains zipped, named multi-file uploads by default. We
  do not enable its new direct single-file mode. Download-artifact v8 extracts
  those archives and now fails on digest mismatches by default; this agrees
  with the candidate's independent checksum verification.
- Cache v6 changes its JavaScript module format. Existing cache keys, paths,
  and the locked dependency restore commands are unchanged.

`tests/test_workflow_contract.py` checks the exact reviewed SHAs and majors,
full source history, triggers, read-only permissions, and concurrency. Local
contract checks cannot establish runner compatibility; hosted checks must pass
on the maintenance pull request before merge. Future upgrades require another
upstream runtime/input review and corresponding pin, test, and table updates.

## Tags and releases

Release tags are immutable. A published tag is never moved, re-pointed or
deleted: `artifacts/manifest.json` names the source commit a release was built
from, and moving a tag silently invalidates every checksum comparison that
depends on it. A mistake after publication becomes a new version, never an
edited old one. See [the release checklist](RELEASE_CHECKLIST.md).

The active [Immutable release tags ruleset](https://github.com/Veronica0206/Gtheory4LLM/rules/23241962)
blocks updates and deletions of `refs/tags/v*`, with no excluded tags or bypass
actors. Creating new release tags remains allowed. The applied payload is
[`tag-protection.json`](tag-protection.json), using GitHub's
[repository rules API](https://docs.github.com/en/rest/repos/rules).

Read back the live state with:

```sh
gh api repos/Veronica0206/Gtheory4LLM/rulesets/23241962
```

Compare `target`, `enforcement`, `conditions`, `rules`, and `bypass_actors` with
the payload. The readback confirmed active enforcement and that the current
administrator cannot bypass the rule. The existing `v0.1.0` tag still points
to `2332d40109851cbce6337ecf7a3cd7c0e6f3e2b9`. This rule protects tag refs;
release asset replacement remains a maintainer action governed by the release
checklist and checksum verification.

## Committed binaries

Three kinds of binary file are committed here, deliberately:

- `inst/extdata/*.rds` — the bundled annotation tables. These are package data;
  the package cannot work without them, and `inst/extdata/manifest.csv` records
  their checksums.
- `artifacts/*.tar.gz` and `artifacts/*.pdf` — the release bundle. These are
  committed on purpose so that the archive a user installs can be compared,
  byte for byte, against the source commit that produced it. That comparison is
  the whole point of `scripts/check_committed_artifact.py`; hosting them only
  as GitHub release assets would remove the repository's own evidence.
- Nothing else. `scripts/check_public_contents.py` fails on any other binary
  content in the public tree or its reachable history.

The cost is repository size, which is accepted while the release bundle is a
few hundred kilobytes. Revisit this decision if a future release ships large
compiled artifacts; the alternative is to keep the manifest and publish the
bytes only as release assets, accepting that verification then depends on a
reachable remote.

## Who may publish

Tagging, publishing a GitHub release, and submitting to CRAN are maintainer
actions. They are not performed by any workflow in this repository, and no
workflow has write permissions: every workflow declares `permissions:
contents: read`. See [contributing](CONTRIBUTING.md) for what a contributor is
expected to run and report before proposing a merge.
