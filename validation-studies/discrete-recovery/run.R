# Run from the repository root; the only generated data are synthetic.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L) stop("Supply at most one output directory.")
study <- "validation-studies/discrete-recovery"
out <- if (length(args)) args[[1L]] else file.path(study, "results")
if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE)))
  stop("Output directory must be empty; preserve earlier runs.")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
engine <- new.env(parent = globalenv())
source("load_functions.R", local = engine)
config <- read.csv(file.path(study, "config.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(config) == 4L, !anyDuplicated(config$scenario),
          all(config$variance > 0), all(config$replicates == 10L))
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
write_table <- function(x, name) write.csv(x, file.path(out, name), row.names = FALSE, na = "NA")
write_table(config, "config.csv")
files <- c("DESCRIPTION", "load_functions.R", sort(list.files("R", full.names = TRUE)),
           file.path(study, c("config.csv", "PROTOCOL.md", "run.R")))
write_table(data.frame(file = files, md5 = unname(tools::md5sum(files))), "source-files.csv")
metadata <- c(paste("Source commit:", system2("git", c("rev-parse", "HEAD"), stdout = TRUE)),
  paste("Started UTC:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  paste("R:", R.version.string), paste("Platform:", R.version$platform),
  paste("RNG:", paste(RNGkind(), collapse = ";")),
  "Source: explicit checkout; exact files identified by source-files.csv",
  "Fit budget: 180 cumulative seconds, checked between fits",
  "L-BFGS-B; maxit=150; default automatic starts and numerical acceptance checks")
writeLines(metadata, file.path(out, "metadata.txt"))
rows <- do.call(rbind, lapply(seq_len(10L), function(i) data.frame(
  scenario = config$scenario, replicate = i, seed = config$seed_base + i,
  status = "budget_not_started", optimizer_completed = FALSE, accepted = FALSE,
  variance_true = config$variance, intercept_true = config$intercept,
  reliability_true = config$variance / (config$variance + pi^2 / (3 * config$repetitions)),
  variance = NA_real_, intercept = NA_real_, reliability = NA_real_, boundary = NA,
  events = NA_integer_, observations = config$n_items * config$repetitions,
  fit_seconds = 0, approximation_adequacy = "", acceptance_failures = "",
  warnings = "", error = "")))
write_table(rows, "replicates.csv")
fit_seconds <- 0
sanitize <- function(x) {
  x <- gsub(normalizePath("."), "<repository>", paste(x, collapse = " | "), fixed = TRUE)
  x <- gsub(path.expand("~"), "<home>", x, fixed = TRUE)
  gsub("[\r\n]+", " ", x)
}
design <- engine$gt_design("item", "occasion", random = ~ item, full_cell = FALSE)
for (k in seq_len(nrow(rows))) {
  if (fit_seconds >= 180) break
  s <- config[match(rows$scenario[k], config$scenario), ]
  set.seed(rows$seed[k])
  d <- expand.grid(occasion = seq_len(s$repetitions), item = seq_len(s$n_items))
  u <- rnorm(s$n_items, sd = sqrt(s$variance))
  d$y <- rbinom(nrow(d), 1, plogis(s$intercept + u[d$item]))
  rows$events[k] <- sum(d$y)
  warnings <- character()
  started <- proc.time()[["elapsed"]]
  fit <- tryCatch(withCallingHandlers(engine$gt_fit(d, "y", design,
    engine$gt_family("binary", "logit"), covariance = "diagonal",
    control = engine$gt_control(discrete = list(maxit = 150L, optimizer = "L-BFGS-B"))),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w));
                            invokeRestart("muffleWarning") }), error = identity)
  rows$fit_seconds[k] <- proc.time()[["elapsed"]] - started
  fit_seconds <- fit_seconds + rows$fit_seconds[k]
  rows$warnings[k] <- sanitize(warnings)
  if (inherits(fit, "error")) {
    rows$status[k] <- "error"
    rows$error[k] <- sanitize(conditionMessage(fit))
  } else {
    rows$accepted[k] <- isTRUE(fit$numerically_accepted)
    rows$optimizer_completed[k] <- isTRUE(fit$optimizer_completed)
    rows$status[k] <- if (rows$accepted[k]) "accepted" else "rejected"
    rows$variance[k] <- fit$covariance_components$item[1, 1]
    rows$intercept[k] <- as.numeric(fit$means[[1L]])
    rows$boundary[k] <- length(fit$diagnostics$boundary_sources) > 0L
    rows$acceptance_failures[k] <- paste(fit$diagnostics$acceptance_failures, collapse = ";")
    rows$approximation_adequacy[k] <- fit$approximation_adequacy
    if (rows$accepted[k]) {
      rel <- tryCatch(engine$gt_reliability(fit, scale = "latent"), error = identity)
      if (inherits(rel, "error")) rows$error[k] <- sanitize(conditionMessage(rel)) else {
        stopifnot(abs(rel$per_trait$Erho2 - rel$per_trait$Phi) < 1e-12)
        rows$reliability[k] <- rel$per_trait$Erho2
      }
    }
  }
  write_table(rows, "replicates.csv")
}
summary <- do.call(rbind, lapply(config$scenario, function(s) {
  d <- rows[rows$scenario == s, ]
  do.call(rbind, lapply(c("variance", "intercept", "reliability"), function(metric) {
    keep <- d$accepted & is.finite(d[[metric]])
    values <- d[[metric]][keep]
    error <- values - d[[paste0(metric, "_true")]][keep]
    data.frame(scenario = s, metric = metric, planned = nrow(d),
      attempted = sum(d$status != "budget_not_started"), accepted = sum(d$accepted),
      rejected = sum(d$status == "rejected"), errors = sum(d$status == "error"),
      accepted_boundaries = sum(d$accepted & d$boundary, na.rm = TRUE), usable = sum(keep),
      mean_estimate = if (length(values)) mean(values) else NA_real_,
      bias = if (length(error)) mean(error) else NA_real_,
      rmse = if (length(error)) sqrt(mean(error^2)) else NA_real_,
      empirical_sd = if (length(values) > 1L) sd(values) else NA_real_,
      mean_mcse = if (length(values) > 1L) sd(values) / sqrt(length(values)) else NA_real_)
  }))
}))
write_table(summary, "summary.csv")
writeLines(c(metadata, paste("Finished UTC:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  paste("Cumulative fit seconds:", fit_seconds),
  paste("Attempted:", sum(rows$status != "budget_not_started")),
  paste("Accepted:", sum(rows$accepted))), file.path(out, "metadata.txt"))
print(summary, row.names = FALSE)
