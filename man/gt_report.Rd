\name{gt_report}
\alias{gt_report}
\alias{gt_export_report}
\alias{print.gt_report}
\title{Create and Export a Portable Aggregate Analysis Report}
\description{Collects retained analysis metadata and verified coefficient
projections in a versioned snapshot, then exports a self-contained HTML report
with aggregate tables, inline figures, limitations, and provenance. No model
fitting, network access, external assets, or additional packages are needed.}
\usage{
gt_report(fit, preflight = NULL, reliability = NULL, dstudy = NULL)
gt_export_report(report, path, overwrite = FALSE)
\method{print}{gt_report}(x, ...)
}
\arguments{
\item{fit}{A \code{gt_fit}. Rejected fits can be reported as diagnostic objects,
but their reliability or decision-study coefficients are refused.}
\item{preflight}{Optional preflight report with matching family, source,
grouping and counts. Outcome and category coding must also match.}
\item{reliability}{Optional \code{gt_reliability} whose projections agree with
the supplied fit under its declared allocation, scale, fixed facets, score,
and uncertainty settings.}
\item{dstudy}{Optional \code{gt_dstudy} checked against the supplied fit.}
\item{report, x}{A \code{gt_report} snapshot.}
\item{path}{Destination \code{.html} or \code{.htm} file. The parent directory
must already exist. The report embeds its styles, tables and SVG figures.}
\item{overwrite}{Replace an existing destination only when explicitly
\code{TRUE}. Defaults to \code{FALSE}.}
\item{...}{Reserved for print-method compatibility.}
}
\value{\code{gt_report()} returns a plain-list snapshot of class
\code{gt_report}, with \code{schema_version = "1.0"}. It supports
\code{saveRDS()} and \code{readRDS()} without retaining the fitted object.
The main fields are:
\itemize{
\item \code{generated_at}: report creation time.
\item \code{analysis}: estimator, backend and numerical status.
\item \code{design} and \code{families}: model declarations.
\item \code{random_sources} and \code{nesting}: grouping declarations.
\item \code{settings}: selected scalar controls.
\item \code{covariance_settings}: recorded covariance structures.
\item \code{diagnostics}: staged numerical status.
\item \code{source_variances}: component values and fixed flags.
\item \code{uncertainty}: interval scope and availability.
\item \code{retention} and \code{provenance}: retained context.
\item Optional \code{preflight}, \code{reliability} and \code{dstudy} tables.
\item \code{association}, \code{privacy} and \code{limitations}: scope text.
}
Tables have atomic columns; absent optional sections are \code{NULL}.
\code{gt_export_report()} returns the normalized output path invisibly.
The print method returns the snapshot invisibly.}
\details{
\strong{Association checks.} Supplied coefficient objects are checked by
recalculating their declared projections from the supplied fit. This reuses
stored covariance estimates and uncertainty; it does not rerun an optimizer.
Coefficient values, intervals, scales, allocations, fixed facets, composite
weights and uncertainty context must agree. Legitimately reordered result
rows are accepted. This verifies numerical compatibility, not historical
object identity or a shared original data file.

Preflight correspondence checks the available model specification, category
coding, sources, free covariance-parameter counts when recorded, observed
counts, replication and grouping scopes. Requested controls, fixed covariance
values and resource-budget correspondence are not verified. Legacy
preflight objects lacking grouping metadata are labelled as not verified for
nesting. Even matching aggregate specifications cannot prove that preflight
and fitting used the same observations; the report states that limitation
prominently. No preflight is inferred from a fit and no coefficient section is
calculated when its input is omitted.

\strong{Privacy scope.} Only explicit aggregate fields are copied.
Observations, facet-level identifiers, raw category labels, calls, models,
grouping examples, arbitrary controls, diagnostic messages and filesystem
paths are excluded. In particular, calls containing literal data frames and
unused factor levels in empty example tables are not copied. Variable,
outcome and source names, aggregate counts, and numerical estimates remain.
These names and small aggregate counts can themselves be sensitive, so this
is not anonymization; review a report before sharing it.

Categorical profiles use \code{category_1}, \code{category_2}, and so on in
declared category order. The private label correspondence is not exported.
Category counts and proportions of groups with each category are descriptive,
not adequacy or identification thresholds. Gaussian minimum/maximum values,
which are individual observed responses, are not copied.

\strong{Provenance.} The fitting-session record contains only its retained R,
platform and selected package versions. The report-generation environment is
a separate record and never fills a missing fitting-session version.
Session versions describe loaded packages, not necessarily the executing
sources when code was sourced separately. Neither record is an archive hash,
source commit, or release qualification. Missing session or retention records
stay unknown. Model and data retention are not required when the fit retains
the compact panel summary and source covariances needed for coefficient checks.

\strong{Figures and export.} HTML text and SVG labels are escaped; figures use
numeric coordinates and contain no scripts or remote references. Reliability
figures show at most 30 coefficient rows; D-study figures show at most 600
rows. Coverage figures show at most 20 categories and 12 variables. Figure
captions disclose these limits; complete aggregate tables remain available.
Long graphical labels may be shortened, with complete labels in the tables.
Source variance rows flag user-fixed covariance components so they cannot be
mistaken for estimated zeros or estimated variance boundaries.
Allocations are unconnected points; intervals appear only where recorded and
available. Discrete latent coefficients have no intervals. The report cannot
establish observed-label accuracy, a globally optimal allocation, statistical
identification, or qualification of a private backend.

The exporter validates the supported schema version, prepares the complete
HTML in a temporary file, and protects existing destinations unless
\code{overwrite = TRUE}. No R objects or executable serialization are embedded
in the HTML. Saving an RDS snapshot is a separate explicit operation.
}
\seealso{\code{\link{gt_preflight}}, \code{\link{gt_reliability}},
\code{\link{gt_dstudy}}, \code{\link{gt_diagnostics}}}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE)))
report <- gt_report(fit, gt_preflight(d, "score", design),
  gt_reliability(fit), gt_dstudy(fit, data.frame(rater = c(2, 3, 6))))
report
path <- tempfile(fileext = ".html")
gt_export_report(report, path)
unlink(path)
}
