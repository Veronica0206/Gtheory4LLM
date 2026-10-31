# Historical native replay: 29 October 2026

These are machine-readable records from four completed fits: two models, each
run on macOS and Linux using all 21,600 rows. They were generated from source
`403aa8664bd61ffb9bbe17afc6915ca70f8b5612`, archive SHA-256
`5219d180fb97263f3deeedba4911e1f40f02cd7894fa23f04f3433e547755528`.
That candidate was subsequently withdrawn to correct bootstrap identifier
validation. These records are **historical**; they do not claim a fresh full-data
run of the corrected `c9276e0` / `d1328dac...` archive.

## Requests and recorded outcomes

| Model | Outcomes | Recorded result on each platform |
|---|---|---|
| Drug review | Efficacy and safety, two ordinal outcomes, ten declared sources | Numerically accepted; both point references matched; conditional-information reference matched, holding three singular nonzero source matrices fixed |
| Mental health | Three binary groups, ten declared sources | Numerically accepted; both point references matched; conditional-information reference matched, holding five singular nonzero source matrices fixed |

The macOS environment used R 4.5.3 and R's reference BLAS. Linux used R 4.5.2
and OpenBLAS 0.3.26. Both used one numerical thread. Per-platform `status.csv`,
`session-info.txt` and `provenance.R` retain acceptance decisions, environment
versions, archive identity, controls and input/driver hashes. Each model folder
contains component and reliability tables, D-study results, point-reference and
conditional-information comparisons, diagnostics, protocol, data provenance,
preflight, status and warnings. An empty warnings file records no warnings.

## Integrity and reading the records

[manifest.json](manifest.json) maps all 58 exported records to their original
relative paths and hashes. Fifty-six are byte-identical copies. Only the two
platform provenance files changed: private installed-library paths were removed
and the supplied archive path was reduced to its basename. Their numerical
values, environment versions and original file hashes are preserved. The
manifest also fingerprints the original complete run checksum list.
[SHA256SUMS](SHA256SUMS) covers the public records, this README and the manifest.
The complete original record, including serialized fits and execution logs,
remains in project storage; those larger files are not included in this export.

Read CSV files with `read.csv()`. The `.R` records are R `dput()` data and can
be read with `dget()` after inspecting them. For example, from this directory:

```r
status <- read.csv("mac/status.csv")
comparison <- read.csv("linux/drug_review_efficacy_safety/reference-comparison.csv")
provenance <- dget("mac/provenance.R")
stopifnot(all(status$numerical_acceptance), all(comparison$passed))
```

The installed [native workflow](../../inst/examples/native_1_0_workflow.R)
and [guide](../../docs/REAL_DATA_WORKFLOW.md) describe the requests and comparison
policy. Their smoke mode is separate from these full-data runs.

## Scope

These records make the reported results inspectable without repeating the fits.
They establish the recorded numerical and conditional-arithmetic agreement for
the named historical archive and environments. They do not establish global
optimality, first-order Laplace accuracy, interval coverage, or qualification of
the four-aspect drug-review and six-flag mental-health joint models. The
conditional intervals omit uncertainty in held matrices and their selection.
See [validation scope](../../docs/VALIDATION_SCOPE.md).
