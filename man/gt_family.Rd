\name{gt_family}
\alias{gt_family}
\title{Specify a Gaussian, Binary, Ordinal, or Unordered Categorical Outcome}
\description{Keeps observation families distinct and defines their links and category interpretation.}
\usage{
gt_family(family = "gaussian", link = NULL, levels = NULL,
  reference = NULL)
}
\arguments{
\item{family}{One of \code{"gaussian"}, \code{"binary"}, \code{"ordinal"}, or \code{"categorical"}.}
\item{link}{Gaussian uses identity; binary and ordinal use probit (default) or logit; unordered categorical uses softmax.}
\item{levels}{Distinct category labels. Binary levels are negative then positive. Ordinal levels give the substantive order. Categorical levels identify categories without assigning an order. Gaussian outcomes have no category levels.}
\item{reference}{One unordered categorical reference category. Defaults during fitting to the first declared category.}
}
\value{A \code{gt_family} object describing the observation distribution.}
\details{Numeric binary responses must be 0/1. Ordinal and categorical families require at least three categories; use the separate binary family for two categories. Ordinal order must come from declared levels or an ordered factor. Every declared category must occur in the fitted data. Numeric Gaussian outcomes are never constructed by silently converting factors.

Categorical random effects use reference-category contrasts. An unstructured covariance can be transformed under a reference change; a diagonal contrast covariance imposes a model restriction that depends on the reference category.}
\seealso{\code{\link{gt_fit}}}
\examples{
gt_family()
gt_family("binary", link = "logit")
gt_family("ordinal", levels = c("low", "middle", "high"))
gt_family("categorical", levels = c("red", "blue", "green"), reference = "blue")
}
