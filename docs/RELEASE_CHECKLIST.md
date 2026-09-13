# Release correspondence

`artifacts/manifest.json` identifies the published package version, the source
commit that built it, and the hashes of the archive and reference manual.
It is the release identity; a later source-only commit does not rebuild or
silently replace those files.

1. Update DESCRIPTION and NEWS for a release. Keep the marked release summaries
   in README and NEWS consistent with the artifact manifest. An explicitly
   labelled `.9000` development checkout may retain the preceding release.
2. Build from a clean public source commit. Record the source commit, R version,
   archive checksum, and documentation tool versions with the build evidence.
   Preserve the exact candidate checked under R-devel for submission.
3. Run source validation and the reference-manual gate. Record which platforms
   actually passed and whether vignettes and PDF checks ran. Do not substitute
   an installed old package or an older workflow result for the new candidate.
4. Assemble the archive, manual, and checksum manifest. Update the artifact
   README heading and current artifact version in the marked README/NEWS blocks.
   Commit this bundle after the recorded source commit.
5. Verify integrity, version summaries, and installation:

   ```sh
   python3 scripts/run_validation.py --scope all --as-cran
   ```

6. Create the version tag after the bundle commit. Verify its DESCRIPTION and
   manifest against the published files (fetch tags/history if necessary):

   ```sh
   python3 scripts/check_committed_artifact.py --verify-only \
     --check-release-identity --release-tag v0.0.7
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
GitHub enforces them. The R numerical lock does not freeze the documentation
build stack or current-R candidate environment; preserve their session metadata.

CRAN upload, maintainer email confirmation, CRAN review, and acceptance are
separate statuses. Publishing a GitHub release establishes none of the latter.
