# Contributing

Changes should preserve the meaning of the declared model and make their evidence easy to review. Consult [validation scope](VALIDATION_SCOPE.md) before treating a software check as evidence of statistical validity.

## Set up and make a bounded change

1. Work from a named source commit on a separate branch. Use the R and dependency requirements in `DESCRIPTION` and [scripts/VALIDATION.md](../scripts/VALIDATION.md).
2. Keep one coherent change per pull request. Explain the triggering example, resulting behavior, and compatibility impact.
3. Use small synthetic data for reproductions. Public example resources may be used only under their documented provenance and redistribution terms.
4. Keep runtime code in `R/`. The manually maintained `man/*.Rd` files and `NAMESPACE` define documentation and exports; do not regenerate them from informal source comments. Update the vignette when its workflow changes.

Check prerequisites without starting the numerical suite:

```sh
python3 scripts/run_validation.py --scope source --preflight-only
```

Run the relevant source test in a clean R process while developing, for example `Rscript --vanilla tests/test_design.R`. Installed-package tests load the installed package; do not mistake a globally installed older version for the source under review. Before proposing a merge, run the source validation scope, which builds and checks the current package in isolation:

```sh
python3 scripts/run_validation.py --scope source
```

Use the artifact scope when committed release artifacts change. Record skipped vignette/manual checks and unresolved failures explicitly. Do not repeatedly run the full gate after prose-only changes when focused checks resolve the risk. Follow [the exact candidate workflow](../scripts/VALIDATION.md#exact-candidate-for-cran) for release work; a green source check is not evidence that a different archive passed.

## Statistical changes require an explicit account

State these points in the pull request:

- What estimand, score scale, facet universe, or sampling assumption changes?
- What likelihood, covariance parameterization, source term, divisor, or acceptance rule changes?
- Which independent reference or mathematical invariant checks the change, and what failure does the test detect?
- What scientific validation supports the claimed operating region, and what remains unknown?
- Which public outputs or previously accepted inputs change, and how are users informed?

Prefer reference likelihoods, analytic special cases, independent derivatives, and invariance tests over snapshots of the implementation's own output. A test that repeats the same formula can share the same mistake. A deterministic regression belongs in routine validation; a coverage/recovery campaign needs its own protocol, replicate records, and Monte Carlo error reporting.

Preserve explicit failure semantics: do not silently delete random sources, recode outcomes, impute missing cells, increase dense limits, or convert numerical completion into a validity claim. Treat a statistical change separately from a refactor intended to preserve results. Compare source covariances and coefficients on the same model/scale, including boundary and rejected-fit behavior.

## Public content and review evidence

Never paste or commit private manuscripts, unpublished reviewer correspondence, proprietary skill files, raw participant/source text, credentials, or API logs. Minimize numerical failure reports to synthetic or already approved public data. Do not include local absolute paths or private analysis results in public logs. Ask the maintainer before changing data provenance, redistribution scope, or adding an external dataset.

Report the command, source commit, dependency environment, outcome, and material limitations of validation. Do not invent missing results or copy another reviewer's numerical claims into release evidence. A pull request may propose future research without presenting that research as completed. Publishing, tagging, or submitting a release requires the project's authorized release process.
