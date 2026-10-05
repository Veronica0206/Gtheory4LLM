# Portable snapshots contain aggregate tables only, never a fitted object,
# recorded call, model, data, grouping labels, error log, or arbitrary control.
.gt_report_scalar <- function(x, type = "character") {
  if (length(x) != 1L || !is.atomic(x) || !is.null(dim(x)))
    return(switch(type, numeric = NA_real_, logical = NA, NA_character_))
  if (type == "numeric") return(if (is.numeric(x)) as.numeric(x) else NA_real_)
  if (type == "logical") return(if (is.logical(x)) as.logical(x) else NA)
  if (is.character(x)) as.character(x) else NA_character_
}

.gt_report_plain_table <- function(x, columns = names(x)) {
  if (is.null(x)) return(NULL)
  values <- lapply(x[intersect(columns, names(x))], function(value) {
    if (is.factor(value)) return(as.character(value))
    if (is.character(value)) return(as.character(value))
    if (is.logical(value)) return(as.logical(value))
    if (is.numeric(value)) return(as.numeric(value))
    stop("Report tables must contain only atomic scalar columns.", call. = FALSE)
  })
  as.data.frame(values, stringsAsFactors = FALSE, check.names = FALSE)
}

.gt_report_session <- function(session) {
  packages <- c("Gtheory4LLM", "OpenMx", "Matrix")
  versions <- vapply(packages, function(name) {
    record <- session$otherPkgs[[name]]
    if (is.null(record)) record <- session$loadedOnly[[name]]
    .gt_report_scalar(record$Version)
  }, character(1))
  list(available = is.list(session),
    R = .gt_report_scalar(session$R.version$version.string),
    platform = .gt_report_scalar(session$R.version$platform),
    packages = data.frame(package = packages, version = unname(versions)),
    scope = "Versions in the retained fitting session; not an archive or source-commit identity.")
}

.gt_report_coefficients <- function(fit, object, kind) {
  if (is.null(object)) return(NULL)
  expected_class <- paste0("gt_", kind)
  if (!inherits(object, expected_class))
    stop(kind, " must be a ", expected_class, " object.", call. = FALSE)
  if (kind == "reliability") {
    expected <- gt_reliability(fit, scale = object$scale, score = object$score,
      counts = object$design, fixed = object$fixed_facets, level = object$level)
  } else {
    grid <- object$allocations[setdiff(names(object$allocations), object$fixed_facets)]
    expected <- gt_dstudy(fit, grid, scale = object$scale, score = object$score,
      fixed = object$fixed_facets, level = object$level)
  }
  supplied <- as.data.frame(object)
  verified <- as.data.frame(expected)
  canonical <- function(table) table[order(table$design_id, table$kind, table$outcome), , drop = FALSE]
  consistent <- identical(names(supplied), names(verified)) &&
    isTRUE(all.equal(canonical(supplied), canonical(verified),
                     tolerance = 1e-12, check.attributes = FALSE)) &&
    identical(attr(supplied, "allocation_columns"), attr(verified, "allocation_columns")) &&
    identical(object$score, expected$score) &&
    identical(object$fixed_facets, expected$fixed_facets)
  if (!consistent)
    stop(kind, " does not agree with projections from the supplied fit; do not combine unrelated or edited results.",
         call. = FALSE)
  # Rebuilt tables ensure unknown attributes or columns on supplied objects
  # cannot carry observations into the report snapshot.
  .gt_report_plain_table(verified)
}

