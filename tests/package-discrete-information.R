# Estimated interior binary/ordinal information through installed public APIs.
# Frozen response panels retain the source regression's observations and tolerances.
library(Gtheory4LLM)
expect <- function(ok, message) if (!isTRUE(ok)) stop(message)
# Direct installed runners may execute an absolute script path from another
# directory. Resolve its own archive fixture before considering a check cwd.
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
test_directory <- "."
if (length(script_arg) == 1L) {
  script_path <- sub("^--file=", "", script_arg)
  # Rscript encodes argument spaces as ~+~ on some R/platform combinations.
  # Keep an existing literal filename before trying the decoded form.
  if (!file.exists(script_path)) script_path <- gsub("~+~", " ", script_path, fixed = TRUE)
  test_directory <- dirname(normalizePath(script_path, mustWork = TRUE))
}
fixture <- file.path(test_directory, "fixtures", "discrete-information-panels.csv")
if (!file.exists(fixture)) fixture <- file.path("tests", "fixtures", "discrete-information-panels.csv")
expect(file.exists(fixture), "The installed test archive contains its frozen response fixture")
panels <- read.csv(fixture, stringsAsFactors = FALSE)
for (family in c("binary", "ordinal")) {
  panel_name <- if (family == "binary") "binary_logit_single_source" else "ordinal_logit_crossed"
  data <- panels[panels$panel == panel_name, c("item", "rater", "y")]
  levels <- if (family == "binary") c("0", "1") else paste0("c", 1:3)
  data$y <- if (family == "binary") as.integer(data$y) else ordered(data$y, levels = levels)
  fit <- gt_fit(data, "y", gt_design("item", "rater", random = "item"),
    gt_family(family, "logit", levels = levels),
    control = gt_control(discrete = list(engine = "sparse", optimizer = "nlminb",
      check_hessian = TRUE, maxit = 200)))
  diagnostics <- gt_diagnostics(fit)
  expect(diagnostics$numerically_accepted && diagnostics$diagnostics$stability$stable &&
         diagnostics$stationarity$stationary_within_tolerance &&
         diagnostics$standard_errors_available,
         paste(family, "accepted interior fit supplies observed information"))
  components <- gt_components(fit)
  expect(components$item[1, 1] > 0.1 && !length(diagnostics$boundary_sources),
         "The source variance is estimated in the interior")
  covariance <- gt_component_vcov(fit, "parameters")
  component_covariance <- gt_component_vcov(fit)
  expect(is.matrix(covariance) && identical(rownames(covariance), colnames(covariance)) &&
         all(is.finite(covariance)) && min(eigen(covariance, symmetric = TRUE)$values) > 0 &&
         length(attr(covariance, "conditional_on_fixed")) == 0 &&
         component_covariance[1, 1] > 0,
         "Full nuisance-plus-variance uncertainty is finite, positive and not conditional on fixed components")
  reliability <- as.data.frame(gt_reliability(fit, scale = "latent"))
  expect(is.finite(reliability$Erho2_se) && reliability$Erho2_se > 0,
         "The latent coefficient carries nonzero parameter uncertainty")

  if (requireNamespace("ordinal", quietly = TRUE)) {
    # clmm uses a threshold = -intercept for binary logit, and an SD coordinate.
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
    expect(abs(-2 * as.numeric(logLik(fit)) + 2 * as.numeric(logLik(reference))) < 1e-5 &&
           abs(components$item[1, 1] - variance) < 1e-3,
           paste(family, "estimated likelihood and variance agree with clmm"))

    # Transform the entire nuisance-plus-SD Hessian before inverting it.
    J <- if (family == "binary") diag(c(-1, 1 / (2 * reference_sd))) else
      rbind(c(1, 0, 0), c(1, diff(reference$alpha), 0), c(0, 0, 1 / (2 * reference_sd)))
    reference_information <- t(J) %*% reference$Hessian %*% J
    reference_covariance <- solve(reference_information)
    H <- solve(covariance)
    relative_scale <- pmax(1, sqrt(outer(diag(reference_information), diag(reference_information))))
    expect(max(abs(H - reference_information) / relative_scale) < 1e-3,
           paste(family, "all nuisance/variance curvature blocks agree with independent information"))
    expect(max(abs(covariance - reference_covariance)) < 1e-4,
           paste(family, "full parameter covariance agrees after coordinate conversion"))
    p <- nrow(reference_covariance)
    reference_variance_se <- sqrt(reference_covariance[p, p])
    expect(abs(sqrt(component_covariance[1, 1]) - reference_variance_se) < 1e-4,
           paste(family, "estimated source-variance standard error agrees"))
    if (family == "ordinal")
      expect(abs(reference_covariance[p, p] - 1 / reference_information[p, p]) > 0.005,
             "Threshold uncertainty materially changes the variance standard error")
    residual <- (pi^2 / 3) / length(unique(data$rater))
    reference_coefficient_se <- residual / (variance + residual)^2 * reference_variance_se
    expect(abs(reliability$Erho2_se - reference_coefficient_se) < 1e-4,
           paste(family, "latent coefficient SE agrees with the independent full-information delta method"))
    cat("PASS:", family, "interior information and latent coefficient SE against clmm.\n")
  } else cat("SKIP:", family, "external information comparison: suggested ordinal is unavailable.\n")
}
cat("PASS: installed estimated interior sparse information and latent uncertainty.\n")
