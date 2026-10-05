# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Structural and resource checks without optimization or dense model matrices.

# Exact decimal products and subtraction keep very large panel counts honest.
# Digits are stored least significant first; each multiplier is an observed
# level count, so the small intermediate arithmetic is exact in a double.
.gt_preflight_cell_total <- function(counts, subtract = 0) {
  digits <- 1
  for (count in counts) {
    carry <- 0
    for (i in seq_along(digits)) {
      value <- digits[i] * count + carry
      digits[i] <- value %% 10
      carry <- floor(value / 10)
    }
    while (carry > 0) {
      digits <- c(digits, carry %% 10)
      carry <- floor(carry / 10)
    }
  }
  borrow <- 0
  for (i in seq_along(digits)) {
    value <- digits[i] - subtract %% 10 - borrow
    subtract <- floor(subtract / 10)
    borrow <- as.integer(value < 0)
    digits[i] <- value + 10 * borrow
  }
  while (length(digits) > 1L && utils::tail(digits, 1L) == 0) digits <- head(digits, -1L)
  paste(rev(digits), collapse = "")
}

.gt_preflight_example_limit <- function(x, name, zero = TRUE) {
  if (!is.numeric(x) || is.complex(x) || length(x) != 1L || !is.finite(x) ||
      x != floor(x) || x < (if (zero) 0 else 1) || x > .Machine$integer.max)
    stop(name, " must be a ", if (zero) "nonnegative" else "positive",
         " finite integer no greater than .Machine$integer.max.", call. = FALSE)
  as.integer(x)
}

# A factor subset otherwise retains every original label in its levels
# attribute, even with zero rows. Keep only identifiers actually shown.
.gt_preflight_drop_example_levels <- function(data) {
  for (name in names(data)) if (is.factor(data[[name]])) data[[name]] <- droplevels(data[[name]])
  data
}

.gt_preflight_panel_audit <- function(data, variables, replicates, max_examples) {
  values <- lapply(data[variables], unique)
  counts <- vapply(values, length, integer(1))
  codes <- Map(match, data[variables], values)
  keys <- do.call(paste, c(unname(codes), list(sep = ":")))
  unique_keys <- unique(keys)
  cell <- match(keys, unique_keys)
  first <- match(unique_keys, keys)
  frequencies <- tabulate(cell, nbins = length(unique_keys))
  status <- ifelse(frequencies < replicates, "under_replicated",
                   ifelse(frequencies > replicates, "over_replicated", "complete"))
  missing_exact <- .gt_preflight_cell_total(counts, length(unique_keys))
  summary <- data.frame(status = c("complete", "under_replicated", "over_replicated", "missing"),
    cell_count_exact = c(as.character(sum(status == "complete")),
      as.character(sum(status == "under_replicated")),
      as.character(sum(status == "over_replicated")), missing_exact), stringsAsFactors = FALSE)
  summary$cell_count <- as.numeric(summary$cell_count_exact)
  summary <- summary[c("status", "cell_count", "cell_count_exact")]

  # Never format identifiers into keys. Enumerate only the first requested
  # absent cells, using native values via integer codes. At most the number of
  # observed cells plus the requested missing examples can be visited.
  absent <- data[FALSE, variables, drop = FALSE]
  needed <- min(max_examples, as.numeric(missing_exact))
  if (needed > 0) {
    present <- list2env(stats::setNames(rep(list(TRUE), length(unique_keys)), unique_keys),
                        parent = emptyenv(), hash = TRUE)
    indices <- matrix(0L, nrow = needed, ncol = length(variables))
    candidate <- rep(1L, length(variables))
    found <- 0L
    while (found < needed) {
      key <- paste(candidate, collapse = ":")
      if (!exists(key, envir = present, inherits = FALSE)) {
        found <- found + 1L
        indices[found, ] <- candidate
      }
      if (found < needed) for (j in seq_along(candidate)) {
        if (candidate[j] < counts[j]) {
          candidate[j] <- candidate[j] + 1L
          break
        }
        candidate[j] <- 1L
      }
    }
    # Subset a data-frame template to preserve column classes and names.
    absent <- data[rep(1L, needed), variables, drop = FALSE]
    for (j in seq_along(variables)) absent[[j]] <- values[[j]][indices[, j]]
    rownames(absent) <- NULL
  }

  fields <- c(row = "row", observed_replicates = "observed_replicates",
              declared_replicates = "declared_replicates", status = "status")
  prefix <- ".gt_"
  while (any(paste0(prefix, fields) %in% names(data))) prefix <- paste0(".", prefix)
  metadata <- stats::setNames(paste0(prefix, fields), names(fields))
  issue_ids <- which(status != "complete")
  selected <- head(issue_ids, max_examples)
  issues <- data[first[selected], variables, drop = FALSE]
  annotate <- function(table, ids) {
    table[[metadata[["observed_replicates"]]]] <- frequencies[ids]
    table[[metadata[["declared_replicates"]]]] <- rep(replicates, length(ids))
    table[[metadata[["status"]]]] <- status[ids]
    rownames(table) <- NULL
    table
  }
  issues <- annotate(issues, selected)
  issue_rows <- which(status[cell] != "complete")
  rows <- head(issue_rows, max_examples)
  examples <- annotate(data[rows, variables, drop = FALSE], cell[rows])
  examples[[metadata[["row"]]]] <- rows
  sampling <- data.frame(table = c("missing_cells", "replication_issues", "row_examples"),
    total_exact = c(missing_exact, as.character(length(issue_ids)), as.character(length(issue_rows))),
    shown = c(nrow(absent), nrow(issues), nrow(examples)),
    limit = max_examples, stringsAsFactors = FALSE)
  sampling$total <- as.numeric(sampling$total_exact)
  sampling$truncated <- sampling$total > sampling$shown
  list(cell_counts = frequencies, audit = list(
    scope = "Cartesian product of observed coded levels; unused factor levels are excluded.",
    declared_replicates = replicates, summary = summary,
    expected_cells_exact = .gt_preflight_cell_total(counts),
    missing_cells = .gt_preflight_drop_example_levels(absent),
    replication_issues = .gt_preflight_drop_example_levels(issues),
    row_examples = .gt_preflight_drop_example_levels(examples),
    metadata_columns = metadata, examples = sampling,
    example_order = "Missing cells use first-observed level order, first axis varying fastest; observed cells and rows use input order."))
}

