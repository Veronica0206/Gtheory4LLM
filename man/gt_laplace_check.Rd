\name{gt_laplace_check}
\alias{gt_laplace_check}
\alias{print.gt_laplace_check}
\title{Refined Numerical Comparison for a Discrete Fit's Laplace Objective}
\description{Re-estimates the marginal likelihood of a binary, ordinal or categorical fit at its fitted parameters by a refined numerical method and reports how far the first-order Laplace objective is from that estimate, together with whether the estimate is usable.}
\usage{
gt_laplace_check(fit, method = c("auto", "quadrature", "importance"),
  nodes = 20L, draws = 4000L, seed = NULL, max_dimension = 60L,
  max_evaluations = 1000000L, data = NULL)
\method{print}{gt_laplace_check}(x, ..., digits = 6L)
}
\arguments{
\item{fit}{A discrete \code{gt_fit} object. A Gaussian fit is refused: its likelihood is exact.}
\item{method}{\code{"quadrature"} is adaptive Gauss-Hermite quadrature on a product grid, available up to four random-effect dimensions. \code{"importance"} is importance sampling from the Gaussian that the Laplace solution provides. \code{"auto"} chooses quadrature up to three dimensions and importance sampling otherwise.}
\item{nodes}{Quadrature nodes per dimension, from 5 to 80. The estimate is also computed with five more nodes, and the change is reported.}
\item{draws}{Importance-sampling draws, from 100 to one million.}
\item{seed}{Integer seed for importance sampling, required there so that the check can be reproduced. The caller's random-number state is restored.}
\item{max_dimension}{The largest random-effect dimension the check accepts. An estimate by importance sampling degrades as the dimension grows, so raise this together with \code{draws}.}
\item{max_evaluations}{The largest number of integrand evaluations the check will run. Quadrature in \code{d} dimensions needs \code{nodes} to the power \code{d} evaluations plus the same with five more nodes; importance sampling needs \code{draws}. Both this and \code{max_dimension} are applied before anything is allocated or solved.}
\item{data}{The modelled data frame, needed only when the fit was stored without its data.}
\item{x}{A \code{gt_laplace_check} object.}
\item{digits}{Significant digits for the printed likelihood values.}
\item{...}{Further print arguments; currently unused.}
}
\value{A \code{gt_laplace_check} list. \code{available} says whether a refined estimate could be computed at all, and \code{reason} why not when it could not: no Cholesky factor at the mode, a factor that failed the package's solve check, or integrand points that could not be evaluated; \code{unavailable_evaluations} counts those points. When it is available, \code{usable} and \code{reason} give the verdict of the method's own stability rule: for quadrature, that five more nodes per dimension reproduce the estimate to one part in a million of the objective; for importance sampling, that the effective sample size is at least 200 and at least a tenth of the draws. The numbers are \code{laplace_minus2loglik}, the Laplace objective recomputed at the fitted parameters; \code{refined_minus2loglik}, the refined estimate; \code{difference}, Laplace minus refined, and \code{per_observation}; \code{method}, \code{random_dimension}, \code{observations}, \code{nodes} or \code{draws} with \code{seed}, and \code{evaluations}; for importance sampling \code{mc_se}, the Monte Carlo standard error of the refined estimate in minus-two-log-likelihood units, and \code{effective_sample_size}; for quadrature \code{refinement_difference}; \code{stored_minus2loglik} with \code{recomputed_agrees}, whether the recomputed Laplace objective matches the fit's own; \code{numerically_accepted}; and \code{scope}. \code{print()} returns the object invisibly.}
\details{The Laplace objective is \eqn{f(\hat u) + \hat u'\hat u/2 + \log\det R}, where \eqn{f} is the conditional negative log likelihood of the standardized random effects \eqn{u}, \eqn{\hat u} is the conditional mode, and \eqn{R'R} is the Hessian of \eqn{f(u) + u'u/2} at the mode. The marginal likelihood it approximates is \eqn{\int \exp(-f(u))\,\phi(u)\,du}. The check evaluates that integral through the Gaussian \eqn{N(\hat u, (R'R)^{-1})}: as an adaptive Gauss-Hermite sum over a product grid, or as the mean of importance weights over draws from that Gaussian, with the Monte Carlo standard error and the effective sample size of the weights.

The difference measures the error of the first-order approximation in the objective at the fitted parameters, for this fit. It is not a measure of bias in the estimates, which would need refitting under the refined likelihood, and a small difference on one fit does not establish adequacy on another. Refined is a goal, not a property of the number: the quadrature branch is deterministic and its refinement change is evidence of numerical stability, not an error bound; the importance-sampling branch is a Monte Carlo estimate whose weights can miss tail mass that its standard error and effective sample size do not reveal, and whose variance grows with the random-effect dimension, which is why the dimension is capped. The repository's discrete-laplace validation study applies the same comparison to generated panels; this function applies it to a user's fit.

The comparison introduces its own linear algebra, and that is checked as the engines check theirs: the Cholesky factor at the mode must solve the package's fixed probe systems, every triangular solve that places an integration point is verified against its own system, and an integrand value the response kernel cannot evaluate is counted as unavailable rather than taken as zero. When any of these fails, the result says the refined estimate is unavailable and gives no number in its place.

This function does not refit the model. Adaptive quadrature as a fitting method is available in \pkg{lme4} and \pkg{ordinal} for a single scalar random-effect term only, which is why a crossed multi-source design cannot simply substitute quadrature for the Laplace engine; the trade-off belongs in the analysis report, with this diagnostic as its per-fit evidence where it is supported.

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
