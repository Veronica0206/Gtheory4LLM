# Run from the repository root. All generated observations are synthetic.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 1L) stop("Supply at most one output directory.")
destination <- if (length(args)) args[[1L]] else "validation-studies/discrete-laplace"
outputs <- c("scenarios.csv", "results.csv", "summary.csv", "generated-data.csv",
             "source-hashes.csv", "metadata.txt")
if (any(file.exists(file.path(destination, outputs))))
  stop("Study output already exists; supply a new output directory to preserve earlier runs.")
dir.create(destination, recursive = TRUE, showWarnings = FALSE)
stopifnot(file.exists("R/discrete.R"), file.exists("R/discrete_response.R"),
          file.exists("R/design.R"))
engine <- new.env(parent = globalenv())
sys.source("R/design.R", engine)
sys.source("R/discrete_response.R", engine)
sys.source("R/discrete.R", engine)
RNGkind("Mersenne-Twister", "Inversion", "Rejection")

write_table <- function(x, filename) {
  write.csv(x, file.path(destination, filename), row.names = FALSE, na = "")
}
capture_attempt <- function(expr) {
  warnings <- character()
  error <- ""
  value <- tryCatch(withCallingHandlers(force(expr), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }), error = function(e) { error <<- conditionMessage(e); NULL })
  list(value = value, error = error, warnings = paste(unique(warnings), collapse = " | "))
}

# Standalone probability calculations, independent of the engine's kernels.
probabilities <- function(random, scenario) {
  if (scenario$family == "categorical") {
    eta <- sweep(as.matrix(random), 2L, if (scenario$pattern == "balanced")
      c(0, 0) else c(-1.5, -2.3), "+")
    logits <- cbind(0, eta)
    shifted <- exp(logits - apply(logits, 1L, max))
    return(shifted / rowSums(shifted))
  }
  cdf <- if (scenario$link == "logit") stats::plogis else stats::pnorm
  if (scenario$family == "binary") {
    eta <- as.numeric(random) + if (scenario$pattern == "balanced") 0 else -2.2
    return(cbind(cdf(eta, lower.tail = FALSE), cdf(eta)))
  }
  cuts <- if (scenario$pattern == "balanced") c(-0.6, 0.6) else c(1.2, 1.8)
  lower <- cuts[[1L]] - as.numeric(random)
  upper <- cuts[[2L]] - as.numeric(random)
  # The upper-tail difference avoids subtracting two values close to one.
  middle <- ifelse(lower > 0, cdf(lower, lower.tail = FALSE) -
    cdf(upper, lower.tail = FALSE), cdf(upper) - cdf(lower))
  cbind(cdf(lower), pmax(0, middle), cdf(upper, lower.tail = FALSE))
}

conditional_loglik <- function(random, counts, scenario) {
  p <- probabilities(random, scenario)
  occupied <- counts > 0
  as.vector(log(p[, occupied, drop = FALSE]) %*% counts[occupied])
}

quadrature_cache <- new.env(parent = emptyenv())
normal_quadrature <- function(order) {
  key <- as.character(order)
  if (exists(key, quadrature_cache, inherits = FALSE)) return(quadrature_cache[[key]])
  jacobi <- matrix(0, order, order)
  off <- sqrt(seq_len(order - 1L))
  jacobi[cbind(seq_len(order - 1L), 2:order)] <- off
  jacobi[cbind(2:order, seq_len(order - 1L))] <- off
  decomposition <- eigen(jacobi, symmetric = TRUE)
  answer <- list(nodes = decomposition$values,
    weights = decomposition$vectors[1L, ]^2)
  stopifnot(abs(sum(answer$weights) - 1) < 1e-12,
    abs(sum(answer$weights * answer$nodes^2) - 1) < 1e-10)
  quadrature_cache[[key]] <- answer
  answer
}