.gt_preflight_outcome_profile <- function(data, outcomes, families, design, max_examples) {
  variables <- c(design$object, design$facets)
  members <- stats::setNames(lapply(variables, function(variable) {
    if (variable %in% names(design$nested_groups))
      strsplit(design$nested_groups[[variable]], ":", fixed = TRUE)[[1L]] else variable
  }), variables)
  grouping <- lapply(members, function(columns) {
    key <- .gt_tuple_key(data, columns)
    unique_keys <- unique(key)
    list(index = match(key, unique_keys), first = match(unique_keys, key), n = length(unique_keys))
  })
  fields <- c(row_count = "row_count", distinct_values = "distinct_values")
  prefix <- ".gt_"
  while (any(paste0(prefix, fields) %in% names(data))) prefix <- paste0(".", prefix)
  metadata <- stats::setNames(paste0(prefix, fields), names(fields))
  stats::setNames(lapply(outcomes, function(outcome) {
    spec <- families[[outcome]]
    y <- data[[outcome]]
    categorical <- spec$family != "gaussian"
    codes <- if (!categorical) match(y, unique(y)) else
      if (spec$family == "binary") as.integer(y) + 1L else match(as.character(y), spec$levels)
    category_counts <- if (categorical) tabulate(codes, nbins = length(spec$levels)) else integer()
    categories <- if (categorical) data.frame(category = spec$levels, count = category_counts,
      proportion = category_counts / length(y), observed = category_counts > 0L,
      stringsAsFactors = FALSE) else NULL
    finite_statistic <- function(value) if (is.finite(value)) value else NA_real_
    summary <- data.frame(observations = length(y), distinct_values = length(unique(codes)),
      declared_categories = if (categorical) length(spec$levels) else NA_integer_,
      observed_categories = if (categorical) sum(category_counts > 0L) else NA_integer_,
      minimum = if (!categorical) min(y) else NA_real_,
      maximum = if (!categorical) max(y) else NA_real_,
      mean = if (!categorical) finite_statistic(mean(y)) else NA_real_,
      standard_deviation = if (!categorical) finite_statistic(stats::sd(y)) else NA_real_)
    grouped <- lapply(variables, function(variable) {
      group <- grouping[[variable]]
      row_count <- tabulate(group$index, nbins = group$n)
      # Distinct group/value pairs occupy at most one entry per input row;
      # never construct a dense group-by-category contingency table.
      pairs <- unique(data.frame(group = group$index, value = codes))
      distinct <- tabulate(pairs$group, nbins = group$n)
      no_variation <- which(distinct == 1L)
      selected <- head(no_variation, max_examples)
      examples <- data[group$first[selected], members[[variable]], drop = FALSE]
      examples[[metadata[["row_count"]]]] <- row_count[selected]
      examples[[metadata[["distinct_values"]]]] <- distinct[selected]
      rownames(examples) <- NULL
      examples <- .gt_preflight_drop_example_levels(examples)
      scope <- if (variable %in% names(design$nested_groups)) "declared_parent_scoped" else "marginal_coded_levels"
      coverage <- if (categorical) {
        present <- tabulate(pairs$value, nbins = length(spec$levels))
        data.frame(variable = variable, category = spec$levels, groups_present = present,
          total_groups = group$n, proportion = present / group$n, stringsAsFactors = FALSE)
      } else NULL
      list(summary = data.frame(variable = variable, grouping_scope = scope,
        total_groups = group$n, no_variation_groups = length(no_variation),
        single_row_groups = sum(row_count == 1L), no_variation_proportion = length(no_variation) / group$n,
        stringsAsFactors = FALSE), coverage = coverage, examples = examples,
        sampling = data.frame(variable = variable, total = length(no_variation), shown = length(selected),
          limit = max_examples, truncated = length(selected) < length(no_variation), stringsAsFactors = FALSE))
    })
    list(family = spec$family, link = spec$link, summary = summary, categories = categories,
      by_variable = do.call(rbind, lapply(grouped, `[[`, "summary")),
      category_coverage = if (categorical) do.call(rbind, lapply(grouped, `[[`, "coverage")) else NULL,
      group_members = members,
      no_variation_examples = stats::setNames(lapply(grouped, `[[`, "examples"), variables),
      examples = do.call(rbind, lapply(grouped, `[[`, "sampling")), metadata_columns = metadata,
      scope = paste("Descriptive observed response information only; no adequacy threshold or category collapsing.",
        "Declared nested facets use ancestor-scoped groups; other variables use marginal coded levels.",
        "Single-row groups are included in no-variation counts and counted separately.",
        "Gaussian values are never treated as categories; nonfinite derived summaries are NA."),
      privacy = paste("Tables contain outcome/category labels and bounded design-group identifiers.",
        "No response rows or unrelated columns are retained. Small counts and identifiers can still be sensitive;",
        "review before sharing. max_examples = 0 suppresses group identifiers, not aggregate counts or labels."))
  }), outcomes)
}

