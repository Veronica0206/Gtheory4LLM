# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Discrete G-theory likelihoods shared by package and source-based use.
#
# This is a deliberately bounded dense Laplace implementation. Random sources
# are mutually independent, multivariate Gaussian random intercepts. Outcomes
# are conditionally independent given those sources. Within a multinomial
# outcome, its category indicators instead have the joint softmax likelihood.
# Binary/ordinal probit models fix latent residual variance to 1; logit models
# fix it to pi^2/3. No additional free observation-level Gaussian residual is
# estimated. The likelihood is approximate whenever random effects are present.

.gt_d_stop <- function(...) stop(..., call. = FALSE)

.gt_d_control <- function(control) {
  defaults <- list(max_random_dimension = 200L, max_observations = 1200L,
                   max_parameters = 80L, maxit = 150L, inner_maxit = 60L,
                   inner_tol = 1e-7, reltol = 1e-7, start_sd = 0.4,
                   trace = 0L, fixed_covariance = NULL,
                   stationarity_tol = 1e-3, validation_reltol = 1e-10,
                   validation_inner_tol = 1e-9, alternative_starts = 1L,
                   stability_objective_tol = 1e-6,
                   stability_parameter_tol = 0.02, bound_tol = 1e-4,
                   covariance_parameterization = "auto",
                   start = NULL, optimizer = "L-BFGS-B")
  if (!is.list(control) || (length(control) &&
      (is.null(names(control)) || anyNA(names(control)) ||
       any(!nzchar(names(control))) || anyDuplicated(names(control)))))
    .gt_d_stop("discrete control must be a named list.")
  unknown <- setdiff(names(control), names(defaults))
  if (length(unknown)) .gt_d_stop("Unknown discrete control: ", paste(unknown, collapse = ", "), ".")
  for (nm in names(control)) defaults[nm] <- control[nm]
  for (nm in c("max_random_dimension", "max_observations", "max_parameters", "maxit", "inner_maxit")) {
    z <- defaults[[nm]]
    if (!is.numeric(z) || length(z) != 1L || !is.finite(z) || z < 1 || z != floor(z))
      .gt_d_stop(nm, " must be a positive integer.")
  }
  for (nm in c("inner_tol", "reltol", "start_sd", "stationarity_tol",
               "validation_reltol", "validation_inner_tol",
               "stability_objective_tol", "stability_parameter_tol", "bound_tol")) {
    z <- defaults[[nm]]
    if (!is.numeric(z) || length(z) != 1L || !is.finite(z) || z <= 0)
      .gt_d_stop(nm, " must be a positive finite number.")
  }
  if (!is.numeric(defaults$alternative_starts) || length(defaults$alternative_starts) != 1L ||
      !is.finite(defaults$alternative_starts) || defaults$alternative_starts < 0 ||
      defaults$alternative_starts != floor(defaults$alternative_starts) || defaults$alternative_starts > 5)
    .gt_d_stop("alternative_starts must be an integer from 0 to 5; zero disables numerical acceptance.")
  if (!is.numeric(defaults$trace) || length(defaults$trace) != 1L ||
      !is.finite(defaults$trace) || !defaults$trace %in% c(0, 1))
    .gt_d_stop("trace must be 0 or 1.")
  if (!is.character(defaults$covariance_parameterization) ||
      length(defaults$covariance_parameterization) != 1L ||
      is.na(defaults$covariance_parameterization) ||
      !defaults$covariance_parameterization %in% c("auto", "log_cholesky", "variance"))
    .gt_d_stop("covariance_parameterization must be 'auto', 'log_cholesky', or 'variance'.")
  if (!is.character(defaults$optimizer) || length(defaults$optimizer) != 1L ||
      is.na(defaults$optimizer) || !defaults$optimizer %in% c("L-BFGS-B", "nlminb"))
    .gt_d_stop("discrete optimizer must be 'L-BFGS-B' or 'nlminb'.")
  z <- defaults$start
  if (!is.null(z) && (!is.numeric(z) || !is.null(dim(z)) || !length(z) ||
      any(!is.finite(z)) || is.null(names(z)) || anyNA(names(z)) ||
      any(!nzchar(names(z))) || anyDuplicated(names(z))))
    .gt_d_stop("discrete start must be a finite, uniquely named numeric parameter vector.")
  defaults
}

# Keep errors and warnings from numerical attempts without changing the global
# warning option or RNG state. User interrupts are deliberately not caught.
.gt_d_capture <- function(expr) {
  started <- proc.time()[["elapsed"]]
  warnings <- character()
  error <- NULL
  value <- tryCatch(withCallingHandlers(force(expr), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }), error = function(e) {
    error <<- conditionMessage(e)
    NULL
  })
  list(value = value, error = error, warnings = warnings,
       elapsed_seconds = unname(proc.time()[["elapsed"]] - started))
}

.gt_d_optimize <- function(at, objective, lower, upper, optimizer_control,
                            label, optimizer = "L-BFGS-B") {
  # A function is allowed internally for failure-injection tests only. Public
  # controls select a supported engine, which remains fixed across all trials.
  optimizer_name <- if (is.function(optimizer)) "injected_function" else optimizer
  native_control <- optimizer_control
  if (identical(optimizer_name, "nlminb")) {
    native_control <- list(iter.max = optimizer_control$maxit,
      eval.max = max(200, 10 * optimizer_control$maxit),
      rel.tol = optimizer_control$factr * .Machine$double.eps,
      trace = optimizer_control$trace)
    captured <- .gt_d_capture(stats::nlminb(at, objective, lower = lower,
      upper = upper, control = native_control))
  } else {
    if (!is.function(optimizer)) {
      if (!identical(optimizer_name, "L-BFGS-B")) .gt_d_stop("Unsupported discrete optimizer.")
      optimizer <- stats::optim
    }
    captured <- .gt_d_capture(optimizer(at, objective, method = "L-BFGS-B",
      lower = lower, upper = upper, control = native_control))
  }
  raw_result <- captured$value
  fit <- raw_result
  if (identical(optimizer_name, "nlminb") && is.list(fit)) fit$value <- fit$objective
  available <- is.list(fit) && is.numeric(fit$par) &&
    length(fit$par) == length(at) && all(is.finite(fit$par)) &&
    all(fit$par >= lower & fit$par <= upper) &&
    is.numeric(fit$value) && length(fit$value) == 1L &&
    is.finite(fit$value) && fit$value < 1e99 &&
    is.numeric(fit$convergence) && length(fit$convergence) == 1L &&
    is.finite(fit$convergence)
  if (!available) {
    if (is.null(captured$error))
      captured$error <- "Optimizer returned no usable finite result."
    fit <- list(par = at, value = Inf, convergence = 100L,
                message = captured$error)
  } else {
    fit$convergence <- as.integer(fit$convergence)
  }
  fit$result_available <- available
  fit$attempt <- list(label = label, start = at, error = captured$error,
    warnings = captured$warnings, elapsed_seconds = captured$elapsed_seconds,
    optimizer_code = fit$convergence, optimizer_message = fit$message,
    result_available = available, parameters = fit$par,
    objective = fit$value, optimizer = optimizer_name,
    optimizer_control = native_control,
    raw_result = raw_result)
  fit
}

