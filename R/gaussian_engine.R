# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Balanced Gaussian source-covariance likelihood using OpenMx.
# Each call creates an isolated lexical environment for this design's dimensions.
# Shared correlation policy: suppress entries whose variances are negligible
# relative to the corresponding observed-outcome scale (or the largest source
# variance when no external scale is supplied).
.gt_covariance_correlation <- function(M, tolerance = 1e-8, scale = NULL) {
  variances <- diag(M)
  if (is.null(scale)) scale <- rep(max(variances, 0), length(variances))
  valid <- variances > tolerance * scale
  valid <- valid & variances > 0
  result <- matrix(NA_real_, nrow(M), ncol(M), dimnames = dimnames(M))
  if (any(valid)) {
    result[valid, valid] <- M[valid, valid, drop = FALSE] /
      sqrt(outer(variances[valid], variances[valid]))
    result[valid, valid] <- pmax(-1, pmin(1, result[valid, valid]))
  }
  result
}

# Apply the transpose of the normalized R Helmert basis without allocating its
# n-by-n matrix. R's jth contrast is (-1,...,-1,j,0,...,0)/sqrt(j*(j+1)).
.gt_helmert_transform <- function(x) {
  if (!is.matrix(x) || !is.numeric(x) || nrow(x) < 2L)
    stop("Helmert input must be a numeric matrix with at least two rows.", call. = FALSE)
  n <- nrow(x)
  j <- seq_len(n - 1L)
  denominator <- sqrt(as.double(j) * (j + 1))
  result <- matrix(0, n, ncol(x))
  for (column in seq_len(ncol(x))) {
    cumulative <- cumsum(x[, column])
    result[1L, column] <- cumulative[n] / sqrt(n)
    result[-1L, column] <- (j * x[-1L, column] - cumulative[-n]) / denominator
  }
  result
}

# Conservative planning estimate for preparation's live arrays, indexing vectors,
# and stratum cross-products. It is a resource guard, not measured peak RSS; it
# excludes the caller's original data frame and downstream OpenMx objects.
.gt_gaussian_preparation_bytes <- function(N, D, n_axes) {
  8 * (10 * as.double(N) * D + (2 * n_axes + 10) * as.double(N) +
       2^n_axes * (D * D + 8))
}

# Warnings from a derivative-only diagnostic pass describe that pass, not the
# accepted optimizer run. Retain their exact text without changing acceptance.
.gt_gaussian_derivative_run <- function(model, silent = TRUE, run = OpenMx::mxRun) {
  messages <- character()
  failure <- NULL
  result <- tryCatch(withCallingHandlers(run(model, silent = silent),
    warning = function(w) {
      messages <<- c(messages, conditionMessage(w))
      invokeRestart("muffleWarning")
    }), error = function(e) {
      failure <<- conditionMessage(e)
      NULL
    })
  list(model = result, error = failure, warnings = messages)
}

# Wald machinery for the exact balanced Gaussian likelihood.
#
# The OpenMx fit function is -2 log L, so the free-parameter covariance matrix
# is 2 * H^-1 for the numerically differentiated Hessian H at the returned
# estimates. REML supplies restricted-likelihood curvature for the covariance
# parameters; ML supplies profile curvature, because the outcome means are
# profiled rather than free. Neither is a small-sample guarantee, and Wald
# theory does not hold for a component resting on a variance boundary. The
# engine therefore reports availability and boundary contact explicitly rather
# than silently returning an interval that does not cover.
.gt_gaussian_parameter_covariance <- function(hessian, interior, standard_errors = NULL) {
  unavailable <- function(reason) list(covariance = NULL, reason = reason, restricted = FALSE,
    openmx_agreement = NA_real_, condition_number = NA_real_)
  if (is.null(hessian) || !is.matrix(hessian) || !is.numeric(hessian) ||
      nrow(hessian) != ncol(hessian) || !nrow(hessian) || any(!is.finite(hessian)))
    return(unavailable("No finite numerically differentiated Hessian is available."))
  symmetric <- (hessian + t(hessian)) / 2
  invert <- function(M) {
    values <- eigen(M, symmetric = TRUE, only.values = TRUE)$values
    if (min(values) <= 0) return(list(inverse = NULL, smallest = min(values)))
    inverse <- tryCatch(chol2inv(chol(M)), error = function(e) NULL)
    if (is.null(inverse) || any(!is.finite(inverse)))
      return(list(inverse = NULL, smallest = min(values)))
    list(inverse = 2 * inverse, condition_number = max(values) / min(values), smallest = min(values))
  }
  full <- invert(symmetric)
  if (!is.null(full$inverse)) {
    covariance <- full$inverse
    dimnames(covariance) <- dimnames(hessian)
    # OpenMx computes the same quantity in its own standard-error step. Comparing
    # the two is a cheap independent check of this reconstruction, not a test of
    # whether the asymptotic approximation is appropriate for these data.
    agreement <- NA_real_
    if (!is.null(standard_errors)) {
      reported <- as.vector(standard_errors)
      ours <- sqrt(diag(covariance))
      if (length(reported) == length(ours) && all(is.finite(reported)))
        agreement <- max(abs(reported - ours) / pmax(1e-12, abs(ours)))
    }
    return(list(covariance = covariance, reason = NA_character_, restricted = FALSE,
                openmx_agreement = agreement, condition_number = full$condition_number))
  }
  smallest <- format(full$smallest, digits = 3, trim = TRUE)
  # A variance component resting on zero has no Wald standard error, and its
  # row makes the joint Hessian indefinite. Condition on those components being
  # held at zero and invert the interior block instead of discarding every
  # standard error. This is a different, narrower estimand; the caller labels it.
  if (!any(interior) || all(interior))
    return(unavailable(paste0("The estimated Hessian is not positive definite (smallest eigenvalue ",
      smallest, "); Wald standard errors are not defined here.")))
  block <- invert(symmetric[interior, interior, drop = FALSE])
  if (is.null(block$inverse))
    return(unavailable(paste0("Neither the full Hessian (smallest eigenvalue ", smallest,
      ") nor its interior block (smallest eigenvalue ",
      format(block$smallest, digits = 3, trim = TRUE),
      ") is positive definite; Wald standard errors are not defined here.")))
  covariance <- matrix(0, nrow(symmetric), ncol(symmetric), dimnames = dimnames(hessian))
  covariance[interior, interior] <- block$inverse
  list(covariance = covariance, reason = NA_character_, restricted = TRUE,
       openmx_agreement = NA_real_, condition_number = block$condition_number)
}

# Derivative of every unique (lower-triangular) source covariance entry with
# respect to the free parameters actually used by each covariance structure.
# diagonal: G[j, j] = s_j * v_j. pooled: G = v * I.
# unstructured: G = L L', so dG/dL[a, b] = E_ab L' + L E_ab'.
.gt_gaussian_component_jacobian <- function(model, algebra_names, types, outcomes,
                                            parameter_names) {
  D <- length(outcomes)
  index <- which(lower.tri(matrix(0, D, D), diag = TRUE), arr.ind = TRUE)
  entries <- do.call(rbind, lapply(names(types), function(g)
    data.frame(component = g, row = outcomes[index[, 1L]], column = outcomes[index[, 2L]],
               stringsAsFactors = FALSE)))
  jacobian <- matrix(0, nrow(entries), length(parameter_names),
                     dimnames = list(NULL, parameter_names))
  offset <- 0L
  for (g in names(types)) {
    nm <- algebra_names[[g]]
    type <- types[[g]]
    if (type == "diagonal") {
      scale <- diag(OpenMx::mxEvalByName(paste0(nm, "_scale"), model))
      for (j in seq_len(D)) {
        label <- paste0(nm, "_v", j)
        k <- which(index[, 1L] == j & index[, 2L] == j)
        if (label %in% parameter_names) jacobian[offset + k, label] <- scale[[j]]
      }
    } else if (type == "pooled") {
      label <- paste0(nm, "_v")
      for (j in seq_len(D)) {
        k <- which(index[, 1L] == j & index[, 2L] == j)
        if (label %in% parameter_names) jacobian[offset + k, label] <- 1
      }
    } else {
      L <- OpenMx::mxEvalByName(paste0(nm, "_L"), model)
      for (l in seq_len(nrow(index))) {
        label <- paste0(nm, "_l", l)
        if (!label %in% parameter_names) next
        a <- index[l, 1L]
        b <- index[l, 2L]
        jacobian[offset + seq_len(nrow(index)), label] <-
          (index[, 1L] == a) * L[index[, 2L], b] + (index[, 2L] == a) * L[index[, 1L], b]
      }
    }
    offset <- offset + nrow(index)
  }
  list(entries = entries, jacobian = jacobian, index = index)
}

