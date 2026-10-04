# One public-API fit; the Python parent enforces its wall-clock deadline.
args <- commandArgs(trailingOnly = TRUE)
out <- args[[1L]]; lib <- args[[2L]]; k <- as.integer(args[[3L]])
.libPaths(c(normalizePath(lib), .libPaths()))
library(Gtheory4LLM, lib.loc = lib)
stopifnot(as.character(packageVersion("Gtheory4LLM")) == "0.3.0.9000")
s <- read.csv(file.path(out, "plan.csv"), stringsAsFactors = FALSE)[k, ]
d <- read.csv(file.path(out, "panels", sprintf("%02d.csv", k)), stringsAsFactors = FALSE,
              colClasses = c(occasion = "integer", item = "integer", y = "character"))
lev <- if (s$family == "binary") c("0", "1") else c("low", "middle", "high")
if (s$family == "binary") d$y <- as.integer(d$y) else d$y <- ordered(d$y, levels = lev)
counts <- table(factor(as.character(d$y), levels = lev))
row <- data.frame(attempt = k, status = "error", accepted = FALSE, optimizer_completed = FALSE,
                  variance_estimate = NA_real_, reliability_estimate = NA_real_, boundary = NA,
                  observations = nrow(d), category_counts = paste(names(counts), counts, sep = ":", collapse = ";"),
                  engine = "", approximation_adequacy = "", acceptance_failures = "",
                  invalid_evaluations = NA_integer_, fit_seconds = NA_real_, warnings = "", error = "")
warn <- character()
start <- proc.time()[["elapsed"]]
fit <- tryCatch(withCallingHandlers(gt_fit(d, "y",
  gt_design("item", "occasion", random = ~ item, full_cell = FALSE),
  gt_family(s$family, "probit", levels = lev), covariance = "diagonal",
  control = gt_control(discrete = list(maxit = 150L, optimizer = "L-BFGS-B"),
                       retain = list(data = FALSE, model = FALSE, session = FALSE))),
  warning = function(w) { warn <<- c(warn, conditionMessage(w)); invokeRestart("muffleWarning") }),
  error = identity)
row$fit_seconds <- proc.time()[["elapsed"]] - start
row$warnings <- paste(unique(warn), collapse = " | ")
if (inherits(fit, "error")) {
  row$error <- conditionMessage(fit)
  saveRDS(list(error = row$error, condition_class = class(fit)), file.path(out, "details", sprintf("%02d.rds", k)))
} else {
  row$accepted <- isTRUE(fit$numerically_accepted)
  row$status <- if (row$accepted) "accepted" else "rejected"
  row$optimizer_completed <- isTRUE(fit$optimizer_completed)
  row$variance_estimate <- fit$covariance_components$item[1, 1]
  row$boundary <- length(fit$diagnostics$boundary_sources) > 0L
  row$engine <- fit$engine
  row$approximation_adequacy <- fit$approximation_adequacy
  row$acceptance_failures <- paste(fit$diagnostics$acceptance_failures, collapse = ";")
  row$invalid_evaluations <- fit$diagnostics$evaluations$invalid
  stopifnot(identical(fit$engine, "dense_joint_discrete_laplace"))
  if (row$accepted) {
    rel <- tryCatch(gt_reliability(fit, scale = "latent"), error = identity)
    if (inherits(rel, "error")) row$error <- paste("Coefficient extraction:", conditionMessage(rel)) else {
      stopifnot(abs(rel$per_trait$Erho2 - rel$per_trait$Phi) < 1e-12)
      row$reliability_estimate <- rel$per_trait$Erho2
    }
  }
  saveRDS(list(diagnostics = gt_diagnostics(fit), variance = row$variance_estimate,
               parameters = fit$parameters, thresholds = fit$thresholds),
          file.path(out, "details", sprintf("%02d.rds", k)))
}
row$error <- gsub("[\r\n]+", " ", row$error)
write.csv(row, file.path(out, "worker", sprintf("%02d.csv", k)), row.names = FALSE, na = "NA")
