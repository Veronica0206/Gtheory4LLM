# Gtheory4LLM 0.2.0 release

Release state: **published**. This 0.2.0 bundle contains the installable source
archive and reference manual. The archive is the exact candidate the readiness
workflow built from the source commit recorded in `manifest.json` and checked
with R-devel under `R CMD check --as-cran`, adopted unchanged by
`scripts/prepare_release.py --from-checked-candidate` after its check report
was verified; it was never rebuilt. The manifest records that origin, the R
versions that built and checked it, the release state, and the SHA-256
checksums, and `scripts/check_committed_artifact.py --check-release-identity`
fails if this prose and the `v0.2.0` tag disagree, in either direction.

The archive includes three publicly archived LLM annotation panels (eight
outcome sets, fifteen codings) and the installed vignette. Research manuscripts
and private working archives are excluded. Package code is GPL-3; annotation
data retain CC BY 4.0. The statistical pilots and real-data workflow remain in
the source repository, outside the installable archive.

The manual was generated locally by `scripts/build_manual.R`, which rejects
overfull boxes. Two kinds of evidence apply, and they are not the same thing.
The exact archive bytes passed the R-devel candidate check with zero errors,
zero warnings and the single expected new-submission NOTE, with the PDF manual
generated; they also passed archive correspondence with the source commit,
integrity, and a fresh-library install and smoke test, locally and in the
locked validation job on `main`. The release sources, rebuilt from the same
commit, passed the full locked numerical validation and the platform matrix
on `main`; those jobs build the package again rather than installing this
file. The evidence is linked from the
[development status](../docs/DEVELOPMENT_STATUS.md).

The GitHub release for `v0.2.0` carries three assets, unchanged: the archive,
the manual and `manifest.json`. The archive with SHA-256 `910286884cbb…` is the
file to submit to CRAN. The earlier 0.0.6 CRAN submission was returned for two
README links to files outside the archive; that is fixed in this release, and
publishing here establishes no CRAN status.

Verify integrity, source correspondence, and independent installation with:

```sh
python3 scripts/check_committed_artifact.py --check-release-identity
```

See `scripts/VALIDATION.md` for the separate source, artifact and exact candidate
checks. Historical bundles remain in their existing GitHub releases; the
`v0.0.7` and `v0.1.0` tags are unchanged.