.gt_report_preflight <- function(preflight, fit) {
  if (is.null(preflight)) return(NULL)
  if (!inherits(preflight, "gt_preflight")) stop("preflight must be a gt_preflight object.", call. = FALSE)
  families <- function(x) lapply(x, function(f) f[c("family", "link", "levels", "reference")])
  variables <- c(fit$design$object, fit$design$facets)
  members <- stats::setNames(lapply(variables, function(variable)
    if (variable %in% names(fit$design$nested_groups))
      strsplit(fit$design$nested_groups[[variable]], ":", fixed = TRUE)[[1L]] else variable), variables)
  nesting_checked <- length(preflight$outcome_profile) > 0L
  covariance_parameters <- NULL
  residual_parameters <- 0
  free_count <- function(type, q) switch(type, unstructured = q * (q + 1) / 2,
    diagonal = q, pooled = 1, NA_real_)
  if (all(vapply(fit$families, function(f) f$family == "gaussian", logical(1)))) {
    types <- fit$covariance_types
    if (all(c(fit$design$terms, "Residual") %in% names(types))) {
      covariance_parameters <- vapply(types[fit$design$terms], free_count, numeric(1), q = length(fit$outcomes))
      residual_parameters <- free_count(types[["Residual"]], length(fit$outcomes))
    }
  } else if (identical(fit$diagnostics$covariance_parameterization, "fixed")) {
    covariance_parameters <- rep(0, length(fit$design$terms))
  } else if (is.character(fit$covariance) && length(fit$covariance) == 1L) {
    q <- nrow(fit$covariance_components[[1L]])
    covariance_parameters <- rep(free_count(fit$covariance, q), length(fit$design$terms))
  }
  covariance_checked <- !is.null(covariance_parameters) &&
    all(is.finite(c(covariance_parameters, residual_parameters)))
  consistent <- identical(preflight$outcomes, fit$outcomes) &&
    identical(families(preflight$families), families(fit$families)) &&
    isTRUE(all.equal(preflight$observed_counts, fit$panel$counts)) &&
    identical(as.numeric(preflight$observations), as.numeric(fit$N)) &&
    identical(preflight$sources$source, fit$design$terms) &&
    identical(as.integer(preflight$source_counts),
      c(length(fit$design$terms_requested), length(fit$design$terms))) &&
    identical(as.numeric(preflight$observed_replication), as.numeric(fit$panel$cell_replication)) &&
    (!covariance_checked ||
      (identical(as.numeric(preflight$sources$covariance_parameters), as.numeric(covariance_parameters)) &&
       identical(as.numeric(preflight$parameters[["residual_covariance"]]), as.numeric(residual_parameters)))) &&
    (!nesting_checked || all(vapply(preflight$outcome_profile,
      function(profile) identical(profile$group_members, members), logical(1))))
  if (!consistent)
    stop("preflight does not match the fit's outcome, family, source, covariance, nesting or aggregate-count specification.",
         call. = FALSE)
  summaries <- groups <- categories <- coverage <- list()
  for (name in names(preflight$outcome_profile)) {
    profile <- preflight$outcome_profile[[name]]
    selected <- .gt_report_plain_table(profile$summary,
      c("observations", "distinct_values", "declared_categories", "observed_categories"))
    if (!is.null(selected) && ncol(selected)) summaries[[name]] <-
      data.frame(outcome = name, selected, check.names = FALSE)
    selected <- .gt_report_plain_table(profile$by_variable,
      c("variable", "grouping_scope", "total_groups", "no_variation_groups",
        "single_row_groups", "no_variation_proportion"))
    if (!is.null(selected) && ncol(selected)) groups[[name]] <-
      data.frame(outcome = name, selected, check.names = FALSE)
    if (!is.null(profile$categories)) {
      aliases <- paste0("category_", seq_len(nrow(profile$categories)))
      categories[[name]] <- data.frame(outcome = name, category = aliases,
        .gt_report_plain_table(profile$categories, c("count", "proportion", "observed")))
      position <- match(as.character(profile$category_coverage$category),
                        as.character(profile$categories$category))
      if (anyNA(position)) stop("Preflight category coverage has unmatched categories.", call. = FALSE)
      coverage[[name]] <- data.frame(outcome = name, category = aliases[position],
        .gt_report_plain_table(profile$category_coverage,
          c("variable", "groups_present", "total_groups", "proportion")))
    }
  }
  # Family-specific summaries have different columns; keep them as separate
  # tables rather than padding or accidentally retaining unapproved fields.
  list(association = paste("Outcome/category, family, source and aggregate-count specifications agree.",
       if (nesting_checked) "Declared grouping scopes agree." else "Legacy preflight lacks grouping metadata; nesting correspondence is not verified.",
       if (covariance_checked) "Free covariance-parameter counts agree." else "Covariance parameter counts are not verified.",
       "Requested controls, fixed covariance values and resource-budget correspondence are not verified.",
       "This comparison cannot establish that preflight and fit used the same observations."),
    checks = .gt_report_plain_table(preflight$checks, c("check", "passed")),
    sources = .gt_report_plain_table(preflight$sources,
      c("source", "observed_groups", "predictor_dimensions", "random_dimension", "covariance_parameters")),
    panel = .gt_report_plain_table(preflight$panel_audit$summary,
      c("status", "cell_count", "cell_count_exact")),
    outcome_summary = unname(summaries), outcome_groups = unname(groups),
    category_counts = unname(categories), category_coverage = unname(coverage))
}

