# Run from the project root: Rscript tests/test_gaussian_initialization.R
# Square-root recovery for the exact balanced Gaussian engine.
#
# Three layers. (1) The retry controller with the optimizer and the recovery
# injected: the primary attempt is never touched, recovery needs a refusal and
# an unused attempt, it starts from the original coordinates, it consumes one
# existing attempt, and a refused or throwing initializer is retained while the
# ordinary perturbation policy resumes. (2) The square-root kernel: its value
# equals the engine's exact stratum deviance and an independent dense
# covariance deviance at the model's own coordinates, its analytic gradient
# matches finite differences in every coordinate, it is invariant to outcome
# permutation and unit changes, and an initializer whose independent
# reconstruction fails is refused. (3) The public policies: an accepted primary
# attempt is identical under "automatic" and "none", and a one-iteration
# ordinary budget exercises a real recovery without relaxing acceptance.
source("load_functions.R")
check <- function(x, label) {
  if (!isTRUE(x)) stop(label, call. = FALSE)
  cat("PASS:", label, "\n")
}

# ---- (1) controller --------------------------------------------------------
model_stub <- function(tag, value, status = 6L)
  structure(list(tag = tag, output = list(fit = value, status = list(code = status))), class = "MxModel")
scenario <- function(values, budget, eligible = TRUE, throw = FALSE) {
  original <- model_stub("original", NA_real_)
  attempts <- recoveries <- 0L
  starts <- character()
  recovery_start <- NULL
  run <- function(m, silent = TRUE) {
    attempts <<- attempts + 1L
    starts <<- c(starts, m$tag)
    values[[attempts]]
  }
  assess <- function(m) list(accepted = identical(m$output$status$code, 0L),
    components = list(Residual = matrix(1)), likelihood_matches = m$tag != "corrupt",
    reason = if (m$tag == "corrupt") "likelihood mismatch" else "numerical refusal")
  recover <- function(m) {
    recoveries <<- recoveries + 1L
    recovery_start <<- m$tag
    if (throw) stop("initializer refused")
    list(model = if (eligible) model_stub("recovered", NA_real_) else NULL,
         diagnostics = list(status = if (eligible) "handoff_eligible" else "refused",
                            eligible = eligible))
  }
  answer <- tryCatch(.gt_gaussian_retry(original, "CSOLNP", budget - 1L, 1e-12, 3000L,
    "sample_MoM", TRUE, assess, run = run,
    jitter = function(m) { m$tag <- paste0("jitter:", m$tag); m }, recover = recover),
    error = identity)
  list(answer = answer, attempts = attempts, recoveries = recoveries, starts = starts,
       recovery_start = recovery_start)
}
a <- scenario(list(model_stub("success", 1, 0L)), 3L)
check(a$attempts == 1L && a$recoveries == 0L && identical(a$starts, "original"),
      "accepted primary: no recovery, no second attempt")
b <- scenario(list(model_stub("corrupt", -1e30), model_stub("accepted", 10, 0L)), 3L)
check(b$attempts == 2L && b$recoveries == 1L && b$recovery_start == "original" &&
      identical(b$starts, c("original", "recovered")) && b$answer$optimizer_runs == 2L &&
      b$answer$budget == 3L &&
      identical(b$answer$attempts$start_type, c("sample_MoM", "square_root_cold_recovery")) &&
      b$answer$recovery_record$trigger_attempt == 1L && b$answer$recovery_record$handoff_attempt == 2L &&
      b$answer$recovery_record$ordinary_budget == 3L,
      "refused primary: one recovery from the original coordinates consumes attempt two")
c <- scenario(list(model_stub("corrupt", -1e30)), 1L)
check(c$attempts == 1L && c$recoveries == 0L && !isTRUE(c$answer$assessment$accepted),
      "no recovery without an unused attempt")
d <- scenario(list(model_stub("corrupt", -1e30), model_stub("valid-refused", 10),
                   model_stub("accepted", 9, 0L)), 3L, eligible = FALSE)
check(d$recoveries == 1L && d$attempts == 3L &&
      identical(d$starts, c("original", "jitter:original", "jitter:valid-refused")) &&
      identical(d$answer$recovery_record$status, "refused") &&
      is.na(d$answer$recovery_record$handoff_attempt),
      "refused initializer: ordinary perturbation resumes from the original, then the valid anchor")