.gt_d_group <- function(data, members) {
  # Interaction labels contain integer codes only, not potentially colliding
  # user labels. Observed tuples are matched directly without Cartesian grids.
  if (anyNA(data[members])) .gt_d_stop("Missing grouping values are not supported.")
  key <- .gt_tuple_key(data, members)
  group <- match(key, unique(key))
  list(index = group, nlevels = max(group))
}

.gt_d_prepare <- function(data, outcomes, families) {
  if (!is.data.frame(data) || !nrow(data)) .gt_d_stop("data must be a nonempty data.frame.")
  if (!is.character(outcomes) || !length(outcomes) || anyNA(outcomes) ||
      anyDuplicated(outcomes) || any(!outcomes %in% names(data)))
    .gt_d_stop("outcomes must name distinct existing columns.")
  if (inherits(families, "gt_family") || is.character(families$family)) families <- list(families)
  if (!is.list(families) || length(families) != length(outcomes))
    .gt_d_stop("Provide one resolved family specification per outcome.")
  blocks <- vector("list", length(outcomes))
  dimensions <- character()
  parameter_start <- lower <- upper <- numeric()
  parameter_names <- character()
  for (j in seq_along(outcomes)) {
    name <- outcomes[[j]]
    spec <- families[[j]]
    fam <- spec$family
    if (length(fam) != 1L || !fam %in% c("binary", "ordinal", "categorical"))
      .gt_d_stop("The discrete engine accepts binary, ordinal, or categorical families only.")
    link <- spec$link
    if (is.null(link)) link <- if (fam == "categorical") "softmax" else "probit"
    if (!link %in% if (fam == "categorical") "softmax" else c("probit", "logit"))
      .gt_d_stop("Unsupported link for ", fam, ".")
    raw <- data[[name]]
    if (anyNA(raw)) .gt_d_stop("Missing outcomes are not supported by the prototype discrete engine.")
    lev <- spec$levels
    if (fam == "binary") {
      if (is.logical(raw) || (is.numeric(raw) && all(raw %in% c(0, 1)))) {
        y <- as.integer(raw)
        if (is.null(lev)) lev <- c("0", "1")
      } else {
        if (is.null(lev)) lev <- if (is.factor(raw)) levels(raw) else NULL
        if (is.null(lev) || length(lev) != 2L) .gt_d_stop("Binary labels require two declared levels.")
        y <- match(as.character(raw), as.character(lev)) - 1L
      }
      if (length(lev) != 2L || anyNA(y) || length(unique(y)) != 2L)
        .gt_d_stop("Both binary categories must be observed and match declared levels.")
      p <- (sum(y) + 0.5) / (length(y) + 1)
      start <- if (link == "probit") stats::qnorm(p) else stats::qlogis(p)
      indices <- length(parameter_start) + 1L
      parameter_start <- c(parameter_start, start)
      lower <- c(lower, -15); upper <- c(upper, 15)
      parameter_names <- c(parameter_names, paste0(name, "::intercept"))
      dnames <- name
    } else {
      if (is.null(lev)) {
        if (fam == "ordinal" && !is.ordered(raw))
          .gt_d_stop("Ordinal outcomes require an ordered factor or declared levels.")
        lev <- if (is.factor(raw)) levels(raw) else NULL
      }
      if (is.null(lev) || length(lev) < 2L || anyNA(lev) || anyDuplicated(as.character(lev)))
        .gt_d_stop("Declare at least two distinct outcome levels.")
      lev <- as.character(lev)
      if (fam == "categorical") {
        ref <- spec$reference
        if (is.null(ref)) ref <- lev[[1L]]
        if (length(ref) != 1L || !ref %in% lev) .gt_d_stop("Categorical reference must be a declared level.")
        lev <- c(ref, setdiff(lev, ref))
      }
      y <- match(as.character(raw), lev)
      if (anyNA(y)) .gt_d_stop("Outcome values do not match declared levels for ", name, ".")
      freq <- tabulate(y, nbins = length(lev))
      if (any(freq == 0L)) .gt_d_stop("Every declared category must be observed for ", name,
                                    "; empty categories do not identify the current model.")
      if (fam == "ordinal") {
        cp <- cumsum(freq)[-length(freq)] / sum(freq)
        threshold <- if (link == "probit") stats::qnorm(cp) else stats::qlogis(cp)
        start <- c(threshold[[1L]], log(diff(threshold)))
        indices <- length(parameter_start) + seq_along(start)
        parameter_start <- c(parameter_start, start)
        lower <- c(lower, -15, rep(log(1e-4), length(start) - 1L))
        upper <- c(upper, 15, rep(log(100), length(start) - 1L))
        parameter_names <- c(parameter_names, paste0(name, "::threshold_parameter", seq_along(start)))
        dnames <- name
      } else {
        start <- log(freq[-1L] / freq[[1L]])
        indices <- length(parameter_start) + seq_along(start)
        parameter_start <- c(parameter_start, start)
        lower <- c(lower, rep(-15, length(start))); upper <- c(upper, rep(15, length(start)))
        parameter_names <- c(parameter_names, paste0(name, "::", lev[-1L], "_vs_", lev[[1L]], "::intercept"))
        dnames <- paste0(name, "::", lev[-1L], "_vs_", lev[[1L]])
      }
    }
    dims <- length(dimensions) + seq_along(dnames)
    dimensions <- c(dimensions, dnames)
    blocks[[j]] <- list(outcome = name, family = fam, link = link, levels = lev,
                        y = y, dims = dims, parameters = indices,
                        reference = if (fam == "categorical") lev[[1L]] else NULL)
  }
  if (anyDuplicated(dimensions))
    .gt_d_stop("Outcome/category labels produce duplicate latent-dimension names; use unambiguous labels.")
  names(parameter_start) <- parameter_names
  list(blocks = blocks, dimensions = dimensions, start = parameter_start,
       lower = lower, upper = upper, n = nrow(data), q = length(dimensions))
}

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