# Assemble everything a delta-method consumer needs: the entry covariance
# matrix, per-variance standard errors, and an explicit availability record.
.gt_gaussian_uncertainty <- function(model, algebra_names, types, outcomes,
                                     components, hessian, standard_errors,
                                     boundary, estimator_label, check_hessian) {
  parameter_names <- names(OpenMx::omxGetParameters(model))
  record <- list(available = FALSE,
    reason = "Hessian diagnostics were disabled; rerun with check_hessian = TRUE.",
    method = "Delta method from the numerically differentiated -2 log likelihood Hessian (parameter covariance 2 * H^-1).",
    likelihood = estimator_label, boundary_components = names(boundary)[which(boundary)],
    restricted_to_interior = FALSE, fixed_components = character(),
    parameter_covariance = NULL, entries = NULL, jacobian = NULL,
    entry_covariance = NULL, variances = NULL,
    openmx_standard_error_agreement = NA_real_, hessian_condition_number = NA_real_,
    interpretation = paste("Asymptotic Wald standard errors for source variance components.",
      "They do not establish coverage in small designs and are not valid for a component at a variance boundary."))
  if (!check_hessian) return(record)
  # Each free parameter belongs to exactly one component; the algebra prefix and
  # its underscore identify it without re-deriving the structure-specific labels.
  owner <- rep(NA_character_, length(parameter_names))
  for (g in names(types)) {
    prefix <- paste0(algebra_names[[g]], "_")
    owner[startsWith(parameter_names, prefix)] <- g
  }
  if (anyNA(owner)) {
    record$reason <- "Free parameters could not be matched to their covariance components."
    return(record)
  }
  interior <- !unname(boundary[owner])
  # Index the Hessian by parameter name rather than trusting its row order.
  # Without usable labels there is no defensible mapping, so report that.
  aligned <- if (is.matrix(hessian) && identical(dim(hessian), rep.int(length(parameter_names), 2L)) &&
      !is.null(rownames(hessian)) && !is.null(colnames(hessian)) &&
      setequal(rownames(hessian), parameter_names) && setequal(colnames(hessian), parameter_names))
    hessian[parameter_names, parameter_names, drop = FALSE] else NULL
  if (is.null(aligned) && is.matrix(hessian) &&
      identical(dim(hessian), rep.int(length(parameter_names), 2L))) {
    record$reason <- "The numerically differentiated Hessian does not carry this model's free-parameter labels on both axes, so its parameter order cannot be verified."
    return(record)
  }
  inverted <- .gt_gaussian_parameter_covariance(aligned, interior, standard_errors)
  if (is.null(inverted$covariance)) {
    record$reason <- inverted$reason
    return(record)
  }
  mapping <- .gt_gaussian_component_jacobian(model, algebra_names, types, outcomes,
                                             parameter_names)
  entry_covariance <- mapping$jacobian %*% inverted$covariance %*% t(mapping$jacobian)
  labels <- paste0(mapping$entries$component, "[", mapping$entries$row, ",",
                   mapping$entries$column, "]")
  dimnames(entry_covariance) <- list(labels, labels)
  diagonal <- mapping$entries$row == mapping$entries$column
  fixed_components <- if (inverted$restricted) sort(unique(owner[!interior])) else character()
  variances <- data.frame(
    component = mapping$entries$component[diagonal],
    trait = mapping$entries$row[diagonal],
    variance = unlist(lapply(names(types), function(g) diag(components[[g]])), use.names = FALSE),
    std_error = sqrt(pmax(0, diag(entry_covariance)[diagonal])),
    row.names = NULL, stringsAsFactors = FALSE)
  variances$at_boundary <- unname(boundary[variances$component])
  # A component held at zero has no standard error. Reporting the structural
  # zero as a number would read as an estimate known without error.
  variances$std_error[variances$component %in% fixed_components] <- NA_real_
  record$available <- TRUE
  record$reason <- NA_character_
  record$restricted_to_interior <- inverted$restricted
  record$fixed_components <- fixed_components
  record$parameter_covariance <- inverted$covariance
  record$entries <- mapping$entries
  record$jacobian <- mapping$jacobian
  record$entry_covariance <- entry_covariance
  record$variances <- variances
  record$openmx_standard_error_agreement <- inverted$openmx_agreement
  record$hessian_condition_number <- inverted$condition_number
  if (inverted$restricted)
    record$interpretation <- paste("Asymptotic Wald standard errors conditional on the",
      "zero-variance component(s)", paste(fixed_components, collapse = ", "),
      "being held at zero, because the joint Hessian is indefinite there.",
      "They describe the remaining components only, and are not valid coverage statements in small designs.")
  record
}

