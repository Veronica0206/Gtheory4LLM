# Analytic observed Gaussian and identified latent binary/ordinal coefficients.

#' Declare explicit weights for a composite on an already specified score scale
#' @export
gt_score <- function(weights) {
  if (!is.numeric(weights) || !length(weights) || any(!is.finite(weights)) ||
      is.null(names(weights)) || anyNA(names(weights)) || any(!nzchar(names(weights))) ||
      anyDuplicated(names(weights)) || !any(weights != 0))
    stop("weights must be a finite, uniquely named vector with at least one nonzero entry.", call. = FALSE)
  structure(list(weights = weights, normalization = "as_supplied"), class = "gt_score")
}

.gt_reliability_context <- function(fit, scale) {
  if (!inherits(fit, "gt_fit")) stop("Expected a gt_fit object.", call. = FALSE)
  if (isFALSE(fit$converged) || isFALSE(fit$numerically_accepted) ||
      (!is.null(fit$engine) && identical(fit$engine, "dense_joint_discrete_laplace") &&
       !isTRUE(fit$numerically_accepted)))
    stop("Reliability and D studies require a numerically converged fit. Inspect gt_diagnostics(fit) and resolve the fitting failure first.", call. = FALSE)
  types <- vapply(fit$families, `[[`, character(1), "family")
  gaussian <- all(types == "gaussian")
  if (is.null(scale)) {
    if (!gaussian) stop("For binary/ordinal fits, explicitly request scale='latent'; observed-score coefficients need a separate integration method.", call. = FALSE)
    scale <- "observed"
  }
  if (!is.character(scale) || length(scale) != 1L || is.na(scale)) stop("Specify one coefficient scale.", call. = FALSE)
  if (any(types == "categorical"))
    stop("Unordered categorical outcomes have no default scalar G/Phi. Define a substantive score or category-probability estimand before computing reliability; this is not implemented yet.", call. = FALSE)
  if ((gaussian && scale != "observed") || (!gaussian && scale != "latent"))
    stop("This implementation supports observed Gaussian coefficients and identified latent binary/ordinal coefficients only.", call. = FALSE)
  dimensions <- c(fit$design$object, fit$design$facets)
  counts <- stats::setNames(vapply(fit$data[dimensions], function(x) length(unique(x)), integer(1)), dimensions)
  if (nrow(fit$data) != prod(counts) * fit$design$replicates)
    stop("Analytic coefficients currently require a complete balanced coded panel; unbalanced allocations need separate D-study integration.", call. = FALSE)
  cell_counts <- table(.gt_tuple_key(fit$data, dimensions))
  if (any(cell_counts != fit$design$replicates))
    stop("Analytic coefficients require the declared equal within-cell replication.", call. = FALSE)
  components <- fit$covariance_components
  if (!gaussian) {
    latent_variance <- vapply(fit$families, function(f)
      if (f$link == "probit") 1 else pi^2 / 3, numeric(1))
    components$Residual <- diag(latent_variance, nrow = length(latent_variance))
    dimnames(components$Residual) <- list(fit$outcomes, fit$outcomes)
  }
  expected <- c(fit$design$terms, "Residual")
  if (!all(expected %in% names(components))) stop("Missing fitted covariance components.", call. = FALSE)
  if (any(vapply(components[expected], function(x)
    !is.matrix(x) || !identical(dim(x), c(length(fit$outcomes), length(fit$outcomes))) || any(!is.finite(x)), logical(1))))
    stop("Source covariance dimensions do not match the outcome dimensions.", call. = FALSE)
  list(components = components, counts = counts[fit$design$facets], scale = scale,
       gaussian = gaussian, replicates = fit$design$replicates)
}

#' Compute G and Phi under a declared balanced score design
#' @param scale observed for Gaussian; explicitly latent for binary/ordinal.
#' @param score Optional gt_score object; per-trait results are always returned.
#' @param design Optional named positive integer instrumentation counts.
#' @export
gt_reliability <- function(fit, scale = NULL, score = NULL, design = NULL) {
  context <- .gt_reliability_context(fit, scale)
  counts <- context$counts
  if (!is.null(design)) {
    if (!is.numeric(design) || is.null(names(design)) || anyNA(names(design)) ||
        anyDuplicated(names(design)) || any(!names(design) %in% names(counts)) ||
        any(!is.finite(design)) || any(design < 1 | design != floor(design)))
      stop("design must contain named positive integer counts of declared instrumentation facets.", call. = FALSE)
    counts[names(design)] <- design
  }
  .gt_reliability_kernel(fit, context, counts, score)
}

