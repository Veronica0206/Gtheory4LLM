# Public validation entrypoints

Run from any directory with Python 3.10 or later. No additional Python packages
are needed. The scripts check public package sources, independent synthetic
numerical examples, and the approved real LLM annotation resources.

```sh
python3 scripts/run_validation.py --scope source
python3 scripts/run_validation.py --scope artifact
python3 scripts/run_validation.py --scope all --as-cran
```

The source scope runs independent synthetic numerical regressions, the standalone
example, an integrity check of bundled real annotation resources, a package-content
audit, and R package build/install/check. The artifact scope independently verifies
the committed archive and manual against `artifacts/manifest.json`, compares the
archive to its declared public source commit, then installs that exact archive in
a new library and runs its archived smoke test. A source-only revision can retain
a previous bundle: the report keeps source and committed-artifact results separate.
The default scope is `all`; missing release artifacts fail that scope explicitly.

Both source and artifact checks now verify release identity against the manifest:
DESCRIPTION, archive filename, current README/NEWS summaries, and the artifact
README heading must agree. Historical NEWS sections are preserved. A clearly
labelled `.9000` development checkout may retain the preceding release; a new
ordinary release version cannot silently use an older bundle. The archive still
compares to its recorded source commit, not to a later checkout. Check the local
release tag's DESCRIPTION and manifest explicitly before publication:

```sh
python3 scripts/check_committed_artifact.py --verify-only --check-release-identity --release-tag v0.1.0
```

The tag example must be updated for a new release. The ordinary gate reports
whether a tag was checked; it never treats an unfetched tag or unqueried GitHub
release as verified. See [the release checklist](../docs/RELEASE_CHECKLIST.md).


The package build now knits `vignettes/LLM-workflow.Rmd`, so the source stage
needs knitr, rmarkdown, and pandoc in addition to the numerical stack. These are
documentation build tools rather than runtime dependencies, so they are not
recorded in the numerical `renv.lock`; the locked workflow restores their
versions from the combined `scripts/dependency-locks/documentation.lock`.
Current-R compatibility and candidate checks resolve compatible CRAN versions.
When they are absent, `scripts/check_package.py` records that fact under
`vignette_toolchain`, builds with `--no-build-vignettes`, and checks with
`--ignore-vignettes`. The installed-tutorial stage of `tests/package-preflight.R`
then prints `NOT RUN` instead of passing silently, because the end-to-end
workflow really is unverified in that run.

`--as-cran` adds CRAN incoming checks. Only a CRAN incoming NOTE consisting of the
maintainer line and `New submission` is classified as expected. It remains counted
and reported. Other notes, warnings, errors, or incomplete checks fail validation.
The package check uses `--no-manual` so it does not require TeX on every platform,
and R CMD check would accept overfull boxes in any case. `scripts/build_manual.R`
is the only gate that rejects them, so the source scope runs it as the
`reference_manual` stage wherever `pdflatex` is on PATH and omits it otherwise.
The report distinguishes the two through `reference_manual_checked` and
`reference_manual_skipped_reason`, so a run that could not render the manual is
not read as one that rendered it cleanly. The locked Linux workflow installs
TinyTeX so the gate is enforced there; set `GTHEORY_MANUAL_CHECK_DIR` to keep the
rendered manual and its build log.

The locked full gate uses R 4.5.3 and the combined
[`documentation.lock`](dependency-locks/documentation.lock). This includes all
numerical dependencies from `renv.lock`, unchanged, plus the transitive R
build dependencies of knitr 1.50 and rmarkdown 2.29. The separate numerical lock
remains the source of truth for model dependencies;
`check_documentation_lock.py` rejects differences before restoration. The CI cache
includes both locks. Pandoc, TeX, the operating system and system libraries remain
platform-provided; pinning R packages alone does not promise byte-identical PDFs.
The gate reports `vignettes_built` so a skipped build is distinguishable from a
successful one. Restore into an explicit library and pass it to clean R processes:

```sh
python3 scripts/check_documentation_lock.py
Rscript --vanilla scripts/restore_validation.R /tmp/gtheory-validation-library scripts/dependency-locks/documentation.lock
python3 scripts/run_validation.py --library /tmp/gtheory-validation-library --scope all
```

To restore only numerical dependencies, omit the final lockfile argument. The
combined documentation lock was assembled from the working local R 4.5.3
vignette environment. A successful local build does not establish that a fresh
hosted restoration has passed; inspect the corresponding CI run.

The Linux workflow builds source dependencies consistently from CRAN. Explicit
renv repository overrides prevent a runner's binary repository from replacing
those sources. Compiled dependency caches contain package files rather than links
to uncached directories. The environment-restoration tool renv 1.1.5 is pinned
separately. Reports replace machine-local source, work, and home paths with
placeholders; an explicit `--output` controls summary-file creation.

