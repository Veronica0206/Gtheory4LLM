# Release correspondence

`artifacts/manifest.json` identifies the package version, the source commit
that built it, the hashes of the archive and reference manual, and whether the
bundle is only `prepared` locally or actually `published`. It is the release
identity; a later source-only commit does not rebuild or silently replace those
files.

A bundle stays `"release_state": "prepared"` until the version tag exists.
`scripts/check_committed_artifact.py --check-release-identity` fails in both
directions: prose calling a bundle published while no `v<version>` tag exists,
and a `prepared` claim that a tag has already made stale. Nothing may describe a
release as published before step 6 completes.

1. Update DESCRIPTION and NEWS for a release. Keep the marked release summaries
   in README and NEWS consistent with the artifact manifest, including the
   declared release state. An explicitly labelled `.9000` development checkout
   may retain the preceding release.
2. Build from a clean public source commit. Steps 2 to 4 are one command:

   ```sh
   python3 scripts/prepare_release.py
   ```

   It reads the version from DESCRIPTION and derives everything from it, runs
   the source validation scope, builds the archive and the reference manual,
   writes the checksum manifest, rewrites the marked README/NEWS blocks and the
   artifact README heading, and then verifies the bundle and audits public
   content. It stops there: it never tags, pushes, uploads, or submits. Add
   `--dry-run DIR` to rehearse into a scratch directory without touching a
   tracked file, or `--skip-validation` to re-bundle after a checked run.
   Preserve the exact candidate checked under R-devel for submission.
3. Review what it printed: the source commit, the asset names, and the tag it
   says to use. Record which platforms actually passed and whether vignettes and
   the PDF manual were built. If the manual fell back to plain `R CMD Rd2pdf`,
   the build output says so and whether the overfull-box gate ran; decide
   deliberately whether that artifact is the one to publish. Do not substitute an
   installed old package or an older workflow result for the new candidate.
4. Commit the bundle in `artifacts/` together with the updated release blocks,
   after the recorded source commit.
5. Verify integrity, version summaries, and installation:

   ```sh
   python3 scripts/run_validation.py --scope all --as-cran
   ```

6. Publish: set `"release_state": "published"` in the manifest and the marked
   README/NEWS blocks, commit that, then create the version tag on that commit.
   The tag must carry the manifest it publishes, so tag after committing the
   state change. Verify its DESCRIPTION and manifest against the published files
   (fetch tags/history if necessary):

   ```sh
   python3 scripts/check_committed_artifact.py --verify-only \
     --check-release-identity --release-tag v0.1.0
   ```

   Replace the example tag for a new release. A deliberately mismatched version,
   filename, summary, or tag must fail before publication. Upload the verified
   files unchanged; compare the hosting service's asset sizes and SHA-256 values
   with the manifest. Never move an existing release tag to hide a changed file.

## CI and review policy

All main-branch changes, ordinary pull requests, and manual dispatches trigger
candidate readiness, including vignette-, README-, and NEWS-only changes.
External Actions are pinned to reviewed full commit SHAs with their major refs
recorded in comments. Update these deliberately and retain review evidence.
Superseded runs on the same workflow/ref are cancelled to avoid duplicate work.

Before merging statistical changes, review the completed full numerical,
platform compatibility, and exact candidate jobs. Before publishing, review the
artifact and tag checks as well. Branch protection/required-check settings are a
separate repository-admin configuration; this document does not assert that
GitHub enforces them. The numerical and documentation locks pin the R packages
used by the locked validation job, with a drift check preserving the numerical
versions. Pandoc, TeX, the operating system and system libraries remain outside
these locks. The current-R candidate environment is also separate; preserve its
session metadata and the documentation tool versions used for every build.

CRAN upload, maintainer email confirmation, CRAN review, and acceptance are
separate statuses. Publishing a GitHub release establishes none of the latter.
