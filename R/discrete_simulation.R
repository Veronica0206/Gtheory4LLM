# Categorical design simulation. Source effects are Gaussian on the fitted
# latent predictor scale; observations retain their declared category labels.
# These helpers do not refit, quantify parameter uncertainty, or calibrate a
# Laplace approximation. They never condition on fitted random-effect modes.

.gt_discrete_sim_model <- function(fit, components = NULL, means = NULL) {
  if (!inherits(fit, "gt_fit") || !isTRUE(fit$numerically_accepted) || !isTRUE(fit$converged))
    stop("Categorical simulation requires an explicitly numerically accepted fit.", call. = FALSE)
  outcomes <- fit$outcomes
  families <- fit$families
  if (!length(outcomes) || anyNA(outcomes) || anyDuplicated(outcomes) ||
      !is.list(families) || !identical(names(families), outcomes) ||
      any(!vapply(families, function(x) inherits(x, "gt_family") &&
        length(x$family) == 1L && x$family %in% c("binary", "ordinal", "categorical"), logical(1))))
    stop("Categorical simulation requires resolved discrete families for every outcome.", call. = FALSE)
  mapping <- fit$link_dimensions
  fields <- c("outcome", "family", "link", "dimension", "category", "reference")
  if (!is.data.frame(mapping) || !all(fields %in% names(mapping)) || !nrow(mapping) ||
      anyNA(mapping[c("outcome", "family", "link", "dimension")]) ||
      any(!nzchar(mapping$dimension)) || anyDuplicated(mapping$dimension) ||
      !setequal(mapping$outcome, outcomes))
    stop("The fitted latent-dimension mapping is missing or inconsistent.", call. = FALSE)
  dimensions <- as.character(mapping$dimension)
  q <- length(dimensions)
  if (64 * as.double(q)^2 > 512 * 1024^2)
    stop("Categorical simulation covariance workspace exceeds the 512 MiB limit.", call. = FALSE)
  blocks <- stats::setNames(vector("list", length(outcomes)), outcomes)
  for (outcome in outcomes) {
    family <- families[[outcome]]
    family <- gt_family(family$family, family$link, family$levels, family$reference)
    levels <- family$levels
    index <- which(mapping$outcome == outcome)
    if (is.null(levels) || any(mapping$family[index] != family$family) ||
        any(mapping$link[index] != family$link))
      stop("Simulation requires consistent resolved family levels and links.", call. = FALSE)
    if (family$family == "categorical") {
      reference <- family$reference
      if (is.null(reference)) reference <- levels[[1L]]
      categories <- as.character(mapping$category[index])
      if (length(index) != length(levels) - 1L || anyNA(categories) || anyDuplicated(categories) ||
          !setequal(categories, setdiff(levels, reference)) ||
          anyNA(mapping$reference[index]) || any(mapping$reference[index] != reference))
        stop("Simulation nominal contrasts do not match the declared reference and categories.", call. = FALSE)
    } else {
      if (length(index) != 1L)
        stop("Binary and ordinal outcomes need one fitted latent dimension each.", call. = FALSE)
      reference <- NULL
      categories <- NULL
    }
    thresholds <- if (family$family == "ordinal") fit$thresholds[[outcome]] else NULL
    if (family$family == "ordinal" && (!is.numeric(thresholds) ||
        length(thresholds) != length(levels) - 1L || any(!is.finite(thresholds)) ||
        any(diff(thresholds) <= 0)))
      stop("Simulation requires finite, strictly ordered fitted thresholds.", call. = FALSE)
    blocks[[outcome]] <- list(outcome = outcome, family = family$family, link = family$link,
      dims = index, levels = levels, reference = reference, categories = categories, thresholds = thresholds)
  }
  design <- fit$design
  if (!inherits(design, "gt_design")) stop("Simulation requires a retained design.", call. = FALSE)
  variables <- c(design$object, design$facets)
  panel <- .gt_reliability_panel(fit, variables)
  if (!identical(names(panel$counts), variables) || any(!is.finite(panel$counts)) ||
      any(panel$counts < 2 | panel$counts != floor(panel$counts)))
    stop("Simulation requires recorded object and facet counts of at least two.", call. = FALSE)
  replicates <- .gt_sim_integer(design$replicates, "design replicates")
  call <- NULL
  if (!is.null(design$batch)) {
    status <- .gt_batch_status(design)
    if (!identical(status$status, "modelled") || length(status$not_modelled))
      stop("Categorical simulation requires a modelled equal fixed call layout; declared unmodelled batches cannot be simulated.",
           call. = FALSE)
    call <- design$batch_model
    n <- panel$counts[[design$object]]
    membership <- call$item_batches
    if (replicates != 1L || panel$rows != prod(panel$counts) || any(panel$cell_replication != 1L) ||
        length(call$item_levels) != n || anyNA(call$item_levels) || anyDuplicated(call$item_levels) ||
        length(membership) != n || anyNA(membership))
      stop("Simulation needs a retained complete one-observation fixed call layout.", call. = FALSE)
    membership <- match(membership, unique(membership))
    if (max(membership) != call$batches || any(tabulate(membership) != call$size))
      stop("The retained call membership does not match its equal batch size.", call. = FALSE)
    call$item_batches <- membership
    auxiliary <- c(design$batch$id, design$batch$order)
    if (any(auxiliary %in% c(variables, outcomes)) || anyDuplicated(auxiliary))
      stop("Simulation call identifier and order columns must be distinct from model columns.", call. = FALSE)
    if (is.null(design$batch$id) && is.null(design$batch$order) &&
        !identical(membership, rep(seq_len(call$batches), each = call$size)))
      stop("The inferred call layout cannot be reproduced from the retained item order.", call. = FALSE)
  }
  sources <- .gt_fitted_sources(design)
  members <- design$term_members
  if (!length(sources) || anyDuplicated(sources) || !setequal(names(members), design$terms) ||
      any(!vapply(members, function(x) length(x) > 0L && !anyNA(x) &&
        !anyDuplicated(x) && all(x %in% variables), logical(1))))
    stop("Simulation requires complete retained random-source grouping terms.", call. = FALSE)
  scenario <- !is.null(components) || !is.null(means)
  if (is.null(components)) components <- fit$covariance_components
  if (!is.list(components) || is.null(names(components)) || anyDuplicated(names(components)) ||
      !setequal(names(components), sources))
    stop("components must name every fitted discrete source, without a Gaussian Residual.", call. = FALSE)
  .gt_d_validate_covariance_request(fit$covariance)
  roots <- stats::setNames(vector("list", length(sources)), sources)
  components <- components[sources]
  for (source in sources) {
    value <- components[[source]]
    if (!is.matrix(value) || !is.numeric(value) || is.complex(value) ||
        !identical(dim(value), c(q, q)) || any(!is.finite(value)))
      stop("Each categorical source covariance must be a finite latent-dimension matrix.", call. = FALSE)
    if (!is.null(rownames(value)) || !is.null(colnames(value))) {
      valid <- function(x) !is.null(x) && !anyNA(x) && !anyDuplicated(x) && setequal(x, dimensions)
      if (!valid(rownames(value)) || !valid(colnames(value)))
        stop("Covariance axes must name every fitted latent dimension exactly once.", call. = FALSE)
      value <- value[dimensions, dimensions, drop = FALSE]
    }
    tolerance <- 1e-10 * max(1, max(abs(value)))
    if (max(abs(value - t(value))) > tolerance)
      stop("Simulation covariance must be symmetric: ", source, ".", call. = FALSE)
    if (fit$covariance == "diagonal" && any(abs(value[row(value) != col(value)]) > tolerance))
      stop("Simulation covariance must preserve the fitted diagonal structure.", call. = FALSE)
    decomposition <- eigen((value + t(value)) / 2, symmetric = TRUE)
    if (any(!is.finite(decomposition$values)) || min(decomposition$values) < -tolerance)
      stop("Simulation covariance must be positive semidefinite: ", source, ".", call. = FALSE)
    root <- sweep(decomposition$vectors, 2L, sqrt(pmax(0, decomposition$values)), "*")
    roots[[source]] <- root
    components[[source]] <- tcrossprod(root)
    dimnames(components[[source]]) <- list(dimensions, dimensions)
  }
  if (is.null(means)) means <- fit$means
  if (!is.numeric(means) || is.complex(means) || length(means) != q || any(!is.finite(means)) ||
      is.null(names(means)) || anyNA(names(means)) || anyDuplicated(names(means)) ||
      !setequal(names(means), dimensions))
    stop("means must name every fitted latent dimension exactly once.", call. = FALSE)
  means <- means[dimensions]
  ordinal <- unlist(lapply(blocks, function(x) if (x$family == "ordinal") x$dims else integer()))
  if (length(ordinal) && any(means[ordinal] != 0))
    stop("Ordinal latent intercepts must remain zero; location is in the fitted thresholds.", call. = FALSE)
  structure(list(design = design, outcomes = outcomes, families = families, blocks = blocks,
    dimensions = dimensions, q = q, counts = panel$counts, replicates = replicates,
    components = components, roots = roots, means = means, members = members, call = call,
    covariance = fit$covariance,
    parameter_source = if (scenario) "specified_parameter_scenario" else "fitted_model_plugin"),
    class = "gt_discrete_sim_model")
}

