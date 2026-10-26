# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.

# Object-cluster bootstrap of an accepted fit.
#
# Each replicate resamples the objects of measurement with replacement. A
# drawn object keeps every one of its rows, so its complete instrumentation
# panel travels with it, and an object drawn more than once enters as that
# many distinct objects. The resample is refitted with the fit's own design,
# families, estimator, covariance structures and controls, and the refit must
# pass the same numerical acceptance as any fit. Refused and failed refits are
# recorded and never stand in for accepted ones; resampling continues until
# the requested number of accepted refits or the attempt budget is reached.
#
# Every object must share one instrumentation layout: the same facet-level
# combinations, as often, with the same outcomes observed. In an incomplete
# panel a level confined to some objects is lost from every resample that omits
# them, and that is a different procedure, so such a fit is refused.
#
# The facet levels are the observed ones in every replicate, so the intervals
# describe object sampling conditional on the instrumentation panel. They do
# not reflect that the evaluators, prompts or other facet levels were
# themselves a sample. No resampling scheme reproduces the sampling of a
# crossed random design exactly (McCullagh, 2000); resampling the object facet
# is the boot-p procedure of Brennan (2001).
#
# Every attempt draws from its own seed, taken from one stream fixed by
# `seed`, so a replicate does not depend on the number of cores, on how
# attempts are batched, or on the attempt budget. The leave-one-object-out
# refits for BCa acceleration take their retry seeds from the same stream. An
# explicit Gaussian retry seed in the controls governs every refit's restarts
# instead, as it does in gt_fit(); the record shows the seed a refit used.

# Fewer finite replicate estimates than this leave an interval unavailable.
.GT_BOOTSTRAP_MINIMUM <- 50L