.gt_d_covariance_setup <- function(groups, q, covariance, control, dimensions) {
  if (!is.character(covariance) || length(covariance) != 1L ||
      !covariance %in% c("diagonal", "unstructured"))
    .gt_d_stop("covariance must be 'diagonal' or 'unstructured'.")
  fixed <- control$fixed_covariance
  if (!is.null(fixed)) {
    if (!is.list(fixed) || is.null(names(fixed)) || anyDuplicated(names(fixed)) ||
        !setequal(names(fixed), names(groups)))
      .gt_d_stop("fixed_covariance must give one named matrix for every random source.")
    factors <- lapply(fixed[names(groups)], function(x) {
      if (!is.matrix(x) || !is.numeric(x) || !identical(dim(x), c(q, q)) ||
          any(!is.finite(x)))
        .gt_d_stop("Fixed source covariance matrices must be finite symmetric q by q matrices.")
      # Unnamed matrices are positional. Once either axis is named, both axes
      # must identify every latent dimension and are aligned independently.
      if (!is.null(rownames(x)) || !is.null(colnames(x))) {
        labels <- dimnames(x)
        if (any(vapply(labels, function(z) is.null(z) || anyNA(z) ||
                       any(!nzchar(z)) || anyDuplicated(z) ||
                       !setequal(z, dimensions), logical(1))))
          .gt_d_stop("Named fixed covariance matrices require unique row and column names matching all latent dimensions.")
        x <- x[dimensions, dimensions, drop = FALSE]
      }
      if (max(abs(x - t(x))) > 1e-9)
        .gt_d_stop("Fixed source covariance matrices must be finite symmetric q by q matrices after label alignment.")
      eig <- eigen(x, symmetric = TRUE)
      if (min(eig$values) < -1e-9) .gt_d_stop("Fixed source covariance matrices must be positive semidefinite.")
      if (covariance == "diagonal" && any(abs(x[row(x) != col(x)]) > 1e-9))
        .gt_d_stop("Off-diagonal fixed covariance supplied with covariance='diagonal'.")
      sweep(eig$vectors, 2L, sqrt(pmax(0, eig$values)), "*")
    })
    return(list(fixed = factors, start = numeric(), lower = numeric(), upper = numeric(), q = q,
                parameterization = "fixed"))
  }
  # Resolve coordinates without changing the requested covariance model.
  # Joint unstructured models retain all cross-outcome covariance parameters.
  parameterization <- control$covariance_parameterization
  if (identical(parameterization, "auto"))
    parameterization <- if (q == 1L || covariance == "diagonal") "variance" else "log_cholesky"
  if (identical(parameterization, "variance")) {
    if (q > 1L && covariance != "diagonal")
      .gt_d_stop("The variance parameterization requires a univariate or diagonal covariance model; unstructured joint covariance still uses log_cholesky.")
    start <- rep(control$start_sd^2, length(groups) * q)
    if (any(!is.finite(start)) || any(start > exp(10)))
      .gt_d_stop("start_sd exceeds the variance parameterization's upper bound.")
    names(start) <- unlist(lapply(names(groups), function(s)
      paste0(s, "::variance[", dimensions, "]")), use.names = FALSE)
    return(list(fixed = NULL, start = start, lower = rep(0, length(start)),
      upper = rep(exp(10), length(start)),
      positions = which(diag(q) == 1, arr.ind = TRUE), diagpos = rep(TRUE, q),
      per = as.integer(q), q = q, sources = names(groups),
      parameterization = "variance"))
  }
  positions <- if (covariance == "diagonal") which(diag(q) == 1, arr.ind = TRUE) else
    which(lower.tri(matrix(0, q, q), diag = TRUE), arr.ind = TRUE)
  diagpos <- positions[, 1L] == positions[, 2L]
  per <- nrow(positions)
  start <- rep(ifelse(diagpos, log(control$start_sd), 0), length(groups))
  lower <- rep(ifelse(diagpos, -10, -10), length(groups))
  upper <- rep(ifelse(diagpos, 5, 10), length(groups))
  names(start) <- unlist(lapply(names(groups), function(s)
    paste0(s, "::chol[", dimensions[positions[, 1L]], ",", dimensions[positions[, 2L]], "]")), use.names = FALSE)
  list(fixed = NULL, start = start, lower = lower, upper = upper,
       positions = positions, diagpos = diagpos, per = per, q = q, sources = names(groups),
       parameterization = "log_cholesky")
}

.gt_d_covariance_factors <- function(parameters, setup) {
  if (!is.null(setup$fixed)) return(setup$fixed)
  setNames(lapply(seq_along(setup$sources), function(s) {
    x <- parameters[(s - 1L) * setup$per + seq_len(setup$per)]
    if (identical(setup$parameterization, "variance")) {
      if (any(!is.finite(x)) || any(x < 0))
        .gt_d_stop("Direct variance parameters must be finite and nonnegative.")
      x <- sqrt(x)
    } else {
      x[setup$diagpos] <- exp(x[setup$diagpos])
    }
    L <- matrix(0, setup$q, setup$q)
    L[setup$positions] <- x
    L
  }), setup$sources)
}

.gt_d_W <- function(groups, factors, n, q) {
  dimension <- sum(vapply(groups, `[[`, integer(1), "nlevels")) * q
  W <- matrix(0, n * q, dimension)
  offset <- 0L
  for (s in seq_along(groups)) {
    group <- groups[[s]]
    L <- factors[[s]]
    for (a in seq_len(q)) for (b in seq_len(q)) if (L[a, b] != 0)
      W[cbind((a - 1L) * n + seq_len(n), offset + (b - 1L) * group$nlevels + group$index)] <- L[a, b]
    offset <- offset + q * group$nlevels
  }
  W
}

.gt_d_kernel_rank <- function(groups) {
  # <Z_s Z_s', Z_t Z_t'> is the sum of squared joint group counts.
  # This checks source-kernel linear dependence without allocating n by n K's.
  k <- length(groups)
  gram <- matrix(0, k, k)
  for (s in seq_len(k)) for (t in seq_len(s)) {
    key <- paste(groups[[s]]$index, groups[[t]]$index, sep = ":")
    counts <- tabulate(match(key, unique(key)))
    gram[s, t] <- gram[t, s] <- sum(counts^2)
  }
  normalized <- gram / sqrt(outer(diag(gram), diag(gram)))
  values <- eigen(normalized, symmetric = TRUE, only.values = TRUE)$values
  list(rank = sum(values > max(values) * 1e-10), n_sources = k,
       smallest_normalized_eigenvalue = min(values))
}

