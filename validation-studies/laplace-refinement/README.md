# Defensive-mixture Laplace diagnostic

This bounded numerical study evaluates the corrected importance-sampling
diagnostic on the existing three-item binary-logit fixture. It addresses a
specific defect of the previous Gaussian-only proposal: its importance weights
can have infinite second moments even while empirical ESS is high.

The corrected proposal is `0.9 * Laplace Gaussian + 0.1 * standard-normal prior`.
Every draw uses the full mixture density in its importance weight. Since a
categorical likelihood is at most one and the proposal dominates one tenth of
the prior, unnormalised weights are bounded by ten. This establishes finite
weight moments. It does not establish accurate finite-sample Monte Carlo
intervals, adequate relative precision, or recovery of fitted model parameters.

The [protocol](PROTOCOL.md) specifies the fixture, two budgets and 80 seeds
before execution. [The runner](run.R) fits the fixture once, then compares the
diagnostic at those fixed parameters with a product of three independent
one-dimensional adaptive integrals. The two reference tolerances give the same
reported minus-two-log-likelihood, 27.7927637807; the Laplace value is
27.9131039116. The Gaussian-only proposal's precision eigenvalues are 3.6752,
4.0499 and 4.5773, all above the logistic-tail threshold of two.

[All 80 attempted comparisons](results-20261018/replicates.csv) and the
[summaries](results-20261018/summary.csv) are retained. Every comparison was
available and passed the empirical ESS screen on this fixture.

| Draws per comparison | Independent repetitions | Empirical SD of error | RMS reported MCSE | RMSE | Nominal 95% MC intervals containing reference |
|---|---:|---:|---:|---:|---:|
| 2,000 | 40 | 0.02264 | 0.02268 | 0.02237 | 40/40; exact 95% proportion interval 0.912–1.000 |
| 20,000 | 40 | 0.00642 | 0.00715 | 0.00637 | 39/40; exact 95% proportion interval 0.868–0.999 |

These are descriptive finite-sample checks on one binary model, with imprecise
calibration estimates. They are not general validation of ordinal, nominal,
multivariate or crossed models, an operating-range claim, or a coverage study
of statistical model-parameter intervals. Importance sampling can still have
poor relative precision, and empirical ESS can miss poorly sampled regions.
The public diagnostic keeps those qualifications in its printed output.

Reproduce in a new output directory with an isolated package installation:

```sh
Rscript validation-studies/laplace-refinement/run.R NEW_OUTPUT_DIR R_LIBRARY
```

Alternatively set `GT_STUDY_LIBRARY` and omit `R_LIBRARY`. Either selects
archive-based execution, which also works when just `run.R` and `PROTOCOL.md`
are copied into a manuscript supplement. It fingerprints the installed package
and study files without assuming a Git repository. The study requires `digest`
and `jsonlite`. Each new result directory retains the executed runner/protocol
and an `execution.json` with completion status, attempt count and before/after
SHA-256 records. Completion describes execution, not success of every numerical
comparison.

The [environment record](results-20261018/environment.txt) identifies an
installed local development build reporting version 0.6.0, based on source
revision `4d9d572` plus the explicitly recorded working-tree corrections. It is
not evidence about the unchanged frozen 0.6.0 archive. Before/after source
SHA-256 records identify the exact owned files used during the study; a later
test-only change made a console-text assertion insensitive to line wrapping.
The numerical implementation, protocol and runner were unchanged by that
assertion repair. Final-archive checks and cross-platform qualification are
separate evidence.

The runner was subsequently extended for archive-based reproduction. The
[original executed runner](results-20261018/run-executed.R) and
[original protocol](results-20261018/PROTOCOL.md) are preserved with the initial
results and verified against its pre-run hashes. The portability change leaves
the numerical study specification unchanged; later executions record their own
mode, snapshots and fingerprints.

For public portability, the two initial `source-sha256-*.txt` records now use
package-relative source labels instead of the original local source-root
prefix. This changes only the displayed paths: all SHA-256 strings, their
order, the referenced source identities and every numerical result are
unchanged. The original path-bearing records are retained in a separate private
audit snapshot. The initial executed runner and protocol remain byte-for-byte
unchanged beside the results; their hashes still match these records. The
current runner already emits relative fingerprint labels for installed package,
study and source-tree files, so it requires no change for this correction.
