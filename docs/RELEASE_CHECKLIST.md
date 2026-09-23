# Release correspondence

`artifacts/manifest.json` identifies the package version, the source commit
that built it, the hashes of the archive and reference manual, and whether the
bundle is only `prepared` locally or actually `published`. It is the release
identity; a later source-only commit does not rebuild or silently replace those
files.

README and NEWS are package source files. Their marked summaries identify the
**source version** and link the repository manifest and releases page, without
embedding a changing `prepared`/`published` state. The `artifacts/` and `docs/`
directories are excluded from the archive. Publication updates those repository
records; it does not edit the source files or rebuild the checked archive.
Historical releases retain their original summaries and bytes, and the verifier
continues to accept that legacy format.

1. Set the release version in DESCRIPTION and the publication-neutral `Source
   version` summaries in README and NEWS. Finish the release notes and commit
   the source files. Fetch tags before preparation. An explicitly labelled
   `.9000` development checkout may retain the preceding release bundle.
2. Prepare from that clean source commit:

   ```sh
   python3 scripts/prepare_release.py
   ```

   The script builds into temporary staging, verifies archive correspondence
   with source and release identity, runs source validation, and audits
   public content before copying the bundle into `artifacts/`. Source validation
   uses the staged manifest, so the previous committed bundle cannot falsely
   block a new release version. It never rewrites README or NEWS, tags, pushes,
   uploads, or submits. `--dry-run DIR` must point outside the checkout and also
   verifies the staged bundle; `--skip-validation` skips only the source suite,
   never archive integrity or release identity. Existing version tags or a
   published manifest for that version block rebuilding before any build starts.
   `--state published` is rejected even for a rehearsal.

   To make the archive in the manifest the very archive the candidate workflow
   checked, run that workflow on the source commit first, download its
   `cran-candidate-checked-<commit>` artifact, and prepare from it:

   ```sh
   python3 scripts/prepare_release.py --from-checked-candidate /path/to/cran-candidate-checked
   ```

   The archive is copied unchanged after its manifest is checked against this
   package, version and commit and its check report is required to record a
   successful R-devel check of those exact bytes; the manual is still built
   here; every other verification runs as before. The manifest records which origin the archive
   had under `archive_provenance`.
3. Review the printed source commit, files, hashes and checks. Retain the exact
   archive checked on each platform; a rebuilt candidate has its own identity,
   which is why the previous step can adopt the checked one. If manual building
   fell back to plain `R CMD Rd2pdf`, record whether the overfull-box gate ran.
   The 0.0.6 CRAN submission was returned for README file links; the next
   submission is the archive this checklist prepares, submitted only after
   publication.
4. Commit the checked bundle in `artifacts/` after its recorded source commit.
   The archive's README/NEWS bytes must still equal that source commit. Run the
   relevant artifact installation and release checks before publication.
5. At publication, set `"release_state": "published"` in
   `artifacts/manifest.json`, update `artifacts/README.md`, and commit that
   excluded metadata. Create a **new** version tag on that commit, then verify
   its DESCRIPTION and manifest:

   ```sh
   python3 scripts/check_committed_artifact.py --verify-only \
     --check-release-identity --release-tag v<version>
   ```

   Replace the placeholder with the new version. The manifest requires its tag;
   the short metadata-commit/tag transition is not a completed publication.
6. Future GitHub releases use the enabled immutable-release setting. Create a
   draft, attach the verified archive, manual and manifest, compare their
   hashes and sizes, and publish only after the complete draft is checked.
   Publishing locks the release assets and tag. Do not build or replace files
   during upload. After publication, use `gh release verify v<version>` and
   `gh release verify-asset v<version> <asset-path>` for each asset, alongside
   the manifest comparisons. See [repository policy](REPOSITORY_POLICY.md).

Never move a release tag or replace an existing published asset. The setting
applies to future releases; the existing 0.1.0 release remains unmodified and
was not retroactively made immutable.

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