.gt_d_laplace <- function(parameters, prep, groups, setup, control, details = FALSE,
                          factors_override = NULL) {
  fixed_length <- length(prep$start)
  factors <- if (is.null(factors_override))
    .gt_d_covariance_factors(parameters[-seq_len(fixed_length)], setup) else factors_override
  W <- .gt_d_W(groups, factors, prep$n, prep$q)
  baseline <- .gt_d_baseline(parameters, prep)
  u <- numeric(ncol(W))
  converged <- FALSE
  last_gradient <- Inf
  for (iter in seq_len(control$inner_maxit)) {
    eta <- baseline + matrix(W %*% u, prep$n, prep$q)
    response <- .gt_d_response(eta, parameters, prep, W)
    if (!response$valid) return(if (details) list(valid = FALSE) else 1e100)
    gradient <- as.vector(crossprod(W, response$gradient)) + u
    last_gradient <- max(abs(gradient))
    if (last_gradient <= control$inner_tol) { converged <- TRUE; break }
    R <- tryCatch(chol(response$H), error = function(e) NULL)
    if (is.null(R)) return(if (details) list(valid = FALSE) else 1e100)
    step <- backsolve(R, forwardsolve(t(R), gradient))
    objective <- response$nll + sum(u^2) / 2
    descent <- sum(gradient * step)
    multiplier <- 1
    accepted <- FALSE
    for (line in seq_len(30L)) {
      candidate <- u - multiplier * step
      next_eta <- baseline + matrix(W %*% candidate, prep$n, prep$q)
      next_response <- .gt_d_response(next_eta, parameters, prep)
      if (next_response$valid && next_response$nll + sum(candidate^2) / 2 <=
          objective - 1e-4 * multiplier * descent + 1e-12) {
        u <- as.vector(candidate)
        accepted <- TRUE
        break
      }
      multiplier <- multiplier / 2
    }
    if (!accepted) break
  }
  # Always recompute at the final mode, including when max iterations was hit.
  eta <- baseline + matrix(W %*% u, prep$n, prep$q)
  response <- .gt_d_response(eta, parameters, prep, W)
  if (!response$valid) return(if (details) list(valid = FALSE) else 1e100)
  last_gradient <- max(abs(as.vector(crossprod(W, response$gradient)) + u))
  converged <- is.finite(last_gradient) && last_gradient <= control$inner_tol * 10
  R <- tryCatch(chol(response$H), error = function(e) NULL)
  if (is.null(R) || !converged) return(if (details)
    list(valid = FALSE, inner_converged = converged, inner_gradient = last_gradient) else 1e100)
  value <- response$nll + sum(u^2) / 2 + sum(log(diag(R)))
  if (!details) return(value)
  list(valid = TRUE, nll = value, factors = factors, mode = u, eta = eta,
       conditional_nll = response$nll, inner_iterations = iter,
       inner_converged = converged, inner_gradient = last_gradient,
       random_dimension = length(u))
}

.gt_d_psd <- function(S) {
  eig <- eigen((S + t(S)) / 2, symmetric = TRUE)
  tcrossprod(sweep(eig$vectors, 2L, sqrt(pmax(0, eig$values)), "*"))
}

.gt_d_covariance_factor <- function(S) {
  eig <- eigen((S + t(S)) / 2, symmetric = TRUE)
  sweep(eig$vectors, 2L, sqrt(pmax(0, eig$values)), "*")
}