gt_bootstrap <- function(fit, replicates = 1000L, seed, max_attempts = 2L * replicates,
                         jackknife = FALSE, warm_start = TRUE, cores = 1L,
                         data = NULL, control = NULL) {
  .gt_require_fit(fit)
  if (!.gt_fit_usable(fit))
    stop("A bootstrap requires a numerically accepted fit. Inspect gt_diagnostics(fit) first.", call. = FALSE)
  if (!is.null(fit$design$batch))
    stop("Declared batches tie items to shared calls; resampling items would break that layout, ",
         "so this fit cannot be bootstrapped by object.", call. = FALSE)
  count <- function(x, name, minimum) {
    if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || x != floor(x) || x < minimum ||
        x > .Machine$integer.max)
      stop(name, " must be one whole number of at least ", minimum, ".", call. = FALSE)
    as.integer(x)
  }
  replicates <- count(replicates, "replicates", 1L)
  max_attempts <- count(max_attempts, "max_attempts", replicates)
  cores <- count(cores, "cores", 1L)
  if (missing(seed)) stop("seed is required, so the replicates can be reproduced.", call. = FALSE)
  seed <- .gt_sim_integer(seed, "seed", 0L)
  for (name in c("jackknife", "warm_start")) {
    value <- get(name)
    if (!is.logical(value) || length(value) != 1L || is.na(value))
      stop(name, " must be TRUE or FALSE.", call. = FALSE)
  }
  if (cores > 1L && identical(.Platform$OS.type, "windows"))
    stop("cores > 1 uses forked processes, which Windows does not provide; use cores = 1.", call. = FALSE)
  if (is.null(control)) control <- fit$control
  if (!inherits(control, "gt_control")) stop("control must be created by gt_control().", call. = FALSE)
  data <- .gt_bootstrap_data(fit, data)
  object <- fit$design$object
  labels <- unique(data[[object]])
  rows_by_object <- split(seq_len(nrow(data)), factor(match(data[[object]], labels), levels = seq_along(labels)))
  if (!.gt_bootstrap_common_layout(data, fit$design$facets, fit$outcomes, rows_by_object))
    stop("The objects do not share one instrumentation layout (the same facet-level combinations, ",
         "as often, with the same outcomes observed). A resample of this incomplete panel could lose ",
         "a facet level confined to the objects it omits, so it cannot be bootstrapped by object.", call. = FALSE)
  n <- length(labels)
  # The leave-one-out retry seeds come first, then one resampling seed and one
  # retry seed per attempt; the stream's prefix does not depend on its length.
  seeds <- .gt_sim_rng(seed, sample.int(.Machine$integer.max, n + 2L * max_attempts))
  # The retry seed a refit uses: an explicit Gaussian one in the controls, or
  # else the stream's. The lme4 route refuses the setting.
  explicit <- if (.gt_is_gaussian(fit)) control$gaussian$retry_seed
  retry_of <- function(drawn) if (is.null(explicit)) drawn else as.integer(explicit)
  refit <- function(draw, retry_seed) .gt_bootstrap_refit(fit,
    .gt_bootstrap_sample(data, object, rows_by_object, draw), control, retry_seed, warm_start)
  attempt <- function(k) {
    draw <- .gt_sim_rng(seeds[[n + 2L * k - 1L]], sample.int(n, n, replace = TRUE))
    used <- retry_of(seeds[[n + 2L * k]])
    c(list(attempt = k, seed = seeds[[n + 2L * k - 1L]], retry_seed = used), refit(draw, used))
  }
  done <- list()
  accepted <- 0L
  next_attempt <- 1L
  while (accepted < replicates && next_attempt <= max_attempts) {
    batch <- seq.int(next_attempt, min(max_attempts, next_attempt + max(replicates - accepted, cores) - 1L))
    done <- c(done, .gt_bootstrap_map(batch, attempt, cores))
    accepted <- sum(vapply(done, function(x) identical(x$status, "accepted"), logical(1)))
    next_attempt <- max(batch) + 1L
  }
  # Only the attempts up to the last accepted replicate that is used are kept,
  # so parallel surplus never changes the result or its record.
  status <- vapply(done, `[[`, character(1), "status")
  used <- which(status == "accepted")[seq_len(min(accepted, replicates))]
  cutoff <- if (length(used) == replicates) max(used) else length(done)
  done <- done[seq_len(cutoff)]
  kept <- done[vapply(done, function(x) identical(x$status, "accepted"), logical(1))]
  leave_one_out <- if (jackknife) {
    out <- .gt_bootstrap_map(seq_len(n), function(i) {
      used <- retry_of(seeds[[i]])
      c(list(attempt = i, seed = NA_integer_, retry_seed = used), refit(setdiff(seq_len(n), i), used))
    }, cores)
    list(components = lapply(out, function(x) if (identical(x$status, "accepted")) x$components),
         records = .gt_bootstrap_records(out, labels),
         complete = all(vapply(out, function(x) identical(x$status, "accepted"), logical(1))))
  }
  records <- .gt_bootstrap_records(done)
  structure(list(unit = object, objects = n, replicates = replicates,
    accepted = length(kept), attempts = length(done),
    components = lapply(kept, `[[`, "components"), records = records,
    jackknife = leave_one_out,
    original = list(outcomes = fit$outcomes, components = fit$covariance_components,
                    minus2loglik = fit$minus2loglik, estimator = fit$estimator),
    settings = list(seed = seed, max_attempts = max_attempts, warm_start = warm_start, cores = cores),
    interpretation = paste("Object bootstrap: objects resampled with replacement, each with its",
      "complete instrumentation panel, every resample refitted under the fit's specification",
      "and acceptance rule. Intervals describe object sampling conditional on the observed",
      "instrumentation levels and on numerical acceptance; they do not reflect sampling of",
      "the facet levels.")), class = "gt_bootstrap")
}

# The modelled data: the fit's own, or a supplied copy that must describe the
# same panel.
.gt_bootstrap_data <- function(fit, data) {
  if (is.null(data)) {
    if (!is.data.frame(fit$data))
      stop("This fit was stored without its data (retain = list(data = FALSE)); supply data =, ",
           "the data frame it was fitted to.", call. = FALSE)
    return(.gt_bootstrap_labels(fit, fit$data))
  }
  columns <- c(fit$design$object, fit$design$facets, fit$outcomes)
  if (!is.data.frame(data) || !all(columns %in% names(data)))
    stop("data must be a data frame with the fit's object, facet and outcome columns.", call. = FALSE)
  panel <- .gt_panel_summary(data[columns], fit$design)
  recorded <- fit$panel
  if (!is.list(recorded) || !identical(as.integer(panel$counts), as.integer(recorded$counts)) ||
      !identical(panel$rows, recorded$rows) || !identical(panel$observed_cells, recorded$observed_cells))
    stop("data does not describe the panel this fit was made from.", call. = FALSE)
  data[columns]
}

