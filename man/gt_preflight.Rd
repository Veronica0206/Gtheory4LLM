\name{gt_preflight}
\alias{gt_preflight}
\alias{print.gt_preflight}
\title{Inspect Data, Source Dimensions, and Backend Limits Before Fitting}
\description{Reports observed design counts, random-source dimensions, parameter counts, and the current backend's structural and resource restrictions without optimizing a model. Uses the same category and source-resolution rules as fitting.}
\usage{
gt_preflight(data, outcomes, design, family = gt_family("gaussian"),
  covariance = "unstructured", residual = NULL,
  control = gt_control())

\method{print}{gt_preflight}(x, ...)
}
\arguments{
\item{data}{A nonempty data frame with unique column names.}
\item{outcomes}{One or more outcome column names.}
\item{design}{A design from \code{\link{gt_design}}.}
\item{family}{A family from \code{\link{gt_family}}, or a named family list matching the outcomes.}
\item{covariance}{The source covariance specification accepted by \code{\link{gt_fit}}.}
\item{residual}{Gaussian residual covariance specification, or \code{NULL} for the default. Do not specify this argument for discrete outcomes.}
\item{control}{Engine controls from \code{\link{gt_control}}. Resource limits are read from the selected engine's controls.}
\item{x}{An object returned by \code{gt_preflight}.}
\item{...}{Reserved for print-method compatibility.}
}
\value{A \code{gt_preflight} list with observed counts and replication,
source and parameter totals, resource estimates, and interpretation notes.
It also contains:
\itemize{
\item \code{sources}: a data frame describing the random sources.
\item \code{checks}: a data frame of the structural and resource checks.
\item \code{fitting_feasible}: whether those checks passed.
\item \code{supported_reliability_scales}: conditional coefficient scales.
}
Feasibility is not a fitting or identification result. Invalid input types or
observation categories raise an error. Unsupported observed designs and
exceeded resource limits are reported as failed checks.}
\details{
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
}