reference_nll <- function(counts, scenario) {
  if (scenario$variance == 0) {
    zero <- if (scenario$family == "categorical") matrix(c(0, 0), 1L) else 0
    value <- -sum(vapply(counts, function(x)
      conditional_loglik(zero, x, scenario), numeric(1)))
    return(list(coarse = value, fine = value, difference = 0, converged = TRUE,
      method = "exact_zero_variance", refinement = "exact", error_estimate = 0))
  }
  if (scenario$family != "categorical") {
    integrate_at <- function(tolerance) {
      pieces <- lapply(counts, function(x) {
        integrand <- function(u) exp(conditional_loglik(u, x, scenario) +
          dnorm(u, sd = sqrt(scenario$variance), log = TRUE))
        integrate(integrand, -Inf, Inf, rel.tol = tolerance,
          abs.tol = tolerance * 1e-4, subdivisions = 1000L, stop.on.error = TRUE)
      })
      values <- vapply(pieces, `[[`, numeric(1), "value")
      if (any(!is.finite(values) | values <= 0) ||
          any(vapply(pieces, `[[`, character(1), "message") != "OK"))
        stop("Adaptive integration returned an unusable integral.")
      list(nll = -sum(log(values)), relative_error_estimate =
        sum(vapply(pieces, `[[`, numeric(1), "abs.error") / values))
    }
    first <- integrate_at(1e-8)
    last <- integrate_at(1e-11)
    delta <- abs(first$nll - last$nll)
    return(list(coarse = first$nll, fine = last$nll, difference = delta,
      converged = delta <= 1e-7, method = "adaptive_1d",
      refinement = "relative_1e-8_vs_1e-11", error_estimate = last$relative_error_estimate))
  }
  covariance <- scenario$variance * matrix(c(1, .3, .3, 1), 2L)
  factor <- chol(covariance)
  integrate_order <- function(order) {
    rule <- normal_quadrature(order)
    coordinates <- as.matrix(expand.grid(rule$nodes, rule$nodes))
    log_weights <- as.vector(outer(log(rule$weights), log(rule$weights), "+"))
    random <- coordinates %*% factor
    -sum(vapply(counts, function(x) {
      log_terms <- conditional_loglik(random, x, scenario) + log_weights
      center <- max(log_terms)
      center + log(sum(exp(log_terms - center)))
    }, numeric(1)))
  }
  previous <- integrate_order(41L)
  delta <- Inf
  for (order in c(81L, 161L, 321L, 481L)) {
    current <- integrate_order(order)
    delta <- abs(current - previous)
    if (order >= 161L && delta <= 1e-7) break
    if (order < 481L) previous <- current
  }
  list(coarse = previous, fine = current, difference = delta,
    converged = is.finite(delta) && delta <= 1e-7, method = "tensor_normal_quadrature_2d",
    refinement = paste0("latest_order_", order), error_estimate = NA_real_)
}

specifications <- data.frame(family = c("binary", "binary", "ordinal", "ordinal", "categorical"),
  link = c("logit", "probit", "logit", "probit", "softmax"))
grid <- expand.grid(specification = seq_len(nrow(specifications)), observations_per_item = c(3L, 12L),
  variance = c(0, .1, 2), pattern = c("balanced", "rare"), stringsAsFactors = FALSE)
scenarios <- cbind(scenario = seq_len(nrow(grid)), specifications[grid$specification, ],
  grid[, setdiff(names(grid), "specification")], items = 6L,
  replicates = 3L)
rownames(scenarios) <- NULL
write_table(scenarios, "scenarios.csv")

source_files <- c("R/design.R", "R/discrete_response.R", "R/discrete.R", "DESCRIPTION",
  "validation-studies/discrete-laplace/run.R", "validation-studies/discrete-laplace/PROTOCOL.md")
