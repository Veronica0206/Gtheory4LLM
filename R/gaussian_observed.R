# A bounded observed-row likelihood for incomplete univariate Gaussian panels.
# Missing whole cells are absent observations, never filled or silently dropped.
# This dense reference checks lme4's likelihood; it is not a large-panel engine.

.gt_gaussian_observed_bytes <- function(rows, sources) {
  # Source kernels, centered kernel vectors for identification, and conservative
  # Cholesky/cross-product working space. Caller data and lme4 are additional.
  8 * as.double(rows)^2 * (4 * (as.double(sources) + 1) + 10)
}

.gt_gaussian_observed_prepare <- function(data, outcomes, design,
                                          max_observed_rows = 1000L,
                                          max_preparation_bytes = 512 * 1024^2) {
  if (length(outcomes) != 1L)
    stop("Observed-row Gaussian fitting supports one outcome only; joint incomplete panels are not implemented.",
         call. = FALSE)
  if (!is.null(design$batch))
    stop("Observed-row Gaussian fitting does not support declared batches or shared-call effects.", call. = FALSE)
  if (!identical(design$replicates, 1L))
    stop("Observed-row Gaussian fitting requires one observation per observed cell; replication is not supported.",
         call. = FALSE)
  if (!is.numeric(max_observed_rows) || length(max_observed_rows) != 1L ||
      !is.finite(max_observed_rows) || max_observed_rows < 2 ||
      max_observed_rows != floor(max_observed_rows))
    stop("max_observed_rows must be one finite integer of at least two.", call. = FALSE)
  if (!is.numeric(max_preparation_bytes) || length(max_preparation_bytes) != 1L ||
      !is.finite(max_preparation_bytes) || max_preparation_bytes <= 0)
    stop("max_preparation_bytes must be a positive finite number of bytes.", call. = FALSE)
  variables <- c(design$object, design$facets)
  if (!is.data.frame(data) || !nrow(data) || anyDuplicated(names(data)) ||
      !all(c(variables, outcomes) %in% names(data)))
    stop("Observed-row Gaussian fitting requires a nonempty data frame with outcome and design columns.",
         call. = FALSE)
  N <- nrow(data)
  if (N > max_observed_rows)
    stop("Observed-row Gaussian fitting exceeds max_observed_rows (", max_observed_rows,
         "); the independent dense likelihood check is explicitly bounded.", call. = FALSE)
  estimated_bytes <- .gt_gaussian_observed_bytes(N, length(design$terms))
  if (!is.finite(estimated_bytes) || estimated_bytes > max_preparation_bytes)
    stop("Observed-row Gaussian preparation allocation estimate exceeds max_preparation_bytes.", call. = FALSE)
  y <- data[[outcomes]]
  if (!is.numeric(y) || any(!is.finite(y)))
    stop("The Gaussian outcome must be numeric with no missing or non-finite values; omit absent whole cells explicitly.",
         call. = FALSE)
  if (length(unique(y)) < 2L)
    stop("Constant outcomes do not identify trait variance or correlations.", call. = FALSE)
  counts <- vapply(data[variables], function(x) {
    if (!is.atomic(x) || anyNA(x) || (is.numeric(x) && any(!is.finite(x))))
      stop("Design variables must have finite, nonmissing atomic values.", call. = FALSE)
    length(unique(x))
  }, integer(1))
  if (any(counts < 2L))
    stop("The object and every facet need at least two observed levels.", call. = FALSE)
  if (anyDuplicated(.gt_tuple_key(data, variables)))
    stop("Observed-row Gaussian fitting requires exactly one row per observed cell.", call. = FALSE)
  if (!length(design$terms))
    stop("Observed-row Gaussian fitting requires at least one retained random source.", call. = FALSE)
  if (!design$object %in% design$terms)
    stop("Gaussian random sources must include the object main effect.", call. = FALSE)
  kernels <- lapply(design$terms, function(term) {
    members <- design$term_members[[term]]
    if (is.null(members)) members <- strsplit(term, ":", fixed = TRUE)[[1L]]
    groups <- .gt_tuple_key(data, members)
    if (length(unique(groups)) < 2L || length(unique(groups)) >= N)
      stop("Observed-row source '", term,
           "' has fewer than two groups or is aliased with the observation residual.", call. = FALSE)
    1 * outer(groups, groups, `==`)
  })
  names(kernels) <- design$terms
  kernels$Residual <- diag(N)
  # Check covariance identification on the intercept-free observation space.
  # Independent raw kernels alone are insufficient for REML when their
  # difference can be absorbed by the fixed-intercept space.
  centered <- vapply(kernels, function(K) {
    means <- rowMeans(K)
    as.vector(sweep(sweep(K, 1L, means), 2L, means) + mean(means))
  }, numeric(N * N))
  norms <- sqrt(colSums(centered^2))
  if (any(!is.finite(norms)) || any(norms <= .Machine$double.eps))
    stop("Observed-row covariance sources are not identifiable after removing the fixed intercept.", call. = FALSE)
  normalized <- sweep(centered, 2L, norms, `/`)
  eigenvalues <- eigen(crossprod(normalized), symmetric = TRUE, only.values = TRUE)$values
  tolerance <- 1e-8
  rank <- sum(eigenvalues > tolerance * max(eigenvalues))
  if (rank != length(kernels))
    stop("Observed-row covariance source kernels are linearly dependent after removing the fixed intercept; the incomplete design does not identify all requested components.",
         call. = FALSE)
  list(N = N, D = 1L, outcomes = outcomes, facets = stats::setNames(variables, variables),
       counts = counts, means = stats::setNames(mean(y), outcomes),
       observed_variances = stats::setNames(stats::var(y), outcomes),
       y = y, kernels = kernels, panel_type = "observed",
       complete_balanced = as.double(N) == prod(as.double(counts)),
       resources = list(rows = N, max_observed_rows = max_observed_rows,
         estimated_preparation_bytes = estimated_bytes, max_preparation_bytes = max_preparation_bytes),
       identification = list(checked = TRUE, rank = rank, components = length(kernels),
         normalized_kernel_eigenvalues = eigenvalues, relative_tolerance = tolerance,
         scope = "Linear independence of source and residual covariance kernels after removing the fixed intercept; this is not a finite-sample precision guarantee."))
}