# Inspect an observed design before fitting
gt_preflight <- function(data, outcomes, design, family = gt_family("gaussian"),
                         covariance = "unstructured", residual = NULL,
                         control = gt_control(), max_examples = 10L) {
  max_examples <- .gt_preflight_example_limit(max_examples, "max_examples")
  if (!inherits(design, "gt_design")) stop("Use gt_design() to declare the design.", call. = FALSE)
  if (!is.data.frame(data) || !nrow(data) || anyDuplicated(names(data)))
    stop("data must be a nonempty data frame with unique column names.", call. = FALSE)
  outcomes <- .gt_design_names(outcomes, "outcomes")
  variables <- c(design$object, design$facets)
  if (length(intersect(outcomes, variables))) stop("Outcome and design columns must differ.", call. = FALSE)
  missing_columns <- setdiff(c(variables, outcomes), names(data))
  if (length(missing_columns)) stop("Missing outcome or design columns: ",
    paste(sQuote(missing_columns), collapse = ", "), ".", call. = FALSE)
  if (!inherits(control, "gt_control")) stop("control must be created by gt_control().", call. = FALSE)
  for (v in variables) {
    x <- data[[v]]
    invalid <- if (is.atomic(x)) which(is.na(x) | if (is.numeric(x)) !is.finite(x) else FALSE) else integer()
    if (!is.atomic(x) || length(invalid) || length(unique(x)) < 2L) {
      detail <- if (length(invalid)) paste0(" Invalid rows: ",
        paste(head(invalid, max_examples), collapse = ", "),
        if (length(invalid) > max_examples)
          paste0(" (", length(invalid), " total; examples truncated)") else "", ".") else
        if (!is.atomic(x)) " The column must be atomic." else
          paste0(" Observed distinct levels: ", length(unique(x)), ".")
      stop("Each design variable needs at least two finite, nonmissing levels: ", v, ".", detail, call. = FALSE)
    }
  }
  resolved <- .gt_resolve_families(data[c(variables, outcomes)], outcomes, family, allow_absent = TRUE)
  families <- resolved$families
  kinds <- vapply(families, `[[`, character(1), "family")
  gaussian <- all(kinds == "gaussian")
  if (any(kinds == "gaussian") && !gaussian)
    stop("Joint Gaussian-discrete outcomes are not supported by the current engines.", call. = FALSE)

  checks <- data.frame(check = character(), passed = logical(), detail = character(),
                       stringsAsFactors = FALSE)
  add_check <- function(name, passed, detail) {
    checks <<- rbind(checks, data.frame(check = name, passed = passed,
                                       detail = detail, stringsAsFactors = FALSE))
  }
  outcome_profile <- .gt_preflight_outcome_profile(resolved$data, outcomes, families, design, max_examples)
  category_complete <- vapply(outcome_profile, function(profile)
    is.null(profile$categories) || all(profile$categories$observed), logical(1))
  if (!gaussian) add_check("outcome_category_coverage", all(category_complete),
    if (all(category_complete)) "Every declared category is observed in each discrete outcome." else
      paste0("Absent declared categories in ", paste(sQuote(outcomes[!category_complete]), collapse = ", "),
        "; fitting still refuses these outcomes. Inspect outcome_profile category counts."))
  n <- nrow(data)
  counts <- vapply(data[variables], function(x) length(unique(x)), integer(1))
  panel <- .gt_preflight_panel_audit(data, variables, design$replicates, max_examples)
  batch_audit <- if (is.null(design$batch)) NULL else .gt_batch_audit(data, design, max_examples)
  cell_counts <- panel$cell_counts
  expected_cells <- prod(as.double(counts))
  complete <- length(cell_counts) == expected_cells
  replicated <- all(cell_counts == design$replicates)
  add_check("declared_replication", replicated,
            "Every observed full cell must have the declared number of measurements.")
  design_error <- NULL
  checked <- tryCatch(.gt_resolve_design(resolved$data, design,
    if (gaussian) "gaussian" else "discrete"), error = function(e) {
      design_error <<- conditionMessage(e)
      NULL
    })
  add_check("family_design_resolution", !is.null(checked),
            if (is.null(design_error)) "Family-specific source resolution succeeded." else design_error)
  # Keep requested source counts available even when fitting is blocked.
  reporting_design <- if (is.null(checked)) design else checked
  terms <- reporting_design$term_members
  groups <- lapply(terms, function(members) .gt_d_group(data, members))
  levels <- vapply(groups, `[[`, integer(1), "nlevels")
  q <- if (gaussian) length(outcomes) else sum(vapply(families, function(f)
    if (f$family == "categorical") length(f$levels) - 1L else 1L, integer(1)))
  location_parameters <- if (gaussian) length(outcomes) else sum(vapply(families, function(f)
    if (f$family == "binary") 1L else length(f$levels) - 1L, integer(1)))
  random_dimension <- sum(as.double(levels)) * q
  add_check("repeated_source_groups", all(levels >= 2L),
            "Every retained source needs at least two observed groups.")
  covariance_parameters <- numeric(length(terms))
  names(covariance_parameters) <- names(terms)
  residual_parameters <- 0
  resources <- list()
  kernel_check <- "not_applicable"
  if (gaussian) {
    .gt_gaussian_validate_control(control$gaussian)
    if (is.null(residual)) residual <- "unstructured"
    .gt_validate_residual_request(residual)
    component_names <- c(names(terms), "Residual")
    .gt_validate_covariance_request(covariance, names(terms))
    types <- if (is.null(names(covariance)))
      stats::setNames(rep(covariance, length(component_names)), component_names) else {
        overridden <- stats::setNames(rep("diagonal", length(component_names)), component_names)
        overridden[names(covariance)] <- covariance
        overridden
      }
    types[["Residual"]] <- residual
    parameter_count <- function(type) switch(type, diagonal = q,
      unstructured = q * (q + 1) / 2, pooled = 1)
    covariance_parameters[] <- vapply(types[names(terms)], parameter_count, numeric(1))
    residual_parameters <- parameter_count(residual)
    add_check("complete_coded_panel", complete,
              "Gaussian fitting requires the complete Cartesian product of observed coded levels.")
    add_check("one_row_per_cell", design$replicates == 1L,
              "The Gaussian backend currently supports one measurement per full cell.")
    add_check("factorial_strata_limit", length(variables) <= 12L,
              "The exact Gaussian backend supports at most 4096 strata (12 axes including the object).")
    limit <- control$gaussian$max_preparation_bytes
    if (is.null(limit)) limit <- 512 * 1024^2
    if (!is.numeric(limit) || length(limit) != 1L || !is.finite(limit) || limit <= 0)
      stop("max_preparation_bytes must be a positive finite number of bytes.", call. = FALSE)
    bytes <- .gt_gaussian_preparation_bytes(expected_cells, q, length(variables))
    add_check("preparation_resource_limit", bytes <= limit,
              "The Gaussian preparation estimate must fit the configured allocation limit.")
    resources <- list(preparation_estimated_bytes = bytes, preparation_limit_bytes = limit,
      factorial_strata = 2^length(variables),
      scope = "Preparation working arrays only; excludes caller data and downstream OpenMx objects.")
  } else {
    if (!is.null(residual)) stop("Do not specify a Gaussian residual covariance for discrete outcomes.", call. = FALSE)
    dc <- .gt_d_control(control$discrete)
    .gt_d_validate_covariance_request(covariance)
    covariance_parameters[] <- if (!is.null(dc$fixed_covariance)) 0 else
      if (covariance == "diagonal") q else q * (q + 1) / 2
    add_check("repeated_observations_within_source", all(levels < n),
              "Observation-specific random sources are unsupported for discrete outcomes.")
    add_check("observation_limit", n <= dc$max_observations,
              paste("Measurement rows must not exceed", dc$max_observations))
    add_check("random_dimension_limit", random_dimension <= dc$max_random_dimension,
              paste("Dense random-effect dimensions must not exceed", dc$max_random_dimension))
    add_check("parameter_limit", location_parameters + sum(covariance_parameters) <= dc$max_parameters,
              paste("Free observation and covariance parameters must not exceed", dc$max_parameters))
    dense <- .gt_d_dense_bytes(n, q, random_dimension)
    add_check("dense_memory_limit", dense$total <= dc$max_dense_bytes,
              paste("Estimated dense working memory", .gt_d_format_bytes(dense$total),
                    "must not exceed max_dense_bytes", .gt_d_format_bytes(dc$max_dense_bytes)))
    # Reuse fitting's covariance/kernel checks only within its size limits.
    # No random-design matrix, Hessian, likelihood or optimizer is constructed.
    if (all(checks$passed)) {
      setup_error <- NULL
      setup <- tryCatch({
        prep <- .gt_d_prepare(resolved$data, outcomes, families)
        .gt_d_covariance_setup(groups, prep$q, covariance, dc, prep$dimensions)
      }, error = function(e) {
        setup_error <<- conditionMessage(e)
        NULL
      })
      add_check("covariance_specification", !is.null(setup),
                if (is.null(setup_error)) "Covariance setup succeeded." else setup_error)
      if (!is.null(setup) && is.null(setup$fixed)) {
        rank <- .gt_d_kernel_rank(groups)
        augmented <- .gt_d_kernel_rank(c(unname(groups), list(
          list(index = seq_len(n), nlevels = n))))
        add_check("source_kernel_independence", rank$rank == rank$n_sources,
                  "Observed source kernels must be linearly independent under the current free-covariance guard.")
        add_check("source_residual_separation", augmented$rank == augmented$n_sources,
                  "Free source kernels must not span the observation identity under the current discrete guard.")
        kernel_check <- "checked"
      } else kernel_check <- if (is.null(setup)) "skipped_invalid_covariance" else "not_required_for_fixed_covariance"
    } else kernel_check <- "skipped_after_structural_or_resource_failure"
    resources <- list(dense_matrix_bytes_lower_bound =
      8 * (as.double(n) * q * random_dimension + random_dimension^2),
      dense_working_bytes_estimate = dense$total,
      dense_working_bytes_breakdown = dense[c("random_design", "conditional_hessian",
        "block_slices", "predictors", "multiplier")],
      max_dense_bytes = dc$max_dense_bytes,
      max_observations = dc$max_observations,
      max_random_dimension = dc$max_random_dimension, max_parameters = dc$max_parameters,
      scope = paste("Planning estimates for one dense likelihood evaluation, checked",
        "before allocation. Not peak resident memory and not a runtime prediction."))
  }
  sources <- data.frame(source = names(terms), observed_groups = unname(levels),
    predictor_dimensions = q, random_dimension = unname(as.double(levels) * q),
    covariance_parameters = unname(covariance_parameters), stringsAsFactors = FALSE)
  balanced <- complete && replicated
  scales <- if (!balanced || !all(category_complete) || any(kinds == "categorical")) character() else
    if (gaussian) "observed" else "latent"
  notes <- c("Preflight checks structure and configured size limits. It does not establish identification, approximation adequacy, fit acceptance, or scientific validity.",
    "A supported reliability scale is conditional on a numerically accepted fit and the stated averaging design.",
    "Starting values and all optimizer-specific controls are validated during fitting.")
  if (any(levels < 5L)) notes <- c(notes,
    "Some sources have fewer than five observed groups. This is a descriptive caution about limited information, not a rejection rule.")
  if (!balanced) notes <- c(notes,
    "Analytic reliability and D studies require a complete balanced coded panel even when discrete fitting permits missing whole cells.")
  if (any(kinds == "categorical")) notes <- c(notes,
    "Unordered categorical outcomes have no implemented scalar G/Phi; category contrasts are not separate measured outcomes.")
  # The call is kept as a record of the request; nothing reads it back. Through
  # do.call(), or with the data written inline, its data argument is the data
  # frame itself, unused columns included. Only a plain object name is kept;
  # anything else is replaced by the marker a fit uses when its data is dropped.
  recorded_call <- match.call()
  if ("data" %in% names(recorded_call) && !is.name(recorded_call$data))
    recorded_call$data <- as.name("<dropped>")
  report <- structure(list(call = recorded_call, outcomes = outcomes, families = families,
    engine = if (gaussian) "exact_balanced_gaussian" else "dense_joint_discrete_laplace",
    observations = n, observed_counts = counts, observed_cells = length(cell_counts),
    expected_cells = expected_cells, observed_replication = sort(unique(as.integer(cell_counts))),
    complete_balanced_panel = balanced, panel_audit = panel$audit, outcome_profile = outcome_profile, sources = sources,
    source_counts = c(requested = length(design$terms_requested), retained = length(terms)),
    aliased_terms = if (is.null(checked)) character() else checked$aliased_terms,
    random_dimension = random_dimension, predictor_dimensions = q,
    parameters = c(observation = location_parameters, source_covariance = sum(covariance_parameters),
      residual_covariance = residual_parameters,
      total = location_parameters + sum(covariance_parameters) + residual_parameters),
    checks = checks, fitting_feasible = all(checks$passed), resources = resources,
    kernel_check = kernel_check, supported_reliability_scales = scales,
    scale_interpretation = if (length(scales) == 0L) "No implemented analytic scalar coefficient for this family/panel combination." else
      if (gaussian) "Reliability of observed Gaussian-score averages." else
        "Reliability of latent-response averages; not label proportions, majority votes, or ordinal-score averages.",
    notes = notes), class = "gt_preflight")
  # Present only for a design that declares batches, so every other preflight
  # object is unchanged.
  if (!is.null(batch_audit)) {
    report$batch_audit <- batch_audit
    report$notes <- c(report$notes, .GT_BATCH_NOTE)
  }
  report
}