write_table(data.frame(file = source_files, md5 = unname(tools::md5sum(source_files))), "source-hashes.csv")
source_commit <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
source_changes <- system2("git", c("status", "--porcelain", "--", "R", "DESCRIPTION"), stdout = TRUE)
started <- proc.time()[["elapsed"]]
started_utc <- format(Sys.time(), tz = "UTC", usetz = TRUE)
records <- vector("list", nrow(scenarios) * 3L)
generated <- list()
position <- 0L
for (index in seq_len(nrow(scenarios))) for (replicate in seq_len(3L)) {
  position <- position + 1L
  scenario <- scenarios[index, ]
  seed <- 30100L + 100L * index + replicate
  row <- data.frame(scenario, replicate = replicate, seed = seed,
    status = "budget_not_started", category_counts = "", n_observations =
      scenario$items * scenario$observations_per_item,
    laplace_nll = NA_real_, engine_valid = FALSE, inner_converged = FALSE,
    inner_gradient = NA_real_, inner_iterations = NA_integer_,
    reference_nll_coarse = NA_real_, reference_nll = NA_real_,
    reference_difference = NA_real_, reference_converged = FALSE,
    reference_method = "", reference_refinement = "", reference_error_estimate = NA_real_,
    signed_nll_error = NA_real_, absolute_nll_error = NA_real_,
    signed_error_per_observation = NA_real_, engine_error = "", engine_warnings = "",
    reference_error = "", reference_warnings = "", elapsed_seconds = 0,
    stringsAsFactors = FALSE)
  if (proc.time()[["elapsed"]] - started > 240) {
    records[[position]] <- row
    next
  }
  panel_started <- proc.time()[["elapsed"]]
  set.seed(seed)
  n_categories <- if (scenario$family == "binary") 2L else 3L
  q <- if (scenario$family == "categorical") 2L else 1L
  covariance <- if (q == 2L) scenario$variance * matrix(c(1, .3, .3, 1), 2L) else
    matrix(scenario$variance)
  # Fixed standard-normal draws are retained even at variance zero.
  standard <- matrix(rnorm(scenario$items * q), scenario$items, q)
  random <- if (scenario$variance == 0) standard * 0 else standard %*% chol(covariance)
  panel <- expand.grid(occasion = seq_len(scenario$observations_per_item), item = seq_len(scenario$items))
  p <- probabilities(random[panel$item, , drop = FALSE], scenario)
  uniforms <- runif(nrow(panel))
  y <- vapply(seq_len(nrow(panel)), function(k) which(uniforms[[k]] <= cumsum(p[k, ]))[[1L]], integer(1))
  generated[[length(generated) + 1L]] <- data.frame(scenario = index, replicate = replicate,
    seed = seed, panel, response_category = y)
  counts <- lapply(seq_len(scenario$items), function(item) tabulate(y[panel$item == item], nbins = n_categories))
  row$category_counts <- paste(tabulate(y, nbins = n_categories), collapse = ":")
  if (scenario$family == "binary") {
    panel$response <- y - 1L
    spec <- list(family = "binary", link = scenario$link, levels = c("0", "1"))
    parameters <- if (scenario$pattern == "balanced") 0 else -2.2
  } else {
    lev <- c("first", "second", "third")
    panel$response <- factor(lev[y], levels = lev, ordered = scenario$family == "ordinal")
    spec <- list(family = scenario$family, link = scenario$link, levels = lev, reference = "first")
    if (scenario$family == "ordinal") {
      cuts <- if (scenario$pattern == "balanced") c(-.6, .6) else c(1.2, 1.8)
      parameters <- c(cuts[[1L]], log(diff(cuts)))
    } else parameters <- if (scenario$pattern == "balanced") c(0, 0) else c(-1.5, -2.3)
  }
  evaluation <- capture_attempt({
    prep <- engine$.gt_d_prepare(panel, "response", list(spec))
    groups <- list(item = engine$.gt_d_group(panel, "item"))
    control <- engine$.gt_d_control(list(inner_tol = 1e-9, inner_maxit = 100L,
      fixed_covariance = list(item = covariance)))
    setup <- engine$.gt_d_covariance_setup(groups, prep$q,
      if (q == 1L) "diagonal" else "unstructured", control, prep$dimensions)
    engine$.gt_d_laplace(parameters, prep, groups, setup, control, details = TRUE)
  })
  row$engine_error <- evaluation$error
  row$engine_warnings <- evaluation$warnings
  if (!is.null(evaluation$value)) {
    detail <- evaluation$value
    row$engine_valid <- isTRUE(detail$valid)
    row$inner_converged <- isTRUE(detail$inner_converged)
    if (!is.null(detail$inner_gradient)) row$inner_gradient <- detail$inner_gradient
    if (!is.null(detail$inner_iterations)) row$inner_iterations <- detail$inner_iterations
    if (isTRUE(detail$valid)) row$laplace_nll <- detail$nll
  }
  reference <- capture_attempt(reference_nll(counts, scenario))
  row$reference_error <- reference$error
  row$reference_warnings <- reference$warnings
  if (!is.null(reference$value)) {
    ref <- reference$value
    row$reference_nll_coarse <- ref$coarse
    row$reference_nll <- ref$fine
    row$reference_difference <- ref$difference
    row$reference_converged <- ref$converged
    row$reference_method <- ref$method
    row$reference_refinement <- ref$refinement
    row$reference_error_estimate <- ref$error_estimate
  }
  row$status <- if (!row$reference_converged) "reference_unavailable_or_unstable" else
    if (!row$engine_valid) "engine_unavailable" else "compared"
  if (row$status == "compared") {
    row$signed_nll_error <- row$laplace_nll - row$reference_nll
    row$absolute_nll_error <- abs(row$signed_nll_error)
    row$signed_error_per_observation <- row$signed_nll_error / row$n_observations
  }
  row$elapsed_seconds <- proc.time()[["elapsed"]] - panel_started
  records[[position]] <- row
  # Checkpoint each completed scenario to retain earlier evidence on interruption.
  if (replicate == 3L) {
    write_table(do.call(rbind, records[seq_len(position)]), "results.csv")
    cat(sprintf("Completed %d/%d panels (%.1f seconds).\n", position, length(records),
      proc.time()[["elapsed"]] - started))
  }
}
results <- do.call(rbind, records)
write_table(results, "results.csv")
if (length(generated)) write_table(do.call(rbind, generated), "generated-data.csv")
summaries <- lapply(seq_len(nrow(scenarios)), function(index) {
  x <- results[results$scenario == index, ]
  usable <- x$status == "compared"
  values <- x$signed_nll_error[usable]
  data.frame(scenarios[index, ], planned = nrow(x), started = sum(x$status != "budget_not_started"),
    compared = sum(usable), engine_unavailable = sum(x$status == "engine_unavailable"),
    reference_unavailable_or_unstable = sum(x$status == "reference_unavailable_or_unstable"),
    mean_signed_nll_error = if (length(values)) mean(values) else NA_real_,
    mean_absolute_nll_error = if (length(values)) mean(abs(values)) else NA_real_,
    maximum_absolute_nll_error = if (length(values)) max(abs(values)) else NA_real_,
    maximum_absolute_error_per_observation = if (length(values))
      max(abs(x$signed_error_per_observation[usable])) else NA_real_)
})
write_table(do.call(rbind, summaries), "summary.csv")
metadata <- c(paste("Study started UTC:", started_utc),
  paste("Source commit:", source_commit),
  paste("Source R/DESCRIPTION working-tree changes:", if (length(source_changes))
    paste(source_changes, collapse = " | ") else "none"),
  paste("R:", R.version.string), paste("Platform:", R.version$platform),
  paste("RNG:", paste(RNGkind(), collapse = "; ")),
  "Package dependencies for this study: base R only; package source loaded explicitly.",
  "Engine controls: inner_tol=1e-9; inner_maxit=100; fixed generating covariance.",
  "Reference convergence threshold: successive NLL difference <= 1e-7.",
  "Planned panels: 180; elapsed budget seconds: 240 (checked between panels).",
  paste("Started panels:", sum(results$status != "budget_not_started")),
  paste("Compared panels:", sum(results$status == "compared")),
  paste("Elapsed seconds:", format(proc.time()[["elapsed"]] - started, digits = 8)))
writeLines(metadata, file.path(destination, "metadata.txt"))
cat(paste(metadata, collapse = "\n"), "\n")
