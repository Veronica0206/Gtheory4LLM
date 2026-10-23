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

# Stable ordinal log probabilities and location derivatives.
.gt_d_ordinal_interval <- function(lo, hi, link, derivatives = FALSE) {
  n <- length(lo)
  lp <- g <- h <- numeric(n)
  finite <- is.finite(lo) & is.finite(hi)
  lower_end <- !is.finite(lo) & is.finite(hi)
  upper_end <- is.finite(lo) & !is.finite(hi)
  cdf <- if (link == "probit") stats::pnorm else stats::plogis
  lp[lower_end] <- cdf(hi[lower_end], log.p = TRUE)
  lp[upper_end] <- cdf(lo[upper_end], lower.tail = FALSE, log.p = TRUE)
  if (link == "logit") {
    lp[finite] <- plogis(hi[finite], log.p = TRUE) + plogis(lo[finite], lower.tail = FALSE, log.p = TRUE) +
      log(-expm1(lo[finite] - hi[finite]))
    if (derivatives) {
      la <- plogis(hi, lower.tail = FALSE, log.p = TRUE)
      lb <- plogis(lo, log.p = TRUE)
      above <- la > lb
      below <- la < lb
      g[above] <- exp(la[above]) * (-expm1(lb[above] - la[above]))
      g[below] <- -exp(lb[below]) * (-expm1(la[below] - lb[below]))
      center <- (lo + hi)/2
      half <- (hi - lo)/2
      paired <- finite & is.finite(center) & is.finite(half) & abs(center) < 300 & half < 300
      g[paired] <- -sinh(center[paired])/(cosh(center[paired]) + cosh(half[paired]))
      h <- plogis(lo) * plogis(lo, lower.tail = FALSE) + plogis(hi) * plogis(hi, lower.tail = FALSE)
    }
  } else {
    half <- (hi - lo)/2
    center <- (hi + lo)/2
    narrow <- finite & is.finite(center) & half > 0 & half <= 0.5 & abs(center) * half <= 1
    other <- finite & !narrow
    crossing <- other & lo <= 0 & hi >= 0
    lp[crossing] <- log1p(-(pnorm(lo[crossing]) + pnorm(hi[crossing], lower.tail = FALSE)))
    left <- other & hi < 0
    right <- other & lo > 0
    lp[left] <- .gt_d_logdiff(pnorm(hi[left], log.p = TRUE), pnorm(lo[left], log.p = TRUE))
    lp[right] <- .gt_d_logdiff(pnorm(lo[right], lower.tail = FALSE, log.p = TRUE), pnorm(hi[right],
      lower.tail = FALSE, log.p = TRUE))
    if (derivatives) {
      ordinary <- !narrow
      rl <- exp(dnorm(lo[ordinary], log = TRUE) - lp[ordinary])
      rh <- exp(dnorm(hi[ordinary], log = TRUE) - lp[ordinary])
      sl <- ifelse(is.finite(lo[ordinary]), -lo[ordinary], 0)
      sh <- ifelse(is.finite(hi[ordinary]), -hi[ordinary], 0)
      g[ordinary] <- rh - rl
      h[ordinary] <- g[ordinary]^2 - (sh * rh - sl * rl)
      # A factored density difference retains nearly symmetric crossing scores.
      if (any(crossing)) {
        delta <- (lo[crossing] - hi[crossing]) * ((lo[crossing] + hi[crossing])/2)
        rl_cross <- exp(dnorm(lo[crossing], log = TRUE) - lp[crossing])
        rh_cross <- exp(dnorm(hi[crossing], log = TRUE) - lp[crossing])
        gc <- numeric(length(delta))
        above <- delta >= 0
        gc[above] <- rh_cross[above] * (-expm1(-delta[above]))
        gc[!above] <- -rl_cross[!above] * (-expm1(delta[!above]))
        g[crossing] <- gc
        h[crossing] <- gc^2 + hi[crossing] * rh_cross - lo[crossing] * rl_cross
      }
    }
    # The fixed16-node rule is used only on the qualified bounded exponent region.
    if (any(narrow)) {
      nodes <- c(
        0.0052995325041750333, 0.02771248846338371, 0.067184398806084122, 0.12229779582249849,
        0.19106187779867811, 0.27099161117138632, 0.35919822461037054, 0.45249374508118129,
        0.54750625491881877, 0.64080177538962946, 0.72900838882861374, 0.80893812220132189,
        0.87770220417750155, 0.93281560119391582, 0.9722875115366163, 0.99470046749582497
      )
      weights <- c(
        0.013576229705877048, 0.031126761969323947, 0.047579255841246393, 0.062314485627766938,
        0.074797994408288368, 0.084578259697501268, 0.091301707522461792, 0.094725305227534251,
        0.094725305227534251, 0.091301707522461792, 0.084578259697501268, 0.074797994408288368,
        0.062314485627766938, 0.047579255841246393, 0.031126761969323947, 0.013576229705877048
      )
      # Quadrature scratch stays bounded under arbitrary user row overrides.
      for (block_start in seq.int(1L, n, by = 512L)) {
        positions <- seq.int(block_start, min(n, block_start + 511L))
        positions <- positions[narrow[positions]]
        if (!length(positions)) next
        a <- half[positions]
        c <- center[positions]
        z <- outer(a, nodes)
        u <- outer(abs(c) * a, nodes)
        zs <- pmin(abs(c), a)
        M <- abs(c) * zs - zs^2/2
        common <- exp(-z^2/2 + u - M)
        even <- common * (1 + exp(-2 * u))
        I0 <- as.vector(even %*% weights)
        lp[positions] <- dnorm(c, log = TRUE) + log(a) + M + log(I0)
        if (derivatives) {
          odd <- -sign(c) * common * (-expm1(-2 * u))
          offset <- a * as.vector(odd %*% (weights * nodes))/I0
          variance <- a^2 * as.vector(even %*% (weights * nodes^2))/I0 - offset^2
          g[positions] <- -(c + offset)
          h[positions] <- 1 - variance
        }
      }
    }
  }
  if (derivatives) list(log_probability = lp, gradient = g, curvature = h) else lp
}

