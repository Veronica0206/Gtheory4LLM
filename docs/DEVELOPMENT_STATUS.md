# Improvement-plan status

This describes implementation and evidence, not a promise that every reviewer
recommendation has been completed.

## Implemented

- Release identity checks; README/NEWS correction; comprehensive candidate
  triggers; immutable GitHub Action references and cancellation of superseded runs.
- Accurate documentation of Gaussian assumptions, fixed-facet interpretation,
  boundary inference and finite-sample uncertainty.
- Contribution and release checklists, with private manuscript material excluded
  from public package content.
- Three reproducible [statistical pilot studies](../validation-studies/README.md),
  including all attempts, independent Gaussian targets and discrete integration.
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

No sparse backend, expanded fitting limit, unbalanced coefficient formula,
discrete interval method or new CRAN release is claimed by this work. Local
checks and published pilot results also do not imply a passing hosted CI run.