print.gt_preflight <- function(x, ...) {
  cat("G-theory preflight:", x$observations, "rows |", x$engine, "\n")
  cat("Observed levels:", paste(paste(names(x$observed_counts), x$observed_counts, sep = "="), collapse = ", "), "\n")
  cat("Retained random sources:", x$source_counts[["retained"]],
      "| Random dimensions:", x$random_dimension,
      "| Model parameters:", x$parameters[["total"]], "\n")
  cat("Structural/resource checks:", if (x$fitting_feasible) "PASS" else "BLOCKED", "\n")
  cat("Panel cells (observed coded levels):\n")
  print(x$panel_audit$summary[c("status", "cell_count_exact")], row.names = FALSE)
  cat("Audit examples returned:", paste(paste(x$panel_audit$examples$table,
    x$panel_audit$examples$shown, sep = "="), collapse = ", "),
    "| Per-table limit:", x$panel_audit$examples$limit[[1L]], "\n")
  if (any(x$panel_audit$examples$truncated)) cat("Some audit example tables are truncated; see panel_audit$examples.\n")
  if (!is.null(x$batch_audit)) {
    b <- x$batch_audit
    count <- function(n) format(n, scientific = FALSE, trim = TRUE)
    dependence <- paste0("equal dependence within a call",
      if (b$sequential) paste0(" | sequential reach ", b$sequential) else "",
      if (b$neighbor) paste0(" | neighbour reach ", b$neighbor) else "",
      if (!is.null(b$by)) paste0(" | may differ by ", b$by) else "")
    if (identical(b$membership, "recorded")) {
      cat("Recorded calls: ", count(b$calls), " in column ", sQuote(b$id), " | ", b$batches,
          " distinct batches of up to ", b$size, " items | ",
          if (b$fixed_composition && b$fixed_order) "the same batches and order in every condition" else
            if (b$fixed_composition) "the same batches in every condition, in more than one order" else
              "batches differ between conditions",
          " | ", dependence, "\n", sep = "")
      if (!b$equal_sized) cat(count(b$short_calls), " call(s) hold fewer than ", b$size,
          " items; the smallest holds ", b$smallest_call, "\n", sep = "")
    } else {
      cat("Implied calls: ", b$batches, " batches of ", b$size, " items",
          if (!b$equal_sized) paste0(" (the last holds ", b$smallest_call, ")") else "",
          " x ", b$conditions, " conditions",
          if (b$replicates > 1) paste0(" x ", b$replicates, " repeats") else "",
          " = ", count(b$calls), " calls | ", dependence, "\n", sep = "")
      cat("Batch membership is inferred from item order, not read from recorded calls;",
          "items removed after collection cannot be detected.\n")
    }
    if (!b$consistent) cat("Batch declaration does not describe these data:", paste(b$problems, collapse = "; "), "\n")
    else if (isTRUE(b$stored_rows$checked))
      cat("Stored rows agree with the declared batches in", b$stored_rows$batches_agree, "of",
          b$stored_rows$conditions, "conditions; with their order in", b$stored_rows$order_agrees, "\n")
  }
  cat("Outcome profiles:", length(x$outcome_profile),
    "| See outcome_profile for category coverage, numeric summaries, and descriptive group variation.\n")
  if (!x$fitting_feasible) print(x$checks[!x$checks$passed, , drop = FALSE], row.names = FALSE)
  cat("Supported reliability scale:", if (length(x$supported_reliability_scales))
    paste(x$supported_reliability_scales, collapse = ", ") else "none", "\n")
  cat(x$scale_interpretation, "\n")
  cat(x$notes[[1L]], "\n")
  invisible(x)
}

