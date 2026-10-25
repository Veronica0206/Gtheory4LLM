\name{gt_fit}
\alias{gt_fit}
\alias{print.gt_fit}
\alias{summary.gt_fit}
\title{Fit Univariate or Joint Multivariate Generalizability Models}
\description{Fits selected random-source covariance models using exact Gaussian likelihoods or dense and sparse first-order Laplace likelihoods for discrete outcomes.}
\usage{
gt_fit(data, outcomes, design = NULL, family = gt_family("gaussian"),
  estimator = NULL, covariance = "unstructured", residual = NULL,
  control = gt_control(), formula = NULL, measured = NULL)
\method{print}{gt_fit}(x, ...)
\method{summary}{gt_fit}(object, ...)
}
\arguments{
\item{data}{Data frame containing the object, all declared instrumentation columns, and outcomes. Missing values are not silently dropped. With a model formula the data frame may also be given second, after the formula.}
\item{outcomes}{One or more unique outcome column names, or a two-sided model formula. The formula names the outcomes on its left, one column or \code{cbind()} of several, and the random sources on its right in the grammar of \code{gt_design()}'s \code{random}. The object of measurement is the variable named by \code{measured}, or else the first variable on the right; the other variables are the instrumentation facets. \code{score ~ item * rater} declares the sources \code{item + rater + item:rater}; \code{label ~ item + rater} is the reduced model a one-observation-per-cell discrete fit needs.}
\item{design}{A declaration created by \code{gt_design()}. Omit it with a formula, which supplies the design; a family given in this position after a formula is read as \code{family}, the order \code{glm()} users expect. Replicates, batches and the automatic nesting selectors have no formula syntax and need \code{gt_design()}. A facet absent from every random-source term also needs an explicit design declaration.}
\item{formula}{The model formula under its own name, for calls such as \code{gt_fit(formula = score ~ item * rater, data = d)}; the same as giving it as \code{outcomes}.}
\item{measured}{With a formula, the name of the right-hand variable that is the object of measurement. \code{NULL} takes the first variable on the right, and the fit's design records which rule applied. Re-ordering a formula without \code{measured} changes the object of measurement, and with it every reliability coefficient, while the variance components stay the same; name it whenever the order is not deliberate. The argument is not called \code{object} because that is the first argument of \code{update()} and the other model generics.}
\item{family}{One \code{gt_family} object for all outcomes, or a named list matching outcomes exactly. Multiple discrete families can be modeled jointly. Joint Gaussian-discrete likelihoods are not implemented.}
\item{estimator}{Gaussian: \code{"REML"} (default) or \code{"ML"}. Discrete: \code{"ML_Laplace"}.}
\item{covariance}{\code{"unstructured"} or \code{"diagonal"}; Gaussian also accepts named source overrides, with unspecified sources using diagonal covariance. Discrete source covariance uses the common requested structure. A discrete fit with a nominal outcome also accepts \code{"exchangeable"}: each source gives every category its own random utility with one variance, \eqn{\sigma^2(I + 11')} on the K - 1 contrasts, unchanged by a change of reference category, with one variance per source and outcome; binary and ordinal outcomes in the same fit keep one variance each, and outcomes are independent within a source.}
\item{residual}{The Gaussian residual structure. Choose \code{"unstructured"}, \code{"diagonal"}, or \code{"pooled"}; pooled gives equal outcome variances. Omit for discrete outcomes.}
\item{control}{A \code{gt_control} object.}
\item{x, object}{A fitted \code{gt_fit} object for the print or summary method.}
\item{...}{Further method arguments; currently unused.}
}
\value{A \code{gt_fit} object whose class vector is \code{"gt_gaussian_fit"} or \code{"gt_discrete_fit"}, according to the engine, followed by \code{"gt_fit"}. It contains source covariance matrices, estimates, likelihood and parameter counts, the resolved design and observation families, modeled data, and numerical diagnostics. Gaussian objects retain prepared sufficient statistics and the fitted engine model (OpenMx or lme4), subject to the retention controls. The OpenMx path also records source-covariance uncertainty and a \code{component_standard_errors} table when its curvature checks permit them. The lme4 path returns estimated source covariance matrices but does not compute the sampling covariance of their estimates; source-variance standard errors and reliability-coefficient intervals are unavailable. Discrete objects include thresholds or category contrasts and conditional probabilities evaluated at the random-effect mode. \code{print()} returns the fit invisibly. \code{summary()} returns a \code{summary.gt_fit} list with estimates, a source-variance table carrying standard errors and a boundary flag where they are available, full covariance components, for a Gaussian fit the observed-score reliability at the fitted facet counts as a \code{gt_reliability} object in \code{reliability} where the fit allows one and otherwise the reason in \code{reliability_note}, and diagnostics. Its \link[=print.summary.gt_fit]{print method} displays a concise report of numerical acceptance, selected attempts, boundaries, and estimates.}
\details{\strong{Formula interface.} \code{outcomes} may be a two-sided model formula, with the data frame given before or after it. \code{gt_fit(score ~ item * rater, data)} declares the outcome \code{score}, the object of measurement \code{item}, the facet \code{rater}, and the sources \code{item}, \code{rater} and \code{item:rater}. A joint fit of two outcomes is written \code{cbind(efficacy, safety) ~ item + rater}. Nothing in the formula is evaluated: it names columns and sources, and \code{fit$design$formula} records it. The resolved design is the object \code{gt_design(object, facets, random = ~ ...)} builds, so a formula fit and a design fit of the same sources are the same fit. Every fit, however declared, answers \code{formula()} and \code{update()}; see \code{\link{gt_fit_methods}}. The recorded \code{fit$call} names each argument, with the formula under \code{formula} and the data under \code{data} whichever order they were given in.

\strong{Engines.} Gaussian outcomes use the exact balanced likelihood through
OpenMx by default. Set \code{engine = "lme4"} in the Gaussian controls to fit
the same sources as random intercepts through lme4. The criterion is
cross-checked against the exact balanced deviance.

Adding \code{panel = "observed"} to those controls opts into bounded univariate
fitting on incomplete observed rows. This route is checked against an
independent dense covariance likelihood; see \link{gaussian_observed}.

The discrete controls default to \code{engine = "dense"}; use
\code{engine = "sparse"} for sparse algebra. Both calculate the same first-order
Laplace objective for binary, ordinal and nominal outcomes, separately or
jointly, and use the same acceptance policy. Sparse algebra does not refine
the likelihood approximation or certify large-panel performance. Sparse
L-BFGS-B fits can request \code{gradient = "analytic"}, which replaces the
optimizer's finite-difference gradient with the analytic gradient of the same
objective; the acceptance policy is unchanged, and \code{\link{gt_control}}
lists the supported covariance coordinates and the refusals.

\code{\link{gt_laplace_check}} attempts a fixed-parameter numerical comparison
with a refined marginal likelihood and reports diagnostic precision and
usability; finite-sample accuracy is not guaranteed. The diagnostics record
the engine, its optimizer and the approximation separately.

The default Gaussian route requires a complete coded Cartesian panel with one observation per cell and at most 4096 factorial strata. A design that declares equal fixed batches with \code{\link{gt_batch}} adds one source, \code{Call}, shared by the items of a batch under one condition, and one factorial axis, because an item is then a batch-by-slot cell; see \code{\link{gt_batch}} for when a declaration is modelled. Implicit normalized Helmert contrasts avoid quadratic allocation along a large object axis. Gaussian ML profiles one fixed intercept per outcome; balanced REML includes the unscaled-intercept constant D * log(N). The observed-row option instead evaluates \eqn{\log|X'V^{-1}X|} on the retained rows, with an unscaled intercept, and refuses batch declarations. Gaussian ML AIC counts covariance parameters and profiled means. Its generic BIC uses N response vectors; \code{ml_BIC_scalar_scores} explicitly provides the alternative N * D convention. The exact balanced engine preserves the archive's variance-only parameter convention in \code{legacy_AIC} and \code{legacy_BIC}; these fields are unavailable on the lme4 route. For REML the fit's \code{AIC} and \code{BIC} elements are \code{NA}; \code{AIC()} and \code{BIC()} use the restricted likelihood with covariance parameters only, \code{BIC()} over N response vectors. The fit records the \code{AIC()} value, the \code{BIC()} value, and the alternative N * D scalar-score BIC under explicit names, in that order:
\itemize{
\item \code{reml_AIC_variance_parameters}
\item \code{reml_BIC_response_vectors_variance_parameters}
\item \code{reml_BIC_scalar_scores_variance_parameters}
}

Discrete models use binary links, ordinal thresholds, or unordered reference-category softmax contrasts. They do not estimate a free Gaussian observation residual. Probit latent residual variance is identified as 1; logit as pi^2 / 3. Unsupported observation-level sources, aliased free source kernels, missing categories, and resource-limit violations are rejected.

Incomplete Gaussian fitting is univariate only. Discrete designs may omit whole
cells, including for joint outcomes, provided retained cells have the declared
equal replication and every retained row contains all requested outcomes.
Partially observed outcome vectors are rejected. This does not model the
missingness mechanism or provide analytic reliability for an irregular panel.

Both discrete engines can append a \code{Call} source for an eligible fixed
batch layout. Its grouping is the batch under the complete combination of
instrumentation facets. The call source is included in random-dimension,
covariance-parameter, memory and kernel-identification checks. This does not
implement variable batch sizes, positional dependence or automatic reliability
for a shared-call layout.

Returned binary probabilities evaluate each tail directly, preserving small
representable probabilities and the declared category order. These are
conditional probabilities at the random-effect mode, not population-marginal
probabilities.

The OpenMx Gaussian engine also computes asymptotic Wald standard errors for source variance components. These use a numerical Hessian of the restricted or profile likelihood. These are large-sample quantities conditional on the declared model; they do not establish coverage in small designs and do not apply to a component resting on a variance boundary. \code{check_hessian = FALSE} disables them along with the other derivative diagnostics on that engine. The lme4 engine returns estimated source covariance matrices but does not compute their sampling covariance or source-variance standard errors.

Discrete \code{check_hessian = TRUE} requests observed information of the
Laplace negative log likelihood after acceptance. Nuisance intercepts and
thresholds are included when covariance-parameter uncertainty is extracted.
If an estimated source covariance lies on its boundary, the entire source
matrix is held at its fitted value, which may be zero or singular and nonzero;
information is then computed over the remaining coordinates. The resulting
latent coefficient intervals are conditional on those held matrices, whose
own standard errors remain unavailable. The uncertainty record names the
held sources and their kinds. This does not account for uncertainty in
selecting the boundary sources or estimating their held values.

Step-size instability, unusable conditional modes, parameter-bound contact,
all estimated sources at their boundaries, or non-positive-definite information
still withhold uncertainty with a reason. Where available, the delta-method
errors and intervals are asymptotic and depend on the first-order Laplace
likelihood; coverage after boundary selection has not been established.
The analytic route differences gradients rather than objectives to form the
information matrix. See \code{\link{gt_control}} for its coordinates and checks.

Numerical acceptance includes optimizer completion and independent stationarity, bound, and tighter-tolerance restart checks. First-order stationarity does not establish a global optimum. A numerically accepted Laplace fit still requires an assessment of approximation adequacy for the intended analysis. Reliability and decision studies reject fits that fail numerical acceptance.

\strong{Reproduction and empirical scope.} Repeating the same request requires
the recorded data and coding, source archive, controls, seeds and numerical
environment; see \link{gt_control}. Across platforms, compare unrounded estimates
under declared tolerances and require agreement in numerical-acceptance and
uncertainty-availability decisions. Identical printed coefficients alone do not
establish reproducibility, and bitwise-identical optimization is not promised.

The installed \file{examples/native_1_0_workflow.R} defines a public workflow for
two specified native examples:
\itemize{
\item Efficacy and safety from \code{drug_review_4aspect}.
\item The three groups in \code{mental_health_3group}.
}
Both are loaded with \code{gt_example()} and \code{coding = "native"}. Each full request
retains 21,600 rows and ten declared sources. The project records report
numerical acceptance on macOS and Linux for those requests, with sparse
analytic-gradient fitting and projected boundary escape. Their original
ordinary information was unavailable. Later macOS information-only computations
at those saved estimates produced conditional intervals while holding named
singular nonzero source matrices fixed. That evidence does not include a new
optimizer run, Linux conditional information, or interval-coverage assessment.
The current 1.0.0 release-candidate review has not repeated the 21,600-row fits.
These records do not establish higher-order likelihood accuracy or results for
the four-aspect drug-review and six-flag mental-health models. Sourcing the
script does not fit the native panels; its helper requires an explicit
\code{mode = "full"} call. Its small synthetic \code{mode = "smoke"} checks
the reporting path only.}
\seealso{\code{\link{gt_design}}, \code{\link{gt_control}}, \code{\link{gt_diagnostics}}. The package installs a worked first discrete fit as \code{discrete-first.R}, and the scoped native workflow as \code{native_1_0_workflow.R}.}
\examples{
d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
fit <- gt_fit(d, "score", design,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
print(fit)
deviance(fit)
# The same model as a formula: outcomes on the left, random sources on the
# right with the object of measurement first.
formula_fit <- gt_fit(score ~ item + rater, d, measured = "item",
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))
all.equal(gt_components(formula_fit), gt_components(fit))
summary(formula_fit)
# The same model through lme4, cross-checked against the exact balanced
# deviance at its estimates; no standard errors on this path.
if (requireNamespace("lme4", quietly = TRUE)) {
  lme4_fit <- gt_fit(d, "score", design,
    control = gt_control(gaussian = list(engine = "lme4")))
  gt_diagnostics(lme4_fit)$engine
  all.equal(gt_components(lme4_fit), gt_components(fit), tolerance = 1e-4)
}
# Re-ordering the right-hand side would make rater the object of measurement;
# measured keeps the target explicit whatever the order.
gt_fit(score ~ rater + item, d, measured = "item",
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42)))$design
# A discrete outcome at one observation per cell: declare the design without
# the object-by-all-facets source, which no discrete fit there can identify.
b <- expand.grid(rater = 1:4, item = 1:10)
b$label <- as.integer((b$item + 2 * b$rater) \%\% 5 > 1)
binary_fit <- gt_fit(b, "label", gt_design("item", "rater", full_cell = FALSE),
  gt_family("binary"))
gt_diagnostics(binary_fit)$numerically_accepted
# As a formula, with the family following it as in glm().
binary_formula <- gt_fit(label ~ item + rater, b, gt_family("binary"),
  measured = "item")
all.equal(gt_components(binary_formula), gt_components(binary_fit))
# The installed worked example, start to finish:
script <- system.file("examples", "discrete-first.R",
                      package = "Gtheory4LLM")
file.exists(script)
}
