\name{gt_control}
\alias{gt_control}
\title{Configure Gaussian and Discrete Fitting and Acceptance Checks}
\description{Collects backend controls in separate named lists, together with which optional components a fitted object keeps. Backend-specific names and values are checked when a model is fitted.}
\usage{
gt_control(gaussian = list(), discrete = list(), retain = list())
}
\arguments{
\item{gaussian}{Uniquely named list of Gaussian settings, described below.}
\item{discrete}{Uniquely named list of discrete settings, described below.}
\item{retain}{Uniquely named list of logical retention switches, described below. Every default is \code{TRUE}.}
}
\value{A \code{gt_control} object with separate Gaussian and discrete control lists and a resolved retention record.}
\details{\strong{Retained components.} \code{retain} decides which optional parts of a fitted object are kept. All four default to \code{TRUE}, so a fit keeps exactly what it kept before these switches existed; dropping a component is always something the caller asked for.
\itemize{
\item \code{data}: the modelled data frame. Dropping it removes every copy of the observations from the fit, including the summary copy the Gaussian OpenMx model carried.
\item \code{model}: the Gaussian OpenMx model and its factorial cross-products, and for a discrete fit the conditional predictors and probabilities held for every observation. The OpenMx model carries its own copy of the observations until \code{data} is dropped, so with them this is usually the largest component. The observed outcome variances are kept either way, so the correlations that \code{gt_components()} can report are unaffected.
\item \code{retry_log}: the optimizer transcript and the bulky per-attempt payloads. Each attempt's label, error, optimizer code and message, and objective are kept, so \code{gt_diagnostics()} reports the same decisions and reasons.
\item \code{session}: the \code{sessionInfo()} record. Keep it for reproducible research; it is worth its size when a result must be traced to an environment.
}

None of these components is used to compute an estimate, a diagnostic decision, a coefficient, or a decision study. \code{gt_reliability()} and \code{gt_dstudy()} work from the fitted source covariances, the resolved design, and either the retained data or the compact panel summary every fit records. With \code{data = TRUE} the balanced-panel rules are checked against the retained data, so a panel edited after fitting is still caught; with \code{data = FALSE} the same two rules are applied to the recorded summary. The fit keeps a \code{retained} record of what was dropped.

\strong{Gaussian controls} and their defaults are:
\itemize{
\item \code{optimizer}: CSOLNP.
\item \code{max_iterations}: 3000.
\item \code{tolerance}: 1e-12.
\item \code{check_hessian}: TRUE.
\item \code{threads}: 1.
\item \code{silent}: TRUE.
\item \code{extra_tries}: 9.
\item \code{retry_seed}: NULL.
\item \code{start}: NULL (automatic moment-based covariance starts).
\item \code{max_preparation_bytes}: 512 * 1024^2.
}
The allocation guard estimates preparation memory, excluding caller data and downstream OpenMx objects. An explicit retry seed preserves the caller's random-number state.
Gaussian \code{start} accepts a complete named list of covariance matrices for
all model sources, including \code{Residual}. Fully named matrix axes are matched
independently to the outcome names; both unnamed axes use outcome order.
Incomplete, duplicate, or incompatible labels are rejected. Admissible matrices
receive the engine's existing interior eigenvalue floor. Diagonal models retain
their repaired diagonal entries, and a pooled residual starts from the mean
of those entries. These values initialize estimated parameters; they do not
fix their fitted values.

Discrete resource limits are:
\itemize{
\item \code{max_random_dimension}: 200.
\item \code{max_observations}: 1200.
\item \code{max_parameters}: 80.
\item \code{max_dense_bytes}: 512 * 1024^2.
}
Discrete optimizer controls are:
\itemize{
\item \code{maxit}: 150.
\item \code{inner_maxit}: 60.
\item \code{inner_tol}: 1e-7.
\item \code{reltol}: 1e-7.
\item \code{start_sd}: 0.4.
\item \code{trace}: 0.
\item \code{optimizer}: \code{"L-BFGS-B"}; alternatively \code{"nlminb"}.
\item \code{start}: NULL (automatic response and covariance starts).
\item \code{covariance_parameterization}: \code{"auto"}.
}
The default \code{"auto"} uses direct nonnegative variance coordinates for
univariate models and for joint models whose \code{covariance} is
\code{"diagonal"}.
Joint models with unstructured covariance use \code{"log_cholesky"}, retaining
all cross-outcome covariance parameters. Explicit \code{"variance"} and
\code{"log_cholesky"} selections remain available. Direct variance coordinates
admit exact zeros; an explicit \code{"variance"} request with joint unstructured
covariance is rejected rather than removing covariances. The variance upper
bound is \code{exp(10)}, matching the largest diagonal variance allowed by the
log-Cholesky bounds. \code{start_sd}
still denotes a starting standard deviation and must be positive.

Discrete \code{start} is a finite, uniquely named numeric vector of optimizer
parameters, with complete or partial overrides of the automatic starts. Names
are matched exactly; unknown names and values outside the model bounds are
rejected. Automatic starts are also checked against the bounds before fitting;
the optimizer never silently projects an invalid starting vector. Labels that
produce ambiguous parameter names are rejected. The fitted
\code{fit$parameters} vector can initialize a refit of the
same model, with unchanged family links, category coding, covariance structure,
and covariance parameterization. These are optimizer coordinates: ordinal
threshold parameters contain the first threshold followed by log positive gaps;
log-Cholesky diagonal parameters are log standard deviations; direct-variance
parameters are variances. Actual and automatic initial vectors are retained in
the diagnostics, and \code{fit$starting_parameters} records the primary start.
Alternative starts perturb fixed-effect coordinates from the primary start and
use the automatic covariance starts with distinct deterministic scale
perturbations. If clipping would duplicate an earlier start, a bounded
fixed-effect perturbation makes the additional trial distinct.

The selected discrete optimizer remains fixed for primary fits, alternatives,
and tight refinements; the engine never silently switches algorithms.
\code{maxit} limits iterations per optimization. For \code{nlminb}, the function
evaluation budget is \code{max(200, 10 * maxit)}, and \code{reltol} supplies its
relative objective tolerance. Each optimizer uses its own native stopping rules;
the same independent numerical-acceptance checks apply afterward. Optimizer
choice is not evidence of approximation accuracy.

Zero is a natural lower boundary in direct variance coordinates, not an artificial
optimizer floor. Within \code{gt_diagnostics(fit)$diagnostics}, the
\code{zero_variance_parameters} field lists exact zeros. These estimates must
still pass independent covariance-scale stationarity and restart checks. All upper
bounds and fixed-effect/threshold bounds remain artificial and still cause
rejection on contact. This mode does not establish approximation accuracy or
sampling properties for boundary estimates.
The diagnostics field \code{covariance_parameterization_requested} records the
control selection; \code{covariance_parameterization} records the resolved
coordinates (\code{"variance"}, \code{"log_cholesky"}, or \code{"fixed"}).

Discrete numerical-acceptance controls are:
\itemize{
\item \code{stationarity_tol}: 1e-3.
\item \code{validation_reltol}: 1e-10.
\item \code{validation_inner_tol}: 1e-9.
\item \code{alternative_starts}: 1.
\item \code{stability_objective_tol}: 1e-6.
\item \code{stability_parameter_tol}: 0.02.
\item \code{bound_tol}: 1e-4.
}
Setting alternative starts to zero disables numerical acceptance, not just an optional report.
The discrete optimization-attempt budget is
\code{2 * (1 + alternative_starts)}: one preliminary and one tight fit for
the primary start and each alternative. Final-mode and stationarity evaluations
are recorded separately and are not additional optimization trials. Gaussian
\code{extra_tries} and discrete \code{alternative_starts} therefore have different
meanings. Covariance derivative accuracy uses at most six step halvings when
needed, without changing the stationarity or derivative-disagreement tolerances.
Every stationarity evaluation, including the center and all fixed-effect and
covariance perturbations, must have a valid, converged conditional mode and
usable finite likelihood. A failed evaluation ends the diagnostic and records
a validation error; an optimizer penalty is never treated as a derivative.

For a known-covariance calculation, \code{fixed_covariance} can provide one positive-semidefinite matrix for every discrete random source. Fully named matrices are matched and reordered to the latent dimensions; unnamed matrices are positional. Partial or incompatible dimension names are rejected. These matrices are fixed assumptions rather than estimated source covariances. The covariance parameterization setting is not used when all covariances are fixed.

The \code{attempts} entry of \code{gt_diagnostics(fit)$diagnostics} retains
starts, controls, optimizer codes, messages, errors, warnings, elapsed time, and
returned parameters. A computational failure during
refinement, a restart, or stationarity checking prevents numerical acceptance but
preserves an otherwise usable primary or alternative fit for inspection.
Unusable optimizer returns are retained unchanged as \code{raw_result}, separately
from the computational placeholder. The selected attempt, optimizer, trial count,
and budget are also reported. If no fitted candidate supplies
a usable conditional mode, a \code{gt_discrete_numerical_failure} error condition
retains the attempt records instead. Invalid input still fails before fitting.
Warnings captured during numerical attempts are retained in these diagnostics;
user interrupts are not swallowed.

\code{max_dense_bytes} bounds the dense algebra that the other discrete limits
imply, and is checked before anything is allocated. The estimate covers the
random-design matrix, the conditional Hessian and its factor, the slices of the
design matrix that forming that Hessian materializes, the linear predictor and
gradient, and a planning multiplier for copy-on-modify. It is not peak resident
memory: it excludes the caller's data, the optimizer's own state, and the
allocation the finite-difference stationarity pass repeats, so it underestimates
what a fit really uses. Its purpose is to refuse the obviously impossible with a
message naming the observation count, the random dimension, and the size of the
random-design matrix, rather than to certify that a permitted model is
comfortable. \code{gt_preflight()} reports the same estimate and its breakdown
under \code{$resources}. Raising this limit makes neither the dense algebra
practical nor the approximation accurate.

Optimizer completion, numerical acceptance, and approximation adequacy are separate. Tighter numerical tolerances do not establish the adequacy of a first-order Laplace approximation.}
\seealso{\code{\link{gt_diagnostics}}, \code{\link{gt_fit}}}
\examples{
gt_control(gaussian = list(retry_seed = 123, check_hessian = FALSE),
  discrete = list(max_random_dimension = 100, alternative_starts = 1))
# Auto selects boundary-capable coordinates when the covariance model permits.
gt_control(discrete = list(covariance_parameterization = "auto"))
gt_control(discrete = list(optimizer = "nlminb", alternative_starts = 2))
# A lean fit for a large panel: estimates, diagnostics, reliability and
# decision studies are unchanged; the stored copies of the data are not kept.
gt_control(retain = list(data = FALSE, model = FALSE))
}