# Construct an explicitly versioned, serializable snapshot without fitting.
gt_report <- function(fit, preflight = NULL, reliability = NULL, dstudy = NULL) {
  if (!inherits(fit, "gt_fit")) stop("fit must be a gt_fit object.", call. = FALSE)
  family_names <- vapply(fit$families, `[[`, character(1), "family")
  gaussian <- all(family_names == "gaussian")
  families <- data.frame(outcome = fit$outcomes, family = unname(family_names),
    link = vapply(fit$families, function(f) .gt_report_scalar(f$link), character(1)),
    categories = vapply(fit$families, function(f) length(f$levels), integer(1)), row.names = NULL)
  counts <- fit$panel$counts
  design <- data.frame(variable = c(fit$design$object, fit$design$facets),
    role = c("object", rep("instrumentation facet", length(fit$design$facets))),
    observed_levels = as.numeric(counts[c(fit$design$object, fit$design$facets)]))
  stages <- .gt_staged_diagnostics(fit)
  diagnostics <- data.frame(stage = names(stages),
    status = vapply(stages, function(x) .gt_report_scalar(x$status), character(1)))
  covariance <- do.call(rbind, lapply(names(fit$covariance_components), function(source) {
    component <- fit$covariance_components[[source]]
    dimension <- if (nrow(component) == length(fit$outcomes) && !any(family_names == "categorical"))
      fit$outcomes else paste("latent dimension", seq_len(nrow(component)))
    data.frame(source = source, dimension = dimension, variance = as.numeric(diag(component)),
      covariance_fixed = !gaussian && identical(fit$diagnostics$covariance_parameterization, "fixed"))
  }))
  controls <- list()
  for (engine in c("gaussian", "discrete")) {
    values <- fit$control[[engine]]
    for (name in intersect(names(values), c("maxit", "extra_tries", "retry_seed", "threads",
      "check_hessian", "max_preparation_bytes", "max_dense_bytes", "max_observations",
      "max_random_dimension", "max_parameters", "inner_maxit", "inner_tol", "reltol",
      "validation_inner_tol", "validation_inner_maxit", "alternative_starts"))) {
      value <- values[[name]]
      if (length(value) == 1L && (is.numeric(value) || is.logical(value)))
        controls[[length(controls) + 1L]] <- data.frame(engine = engine, setting = name,
          value = as.character(value))
    }
  }
  optimizer <- fit$diagnostics[["optimizer"]]
  if (is.null(optimizer)) optimizer <- fit$retry_settings[["optimizer"]]
  if (is.character(optimizer) && length(optimizer) == 1L &&
      optimizer %in% c("SLSQP", "CSOLNP", "NPSOL", "L-BFGS-B", "nlminb"))
    controls[[length(controls) + 1L]] <- data.frame(engine = if (gaussian) "gaussian" else "discrete",
      setting = "recorded_optimizer", value = optimizer)
  covariance_types <- fit$covariance_types
  covariance_settings <- if (is.character(covariance_types) && length(covariance_types))
    data.frame(source = names(covariance_types), structure = ifelse(covariance_types %in%
      c("unstructured", "diagonal", "pooled"), covariance_types, "not_recorded")) else NULL
  runtime_packages <- c("Gtheory4LLM", "OpenMx", "Matrix")
  runtime <- list(R = R.version.string, platform = R.version$platform,
    packages = data.frame(package = runtime_packages, version = vapply(runtime_packages,
      function(name) tryCatch(as.character(utils::packageVersion(name)), error = function(e) NA_character_),
      character(1)), row.names = NULL),
    scope = "Environment generating this report; not evidence of the original fitting environment.")
  retention <- data.frame(component = c("data", "model", "session", "retry_log"),
    retained = vapply(c("data", "model", "session", "retry_log"), function(name)
      .gt_report_scalar(fit$retained[[name]], "logical"), logical(1)))
  uncertainty <- list(available = isTRUE(fit$uncertainty$available),
    conditional = isTRUE(fit$uncertainty$restricted_to_interior),
    fixed_components = as.character(fit$uncertainty$fixed_components),
    scope = if (!gaussian) "Discrete coefficients are point estimates only; no intervals are implemented."
      else if (!isTRUE(fit$uncertainty$available)) "No usable fitted parameter covariance is recorded; intervals are unavailable."
      else "Asymptotic estimation intervals under the declared model; not future-panel prediction intervals.")
  batch <- .gt_batch_status(fit$design)
  report <- list(schema_version = "1.0",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    analysis = list(estimator = .gt_report_scalar(fit$estimator),
      backend = .gt_report_scalar(if (is.null(fit$engine)) fit$backend else fit$engine),
      observations = .gt_report_scalar(fit$N, "numeric"),
      replicates = .gt_report_scalar(fit$design$replicates, "numeric"),
      numerically_accepted = .gt_report_scalar(fit$numerically_accepted, "logical"),
      optimizer_completed = .gt_report_scalar(fit$optimizer_completed, "logical"),
      covariance_scale = if (gaussian) "Gaussian observed-score covariance" else "Identified latent predictor covariance",
      minus2loglik = .gt_report_scalar(fit$minus2loglik, "numeric"),
      batch_status = batch$status),
    design = design, families = families,
    random_sources = c(as.character(fit$design$terms), if (identical(batch$status, "modelled")) .GT_CALL_TERM),
    nesting = lapply(fit$design$nested, as.character),
    settings = if (length(controls)) do.call(rbind, controls) else NULL,
    covariance_settings = covariance_settings,
    diagnostics = diagnostics, source_variances = covariance, uncertainty = uncertainty,
    retention = retention,
    provenance = list(fitting_session = .gt_report_session(fit$session), report_runtime = runtime),
    preflight = .gt_report_preflight(preflight, fit),
    reliability = .gt_report_coefficients(fit, reliability, "reliability"),
    dstudy = .gt_report_coefficients(fit, dstudy, "dstudy"),
    association = paste("Supplied coefficient tables agree with recalculated projections from the supplied fit",
      "under their declared scale, allocation, fixed facets, score and uncertainty settings.",
      "This checks numerical compatibility, not original-object or original-data identity."),
    privacy = paste("Observations, facet-level identifiers, calls, grouping examples, models,",
      "free-form diagnostic messages, file paths and arbitrary controls are excluded.",
      "Variable, outcome and source names and aggregate estimates remain; this is not anonymization."),
    limitations = c(.gt_batch_status_text(batch),
      "Numerical acceptance is not a claim of statistical identification, accuracy, or approximation adequacy.",
      "Binary and ordinal coefficients describe latent responses, not observed labels, proportions or majority votes.",
      "Decision studies are conditional projections over supplied allocations; they do not establish an optimal design or future performance.",
      "A backend label records what ran; this report does not qualify the private sparse prototype.",
      "Only recorded scalar requested controls are shown. Omitted defaults are not reconstructed.",
      "A missing fitting session or retention record stays unknown; report-generation versions do not fill that gap."))
  structure(report, class = "gt_report")
}