# Whether every object carries the same multiset of facet-level combinations,
# each with the same outcomes observed.
.gt_bootstrap_common_layout <- function(data, facets, outcomes, rows_by_object) {
  cells <- do.call(paste, c(list(.gt_tuple_key(data, facets)),
                            lapply(data[outcomes], function(x) as.integer(is.na(x))), list(sep = "|")))
  layouts <- vapply(rows_by_object, function(rows) paste(sort(cells[rows]), collapse = "\n"), character(1))
  length(unique(layouts)) == 1L
}

# The retained frame holds each binary outcome as its 0/1 code over the
# recorded levels. Refits go through gt_fit(), which reads numeric binary input
# as the labels "0" and "1", so codes over any other labels are returned to
# those labels, in the recorded order; the second level stays the coded 1.
.gt_bootstrap_labels <- function(fit, data) {
  for (outcome in fit$outcomes) {
    spec <- fit$families[[outcome]]
    x <- data[[outcome]]
    if (identical(spec$family, "binary") && !identical(spec$levels, c("0", "1")) &&
        is.numeric(x) && all(x %in% c(0, 1)))
      data[[outcome]] <- factor(spec$levels[x + 1L], levels = spec$levels)
  }
  data
}

# One resample: the drawn objects' rows, each draw a distinct object.
.gt_bootstrap_sample <- function(data, object, rows_by_object, draw) {
  pieces <- rows_by_object[draw]
  sample <- data[unlist(pieces, use.names = FALSE), , drop = FALSE]
  rownames(sample) <- NULL
  sample[[object]] <- factor(rep(seq_along(draw), lengths(pieces)), levels = seq_along(draw))
  sample
}

# Refit one resample with the fit's specification; keep only what the
# intervals need and what the record reports.
.gt_bootstrap_refit <- function(fit, sample, control, retry_seed, warm_start) {
  gaussian <- .gt_is_gaussian(fit)
  # Observed information plays no part in acceptance, and a replicate needs
  # only its estimates. The lme4 route takes neither setting.
  if (gaussian) {
    if (!identical(control$gaussian$engine, "lme4")) {
      if (is.null(control$gaussian$retry_seed)) control$gaussian$retry_seed <- retry_seed
      control$gaussian$check_hessian <- FALSE
    }
    covariance <- fit$covariance_types[fit$design$terms]
    residual <- unname(fit$covariance_types[["Residual"]])
  } else {
    # The original estimates are the primary start; the alternative starts
    # and every acceptance check still apply.
    if (warm_start) control$discrete$start <- .gt_bootstrap_start(fit)
    control$discrete$check_hessian <- FALSE
    covariance <- fit$covariance
    residual <- NULL
  }
  warnings <- 0L
  started <- proc.time()[["elapsed"]]
  refit <- tryCatch(withCallingHandlers(
    .gt_sim_rng(retry_seed, gt_fit(sample, fit$outcomes, fit$design, family = fit$families,
      estimator = fit$estimator, covariance = covariance, residual = residual, control = control)),
    warning = function(w) {
      warnings <<- warnings + 1L
      invokeRestart("muffleWarning")
    }), error = identity)
  seconds <- proc.time()[["elapsed"]] - started
  if (inherits(refit, "error"))
    return(list(status = "error", reason = conditionMessage(refit), seconds = seconds,
                warnings = warnings, deviance = NA_real_, boundary_sources = NA_character_))
  boundary <- .gt_fit_status(refit)$boundary_sources
  record <- list(seconds = seconds, warnings = warnings,
    deviance = if (is.numeric(refit$minus2loglik)) refit$minus2loglik else NA_real_,
    boundary_sources = paste(boundary, collapse = "; "))
  if (!.gt_fit_usable(refit)) {
    failures <- .gt_fit_status(refit)$acceptance_failures
    return(c(list(status = "refused", reason = if (length(failures)) paste(failures, collapse = "; ") else
      "The refit was not numerically accepted."), record))
  }
  c(list(status = "accepted", reason = NA_character_, components = refit$covariance_components), record)
}