The compatibility workflow is a separate, smaller source check on current R for
Windows/macOS and the minimum supported R 4.5.0 on Ubuntu 22.04. It installs
pandoc so the vignette is exercised on every platform in that matrix. It retains every installed-package test,
the independent lme4/ordinal comparisons, and selected synthetic source regressions.
It never claims a full locked-environment pass. Current Windows/macOS dependencies
are resolved from CRAN and their actual versions are reported. The minimum-R job
uses `scripts/dependency-locks/R-4.5.0.lock`, with the same dependency versions as
the main lock and R 4.5.0 selected explicitly. OpenMx 2.22.11 uses the
`Rf_isDataFrame` C API introduced in R 4.5.0 while declaring only
`R (>= 3.5.0)` itself; the package therefore declares R 4.5.0 or later on its
behalf. Nothing in this package's own R code requires R 4.5. The preflight
rejects older R before loading dependencies.

```sh
Rscript --vanilla scripts/restore_validation.R /tmp/gtheory-minimum-library scripts/dependency-locks/R-4.5.0.lock
python3 scripts/run_validation.py --scope source --compatibility --compact --library /tmp/gtheory-minimum-library
```

All three independent comparison packages—OpenMx, lme4, and ordinal—are required
in every validation mode. `--preflight-only` and `--list` provide readiness and
stage inventories without implying that numerical or artifact checks passed.
A configured CI job is not a successful run; inspect its actual result before
claiming a platform has passed.

## Exact candidate for CRAN

`cran-readiness.yml` is separate from the numerical and compatibility gates.
It covers every main push and ordinary pull request, without package-path
filters, so vignette and release-documentation edits cannot skip it. All three
workflows pin external Actions to verified commit SHAs and cancel superseded
runs on the same workflow/ref. Its
first job selects current R release, requires clean committed sources, audits
the public working tree and reachable history, verifies bundled resources, and
builds one source archive. It records the source commit, actual R version, byte
count, and SHA-256 in `candidate.json`. No pre-existing `artifacts/` bundle is
needed. The current public-resource contract is `public_llm_annotations`: eight
outcome sets with fifteen codings of the three approved real annotation panels,
each containing 21,600 rows. The tutorial and independent numerical regression
fixtures remain synthetic. Historical public-content inspection can recognize
earlier explicitly synthetic resources; current source and candidate checks still
require the approved real annotations.

The downstream job downloads that archive and manifest, verifies their source
commit and hash, then checks the archive with current R-devel using
`R CMD check --as-cran --timings`, including PDF manual generation. It does not
rebuild the candidate. Only the explicit new-submission NOTE described above is
accepted; inaccessible repository URLs or other incoming-check findings fail.
Dependencies in this readiness job are current compatible CRAN versions, recorded
with the check evidence; it does not replace the separately locked numerical gate.

After success, download `cran-candidate-checked-<commit>` for the exact checked
tarball and manifest, and `cran-candidate-check-evidence-<commit>` for full logs,
dependency versions, and test timings. A build artifact alone is not a successful
CRAN check. Preserve this tarball unchanged when making the release manifest or
submitting to CRAN. Hosted artifacts are retained for 30 days. No workflow submits
to CRAN, publishes a release, or changes repository visibility.

For the same process locally, use current R release for the first command and
current R-devel for the second, with the package dependencies and TeX installed.
Use new empty output directories outside the source checkout:

```sh
python3 scripts/cran_readiness.py build --expected-data-kind public_llm_annotations --rscript /path/to/current-release/Rscript --output-dir /tmp/gtheory-cran-candidate
python3 scripts/cran_readiness.py check --expected-data-kind public_llm_annotations --rscript /path/to/R-devel/Rscript --require-devel --candidate-dir /tmp/gtheory-cran-candidate --output-dir /tmp/gtheory-cran-checked
```

The script records the selected local R version; the maintainer must ensure the
build runtime is current. The hosted workflow resolves `release` and `devel`
automatically. Passing checks does not establish CRAN acceptance: submit the
checked file using the official form, then the maintainer must confirm the email
and respond to CRAN's review. `devtools::submit_cran()` rebuilds the package, so it
does not automatically preserve this exact candidate. See the
[CRAN submission checklist](https://cran.r-project.org/web/packages/submission_checklist.html),
[r-lib R setup](https://github.com/r-lib/actions/tree/v2/setup-r), and
[TinyTeX setup](https://github.com/r-lib/actions/tree/v2/setup-tinytex).

Configuration follows the primary [renv documentation](https://rstudio.github.io/renv/reference/config.html)
and [r-lib dependency-action documentation](https://github.com/r-lib/actions/tree/v2/setup-r-dependencies).
The required API is declared in the exact
[R 4.5.0 release header](https://svn.r-project.org/R/tags/R-4-5-0/src/include/Rinternals.h).
The Linux CRAN checks install Pandoc to check Markdown documentation as well as
package metadata; findings remain subject to the strict NOTE policy above.