.gt_discrete_sim_allocation <- function(model, n_items, counts = NULL, max_rows = 1000000L) {
  if (!inherits(model, "gt_discrete_sim_model")) stop("Expected a categorical simulation model.", call. = FALSE)
  n_items <- .gt_sim_integer(n_items, "n_items", 2L)
  max_rows <- .gt_sim_integer(max_rows, "max_rows", 1L, 1000000L)
  allocation <- model$counts
  allocation[[model$design$object]] <- n_items
  if (!is.null(counts)) {
    if (!is.numeric(counts) || is.complex(counts) || !length(counts) || is.null(names(counts)) ||
        anyNA(names(counts)) || anyDuplicated(names(counts)) ||
        any(!names(counts) %in% model$design$facets) || any(!is.finite(counts)) ||
        any(counts < 1 | counts != floor(counts) | counts > .Machine$integer.max))
      stop("counts must uniquely name declared facets with positive integer counts.", call. = FALSE)
    allocation[names(counts)] <- counts
  }
  if (!is.null(model$call) && n_items != model$counts[[model$design$object]])
    stop("Fixed-call simulation retains the fitted item count and grouping.", call. = FALSE)
  rows <- prod(as.double(allocation)) * model$replicates
  if (!is.finite(rows) || rows > max_rows)
    stop("Simulation rows exceed max_rows; reduce the proposed allocation.", call. = FALSE)
  .gt_discrete_sim_resources(model, allocation, 1L)
  allocation
}