.gt_preflight_plot_outcomes <- function(x, outcome, max_categories, max_variables, max_label_chars, ...) {
  if (is.null(outcome)) {
    if (length(x$outcomes) != 1L)
      stop("Select one outcome by name for the outcome coverage plot.", call. = FALSE)
    outcome <- x$outcomes[[1L]]
  }
  if (!is.character(outcome) || length(outcome) != 1L || is.na(outcome) || !outcome %in% x$outcomes)
    stop("outcome must name exactly one preflight outcome.", call. = FALSE)
  profile <- x$outcome_profile[[outcome]]
  if (profile$family == "gaussian")
    stop("Gaussian outcomes have no category heatmap; inspect outcome_profile summary and by_variable tables.",
         call. = FALSE)
  categories <- head(profile$categories$category, max_categories)
  variables <- head(profile$by_variable$variable, max_variables)
  nc <- length(categories)
  nv <- length(variables)
  coverage <- matrix(profile$category_coverage$proportion,
    nrow = nrow(profile$categories), ncol = nrow(profile$by_variable))
  coverage <- coverage[seq_len(nc), seq_len(nv), drop = FALSE]
  abbreviate_label <- function(labels) {
    abbreviated <- ifelse(nchar(labels) > max_label_chars,
      paste0(substr(labels, 1L, max_label_chars - 3L), "..."), labels)
    # Numbered labels keep duplicate abbreviations unambiguous and map back to
    # their declaration/design order in the complete profile tables.
    paste0(seq_along(labels), ". ", abbreviated)
  }
  category_labels <- abbreviate_label(categories)
  variable_labels <- abbreviate_label(variables)
  nested <- profile$by_variable$grouping_scope[seq_len(nv)] == "declared_parent_scoped"
  variable_labels[nested] <- paste0(variable_labels[nested], "*")
  old_margins <- graphics::par("mar")
  on.exit(graphics::par(mar = old_margins), add = TRUE)
  line_height <- graphics::par("cin")[[2L]] * graphics::par("mex")
  margins <- old_margins
  margins[[1L]] <- max(margins[[1L]],
    (max(graphics::strwidth(variable_labels, units = "inches", cex = 0.7)) + 0.5) / line_height)
  margins[[2L]] <- max(margins[[2L]],
    (max(graphics::strwidth(category_labels, units = "inches", cex = 0.7)) + 0.3) / line_height)
  graphics::par(mar = margins)
  title_outcome <- if (nchar(outcome) > max_label_chars)
    paste0(substr(outcome, 1L, max_label_chars - 3L), "...") else outcome
  defaults <- list(x = 0:nv, y = 0:nc, z = t(coverage[nc:1L, , drop = FALSE]),
    zlim = c(0, 1), col = grDevices::colorRampPalette(c("#F4F7FA", "#296A96"))(51L),
    xlab = "", ylab = "", axes = FALSE, main = paste("Category coverage:", title_outcome))
  arguments <- list(...)
  defaults[names(arguments)] <- NULL
  do.call(graphics::image, c(defaults, arguments))
  graphics::axis(1L, at = seq_len(nv) - 0.5, labels = variable_labels, las = 2L, cex.axis = 0.7)
  graphics::axis(2L, at = seq_len(nc) - 0.5, labels = rev(category_labels), las = 1L, cex.axis = 0.7)
  if (nv <= 8L && nc <= 12L) for (i in seq_len(nv)) for (j in seq_len(nc)) {
    value <- coverage[j, i]
    label <- if (value == 0) "0%" else if (value == 1) "100%" else
      if (value >= 0.9995) "<100%" else if (value < 0.0001) "<0.01%" else
      paste0(format(100 * value, digits = 3L, trim = TRUE), "%")
    graphics::text(i - 0.5, nc - j + 0.5, label,
      col = if (value >= 0.6) "white" else "#152A3A", cex = 0.7)
  }
  truncated <- nc < nrow(profile$categories) || nv < nrow(profile$by_variable)
  shown <- paste0(nc, "/", nrow(profile$categories), " categories; ", nv, "/",
    nrow(profile$by_variable), " variables", if (truncated) " (truncated)" else "",
    if (any(nested)) "; * parent-scoped" else "")
  graphics::mtext(shown, side = 3L, line = 0.3, cex = 0.65)
  graphics::mtext("Groups with category (0-100%); darker = higher. Descriptive only.",
    side = 1L, line = margins[[1L]] - 1, cex = 0.65)
  invisible(x)
}

