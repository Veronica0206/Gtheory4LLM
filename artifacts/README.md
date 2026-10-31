# Gtheory4LLM 1.0.0 release

Release state: **prepared**.

Version 1.0.0 extends the formula-based G-theory workflow with dense and sparse
categorical fitting, optional analytic Laplace gradients, conditional-information
intervals, object-bootstrap inference, and categorical planning tools. It repairs
bootstrap data/model association and nominal-gradient tail arithmetic. Gaussian
fitting retains OpenMx and a bounded lme4 route; discrete fitting uses first-order
Laplace approximation.

## Release files

Use `Gtheory4LLM_1.0.0.tar.gz`, the exact checked archive. The reference manual and
manifest accompany it. Repository documentation commits do not rebuild the package.
Publication state is recorded in the [manifest](manifest.json).

| File | Bytes | SHA-256 |
|---|---:|---|
| `Gtheory4LLM_1.0.0.tar.gz` | 785,808 | `5219d180fb97263f3deeedba4911e1f40f02cd7894fa23f04f3433e547755528` |
| `Gtheory4LLM-manual.pdf` | 433,204 | `ecfb3a4ec559fb82ac8908d7285e2c543f1df71ca2af5791237bcad26b004dc1` |

Package source: `403aa8664bd61ffb9bbe17afc6915ca70f8b5612`.
Requires R >= 4.5.0. Source installation requires a C compiler.

## Validation

- The selected archive passed `R CMD check --as-cran` on Linux R-devel,
  macOS R release, Windows R release and local macOS R 4.5.3 with
  **0 errors, 0 warnings and 0 notes**. The same archive passed the Linux
  no-long-double package check and a separate 54/54 installed-test sweep.
  The no-long-double check was not `--as-cran`.
- Ordinary exact checks included the PDF/HTML manuals and vignettes; noLD
  checked the PDF manual. External system-clock checking was disabled.
- Hosted full numerical validation passed 79/79 stages, including 71 R source
  tests. Compatibility passed 47/47 stages on each of macOS, Windows and
  minimum-supported R 4.5.0. These source runs are distinct from archive checks.
- The exact archive was installed separately on macOS R 4.5.3 and Linux R 4.5.2
  for the October 29 full-data reruns. Both 21,600-row examples passed on both
  platforms: two ordinal drug efficacy/safety outcomes and three binary
  mental-health groups. All four fits were accepted and matched the declared
  point and conditional-information references.

Evidence: [exact archive](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/40878740980),
[full validation](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/40878717801),
[compatibility](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/40878717802),
and the [reproduction record](../docs/DEVELOPMENT_STATUS.md#100-release-gates).
The final local exact check superseded an HTML-tool environment NOTE and an
incomplete CRAN-download timeout; neither unsuccessful attempt is counted as a pass.

## Scope

Numerical reproducibility does not establish global optimality, general Laplace
accuracy or calibrated interval coverage. Conditional intervals hold named singular
source matrices fixed and omit their estimation and selection uncertainty. The
historical Gaussian bootstrap pilot showed undercoverage. The four-aspect drug
and six-flag mental-health joint models remain outside this release's qualified
full-data examples. See [validation scope](../docs/VALIDATION_SCOPE.md) and
[limitations](../docs/LIMITATIONS.md).

GitHub publication does not constitute CRAN submission or acceptance.
