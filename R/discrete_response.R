# Discrete response probabilities, derivatives, and curvature.
# Loaded before discrete.R; shared validation helpers resolve at call time.

.gt_d_thresholds <- function(parameters) {
  if (length(parameters) == 1L) return(unname(parameters))
  unname(c(parameters[[1L]], parameters[[1L]] + cumsum(exp(parameters[-1L]))))
}

.gt_d_baseline <- function(parameters, prep) {
  eta <- matrix(0, prep$n, prep$q)
  for (block in prep$blocks) if (block$family != "ordinal")
    eta[, block$dims] <- rep(parameters[block$parameters], each = prep$n)
  eta
}

.gt_d_logdiff <- function(a, b) {
  # log(exp(a)-exp(b)), a >= b. expm1 preserves small category intervals.
  a + log(-expm1(pmin(0, b - a)))
}

.gt_d_log_interval <- function(lo, hi, link) {
  cdf <- if (link == "probit") stats::pnorm else stats::plogis
  use_tail <- lo > 0
  ans <- numeric(length(lo))
  ans[!use_tail] <- .gt_d_logdiff(cdf(hi[!use_tail], log.p = TRUE),
                                 cdf(lo[!use_tail], log.p = TRUE))
  ans[use_tail] <- .gt_d_logdiff(cdf(lo[use_tail], lower.tail = FALSE, log.p = TRUE),
                                cdf(hi[use_tail], lower.tail = FALSE, log.p = TRUE))
  ans
}

# Use the same log-interval arithmetic as the ordinal likelihood. Direct CDF
# subtraction loses representable probabilities in the upper tail. The log
# option also exposes intervals below ordinary probability underflow.
.gt_d_ordinal_probabilities <- function(eta, thresholds, link, log = FALSE) {
  if (!is.numeric(eta) || !length(eta) || any(!is.finite(eta)) ||
      !is.numeric(thresholds) || !length(thresholds) ||
      any(!is.finite(thresholds)) || any(diff(thresholds) <= 0) ||
      !is.character(link) || length(link) != 1L || is.na(link) ||
      !link %in% c("probit", "logit") ||
      !is.logical(log) || length(log) != 1L || is.na(log))
    .gt_d_stop("Invalid ordinal probability inputs.")
  cuts <- c(-Inf, thresholds, Inf)
  probabilities <- vapply(seq_len(length(cuts) - 1L), function(k)
    .gt_d_log_interval(cuts[[k]] - eta, cuts[[k + 1L]] - eta, link),
    numeric(length(eta)))
  probabilities <- matrix(probabilities, nrow = length(eta))
  if (log) probabilities else exp(probabilities)
}

.gt_d_response <- function(eta, parameters, prep, W = NULL) {
  n <- prep$n
  gradient <- matrix(0, n, prep$q)
  curvature <- vector("list", length(prep$blocks))
  nll <- 0
  for (j in seq_along(prep$blocks)) {
    b <- prep$blocks[[j]]
    e <- eta[, b$dims, drop = FALSE]
    if (b$family == "binary") {
      if (b$link == "logit") {
        x <- as.vector(e)
        nll <- nll + sum(pmax(x, 0) + log1p(exp(-abs(x))) - b$y * x)
        p <- stats::plogis(x)
        gradient[, b$dims] <- p - b$y
        curvature[[j]] <- list(dims = b$dims, diagonal = p * (1 - p))
      } else {
        signed <- (2 * b$y - 1) * as.vector(e)
        lp <- stats::pnorm(signed, log.p = TRUE)
        mills <- exp(stats::dnorm(signed, log = TRUE) - lp)
        nll <- nll - sum(lp)
        gradient[, b$dims] <- -(2 * b$y - 1) * mills
        h <- mills * (mills + signed)
        curvature[[j]] <- list(dims = b$dims, diagonal = h)
      }
    } else if (b$family == "ordinal") {
      cuts <- c(-Inf, .gt_d_thresholds(parameters[b$parameters]), Inf)
      lo <- cuts[b$y] - as.vector(e)
      hi <- cuts[b$y + 1L] - as.vector(e)
      lp <- .gt_d_log_interval(lo, hi, b$link)
      density <- if (b$link == "probit") stats::dnorm else stats::dlogis
      rlo <- exp(density(lo, log = TRUE) - lp)
      rhi <- exp(density(hi, log = TRUE) - lp)
      d <- rhi - rlo
      if (b$link == "probit") {
        slo <- ifelse(is.finite(lo), -lo, 0)
        shi <- ifelse(is.finite(hi), -hi, 0)
      } else {
        slo <- 1 - 2 * stats::plogis(lo)
        shi <- 1 - 2 * stats::plogis(hi)
      }
      h <- d^2 - (shi * rhi - slo * rlo)
      nll <- nll - sum(lp)
      gradient[, b$dims] <- d
      curvature[[j]] <- list(dims = b$dims, diagonal = h)
    } else {
      # Reference category has predictor zero; all other categories are fitted
      # together with the multinomial likelihood, never one-versus-rest fits.
      maximum <- pmax(0, apply(e, 1L, max))
      denominator <- exp(-maximum) + rowSums(exp(e - maximum))
      logden <- maximum + log(denominator)
      chosen <- numeric(n)
      nonref <- which(b$y > 1L)
      chosen[nonref] <- e[cbind(nonref, b$y[nonref] - 1L)]
      nll <- nll + sum(logden - chosen)
      p <- exp(e - logden)
      grad <- p
      grad[cbind(nonref, b$y[nonref] - 1L)] <- grad[cbind(nonref, b$y[nonref] - 1L)] - 1
      gradient[, b$dims] <- grad
      curvature[[j]] <- list(dims = b$dims, probability = p)
    }
  }
  if (!is.finite(nll) || any(!is.finite(gradient))) return(list(valid = FALSE))
  for (curv in curvature) if (!is.null(curv$diagonal)) {
    if (any(!is.finite(curv$diagonal)) || any(curv$diagonal < -1e-7))
      return(list(valid = FALSE))
  }
  ans <- list(valid = TRUE, nll = nll, gradient = as.vector(gradient), curvature = curvature)
  if (!is.null(W)) {
    H <- diag(ncol(W))
    for (curv in curvature) {
      if (!is.null(curv$diagonal)) {
        row <- (curv$dims - 1L) * n + seq_len(n)
        A <- W[row, , drop = FALSE]
        H <- H + crossprod(A, A * pmax(0, curv$diagonal))
      } else {
        p <- curv$probability
        for (a in seq_along(curv$dims)) {
          ia <- (curv$dims[[a]] - 1L) * n + seq_len(n)
          A <- W[ia, , drop = FALSE]
          for (bb in seq_along(curv$dims)) {
            ib <- (curv$dims[[bb]] - 1L) * n + seq_len(n)
            B <- W[ib, , drop = FALSE]
            weight <- (as.integer(a == bb) * p[, a]) - p[, a] * p[, bb]
            H <- H + crossprod(A, B * weight)
          }
        }
      }
    }
    ans$H <- (H + t(H)) / 2
  }
  ans
}

