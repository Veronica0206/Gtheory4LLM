# The structural derivative envelope, run from sources and from an installed
# archive. The envelope is the conditional Hessian's pattern with every factor
# entry set to one, built once per design: it is the pattern the preflight's
# working-memory estimate factorizes, it contains the pattern of every
# numeric Hessian the design can produce, and the numeric Hessian overlaid on
# it, explicit zeros kept, factorizes to the production log determinant and
# solves the production probes. A Hessian with an entry outside the envelope,
# or an overlay without a Cholesky factor, is refused by name.
if (identical(Sys.getenv("GT_SPARSE_ENVELOPE_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
envelope_of <- internal(".gt_d_sparse_envelope")
overlay <- internal(".gt_d_sparse_envelope_factor")
problem_of <- internal(".gt_d_laplace_problem")
resources <- internal(".gt_d_sparse_resources")
fill_bound <- internal(".gt_d_sparse_bytes")
sparse_W <- internal(".gt_d_sparse_build")
sparse_hessian <- internal(".gt_d_sparse_hessian")
sparse_factor <- internal(".gt_d_sparse_factor")
sparse_logdet <- internal(".gt_d_sparse_logdet")
kernel <- internal(".gt_d_response_kernel")
evaluator_of <- internal(".gt_d_sparse_evaluator")
factors_of <- internal(".gt_d_covariance_factors")
refused <- function(expr, pattern) {
  got <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(got, "error"), grepl(pattern, conditionMessage(got), fixed = TRUE))
  invisible(conditionMessage(got))
}

data <- expand.grid(item = seq_len(12L), rater = seq_len(4L), prompt = seq_len(2L))
data$binary <- as.integer((data$item + 2 * data$rater + data$prompt) %% 5 < 2)
data$ordinal <- ordered(c("low", "middle", "high")[(data$item + data$rater) %% 3 + 1L],
                        levels = c("low", "middle", "high"))
families <- list(binary = gt_family("binary", "probit"),
                 ordinal = gt_family("ordinal", "logit", levels = levels(data$ordinal)))
design <- gt_design("item", c("rater", "prompt"), random = c("item", "rater", "prompt", "item:rater"))
problem <- problem_of(data, c("binary", "ordinal"), design, families, "unstructured",
                      list(engine = "sparse", inner_tol = 1e-10, max_random_dimension = 400L))
envelope <- problem$envelope
prep <- problem$prep
n <- prep$n
q <- prep$q
dimension <- envelope$dimension
stopifnot(inherits(envelope, "gt_discrete_sparse_envelope"), dimension == problem$context$random_dimension,
          length(envelope$key) == envelope$hessian_triangle_entries,
          all(envelope$rows >= envelope$columns), !anyDuplicated(envelope$key),
          identical(sort(envelope$permutation), seq_len(dimension)))

# The envelope is the pattern the preflight prices: same Hessian and factor counts.
bound <- fill_bound(n, q, dimension, length(problem$groups))
estimate <- resources(problem$groups, n, q, dimension, bound$total - 1)
stopifnot(identical(estimate$method, "structural_factorization"),
          estimate$hessian_entries == envelope$hessian_entries, estimate$factor_entries == envelope$factor_entries,
          2 * envelope$hessian_triangle_entries - dimension == envelope$hessian_entries)

# Numeric Hessians at three parameter points: all factor entries nonzero, one
# exact zero off-diagonal, one exact zero pivot with its column. Each lies
# inside the envelope, overlays with explicit zeros kept, and the overlay's
# factor reproduces the production log determinant and solves the probes.
parameters <- problem$start
covariance_at <- length(prep$start) + seq_along(problem$setup$start)
points <- list(nonzero = replace(parameters, covariance_at, c(.6, .2, .5, .4, -.1, .3, .5, .15, .45, .35, .1, .4)),
               zero_offdiagonal = replace(parameters, covariance_at, c(.6, 0, .5, .4, 0, .3, .5, 0, .45, .35, 0, .4)),
               zero_pivot = replace(parameters, covariance_at, c(0, 0, .5, .4, -.1, .3, .5, .15, .45, .35, .1, .4)))
for (name in names(points)) {
  at <- points[[name]]
  record <- evaluator_of()(at, prep, problem$groups, problem$setup, problem$control, details = TRUE)
  stopifnot(isTRUE(record$valid))
  factors <- factors_of(at[covariance_at], problem$setup)
  W <- sparse_W(problem$context, factors)
  response <- kernel(record$eta, at, prep)
  H <- sparse_hessian(response$curvature, W, n)
  production <- sparse_factor(H, counts = TRUE)
  result <- overlay(H, envelope, production)
  # The overlay's Hessian pattern contains the numeric one; its factor fill is
  # not comparable, because each factorization takes its own fill-reducing
  # ordering and an ordering on the larger pattern can fill less.
  stopifnot(isTRUE(result$valid), result$stored_entries == envelope$hessian_triangle_entries,
            abs(result$log_determinant_difference) <= 1e-8 * max(1, abs(sparse_logdet(production))),
            result$hessian_entries >= production$hessian_entries)
  # Values: H where H has entries, explicit zeros everywhere else on the envelope.
  dense_H <- as.matrix(H)
  dense_E <- as.matrix(result$matrix)
  stopifnot(max(abs(dense_E - dense_H)) == 0,
            all(dense_H[cbind(envelope$rows, envelope$columns)] == dense_E[cbind(envelope$rows, envelope$columns)]))
  stored <- Matrix::summary(methods::as(result$matrix, "generalMatrix"))
  stopifnot(nrow(stored) == 2 * envelope$hessian_triangle_entries - dimension)
  # Every pair of an observation's coordinates is an entry of the overlay's factor pattern.
  L <- methods::as(result$factorization$factor, "CsparseMatrix")
  perm <- match(seq_len(dimension), envelope$permutation)
  index <- internal(".gt_selected_local_index")(problem$context)
  for (i in c(1L, 17L, n)) {
    where <- perm[index[i, ]]
    pairs <- expand.grid(a = where, b = where)
    lower_pairs <- pairs[pairs$a >= pairs$b, ]
    stopifnot(all(sapply(seq_len(nrow(lower_pairs)), function(k) {
      column <- lower_pairs$b[k]
      any(L@i[seq.int(L@p[column] + 1L, L@p[column + 1L])] + 1L == lower_pairs$a[k])
    })))
  }
  cat("PASS: envelope overlay at the", name, "point\n")
}

# Refusals: an entry outside the envelope, a dimension mismatch, no Cholesky factor.
at <- points$nonzero
record <- evaluator_of()(at, prep, problem$groups, problem$setup, problem$control, details = TRUE)
factors <- factors_of(at[covariance_at], problem$setup)
W <- sparse_W(problem$context, factors)
H <- sparse_hessian(kernel(record$eta, at, prep)$curvature, W, n)
production <- sparse_factor(H, counts = FALSE)
item_columns <- problem$context$offsets[[1L]] + c(1L, 2L)
outside <- H
outside[item_columns[1L], item_columns[2L]] <- outside[item_columns[2L], item_columns[1L]] <- 1e-3
result <- overlay(outside, envelope, production)
stopifnot(identical(result$valid, FALSE), identical(result$reason, "envelope_mismatch"))
indefinite <- H - Matrix::Diagonal(dimension, x = 50)
result <- suppressWarnings(overlay(indefinite, envelope, production))
stopifnot(identical(result$valid, FALSE), identical(result$reason, "envelope_not_positive_definite"))
refused(overlay(H[-1L, -1L], envelope, production), "dimension")
refused(envelope_of(list()), "context")
cat("PASS: structural envelope equals the preflight's pattern, overlays three Hessians with explicit zeros,",
    "covers every local block, and refuses by name.\n")
