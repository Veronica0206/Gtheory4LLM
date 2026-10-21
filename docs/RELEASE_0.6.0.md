# Gtheory4LLM 0.6.0 qualification record

Qualification checkpoint: 2026-10-20 21:00 America/New_York
(2026-10-21 01:00 UTC). The selected bundle was prepared at this checkpoint.
Pending items below describe that time; later publication requires separate
tag, manifest, and delivery evidence. This document does not establish CRAN
submission. The integrated source is
`352468d11ee7d09d7b0fba3e97cdf167dd6a75e7`, preserved through the protected
fast-forward of [PR #75](https://github.com/Veronica0206/Gtheory4LLM/pull/75).
Branch protection was not relaxed.

## Scope

The Model Interface release adds formula-based fitting and preflight with an
explicit object of measurement, consistent fit classes and model methods,
an independently checked lme4 Gaussian engine, and `gt_laplace_check()` for
fixed-parameter approximation comparisons. Its refinements add the defensive importance mixture and improve
source/boundary diagnostic mapping, documentation, and runnable examples. The public workflow leads with the formula where
the design grammar supports it; explicit design declarations remain available.
See [NEWS](../NEWS.md) and [limitations](LIMITATIONS.md).

Public sparse categorical fitting, categorical intervals, new categorical
observed-score, decision and vector targets, incomplete-panel inference,
categorical call effects, and expanded planning are future work. This release does not claim those capabilities or
eliminate platform-sensitive numerical acceptance decisions. Companion analyses use the qualified 0.6.0 archive; later development requires
separate qualification.

## Selected bundle

The archive was built with R 4.6.1 and adopted unchanged from the integrated
source's checked candidate. Publication metadata must not rebuild it.

| File | Bytes | SHA-256 |
|---|---:|---|
| `Gtheory4LLM_0.6.0.tar.gz` | 570,725 | `d9a592b7b40b73dab9b6d051b4abbe2eff5cf54b1a22d15c58c7ec1d46aef5bd` |
| `Gtheory4LLM-manual.pdf` | 351,150 | `43d10fb565787bd1e985f11db341e554681b3b0e3a7eac417e4bfa18b0dc2cb9` |

The separately built reference manual has 66 pages; its overfull-box gate and
visual review passed. The [manifest](../artifacts/manifest.json) records the
selected source, artifact identities, preparation/publication state, and
checked-candidate provenance. The ordinary check report's SHA-256 is
`7eebb80746c0daaec681cd4207c5d1fb81801f1c059d508f2b7f8b08da0846d2`.

## Completed qualification

- [Integrated-source candidate run](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861542):
  ordinary Linux R-devel 4.7.0 (2026-10-18 r90707), `R CMD check --as-cran`,
  **0 errors, 0 warnings, 0 notes** for the selected archive, including the
  PDF manual and all **33 packaged tests**.
- The same candidate run's Linux x86-64 noLD job, R-devel (2026-10-03 r90638)
  on AMD EPYC 7763 with long-double support verified absent, checked the
  **same archive bytes** using `R CMD check --no-stop-on-test-error`:
  **0 errors, 0 warnings, 0 notes**, PDF manual and all **33 packaged tests**.
  The separate installed-test loop passed **33/33**. Reference BLAS/LAPACK
  probes at setup, after loading numerical dependencies, and after all tests
  each completed **80 native solves with 0 invalid**. An independent audit
  matched the ordinary/noLD source, size and hash records and fingerprinted
  all **368 downloaded evidence files**. Native probes were audited from
  retained records; the evidence audit did not rerun numerical operations.
- [Integrated-source full validation](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861801):
  **32/32 stages**, locked scope `all`, including independent OpenMx, lme4 and
  ordinal comparisons and a staged-bundle artifact check.
- [Integrated-source compatibility](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39521861768):
  **20/20 stages on each** of Windows/R release, macOS/R release, and
  Ubuntu 22.04/R 4.5.0. These source checks are not checks of one identical
  archive across those platforms.
- Local macOS arm64, R 4.5.3: full locked validation against the selected
  staged manifest passed **32/32 stages**, including source checks, the manual
  gate, and a fresh-library install/smoke of the selected archive. Its source
  package check rebuilt a local archive and reported **0 errors, 0 warnings,
  0 notes** under `--no-manual --as-cran`; the manual was checked separately.
  Local remote incoming lookups (`_R_CHECK_CRAN_INCOMING_REMOTE_=false`) and
  external system-clock checks (`_R_CHECK_SYSTEM_CLOCK_=false`) were disabled.
  Hosted ordinary R-devel supplies the selected archive's remote incoming
  check evidence. No external-clock verification is claimed.

The earlier [PR candidate run](https://github.com/Veronica0206/Gtheory4LLM/actions/runs/39511869200)
qualified synthetic merge `9f7ff6239bfd7a2f7958869ce97f50cf2dcb6a92`, including
noLD and 33/33 installed tests. Its 570,728-byte archive, SHA-256
`5aa05e122d467657908595a78fd277ad33f1d31b85bbcd20dc9bf673dfc11ae3`, is
historical PR evidence, not the selected release archive. Canceled duplicate
push checks were rerun successfully before the protected fast-forward.

## Gates still pending at this checkpoint

1. Integrate the reviewed bundle/publication metadata through its own required
   checks; verify the new tag and published manifest without moving the tag.
2. Complete sequential macOS/Linux manuscript reproduction from this selected
   archive, then review and synchronize the PDFs and records. Previous
   manuscript runs remain separately identified historical evidence.
3. Verify the complete draft's archive, manual and manifest bytes, publish, and
   verify immutable delivery and release attestations.

CRAN upload, maintainer confirmation, CRAN review, and CRAN acceptance are
separate from these steps. No 0.6.0 CRAN submission or current reverse-dependency
survey is established here. Historical release assets, tags, and records remain
unchanged; later results must identify their own exact commit and bytes.
