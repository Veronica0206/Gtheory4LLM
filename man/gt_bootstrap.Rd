\name{gt_bootstrap}
\alias{gt_bootstrap}
\alias{print.gt_bootstrap}
\alias{summary.gt_bootstrap}
\alias{as.data.frame.gt_bootstrap}
\title{Object Bootstrap of an Accepted Fit}
\description{Resamples the objects of measurement with replacement, each with its complete instrumentation panel, refits every resample under the fit's model and the recorded refit controls, and keeps the accepted replicates' source covariance matrices. \code{\link{gt_reliability}} and \code{\link{gt_dstudy}} then take percentile or BCa intervals from them, and \code{summary()} gives intervals for the variance components.}
\usage{
gt_bootstrap(fit, replicates = 1000L, seed, max_attempts = 2L * replicates,
  jackknife = FALSE, warm_start = TRUE, cores = 1L, data = NULL,
  control = NULL)
\method{print}{gt_bootstrap}(x, ...)
\method{summary}{gt_bootstrap}(object, level = 0.95,
  interval_type = c("percentile", "bca"), ...)
\method{as.data.frame}{gt_bootstrap}(x, row.names = NULL, optional = FALSE, ...)
}
\arguments{
\item{fit}{A Gaussian or discrete fit that was numerically accepted, of a panel in which every object shares one instrumentation layout. A fit with declared batches is refused, because resampling items would break its fixed call layout, and so is a fit whose objects do not share one layout, because a resample could lose a facet level confined to the objects it omits.}
\item{replicates}{The number of accepted refits wanted.}
\item{seed}{Required integer seed between zero and \code{.Machine$integer.max}. The caller's random-number state is restored.}
\item{max_attempts}{The largest number of resamples to try; it cannot be smaller than the number of replicates wanted. Resampling stops when that many refits are accepted or the budget is spent.}
\item{jackknife}{\code{TRUE} also refits the data with each object left out once, which BCa intervals need for their acceleration. This costs one refit per object.}
\item{warm_start}{For discrete fits, \code{TRUE} starts each refit's primary attempt at the original estimates. A source on its covariance boundary starts from the original fit's starting values instead, so no refit begins on a zero factor column. The alternative starts and every acceptance check still apply. Gaussian refits always start as the original fit did.}
\item{cores}{Processes to use. More than one forks the R session through the parallel package, which cannot fork on Windows. Each attempt draws from its own seed, so the replicates do not depend on this value.}
\item{data}{The original modelled observations and design identifiers, in their
fitted row order; needed when the fit was stored without its data. A supplied
copy is checked against retained observations or a compact identity recorded
before data retention. Matching only the panel dimensions is insufficient.
Row names, unused columns, column order and factor storage do not matter;
permuting rows is refused because object encounter order determines seeded
resampling. Original category labels and the fit's retained binary codes are
accepted under the fit's recorded category order. Older fits that kept neither
observations nor a verifiable identity must be refitted.}
\item{control}{A \code{\link{gt_control}} for the refits; by default the fit's
own. Explicit controls set the refits' numerical settings and acceptance
thresholds, so they need not match those used for the original fit. They must
preserve any \code{fixed_covariance} matrices: adding, removing or changing fixed
source covariances would change the model and is refused. Equivalent source
and matrix-label ordering is allowed. The bootstrap does not automatically
relax acceptance thresholds. Refits compute no observed information, which
plays no part in acceptance.}
\item{x, object}{A \code{gt_bootstrap} object.}
\item{level}{Confidence level for the component intervals.}
\item{interval_type}{\code{"percentile"} or \code{"bca"}; BCa needs \code{jackknife = TRUE}.}
\item{row.names, optional, ...}{Generic arguments; \code{row.names} sets the record's row names, and the others are unused.}
}
\value{A \code{gt_bootstrap} list with the resampled unit (the object column), the number of objects, the requested and accepted replicate counts, the number of attempts, the accepted replicates' source covariance matrices in attempt order, an attempt record, the leave-one-out refits when requested, the original fit's estimates that identify it, the settings, and an interpretation.

The attempt record, also returned by \code{as.data.frame()}, has one row per attempt up to the last accepted replicate used: the attempt number, its resampling seed, the retry seed the refit used (an explicit Gaussian \code{retry_seed} in the controls, which every refit then uses, or else one from the same stream), its status (\code{"accepted"}, \code{"refused"} or \code{"error"}), the acceptance failures or error message, elapsed seconds, the number of warnings, the deviance, and the sources on their covariance boundary. The leave-one-out record names the object left out instead of a resampling seed.

The settings retain \code{jackknife}, the requested \code{gt_control}, and a
\code{refit_control} template after the bootstrap's information and warm-start
adjustments. Per-attempt retry seeds come from the records unless an explicit
Gaussian retry seed is present. The template does not reconstruct engine
defaults or optimizer-internal restart states; retain the source archive and
numerical environment alongside it.

New bootstrap objects also record the fitted data identity, which is checked
when attaching intervals to a fit or report. Legacy bootstrap objects without
this identity retain the older estimate-based association checks; they cannot
verify that the underlying observations and identifiers match.

\code{summary()} returns a data frame with one row per unique entry of each source covariance matrix: the original estimate, the bootstrap standard error, the interval bounds, and the number of finite replicate values.}
\details{
\strong{The resample.} Objects are drawn with replacement, as many as were fitted. A drawn object keeps all of its rows, so its complete panel of evaluators, prompts and other facet levels travels with it, and an object drawn more than once enters the refit as that many distinct objects. Every object must share one instrumentation layout: the same facet-level combinations, as often, with the same outcomes observed. The facet levels are then the observed ones in every replicate, and objects that share one partial layout keep it. When the layouts differ, a level confined to some objects would be lost from every resample that omits them, so such a fit is refused. Resampling the object facet is the boot-p procedure of Brennan (2001). No resampling scheme reproduces the sampling of a crossed random design exactly (McCullagh, 2000).

\strong{What the intervals describe.} Object-sampling uncertainty, conditional on the observed instrumentation levels, on the declared model, and on numerical acceptance. They do not reflect that the evaluators, prompts or other facet levels were themselves a sample, which the random-facet Wald intervals do; sources without the object, such as an evaluator main effect, are therefore estimated from the same levels in every replicate. Relative coefficients depend mainly on object-level sources; absolute coefficients also depend on facet main effects, so their bootstrap intervals can be narrower than the corresponding Wald intervals. Neither is a calibration guarantee.

\strong{Acceptance.} Each refit uses the fit's design, families, estimator and resolved covariance structures, including fixed source covariances. Numerical checks use the recorded refit controls, which default to the original controls and may be explicitly overridden. A refused or failed refit is recorded with its reason and never stands in for an accepted one. Resampling continues to \code{max_attempts}; when fewer than \code{replicates} are accepted the object says so. Dropping refused refits conditions the intervals on fitting success; report the attempt record beside them.

\strong{Intervals.} The original fit supplies every point estimate. Percentile intervals are type 6 sample quantiles (see \code{\link[stats]{quantile}}) of the finite replicate values. BCa intervals adjust the percentiles for the share of replicates below the estimate and for the leave-one-out skewness (Efron, 1987). An interval needs a finite original estimate and at least 50 finite replicate values; BCa also needs every leave-one-out refit accepted and finite. An endpoint whose percentile falls outside \eqn{[1/(B+1), B/(B+1)]}, for \eqn{B} finite values, has no replicate support and is reported as \code{NA}. The bootstrap standard error is the standard deviation of the replicate values.

\strong{Coverage.} In a frozen pilot of the Gaussian item-by-rater design with 24 items and three or six raters, 200 REML panels per setting and 500 replicates each, 95\% percentile intervals covered the population coefficients in 92.0--94.0\% of panels for Erho2 and 89.5--92.5\% for Phi; BCa intervals were available in 85--99\% of panels and covered in 89.1--93.8\% of those; delta-method intervals on the same panels covered in 95.0--97.0\%. The shortfall also occurred at zero rater variance. Coverage for other designs, larger panels and discrete or multivariate fits has not been assessed. The protocol and results are in the package repository under \file{validation-studies/bootstrap-coverage}.

\strong{Cost.} A bootstrap costs one fit per attempt, and the leave-one-out refits one fit per object. Small Gaussian fits take a fraction of a second each; joint categorical fits of large panels can take an hour or more each, which makes a bootstrap of them a matter of days even across many cores. For those, the boundary-conditional Wald intervals of \code{gt_control(discrete = list(check_hessian = TRUE))} remain available.
}
\references{
Brennan, R. L. (2001). \emph{Generalizability Theory}. Springer. \doi{10.1007/978-1-4757-3456-0}

Efron, B. (1987). Better bootstrap confidence intervals. \emph{Journal of the American Statistical Association}, 82(397), 171--185. \doi{10.1080/01621459.1987.10478410}

McCullagh, P. (2000). Resampling and exchangeable arrays. \emph{Bernoulli}, 6(2), 285--301.\cr \doi{10.2307/3318577}
}
\seealso{\code{\link{gt_reliability}}, \code{\link{gt_dstudy}}, \code{\link{gt_fit}}}
\examples{
set.seed(2)
d <- expand.grid(rater = factor(1:4), item = factor(1:30))
d$score <- rnorm(30)[d$item] + rnorm(4, sd = 0.5)[d$rater] + rnorm(nrow(d), sd = 0.7)
fit <- gt_fit(d, "score", gt_design("item", "rater"))
\donttest{
boot <- gt_bootstrap(fit, replicates = 200, seed = 11)
boot
gt_reliability(fit, bootstrap = boot)
gt_dstudy(fit, data.frame(rater = c(1, 2, 8)), bootstrap = boot)
summary(boot)
}
}
