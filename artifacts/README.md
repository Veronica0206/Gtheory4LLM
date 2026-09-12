# Gtheory4LLM 0.0.6 development release

The source archive includes three real publicly archived LLM annotation panels
(eight outcome sets, fifteen codings). The accompanying 28-page PDF is the package
reference manual. Research manuscripts and private working archives are excluded.
Package code is GPL-3; the annotation data retain CC BY 4.0.

The archive was built with R 4.6.1 from the source commit in `manifest.json`,
which records archive and manual SHA-256 checksums. Independent installation and
smoke tests passed. Windows and macOS on current R, Linux on minimum R 4.5.0,
and the locked Linux numerical suite passed. The manual passed visual review.

The [exact archive check under R-devel](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/34724251172)
records its own result, including PDF and HTML documentation checks. These checks
do not establish CRAN acceptance. See the GitHub release for submission status.

Verify archive integrity, source correspondence, and installation with:

```sh
python3 scripts/run_validation.py --scope artifact
```

See `scripts/VALIDATION.md` for source and artifact validation details.