print.gt_report <- function(x, ...) {
  cat("G-theory analysis report | schema", x$schema_version, "\n")
  cat("Backend:", x$analysis$backend, "| Numerically accepted:", x$analysis$numerically_accepted, "\n")
  cat("Tables:", nrow(x$design), "design variables |",
      if (is.null(x$reliability)) 0L else nrow(x$reliability), "reliability rows |",
      if (is.null(x$dstudy)) 0L else nrow(x$dstudy), "decision-study rows\n")
  cat("Export with gt_export_report(report, path).", "\n")
  invisible(x)
}

.gt_report_escape <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  gsub("'", "&#39;", x, fixed = TRUE)
}

.gt_report_html_table <- function(x) {
  if (is.null(x) || !nrow(x) || !ncol(x)) return("<p class='muted'>Not supplied or not recorded.</p>")
  x <- .gt_report_plain_table(x)
  cells <- lapply(x, function(value) {
    text <- if (is.numeric(value)) format(value, digits = 6L, trim = TRUE) else as.character(value)
    text[is.na(value)] <- "Not available"
    .gt_report_escape(text)
  })
  rows <- vapply(seq_len(nrow(x)), function(i)
    paste0("<tr>", paste0("<td>", vapply(cells, `[[`, character(1), i), "</td>", collapse = ""), "</tr>"), character(1))
  paste0("<div class='table-wrap'><table><thead><tr>",
    paste0("<th scope='col'>", .gt_report_escape(names(x)), "</th>", collapse = ""),
    "</tr></thead><tbody>", paste(rows, collapse = ""), "</tbody></table></div>")
}