.gt_gaussian_observed_deviance <- function(prepared, components, reml = TRUE) {
  if (!is.list(components) || is.null(names(components)) || anyDuplicated(names(components)) ||
      !setequal(names(components), names(prepared$kernels)))
    stop("Observed-row likelihood needs exactly the declared source and residual components.", call. = FALSE)
  variances <- vapply(components[names(prepared$kernels)], function(M) {
    if (!is.matrix(M) || !identical(dim(M), c(1L, 1L)) ||
        !is.numeric(M) || !is.finite(M[1L, 1L]) || M[1L, 1L] < 0)
      stop("Observed-row covariance components must be finite nonnegative one-by-one matrices.", call. = FALSE)
    M[1L, 1L]
  }, numeric(1))
  if (variances[["Residual"]] <= 0)
    stop("Observed-row likelihood requires positive observation residual variance.", call. = FALSE)
  if (!is.logical(reml) || length(reml) != 1L || is.na(reml))
    stop("reml must be TRUE or FALSE.", call. = FALSE)
  V <- matrix(0, prepared$N, prepared$N)
  for (name in names(variances)) V <- V + variances[[name]] * prepared$kernels[[name]]
  R <- chol(V)
  # Center first to avoid subtracting two large estimated means; the profiled
  # likelihood is invariant to this common intercept translation.
  white <- forwardsolve(t(R), cbind(1, prepared$y - mean(prepared$y)))
  information <- sum(white[, 1L]^2)
  beta <- sum(white[, 1L] * white[, 2L]) / information
  quadratic <- sum((white[, 2L] - white[, 1L] * beta)^2)
  (prepared$N - as.integer(reml)) * log(2 * pi) + 2 * sum(log(diag(R))) +
    quadratic + if (reml) log(information) else 0
}
