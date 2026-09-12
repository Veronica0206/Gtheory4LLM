# Public validation entrypoints

Run from any directory with Python 3.10 or later. No additional Python packages
are needed. The scripts check public package sources and synthetic examples only.

```sh
python3 scripts/run_validation.py --scope source
python3 scripts/run_validation.py --scope artifact
python3 scripts/run_validation.py --scope all --as-cran
```

The source scope runs independent synthetic numerical regressions, the standalone
example, a reproducibility check of bundled synthetic resources, a package-content
audit, and R package build/install/check. The artifact scope independently verifies
the committed archive and manual against `artifacts/manifest.json`, compares the
archive to its declared public source commit, then installs that exact archive in
a new library and runs its archived smoke test. A source-only revision can retain
a previous bundle: the report keeps source and committed-artifact results separate.
The default scope is `all`; missing release artifacts fail that scope explicitly.

`--as-cran` adds CRAN incoming checks. Only a CRAN incoming NOTE consisting of the
maintainer line and `New submission` is classified as expected. It remains counted
and reported. Other notes, warnings, errors, or incomplete checks fail validation.
PDF manual generation is separate through `scripts/build_manual.R`; the automated
package check uses `--no-manual` so it does not require TeX on every platform.

The locked full gate uses R 4.5.3 and all versions in `renv.lock`. Restore into an
explicit library and pass that library to every clean R process:

```sh
Rscript --vanilla scripts/restore_validation.R /tmp/gtheory-validation-library
python3 scripts/run_validation.py --library /tmp/gtheory-validation-library --scope all
```

The Linux workflow builds source dependencies consistently from CRAN. Explicit
renv repository overrides prevent a runner's binary repository from replacing
those sources. Compiled dependency caches contain package files rather than links
to uncached directories. The environment-restoration tool renv 1.1.5 is pinned
separately. Reports replace machine-local source, work, and home paths with
placeholders; an explicit `--output` controls summary-file creation.

The compatibility workflow is a separate, smaller source check on current R for
Windows/macOS and R 4.2.3 on Ubuntu 22.04. It retains every installed-package test,
the independent lme4/ordinal comparisons, and selected synthetic source regressions.
It never claims a full locked-environment pass. Current Windows/macOS dependencies
are resolved from CRAN and their actual versions are reported. The minimum-R job
uses `scripts/dependency-locks/R-4.2.3.lock`: it preserves the locked dependency
versions except Matrix 1.6-5 and MASS 7.3-60, whose source DESCRIPTION files support
R 4.2. Later Matrix/MASS versions in the main lock require R 4.4 or newer.

```sh
Rscript --vanilla scripts/restore_validation.R /tmp/gtheory-minimum-library scripts/dependency-locks/R-4.2.3.lock
python3 scripts/run_validation.py --scope source --compatibility --compact --library /tmp/gtheory-minimum-library
```

All three independent comparison packages—OpenMx, lme4, and ordinal—are required
in every validation mode. `--preflight-only` and `--list` provide readiness and
stage inventories without implying that numerical or artifact checks passed.
A configured CI job is not a successful run; inspect its actual result before
claiming a platform has passed.

## Exact candidate for CRAN

`cran-readiness.yml` is separate from the numerical and compatibility gates. Its
first job selects current R release, requires clean committed sources, audits
the public working tree and reachable history, verifies bundled resources, and
builds one source archive. It records the source commit, actual R version, byte
count, and SHA-256 in `candidate.json`. No pre-existing `artifacts/` bundle is
needed. The default public-resource contract is synthetic; changing that contract
requires an explicit approved data decision and matching audit configuration.

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
python3 scripts/cran_readiness.py build --rscript /path/to/current-release/Rscript --output-dir /tmp/gtheory-cran-candidate
python3 scripts/cran_readiness.py check --rscript /path/to/R-devel/Rscript --require-devel --candidate-dir /tmp/gtheory-cran-candidate --output-dir /tmp/gtheory-cran-checked
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
Minimum-R version choices are recorded in the CRAN sources for
[Matrix 1.6-5](https://cran.r-project.org/src/contrib/Archive/Matrix/Matrix_1.6-5.tar.gz)
and [MASS 7.3-60](https://cran.r-project.org/src/contrib/Archive/MASS/MASS_7.3-60.tar.gz).