# A discrete warm start: the original estimates, except that a source on its
# covariance boundary starts from the original fit's starting values. Started
# on an exact zero factor column, the analytic route could not leave it.
.gt_bootstrap_start <- function(fit) {
  start <- fit$parameters
  initial <- fit$starting_parameters
  boundary <- fit$diagnostics$boundary_sources
  if (!length(boundary) || !identical(names(initial), names(start))) return(start)
  nuisance <- Reduce(`|`, lapply(fit$outcomes, function(o) startsWith(names(start), paste0(o, "::"))),
                     logical(length(start)))
  held <- !nuisance & Reduce(`|`, lapply(boundary, function(s) startsWith(names(start), paste0(s, "::"))),
                             logical(length(start)))
  start[held] <- initial[held]
  start
}

# Serial or forked evaluation. A worker that dies is an error record, never a
# silently missing replicate.
.gt_bootstrap_map <- function(ids, worker, cores) {
  if (cores == 1L || length(ids) == 1L) return(lapply(ids, worker))
  out <- parallel::mclapply(ids, worker, mc.cores = cores, mc.preschedule = FALSE, mc.set.seed = FALSE)
  lapply(seq_along(ids), function(j) {
    x <- out[[j]]
    if (is.list(x) && !is.null(x$status)) return(x)
    list(attempt = ids[[j]], seed = NA_integer_, retry_seed = NA_integer_, status = "error",
         reason = paste("The worker process failed:",
                        if (inherits(x, "try-error")) trimws(as.character(x)) else "no result returned"),
         seconds = NA_real_, warnings = NA_integer_, deviance = NA_real_, boundary_sources = NA_character_)
  })
}

.gt_bootstrap_records <- function(out, labels = NULL) {
  field <- function(name, missing, convert) vapply(out, function(x)
    if (length(x[[name]]) == 1L) convert(x[[name]]) else missing, missing)
  records <- data.frame(attempt = field("attempt", NA_integer_, as.integer),
    seed = field("seed", NA_integer_, as.integer), retry_seed = field("retry_seed", NA_integer_, as.integer),
    status = field("status", NA_character_, as.character), reason = field("reason", NA_character_, as.character),
    seconds = field("seconds", NA_real_, as.numeric), warnings = field("warnings", NA_integer_, as.integer),
    deviance = field("deviance", NA_real_, as.numeric),
    boundary_sources = field("boundary_sources", NA_character_, as.character), stringsAsFactors = FALSE)
  if (!is.null(labels)) {
    names(records)[1L] <- "left_out"
    records$left_out <- as.character(labels)
    records$seed <- NULL
  }
  records
}

print.gt_bootstrap <- function(x, ...) {
  status <- table(factor(x$records$status, levels = c("accepted", "refused", "error")))
  cat("Object bootstrap of", x$objects, paste0(x$unit, "s"), "|", x$accepted, "accepted of",
      x$replicates, "requested |", x$attempts, "attempts\n")
  cat("Attempts:", paste(names(status), status, sep = " ", collapse = ", "), "\n")
  if (!is.null(x$jackknife))
    cat("Leave-one-out refits:", sum(x$jackknife$records$status == "accepted"), "of", x$objects,
        "accepted;", if (isTRUE(x$jackknife$complete)) "BCa acceleration available." else
          "BCa acceleration unavailable.", "\n")
  if (x$accepted < .GT_BOOTSTRAP_MINIMUM)
    cat("Fewer than", .GT_BOOTSTRAP_MINIMUM, "accepted replicates: no interval is available.\n")
  cat("Instrumentation levels are held at those observed; see $interpretation.\n")
  invisible(x)
}

as.data.frame.gt_bootstrap <- function(x, row.names = NULL, optional = FALSE, ...) {
  if (!inherits(x, "gt_bootstrap")) stop("Expected a gt_bootstrap object.", call. = FALSE)
  records <- x$records
  if (!is.null(row.names)) rownames(records) <- row.names
  records
}