.gt_gaussian_engine <- function(facet_names) {
  .gt_facet_names <- facet_names
  .gt_full_mask <- as.integer(2^length(facet_names) - 1)
  .gt_validate_facets <- function(facets) {
    if (!is.character(facets) || length(facets) != length(.gt_facet_names) ||
        anyNA(facets) || any(!nzchar(facets)) || is.null(names(facets)) ||
        anyDuplicated(facets) || anyDuplicated(names(facets)) ||
        !setequal(names(facets), .gt_facet_names))
      stop("facets must map every design variable to one unique data column.", call. = FALSE)
    facets[.gt_facet_names]
  }
  .gt_resolve_spec <- function(spec) {
    if (!is.character(spec) || !length(spec) || anyNA(spec))
      stop("spec must contain the design's canonical grouping terms.", call. = FALSE)
    groups <- vapply(spec, function(term) {
      parts <- strsplit(term, ":", fixed = TRUE)[[1L]]
      if (!length(parts) || any(!parts %in% .gt_facet_names) || anyDuplicated(parts))
        stop("Invalid Gaussian random-source term: ", term, call. = FALSE)
      paste(.gt_facet_names[.gt_facet_names %in% parts], collapse = ":")
    }, character(1), USE.NAMES = FALSE)
    if (anyDuplicated(groups) || !.gt_facet_names[[1L]] %in% groups)
      stop("Random sources must be unique and include the object main effect.", call. = FALSE)
    if (paste(.gt_facet_names, collapse = ":") %in% groups)
      stop("The full-cell random source is aliased with Residual without replication.", call. = FALSE)
    groups
  }
.gt_default_facets <- setNames(.gt_facet_names, .gt_facet_names)
.gt_mask <- function(group) {
  sum(2L ^ (match(strsplit(group, ":", fixed = TRUE)[[1L]], .gt_facet_names) - 1L))
}
.gt_bits <- function(mask) as.logical(bitwAnd(as.integer(mask), 2L ^ (seq_along(.gt_facet_names) - 1L)))
.gt_error <- function(...) stop(..., call. = FALSE)

# Prepare sufficient cross-products using orthonormal factorial contrasts.
#
# Requires one complete observation per object-by-all-facets cell, at least
# two levels per variable, and numeric nonconstant outcomes.
# No imputation, aggregation, or outcome recoding is performed.
gtheory_prepare <- function(data, outcomes, facets = .gt_default_facets,
                            max_preparation_bytes = 512 * 1024^2) {
  facets <- .gt_validate_facets(facets)
  if (!is.data.frame(data) || anyDuplicated(names(data)))
    .gt_error("data must be a data frame with unique column names.")
  if (!is.character(outcomes) || !length(outcomes) || anyNA(outcomes) ||
      anyDuplicated(outcomes) || any(!nzchar(outcomes)))
    .gt_error("outcomes must contain unique, nonempty numeric column names.")
  missing_columns <- setdiff(c(outcomes, unname(facets)), names(data))
  if (length(missing_columns))
    .gt_error("Missing data columns: ", paste(missing_columns, collapse = ", "))
  if (length(intersect(outcomes, unname(facets))))
    .gt_error("Outcome and facet columns must be distinct.")
  if (!nrow(data)) .gt_error("data contains no observations.")
  if (any(!vapply(data[outcomes], is.numeric, logical(1))))
    .gt_error("Outcomes must be numeric. Factors are not silently converted.")
  if (any(vapply(data[outcomes], function(x) any(!is.finite(x)), logical(1))))
    .gt_error("Outcomes contain missing or non-finite values.")
  if (any(vapply(data[outcomes], function(x) length(unique(x)) < 2L, logical(1))))
    .gt_error("Constant outcomes do not identify trait variance or correlations.")
  facet_levels <- lapply(data[unname(facets)], function(x) {
    if (!is.atomic(x) || anyNA(x) || (is.numeric(x) && any(!is.finite(x))))
      .gt_error("Facets must have nonmissing, finite atomic values.")
    if (is.factor(x)) levels(droplevels(x)) else sort(unique(x))
  })
  names(facet_levels) <- .gt_facet_names
  counts <- setNames(vapply(facet_levels, length, integer(1)), .gt_facet_names)
  if (any(counts < 2L)) .gt_error("The object and every instrumentation facet need at least two observed levels.")
  N <- prod(counts)
  if (N != nrow(data))
    .gt_error("A complete balanced factorial design is required: expected ", N,
              " rows, received ", nrow(data), ". Missing cells are not dropped. ",
              "Check missing cells and facet coding. If child IDs are unique within parents, ",
              "use an explicitly verified within-parent index only when the sampling design ",
              "supports the same complete coded panel; declare the parent-scoped nested terms. ",
              "Otherwise this Gaussian backend does not support the design; do not fill or relabel cells automatically.")
  if (!is.numeric(max_preparation_bytes) || length(max_preparation_bytes) != 1L ||
      !is.finite(max_preparation_bytes) || max_preparation_bytes <= 0)
    .gt_error("max_preparation_bytes must be a positive finite number of bytes.")
  D <- length(outcomes)
  estimated_bytes <- .gt_gaussian_preparation_bytes(N, D, length(counts))
  if (estimated_bytes > max_preparation_bytes)
    .gt_error("Gaussian preparation allocation estimate (", round(estimated_bytes),
      " bytes) exceeds max_preparation_bytes (", format(max_preparation_bytes, scientific = FALSE),
      "). Increase the explicit limit only if sufficient memory is available.")
  # The guard runs before allocating the outcome matrix, ordering indices, or
  # contrast arrays. No axis-square matrix is created by this implementation.
  Y <- as.matrix(data[outcomes])
  strides <- c(1, head(cumprod(counts), -1L))
  indices <- lapply(seq_along(facets), function(j)
    match(as.character(data[[facets[j]]]), as.character(facet_levels[[j]])))
  row_index <- 1 + Reduce(`+`, Map(function(i, s) (i - 1L) * s, indices, strides))
  if (anyNA(row_index) || anyDuplicated(row_index))
    .gt_error("Duplicate factorial cells detected; exactly one row per cell is required.")
  Y <- Y[order(row_index), , drop = FALSE]
  D <- ncol(Y)
  transformed <- array(Y, dim = c(counts, D))
  for (axis in seq_along(counts)) {
    n <- counts[axis]
    perm <- c(axis, setdiff(seq_len(length(counts) + 1L), axis))
    work <- aperm(transformed, perm)
    work[] <- .gt_helmert_transform(matrix(work, nrow = n))
    transformed <- aperm(work, order(perm))
  }
  transformed <- matrix(transformed, nrow = N, ncol = D)
  codes <- integer(N)
  for (j in seq_along(counts)) {
    is_contrast <- ((seq_len(N) - 1L) %/% strides[j]) %% counts[j] > 0L
    codes <- codes + as.integer(is_contrast) * 2L^(j - 1L)
  }
  strata <- lapply(seq.int(0L, .gt_full_mask), function(mask) {
    block <- transformed[codes == mask, , drop = FALSE]
    list(mask = mask, df = nrow(block), SSCP = crossprod(block))
  })
  names(strata) <- as.character(seq.int(0L, .gt_full_mask))
  structure(list(strata = strata, counts = counts, N = N, D = D,
                 means = setNames(colMeans(Y), outcomes), outcomes = outcomes,
                 facets = facets, levels = facet_levels,
                 observed_variances = setNames(apply(Y, 2L, stats::var), outcomes),
                 allocation = list(estimated_bytes = estimated_bytes,
                   limit_bytes = max_preparation_bytes,
                   method = "Implicit normalized Helmert contrasts; linear in rows times outcomes",
                   estimate_scope = "Preparation working arrays; excludes caller data and downstream OpenMx model")),
            class = "gtheory_prepared")
}

.gt_validate_components <- function(prepared, components) {
  if (!inherits(prepared, "gtheory_prepared")) .gt_error("Use gtheory_prepare first.")
  if (!is.list(components) || is.null(names(components)) ||
      anyDuplicated(names(components)) || !"Residual" %in% names(components))
    .gt_error("components must be a uniquely named list including Residual.")
  groups <- .gt_resolve_spec(setdiff(names(components), "Residual"))
  if (!identical(groups, setdiff(names(components), "Residual")))
    .gt_error("Component names must use canonical facet order.")
  for (g in names(components)) {
    M <- components[[g]]
    if (!is.matrix(M) || !is.numeric(M) ||
        !identical(dim(M), c(prepared$D, prepared$D)) || any(!is.finite(M)) ||
        max(abs(M - t(M))) > 1e-8 * max(1, max(abs(M))))
      .gt_error("Invalid covariance matrix for ", g, ".")
    eig <- eigen(M, symmetric = TRUE, only.values = TRUE)$values
    if (min(eig) < -1e-8 * max(1, max(abs(eig))))
      .gt_error("Covariance matrix is not positive semidefinite: ", g)
  }
  groups
}

.gt_stratum_covariance <- function(prepared, components, mask) {
  C <- components[["Residual"]]
  for (g in setdiff(names(components), "Residual")) {
    gm <- .gt_mask(g)
    if (bitwAnd(gm, mask) == mask)
      C <- C + prod(prepared$counts[!.gt_bits(gm)]) * components[[g]]
  }
  C
}

# Evaluate the exact Gaussian ML or REML deviance without fitting a model.
# REML includes D * log(N), matching the unscaled fixed intercepts in lme4.
gtheory_deviance <- function(prepared, components, reml = TRUE) {
  .gt_validate_components(prepared, components)
  if (!is.logical(reml) || length(reml) != 1L || is.na(reml))
    .gt_error("reml must be TRUE or FALSE.")
  result <- (prepared$N - as.integer(reml)) * prepared$D * log(2 * pi)
  if (reml) result <- result + prepared$D * log(prepared$N)
  for (s in prepared$strata) {
    if (reml && s$mask == 0L) next
    C <- .gt_stratum_covariance(prepared, components, s$mask)
    ch <- tryCatch(chol(C), error = function(e) NULL)
    if (is.null(ch)) return(Inf)
    result <- result + s$df * 2 * sum(log(diag(ch)))
    if (s$mask != 0L) result <- result + sum(chol2inv(ch) * t(s$SSCP))
  }
  as.numeric(result)
}

.gt_covariance_types <- function(groups, covariance) {
  choices <- c("diagonal", "unstructured")
  if (!is.character(covariance) || !length(covariance) || anyNA(covariance) ||
      any(!covariance %in% choices))
    .gt_error("covariance must specify diagonal or unstructured.")
  if (is.null(names(covariance))) {
    if (length(covariance) != 1L) .gt_error("Multiple covariance types must be named.")
    return(setNames(rep(covariance, length(groups)), groups))
  }
  if (anyDuplicated(names(covariance)) || any(!names(covariance) %in% groups))
    .gt_error("Named covariance overrides must refer to unique model components.")
  result <- setNames(rep("diagonal", length(groups)), groups)
  result[names(covariance)] <- covariance
  result
}

.gt_psd_start <- function(M, scale) {
  # Strictly interior starts avoid zero Cholesky columns with zero derivatives.
  # A 1e-5 floor reproducibly stranded CSOLNP at nonstationary covariance
  # boundaries in delete-one-item fits. This larger floor changes starts only;
  # fitted random-effect variances remain free to reach zero.
  scale_outer <- sqrt(outer(scale, scale))
  eig <- eigen((M + t(M)) / (2 * scale_outer), symmetric = TRUE)
  (eig$vectors %*% diag(pmax(eig$values, 1e-3), nrow(M)) %*%
    t(eig$vectors)) * scale_outer
}

.gt_moment_components <- function(prepared, groups) {
  # Invert the saturated expected mean cross-products to obtain moment starts.
  # They are only starts; all retained parameters are optimized by likelihood.
  pieces <- vector("list", .gt_full_mask)
  pieces[[.gt_full_mask]] <- prepared$strata[[as.character(.gt_full_mask)]]$SSCP / prepared$strata[[as.character(.gt_full_mask)]]$df
  for (a in seq.int(.gt_full_mask - 1L, 1L)) {
    s <- prepared$strata[[as.character(a)]]
    M <- s$SSCP / s$df - pieces[[.gt_full_mask]]
    for (b in if (a < .gt_full_mask - 1L) seq.int(a + 1L, .gt_full_mask - 1L) else integer()) {
      if (bitwAnd(b, a) == a)
        M <- M - prod(prepared$counts[!.gt_bits(b)]) * pieces[[b]]
    }
    pieces[[a]] <- M / prod(prepared$counts[!.gt_bits(a)])
  }
  matrices <- lapply(c(groups, "Residual"), function(g) {
    M <- if (g == "Residual") pieces[[.gt_full_mask]] else pieces[[.gt_mask(g)]]
    dimnames(M) <- list(prepared$outcomes, prepared$outcomes)
    M
  })
  setNames(matrices, c(groups, "Residual"))
}

.gt_initial_components <- function(prepared, groups) {
  lapply(.gt_moment_components(prepared, groups), .gt_psd_start,
         scale = prepared$observed_variances)
}

# Raw-data method-of-moments components and admissible OpenMx starting values.
# Saturated expected mean cross-products are inverted first, then the sources
# in the requested model are selected. Negative moment components are retained
# in raw_components; only starting_components receive an interior PSD repair.
gtheory_mom <- function(data, outcomes, facets = .gt_default_facets,
                       spec) {
  prepared <- gtheory_prepare(data, outcomes, facets)
  groups <- .gt_resolve_spec(spec)
  raw <- .gt_moment_components(prepared, groups)
  starts <- lapply(raw, .gt_psd_start, scale = prepared$observed_variances)
  adjustments <- do.call(rbind, lapply(names(raw), function(g) {
    scale <- sqrt(outer(prepared$observed_variances, prepared$observed_variances))
    delta <- max(abs((starts[[g]] - raw[[g]]) / scale))
    data.frame(component = g,
      raw_min_standardized_eigenvalue = min(eigen(raw[[g]] / scale,
        symmetric = TRUE, only.values = TRUE)$values),
      start_min_standardized_eigenvalue = min(eigen(starts[[g]] / scale,
        symmetric = TRUE, only.values = TRUE)$values),
      maximum_standardized_adjustment = delta, adjusted = delta > 1e-10)
  }))
  list(spec = spec, outcomes = outcomes, raw_components = raw,
       starting_components = starts, adjustments = adjustments)
}

.gt_correlation <- .gt_covariance_correlation

# Fixed optimization units from marginal expected curvature at the start.
# Variances remain direct nonnegative parameters, so a zero variance can
# leave the boundary when its covariance-scale score points into the domain.
.gt_parameter_scales <- function(prepared, components, groups, reml) {
  components <- lapply(components, .gt_psd_start, scale = prepared$observed_variances)
  information <- lapply(components, function(M) rep(0, prepared$D))
  for (s in prepared$strata) {
    if (reml && s$mask == 0L) next
    coefficients <- setNames(rep(0, length(components)), names(components))
    coefficients[["Residual"]] <- 1
    for (g in groups) if (bitwAnd(.gt_mask(g), s$mask) == s$mask)
      coefficients[[g]] <- prod(prepared$counts[!.gt_bits(.gt_mask(g))])
    marginal <- Reduce(`+`, Map(function(M, a) diag(M) * a, components, coefficients))
    for (g in names(components))
      information[[g]] <- information[[g]] + s$df * (coefficients[[g]] / marginal)^2
  }
  lapply(information, function(x) 1 / sqrt(x))
}

# Fit a univariate G-study using the same Gaussian random-intercept models.
fit_openmx_gtheory <- function(data, outcome, facets = .gt_default_facets,
                              spec, reml = TRUE, ...) {
  if (!is.character(outcome) || length(outcome) != 1L)
    .gt_error("outcome must identify exactly one numeric column.")
  fit_openmx_multivariate(data, outcome, facets = facets, spec = spec,
                         reml = reml, covariance = "diagonal",
                         residual = "diagonal", ...)
}

# Fit a joint multivariate G-study with directly estimated trait covariances.
#
# A scalar covariance type applies to every random-effect source. A named
# vector supplies overrides, leaving unspecified sources diagonal.
# residual='pooled' imposes sigma^2 I; diagonal allows trait-specific variance;
# unstructured also estimates residual covariance between traits in one cell.
# This is a Gaussian observed-score model, including for numeric binary data.
.gt_parse_tryhard_trials <- function(native_messages, optimizer, start_label,
                                     max_trials) {
  begins <- grep("Beginning (initial fit attempt|fit attempt [0-9]+)", native_messages)
  if (!length(begins) || length(begins) > max_trials)
    .gt_error("Could not verify the native mxTryHard optimization-trial count.")
  do.call(rbind, lapply(seq_along(begins), function(i) {
    end <- if (i < length(begins)) begins[i + 1L] - 1L else length(native_messages)
    lines <- native_messages[begins[i]:end]
    # Native final summaries repeat the selected fit's objective, even when
    # the last optimization trial errored. Only a trial's own result block
    # supplies its objective; never attribute the final summary to that trial.
    summary_at <- grep("^(Solution found|Retry limit reached|Final run|Computing Hessian)", trimws(lines))
    if (length(summary_at)) lines <- head(lines, summary_at[[1L]] - 1L)
    result_at <- grep("^Attempt [0-9]+ result:", trimws(lines))
    fit_line <- if (length(result_at)) grep("^fit value = ",
      trimws(lines[seq.int(result_at[[1L]], length(lines))]), value = TRUE) else character()
    status_line <- grep("OpenMx status code [0-9]+", lines, value = TRUE)
    data.frame(attempt = i, optimizer = optimizer,
      start = if (i == 1L) start_label else "native_uniform_perturbation",
      status = if (length(status_line)) as.integer(sub(
        ".*OpenMx status code ([0-9]+).*", "\\1", status_line[1L])) else NA_integer_,
      minus2loglik = if (length(fit_line)) as.numeric(sub(
        "^fit value = ", "", fit_line[1L])) else NA_real_,
      returned_fit = FALSE,
      error = if (any(grepl("Fit attempt generated errors", lines, fixed = TRUE)))
        "Native trial failed; see retry_log." else "", stringsAsFactors = FALSE)
  }))
}

.gt_tryhard_fit <- function(model, optimizer, extra_tries, tolerance,
                            max_iterations, start_label, silent) {
  # Keep OpenMx's retry machinery intact. Its message transcript provides the
  # attempted-trial count even when a trial errors before returning a fit.
  native_messages <- character()
  output <- capture.output(fitted <- withCallingHandlers(
    OpenMx::mxTryHard(model, extraTries = extra_tries, greenOK = FALSE,
      OKstatuscodes = 0L, jitterDistrib = "runif", loc = 1, scale = 0.25,
      finetuneGradient = FALSE, exhaustive = FALSE, checkHess = FALSE,
      initialTolerance = tolerance, maxMajorIter = max_iterations,
      iterationSummary = TRUE, bestInitsOutput = FALSE, showInits = FALSE,
      intervals = FALSE, silent = FALSE),
    message = function(m) {
      native_messages <<- c(native_messages, conditionMessage(m))
      if (silent) invokeRestart("muffleMessage")
    }))
  if (!silent && length(output)) cat(paste(output, collapse = "\n"), "\n")
  attempts <- .gt_parse_tryhard_trials(native_messages, optimizer, start_label,
    extra_tries + 1L)
  transcript <- c(native_messages, if (length(output)) c("Native standard output:", output))
  if (inherits(fitted, "try-error") || !inherits(fitted, "MxModel"))
    stop(structure(list(message = "All native mxTryHard trials failed; inspect retry_log.",
      call = NULL, retry_attempts = attempts, retry_log = transcript,
      optimization_trials = nrow(attempts)),
      class = c("gt_native_retry_failure", "error", "condition")))
  if (any(is.finite(attempts$minus2loglik))) {
    delta <- abs(attempts$minus2loglik - as.numeric(fitted$output$fit))
    delta[!is.finite(delta)] <- Inf
    matched <- which(delta < 1e-8 + 1e-12 * abs(as.numeric(fitted$output$fit)))
    # Native text output may round distinct trials to the same objective.
    # Never assign final-fit status to an arbitrary member of an ambiguous tie.
    if (length(matched) == 1L) {
      selected <- matched[[1L]]
      attempts$returned_fit[selected] <- TRUE
      attempts$status[selected] <- as.integer(fitted$output$status$code)
    }
  }
  list(model = fitted, attempts = attempts, log = transcript)
}

.gt_native_uniform_start <- function(model) {
  parameters <- OpenMx::omxGetParameters(model)
  lower <- OpenMx::omxGetParameters(model, fetch = "lbound")
  upper <- OpenMx::omxGetParameters(model, fetch = "ubound")
  lower[is.na(lower)] <- -Inf
  upper[is.na(upper)] <- Inf
  OpenMx::omxSetParameters(model, labels = names(parameters),
    values = OpenMx::imxJiggle(parameters, lower, upper, dsn = "runif", loc = 1, scale = 0.25))
}

.gt_complete_tryhard_fit <- function(model, optimizer, extra_tries, tolerance,
    max_iterations, start_label, silent, assess) {
  # mxTryHard has no callback for the covariance-scale acceptance check.
  # Continue on this same model/data with only the unused optimization budget;
  # all continuation perturbations use OpenMx's own bounded uniform helper.
  budget <- as.integer(extra_tries) + 1L
  used <- 0L
  invocation <- 0L
  history <- list()
  logs <- character()
  best <- NULL
  next_model <- model
  continuation_reason <- "initial MoM fit"
  while (used < budget) {
    invocation <- invocation + 1L
    remaining <- budget - used
    native_error <- NULL
    native <- tryCatch(.gt_tryhard_fit(next_model, optimizer, remaining - 1L,
      tolerance, max_iterations, if (used == 0L) start_label else
        "native_uniform_perturbation", silent), gt_native_retry_failure = function(e) {
          native_error <<- e
          list(model = NULL, attempts = e$retry_attempts, log = e$retry_log)
        })
    rows <- native$attempts
    if (!nrow(rows) || nrow(rows) > remaining)
      .gt_error("Native retries returned an invalid consumed-trial count.")
    rows$native_attempt <- rows$attempt
    rows$attempt <- used + seq_len(nrow(rows))
    rows$invocation <- invocation
    rows$continuation_reason <- continuation_reason
    rows$native_returned_fit <- rows$returned_fit
    rows$returned_fit <- FALSE
    rows$external_accepted <- NA
    rows$external_rejection_reason <- ""
    used <- used + nrow(rows)
    evaluation <- if (!is.null(native$model)) tryCatch(assess(native$model),
      error = function(e) list(accepted = FALSE, reason = conditionMessage(e))) else
        list(accepted = FALSE, reason = conditionMessage(native_error))
    if (any(rows$native_returned_fit)) {
      rows$external_accepted[rows$native_returned_fit] <- isTRUE(evaluation$accepted)
      rows$external_rejection_reason[rows$native_returned_fit] <- evaluation$reason
    }
    history[[invocation]] <- rows
    logs <- c(logs, sprintf("Native invocation %d; %d trials remaining; %s",
      invocation, remaining, continuation_reason), native$log,
      paste("External acceptance:", isTRUE(evaluation$accepted), evaluation$reason))
    if (!is.null(native$model)) {
      value <- as.numeric(native$model$output$fit)
      usable <- is.finite(value) && !is.null(evaluation$components)
      if (usable && (is.null(best) || isTRUE(evaluation$accepted) ||
          (!isTRUE(best$assessment$accepted) && value < best$value)))
        best <- list(model = native$model, assessment = evaluation,
          invocation = invocation, value = value)
    }
    if (isTRUE(evaluation$accepted) || used >= budget) break
    continuation_reason <- evaluation$reason
    base_model <- if (!is.null(best)) best$model else model
    next_model <- tryCatch(.gt_native_uniform_start(base_model), error = function(e) {
      message <- paste("Native continuation initialization failed:", conditionMessage(e))
      stop(structure(list(message = message, call = NULL,
        retry_attempts = do.call(rbind, history), retry_log = c(logs, message),
        optimization_trials = used), class = c("gt_native_retry_failure", "error", "condition")))
    })
  }
  attempts <- do.call(rbind, history)
  rownames(attempts) <- NULL
  if (is.null(best)) stop(structure(list(
    message = "No native fit supplied usable covariance estimates within the total trial budget.",
    call = NULL, retry_attempts = attempts, retry_log = logs,
    optimization_trials = used), class = c("gt_native_retry_failure", "error", "condition")))
  attempts$returned_fit <- attempts$invocation == best$invocation & attempts$native_returned_fit
  list(model = best$model, assessment = best$assessment, attempts = attempts,
    log = logs, budget = budget, invocations = invocation)
}

fit_openmx_multivariate <- function(
    data, outcomes, facets = .gt_default_facets, spec,
    reml = TRUE, covariance = "unstructured", residual = "unstructured",
    start = NULL, optimizer = "CSOLNP", max_iterations = 3000L,
    tolerance = 1e-12, check_hessian = TRUE, threads = 1L, silent = TRUE,
    extra_tries = 9L, retry_seed = NULL, prepared = NULL,
    max_preparation_bytes = 512 * 1024^2) {
  if (!requireNamespace("OpenMx", quietly = TRUE))
    .gt_error("Install OpenMx before fitting: install.packages('OpenMx').")
  groups <- .gt_resolve_spec(spec)
  if (is.null(prepared)) {
    prepared <- gtheory_prepare(data, outcomes, facets, max_preparation_bytes)
  } else if (!inherits(prepared, "gtheory_prepared") ||
      !identical(prepared$outcomes, outcomes) ||
      !identical(prepared$facets, .gt_validate_facets(facets)) ||
      prepared$N != nrow(data)) {
    .gt_error("Prepared Gaussian data do not match the fitting request.")
  }
  if (!is.logical(reml) || length(reml) != 1L || is.na(reml))
    .gt_error("reml must be TRUE or FALSE.")
  if (!is.logical(check_hessian) || length(check_hessian) != 1L || is.na(check_hessian))
    .gt_error("check_hessian must be TRUE or FALSE.")
  if (!is.numeric(tolerance) || length(tolerance) != 1L ||
      !is.finite(tolerance) || tolerance <= 0)
    .gt_error("tolerance must be a positive finite scalar.")
  if (!is.numeric(extra_tries) || length(extra_tries) != 1L ||
      !is.finite(extra_tries) || extra_tries < 0 || extra_tries != round(extra_tries))
    .gt_error("extra_tries must be a nonnegative integer.")
  if (!is.null(retry_seed)) {
    if (!is.numeric(retry_seed) || length(retry_seed) != 1L ||
        !is.finite(retry_seed) || retry_seed < 0 || retry_seed > .Machine$integer.max ||
        retry_seed != round(retry_seed)) .gt_error("retry_seed must be a nonnegative integer.")
    old_kind <- RNGkind()
    old_rng <- if (exists(".Random.seed", .GlobalEnv, inherits = FALSE))
      get(".Random.seed", .GlobalEnv) else NULL
    on.exit({
      do.call(RNGkind, as.list(old_kind))
      if (is.null(old_rng)) {
        if (exists(".Random.seed", .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
      } else assign(".Random.seed", old_rng, .GlobalEnv)
    }, add = TRUE)
    RNGkind("Mersenne-Twister", "Inversion", "Rejection")
    set.seed(as.integer(retry_seed))
  }
  for (x in list(threads = threads, max_iterations = max_iterations)) {
    if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || x < 1 || x != round(x))
      .gt_error("threads and max_iterations must be positive integers.")
  }
  types <- .gt_covariance_types(groups, covariance)
  residual <- match.arg(residual, c("unstructured", "diagonal", "pooled"))
  types <- c(types, Residual = residual)
  if (prepared$D == 1L) types[] <- "diagonal"
  component_names <- names(types)
  start_label <- if (is.null(start)) "sample_MoM" else "provided_components"
  if (is.null(start)) start <- .gt_initial_components(prepared, groups)
  .gt_validate_components(prepared, start)
  if (!setequal(names(start), component_names))
    .gt_error("start must contain a covariance matrix for every model component.")
  D <- prepared$D
  parameter_scales <- .gt_parameter_scales(prepared, start, groups, reml)
  objects <- list()
  algebra_names <- setNames(sprintf("G%02d", seq_along(types)), component_names)
  n_variance_parameters <- 0L
  parameter_labels <- list()
  for (j in seq_along(types)) {
    g <- component_names[j]
    type <- types[j]
    nm <- unname(algebra_names[j])
    M <- .gt_psd_start(start[[g]], prepared$observed_variances)
    if (type == "diagonal") {
      sn <- paste0(nm, "_V")
      scale_name <- paste0(nm, "_scale")
      scale_values <- parameter_scales[[g]]
      labels <- matrix(NA_character_, D, D)
      diag(labels) <- paste0(nm, "_v", seq_len(D))
      bounds <- matrix(NA_real_, D, D)
      diag(bounds) <- if (g == "Residual") prepared$observed_variances * 1e-10 / scale_values else 0
      objects[[length(objects) + 1L]] <- OpenMx::mxMatrix(
        "Diag", D, D, values = diag(scale_values, D), free = FALSE, name = scale_name)
      objects[[length(objects) + 1L]] <- OpenMx::mxMatrix(
        "Diag", D, D, free = diag(TRUE, D), values = diag(diag(M) / scale_values, D),
        labels = labels, lbound = bounds, name = sn)
      objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(
        paste0(scale_name, " %*% ", sn), name = nm)
      n_variance_parameters <- n_variance_parameters + D
      parameter_labels[[g]] <- diag(labels)
    } else if (type == "pooled") {
      vn <- paste0(nm, "_scalar")
      objects[[length(objects) + 1L]] <- OpenMx::mxMatrix(
        "Full", 1, 1, free = TRUE, values = mean(diag(M)),
        labels = paste0(nm, "_v"), lbound = min(prepared$observed_variances) * 1e-10,
        name = vn)
      objects[[length(objects) + 1L]] <- OpenMx::mxMatrix("Iden", D, D, name = "traitI")
      objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(
        paste0(vn, " %x% traitI"), name = nm)
      n_variance_parameters <- n_variance_parameters + 1L
      parameter_labels[[g]] <- paste0(nm, "_v")
    } else {
      ln <- paste0(nm, "_L")
      free <- lower.tri(M, diag = TRUE)
      labels <- matrix(NA_character_, D, D)
      labels[free] <- paste0(nm, "_l", seq_len(sum(free)))
      bounds <- matrix(NA_real_, D, D)
      diag(bounds) <- if (g == "Residual") sqrt(prepared$observed_variances * 1e-10) else 0
      objects[[length(objects) + 1L]] <- OpenMx::mxMatrix(
        "Lower", D, D, free = free, values = t(chol(M)), labels = labels,
        lbound = bounds, name = ln)
      objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(
        paste0(ln, " %*% t(", ln, ")"), name = nm)
      n_variance_parameters <- n_variance_parameters + D * (D + 1L) / 2L
      parameter_labels[[g]] <- labels[free]
    }
  }
  # Evaluate determinants in fixed observed-SD units to avoid over/underflow
  # when otherwise well-conditioned outcomes use very large or small units.
  # The constant restores the determinant in the original outcome units.
  objects[[length(objects) + 1L]] <- OpenMx::mxMatrix("Diag", D, D,
    values = diag(1 / sqrt(prepared$observed_variances), D), free = FALSE,
    name = "observedSDInverse")
  log_scale_determinant <- sum(log(prepared$observed_variances))
  blocks <- character()
  score_names <- character()
  for (s in prepared$strata) {
    if (reml && s$mask == 0L) next
    nm <- paste0("C", s$mask)
    summands <- algebra_names[["Residual"]]
    for (g in groups) {
      gm <- .gt_mask(g)
      if (bitwAnd(gm, s$mask) == s$mask) {
        coefficient <- prod(prepared$counts[!.gt_bits(gm)])
        summands <- c(summands, paste0(coefficient, " * ", algebra_names[[g]]))
      }
    }
    objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(
      paste(summands, collapse = " + "), name = nm)
    inv_name <- paste0("Inv", s$mask)
    objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(
      paste0("solve(", nm, ")"), name = inv_name)
    # Retain determinant-domain trial rejection (a failing chol algebra can be
    # fatal in OpenMx), but apply it to the standardized stratum covariance.
    scaled_name <- paste0("Scaled", nm)
    objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(
      paste0("observedSDInverse %*% ", nm, " %*% observedSDInverse"), name = scaled_name)
    term <- paste0(s$df, " * (log(det(", scaled_name, ")) + ",
      format(log_scale_determinant, digits = 17, scientific = FALSE, trim = TRUE), ")")
    if (s$mask != 0L) {
      sn <- paste0("SS", s$mask)
      objects[[length(objects) + 1L]] <- OpenMx::mxMatrix(
        "Full", D, D, values = s$SSCP, free = FALSE, name = sn)
      term <- paste0(term, " + tr(", inv_name, " %*% ", sn, ")")
    }
    bn <- paste0("block", s$mask)
    objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(term, name = bn)
    blocks <- c(blocks, bn)
    score_name <- paste0("Score", s$mask)
    score_expr <- paste0(s$df, " * ", inv_name)
    if (s$mask != 0L) score_expr <- paste0(score_expr, " - ", inv_name,
      " %*% SS", s$mask, " %*% ", inv_name)
    objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(score_expr, name = score_name)
    score_names[as.character(s$mask)] <- score_name
  }
  # Exact first derivatives avoid finite-difference cancellation on the large
  # observed-data deviances, especially near variance-component boundaries.
  gradient_entries <- character()
  gradient_labels <- character()
  for (g in component_names) {
    nm <- algebra_names[[g]]
    terms <- character()
    for (mask in as.integer(names(score_names))) {
      gm <- if (g == "Residual") .gt_full_mask else .gt_mask(g)
      if (bitwAnd(gm, mask) == mask) {
        multiplier <- if (g == "Residual") 1 else prod(prepared$counts[!.gt_bits(gm)])
        terms <- c(terms, paste0(multiplier, " * ", score_names[[as.character(mask)]]))
      }
    }
    gn <- paste0(nm, "_score")
    objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(
      paste(terms, collapse = " + "), name = gn)
    if (types[[g]] == "diagonal") {
      gradient_entries <- c(gradient_entries, paste0(nm, "_scale[", seq_len(D), ",", seq_len(D), "] * ",
        gn, "[", seq_len(D), ",", seq_len(D), "]"))
    } else if (types[[g]] == "pooled") {
      gradient_entries <- c(gradient_entries, paste0("tr(", gn, ")"))
    } else {
      ln <- paste0(nm, "_L")
      gl <- paste0(nm, "_Lscore")
      objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(
        paste0("2 * ", gn, " %*% ", ln), name = gl)
      ix <- which(lower.tri(matrix(0, D, D), diag = TRUE), arr.ind = TRUE)
      gradient_entries <- c(gradient_entries, paste0(gl, "[", ix[,1], ",", ix[,2], "]"))
    }
    gradient_labels <- c(gradient_labels, parameter_labels[[g]])
  }
  objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(
    paste0("rbind(", paste(gradient_entries, collapse = ","), ")"),
    name = "analyticGradient", dimnames = list(gradient_labels, NULL))
  constant <- (prepared$N - as.integer(reml)) * D * log(2 * pi)
  if (reml) constant <- constant + D * log(prepared$N)
  objects[[length(objects) + 1L]] <- OpenMx::mxMatrix(
    "Full", 1, 1, values = constant, free = FALSE, name = "constant")
  objects[[length(objects) + 1L]] <- OpenMx::mxAlgebraFromString(
    paste(c("constant", blocks), collapse = " + "), name = "deviance")
  objects[[length(objects) + 1L]] <- OpenMx::mxFitFunctionAlgebra(
    "deviance", gradient = "analyticGradient", numObs = prepared$N * D, units = "-2lnL")
  # Actual observations supply native summary metadata. The algebra likelihood
  # still uses the fixed contrast cross-products rebuilt by gtheory_prepare().
  # mxBootstrap() cannot rebuild those statistics by resampling this mxData.
  # Raw data are summary metadata, not the algebra likelihood input. OpenMx
  # prohibits punctuation such as periods in manifest names, although these are
  # valid R column names. Use private names here and keep original outcome names
  # on means, covariance matrices, estimates, and every returned statistic.
  metadata_data <- as.data.frame(data[outcomes])
  names(metadata_data) <- paste0("GTOutcome", seq_along(outcomes))
  objects[[length(objects) + 1L]] <- OpenMx::mxData(
    observed = metadata_data, type = "raw")
  model <- do.call(OpenMx::mxModel, c(list(model = "BalancedGTheory"), objects))
  model <- OpenMx::mxOption(model, "Number of Threads", as.character(threads))
  # mxTryHard preserves this explicit optimizer plan. No Hessian/SE/CI work is
  # requested during retrying, so its optional final run cannot optimize again.
  model <- OpenMx::mxOption(model, "Calculate Hessian", "No")
  model <- OpenMx::mxOption(model, "Standard Errors", "No")
  model <- OpenMx::mxModel(model, OpenMx::mxComputeSequence(list(
    OpenMx::mxComputeGradientDescent(engine = optimizer, tolerance = tolerance,
      maxMajorIter = as.integer(max_iterations), nudgeZeroStarts = FALSE))))
  assess <- function(candidate) {
    components <- lapply(algebra_names, function(nm) {
      M <- OpenMx::mxEvalByName(nm, candidate)
      dimnames(M) <- list(outcomes, outcomes)
      M
    })
    status <- as.integer(candidate$output$status$code)
    stationarity <- gtheory_optimization_diagnostics(prepared, components, types, reml)
    independent <- gtheory_deviance(prepared, components, reml = reml)
    native <- as.numeric(candidate$output$fit)
    likelihood_matches <- is.finite(independent) && is.finite(native) &&
      abs(independent - native) <= 1e-5
    reason <- c(if (status != 0L) paste("OpenMx optimizer status", status),
      if (!stationarity$stationary_within_tolerance) "Covariance-scale stationarity check failed.",
      if (!likelihood_matches) "Independent likelihood reconstruction failed.")
    list(accepted = status == 0L && stationarity$stationary_within_tolerance && likelihood_matches,
      components = components, stationarity = stationarity,
      likelihood_matches = likelihood_matches, reason = paste(reason, collapse = " | "))
  }
  timing <- system.time({
    retried <- .gt_complete_tryhard_fit(model, optimizer, as.integer(extra_tries), tolerance,
      as.integer(max_iterations), start_label, silent, assess)
    model <- retried$model
  })
  optimizer_status <- as.integer(model$output$status$code)
  derivative_diagnostics <- NULL
  derivative_error <- NULL
  derivative_warnings <- character()
  diagnostic_seconds <- 0
  if (check_hessian) {
    # Derivative-only computation at the returned parameters is not another
    # optimization trial. Preserve the optimizer's status and fitted model.
    derivative_model <- OpenMx::mxModel(model, OpenMx::mxComputeSequence(list(
      OpenMx::mxComputeNumericDeriv(parallel = FALSE),
      OpenMx::mxComputeStandardError(), OpenMx::mxComputeHessianQuality(),
      OpenMx::mxComputeReportDeriv())))
    diagnostic_timing <- system.time(derivative_result <-
      .gt_gaussian_derivative_run(derivative_model, silent = silent))
    derivative_diagnostics <- derivative_result$model
    derivative_error <- derivative_result$error
    derivative_warnings <- derivative_result$warnings
    diagnostic_seconds <- unname(diagnostic_timing[["elapsed"]])
  }
  components <- retried$assessment$components
  estimates <- do.call(rbind, lapply(names(components), function(g)
    data.frame(component = g, trait = outcomes, variance = diag(components[[g]]),
               row.names = NULL)))
  status <- optimizer_status
  stationarity <- retried$assessment$stationarity
  issues <- character()
  if (status != 0L) issues <- c(issues, paste("OpenMx optimizer status", status))
  if (!stationarity$stationary_within_tolerance)
    issues <- c(issues, "Covariance-scale first-order stationarity check failed.")
  if (!retried$assessment$likelihood_matches)
    issues <- c(issues, "Independent likelihood reconstruction failed.")
  if (!check_hessian) issues <- c(issues, "Hessian diagnostics were disabled.")
  diagnostic_output <- if (is.null(derivative_diagnostics)) model$output else derivative_diagnostics$output
  if (!is.null(derivative_error)) issues <- c(issues, paste("Hessian diagnostics failed:", derivative_error))
  if (length(derivative_warnings)) issues <- c(issues, paste0(
    "Derivative-only OpenMx diagnostics emitted ", length(derivative_warnings),
    " warning(s); inspect derivative_warnings and Hessian quality. ",
    "These warnings do not replace the optimizer status or numerical acceptance checks."))
  if (check_hessian && isFALSE(diagnostic_output$infoDefinite))
    issues <- c(issues, "The estimated Hessian is not positive definite.")
  boundary <- vapply(components, function(M) {
    standardized <- M / sqrt(outer(prepared$observed_variances, prepared$observed_variances))
    ev <- eigen(standardized, symmetric = TRUE, only.values = TRUE)$values
    min(ev) <= 1e-8
  }, logical(1))
  if (any(boundary)) issues <- c(issues, paste("Boundary or nearly singular components:",
                                              paste(names(boundary)[boundary], collapse = ", ")))
  for (g in groups[types[groups] == "unstructured"]) {
    # Few grouping levels warn about information, not algebraic identification.
    nlevels <- prod(prepared$counts[.gt_bits(.gt_mask(g))])
    if (nlevels <= D + 1L)
      issues <- c(issues, paste0(g, " has only ", nlevels, " grouping levels for ",
                                D, " traits; its covariance may be unstable."))
  }
  uncertainty <- .gt_gaussian_uncertainty(model, algebra_names, types, outcomes,
    components, diagnostic_output$hessian, diagnostic_output$standardErrors,
    boundary, if (reml) "REML restricted likelihood" else "ML profile likelihood",
    check_hessian)
  if (isTRUE(uncertainty$available) && isTRUE(uncertainty$restricted_to_interior))
    issues <- c(issues, paste0("The joint Hessian is indefinite at a variance boundary, so standard errors condition on ",
      paste(uncertainty$fixed_components, collapse = ", "),
      " being held at zero. Intervals then describe the remaining components only."))
  else if (isTRUE(uncertainty$available) && length(uncertainty$boundary_components))
    issues <- c(issues, paste0("Wald standard errors were computed, but ",
      paste(uncertainty$boundary_components, collapse = ", "),
      " rest(s) on a variance boundary; their standard errors and any interval derived from them are not valid."))
  if (!isTRUE(uncertainty$available) && check_hessian)
    issues <- c(issues, paste("Standard errors are unavailable:", uncertainty$reason))
  if (isTRUE(uncertainty$available) && is.finite(uncertainty$openmx_standard_error_agreement) &&
      uncertainty$openmx_standard_error_agreement > 1e-6)
    issues <- c(issues, paste0("Reconstructed and native OpenMx standard errors differ by a relative ",
      format(uncertainty$openmx_standard_error_agreement, digits = 3),
      "; inspect uncertainty$parameter_covariance before quoting an interval."))
  deviance <- as.numeric(model$output$fit)
  # Preserve the archive's variance-only, N*D OpenMx criteria under explicit
  # legacy names. For ordinary ML, profiled means remain estimated parameters.
  # N denotes multivariate response vectors; N*D scalar scores is an alternative
  # BIC convention, not another likelihood. REML is not a full-data ML likelihood
  # and is left without generic AIC/BIC rather than adding means automatically.
  native_summary <- summary(model, numObs = prepared$N * D)
  df <- nrow(native_summary$parameters)
  native_bic <- unname(native_summary$informationCriteria["BIC:", "par"])
  native_aic <- unname(native_summary$informationCriteria["AIC:", "par"])
  if (!is.finite(native_bic) || !is.finite(native_aic) || df != n_variance_parameters)
    .gt_error("Native OpenMx information criteria or parameter count are unavailable/inconsistent.")
  total_parameters <- n_variance_parameters + D
  ml_aic <- if (reml) NA_real_ else deviance + 2 * total_parameters
  ml_bic_vectors <- if (reml) NA_real_ else deviance + log(prepared$N) * total_parameters
  ml_bic_scalars <- if (reml) NA_real_ else deviance + log(prepared$N * D) * total_parameters
  result <- structure(list(
    spec = spec, groups = groups, outcomes = outcomes, facets = prepared$facets,
    counts = prepared$counts, N = prepared$N, D = D, means = prepared$means,
    reml = reml, covariance_types = types, covariance_components = components,
    correlations = lapply(components, .gt_correlation,
                          scale = prepared$observed_variances), estimates = estimates,
    minus2loglik = deviance, loglik = -deviance / 2,
    uncertainty = uncertainty,
    component_standard_errors = uncertainty$variances,
    n_variance_parameters = n_variance_parameters, n_parameters = total_parameters,
    n_profiled_means = D, n_model_parameters = total_parameters,
    n_likelihood_parameters = if (reml) n_variance_parameters else total_parameters,
    legacy_n_parameters = df,
    AIC = ml_aic, BIC = ml_bic_vectors,
    ml_AIC = ml_aic, ml_BIC_response_vectors = ml_bic_vectors,
    ml_BIC_scalar_scores = ml_bic_scalars,
    legacy_AIC = native_aic, legacy_BIC = native_bic,
    reml_AIC_variance_parameters = if (reml) native_aic else NA_real_,
    reml_BIC_scalar_scores_variance_parameters = if (reml) native_bic else NA_real_,
    information_criteria = list(likelihood = if (reml) "REML" else "ML",
      generic = if (reml) "AIC/BIC unavailable for REML; explicitly named restricted-likelihood conventions provided" else
        "AIC counts covariance parameters and profiled means; BIC uses N response vectors",
      legacy = "OpenMx variance parameters only, with N*D scalar scores for BIC",
      bic_response_vectors = prepared$N, bic_scalar_scores = prepared$N * D,
      caution = "BIC sample-size conventions must be stated; response vectors are correlated by shared random sources"),
    bic_source = if (reml) NA_character_ else "ML deviance + log(N) * (covariance parameters + profiled means)",
    bic_nobs = if (reml) NA_real_ else prepared$N,
    legacy_bic_nobs = native_summary$numObs, status = status,
    converged = isTRUE(retried$assessment$accepted),
    diagnostics = list(issues = issues, boundary_components = boundary,
                       hessian_checked = check_hessian,
                       gradient = diagnostic_output$gradient,
                       hessian = diagnostic_output$hessian,
                       standard_errors = diagnostic_output$standardErrors,
                       standard_errors_available = isTRUE(uncertainty$available),
                       standard_errors_unavailable_reason = uncertainty$reason,
                       info_definite = diagnostic_output$infoDefinite,
                       hessian_error = derivative_error,
                       derivative_warnings = derivative_warnings,
                       derivative_warning_scope = "Derivative-only Hessian/SE diagnostics; optimizer warnings are not intercepted.",
                       covariance_stationarity = stationarity,
                       independent_likelihood_matches = retried$assessment$likelihood_matches),
    optimization_trials = nrow(retried$attempts), retry_attempts = retried$attempts,
    returned_trial_identified = any(retried$attempts$returned_fit),
    retry_log = retried$log,
    retry_settings = list(optimizer = optimizer, extraTries = as.integer(extra_tries),
      jitterDistrib = "runif", loc = 1, scale = 0.25, finetuneGradient = FALSE,
      exhaustive = FALSE, OKstatuscodes = 0L, greenOK = FALSE,
      start = start_label, retry_seed = retry_seed, rng = RNGkind(),
      protocol = "native_uniform_full_acceptance_v2",
      acceptance = "optimizer0_covariance_stationarity_likelihood",
      total_trial_budget = retried$budget, native_invocations = retried$invocations,
      continuation_perturbation = "OpenMx::imxJiggle(runif, loc=1, scale=0.25)"),
    elapsed_seconds = unname(timing[["elapsed"]]) + diagnostic_seconds,
    diagnostic_seconds = diagnostic_seconds, model = model,
    session = utils::sessionInfo()), class = "openmx_gtheory_fit")
  if (status != 0L) warning("Fit returned OpenMx status ", status,
                            "; inspect diagnostics before interpreting estimates.", call. = FALSE)
  if (!stationarity$stationary_within_tolerance)
    warning("Covariance-scale first-order stationarity check failed; inspect diagnostics.", call. = FALSE)
  result
}


# Diagnose covariance-scale stationarity, including variance boundaries.
#
# The exact derivative H_g satisfies d(-2 log L) = tr(H_g dG_g).
# Diagonal models use box projection in Fisher-standardized variance units.
# Unstructured models use PSD-cone projection after standardizing each trait
# by its observed SD and scaling the component by a scalar curvature bound.
# A zero projected score is the first-order KKT condition. A small numerical
# score is a local stationarity diagnostic, not proof of a global optimum.
# The scalar matrix scaling changes the magnitude, but not the zero, of KKT.
# Report negative-eigenvalue and complementarity diagnostics alongside it.
gtheory_optimization_diagnostics <- function(
    prepared, components, covariance_types = NULL, reml = TRUE,
    tolerance = 1e-3, boundary_tolerance = 1e-8) {
  .gt_validate_components(prepared, components)
  if (!is.logical(reml) || length(reml) != 1L || is.na(reml))
    stop("reml must be TRUE or FALSE.")
  if (!is.numeric(tolerance) || length(tolerance) != 1L ||
      !is.finite(tolerance) || tolerance <= 0)
    stop("tolerance must be one positive finite number.")
  if (!is.numeric(boundary_tolerance) || length(boundary_tolerance) != 1L ||
      !is.finite(boundary_tolerance) || boundary_tolerance < 0)
    stop("boundary_tolerance must be one nonnegative finite number.")
  groups <- names(components)
  D <- prepared$D
  if (is.null(covariance_types))
    covariance_types <- setNames(rep(if (D == 1L) "diagonal" else "unstructured", length(groups)), groups)
  if (!is.character(covariance_types) || is.null(names(covariance_types)) ||
      anyDuplicated(names(covariance_types)) || !setequal(names(covariance_types), groups) ||
      anyNA(covariance_types) || any(!covariance_types %in% c("diagonal", "unstructured", "pooled")))
    stop("covariance_types must name every component exactly once.")
  covariance_types <- covariance_types[groups]
  zero <- matrix(0, D, D)
  gradients <- setNames(lapply(groups, function(g) zero), groups)
  diagonal_curvature <- setNames(lapply(groups, function(g) numeric(D)), groups)
  pooled_curvature <- setNames(rep(0, length(groups)), groups)
  matrix_curvature_bound <- setNames(rep(0, length(groups)), groups)
  obs_sd <- sqrt(prepared$observed_variances)
  standardizer <- diag(1 / obs_sd, D)
  unstandardizer <- diag(obs_sd, D)
  for (stratum in prepared$strata) {
    if (reml && stratum$mask == 0L) next
    C <- .gt_stratum_covariance(prepared, components, stratum$mask)
    inverse <- chol2inv(chol(C))
    H <- stratum$df * inverse
    if (stratum$mask != 0L) H <- H - inverse %*% stratum$SSCP %*% inverse
    standardized_inverse <- unstandardizer %*% inverse %*% unstandardizer
    largest_inverse_eigenvalue <- max(eigen(standardized_inverse, symmetric = TRUE, only.values = TRUE)$values)
    for (g in groups) {
      mask <- if (g == "Residual") .gt_full_mask else .gt_mask(g)
      if (bitwAnd(mask, stratum$mask) != stratum$mask) next
      a <- if (g == "Residual") 1 else prod(prepared$counts[!.gt_bits(mask)])
      gradients[[g]] <- gradients[[g]] + a * H
      # Expected curvature of the -2 log likelihood, not ordinary log-likelihood information.
      diagonal_curvature[[g]] <- diagonal_curvature[[g]] + stratum$df * a^2 * diag(inverse)^2
      pooled_curvature[[g]] <- pooled_curvature[[g]] + stratum$df * a^2 * sum(inverse^2)
      # Upper bound for the Frobenius-operator curvature in standardized trait units.
      matrix_curvature_bound[[g]] <- matrix_curvature_bound[[g]] + stratum$df * a^2 * largest_inverse_eigenvalue^2
    }
  }
  psd_project <- function(M) {
    e <- eigen((M + t(M)) / 2, symmetric = TRUE)
    e$vectors %*% diag(pmax(e$values, 0), nrow(M)) %*% t(e$vectors)
  }
  summary <- list()
  projected <- list()
  for (g in groups) {
    G <- components[[g]]
    H <- (gradients[[g]] + t(gradients[[g]])) / 2
    type <- covariance_types[[g]]
    standardized_G <- standardizer %*% G %*% standardizer
    standardized_H <- unstandardizer %*% H %*% unstandardizer
    min_cov_eigen <- min(eigen(standardized_G, symmetric = TRUE, only.values = TRUE)$values)
    min_score_eigen <- min(eigen(standardized_H, symmetric = TRUE, only.values = TRUE)$values)
    complementarity <- sqrt(sum((standardized_H %*% standardized_G)^2))
    if (type == "diagonal") {
      h <- diag(H)
      v <- diag(G)
      scale <- 1 / sqrt(diagonal_curvature[[g]])
      lower <- if (g == "Residual") prepared$observed_variances * 1e-10 else rep(0, D)
      u <- (v - lower) / scale
      score <- h * scale
      projected[[g]] <- u - pmax(0, u - score)
      projected_norm <- max(abs(projected[[g]]))
      boundary <- v <= lower + boundary_tolerance * prepared$observed_variances
      boundary_bad <- any(boundary & score < -tolerance)
      # Only diagonal covariance directions are free for this type.
      min_score_eigen <- min(score)
      complementarity <- max(abs((v - lower) * h))
      scale_description <- "each variance scaled by inverse square root expected curvature"
    } else if (type == "pooled") {
      check_value <- mean(diag(G))
      if (max(abs(G - diag(check_value, D))) > 1e-8 * max(1, abs(check_value)))
        stop("A pooled covariance must equal a scalar times the identity.")
      h <- sum(diag(H))
      scale <- 1 / sqrt(pooled_curvature[[g]])
      lower <- if (g == "Residual") min(prepared$observed_variances) * 1e-10 else 0
      u <- (check_value - lower) / scale
      score <- h * scale
      projected[[g]] <- u - max(0, u - score)
      projected_norm <- abs(projected[[g]])
      boundary <- check_value <= lower + boundary_tolerance * min(prepared$observed_variances)
      boundary_bad <- boundary && score < -tolerance
      min_score_eigen <- score
      complementarity <- abs((check_value - lower) * h)
      scale_description <- "pooled variance scaled by inverse square root expected curvature"
    } else {
      curvature_root <- sqrt(matrix_curvature_bound[[g]])
      U <- standardized_G * curvature_root
      S <- standardized_H / curvature_root
      projected[[g]] <- U - psd_project(U - S)
      projected_norm <- sqrt(sum(projected[[g]]^2))
      boundary_bad <- min_cov_eigen <= boundary_tolerance &&
        min(eigen(S, symmetric = TRUE, only.values = TRUE)$values) < -tolerance
      min_score_eigen <- min(eigen(S, symmetric = TRUE, only.values = TRUE)$values)
      scale_description <- "trait-standardized PSD cone; scalar upper bound on expected curvature"
    }
    summary[[g]] <- data.frame(component = g, covariance_type = type,
      projected_score = projected_norm, tolerance = tolerance,
      stationary_within_tolerance = is.finite(projected_norm) && projected_norm <= tolerance,
      min_standardized_covariance_eigenvalue = min_cov_eigen,
      min_scaled_score_eigenvalue = min_score_eigen,
      complementarity_norm = complementarity,
      negative_score_at_boundary = boundary_bad, scaling = scale_description,
      row.names = NULL)
    gradients[[g]] <- H
  }
  tab <- do.call(rbind, summary)
  rownames(tab) <- NULL
  list(components = tab, gradients = gradients, projected_scores = projected,
       max_projected_score = max(tab$projected_score),
       stationary_within_tolerance = all(tab$stationary_within_tolerance),
       negative_score_at_boundary = any(tab$negative_score_at_boundary),
       reml = reml, tolerance = tolerance,
       interpretation = "Covariance-scale first-order stationarity only; does not establish a global optimum.")
}

  list(fit = fit_openmx_multivariate, prepare = gtheory_prepare,
       correlation = .gt_correlation,
       deviance = gtheory_deviance, moment_components = .gt_moment_components,
       optimization_diagnostics = gtheory_optimization_diagnostics)
}
