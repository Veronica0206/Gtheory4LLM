# Improvement-plan status for 0.1.0

Version 0.1.0 is prepared locally. Its local R 4.5.3 archive checks passed;
GitHub publication and the exact hosted current-R/R-devel candidate check are
pending. The confirmed 0.0.6 CRAN submission is awaiting a decision, so 0.1.0
has not been submitted as a duplicate. These are separate completion states.

This describes implementation and evidence, not a promise that every reviewer
recommendation has been completed.

Version 0.1.0 consolidates the reviewed 0.0.7 numerical implementation,
documentation, reproducible pilots, and release checks. It does not expand the
supported fitting limits or statistical operating range. The checked release
files are identified by [the artifact manifest](../artifacts/manifest.json);
CRAN submission and acceptance must be reported separately.

## Implemented

- Release identity checks; README/NEWS correction; comprehensive candidate
  triggers; immutable GitHub Action references and cancellation of superseded
  runs; compatibility checkouts retaining release-verification history.
- Accurate documentation of Gaussian assumptions, fixed-facet interpretation,
  boundary inference and finite-sample uncertainty.
- Contribution and release checklists, with private manuscript material excluded
  from public package content.
- Three reproducible [statistical pilot studies](../validation-studies/README.md),
  including all attempts, independent Gaussian targets and discrete integration:
  320 Gaussian fits, 180 fixed-parameter discrete panels, and 40 binary recovery
  fits. Their 0.0.7 execution provenance is preserved.
- An executable [real-data and failure tutorial](REAL_DATA_WORKFLOW.md).
- A documentation dependency lock preserving every numerical dependency, with
  drift checks and the locked workflow configured to restore it.

## Still outstanding

- Larger Gaussian coverage and discrete recovery campaigns, especially fixed
  facets, higher-order sources, multivariate covariance and realistic missingness.
- Separation of the large numerical engines into stable internal modules and
  a sparse discrete backend, with comparison against the existing dense backend.
- Principled unbalanced Gaussian estimation and unbalanced reliability/D studies.
- Cost-aware D-study planning and covariance/extrapolation sensitivity analysis.
- Broader property-based, fuzz and numerical mutation testing. Existing targeted
  regression and deliberate release/configuration mutation tests are narrower.
- Required-check branch protection. Workflow checks exist; configuring a
  workflow is different from enforcing it through repository protection.

No sparse backend, expanded fitting limit, unbalanced coefficient formula or
discrete interval method is claimed by this release. Local checks and published
pilot results do not imply a passing hosted CI run or CRAN acceptance. Release
decisions require the results for the exact candidate being published.