# Percentile intervals by default, BCa on request, for every unique entry of
# every source covariance matrix.
summary.gt_bootstrap <- function(object, level = 0.95, interval_type = c("percentile", "bca"), ...) {
  if (!inherits(object, "gt_bootstrap")) stop("Expected a gt_bootstrap object.", call. = FALSE)
  .gt_check_level(level)
  interval <- match.arg(interval_type)
  original <- object$original$components
  rows <- do.call(rbind, lapply(names(original), function(source) {
    M <- original[[source]]
    cells <- which(lower.tri(M, diag = TRUE), arr.ind = TRUE)
    labels <- if (is.null(rownames(M))) as.character(seq_len(nrow(M))) else rownames(M)
    do.call(rbind, lapply(seq_len(nrow(cells)), function(r) {
      i <- cells[r, 1L]
      j <- cells[r, 2L]
      entry <- function(components) {
        value <- components[[source]]
        if (is.matrix(value) && all(dim(value) >= c(i, j))) value[i, j] else NA_real_
      }
      values <- vapply(object$components, entry, numeric(1))
      jack <- if (!is.null(object$jackknife)) vapply(object$jackknife$components, function(x)
        if (is.null(x)) NA_real_ else entry(x), numeric(1))
      bounds <- .gt_bootstrap_interval(M[i, j], values, jack, level, interval)
      data.frame(source = source, row = labels[[i]], column = labels[[j]], estimate = M[i, j],
                 std_error = bounds[["se"]], lower = bounds[["lower"]], upper = bounds[["upper"]],
                 finite = as.integer(bounds[["finite"]]), stringsAsFactors = FALSE)
    }))
  }))
  rownames(rows) <- NULL
  attr(rows, "interval") <- interval
  attr(rows, "level") <- level
  attr(rows, "interpretation") <- object$interpretation
  rows
}

# Bootstrap standard error and percentile or BCa interval of one statistic.
# The interval needs a finite original estimate and at least
# .GT_BOOTSTRAP_MINIMUM finite replicates; BCa also needs every
# leave-one-out estimate. An endpoint whose percentile falls outside
# [1 / (B + 1), B / (B + 1)] has no replicate support and is unavailable.
.gt_bootstrap_interval <- function(original, values, jackknife = NULL, level, interval) {
  finite <- values[is.finite(values)]
  B <- length(finite)
  unavailable <- c(se = NA_real_, lower = NA_real_, upper = NA_real_, finite = B)
  if (!is.finite(original) || B < .GT_BOOTSTRAP_MINIMUM) return(unavailable)
  se <- stats::sd(finite)
  alpha <- (1 - level) / 2
  probabilities <- c(alpha, 1 - alpha)
  if (identical(interval, "bca")) {
    if (is.null(jackknife) || !length(jackknife) || any(!is.finite(jackknife)))
      return(c(se = se, lower = NA_real_, upper = NA_real_, finite = B))
    share <- (sum(finite < original) + 0.5 * sum(finite == original)) / B
    if (share <= 0 || share >= 1) return(c(se = se, lower = NA_real_, upper = NA_real_, finite = B))
    z0 <- stats::qnorm(share)
    deviation <- mean(jackknife) - jackknife
    spread <- sum(deviation^2)
    acceleration <- if (spread > 0) sum(deviation^3) / (6 * spread^1.5) else 0
    z <- stats::qnorm(probabilities)
    denominator <- 1 - acceleration * (z0 + z)
    if (any(denominator <= 0)) return(c(se = se, lower = NA_real_, upper = NA_real_, finite = B))
    probabilities <- stats::pnorm(z0 + (z0 + z) / denominator)
  }
  if (any(!is.finite(probabilities)) || any(probabilities < 1 / (B + 1)) || any(probabilities > B / (B + 1)))
    return(c(se = se, lower = NA_real_, upper = NA_real_, finite = B))
  bounds <- stats::quantile(finite, probabilities, type = 6, names = FALSE)
  c(se = se, lower = bounds[[1L]], upper = bounds[[2L]], finite = B)
}