.gt_discrete_sim_resources <- function(model, allocation, n_panels) {
  if (!is.numeric(allocation) || !identical(names(allocation), names(model$counts)) ||
      any(!is.finite(allocation)) || any(allocation < 1 | allocation != floor(allocation)) ||
      allocation[[model$design$object]] < 2)
    stop("Invalid categorical simulation allocation.", call. = FALSE)
  rows <- prod(as.double(allocation)) * model$replicates
  if (!is.finite(rows) || rows > 1000000)
    stop("Categorical simulation exceeds one million rows per panel.", call. = FALSE)
  if (!is.null(model$call) && allocation[[model$design$object]] != length(model$call$item_batches))
    stop("Fixed-call simulation retains the fitted item count and grouping.", call. = FALSE)
  groups <- sum(vapply(model$members, function(x) prod(as.double(allocation[x])), numeric(1)))
  if (!is.null(model$call)) groups <- groups + model$call$batches * prod(allocation[model$design$facets])
  categories <- sum(vapply(model$blocks, function(x) length(x$levels), integer(1)))
  bytes <- 8 * (rows * n_panels * (2 * length(allocation) + 4 * model$q +
    2 * categories + 2 * length(model$outcomes)) + groups * model$q * (n_panels + 1) + 4 * model$q^2)
  if (!is.finite(bytes) || bytes > 512 * 1024^2)
    stop("Estimated categorical simulation workspace exceeds the 512 MiB limit.", call. = FALSE)
  invisible(list(rows = rows, estimated_bytes = bytes))
}

# The returned columns are in substantive declared category order, including
# nominal reference categories. No numeric category ordering is introduced.
.gt_discrete_sim_probabilities <- function(model, eta) {
  if (!is.matrix(eta) || !is.numeric(eta) || ncol(eta) != model$q || !nrow(eta) ||
      any(!is.finite(eta))) stop("Invalid simulated latent predictors.", call. = FALSE)
  answer <- lapply(model$blocks, function(block) {
    if (block$family == "binary") {
      cdf <- if (block$link == "probit") stats::pnorm else stats::plogis
      result <- cbind(cdf(eta[, block$dims], lower.tail = FALSE), cdf(eta[, block$dims]))
    } else if (block$family == "ordinal") {
      result <- .gt_d_ordinal_probabilities(eta[, block$dims], block$thresholds, block$link)
    } else {
      predictors <- matrix(0, nrow(eta), length(block$levels), dimnames = list(NULL, block$levels))
      predictors[, match(block$categories, block$levels)] <- eta[, block$dims, drop = FALSE]
      result <- exp(predictors - apply(predictors, 1L, max))
    }
    if (any(!is.finite(result)) || any(result < 0) || any(rowSums(result) <= 0))
      stop("Simulated response probabilities are invalid.", call. = FALSE)
    result <- result / rowSums(result)
    colnames(result) <- block$levels
    result
  })
  answer
}