# Independent finite differences of the final marginal objective. Covariance
# derivatives use PSD rank-one increments, so they remain defined at zero and
# singular covariance matrices and do not vanish merely because log-SD does.
# Richardson extrapolation and bounded step halving check truncation stability.
# Refinement changes the numerical resolution, never the acceptance tolerance.
.gt_d_stationarity <- function(parameters, prep, groups, setup, control, final) {
  # Optimizers may use a finite penalty for a failed conditional mode, but
  # finite differences must never subtract those penalties. Require the
  # detailed validity record at every center and perturbation, stopping at
  # the first failure so later step refinement cannot erase it. The caller
  # preserves this error in the fit and blocks numerical acceptance.
  objective <- function(par, factors = final$factors, location) {
    value <- .gt_d_laplace(par, prep, groups, setup, control,
                          details = TRUE, factors_override = factors)
    reason <- if (!is.list(value) || !isTRUE(value$valid))
      "invalid conditional mode" else if (!isTRUE(value$inner_converged))
      "conditional mode did not converge" else if (
        !is.numeric(value$nll) || length(value$nll) != 1L ||
        !is.finite(value$nll) || value$nll >= 1e99)
      "unusable marginal objective" else NULL
    if (!is.null(reason))
      .gt_d_stop("Stationarity validation failed at ", location, ": ", reason, ".")
    value$nll
  }
  base <- objective(parameters, location = "center")
  normalization <- sqrt(prep$n)
  # At a natural zero-variance boundary the valid derivative is one-sided.
  # Its raw O(h) truncation error can exceed the accuracy gate even when the
  # extrapolated score is accurate. Halve the step at most six times and keep
  # the original, conservative coarse/fine disagreement criterion.
  max_refinements <- 6L
  refine <- function(derivative, h, scaling, order) {
    coarse <- derivative(h)
    fine <- derivative(h / 2)
    refinements <- 0L
    disagreement <- max(abs(fine - coarse)) * scaling
    while (is.finite(disagreement) &&
           disagreement > control$stationarity_tol / 2 &&
           refinements < max_refinements) {
      h <- h / 2
      coarse <- fine
      fine <- derivative(h / 2)
      refinements <- refinements + 1L
      disagreement <- max(abs(fine - coarse)) * scaling
    }
    multiplier <- 2^order
    list(score = (multiplier * fine - coarse) / (multiplier - 1),
         disagreement = disagreement, step = h, refinements = refinements)
  }
  fixed_score <- fixed_disagreement <- fixed_steps <- numeric(length(prep$start))
  fixed_refinements <- integer(length(prep$start))
  for (j in seq_along(prep$start)) {
    h <- 1e-4 * max(1, abs(parameters[[j]]))
    derivative <- function(step) {
      plus <- minus <- parameters
      plus[[j]] <- plus[[j]] + step; minus[[j]] <- minus[[j]] - step
      label <- paste0("fixed parameter ", names(prep$start)[[j]],
                      " (step ", format(step, scientific = TRUE), ")")
      (objective(plus, location = paste(label, "positive probe")) -
       objective(minus, location = paste(label, "negative probe"))) / (2 * step)
    }
    difference <- refine(derivative, h, 1 / normalization, order = 2L)
    fixed_score[[j]] <- difference$score
    fixed_disagreement[[j]] <- difference$disagreement
    fixed_steps[[j]] <- difference$step
    fixed_refinements[[j]] <- difference$refinements
  }
  names(fixed_score) <- names(fixed_steps) <- names(fixed_refinements) <- names(prep$start)
  cov_gradients <- projected <- list()
  cov_disagreement <- cov_steps <- numeric()
  cov_refinements <- integer()
  if (is.null(setup$fixed)) for (s in seq_along(final$factors)) {
    S <- tcrossprod(final$factors[[s]])
    scale <- max(1, max(diag(S)))
    h <- 1e-4 * scale
    evaluate <- function(increment, direction, step) {
      factors <- final$factors
      factors[[s]] <- .gt_d_covariance_factor(S + increment)
      objective(parameters, factors, location = paste0("covariance source ",
        names(final$factors)[[s]], " ", direction,
        " (step ", format(step, scientific = TRUE), ")"))
    }
    derivative <- function(step) {
      G <- matrix(0, prep$q, prep$q)
      for (a in seq_len(prep$q)) {
        direction <- matrix(0, prep$q, prep$q); direction[a, a] <- step
        G[a, a] <- (evaluate(direction, paste("diagonal", a), step) - base) / step
      }
      if (!identical(setup$per, prep$q)) for (a in seq_len(prep$q)) {
        if (a == prep$q) next
        for (b in seq.int(a + 1L, prep$q)) {
          plus <- minus <- numeric(prep$q)
          plus[c(a, b)] <- 1; minus[c(a, b)] <- c(1, -1)
          G[a, b] <- G[b, a] <-
            (evaluate(step * tcrossprod(plus), paste("positive contrast", a, b), step) -
             evaluate(step * tcrossprod(minus), paste("negative contrast", a, b), step)) / (4 * step)
        }
      }
      G
    }
    difference <- refine(derivative, h, scale / normalization, order = 1L)
    G <- difference$score
    normalized_S <- S / scale
    normalized_G <- G * scale / normalization
    projected[[names(final$factors)[[s]]]] <- if (identical(setup$per, prep$q))
      diag(normalized_S) - pmax(0, diag(normalized_S) - diag(normalized_G)) else
      normalized_S - .gt_d_psd(normalized_S - normalized_G)
    cov_gradients[[names(final$factors)[[s]]]] <- G
    cov_disagreement <- c(cov_disagreement, difference$disagreement)
    cov_steps[[names(final$factors)[[s]]]] <- difference$step
    cov_refinements[[names(final$factors)[[s]]]] <- difference$refinements
  }
  fixed_norm <- max(c(0, abs(fixed_score) / normalization))
  covariance_norm <- max(abs(c(0, unlist(projected))))
  finite_difference_disagreement <- max(c(0, fixed_disagreement, cov_disagreement))
  checked <- all(is.finite(c(base, fixed_norm, covariance_norm, finite_difference_disagreement))) && base < 1e99
  accepted <- checked && max(fixed_norm, covariance_norm) <= control$stationarity_tol &&
    finite_difference_disagreement <= control$stationarity_tol / 2
  list(stationary_within_tolerance = accepted, fixed_effect_score = fixed_score,
       covariance_gradients = cov_gradients, covariance_projected_scores = projected,
       fixed_effect_scaled_norm = fixed_norm, covariance_scaled_norm = covariance_norm,
       finite_difference_disagreement = finite_difference_disagreement,
       finite_difference_refinement = list(max_refinements = max_refinements,
         fixed_steps = fixed_steps, fixed_refinements = fixed_refinements,
         covariance_steps = cov_steps, covariance_refinements = cov_refinements,
         method = "Richardson extrapolation with bounded step halving; unchanged raw coarse/fine disagreement gate."),
       tolerance = control$stationarity_tol,
       scaling = "Fixed scores divided by sqrt(number of rows); source covariance PSD projection after scaling by max(1, largest source variance), with scores divided by sqrt(number of rows).",
       interpretation = "Independent local first-order Laplace-objective stationarity only; not global optimality, identification, or integration accuracy.")
}

.gt_d_fit_distance <- function(a, b, prep, setup) {
  fixed <- seq_along(prep$start)
  location <- max(c(0, abs(a[fixed] - b[fixed]) / pmax(1, abs(a[fixed]), abs(b[fixed]))))
  A <- .gt_d_covariance_factors(a[-fixed], setup)
  B <- .gt_d_covariance_factors(b[-fixed], setup)
  covariance <- max(c(0, vapply(seq_along(A), function(s) {
    S <- tcrossprod(A[[s]]); T <- tcrossprod(B[[s]])
    max(abs(S - T)) / max(1, abs(S), abs(T))
  }, numeric(1))))
  max(location, covariance)
}

