# The structural derivative envelope of a sparse discrete design.
#
# The analytic gradient reads entries of H^{-1} wherever a derivative of the
# conditional Hessian H = I + W' C W can be nonzero, and a derivative can be
# nonzero where H's current entry is zero: a factor coefficient at zero still
# has a derivative, and a diagonal curvature leaves latent dimensions of one
# observation uncoupled that a derivative couples. The selected inverse is
# computed on a Cholesky factor's own pattern and refuses an absent entry, so
# the factor it runs on must come from a pattern that contains every such
# entry. That pattern is the envelope: the conditional Hessian of the same
# design with every factor entry set to one, so that every latent dimension of
# an observation is coupled and every source's coordinates for that
# observation are coupled to every other source's. It is the pattern the
# preflight's working-memory estimate already factorizes, built once per
# design because it does not depend on the parameters.
#
# At an evaluation the numeric H is overlaid into the envelope: its values are
# placed at their positions and every other envelope position holds an
# explicit zero, so the factorization keeps the whole pattern. The overlay is
# checked before it is used: H's own pattern must lie inside the envelope,
# the envelope factor must solve the same two probes the production factor
# solves, and its log determinant must agree with the production factor's.
# The production mode, value and factor are never replaced; the envelope
# factor serves the gradient only.

.gt_d_sparse_envelope <- function(context) {
  if (!inherits(context, "gt_discrete_sparse_context"))
    .gt_d_stop("A structural envelope needs a context from .gt_d_sparse_context().")
  q <- context$q
  ones <- rep(list(matrix(1, q, q)), length(context$groups))
  W <- .gt_d_sparse_build(context, ones)
  H <- Matrix::Diagonal(ncol(W)) + Matrix::crossprod(W)
  general <- methods::as(methods::as(H, "generalMatrix"), "CsparseMatrix")
  dimension <- ncol(general)
  columns <- rep(seq_len(dimension), diff(general@p))
  rows <- general@i + 1L
  lower <- rows >= columns
  rows <- rows[lower]
  columns <- columns[lower]
  factorization <- .gt_d_sparse_factor(H, permute = TRUE, counts = TRUE)
  permutation <- if (length(factorization$factor@perm))
    as.integer(factorization$factor@perm) + 1L else seq_len(dimension)
  structure(list(rows = rows, columns = columns,
                 key = (as.double(columns) - 1) * dimension + rows,
                 dimension = dimension, random_dimension = dimension,
                 hessian_triangle_entries = length(rows),
                 hessian_entries = factorization$hessian_entries,
                 factor_entries = factorization$factor_entries,
                 permutation = permutation,
                 groups = context$groups, n = context$n, q = q),
            class = "gt_discrete_sparse_envelope")
}

# The envelope key of a symmetric sparse matrix's lower triangle, with its values.
.gt_d_sparse_envelope_triangle <- function(H) {
  general <- methods::as(methods::as(H, "generalMatrix"), "CsparseMatrix")
  dimension <- ncol(general)
  columns <- rep(seq_len(dimension), diff(general@p))
  rows <- general@i + 1L
  lower <- rows >= columns
  list(key = (as.double(columns[lower]) - 1) * dimension + rows[lower], x = general@x[lower],
       dimension = dimension)
}

# The numeric conditional Hessian factorized on the envelope's pattern. The
# production factorization is the authority: the envelope factor must solve
# the probes and reproduce its log determinant, or the gradient is refused.
.gt_d_sparse_envelope_factor <- function(H, envelope, production) {
  if (!inherits(envelope, "gt_discrete_sparse_envelope"))
    .gt_d_stop("An envelope factorization needs an envelope from .gt_d_sparse_envelope().")
  if (!methods::is(H, "sparseMatrix") || nrow(H) != ncol(H) || nrow(H) != envelope$dimension)
    .gt_d_stop("The conditional Hessian does not match the envelope's dimension.")
  if (!inherits(production, "gt_discrete_sparse_factor"))
    .gt_d_stop("An envelope factorization needs the production factorization to compare with.")
  triangle <- .gt_d_sparse_envelope_triangle(H)
  position <- match(triangle$key, envelope$key)
  if (anyNA(position))
    return(list(valid = FALSE, reason = "envelope_mismatch",
                detail = sprintf("%d entries of the conditional Hessian lie outside the structural envelope",
                                 sum(is.na(position)))))
  x <- numeric(length(envelope$key))
  x[position] <- triangle$x
  # Built from explicit triplets so that every envelope position, including
  # the ones that hold an exact zero, is a stored entry of the matrix the
  # factorization sees.
  overlaid <- Matrix::sparseMatrix(i = envelope$rows, j = envelope$columns, x = x,
                                   dims = c(envelope$dimension, envelope$dimension), symmetric = TRUE)
  factorization <- tryCatch(.gt_d_sparse_factor(overlaid, permute = TRUE, counts = TRUE),
                            error = function(e) NULL)
  if (is.null(factorization))
    return(list(valid = FALSE, reason = "envelope_not_positive_definite",
                detail = "the overlaid conditional Hessian has no Cholesky factor"))
  probes <- .gt_d_sparse_final_factor_check(overlaid, factorization)
  if (!isTRUE(probes$valid))
    return(c(list(valid = FALSE, reason = "envelope_factor_invalid",
                  detail = "the envelope factor does not solve its own probes"), probes))
  logdet <- .gt_d_sparse_logdet(factorization)
  reference <- .gt_d_sparse_logdet(production)
  tolerance <- 1e-8 * max(1, abs(reference))
  if (!is.finite(logdet) || abs(logdet - reference) > tolerance)
    return(list(valid = FALSE, reason = "envelope_mismatch",
                detail = sprintf("log determinant %.12g on the envelope against %.12g on the production factor",
                                 logdet, reference)))
  list(valid = TRUE, factorization = factorization, matrix = overlaid, log_determinant = logdet,
       log_determinant_difference = logdet - reference,
       factor_entries = factorization$factor_entries, hessian_entries = factorization$hessian_entries,
       stored_entries = length(envelope$key))
}