# Caller owns the RNG scope. Sharing means the identical source realization at
# corresponding coded levels in each panel; unshared sources are independently
# redrawn. Default: stable object main effects, redrawn instrumentation effects,
# interactions and calls. Observations are always conditionally independent.
.gt_discrete_sim_panels <- function(model, allocation, n_panels = 2L,
                                    shared_sources = intersect(model$design$object, names(model$components))) {
  if (!inherits(model, "gt_discrete_sim_model")) stop("Expected a categorical simulation model.", call. = FALSE)
  n_panels <- .gt_sim_integer(n_panels, "n_panels", 1L, 1000L)
  if (!is.character(shared_sources) || anyNA(shared_sources) || anyDuplicated(shared_sources) ||
      any(!shared_sources %in% names(model$components)))
    stop("shared_sources must uniquely name fitted random sources.", call. = FALSE)
  .gt_discrete_sim_resources(model, allocation, n_panels)
  panel <- expand.grid(lapply(unname(allocation), seq_len), KEEP.OUT.ATTRS = FALSE,
                       stringsAsFactors = FALSE)
  names(panel) <- names(allocation)
  if (model$replicates > 1L) panel <- panel[rep(seq_len(nrow(panel)), each = model$replicates), , drop = FALSE]
  rownames(panel) <- NULL
  groupings <- lapply(model$members, function(members) {
    keys <- .gt_tuple_key(panel, members)
    match(keys, unique(keys))
  })
  if (!is.null(model$call)) {
    item <- panel[[model$design$object]]
    membership <- model$call$item_batches
    keys <- paste(membership[item], .gt_tuple_key(panel, model$design$facets), sep = ":")
    groupings[[.GT_CALL_TERM]] <- match(keys, unique(keys))
    declaration <- model$design$batch
    if (!is.null(declaration$id)) panel[[declaration$id]] <- groupings[[.GT_CALL_TERM]]
    if (!is.null(declaration$order)) {
      item_order <- order(order(membership, seq_along(membership)))
      panel[[declaration$order]] <- item_order[item]
    }
  }
  draw <- function(source) {
    levels <- max(groupings[[source]])
    matrix(stats::rnorm(levels * model$q), levels, model$q) %*% t(model$roots[[source]])
  }
  shared <- stats::setNames(lapply(shared_sources, draw), shared_sources)
  panels <- probabilities <- vector("list", n_panels)
  for (r in seq_len(n_panels)) {
    eta <- matrix(rep(model$means, each = nrow(panel)), nrow(panel), model$q)
    for (source in names(model$components)) {
      effects <- if (source %in% shared_sources) shared[[source]] else draw(source)
      eta <- eta + effects[groupings[[source]], , drop = FALSE]
    }
    probabilities[[r]] <- .gt_discrete_sim_probabilities(model, eta)
    data <- panel
    for (outcome in model$outcomes) {
      block <- model$blocks[[outcome]]
      probability <- probabilities[[r]][[outcome]]
      uniforms <- stats::runif(nrow(panel))
      cumulative <- numeric(nrow(panel))
      category <- rep.int(1L, nrow(panel))
      for (k in seq_len(length(block$levels) - 1L)) {
        cumulative <- cumulative + probability[, k]
        category <- category + (uniforms >= cumulative)
      }
      data[[outcome]] <- factor(block$levels[category], levels = block$levels,
                                ordered = block$family == "ordinal")
    }
    panels[[r]] <- data
  }
  call_layout <- if (is.null(model$call)) NULL else list(modelled = TRUE, term = .GT_CALL_TERM,
    batches = model$call$batches, size = model$call$size,
    calls = model$call$batches * prod(allocation[model$design$facets]),
    item_levels = seq_len(allocation[[model$design$object]]),
    item_batches = model$call$item_batches, source_item_levels = model$call$item_levels)
  list(panels = panels, probabilities = probabilities, allocation = allocation,
    shared_sources = shared_sources, redrawn_sources = setdiff(names(model$components), shared_sources),
    replicates = model$replicates, call_layout = call_layout)
}

.gt_simulate_discrete <- function(fit, n_items, counts, seed, components, means, max_rows) {
  model <- .gt_discrete_sim_model(fit, components, means)
  allocation <- .gt_discrete_sim_allocation(model, n_items, counts, max_rows)
  draw <- .gt_sim_rng(seed, .gt_discrete_sim_panels(model, allocation, 1L, shared_sources = character()))
  result <- draw$panels[[1L]]
  attr(result, "simulation") <- list(purpose = "design_simulation", family = "categorical",
    parameter_source = model$parameter_source, seed = as.integer(seed),
    n_items = allocation[[model$design$object]], counts = allocation[model$design$facets],
    replicates = model$replicates, means = model$means, thresholds = fit$thresholds,
    components = model$components, covariance = model$covariance, families = model$families,
    link_dimensions = fit$link_dimensions, design = model$design, call_layout = draw$call_layout,
    interpretation = paste("Fresh Gaussian source effects on the fitted latent scale and categorical observations;",
      "complete future coded panel, conditional on fitted or specified parameters.",
      "No missing outcomes are imputed and no parameter uncertainty or approximation calibration is supplied."))
  result
}
