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

# The fixed 16-node Gauss-Legendre rule on [0, 1] used by the narrow-interval and
# tilted-tail probit quadratures.
.gt_d_gauss_nodes <- c(
  0.0052995325041750333, 0.02771248846338371, 0.067184398806084122, 0.12229779582249849,
  0.19106187779867811, 0.27099161117138632, 0.35919822461037054, 0.45249374508118129,
  0.54750625491881877, 0.64080177538962946, 0.72900838882861374, 0.80893812220132189,
  0.87770220417750155, 0.93281560119391582, 0.9722875115366163, 0.99470046749582497
)
.gt_d_gauss_weights <- c(
  0.013576229705877048, 0.031126761969323947, 0.047579255841246393, 0.062314485627766938,
  0.074797994408288368, 0.084578259697501268, 0.091301707522461792, 0.094725305227534251,
  0.094725305227534251, 0.091301707522461792, 0.084578259697501268, 0.074797994408288368,
  0.062314485627766938, 0.047579255841246393, 0.031126761969323947, 0.013576229705877048
)

# Third derivatives and endpoint partials, when asked for, come from the same
# regime that produced the curvature, so a derivative never describes a
# different arithmetic than the Hessian it accompanies. In the engine's
# convention the endpoints are already shifted by the linear predictor
# (lo = cut - eta), so a partial in lo or hi is the partial in that cut.
# Probit same-side intervals use a tilted-exponential quadrature: the closed
# form of the third cumulant cancels three leading orders in a far tail.
# Stable ordinal log probabilities and location derivatives.
.gt_d_ordinal_interval <- function(lo, hi, link, derivatives = FALSE, third = FALSE) {
  if (third) derivatives <- TRUE
  n <- length(lo)
  lp <- g <- h <- numeric(n)
  if (third) {
    t3 <- l_lo <- l_hi <- s_lo <- s_hi <- c_lo <- c_hi <- numeric(n)
    regime <- rep("closed", n)
    dl <- dh <- var <- numeric(n)
  }
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
    if (third) {
      # Each endpoint's logistic density d = F(1 - F) and its derivative
      # -d tanh(x / 2); the third location derivative is the sum of the two
      # endpoint terms, in the paired sinh/cosh form on crossing intervals so
      # that a near-symmetric interval's small value is not a difference.
      F_L <- plogis(lo); S_L <- plogis(lo, lower.tail = FALSE)
      F_H <- plogis(hi); S_H <- plogis(hi, lower.tail = FALSE)
      d_L <- F_L * S_L; d_H <- F_H * S_H
      t3 <- d_H * tanh(hi / 2) + d_L * tanh(lo / 2)
      crossing <- paired & lo < 0 & hi > 0
      cc <- cosh(center[crossing]); ca <- cosh(half[crossing])
      # Divide by ca^3 before multiplying: finite cosh arguments do not keep
      # the unscaled cubic finite on wide, explicitly admitted intervals.
      # Crossing intervals have abs(center) < half, so both ratios are bounded.
      ratio <- cc / ca
      sinh_ratio <- sinh(center[crossing]) / ca
      t3[crossing] <- sinh_ratio * (2 / ca^2 + ratio - 1) / (1 + ratio)^3
      regime[crossing] <- "paired"
      inv <- 1 / expm1(hi - lo)
      l_lo <- F_L + inv; l_hi <- -S_H - inv
      s_lo <- -d_L; s_hi <- -d_H
      c_lo <- -d_L * tanh(lo / 2); c_hi <- -d_H * tanh(hi / 2)
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
      nodes <- .gt_d_gauss_nodes
      weights <- .gt_d_gauss_weights
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
          if (third) {
            # The third central moment from the same nodes: raw moments of the
            # offset from the centre, then the cumulant identity.
            raw2 <- variance + offset^2
            raw3 <- a^3 * as.vector(odd %*% (weights * nodes^3))/I0
            t3[positions] <- -(raw3 - 3 * offset * raw2 + 2 * offset^3)
            dl[positions] <- -a - offset
            dh[positions] <- a - offset
            var[positions] <- variance
            regime[positions] <- "narrow"
          }
        }
      }
    }
    if (third) {
      # Density ratios at the finite endpoints; an infinite endpoint has none.
      r_L <- ifelse(is.finite(lo), exp(dnorm(lo, log = TRUE) - lp), 0)
      r_H <- ifelse(is.finite(hi), exp(dnorm(hi, log = TRUE) - lp), 0)
      mu <- -g
      closed <- !narrow
      # Closed forms: T = (H^2 - 1) r_H - (L^2 - 1) r_L + 3 g D + 2 g^3 with
      # D = H r_H - L r_L; a crossing interval takes the difference of its two
      # endpoint terms through g and 4 a c r_L so that a near-symmetric
      # interval's small value is not a difference of two large ones.
      D <- ifelse(is.finite(hi), hi * r_H, 0) - ifelse(is.finite(lo), lo * r_L, 0)
      t3[closed] <- (ifelse(is.finite(hi), (hi^2 - 1) * r_H, 0) - ifelse(is.finite(lo), (lo^2 - 1) * r_L, 0) +
                       3 * g * D + 2 * g^3)[closed]
      t3[crossing] <- ((hi^2 - 1) * g + 4 * half * center * r_L + 3 * g * D + 2 * g^3)[crossing]
      regime[crossing] <- "crossing"
      dl[closed] <- (lo - mu)[closed]
      dh[closed] <- (hi - mu)[closed]
      var[closed] <- (1 - h)[closed]
      # Same-side intervals and one-sided tails: mirrored so that the near
      # endpoint L is nonnegative, the truncated density is proportional to
      # exp(-L u / s - u^2 / (2 s^2)) in u = s (z - L) >= 0 with s = max(1, L),
      # and its first three moments come from the 16-node rule on fixed panels
      # of u, which the exponential factor makes negligible beyond 64.
      same <- closed & !crossing &
        ((is.finite(lo) & lo >= 0 & (!is.finite(hi) | hi > lo)) |
         (is.finite(hi) & hi <= 0 & (!is.finite(lo) | lo < hi)))
      if (any(same)) {
        edges <- c(0, 1, 2, 4, 8, 16, 32, 64)
        for (block_start in seq.int(1L, n, by = 512L)) {
          positions <- seq.int(block_start, min(n, block_start + 511L))
          positions <- positions[same[positions]]
          if (!length(positions)) next
          mirrored <- !(is.finite(lo[positions]) & lo[positions] >= 0)
          L <- ifelse(mirrored, -hi[positions], lo[positions])
          H <- ifelse(mirrored, -lo[positions], hi[positions])
          H[!is.finite(H)] <- Inf
          s <- pmax(1, L)
          U <- (H - L) * s
          m <- matrix(0, length(positions), 4L)
          for (k in seq_len(length(edges) - 1L)) {
            a0 <- pmin(edges[k], U)
            a1 <- pmin(edges[k + 1L], U)
            width <- a1 - a0
            keep <- width > 0
            if (!any(keep)) next
            u <- a0[keep] + outer(width[keep], .gt_d_gauss_nodes)
            w <- exp(-L[keep] * u / s[keep] - (u / s[keep])^2 / 2)
            for (power in 0:3)
              m[keep, power + 1L] <- m[keep, power + 1L] +
                width[keep] * as.vector((u^power * w) %*% .gt_d_gauss_weights)
          }
          R1 <- m[, 2L] / m[, 1L]; R2 <- m[, 3L] / m[, 1L]; R3 <- m[, 4L] / m[, 1L]
          offset <- R1 / s
          k3 <- (R3 - 3 * R1 * R2 + 2 * R1^3) / s^3
          t3[positions] <- ifelse(mirrored, k3, -k3)
          dl_m <- -offset
          dh_m <- (H - L) - offset
          dl[positions] <- ifelse(mirrored, -dh_m, dl_m)
          dh[positions] <- ifelse(mirrored, -dl_m, dh_m)
          var[positions] <- (R2 - R1^2) / s^2
          regime[positions] <- "tilted"
        }
      }
      l_lo <- r_L; l_hi <- -r_H
      s_lo <- r_L * dl; s_hi <- -r_H * dh
      c_lo <- r_L * (dl^2 - var); c_hi <- -r_H * (dh^2 - var)
    }
  }
  if (third) {
    # An infinite endpoint has no partial: its ratio is zero and its offset infinite.
    s_lo[!is.finite(lo)] <- 0; c_lo[!is.finite(lo)] <- 0; l_lo[!is.finite(lo)] <- 0
    s_hi[!is.finite(hi)] <- 0; c_hi[!is.finite(hi)] <- 0; l_hi[!is.finite(hi)] <- 0
    return(list(log_probability = lp, gradient = g, curvature = h, third = t3,
                loss_lo = l_lo, loss_hi = l_hi, score_lo = s_lo, score_hi = s_hi,
                curvature_lo = c_lo, curvature_hi = c_hi, regime = regime))
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

# Third derivatives of the response loss at a kernel result, for the analytic
# gradient: per observation the third derivative of the loss in its linear
# predictor for binary and ordinal blocks, and for ordinal blocks the partials
# of loss, score and curvature in the block's stored threshold coordinates.
# Nominal blocks carry no scalar third derivative here; their contraction uses
# the probabilities the kernel already returns. Every value comes from the
# arithmetic that produced the curvature the Hessian used. A row whose
# curvature the kernel tolerated below zero, which the Hessian assembly
# replaces by zero, has no derivative of the assembled matrix, so the block is
# refused rather than differentiated as if it had not been clipped.
.gt_d_response_third <- function(eta, parameters, prep, response) {
  if (!is.list(response) || !isTRUE(response$valid))
    return(list(valid = FALSE, reason = "invalid_response"))
  blocks <- vector("list", length(prep$blocks))
  for (j in seq_along(prep$blocks)) {
    b <- prep$blocks[[j]]
    curvature <- response$curvature[[j]]
    if (!is.null(curvature$diagonal) && any(curvature$diagonal < 0))
      return(list(valid = FALSE, reason = "clipped_curvature", block = b$outcome))
    e <- as.vector(eta[, b$dims, drop = FALSE])
    if (b$family == "binary") {
      # A binary outcome is the one-cut interval at zero: (-eta, Inf) for an
      # event and (-Inf, -eta) otherwise, so its third derivative is the
      # interval kernel's in the same regimes. The closed Mills-ratio form,
      # r [1 - (r + m)(2r + m)] in the signed margin m, is exact in algebra
      # but loses the bracket in a far tail: it is of order 2 / m^4 and is
      # fed by the rounding of log Phi(m), which at m = 40 costs about 2e-4
      # of the value, where the tilted quadrature keeps twelve digits.
      event <- b$y == 1L
      interval <- .gt_d_ordinal_interval(ifelse(event, -e, -Inf), ifelse(event, Inf, -e), b$link, third = TRUE)
      blocks[[j]] <- list(dims = b$dims, family = "binary", third = interval$third, regime = interval$regime)
    } else if (b$family == "ordinal") {
      stored <- parameters[b$parameters]
      cuts <- c(-Inf, .gt_d_thresholds(stored), Inf)
      interval <- .gt_d_ordinal_interval(cuts[b$y] - e, cuts[b$y + 1L] - e, b$link, third = TRUE)
      k <- length(stored)
      loss_theta <- score_theta <- curvature_theta <- matrix(0, length(e), k)
      # The first stored cut shifts every finite cut, which is the opposite of
      # shifting eta: minus the location derivatives, never a difference of
      # two endpoint terms.
      loss_theta[, 1L] <- -interval$gradient
      score_theta[, 1L] <- -interval$curvature
      curvature_theta[, 1L] <- -interval$third
      # A log gap shifts every cut from its own onwards by exp(gap): both
      # endpoints of the categories above it, the upper endpoint of its own
      # category, nothing below.
      if (k > 1L) for (gap in 2:k) {
        scale <- exp(stored[[gap]])
        above <- b$y > gap
        own <- b$y == gap
        loss_theta[above, gap] <- -scale * interval$gradient[above]
        score_theta[above, gap] <- -scale * interval$curvature[above]
        curvature_theta[above, gap] <- -scale * interval$third[above]
        loss_theta[own, gap] <- scale * interval$loss_hi[own]
        score_theta[own, gap] <- scale * interval$score_hi[own]
        curvature_theta[own, gap] <- scale * interval$curvature_hi[own]
      }
      blocks[[j]] <- list(dims = b$dims, family = "ordinal", third = interval$third, regime = interval$regime,
                          loss_theta = loss_theta, score_theta = score_theta, curvature_theta = curvature_theta)
    } else {
      blocks[[j]] <- list(dims = b$dims, family = "categorical", third = NULL)
    }
    values <- c(blocks[[j]]$third, blocks[[j]]$loss_theta, blocks[[j]]$score_theta, blocks[[j]]$curvature_theta)
    if (length(values) && any(!is.finite(values)))
      return(list(valid = FALSE, reason = "nonfinite_third_derivative", block = b$outcome))
  }
  list(valid = TRUE, blocks = blocks)
}
