\name{gt_laplace_check}
\alias{gt_laplace_check}
\alias{print.gt_laplace_check}
\title{Refined Numerical Comparison for a Discrete Fit's Laplace Objective}
\description{Estimates the marginal likelihood of a binary, ordinal or categorical fit at fixed fitted parameters by a numerical comparison method. Reports the difference from the first-order Laplace objective, numerical diagnostics, and whether an empirical stability screen passed. Passing that screen is not an accuracy guarantee.}
\usage{
gt_laplace_check(fit, method = c("auto", "quadrature", "importance"),
  nodes = 20L, draws = 4000L, seed = NULL, max_dimension = 60L,
  max_evaluations = 1000000L, data = NULL)
\method{print}{gt_laplace_check}(x, ..., digits = 6L)
}
\arguments{
\item{fit}{A discrete \code{gt_fit} object. A Gaussian fit is refused: its likelihood is exact.}
\item{method}{\code{"quadrature"} is adaptive Gauss-Hermite quadrature on a product grid, available up to four random-effect dimensions. \code{"importance"} uses a defensive mixture: 90\% the Gaussian at the conditional mode and 10\% the standard-normal prior on standardized random effects. Every importance weight uses the full mixture density. \code{"auto"} chooses quadrature up to three dimensions and importance sampling otherwise.}
\item{nodes}{Quadrature nodes per dimension, from 5 to 80. The estimate is also computed with five more nodes, and the change is reported.}
\item{draws}{Importance-sampling draws, from 100 to one million.}
\item{seed}{Integer seed for importance sampling, required there so that the check can be reproduced. The caller's random-number state is restored.}
\item{max_dimension}{The largest random-effect dimension the check accepts. Importance sampling can have poor relative precision in large dimensions. Raising this cap or \code{draws} does not ensure accuracy; examine independent seeds and increasing budgets.}
\item{max_evaluations}{The largest number of integrand evaluations the check will run. Quadrature in \code{d} dimensions needs \code{nodes} to the power \code{d} evaluations plus the same with five more nodes; importance sampling needs \code{draws}. Both this and \code{max_dimension} are applied before dense matrices are allocated or solved; the dense-memory budget described below also applies.}
\item{data}{The modelled data frame, needed only when the fit was stored without its data. A fitted Call source is reconstructed from retained item-to-batch membership, so auxiliary call-ID and order columns are optional. The original items and complete fixed layout must be present. Supplied auxiliary call columns must agree with the retained layout.}
\item{x}{A \code{gt_laplace_check} object.}
\item{digits}{Significant digits for the printed likelihood values.}
\item{...}{Further print arguments; currently unused.}
}
\value{A \code{gt_laplace_check} list. \code{available} says whether a numerical comparison could be computed, and \code{reason} explains any failure: no Cholesky factor at the mode, a factor that failed the package's solve check, or integrand points that could not be evaluated; \code{unavailable_evaluations} counts those points. When available, \code{usable} and \code{reason} give the verdict of an empirical stability screen: for quadrature, five more nodes per dimension reproduce the estimate to one part in a million of the objective; for importance sampling, empirical effective sample size is at least 200 and at least a tenth of the draws. This is a diagnostic screen, not a certificate of accuracy.

The returned numerical fields are:
\itemize{
\item \code{laplace_minus2loglik}: the objective recomputed at the fitted parameters.
\item \code{refined_minus2loglik}: the numerical comparison estimate.
\item \code{difference}: Laplace minus comparison. Its value per observation is \code{per_observation}.
\item \code{method}, \code{random_dimension}, and \code{observations}: the method and problem size.
\item \code{nodes}, or \code{draws} with \code{seed}: the integration controls. The evaluation count is \code{evaluations}.
\item \code{mc_se}: a delta-method estimate of Monte Carlo standard error in minus-two-log-likelihood units, for importance sampling.
\item \code{effective_sample_size}: the empirical importance-sampling ESS.
\item \code{proposal} and \code{prior_weight}: the mixture specification.
\item \code{proposal_draws}: the realized component counts.
\item \code{weight_upper_bound}: the theoretical bound on unnormalised weights.
\item \code{max_importance_weight}: the largest observed unnormalised weight.
\item \code{refinement_difference}: the quadrature change on the finer grid.
\item \code{stored_minus2loglik}: the objective retained by the fit.
\item \code{recomputed_agrees}: whether the recomputed objective matches the stored value.
\item \code{numerically_accepted}: the fit's numerical acceptance flag.
\item \code{resources}: estimated bytes for dense reconstruction, integration workspace, their total, and the applied \code{max_dense_bytes} budget. These conservative estimates are not measured peak memory.
\item \code{scope}: the qualifications on interpreting this comparison.
}
\code{print()} displays those qualifications and returns the object invisibly.}
\details{The Laplace objective is \eqn{f(\hat u) + \hat u'\hat u/2 + \log\det R}, where \eqn{f} is the conditional negative log likelihood of the standardized random effects \eqn{u}, \eqn{\hat u} is the conditional mode, and \eqn{R'R} is the Hessian of \eqn{f(u) + u'u/2} at the mode. The marginal likelihood it approximates is \eqn{\int \exp(-f(u))\,\phi(u)\,du}. Quadrature adapts a product grid using \eqn{N(\hat u, (R'R)^{-1})}.

Importance sampling instead uses \eqn{q(u) = 0.9\,\phi_H(u-\hat u) + 0.1\,\phi(u)}, where \eqn{\phi_H} has covariance \eqn{(R'R)^{-1}}. An independent component indicator selects the sampling distribution for each draw; the denominator of every weight is the full mixture density \eqn{q(u)}, not the density of the selected component. For these discrete observation models, \eqn{0 \leq \exp(-f(u)) \leq 1}. Since \eqn{q(u) \geq 0.1\phi(u)}, the unnormalised weights \eqn{\exp(-f(u))\phi(u)/q(u)} are bounded by 10 and have finite moments. A Gaussian-only proposal need not have finite weight variance; the prior component addresses that defect without changing the fitted model or Laplace objective.

The difference estimates approximation error in the objective at fixed parameters. It is not a measure of bias in fitted estimates, which would need refitting under a different likelihood. A stable quadrature refinement is evidence of numerical stability, not an error bound. Finite importance-weight moments do not guarantee useful relative precision or calibrated finite-sample Monte Carlo intervals. The log-likelihood estimate has finite-sample Monte Carlo bias, its reported standard error is a delta-method estimate, and empirical ESS can miss poorly sampled regions. Examine independent seeds and increasing draw budgets, preferably against an independent numerical reference on a tractable model. Neither a larger budget nor a passed screen establishes adequacy on another fit. The versioned \file{validation-studies/laplace-refinement} record compares the defensive-mixture diagnostic with independent integration on a bounded binary fixture; it is not a general validation of all designs or outcome families.

The comparison introduces its own linear algebra, and that is checked as the engines check theirs: the Cholesky factor at the mode must solve the package's fixed probe systems, every triangular solve that places an integration point is verified against its own system, and an integrand value the response kernel cannot evaluate is counted as unavailable rather than taken as zero. When any of these fails, the result says the refined estimate is unavailable and gives no number in its place.

The diagnostic uses dense conditional algebra even when the fitted engine was sparse. Before allocating dense matrices, it applies the fit's discrete \code{max_dense_bytes} control to a conservative estimate of dense reconstruction plus importance-proposal or quadrature-grid workspace. A fit that is feasible with sparse algebra can therefore exceed the diagnostic's memory budget. The dimension, evaluation and draw limits remain in force; raising a memory budget does not improve approximation accuracy. Fixed-layout Call sources use the retained item membership and the same layout validator as fitting. An absent or inconsistent retained layout is refused rather than replaced by newly inferred batches.

This function does not refit the model. Adaptive quadrature as a fitting method in \pkg{lme4} and \pkg{ordinal} is restricted to a single scalar random-effect term; it is not a direct substitute in those packages for a crossed multi-source fit. Other Monte Carlo likelihood methods exist for some crossed discrete models. A comparison must match the response family, link, covariance structure and estimand; this diagnostic does not replace such a refitted comparison.

A fit that failed numerical acceptance can still be checked. The result then describes its stopping point, and the print says so.}
\seealso{\code{\link{gt_fit}}, \code{\link{gt_diagnostics}}}
\examples{
b <- expand.grid(item = 1:3, rater = 1:8)
b$y <- as.integer((b$item + b$rater) \%\% 3 > 0)
fit <- gt_fit(b, "y", gt_design("item", "rater", random = ~ item),
  gt_family("binary", "logit"))
gt_laplace_check(fit)
gt_laplace_check(fit, method = "importance", draws = 2000, seed = 1)
}
