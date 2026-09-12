# Gtheory4LLM 0.0.6 release candidate

The source archive contains the package and its three real, publicly archived
LLM annotation panels (eight outcome sets, fifteen codings). The accompanying
28-page PDF is the package reference manual. Research manuscripts and private
working archives are outside these release files.

The source archive and manual correspond to the source commit recorded in
`manifest.json`, which records both SHA-256 checksums. This local candidate was
built and checked with R 4.5.3: source numerical checks and the installed package
check passed with no errors, warnings, or notes. The manual compiled without
overfull text and passed visual review. Hosted platform validation and CRAN
submission status are reported separately; this file does not assert CRAN
acceptance.

The CRAN-readiness workflow builds with current R release and checks that exact
archive with R-devel and PDF manual generation. Verify the distributed artifact
and source correspondence with:

```sh
python3 scripts/run_validation.py --scope artifact
```

See `scripts/VALIDATION.md` for the full source-and-artifact checks.
