\name{gt_score}
\alias{gt_score}
\alias{print.gt_score}
\title{Declare Composite-Score Weights}
\description{Stores explicit weights without normalizing or choosing a score scale.}
\usage{
gt_score(weights)
\method{print}{gt_score}(x, ...)
}
\arguments{
\item{weights}{Finite numeric vector with unique outcome names and at least one nonzero entry. Every modeled outcome must be weighted exactly once when used in a reliability calculation.}
\item{x}{A \code{gt_score} object for the print method.}
\item{...}{Further print arguments; currently unused.}
}
\value{A \code{gt_score} object containing weights and the \code{"as_supplied"} normalization policy. \code{print()} shows the weights and returns the object invisibly.}
\details{Weights must be substantively meaningful on the chosen outcome scale. A latent binary/ordinal composite is not an observed-score composite. Negative and non-unit-sum weights are allowed.}
\seealso{\code{\link{gt_reliability}}, \code{\link{gt_dstudy}}}
\examples{
gt_score(c(efficacy = 0.5, safety = 0.5))
}
