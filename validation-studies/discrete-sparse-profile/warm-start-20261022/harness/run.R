# Independent synthetic full-panel scale characterization; no manuscript data.
args <- commandArgs(TRUE)
stopifnot(length(args) %in% c(3L, 4L))
if (length(args) == 4L) stopifnot(args[[4L]] == "preflight-only")
source_root <- normalizePath(args[[1L]], mustWork = TRUE)
output <- normalizePath(args[[2L]], mustWork = TRUE)
optimizer <- args[[3L]]
stopifnot(optimizer %in% c("L-BFGS-B", "nlminb"))
source(file.path(source_root, "load_functions.R"))
write_json <- function(x, name) {
  path <- file.path(output, name)
  stopifnot(!file.exists(path))
  jsonlite::write_json(x, path, pretty = TRUE, auto_unbox = TRUE,
                       digits = 16, null = "null", na = "null")
}
capture <- function(expr) {
  warnings <- character()
  error <- NULL
  timing <- system.time(value <- tryCatch(withCallingHandlers(force(expr),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
    }), error = function(e) { error <<- conditionMessage(e); NULL }))
  list(value = value, warnings = warnings, error = error, timing = timing)
}

# All six random sources below enter the data-generating model. The three
# remaining axes only index independent replicates conditional on those effects.
# This is a deliberately stated synthetic covariance law, not an adopted model
# of any of the package's three real annotation panels.
data <- expand.grid(item = seq_len(100L), evaluator = seq_len(4L),
  prompt = seq_len(3L), temperature = seq_len(6L), seed = seq_len(3L))
source_variance <- c(item = 1, evaluator = .2, prompt = .15,
                     "item:evaluator" = .25, "item:prompt" = .2,
                     "evaluator:prompt" = .1)
set.seed(2026102101L)
eta <- numeric(nrow(data))
groups <- list()
for (name in names(source_variance)) {
  variables <- strsplit(name, ":", fixed = TRUE)[[1L]]
  group <- do.call(interaction, c(data[variables], list(drop = TRUE)))
  groups[[name]] <- nlevels(group)
  eta <- eta + rnorm(nlevels(group), sd = sqrt(source_variance[[name]]))[as.integer(group)]
}
latent <- eta + rnorm(nrow(data))
thresholds <- c(-.7, .6)
data$y <- ordered(c("low", "middle", "high")[1L + (latent > thresholds[1L]) +
                                                      (latent > thresholds[2L])],
                  levels = c("low", "middle", "high"))
write.csv(data, file.path(output, "input.csv"), row.names = FALSE)
write_json(list(generator_seed = 2026102101L, rows = nrow(data),
  source_variances = as.list(source_variance), thresholds = thresholds,
  latent_residual_variance = 1, source_group_counts = groups,
  random_dimension = sum(unlist(groups)), counts = as.list(table(data$y)),
  interpretation = "Synthetic six-source ordinal-probit law with independent conditional replicates; not a native-data model or coverage study."), "generator.json")
design <- gt_design("item", c("evaluator", "prompt", "temperature", "seed"),
                    random = names(source_variance))
control <- gt_control(discrete = list(engine = "sparse", optimizer = optimizer,
  max_observations = 21600L, max_random_dimension = 819L, check_hessian = TRUE))
family <- gt_family("ordinal", "probit", levels = levels(data$y))
preflight <- capture(gt_preflight(data, "y", design, family, control = control))
saveRDS(preflight, file.path(output, "preflight.rds"))
if (length(args) == 4L) {
  write_json(list(scope = "preflight_only_no_fit", error = preflight$error,
    preflight = if (!is.null(preflight$value)) preflight$value[c("fitting_feasible",
      "checks", "sources", "resources")] else NULL), "preflight.json")
  quit(save = "no", status = if (is.null(preflight$error)) 0L else 1L)
}
attempt <- capture(gt_fit(data, "y", design, family, control = control))
saveRDS(attempt, file.path(output, "attempt.rds"))
fit <- attempt$value
write_json(list(status = if (is.null(fit)) "refused" else
    if (isTRUE(fit$numerically_accepted)) "accepted" else "rejected",
  error = attempt$error, warnings = attempt$warnings,
  elapsed_seconds = unname(attempt$timing[["elapsed"]]),
  optimizer = optimizer, declared_control = unclass(control),
  engine = if (!is.null(fit)) fit$engine else NULL,
  accepted = if (!is.null(fit)) fit$numerically_accepted else FALSE,
  diagnostics = if (!is.null(fit)) fit$diagnostics else NULL,
  variances = if (!is.null(fit)) lapply(gt_components(fit), unname) else NULL,
  latent_reliability = if (!is.null(fit) && isTRUE(fit$numerically_accepted))
    as.data.frame(gt_reliability(fit, scale = "latent")) else NULL,
  same_objective_external_comparison = "pending",
  scope = "One fixed synthetic dataset; numerical acceptance is not parameter recovery, interval coverage, or Laplace accuracy."), "summary.json")
capture.output(sessionInfo(), file = file.path(output, "sessionInfo.txt"))
