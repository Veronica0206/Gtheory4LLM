# Full observed information against an independently fitted Laplace likelihood.
# Frozen observed panels are read, not regenerated; no full native panels run.
source("load_functions.R")
stopifnot(requireNamespace("ordinal", quietly = TRUE))
expect <- function(ok, message) if (!isTRUE(ok)) stop(message)
panels <- read.csv(file.path("validation-studies", "discrete-sparse-fitted-smoke", "panels.csv"),
                   stringsAsFactors = FALSE)
for (family in c("binary", "ordinal")) {
  panel_name <- if (family == "binary") "binary_logit_single_source" else "ordinal_logit_crossed"
  data <- panels[panels$panel == panel_name, c("item", "rater", "y")]
  levels <- if (family == "binary") c("0", "1") else paste0("c", 1:3)
  data$y <- if (family == "binary") as.integer(data$y) else ordered(data$y, levels = levels)
  fit <- gt_fit(data, "y", gt_design("item", "rater", random = "item"),
    gt_family(family, "logit", levels = levels),
    control = gt_control(discrete = list(engine = "sparse", optimizer = "nlminb",
      check_hessian = TRUE, maxit = 200)))
  expect(fit$numerically_accepted && fit$diagnostics$stability$stable &&
         fit$diagnostics$outer_stationarity$stationary_within_tolerance &&
         fit$uncertainty$available, paste(family, "accepted interior fit supplies observed information"))
  expect(fit$covariance_components$item[1, 1] > 0.1 &&
         !length(fit$uncertainty$boundary_components), "The variance is estimated in the interior")
  expect(identical(names(fit$parameters), names(fit$starting_parameters)) &&
         identical(names(fit$uncertainty$parameter_standard_errors), names(fit$parameters)),
         "Selected optimizer coordinates and standard errors retain their parameter names")

  # With two ordered levels the cumulative-logit model is the Bernoulli-logit
  # model with threshold = -intercept. useMatrix=TRUE fits its random SD
  # directly; assert that coordinate contract before transforming the Hessian.
  data$y <- ordered(as.character(data$y), levels = levels)
  reference_warnings <- character()
  reference <- withCallingHandlers(ordinal::clmm(y ~ 1 + (1 | item), data,
    link = "logit", nAGQ = 1, Hess = TRUE,
    control = ordinal::clmm.control(gradTol = 1e-6, maxIter = 200, useMatrix = TRUE)),
    warning = function(w) {
      reference_warnings <<- c(reference_warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  reference_sd <- as.numeric(reference$ST$item)
  variance <- reference_sd^2
  expect(reference$optRes$convergence == 0 && max(abs(reference$gradient)) < 1e-3 &&
         !length(reference_warnings), paste(family, "external reference converges without warnings"))
  expect(abs(tail(reference$optRes$par, 1) - reference_sd) < 1e-12,
         "The external Hessian's final coordinate is the random SD")
  expect(abs(fit$minus2loglik + 2 * as.numeric(logLik(reference))) < 1e-5 &&
         abs(fit$covariance_components$item[1, 1] - variance) < 1e-3,
         paste(family, "estimated likelihood and variance agree with clmm"))

  # Transform the FULL nuisance+SD information. Inverting only the variance
  # block would implicitly fix estimated intercepts/thresholds and understate SE.
  J <- if (family == "binary") diag(c(-1, 1 / (2 * reference_sd))) else
    rbind(c(1, 0, 0), c(1, diff(reference$alpha), 0), c(0, 0, 1 / (2 * reference_sd)))
  reference_information <- t(J) %*% reference$Hessian %*% J
  reference_covariance <- solve(reference_information)
  H <- fit$uncertainty$hessian
  relative_scale <- pmax(1, sqrt(outer(diag(reference_information), diag(reference_information))))
  expect(max(abs(H - reference_information) / relative_scale) < 1e-3,
         paste(family, "all nuisance/variance curvature blocks agree with independent information"))
  expect(max(abs(fit$uncertainty$parameter_covariance - reference_covariance)) < 1e-4,
         paste(family, "full parameter covariance agrees after coordinate conversion"))
  p <- nrow(reference_covariance)
  reference_variance_se <- sqrt(reference_covariance[p, p])
  expect(abs(sqrt(fit$uncertainty$entry_covariance[1, 1]) - reference_variance_se) < 1e-4,
         paste(family, "estimated source-variance standard error agrees"))
  if (family == "ordinal")
    expect(abs(reference_covariance[p, p] - 1 / reference_information[p, p]) > 0.005,
           "Threshold uncertainty materially changes the variance standard error")

  # A single item source has G = variance/(variance + logistic residual/m).
  # This independent derivative also checks propagation through the source map.
  reliability <- as.data.frame(gt_reliability(fit, scale = "latent"))
  residual <- (pi^2 / 3) / length(unique(data$rater))
  reference_coefficient_se <- residual / (variance + residual)^2 * reference_variance_se
  expect(abs(reliability$Erho2_se - reference_coefficient_se) < 1e-4,
         paste(family, "latent coefficient SE agrees with independent variance-information delta method"))
  cat("PASS:", family, "interior information and latent coefficient SE against clmm.\n")
}

# Nominal covariance Jacobian from closed expressions, independent of the
# factor decoder. Three unordered labels give two jointly modelled contrasts.
nominal <- data.frame(item = rep(seq_len(4L), each = 3L),
                      y = factor(rep(c("red", "blue", "green"), 4L),
                                 levels = c("red", "blue", "green")))
prep <- .gt_d_prepare(nominal, "y", list(gt_family("categorical", "softmax",
  levels = levels(nominal$y), reference = "blue")))
groups <- list(item = .gt_d_group(nominal, "item"))
setup <- .gt_d_covariance_setup(groups, prep$q, "unstructured",
  .gt_d_control(list(covariance_parameterization = "log_cholesky")), prep$dimensions)
parameters <- c(prep$start, setup$start)
a <- log(0.7)
b <- 0.23
c <- log(0.9)
parameters[3:5] <- c(a, b, c)
mapping <- .gt_d_information_mapping(parameters, prep, groups, setup)
oracle <- matrix(0, 3L, 5L)
oracle[, 3:5] <- rbind(c(2 * exp(2 * a), 0, 0),
                       c(b * exp(a), exp(a), 0), c(0, 2 * b, 2 * exp(2 * c)))
expect(max(abs(mapping$jacobian - oracle)) < 1e-14,
       "Nominal variances and covariance use the exact full Cholesky derivative")
expect(identical(mapping$entries$row, prep$dimensions[c(1, 2, 2)]) &&
       identical(mapping$entries$column, prep$dimensions[c(1, 1, 2)]) &&
       all(mapping$jacobian[, 1:2] == 0),
       "Nominal contrast labels, covariance ordering, and nuisance offset are retained")
cat("PASS: nominal off-diagonal source-covariance Jacobian against closed expressions.\n")