# Direct SVG uses only escaped text and formatted numeric coordinates. It is
# independent of Cairo/browser packages and has no executable or remote content.
.gt_report_svg <- function(table, study = FALSE, coefficient = "Phi") {
  if (is.null(table) || !nrow(table)) return("")
  n <- min(nrow(table), if (study) 600L else 30L)
  rows <- table[seq_len(n), , drop = FALSE]
  keys <- unique(rows[c("kind", "outcome")])
  legend_count <- min(nrow(keys), 8L)
  height <- if (study) 350 + 22 * legend_count else 85 + 27 * n
  fmt <- function(x) formatC(x, format = "f", digits = 2L, decimal.mark = ".")
  text <- function(x, y, label, size = 12) paste0("<text x='", fmt(x), "' y='", fmt(y),
    "' font-size='", size, "'>", .gt_report_escape(label), "</text>")
  line <- function(x1, y1, x2, y2, color = "#cbd5e1") paste0("<line x1='", fmt(x1),
    "' y1='", fmt(y1), "' x2='", fmt(x2), "' y2='", fmt(y2), "' stroke='", color, "'/>")
  body <- c("<rect width='900' height='100%' fill='white'/>",
    text(16, 22, paste(coefficient, "|", rows$scale[1L], "scale"), 16))
  if (study) {
    good_x <- is.finite(rows$measurements_per_object)
    limits <- if (any(good_x)) range(c(0, rows$measurements_per_object[good_x])) else c(0, 1)
    if (limits[2L] == 0) limits[2L] <- 1
    xx <- 65 + 775 * (rows$measurements_per_object / limits[2L])
    yy <- 265 - 205 * rows[[coefficient]]
    for (tick in seq(0, 1, by = .25)) body <- c(body,
      line(65, 265 - 205 * tick, 840, 265 - 205 * tick), text(23, 270 - 205 * tick, tick))
    for (tick in seq(0, limits[2L], length.out = 5L)) body <- c(body,
      text(65 + 775 * (tick / limits[2L]), 286, format(tick, digits = 3L, trim = TRUE), 11))
    body <- c(body, text(280, 315, "Measurements per object; open symbols = extrapolated"))
  } else {
    xx <- 315 + 485 * rows[[coefficient]]
    yy <- 55 + 27 * (seq_len(n) - 1L)
    for (tick in seq(0, 1, by = .25)) body <- c(body,
      line(315 + 485 * tick, 38, 315 + 485 * tick, height - 35),
      text(310 + 485 * tick, height - 14, tick))
    labels <- paste(rows$kind, rows$outcome, sep = ": ")
    labels[nchar(labels) > 38L] <- paste0(substr(labels[nchar(labels) > 38L], 1L, 35L), "...")
    for (i in seq_len(n)) body <- c(body, text(12, yy[i] + 4, paste0("[", i, "] ", labels[i])))
  }
  lower <- rows[[paste0(coefficient, "_lower")]]
  upper <- rows[[paste0(coefficient, "_upper")]]
  palette <- c("#1d4ed8", "#b45309", "#15803d", "#9333ea", "#be123c", "#0e7490")
  for (i in which(is.finite(xx) & is.finite(yy))) {
    series <- match(TRUE, keys$kind == rows$kind[i] & keys$outcome == rows$outcome[i])
    color <- palette[(series - 1L) %% length(palette) + 1L]
    if (is.finite(lower[i]) && is.finite(upper[i])) body <- c(body,
      if (study) line(xx[i], 265 - 205 * lower[i], xx[i], 265 - 205 * upper[i], color)
      else line(315 + 485 * lower[i], yy[i], 315 + 485 * upper[i], yy[i], color))
    label <- paste(rows$kind[i], rows$outcome[i], coefficient,
      format(rows[[coefficient]][i], digits = 4L), "design", rows$design_id[i])
    body <- c(body, paste0("<circle cx='", fmt(xx[i]), "' cy='", fmt(yy[i]),
      "' r='4' stroke='", color, "' fill='", if (isTRUE(rows$extrapolated[i])) "white" else color,
      "'><title>", .gt_report_escape(label), "</title></circle>"))
  }
  if (study) for (i in seq_len(legend_count)) {
    label <- paste(keys$kind[i], keys$outcome[i], sep = ": ")
    if (nchar(label) > 85L) label <- paste0(substr(label, 1L, 82L), "...")
    body <- c(body, paste0("<circle cx='70' cy='", 335 + 22 * (i - 1L),
      "' r='4' fill='", palette[(i - 1L) %% length(palette) + 1L], "'/>"),
      text(85, 339 + 22 * (i - 1L), label))
  }
  paste0("<figure><svg xmlns='http://www.w3.org/2000/svg' role='img' aria-label='",
    if (study) "Supplied allocation projections" else "Coefficient estimates and available intervals",
    "' font-family='sans-serif' viewBox='0 0 900 ", height, "'>", paste(body, collapse = ""), "</svg><figcaption>",
    "Showing ", n, " of ", nrow(table), " coefficient rows. Full labels and values are in the table. ",
    "Segments show available estimation intervals; missing intervals are not fabricated. ",
    if (study) paste0("Points are not connected across allocations. Legend shows ",
      legend_count, " of ", nrow(keys), " series. ") else "",
    "Colours distinguish coefficient series and may repeat for many outcomes.</figcaption></figure>")
}

