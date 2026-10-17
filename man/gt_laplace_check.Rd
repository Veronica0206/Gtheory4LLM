\name{gt_laplace_check}
\alias{gt_laplace_check}
\alias{print.gt_laplace_check}
\title{Measure the Laplace Error of a Discrete Fit at Its Fitted Parameters}
\description{Re-evaluates the marginal likelihood of a binary, ordinal or categorical fit by a higher-accuracy method at the fitted parameters and reports how far the first-order Laplace objective is from it.}
\usage{
gt_laplace_check(fit, method = c("auto", "quadrature", "importance"),
  nodes = 20L, draws = 4000L, seed = NULL, max_dimension = 60L,
  data = NULL)
\method{print}{gt_laplace_check}(x, ..., digits = 6L)
}
\arguments{
\item{fit}{A discrete \code{gt_fit} object. A Gaussian fit is refused: its likelihood is exact.}
\item{method}{\code{"quadrature"} is adaptive Gauss-Hermite quadrature on a product grid, available up to four random-effect dimensions. \code{"importance"} is importance sampling from the Gaussian that the Laplace solution provides. \code{"auto"} chooses quadrature up to three dimensions and importance sampling otherwise.}
\item{nodes}{Quadrature nodes per dimension, from 5 to 80. The reference is also computed with five more nodes, and the change is reported.}
\item{draws}{Importance-sampling draws, from 100 to one million.}
\item{seed}{Integer seed for importance sampling, required there so that the check can be reproduced. The caller's random-number state is restored.}
\item{max_dimension}{The largest random-effect dimension the check accepts. An estimate by importance sampling degrades as the dimension grows, so raise this together with \code{draws}.}
\item{data}{The modelled data frame, needed only when the fit was stored without its data.}
\item{x}{A \code{gt_laplace_check} object.}
\item{digits}{Significant digits for the printed likelihood values.}
\item{...}{Further print arguments; currently unused.}
}
\value{A \code{gt_laplace_check} list: \code{laplace_minus2loglik}, the Laplace objective recomputed at the fitted parameters; \code{reference_minus2loglik}, the higher-accuracy value; \code{difference}, Laplace minus reference, and \code{per_observation}; \code{method}, \code{random_dimension}, \code{observations}, \code{nodes} or \code{draws} with \code{seed}, and \code{evaluations}; for importance sampling \code{mc_se}, the Monte Carlo standard error of the reference in minus-two-log-likelihood units, and \code{effective_sample_size}; for quadrature \code{refinement_difference}; \code{stored_minus2loglik} with \code{recomputed_agrees}, whether the recomputed Laplace objective matches the fit's own; \code{numerically_accepted}; and \code{scope}. \code{print()} returns the object invisibly.}
\details{The Laplace objective is \eqn{f(\hat u) + \hat u'\hat u/2 + \log\det R}, where \eqn{f} is the conditional negative log likelihood of the standardized random effects \eqn{u}, \eqn{\hat u} is the conditional mode, and \eqn{R'R} is the Hessian of \eqn{f(u) + u'u/2} at the mode. The marginal likelihood it approximates is \eqn{\int \exp(-f(u))\,\phi(u)\,du}. The check evaluates that integral through the Gaussian \eqn{N(\hat u, (R'R)^{-1})}: as an adaptive Gauss-Hermite sum over a product grid, or as the mean of importance weights over draws from that Gaussian, with the Monte Carlo standard error and the effective sample size of the weights.

The difference measures the error of the first-order approximation in the objective at the fitted parameters, for this fit. It is not a measure of bias in the estimates, which would need refitting under the higher-accuracy likelihood, and a small difference on one fit does not establish adequacy on another. The quadrature branch is deterministic, and its refinement change says whether the grid was fine enough. The importance-sampling branch is a Monte Carlo estimate whose standard error grows with the random-effect dimension, which is why the dimension is capped. The repository's discrete-laplace validation study applies the same comparison to generated panels; this function applies it to a user's fit.

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
