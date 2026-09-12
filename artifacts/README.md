# Local release candidate 0.0.6

This is a prepared local candidate using entirely synthetic examples. Public
distribution and CRAN submission are pending; current-release/R-devel and hosted
platform results have not yet been obtained. The current tarball was built and
checked with R 4.5.3. The CRAN-readiness workflow will build on current R release
and check the exact transferred archive with R-devel before submission.

The source archive and 27-page reference manual correspond to the source commit
recorded in `manifest.json`. That manifest records both files' SHA-256 checksums.
The package passed local source validation and R CMD check with no errors,
warnings, or notes; its manual also compiled and passed visual review.
This is distinct from an R CMD check --as-cran or hosted compatibility result.

Verify the exact distributed artifact and its source correspondence with:

```sh
python3 scripts/run_validation.py --scope artifact
```

Run `--scope all --as-cran` for the combined source/artifact check once URLs are
public. See the software validation instructions in `scripts/VALIDATION.md`.