.gt_report_coverage_svg <- function(table) {
  categories <- head(unique(table$category), 20L)
  variables <- head(unique(table$variable), 12L)
  matrix_bottom <- 38 + 28 * length(categories)
  height <- matrix_bottom + 55 + 22 * length(variables)
  width <- 660 / max(1L, length(variables))
  outcome <- table$outcome[1L]
  if (nchar(outcome) > 70L) outcome <- paste0(substr(outcome, 1L, 67L), "...")
  body <- paste0("<text x='15' y='24' font-size='16'>Category coverage: ",
                  .gt_report_escape(outcome), "</text>")
  for (i in seq_along(categories)) {
    body <- c(body, paste0("<text x='10' y='", 55 + 28 * (i - 1L), "' font-size='12'>",
      .gt_report_escape(categories[i]), "</text>"))
    for (j in seq_along(variables)) {
      value <- table$proportion[table$category == categories[i] & table$variable == variables[j]]
      if (length(value) != 1L || !is.finite(value) || value < 0 || value > 1) next
      color <- grDevices::rgb(.95 - .8 * value, .97 - .55 * value, .99 - .35 * value)
      body <- c(body, paste0("<rect x='", 175 + width * (j - 1L), "' y='", 38 + 28 * (i - 1L),
        "' width='", width - 2, "' height='26' fill='", color, "'/>",
        "<text x='", 180 + width * (j - 1L), "' y='", 55 + 28 * (i - 1L),
        "' font-size='11' fill='", if (value > .6) "white" else "#172033", "'>",
        .gt_report_escape(paste0(format(100 * value, digits = 3L, trim = TRUE), "%")), "</text>"))
    }
  }
  for (j in seq_along(variables)) {
    label <- variables[j]
    if (nchar(label) > 85L) label <- paste0(substr(label, 1L, 82L), "...")
    body <- c(body, paste0("<text x='", 180 + width * (j - 1L), "' y='", matrix_bottom + 17,
      "' font-size='11'>V", j, "</text>"),
      paste0("<text x='15' y='", matrix_bottom + 45 + 22 * (j - 1L),
        "' font-size='12'>V", j, ": ", .gt_report_escape(label), "</text>"))
  }
  paste0("<figure><svg xmlns='http://www.w3.org/2000/svg' role='img' font-family='sans-serif' ",
    "aria-label='Aliased category coverage' viewBox='0 0 900 ",
    height, "'>", paste(body, collapse = ""), "</svg><figcaption>Descriptive proportion of groups with each category. Showing ",
    length(categories), "/", length(unique(table$category)), " aliased categories and ",
    length(variables), "/", length(unique(table$variable)), " variables. Darker means greater coverage, not adequacy. ",
    "Full labels and grouping scopes are in the adjacent aggregate tables.</figcaption></figure>")
}

