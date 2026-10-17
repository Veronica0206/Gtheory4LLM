\name{gt_fit}
\alias{gt_fit}
\alias{print.gt_fit}
\alias{summary.gt_fit}
\title{Fit Univariate or Joint Multivariate Generalizability Models}
\description{Fits selected random-source covariance models using an exact balanced Gaussian likelihood or a dense first-order Laplace likelihood for discrete outcomes.}
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
\item{design}{A declaration created by \code{gt_design()}. Omit it with a formula, which supplies the design; a family given in this position after a formula is read as \code{family}, the order \code{glm()} users expect. Replicates, batches and the automatic nesting selectors have no formula syntax and need \code{gt_design()}.}
\item{formula}{The model formula under its own name, for calls such as \code{gt_fit(formula = score ~ item * rater, data = d)}; the same as giving it as \code{outcomes}.}
\item{measured}{With a formula, the name of the right-hand variable that is the object of measurement. \code{NULL} takes the first variable on the right, and the fit's design records which rule applied. Re-ordering a formula without \code{measured} changes the object of measurement, and with it every reliability coefficient, while the variance components stay the same; name it whenever the order is not deliberate. The argument is not called \code{object} because that is the first argument of \code{update()} and the other model generics.}
\item{family}{One \code{gt_family} object for all outcomes, or a named list matching outcomes exactly. Multiple discrete families can be modeled jointly. Joint Gaussian-discrete likelihoods are not implemented.}
\item{estimator}{Gaussian: \code{"REML"} (default) or \code{"ML"}. Discrete: \code{"ML_Laplace"}.}
\item{covariance}{\code{"unstructured"} or \code{"diagonal"}; Gaussian also accepts named source overrides, with unspecified sources using diagonal covariance. Discrete source covariance uses the common requested structure.}
\item{residual}{The Gaussian residual structure. Choose \code{"unstructured"}, \code{"diagonal"}, or \code{"pooled"}; pooled gives equal outcome variances. Omit for discrete outcomes.}
\item{control}{A \code{gt_control} object.}
\item{x, object}{A fitted \code{gt_fit} object for the print or summary method.}
\item{...}{Further method arguments; currently unused.}
}
\value{A \code{gt_fit} object whose class vector is \code{"gt_gaussian_fit"} or \code{"gt_discrete_fit"}, according to the engine, followed by \code{"gt_fit"}. It contains source covariance matrices, estimates, likelihood and parameter counts, the resolved design and observation families, modeled data, and numerical diagnostics. Gaussian objects also retain the OpenMx model, prepared sufficient statistics, an \code{uncertainty} record holding the parameter covariance matrix and its delta-method mapping to source covariance entries, and a \code{component_standard_errors} table. Discrete objects include thresholds or category contrasts and conditional probabilities evaluated at the random-effect mode. \code{print()} returns the fit invisibly. \code{summary()} returns a \code{summary.gt_fit} list with estimates, a source-variance table carrying standard errors and a boundary flag where they are available, full covariance components, for a Gaussian fit the observed-score reliability at the fitted facet counts as a \code{gt_reliability} object in \code{reliability} where the fit allows one and otherwise the reason in \code{reliability_note}, and diagnostics. Its \link[=print.summary.gt_fit]{print method} displays a concise report of numerical acceptance, selected attempts, boundaries, and estimates.}
\details{\strong{Formula interface.} \code{outcomes} may be a two-sided model formula, with the data frame given before or after it. \code{gt_fit(score ~ item * rater, data)} declares the outcome \code{score}, the object of measurement \code{item}, the facet \code{rater}, and the sources \code{item}, \code{rater} and \code{item:rater}. A joint fit of two outcomes is written \code{cbind(efficacy, safety) ~ item + rater}. Nothing in the formula is evaluated: it names columns and sources, and \code{fit$design$formula} records it. The resolved design is the object \code{gt_design(object, facets, random = ~ ...)} builds, so a formula fit and a design fit of the same sources are the same fit. Every fit, however declared, answers \code{formula()} and \code{update()}; see \code{\link{gt_fit_methods}}. The recorded \code{fit$call} names each argument, with the formula under \code{formula} and the data under \code{data} whichever order they were given in.

\strong{Engines.} Gaussian outcomes are fitted by the exact balanced likelihood through OpenMx, or, with \code{gt_control(gaussian = list(engine = "lme4"))}, by lme4 as random intercepts for the same sources; the two are the same likelihood, and the lme4 fit is cross-checked against the exact deviance at its estimates. Discrete outcomes have one engine, the dense first-order Laplace likelihood; \code{\link{gt_laplace_check}} measures its approximation error on a fitted model. \code{gt_diagnostics(fit)} records the engine, its optimizer and the approximation separately.

The Gaussian backend requires a complete coded Cartesian panel with one observation per cell and at most 4096 factorial strata. A design that declares equal fixed batches with \code{\link{gt_batch}} adds one source, \code{Call}, shared by the items of a batch under one condition, and one factorial axis, because an item is then a batch-by-slot cell; see \code{\link{gt_batch}} for when a declaration is modelled. Implicit normalized Helmert contrasts avoid quadratic allocation along a large object axis. Gaussian ML profiles one fixed intercept per outcome; REML includes the unscaled-intercept constant D * log(N). Gaussian ML AIC counts covariance parameters and profiled means. Its generic BIC uses N response vectors; \code{ml_BIC_scalar_scores} explicitly provides the alternative N * D convention. \code{legacy_AIC} and \code{legacy_BIC} preserve the archive's variance-only parameter convention. For REML the fit's \code{AIC} and \code{BIC} elements are \code{NA}; \code{AIC()} and \code{BIC()} use the restricted likelihood with covariance parameters only, \code{BIC()} over N response vectors. The fit records the \code{AIC()} value, the \code{BIC()} value, and the alternative N * D scalar-score BIC under explicit names, in that order:
\itemize{
\item \code{reml_AIC_variance_parameters}
\item \code{reml_BIC_response_vectors_variance_parameters}
\item \code{reml_BIC_scalar_scores_variance_parameters}
}

Discrete models use binary links, ordinal thresholds, or unordered reference-category softmax contrasts. They do not estimate a free Gaussian observation residual. Probit latent residual variance is identified as 1; logit as pi^2 / 3. Unsupported observation-level sources, aliased free source kernels, missing categories, and resource-limit violations are rejected.

Returned binary probabilities evaluate each tail directly, preserving small
representable probabilities and the declared category order. These are
conditional probabilities at the random-effect mode, not population-marginal
probabilities.

Gaussian fitting also computes asymptotic Wald standard errors for the source variance components from the numerically differentiated restricted- or profile-likelihood Hessian. These are large-sample quantities conditional on the declared model; they do not establish coverage in small designs and do not apply to a component resting on a variance boundary. \code{check_hessian = FALSE} disables them along with the other derivative diagnostics.

Numerical acceptance includes optimizer completion and independent stationarity, bound, and tighter-tolerance restart checks. First-order stationarity does not establish a global optimum. A numerically accepted Laplace fit still requires an assessment of approximation adequacy for the intended analysis. Reliability and decision studies reject fits that fail numerical acceptance.}
\seealso{\code{\link{gt_design}}, \code{\link{gt_control}}, \code{\link{gt_diagnostics}}. The package installs a worked first discrete fit as \code{discrete-first.R}; the example below shows how to source it.}
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
formula_fit <- gt_fit(score ~ item + rater, d,
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
binary_formula <- gt_fit(label ~ item + rater, b, gt_family("binary"))
all.equal(gt_components(binary_formula), gt_components(binary_fit))
# The installed worked example, start to finish:
script <- system.file("examples", "discrete-first.R",
                      package = "Gtheory4LLM")
file.exists(script)
}