e <- scenario(list(model_stub("corrupt", -1e30), model_stub("still-refused", 10)), 2L, throw = TRUE)
check(e$recoveries == 1L && e$attempts == 2L && !isTRUE(e$answer$assessment$accepted) &&
      e$answer$recovery_record$error == "initializer refused",
      "throwing initializer: retained as a refusal, the budget is still spent")

# ---- (2) kernel ------------------------------------------------------------
set.seed(781L)
d12 <- expand.grid(subject = 1:12, rater = letters[1:3], occasion = 1:2,
                   KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
Y <- matrix(rnorm(nrow(d12) * 3), nrow(d12), 3) %*%
  chol(matrix(c(1, .2, .1, .2, 1.3, .1, .1, .1, .8), 3)) +
  matrix(rnorm(36), 12, 3)[d12$subject, ] + matrix(rnorm(9), 3, 3)[match(d12$rater, letters), ] +
  matrix(rnorm(6), 2, 3)[d12$occasion, ]
d12$one <- Y[, 1]; d12$two <- Y[, 2]; d12$three <- Y[, 3]
outcomes <- c("one", "two", "three")
facets <- c("subject", "rater", "occasion")
spec <- facets
covariance <- c(subject = "unstructured", rater = "diagonal", occasion = "diagonal")
raw_deviance <- function(data, outcomes, components, reml) {
  N <- nrow(data); D <- length(outcomes); V <- matrix(0, N * D, N * D)
  for (g in names(components)) {
    K <- if (g == "Residual") diag(N) else
      Reduce(`*`, lapply(data[strsplit(g, ":", fixed = TRUE)[[1L]]], function(x) outer(x, x, `==`)))
    V <- V + kronecker(K, components[[g]])
  }
  Cv <- chol(V); inverse <- chol2inv(Cv); X <- kronecker(matrix(1, N, 1), diag(D))
  info <- crossprod(X, inverse %*% X)
  y <- as.vector(t(as.matrix(data[outcomes]))); beta <- solve(info, crossprod(X, inverse %*% y))
  error <- y - X %*% beta
  value <- (N * D - if (reml) D else 0) * log(2 * pi) + 2 * sum(log(diag(Cv))) +
    drop(crossprod(error, inverse %*% error))
  if (reml) value <- value + 2 * sum(log(diag(chol(info))))
  value
}
# Capture the initializer's context at model construction, without optimizing.
build <- function(data, outs, reml = TRUE, residual = "unstructured") {
  e <- .gt_gaussian_engine(facets)
  env <- environment(e$fit)
  captured <- NULL
  assign(".gt_square_root_initialize", function(context, independent) {
    captured <<- context
    list(eligible = FALSE, status = "context_only")
  }, envir = env)
  assign(".gt_gaussian_retry", function(model, ..., recover = NULL) {
    if (!is.null(recover)) recover(model)
    stop(structure(list(message = "context-only construction", call = NULL, model = model),
                   class = c("context_capture", "error", "condition")))
  }, envir = env)
  prepared <- e$prepare(data, outs)
  result <- tryCatch(e$fit(data, outs, spec = spec, covariance = covariance, residual = residual,
    reml = reml, prepared = prepared, check_hessian = FALSE), context_capture = identity)
  stopifnot(inherits(result, "context_capture"), !is.null(captured))
  list(context = captured, prepared = prepared, model = result$model, engine = e)
}
parameter_for <- function(components, context) {
  x <- context$parameter
  for (g in names(context$sources)) {
    s <- context$sources[[g]]; M <- components[[g]]
    if (s$type == "diagonal") x[s$labels] <- diag(M) / s$scales
    else if (s$type == "pooled") x[s$labels] <- mean(diag(M))
    else x[s$labels] <- t(chol(M))[s$select]
  }
  x
}
contexts <- list()
for (reml in c(FALSE, TRUE)) for (residual in c("unstructured", "pooled")) {
  key <- paste(if (reml) "REML" else "ML", residual, sep = "_")
  b <- build(d12, outcomes, reml, residual); ctx <- b$context
  a <- .gt_square_root_evaluate(ctx$parameter, ctx)
  check(abs(a$value - b$engine$deviance(b$prepared, a$components, reml)) < 1e-8,
        paste(key, "value equals the exact stratum deviance"))
  check(abs(a$value - raw_deviance(d12, outcomes, a$components, reml)) < 1e-8,
        paste(key, "value equals the dense covariance deviance"))
  check(any(vapply(b$prepared$strata, function(s) ncol(s$root) < length(outcomes), logical(1))),
        paste(key, "rectangular low-df roots are handled"))
  check(ctx$root_max_reconstruction_error < 1e-12, paste(key, "cross-product roots reconstruct"))
  lb <- OpenMx::omxGetParameters(b$model, fetch = "lbound"); lb[is.na(lb)] <- -Inf
  ub <- OpenMx::omxGetParameters(b$model, fetch = "ubound"); ub[is.na(ub)] <- Inf
  check(identical(ctx$lower, lb) && identical(ctx$upper, ub), paste(key, "bounds and labels match the model"))
  fd <- ctx$parameter
  for (j in seq_along(fd)) {
    h <- 1e-5 * max(1, abs(fd[j])); u <- v <- ctx$parameter; u[j] <- u[j] + h
    if (v[j] - h < ctx$lower[j]) {
      v[j] <- v[j] + 2 * h
      fd[j] <- (-3 * a$value + 4 * .gt_square_root_evaluate(u, ctx)$value -
                  .gt_square_root_evaluate(v, ctx)$value) / (2 * h)
    } else {
      v[j] <- v[j] - h
      fd[j] <- (.gt_square_root_evaluate(u, ctx)$value - .gt_square_root_evaluate(v, ctx)$value) / (2 * h)
    }
  }
  check(max(abs(fd - a$gradient) / pmax(1, abs(fd), abs(a$gradient))) < 2e-5,
        paste(key, "analytic gradient matches finite differences in every coordinate"))
  perm <- c(3, 1, 2); bp <- build(d12, outcomes[perm], reml, residual)
  mapped <- lapply(a$components, function(M) M[perm, perm]); xp <- parameter_for(mapped, bp$context)
  check(abs(.gt_square_root_evaluate(xp, bp$context)$value - a$value) < 1e-8,
        paste(key, "outcome permutation invariance"))
  scale <- if (residual == "pooled") rep(3, 3) else c(.01, 3, 100)
  du <- d12; du[outcomes] <- Map(`*`, du[outcomes], scale); bu <- build(du, outcomes, reml, residual)
  scaled <- lapply(a$components, function(M) M * outer(scale, scale)); xu <- parameter_for(scaled, bu$context)
  expected <- 2 * (nrow(d12) - as.integer(reml)) * sum(log(scale))
  check(abs(.gt_square_root_evaluate(xu, bu$context)$value - a$value - expected) < 1e-7,
        paste(key, "unit transformation and determinant convention"))
  contexts[[key]] <- b
}
limit <- contexts[[1L]]$prepared$allocation$estimated_bytes
check(inherits(tryCatch(contexts[[1L]]$engine$prepare(d12, outcomes, max_preparation_bytes = limit - 1),
                        error = identity), "error"),
      "preparation guard includes the roots and refuses before allocation")
ctx <- contexts[[1L]]$context; outside <- ctx$parameter; outside[1] <- ctx$lower[1] - 1
check(inherits(tryCatch(.gt_square_root_evaluate(outside, ctx), error = identity), "error"),
      "out-of-bound coordinates are refused")
refused <- .gt_square_root_initialize(ctx, function(x) Inf)
check(!refused$eligible && refused$status == "refused" && is.null(refused$context),
      "an initializer whose independent reconstruction fails is refused, and the record is compact")
eligible <- .gt_square_root_initialize(ctx, function(components)
  contexts[[1L]]$engine$deviance(contexts[[1L]]$prepared, components, reml = FALSE))
check(eligible$eligible && eligible$status == "handoff_eligible" && eligible$independent_difference <= 1e-5 &&
      eligible$objective_calls > 0L && is.null(eligible$context),
      "an initializer reproduced by the independent deviance is eligible")

# ---- (3) public policies ---------------------------------------------------
fits <- list()
for (estimator in c("ML", "REML")) for (policy in c("automatic", "none")) {
  fits[[paste(estimator, policy)]] <- gt_fit(cbind(one, two, three) ~ subject + rater + occasion, d12,
    measured = "subject", covariance = covariance, estimator = estimator,
    control = gt_control(gaussian = list(extra_tries = 1L, check_hessian = TRUE, retry_seed = 439L,
      tolerance = 1e-10, threads = 1L, initialization = policy)))
}
for (estimator in c("ML", "REML")) {
  auto <- fits[[paste(estimator, "automatic")]]; none <- fits[[paste(estimator, "none")]]
  check(isTRUE(gt_diagnostics(auto)$numerically_accepted) && auto$optimization_trials == 1L &&
        identical(gt_components(auto), gt_components(none)) &&
        identical(deviance(auto), deviance(none)) && identical(auto$retry_attempts, none$retry_attempts) &&
        identical(auto$diagnostics$covariance_stationarity, none$diagnostics$covariance_stationarity) &&
        identical(gt_diagnostics(auto)$initialization$status, "not_invoked") &&
        identical(gt_diagnostics(none)$initialization$status, "disabled"),
        paste(estimator, "accepted primary attempt is identical under both policies"))
}
printed <- capture.output(print(gt_diagnostics(fits[["ML automatic"]])))
check(any(grepl("Square-root initialization: not_invoked", printed, fixed = TRUE)),
      "the diagnostics print names the initialization status")
check(inherits(tryCatch(gt_control(gaussian = list(initialization = "bogus")), error = identity), "error") ||
      inherits(tryCatch(gt_fit(cbind(one, two, three) ~ subject + rater + occasion, d12, measured = "subject",
        control = gt_control(gaussian = list(initialization = "bogus"))), error = identity), "error"),
      "an unknown initialization value is refused")
check(inherits(tryCatch(gt_fit(one ~ subject + rater + occasion, d12, measured = "subject",
        control = gt_control(gaussian = list(engine = "lme4", initialization = "automatic"))),
        error = identity), "error"),
      "initialization is refused with the lme4 engine")
# A one-iteration ordinary budget forces a refusal of the primary attempt.
one <- list()
for (policy in c("automatic", "none")) {
  warnings <- character()
  one[[policy]] <- withCallingHandlers(gt_fit(cbind(one, two, three) ~ subject + rater + occasion, d12,
    measured = "subject", covariance = covariance, estimator = "REML",
    control = gt_control(gaussian = list(extra_tries = 1L, check_hessian = TRUE, retry_seed = 439L,
      tolerance = 1e-10, max_iterations = 1L, threads = 1L, initialization = policy))),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") })
}
init <- gt_diagnostics(one$automatic)$initialization
primary_columns <- setdiff(names(one$none$retry_attempts), "returned_fit")
check(identical(one$automatic$retry_attempts[1, primary_columns], one$none$retry_attempts[1, primary_columns]),
      "one-iteration budget: the primary attempt record is identical under both policies")
check(init$status %in% c("handoff_eligible", "refused") && init$trigger_attempt == 1L &&
      init$ordinary_budget == 2L,
      "one-iteration budget: recovery was invoked after the refused primary attempt")
check(identical(one$none$retry_attempts$start_type[2], "uniform_perturbation") &&
      identical(one$automatic$retry_attempts$start_type[2],
        if (isTRUE(init$eligible)) "square_root_cold_recovery" else "uniform_perturbation"),
      "one-iteration budget: the second attempt is the handoff when eligible, otherwise the ordinary perturbation")
for (policy in names(one)) if (isTRUE(gt_diagnostics(one[[policy]])$numerically_accepted))
  check(one[[policy]]$status == 0L && isTRUE(one[[policy]]$diagnostics$independent_likelihood_matches) &&
        isTRUE(one[[policy]]$diagnostics$covariance_stationarity$stationary_within_tolerance),
        paste(policy, "an accepted one-iteration fit passed every ordinary gate"))
cat("PASS: square-root recovery controller, kernel and public policies.\n")
