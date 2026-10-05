\name{gt_preflight}
\alias{gt_preflight}
\alias{print.gt_preflight}
\alias{plot.gt_preflight}
\title{Inspect Data, Source Dimensions, and Backend Limits Before Fitting}
\description{Reports observed design and outcome information, random-source dimensions, parameter counts, and the current backend's structural and resource restrictions without optimizing a model. Declared absent categories are reported as a failed check; fitting continues to reject them. Other category and source-resolution rules match fitting.}
\usage{
gt_preflight(data, outcomes, design, family = gt_family("gaussian"),
  covariance = "unstructured", residual = NULL,
  control = gt_control(), max_examples = 10L)

\method{print}{gt_preflight}(x, ...)

\method{plot}{gt_preflight}(x, type = c("cells", "sources", "outcomes"),
  max_sources = 20L, outcome = NULL, max_categories = 12L,
  max_variables = 8L, max_label_chars = 18L, ...)
}
\arguments{
\item{data}{A nonempty data frame with unique column names.}
\item{outcomes}{One or more outcome column names.}
\item{design}{A design from \code{\link{gt_design}}.}
\item{family}{A family from \code{\link{gt_family}}, or a named family list matching the outcomes.}
\item{covariance}{The source covariance specification accepted by \code{\link{gt_fit}}.}
\item{residual}{Gaussian residual covariance specification, or \code{NULL} for the default. Do not specify this argument for discrete outcomes.}
\item{control}{Engine controls from \code{\link{gt_control}}. Resource limits are read from the selected engine's controls.}
\item{max_examples}{A nonnegative finite integer, no greater than \code{.Machine$integer.max}. Maximum rows in each panel-audit table and in each outcome/variable no-variation example table, and maximum invalid design-row indices in an error. Zero suppresses examples while retaining counts and truncation metadata. Defaults to 10.}
\item{x}{An object returned by \code{gt_preflight}.}
\item{type}{Plot mutually exclusive full-cell counts (\code{"cells"}), random-source dimensions (\code{"sources"}), or descriptive category coverage across design-variable groups (\code{"outcomes"}).}
\item{max_sources}{A positive finite integer limiting the source bars. Sources are sorted by decreasing random dimension, with ties in source-table order. The plot explicitly reports truncation. Ignored for cell bars, but still validated.}
\item{outcome}{For \code{type = "outcomes"}, one outcome name. Required when preflight contains multiple outcomes. Gaussian outcomes have numeric profile tables, not a category heatmap.}
\item{max_categories, max_variables}{Positive finite integers limiting heatmap rows and columns. Categories follow declared order; variables follow design order. Displayed and total counts, and truncation, are printed on the plot.}
\item{max_label_chars}{A finite integer of at least four, limiting heatmap label text before a position number is added. Abbreviated labels map to the complete profile tables by that number.}
\item{...}{For cell/source plotting, named arguments passed to \code{\link[graphics]{barplot}}; for category coverage, named arguments passed to \code{\link[graphics]{image}}. Supplied arguments override plotting defaults. Reserved for print-method compatibility.}
}
\value{A \code{gt_preflight} list with observed counts and replication,
source and parameter totals, resource estimates, and interpretation notes.
It also contains:
\itemize{
\item \code{sources}: a data frame describing the random sources.
\item \code{panel_audit}: bounded panel diagnostics, described below.
\item \code{outcome_profile}: a named list of descriptive outcome summaries,
category counts, grouping coverage, and bounded no-variation examples.
\item \code{batch_audit}: for a design that declares batches, the calls
that declaration implies or records; absent otherwise. Described below.
\item \code{checks}: a data frame of the structural and resource checks.
\item \code{fitting_feasible}: whether those checks passed.
\item \code{supported_reliability_scales}: conditional coefficient scales.
}
Feasibility is not a fitting or identification result. Invalid input types or
undeclared observation categories raise an error. Declared but absent categories
produce a failed \code{outcome_category_coverage} check and
\code{fitting_feasible = FALSE}; no category is removed and \code{gt_fit()}
still raises an error. Unsupported observed designs and
exceeded resource limits are reported as failed checks. Both print and plot methods return \code{x} invisibly.}
\details{
The panel audit uses the Cartesian product of the levels actually observed in
each design column. Unused factor levels are excluded. It does not infer
unobserved levels, physical crossing, or permitted combinations from sampling
intent. No data, source specification, or model is automatically corrected.
\code{panel_audit} contains:
\itemize{
\item \code{summary}: one row each for \code{complete},
\code{under_replicated}, \code{over_replicated}, and \code{missing}.
These categories are mutually exclusive. Complete means an observed full cell
has exactly the declared replication; under-replicated cells have at least one
row but fewer than declared; missing cells have no rows.
\code{cell_count_exact} stores exact decimal counts as character strings.
\code{cell_count} is a numeric convenience column: counts above
\code{2^53} can be rounded, and counts beyond the finite numeric range are
\code{Inf}. \code{expected_cells_exact} gives the exact full-product count.
\item \code{missing_cells}: representative absent full cells, retaining the
original design-column names, sampled values, and classes. Factor levels not
present in an example table are dropped, including all levels in empty tables,
so factor attributes do not expose omitted identifiers. Examples use first-observed
level order, with the object column varying fastest.
\item \code{replication_issues}: cells with incorrect replication, in input
order. Design columns are followed by observed
replication, declared replication, and status metadata.
\item \code{row_examples}: input-row examples from cells with incorrect
replication, in input order. Only design columns and audit metadata are copied;
outcomes and unrelated data columns are excluded. The row metadata is the
one-based input-row position, independent of data-frame row names.
\item \code{metadata_columns}: maps metadata roles to table column names.
The roles identify the input row, observed and declared replication, and status.
The corresponding keys are:
\itemize{
\item \code{row}
\item \code{observed_replicates}
\item \code{declared_replicates}
\item \code{status}
}
Metadata normally uses the prefix \code{.gt_};
leading dots are added until none of the metadata names collide with input
column names. Original column names are not repaired or renamed.
\item \code{examples}: for each example table, the requested \code{limit},
number \code{shown}, total available (\code{total} and authoritative
\code{total_exact}), and whether examples were \code{truncated}.
}
Examples are deterministic, not random samples. Their counts use all input
rows. Missing-cell examples are generated incrementally, visiting at most the
observed-cell count plus the requested example count; the full Cartesian grid
is never materialized. All three example tables are capped separately.

Each \code{outcome_profile[[outcome]]} contains:
\itemize{
\item \code{family}, \code{link}, and \code{summary}: the number of rows and
distinct observed values, and declared/observed category counts for discrete
outcomes. Gaussian outcomes instead have minimum, maximum, mean, and sample
standard deviation; derived summaries outside the finite numeric range are
\code{NA}. Gaussian values are not converted to categories. Globally constant,
missing, or nonfinite Gaussian inputs still raise the fitting validation error.
\item \code{categories}: declared category labels, counts, row proportions,
and an \code{observed} flag. Safely resolved declared categories, including
unused declared factor levels, appear with zero counts when absent. The binary
numeric/logical category labels follow fitting's \code{0}/\code{1} convention.
This table is \code{NULL} for Gaussian outcomes.
\item \code{by_variable}: the number of observed groups, groups with exactly
one distinct response (\code{no_variation_groups}), groups with one row
(\code{single_row_groups}), and the no-variation fraction for each design
variable. Single-row groups are included in no-variation counts, and counted
separately to distinguish missing replication from repeated constant responses.
\item \code{category_coverage}: for each variable/category pair, the number
and proportion of observed groups containing at least one row in that category.
The denominator is the observed group count, not the measurement-row count.
A group may contain several categories, so these proportions need not sum to
one. This table is \code{NULL} for Gaussian outcomes.
\item \code{group_members}: the columns defining each variable's groups.
Declared nested variables include all declared ancestors. Other variables
use their marginal coded levels. Reused nested IDs are distinguished by their
parents. No additional physical nesting is inferred.
The \code{grouping_scope} column of \code{by_variable} records this choice:
\itemize{
\item \code{declared_parent_scoped}: groups include declared ancestors.
\item \code{marginal_coded_levels}: groups use one variable's coded levels.
}
\item \code{no_variation_examples}: one table per design variable containing
at most \code{max_examples} grouping identifiers, row counts and distinct-value
counts, in first-observed order. Sampled values, column classes, and order are
preserved; unused factor levels are dropped. Outcome values and unrelated
columns are excluded. \code{metadata_columns} maps \code{row_count} and
\code{distinct_values} to collision-safe metadata names. \code{examples}
reports total, shown, limit, and truncation for each variable.
\item \code{scope} and \code{privacy}: interpretation and sharing notes.
These tables are descriptive, with no minimum category count or variation
threshold for adequacy. They do not certify identification, fit acceptance,
or likelihood-approximation accuracy, and do not collapse categories.
Category labels, small counts, and sampled grouping identifiers may be
sensitive. \code{max_examples = 0} suppresses group identifiers in example
tables, including unused factor levels, but leaves aggregate counts and
category/outcome labels. The preflight object is not anonymized.
}
The recorded call keeps its data argument only when that argument is a plain
object name. A data frame supplied through \code{do.call()}, or an inline
expression, is recorded as a marker rather than stored in the call.

For a design made with a \code{\link{gt_batch}} declaration, \code{batch_audit}
contains the declared size, order source, facet and reaches, and
\code{membership}: \code{"inferred"} when the batches are cut from the item
order, \code{"recorded"} when the calls are read from the column named in the
declaration's \code{id}. It counts the items, the distinct \code{batches},
the conditions and the \code{calls}. Recorded calls are counted. Inferred
calls are implied: one for each batch, condition and declared replicate.
\code{equal_sized}, \code{calls_below_size} and
\code{smallest_observed_call} describe calls with fewer items present than
declared. That is a property of the rows supplied, not a problem, and not
evidence of how many items a call was sent: a call sent short and a call that
lost rows after collection look the same, and a call with no row left is not
counted. \code{position_scope} records that positions are ranks among the
items present. \code{fixed_composition} and \code{fixed_order} say
whether every condition holds the same batches, and each batch in one order.
\code{consistent} is \code{TRUE} when the declaration can be laid over the
data, with the reasons in \code{problems} when it cannot. At most
\code{max_examples} rows list items with their batch, or their recorded call,
and position. \code{model} says whether a fit of these data would estimate
a shared call effect, with the reason when it would not, the name of the
source it adds and that source's covariance parameters, which the total
parameter count includes. No coefficient scale is offered for a design whose
fit models a call effect; see \code{\link{gt_batch}}.

Inferred membership is a reconstruction from the rows supplied, and
\code{consistent} is then no evidence about how the data were collected:
items removed after collection, calls of other sizes and regrouping between
conditions leave no trace. \code{membership_scope} says so in the object and
the printed report repeats it; for recorded calls it states the limits just
described. For inferred batches \code{stored_rows}
reports, when every condition holds each item once, in how many conditions
consecutive blocks of rows hold one declared batch, and in how many they also
follow the declared order. That agreement means something only when rows are
stored call by call. The audit estimates no dependence and does not enter
\code{checks}.

For absent declared categories, the profile and structural/resource estimates
remain available; free-covariance and source-kernel checks are skipped after
the failed category check, and no reliability scale is offered.

The default plot shows horizontal bars for the four exclusive cell categories.
Direct count labels make zero and small counts visible beside large bars;
labels above \code{1e12} use abbreviated scientific notation marked with a
tilde. Exact counts remain available in the audit table.
The source plot shows the largest random dimensions, up to \code{max_sources}.
Plots describe observed coded levels, not runtime, statistical identification,
or fit acceptance. Numeric cell bars may be rounded above \code{2^53}; a cell
plot raises an error when counts exceed the finite plotting range. Consult the
exact count strings in that case.

The outcome heatmap shows group coverage for one discrete outcome, with a fixed
zero-to-one color scale and bounded category/variable labels. An asterisk marks
a variable whose groups include declared nesting ancestors. Small displays
(at most eight variables and twelve categories) include percentage labels;
near-zero and near-one values are abbreviated without labeling them exactly
zero or one. The plot does not show per-group response rows or treat sparse
coverage as an automatic model rejection. Larger displays use colors only.

Each random source has one predictor dimension per Gaussian, binary, or ordinal outcome and one dimension per nonreference category for a categorical outcome. Its random dimension is the product of that dimension count and its observed grouping count. These are conceptual random-effect dimensions for Gaussian fitting; the exact Gaussian backend instead uses factorial contrasts.

The source table counts free variance/covariance parameters under the requested covariance structure. Fixed discrete source covariance matrices contribute zero free covariance parameters. Gaussian observation parameters are the profiled outcome means; discrete observation parameters are intercepts or ordinal thresholds. The total includes these observation parameters and the Gaussian residual covariance parameters. It is not a residual degrees-of-freedom count or an information-criterion definition.

Gaussian checks require a complete coded Cartesian panel with one measurement per cell and resolve a full-cell source into the residual when appropriate. Discrete fitting can admit missing whole cells, but analytic reliability and D studies still require a complete balanced coded panel. Within configured size limits, preflight also applies the current discrete source-kernel checks. When an earlier structural or resource check fails, \code{kernel_check} explicitly reports that the kernel checks were skipped. Source counts then refer to the requested model if family-specific resolution failed.

The Gaussian allocation estimate covers preparation arrays only. The discrete byte count covers one dense random-design matrix and one random-effect Hessian only. Neither predicts peak memory or runtime. Fewer than five observed groups triggers a descriptive note, not a rejection rule. Starting values and optimizer-specific controls are validated by fitting.

Passing preflight does not establish statistical identification, reliable estimation, numerical acceptance, or Laplace-approximation adequacy. Supported scales remain conditional on a numerically accepted fit: observed Gaussian scores, or explicitly requested latent binary/ordinal responses. Latent coefficients describe averages of latent responses, not majority-vote decisions or observed label proportions. No scalar nominal coefficient is implemented.
}
\seealso{\code{\link{gt_fit}}, \code{\link{gt_diagnostics}}, \code{\link{gt_reliability}}, \code{\link{gt_dstudy}}}
\examples{
# Entirely synthetic evaluator/prompt data; no API or study data are used.
d <- expand.grid(item = 1:8, evaluator = 1:3, prompt = 1:2)
d$score <- sin(d$item) + d$evaluator / 5 + cos(d$item * d$prompt) / 4
design <- gt_design("item", c("evaluator", "prompt"),
  random = ~ item + evaluator + prompt + item:evaluator)
report <- gt_preflight(d, "score", design)
print(report)
report$sources

# Missing whole cells block Gaussian fitting and analytic reliability.
incomplete <- gt_preflight(d[-1, ], "score", design)
incomplete$checks[!incomplete$checks$passed, ]
incomplete$panel_audit$missing_cells
plot(incomplete)
plot(report, type = "sources", max_sources = 5L)
}