plot.gt_preflight <- function(x, type = c("cells", "sources", "outcomes"), max_sources = 20L,
                             outcome = NULL, max_categories = 12L, max_variables = 8L,
                             max_label_chars = 18L, ...) {
  type <- match.arg(type)
  max_sources <- .gt_preflight_example_limit(max_sources, "max_sources", zero = FALSE)
  max_categories <- .gt_preflight_example_limit(max_categories, "max_categories", zero = FALSE)
  max_variables <- .gt_preflight_example_limit(max_variables, "max_variables", zero = FALSE)
  max_label_chars <- .gt_preflight_example_limit(max_label_chars, "max_label_chars", zero = FALSE)
  if (max_label_chars < 4L) stop("max_label_chars must be at least 4.", call. = FALSE)
  if (type == "outcomes") return(.gt_preflight_plot_outcomes(x, outcome, max_categories,
    max_variables, max_label_chars, ...))
  if (type == "cells") {
    plotted <- x$panel_audit$summary
    heights <- plotted$cell_count
    labels <- c("Complete", "Under-replicated", "Over-replicated", "Missing")
    title <- "Panel cells: observed coded levels"
    axis <- "Full cells (mutually exclusive categories)"
    subtitle <- "Complete = declared replication; not a fit-quality check."
  } else {
    order <- order(-x$sources$random_dimension, seq_len(nrow(x$sources)))
    plotted <- x$sources[head(order, max_sources), , drop = FALSE]
    heights <- plotted$random_dimension
    labels <- plotted$source
    title <- "Source dimensions: observed coded levels"
    axis <- "Random-effect dimensions (Gaussian: conceptual)"
    subtitle <- paste0("Showing ", nrow(plotted), " of ", nrow(x$sources),
      " sources; largest first", if (nrow(plotted) < nrow(x$sources)) "; truncated" else "",
      ". Not a fit-quality check.")
  }
  if (any(!is.finite(heights)))
    stop("Cell counts exceed the finite plotting range; inspect panel_audit$summary$cell_count_exact.", call. = FALSE)
  arguments <- list(...)
  defaults <- list(horiz = TRUE, las = 1L, names.arg = rev(labels), main = title,
                   xlab = axis, sub = subtitle, col = "steelblue", border = NA,
                   cex.names = 0.8, cex.sub = 0.8)
  label_counts <- type == "cells" && !isFALSE(arguments$horiz) && !isFALSE(arguments$plot)
  if (label_counts) {
    largest <- max(heights)
    defaults$xlim <- c(0, largest + min(largest * 0.15, (.Machine$double.xmax - largest) / 2))
  }
  old_margins <- graphics::par("mar")
  on.exit(graphics::par(mar = old_margins), add = TRUE)
  margins <- old_margins
  line_height <- graphics::par("cin")[[2L]] * graphics::par("mex")
  label_width <- max(graphics::strwidth(labels, units = "inches", cex = 0.8)) + 0.45
  margins[[2L]] <- max(margins[[2L]], min(label_width,
    graphics::par("fin")[[1L]] * 0.4) / line_height)
  graphics::par(mar = margins)
  defaults[names(arguments)] <- NULL
  positions <- do.call(graphics::barplot, c(list(height = rev(heights)), defaults, arguments))
  if (label_counts) {
    count_labels <- vapply(heights, function(value)
      if (value > 1e12) paste0("~", format(value, digits = 3, scientific = TRUE)) else
        format(value, scientific = FALSE, trim = TRUE), character(1))
    graphics::text(rev(heights), positions, rev(count_labels), pos = 4L, offset = 0.35, cex = 0.8)
  }
  invisible(x)
}