# Context is validated once per D study, independently of grid size.
.gt_reliability_kernel <- function(fit, context, counts, score) {
  matrices <- context$components
  universe <- matrices[[fit$design$object]]
  relative <- matrices$Residual / (prod(counts) * context$replicates)
  absolute <- relative
  for (term in setdiff(fit$design$terms, fit$design$object)) {
    members <- fit$design$term_members[[term]]
    error <- matrices[[term]] / prod(counts[setdiff(members, fit$design$object)])
    absolute <- absolute + error
    if (fit$design$object %in% members) relative <- relative + error
  }
  ratio <- function(u, e) ifelse(is.finite(u + e) & u + e > 0, u / (u + e), NA_real_)
  per_trait <- data.frame(outcome = fit$outcomes,
                         Erho2 = ratio(diag(universe), diag(relative)),
                         Phi = ratio(diag(universe), diag(absolute)), stringsAsFactors = FALSE)
  composite <- NULL
  if (!is.null(score)) {
    if (!inherits(score, "gt_score") || !setequal(names(score$weights), fit$outcomes))
      stop("score must explicitly weight every outcome exactly once.", call. = FALSE)
    w <- score$weights[fit$outcomes]
    q <- function(m) as.numeric(crossprod(w, m %*% w))
    composite <- data.frame(Erho2 = ratio(q(universe), q(relative)),
                            Phi = ratio(q(universe), q(absolute)))
  }
  list(per_trait = per_trait, composite = composite,
       universe_covariance = universe, relative_error_covariance = relative,
       absolute_error_covariance = absolute, scale = context$scale, score = score,
       design = counts, replicates = context$replicates,
       extrapolated = any(counts > context$counts),
       interpretation = if (context$gaussian) "Gaussian observed-score coefficient" else
         "Identified latent-response coefficient; not reliability of binary proportions or ordinal observed scores",
       fit_diagnostics = gt_diagnostics(fit))
}

#' Evaluate balanced allocations using the analytic coefficient definitions
#' @export
gt_dstudy <- function(fit, grid, scale = NULL, score = NULL) {
  context <- .gt_reliability_context(fit, scale)
  if (!is.data.frame(grid) || !nrow(grid) || !ncol(grid) || anyDuplicated(names(grid)) ||
      any(!names(grid) %in% names(context$counts)) ||
      !all(vapply(grid, is.numeric, logical(1))))
    stop("grid must be a nonempty numeric data frame of declared instrumentation facet counts.", call. = FALSE)
  values <- as.matrix(grid)
  if (any(!is.finite(values)) || any(values < 1 | values != floor(values)))
    stop("D-study counts must be positive finite integers.", call. = FALSE)
  allocation <- as.data.frame(as.list(context$counts), check.names = FALSE)[rep(1L, nrow(grid)), , drop = FALSE]
  rownames(allocation) <- NULL
  allocation[names(grid)] <- grid
  result <- lapply(seq_len(nrow(grid)), function(i) {
    co <- .gt_reliability_kernel(fit, context,
      unlist(allocation[i, , drop = FALSE], use.names = TRUE), score)
    table <- data.frame(design_id = i, kind = "outcome", co$per_trait, stringsAsFactors = FALSE)
    if (!is.null(co$composite)) table <- rbind(table,
      data.frame(design_id = i, kind = "composite", outcome = "composite", co$composite))
    table
  })
  structure(list(allocations = allocation, results = do.call(rbind, result),
                 scale = context$scale, score = score,
                 measurements_per_object = apply(allocation, 1L, prod) * context$replicates,
                 extrapolated = apply(allocation, 1L, function(x) any(x > context$counts)),
                 fit_diagnostics = gt_diagnostics(fit)), class = "gt_dstudy")
}

plot.gt_dstudy <- function(x, coefficient = "Erho2", ...) {
  if (!coefficient %in% c("Erho2", "Phi")) stop("coefficient must be Erho2 or Phi.")
  tab <- x$results
  series <- interaction(tab$kind, tab$outcome, drop = TRUE)
  colors <- seq_len(nlevels(series))
  xx <- x$measurements_per_object[tab$design_id]
  graphics::plot(xx, tab[[coefficient]], col = colors[series], pch = 19,
                 xlab = "Measurements per object", ylab = paste(coefficient, "-", x$scale, "scale"), ...)
  graphics::legend("bottomright", legend = levels(series), col = colors, pch = 19, bty = "n")
  invisible(x)
}