.gt_d_log_interval <- function(lo, hi, link) {
  .gt_d_ordinal_interval(lo, hi, link, derivatives = FALSE)
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

# Preserve the variance of an almost-certain nominal category. Subtracting p^2
# from p loses its representable complement when p rounds to one. Legacy
# private curvature fixtures without maximum-category metadata retain their
# original arithmetic; response-kernel records supply the stable complement.
.gt_d_nominal_diagonal <- function(curvature, a) {
  probability <- curvature$probability
  p <- probability[, a]
  result <- p - p^2
  category <- curvature$maximum_category
  complement <- curvature$maximum_complement
  if (is.null(category) && is.null(complement)) return(result)
  n <- nrow(probability)
  if (!is.numeric(category) || length(category) != n || any(!is.finite(category)) ||
      any(category < 0 | category > ncol(probability) | category != floor(category)) ||
      !is.numeric(complement) || length(complement) != n || any(!is.finite(complement)) ||
      any(complement < 0 | complement > 1))
    .gt_d_stop("Invalid nominal maximum-category complement metadata.")
  nonreference <- which(category > 0)
  if (length(nonreference) && any(abs(probability[cbind(nonreference, category[nonreference])] +
      complement[nonreference] - 1) > sqrt(.Machine$double.eps)))
    .gt_d_stop("Nominal maximum-category complements do not match probabilities.")
  selected <- category == a
  result[selected] <- p[selected] * complement[selected]
  result
}

.gt_d_response_kernel <- function(eta, parameters, prep) {
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
        # Work with the observed category's signed margin. Subtracting y*x
        # from softplus(x) cancels a representable positive log loss when a
        # positive event has a large positive predictor. Direct complementary
        # logistic tails likewise retain its score and curvature when the
        # fitted event probability rounds to one.
        sign <- 2 * b$y - 1
        margin <- sign * x
        nll <- nll + sum(pmax(-margin, 0) + log1p(exp(-abs(margin))))
        gradient[, b$dims] <- -sign * stats::plogis(margin, lower.tail = FALSE)
        curvature[[j]] <- list(dims = b$dims,
          diagonal = stats::plogis(x) * stats::plogis(x, lower.tail = FALSE))
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
      response <- .gt_d_ordinal_interval(lo, hi, b$link, derivatives = TRUE)
      nll <- nll - sum(response$log_probability)
      gradient[, b$dims] <- response$gradient
      curvature[[j]] <- list(dims = b$dims, diagonal = response$curvature)
    } else {
      # Reference category has predictor zero; all other categories are fitted
      # together with the multinomial likelihood, never one-versus-rest fits.
      maximum <- pmax(0, apply(e, 1L, max))
      weights <- exp(e - maximum)
      maximum_category <- max.col(e, ties.method = "first")
      maximum_category[maximum == 0] <- 0L
      dominant <- which(maximum_category > 0)
      others <- weights
      if (length(dominant)) others[cbind(dominant, maximum_category[dominant])] <- 0
      remainder <- rowSums(others) + ifelse(maximum_category > 0, exp(-maximum), 0)
      denominator <- 1 + remainder
      complement <- remainder / denominator
      chosen <- numeric(n)
      nonref <- which(b$y > 1L)
      chosen[nonref] <- e[cbind(nonref, b$y[nonref] - 1L)]
      # Keep the small log1p remainder separate from the large common shift.
      nll <- nll + sum((maximum - chosen) + log1p(remainder))
      p <- weights / denominator
      grad <- p
      grad[cbind(nonref, b$y[nonref] - 1L)] <- grad[cbind(nonref, b$y[nonref] - 1L)] - 1
      observed_maximum <- which(b$y > 1L & b$y - 1L == maximum_category)
      if (length(observed_maximum))
        grad[cbind(observed_maximum, maximum_category[observed_maximum])] <- -complement[observed_maximum]
      gradient[, b$dims] <- grad
      curvature[[j]] <- list(dims = b$dims, probability = p,
        maximum_category = maximum_category, maximum_complement = complement)
    }
  }
  if (!is.finite(nll) || any(!is.finite(gradient))) return(list(valid = FALSE))
  for (curv in curvature) if (!is.null(curv$diagonal)) {
    if (any(!is.finite(curv$diagonal)) || any(curv$diagonal < -1e-7))
      return(list(valid = FALSE))
  }
  ans <- list(valid = TRUE, nll = nll, gradient = as.vector(gradient), curvature = curvature)
  ans
}