# Fit one or more discrete outcomes using a joint Laplace likelihood
#
# Internal engine for gt_fit(). covariance is shared as a structure choice
# across sources; every source gets its own matrix. A multivariate ordinal or
# binary fit estimates source covariances across outcomes. A categorical fit
# has K-1 correlated category contrasts per outcome with an explicit reference.
# Mixed discrete families are supported; Gaussian-discrete combinations are
# outside this engine. Missing outcomes and unobserved declared categories are
# rejected in this first implementation. This engine has no REML estimator.
.gt_fit_discrete <- function(data, outcomes, design, families,
                             covariance = "unstructured", control = list()) {
  control <- .gt_d_control(control)
  if (!is.data.frame(data) || nrow(data) > control$max_observations)
    .gt_d_stop("Discrete prototype exceeds max_observations (", control$max_observations,
               "); use a smaller validation design or explicitly revise the resource guard.")
  prep <- .gt_d_prepare(data, outcomes, families)
  terms <- design$term_members
  if (!is.list(terms) || !length(terms) || is.null(names(terms)))
    .gt_d_stop("design must contain named random-source term_members.")
  if (any(!unique(unlist(terms, use.names = FALSE)) %in% names(data)))
    .gt_d_stop("Design grouping columns are missing from data.")
  groups <- lapply(terms, function(members) .gt_d_group(data, members))
  group_sizes <- vapply(groups, `[[`, integer(1), "nlevels")
  if (any(group_sizes < 2L)) .gt_d_stop("Every random source must contain at least two observed groups.")
  # An unrestricted observation-specific source confounds the identified
  # latent scale, including in joint binary/ordinal models; reject it here.
  if (any(group_sizes == nrow(data)))
    .gt_d_stop("Observation-specific random sources are not supported for discrete outcomes; preserve repeated observations within each source group.")
  random_dimension <- sum(group_sizes) * prep$q
  if (random_dimension > control$max_random_dimension)
    .gt_d_stop("Discrete prototype requires ", random_dimension,
               " random-effect dimensions, exceeding max_random_dimension (",
               control$max_random_dimension, "). This dense engine is for small validation designs.")
  setup <- .gt_d_covariance_setup(groups, prep$q, covariance, control, prep$dimensions)
  kernel_rank <- .gt_d_kernel_rank(groups)
  # A combination of individually repeated-group kernels can still equal I.
  # For probit responses, that permits rescaling the total latent covariance
  # and intercepts/thresholds despite the nominally fixed residual variance.
  # Apply this conservative prototype guard to all free-covariance discrete
  # fits; it is not a claim of nonidentification for every possible link/model.
  augmented_rank <- .gt_d_kernel_rank(c(unname(groups), list(
    list(index = seq_len(nrow(data)), nlevels = nrow(data)))))
  source_residual_rank <- list(rank = augmented_rank$rank,
    n_kernels = augmented_rank$n_sources, n_random_sources = length(groups),
    includes_observation_identity = TRUE,
    smallest_normalized_eigenvalue = augmented_rank$smallest_normalized_eigenvalue)
  if (is.null(setup$fixed) && kernel_rank$rank < kernel_rank$n_sources)
    .gt_d_stop("Random-source kernels are linearly dependent in the observed data; separate source covariances are not identified.")
  if (is.null(setup$fixed) && source_residual_rank$rank < source_residual_rank$n_kernels)
    .gt_d_stop("Random-source kernels span an observation-specific component. The discrete prototype does not estimate this structure alongside its fixed observation-scale model; revise the source specification.")
  start <- c(prep$start, setup$start)
  lower <- c(prep$lower, setup$lower)
  upper <- c(prep$upper, setup$upper)
  if (anyDuplicated(names(start)))
    .gt_d_stop("Outcome/source labels produce ambiguous discrete parameter names; rename the labels before fitting.")
  automatic_start <- start
  if (!is.null(control$start)) {
    unknown <- setdiff(names(control$start), names(start))
    if (length(unknown)) .gt_d_stop("Unknown discrete start parameter(s): ",
                                   paste(unknown, collapse = ", "), ".")
    start[names(control$start)] <- control$start
  }
  if (any(start < lower | start > upper))
    .gt_d_stop("Discrete start parameters must lie within their model bounds; check start_sd and explicit start values.")
  if (length(start) > control$max_parameters)
    .gt_d_stop("Discrete prototype exceeds max_parameters (", control$max_parameters, ").")
  objective <- function(par) .gt_d_laplace(par, prep, groups, setup, control)
  initial <- objective(start)
  if (!is.finite(initial) || initial >= 1e99)
    .gt_d_stop("The discrete likelihood did not yield a converged finite inner mode at starting values.")
  optimizer_control <- list(maxit = control$maxit,
    factr = control$reltol / .Machine$double.eps, trace = control$trace)
  primary_fit <- .gt_d_optimize(start, objective, lower, upper,
                                optimizer_control, "primary", optimizer = control$optimizer)
  attempts <- list(primary_fit$attempt)
  coarse_candidates <- list(primary_fit)
  # Optimizer completion alone is insufficient. Refine with a tighter inner
  # solve and objective tolerance, then independently restart away from the
  # fitted point. No random numbers or global RNG state are used for starts.
  validation_control <- control
  validation_control$inner_tol <- min(control$inner_tol, control$validation_inner_tol)
  validation_control$reltol <- min(control$reltol, control$validation_reltol)
  tight_objective <- function(par) .gt_d_laplace(par, prep, groups, setup, validation_control)
  optimize_tight <- function(at, label) {
    result <- .gt_d_optimize(at, tight_objective, lower, upper,
      list(maxit = control$maxit,
        factr = validation_control$reltol / .Machine$double.eps,
        pgtol = 1e-7, ndeps = rep(1e-4, length(start)), trace = control$trace), label,
      optimizer = control$optimizer)
    attempts[[length(attempts) + 1L]] <<- result$attempt
    result
  }
  fit <- optimize_tight(primary_fit$par, "primary_tight")
  alternatives <- vector("list", control$alternative_starts)
  for (attempt in seq_len(control$alternative_starts)) {
    alternative <- start
    fixed <- seq_along(prep$start)
    tier <- 1L + (attempt - 1L) %/% 2L
    alternative[fixed] <- alternative[fixed] + .15 * tier * (-1)^(fixed + attempt)
    if (length(setup$start)) {
      cov_index <- length(prep$start) + seq_along(setup$start)
      alternative[cov_index] <- setup$start
      diagonal <- rep(setup$diagpos, length(groups))
      multiplier <- if (attempt %% 2L) 1.8 * tier else .55 / tier
      if (identical(setup$parameterization, "variance")) {
        alternative[cov_index] <- alternative[cov_index] * multiplier^2
      } else {
        alternative[cov_index[diagonal]] <- alternative[cov_index[diagonal]] + log(multiplier)
        alternative[cov_index[!diagonal]] <- .1 * tier * (-1)^attempt
      }
    }
    alternative <- pmin(upper - 1e-6, pmax(lower + 1e-6, alternative))
    # Clipping extreme user starts can collapse otherwise distinct trials.
    # Keep a distinct first fixed-effect coordinate without using the RNG.
    duplicate_start <- function(x) any(vapply(coarse_candidates, function(candidate)
      identical(unname(x), unname(candidate$attempt$start)), logical(1)))
    if (duplicate_start(alternative)) {
      grid <- lower[[1L]] + seq(.1, .9, length.out = 25L) * (upper[[1L]] - lower[[1L]])
      for (value in grid[order(abs(grid - automatic_start[[1L]]))]) {
        alternative[[1L]] <- value
        if (!duplicate_start(alternative)) break
      }
    }
    alternative_primary <- .gt_d_optimize(alternative, objective, lower, upper,
      optimizer_control, paste0("alternative_", attempt), optimizer = control$optimizer)
    attempts[[length(attempts) + 1L]] <- alternative_primary$attempt
    coarse_candidates[[length(coarse_candidates) + 1L]] <- alternative_primary
    alternatives[[attempt]] <- optimize_tight(alternative_primary$par,
      paste0("alternative_", attempt, "_tight"))
  }
  # Return the best tight fit; retain all objective values and distances so a
  # better restart cannot erase evidence of unstable solutions.
  candidates <- c(list(fit), alternatives)
  values <- vapply(candidates, `[[`, numeric(1), "value")
  # Independently re-evaluate usable candidates; a diagnostic exception must
  # not erase a completed primary fit. Failed checks remain explicit and block
  # reliability, even when another candidate can be retained for inspection.
  final_checks <- list()
  evaluate_final <- function(candidate, settings, label) {
    captured <- .gt_d_capture(.gt_d_laplace(candidate$par, prep, groups,
      setup, settings, details = TRUE))
    valid <- isTRUE(captured$value$valid) &&
      is.finite(captured$value$nll) && captured$value$nll < 1e99
    final_checks[[length(final_checks) + 1L]] <<- list(label = label,
      valid = valid, error = captured$error, warnings = captured$warnings,
      elapsed_seconds = captured$elapsed_seconds)
    if (valid) captured$value else NULL
  }
  final <- NULL
  tight_final_mode <- FALSE
  usable <- which(vapply(candidates, function(x) isTRUE(x$result_available), logical(1)))
  for (index in usable[order(values[usable])]) {
    checked <- evaluate_final(candidates[[index]], validation_control,
                              paste0("tight_candidate_", index))
    if (!is.null(checked)) {
      fit <- candidates[[index]]
      final <- checked
      tight_final_mode <- TRUE
      break
    }
  }
  # Every usable preliminary attempt remains eligible for diagnostic fallback,
  # including alternatives when the primary and all refinements failed. Try
  # tight conditional modes for all of them before using a looser mode. Such
  # failed validation paths still block numerical acceptance below.
  if (is.null(final)) {
    coarse_values <- vapply(coarse_candidates, `[[`, numeric(1), "value")
    coarse_usable <- which(vapply(coarse_candidates,
      function(x) isTRUE(x$result_available), logical(1)))
    coarse_order <- coarse_usable[order(coarse_values[coarse_usable])]
    for (tight in c(TRUE, FALSE)) {
      checked_candidates <- lapply(coarse_order, function(index) {
        candidate <- coarse_candidates[[index]]
        evaluate_final(candidate, if (tight) validation_control else control,
          paste0(candidate$attempt$label, if (tight) "_fallback_tight" else "_fallback"))
      })
      valid <- which(!vapply(checked_candidates, is.null, logical(1)))
      if (length(valid)) {
        selected <- valid[[which.min(vapply(checked_candidates[valid], `[[`, numeric(1), "nll"))]]
        final <- checked_candidates[[selected]]
        fit <- coarse_candidates[[coarse_order[[selected]]]]
        tight_final_mode <- tight
        break
      }
    }
  }
  if (is.null(final)) stop(structure(list(
    message = "No fitted candidate supplied a usable final conditional mode; inspect the condition's attempts and final_checks.",
    call = NULL, attempts = attempts, final_checks = final_checks),
    class = c("gt_discrete_numerical_failure", "error", "condition")))
  captured_stationarity <- .gt_d_capture(.gt_d_stationarity(fit$par, prep,
    groups, setup, validation_control, final))
  stationarity <- captured_stationarity$value
  if (is.null(stationarity)) stationarity <- list(
    stationary_within_tolerance = FALSE,
    error = captured_stationarity$error, tolerance = control$stationarity_tol)
  stationarity$warnings <- captured_stationarity$warnings
  primary_tight <- .gt_d_capture(tight_objective(primary_fit$par))
  computation_failed <- any(vapply(attempts, function(x) !is.null(x$error), logical(1))) ||
    any(vapply(final_checks, function(x) !isTRUE(x$valid), logical(1))) ||
    !is.null(captured_stationarity$error) || !is.null(primary_tight$error)
  objective_difference <- abs(values - fit$value) / max(1, abs(fit$value))
  parameter_difference <- vapply(candidates, function(x) {
    if (!isTRUE(x$result_available)) return(Inf)
    .gt_d_fit_distance(x$par, fit$par, prep, setup)
  }, numeric(1))
  candidate_codes <- vapply(candidates, `[[`, integer(1), "convergence")
  stability <- list(checked = length(alternatives) > 0L,
    stable = length(alternatives) > 0L && !computation_failed &&
      tight_final_mode && all(candidate_codes == 0L) &&
      all(objective_difference <= control$stability_objective_tol) &&
      all(parameter_difference <= control$stability_parameter_tol),
    primary_optimizer_code = primary_fit$convergence,
    primary_objective_at_tighter_tolerance = if (is.null(primary_tight$value)) NA_real_ else primary_tight$value,
    primary_tight_evaluation_error = primary_tight$error,
    tight_objectives = values, optimizer_codes = candidate_codes,
    tight_parameters = lapply(candidates, `[[`, "par"),
    relative_objective_differences = objective_difference,
    scaled_parameter_differences = parameter_difference,
    objective_tolerance = control$stability_objective_tol,
    parameter_tolerance = control$stability_parameter_tol,
    alternative_starts = length(alternatives),
    validation_inner_tol = validation_control$inner_tol,
    validation_reltol = validation_control$reltol)
  components <- lapply(final$factors, function(L) {
    out <- tcrossprod(L)
    dimnames(out) <- list(prep$dimensions, prep$dimensions)
    out
  })
  means <- setNames(numeric(prep$q), prep$dimensions)
  thresholds <- list()
  residual <- setNames(rep(NA_real_, prep$q), prep$dimensions)
  mapping <- vector("list", length(prep$blocks))
  probabilities <- vector("list", length(prep$blocks))
  for (j in seq_along(prep$blocks)) {
    b <- prep$blocks[[j]]
    if (b$family == "ordinal") {
      thresholds[[b$outcome]] <- setNames(.gt_d_thresholds(fit$par[b$parameters]),
                                          paste(b$levels[-length(b$levels)], b$levels[-1L], sep = "|"))
      probs <- .gt_d_ordinal_probabilities(as.vector(final$eta[, b$dims]),
                                            thresholds[[b$outcome]], b$link)
    } else {
      means[b$dims] <- fit$par[b$parameters]
      if (b$family == "binary") {
        # Evaluate each tail directly: subtraction can round small but
        # representable negative-event probabilities to zero.
        cdf <- if (b$link == "probit") stats::pnorm else stats::plogis
        probs <- cbind(cdf(final$eta[, b$dims], lower.tail = FALSE),
                       cdf(final$eta[, b$dims]))
      } else {
        e <- cbind(0, final$eta[, b$dims, drop = FALSE])
        e <- exp(e - apply(e, 1L, max))
        probs <- e / rowSums(e)
      }
    }
    colnames(probs) <- b$levels
    probabilities[[j]] <- probs
    if (b$family != "categorical") residual[b$dims] <- if (b$link == "probit") 1 else pi^2 / 3
    mapping[[j]] <- data.frame(outcome = b$outcome, family = b$family, link = b$link,
                               dimension = prep$dimensions[b$dims],
                               category = if (b$family == "categorical") b$levels[-1L] else NA_character_,
                               reference = if (b$family == "categorical") b$levels[[1L]] else NA_character_,
                               stringsAsFactors = FALSE)
  }
  names(probabilities) <- outcomes
  natural_lower <- rep(FALSE, length(start))
  if (identical(setup$parameterization, "variance"))
    natural_lower[length(prep$start) + seq_along(setup$start)] <- TRUE
  at_bound <- names(start)[(!natural_lower & fit$par - lower < control$bound_tol) |
                            (upper - fit$par < control$bound_tol)]
  zero_variances <- names(start)[natural_lower & fit$par == 0]
  boundary_sources <- names(components)[vapply(components, function(S)
    min(eigen(S, symmetric = TRUE, only.values = TRUE)$values) < 1e-6, logical(1))]
  variables <- unique(c(design$object, design$facets))
  counts <- setNames(vapply(data[variables], function(x) length(unique(x)), integer(1)), variables)
  optimizer_completed <- fit$convergence == 0L
  converged <- optimizer_completed && final$inner_converged && tight_final_mode &&
    isTRUE(stationarity$stationary_within_tolerance) && stability$stable &&
    !computation_failed && !length(at_bound)
  approximation_adequacy <- if (all(vapply(final$factors, function(L) all(L == 0), logical(1))))
    "exact_no_random_variation" else "not_assessed_first_order_laplace"
  acceptance_failures <- c(if (!optimizer_completed) "optimizer_incomplete",
    if (!final$inner_converged) "inner_mode_not_converged",
    if (!tight_final_mode) "tight_final_mode_unavailable",
    if (computation_failed) "validation_computation_failed",
    if (!isTRUE(stationarity$stationary_within_tolerance)) "outer_stationarity_failed",
    if (!stability$stable) "restart_or_tolerance_stability_failed",
    if (length(at_bound)) "artificial_parameter_bound_contact")
  diagnostics <- list(converged = converged, optimizer_completed = optimizer_completed,
                       numerically_accepted = converged,
                       approximation_adequacy = approximation_adequacy,
                       acceptance_failures = acceptance_failures,
                       outer_stationarity = stationarity, stability = stability,
                       attempts = attempts, final_checks = final_checks,
                       selected_attempt = fit$attempt$label,
                       optimizer = control$optimizer,
                       optimizer_fixed_across_attempts = TRUE,
                       optimization_trials = length(attempts),
                       optimization_trial_budget = 2L * (1L + control$alternative_starts),
                       starting_parameters = start, automatic_starting_parameters = automatic_start,
                       supplied_start_parameters = control$start,
                       tight_final_mode = tight_final_mode,
                       covariance_parameterization = setup$parameterization,
                       covariance_parameterization_requested = control$covariance_parameterization,
                       zero_variance_parameters = zero_variances,
                       acceptance = "Completed optimizer, tight conditional mode, independent fixed-effect and covariance-scale stationarity, stable tight restarts, and no artificial-bound contact. Approximation adequacy is separate.",
                       optimizer_code = fit$convergence,
                       optimizer_message = fit$message, inner_converged = final$inner_converged,
                       inner_gradient = final$inner_gradient, inner_iterations = final$inner_iterations,
                       random_dimension = random_dimension, parameter_count = length(start),
                       boundary_sources = boundary_sources, parameter_bounds = at_bound,
                       source_kernel_rank = kernel_rank,
                       source_residual_kernel_rank = source_residual_rank,
                       source_covariances_estimated = is.null(setup$fixed),
                       observation_scale_guard = if (is.null(setup$fixed))
                         "Random-source kernels and observation identity must be linearly independent; necessary safeguard, not proof of identification." else
                         "Covariance-estimation rank guards bypassed because all source covariance matrices were supplied as fixed.",
                       approximation = "First-order Laplace marginal ML; accuracy is not established for sparse groups or large annotation panels.",
                       conditional_independence = TRUE,
                       uncertainty = "Parameter standard errors and confidence intervals are not implemented in this prototype.")
  design$validation_scope <- if (is.null(setup$fixed))
    "Observed grouping columns, repeated groups, and linear independence of source kernels plus observation identity; this is not proof of discrete-model identification." else
    "Observed grouping columns and repeated groups checked; all source covariances fixed, so covariance-estimation rank guards were not enforced."
  design$validated_data <- TRUE
  list(engine = "dense_joint_discrete_laplace", estimator = "ML_Laplace", method = "ML_Laplace",
       means = means, coefficients = means, thresholds = thresholds,
       covariance_components = components, latent_residual_variances = residual,
       link_dimensions = do.call(rbind, mapping), minus2loglik = 2 * final$nll,
       logLik = -final$nll, npar = length(start), nobs = nrow(data), counts = counts,
       group_counts = group_sizes, converged = converged,
       optimizer_completed = optimizer_completed, numerically_accepted = converged,
       approximation_adequacy = approximation_adequacy, diagnostics = diagnostics,
       conditional_eta = final$eta, conditional_probabilities = probabilities,
       uncertainty = list(available = FALSE,
         reason = paste("The dense first-order Laplace engine computes no observed information,",
           "so its coefficients are point estimates only."),
         method = NA_character_, boundary_components = boundary_sources),
       parameters = fit$par, starting_parameters = start, optimizer = fit, covariance = covariance,
       families = families, outcomes = outcomes, design = design, residual_structure = "fixed_by_link",
       control = control)
}

.gt_fit_binary <- function(data, outcomes, design, families,
                           covariance = "unstructured", control = list()) {
  if (any(vapply(families, function(x) x$family != "binary", logical(1))))
    .gt_d_stop(".gt_fit_binary requires binary family specifications.")
  .gt_fit_discrete(data, outcomes, design, families, covariance, control)
}

.gt_fit_ordinal <- function(data, outcomes, design, families,
                            covariance = "unstructured", control = list()) {
  if (any(vapply(families, function(x) x$family != "ordinal", logical(1))))
    .gt_d_stop(".gt_fit_ordinal requires ordinal family specifications.")
  .gt_fit_discrete(data, outcomes, design, families, covariance, control)
}

.gt_fit_categorical <- function(data, outcomes, design, families,
                                covariance = "unstructured", control = list()) {
  if (any(vapply(families, function(x) x$family != "categorical", logical(1))))
    .gt_d_stop(".gt_fit_categorical requires categorical family specifications.")
  .gt_fit_discrete(data, outcomes, design, families, covariance, control)
}