gt_export_report <- function(report, path, overwrite = FALSE) {
  if (!inherits(report, "gt_report") || !identical(report$schema_version, "1.0"))
    stop("Expected a gt_report with supported schema_version '1.0'.", call. = FALSE)
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path) ||
      !grepl("\\.html?$", path, ignore.case = TRUE))
    stop("path must name one .html or .htm file.", call. = FALSE)
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite))
    stop("overwrite must be TRUE or FALSE.", call. = FALSE)
  if (!dir.exists(dirname(path)) || dir.exists(path))
    stop("The report's parent directory must exist and path must not be a directory.", call. = FALSE)
  if (file.exists(path) && !overwrite) stop("Report file already exists; use overwrite = TRUE to replace it.", call. = FALSE)
  esc <- .gt_report_escape
  heading <- function(label) paste0("<h2>", esc(label), "</h2>")
  paragraph <- function(text) paste0("<p>", esc(text), "</p>")
  table <- .gt_report_html_table
  metadata <- data.frame(field = names(report$analysis), value = vapply(report$analysis,
    function(x) if (length(x) == 1L && !is.na(x)) as.character(x) else "Not recorded", character(1)))
  contents <- c("<!doctype html><html lang='en'><head><meta charset='utf-8'>",
    "<meta name='viewport' content='width=device-width,initial-scale=1'>",
    "<title>G-theory analysis report</title><style>",
    "body{font:16px/1.55 system-ui,sans-serif;color:#172033;background:#f4f6fa;margin:0}",
    "main{max-width:1100px;margin:30px auto;padding:30px;background:white;border-radius:12px}",
    "h1{margin:0;color:#123b59}h2{margin-top:32px;border-bottom:1px solid #ccd5df;padding-bottom:8px}",
    "p,td,th{overflow-wrap:anywhere}.notice{background:#eef5fa;padding:16px;border-left:4px solid #27658c}",
    ".muted,figcaption{color:#526176;font-size:14px}.table-wrap{overflow-x:auto;margin:16px 0}",
    "table{border-collapse:collapse;width:100%;font-size:13px}th,td{text-align:left;padding:8px;border:1px solid #dce3eb}",
    "th{background:#edf2f7}tr:nth-child(even){background:#fafbfd}figure{margin:20px 0}svg{width:100%;height:auto}",
    "@media print{body{background:white}main{margin:0;padding:0}.table-wrap{overflow:visible}table{font-size:9px}}",
    "</style></head><body><main><h1>G-theory analysis report</h1>",
    paragraph(paste("Snapshot schema", report$schema_version, "| Generated", report$generated_at)),
    paste0("<div class='notice'>", esc(report$privacy), "</div>"),
    heading("Analysis and numerical status"), table(metadata), table(report$diagnostics),
    paragraph(if (isTRUE(report$analysis$numerically_accepted))
      "The recorded numerical acceptance passed; scientific interpretation still depends on the stated assumptions."
      else "Acceptance is failed or not recorded. Estimates are diagnostic only; this report does not authorize reliability interpretation."),
    heading("Design and observation families"), table(report$design), table(report$families),
    paragraph(paste("Random sources:", paste(report$random_sources, collapse = ", "))),
    paragraph(if (length(report$nesting)) paste("Declared nesting:", paste(vapply(names(report$nesting),
      function(name) paste(name, "within", paste(report$nesting[[name]], collapse = ", ")),
      character(1)), collapse = "; "))
      else "No explicit nesting recorded."),
    heading("Recorded settings and retention"), table(report$settings),
    table(report$covariance_settings), table(report$retention),
    heading("Source variances"), paragraph(report$analysis$covariance_scale), table(report$source_variances))
  if (!is.null(report$preflight)) {
    p <- report$preflight
    contents <- c(contents, heading("Supplied preflight: aggregate correspondence only"), paragraph(p$association),
      table(p$checks), table(p$panel), table(p$sources), heading("Outcome profile: aggregate counts only"),
      unlist(lapply(p$outcome_summary, table), use.names = FALSE),
      unlist(lapply(p$outcome_groups, table), use.names = FALSE),
      paragraph("Category aliases follow declared category order within each outcome. Raw category labels are intentionally omitted; correspondence remains private to the analysis."),
      unlist(lapply(p$category_counts, table), use.names = FALSE),
      unlist(lapply(p$category_coverage, function(x) c(.gt_report_coverage_svg(x), table(x))), use.names = FALSE))
  }
  contents <- c(contents, heading("Coefficient interpretation and uncertainty"),
    paragraph(report$uncertainty$scope),
    paragraph(if (isTRUE(report$uncertainty$conditional)) paste("Inference conditions on fixed covariance components:",
      paste(report$uncertainty$fixed_components, collapse = ", ")) else "No interior-block conditioning is recorded."),
    paragraph(report$association), heading("Reliability"),
    .gt_report_svg(report$reliability, coefficient = "Erho2"),
    .gt_report_svg(report$reliability, coefficient = "Phi"), table(report$reliability),
    heading("Decision study: supplied allocations"),
    .gt_report_svg(report$dstudy, study = TRUE, coefficient = "Phi"), table(report$dstudy),
    heading("Fitting-session provenance"), paragraph(report$provenance$fitting_session$scope),
    paragraph(paste("Recorded fitting R:", report$provenance$fitting_session$R,
      "| Platform:", report$provenance$fitting_session$platform)),
    table(report$provenance$fitting_session$packages),
    heading("Report-generation provenance"), paragraph(report$provenance$report_runtime$scope),
    paragraph(paste(report$provenance$report_runtime$R, report$provenance$report_runtime$platform, sep = " | ")),
    table(report$provenance$report_runtime$packages), heading("Scope and limitations"),
    paste0("<ul>", paste0("<li>", esc(report$limitations), "</li>", collapse = ""), "</ul>"),
    "</main></body></html>")
  temporary <- tempfile("gtheory-report-", tmpdir = dirname(path), fileext = ".html")
  on.exit(unlink(temporary), add = TRUE)
  connection <- file(temporary, open = "wt", encoding = "UTF-8")
  tryCatch(writeLines(enc2utf8(contents), connection), finally = close(connection))
  if (!file.copy(temporary, path, overwrite = overwrite))
    stop("Could not write report; an existing file was not replaced without permission.", call. = FALSE)
  invisible(normalizePath(path, mustWork = TRUE))
}
