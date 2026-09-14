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

### Action versions, and why they are behind

The runners report that Node 20 is deprecated and already run these actions on
Node 24, so nothing here is broken; the pins are behind the current majors:

| Action | Pinned | Current major |
|---|---|---|
| `actions/checkout` | v4 | v7 |
| `actions/setup-python` | v5 | v7 |
| `actions/cache` | v4 | v6 |
| `actions/upload-artifact` | v4 | v7 |
| `actions/download-artifact` | v4 | v8 |
| `r-lib/actions/*` | v2 | v2 |

This is a deliberate deferral, recorded here so that it stays a decision rather
than becoming drift. Bumping five actions across three workflows means five new
reviewed SHAs and, for the artifact pair, behaviour changes across several
majors at once — worth doing carefully, and not worth doing between a green
matrix and a release. `tests/test_workflow_contract.py` pins both the SHA and
the expected major, so an upgrade cannot happen by accident: update the pins,
the majors in that test, and the table above together, and record the evidence.

Do it before the Node 20 runtime is actually withdrawn, not after.

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