# The interval type a coefficient call asked for.
.gt_interval_method <- function(bootstrap, interval) {
  if (is.null(interval)) return(if (is.null(bootstrap)) "wald" else "percentile")
  if (!is.character(interval) || length(interval) != 1L || is.na(interval) ||
      !interval %in% c("wald", "percentile", "bca"))
    stop("interval_type must be 'wald', 'percentile' or 'bca'.", call. = FALSE)
  if (identical(interval, "wald") && !is.null(bootstrap))
    stop("A bootstrap was supplied; request interval_type = 'percentile' or 'bca', or omit bootstrap.", call. = FALSE)
  if (!identical(interval, "wald") && is.null(bootstrap))
    stop("Percentile and BCa intervals need bootstrap = gt_bootstrap(fit, ...).", call. = FALSE)
  interval
}

# A bootstrap belongs to the fit whose estimates it recorded.
.gt_bootstrap_match <- function(fit, bootstrap) {
  if (!inherits(bootstrap, "gt_bootstrap")) stop("bootstrap must be created by gt_bootstrap().", call. = FALSE)
  if (!identical(bootstrap$original$outcomes, fit$outcomes) ||
      !identical(bootstrap$original$minus2loglik, fit$minus2loglik) ||
      !identical(bootstrap$original$components, fit$covariance_components))
    stop("This bootstrap was not made from this fit.", call. = FALSE)
  invisible(bootstrap)
}

.gt_bootstrap_uncertainty <- function(bootstrap, interval) {
  bca <- identical(interval, "bca")
  reason <- if (bootstrap$accepted < .GT_BOOTSTRAP_MINIMUM)
    paste0("Only ", bootstrap$accepted, " accepted bootstrap replicates; at least ",
           .GT_BOOTSTRAP_MINIMUM, " are needed.") else
    if (bca && is.null(bootstrap$jackknife))
      "BCa intervals need the leave-one-out refits; rerun gt_bootstrap() with jackknife = TRUE." else
    if (bca && !isTRUE(bootstrap$jackknife$complete))
      "BCa intervals need every leave-one-out refit accepted, and at least one was not." else NA_character_
  list(available = is.na(reason), reason = reason,
       method = paste0("object_bootstrap_", interval),
       boundary_components = character(), restricted_to_interior = FALSE,
       fixed_components = character(), fixed_component_kinds = character(),
       bootstrap = list(unit = bootstrap$unit, accepted = bootstrap$accepted,
                        attempts = bootstrap$attempts, requested = bootstrap$replicates),
       interpretation = bootstrap$interpretation)
}

# Replace the Wald standard errors and intervals of a coefficient table with
# the bootstrap's. Each replicate's coefficients come from the same kernel,
# with that replicate's source covariances and the fit's design and counts.
.gt_bootstrap_coefficients <- function(result, fit, context, counts, score, fixed, level,
                                       bootstrap, interval) {
  values_of <- function(components) {
    if (is.null(components)) return(NULL)
    replicate <- context
    if (!context$gaussian) components$Residual <- context$components$Residual
    replicate$components <- components
    replicate$uncertainty <- list(available = FALSE)
    tryCatch(.gt_reliability_kernel(fit, replicate, counts, score, fixed, level, values_only = TRUE),
             error = function(e) NULL)
  }
  replicates <- lapply(bootstrap$components, values_of)
  leave_one_out <- if (!is.null(bootstrap$jackknife)) lapply(bootstrap$jackknife$components, values_of)
  update <- function(table, part) {
    if (is.null(table)) return(table)
    for (coefficient in c("Erho2", "Phi")) for (r in seq_len(nrow(table))) {
      pick <- function(x) if (is.null(x) || is.null(x[[part]])) NA_real_ else x[[part]][[coefficient]][[r]]
      bounds <- .gt_bootstrap_interval(table[[coefficient]][[r]], vapply(replicates, pick, numeric(1)),
        if (!is.null(leave_one_out)) vapply(leave_one_out, pick, numeric(1)), level, interval)
      table[[paste0(coefficient, "_se")]][[r]] <- bounds[["se"]]
      table[[paste0(coefficient, "_lower")]][[r]] <- bounds[["lower"]]
      table[[paste0(coefficient, "_upper")]][[r]] <- bounds[["upper"]]
    }
    table
  }
  result$per_trait <- update(result$per_trait, "per_trait")
  result$composite <- update(result$composite, "composite")
  result
}
