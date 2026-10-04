# Portable analysis reports

The development interface exports one offline HTML document containing model
context, diagnostic summaries, aggregate data profiles, tables and embedded
figures. It uses the supplied fit and never runs optimization. A report is an
analysis record, not evidence that the model or an unqualified backend has been
validated for a new population.

## Create and export

Using objects from the installed `LLM-workflow` vignette:

```r
report <- gt_report(fit, preflight = preflight,
  reliability = reliability, dstudy = dstudy)
print(report)
gt_export_report(report, "analysis-report.html")
```

The destination must be new unless `overwrite = TRUE` is explicitly supplied.
The file has no external scripts, network resources or companion image folder.
The report object can also be saved with `saveRDS()` for use within R; its
`schema_version` describes its reporting structure.

The [executable example](../examples/analysis_report_workflow.R) uses synthetic
observations. Any accompanying results describe that simulation, not native
annotation panels or a generally adequate sampling design.

## Result association and provenance

Coefficient and D-study objects supplied to `gt_report()` are checked against
projections recomputed from the fitted components. This does not refit a model
or authenticate an original analysis file. A supplied preflight object must
have compatible aggregate specifications, including free covariance-parameter
counts where the fit records enough information. Requested control values,
fixed covariance values and resource budgets are not authenticated by that
comparison. Matching counts and declarations do not prove that its observations
are the observations originally fitted.

Retained fitting-session metadata and the report-generation session are separate
records. Dropping session retention leaves fitting provenance unavailable; the
current environment is never substituted for the environment of an earlier fit.
Reports do not recover a missing source-archive digest or Git identity.

## Data retained and omitted

The report uses an explicit selection of fields. It excludes observations,
input calls, model objects, observation-level predictions, row examples and
facet-level identifiers. Category labels are represented by aliases in report
profiles. Variable, outcome and source names, design counts and aggregate
estimates remain in the document. Inspect those names and aggregate results
before sharing; exclusion of raw records is not an anonymization guarantee.

A preflight object itself can retain sampled design labels in its bounded
examples, and a fit retains data by default. Exporting a report does not alter
those objects. Use the package's retention controls separately when saving fits.

## Interpretation

- Numerical acceptance is separate from statistical accuracy or approximation
  adequacy. The diagnostic summary retains that distinction.
- Binary and ordinal coefficients describe latent-response averages. They are
  not accuracy, agreement with reference labels or majority-vote reliability.
- Discrete confidence intervals remain unavailable. A report never manufactures
  intervals or turns a point estimate into a precision claim.
- D-study results project the declared fitted variance model onto supplied
  allocations. Extrapolation and uncertainty scope remain explicit.
- Outcome profiles are descriptive. Absent categories and groups with no
  variation do not imply a new minimum-sample rule, and categories are never
  merged automatically.

See [figures](VISUALIZATION.md), [validation scope](VALIDATION_SCOPE.md) and
[the remaining 0.3.0 gates](ROADMAP.md).


## Rendered synthetic examples

- [Gaussian report](figures/reporting-030/gaussian-analysis.html): two continuous
  outcomes, an explicitly weighted composite, and candidate allocations.
- [Ordinal report](figures/reporting-030/ordinal-analysis.html): a small synthetic
  fixed-zero-covariance example with aliased category coverage and latent
  point estimates. Fixed components are labelled in the source table.

![Example category coverage](figures/reporting-030/category-coverage.png)

These reports were generated from a fresh installation of the checked
0.3.0.9000 archive. [Provenance](figures/reporting-030/provenance.json) records its
digest and verification scope. Embedded figures were rendered and inspected;
full HTML browser layout was not verified because local-file browser navigation
was blocked. Neither example is a fitted native annotation analysis.
