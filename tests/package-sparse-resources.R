# The two-stage sparse working-memory estimate, run from sources and from an
# installed archive. The estimate is a planning guard: it must contain the
# pattern of any conditional Hessian the fit can assemble, refuse without
# allocating when the Hessian alone cannot fit, and never exceed the old
# complete-fill bound.
if (identical(Sys.getenv("GT_SPARSE_RESOURCES_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
resources <- internal(".gt_d_sparse_resources")
fill_bound <- internal(".gt_d_sparse_bytes")
pair_bound <- internal(".gt_d_sparse_pair_bound")
sparse_W <- internal(".gt_d_sparse_W")
sparse_factor <- internal(".gt_d_sparse_factor")

# A crossed design: 30 items by 4 raters by 2 prompts, two latent dimensions.
set.seed(20261023)
d <- expand.grid(item = seq_len(30), rater = seq_len(4), prompt = seq_len(2))
n <- nrow(d)
q <- 2L
level_index <- function(x) list(index = as.integer(factor(x)), nlevels = length(unique(x)))
groups <- list(item = level_index(d$item), rater = level_index(d$rater),
               prompt = level_index(d$prompt),
               "item:rater" = level_index(paste(d$item, d$rater)))
dimension <- sum(vapply(groups, `[[`, integer(1), "nlevels")) * q

bound <- fill_bound(n, q, dimension, length(groups))
pairs <- pair_bound(groups, n, q)
stopifnot(is.finite(pairs), pairs > 0, pairs < dimension^2)

# Stage zero: a budget the complete-fill bound already fits keeps that bound.
within <- resources(groups, n, q, dimension, Inf)
stopifnot(identical(within$method, "complete_fill_bound"), within$total == bound$total,
          is.na(within$factor_entries), within$pair_bound_entries == pairs)

# Stage one: the pair-count floor is refused without building a pattern.
floor_total <- 2 * (bound$random_design + bound$predictors + 12 * pairs)
stopifnot(floor_total < bound$total)
refused <- resources(groups, n, q, dimension, floor_total - 1)
stopifnot(identical(refused$method, "pair_bound_exceeds_budget"), refused$total == floor_total,
          is.na(refused$factor_entries), is.na(refused$hessian_entries))

# Stage two: the structural pattern is factorized once.
structural <- resources(groups, n, q, dimension, floor_total)
stopifnot(identical(structural$method, "structural_factorization"),
          structural$hessian_entries <= pairs,
          structural$factor_entries >= dimension,
          structural$total <= bound$total,
          structural$total == 2 * (bound$random_design + bound$predictors +
            12 * (structural$hessian_entries + structural$factor_entries)))

# The structural pattern contains the pattern of an actual conditional Hessian
# whose factors have zeros (a diagonal factor for one source), and the counted
# factor fill is at least the pattern's own lower triangle.
factors <- list(matrix(c(.8, .3, 0, .5), q), diag(c(.4, .9)), matrix(c(.2, .1, 0, .6), q),
                matrix(c(.3, 0, 0, .3), q))
W <- sparse_W(groups, factors, n, q)
actual <- Matrix::Diagonal(ncol(W)) + Matrix::crossprod(W)
pattern <- Matrix::Diagonal(dimension) +
  Matrix::crossprod(sparse_W(groups, rep(list(matrix(1, q, q)), length(groups)), n, q))
stopifnot(Matrix::nnzero(actual) <= structural$hessian_entries,
          Matrix::nnzero(pattern) == structural$hessian_entries,
          Matrix::nnzero(Matrix::tril(Matrix::forceSymmetric(pattern))) <= structural$factor_entries,
          Matrix::nnzero(Matrix::tril(Matrix::forceSymmetric(pattern))) ==
            sparse_factor(pattern, permute = TRUE, counts = TRUE)$hessian_triangle_entries)
# Every entry of the actual pattern is an entry of the structural pattern.
occupied <- Matrix::which(actual != 0)
stopifnot(length(occupied) == Matrix::nnzero(actual), all(as.vector(pattern[occupied]) != 0))

# The public paths name the method. Two binary outcomes on the crossed design.
d$a <- as.integer(runif(n) < plogis(rnorm(30)[d$item] + .3 * rnorm(4)[d$rater]))
d$b <- as.integer(runif(n) < plogis(rnorm(30)[d$item]))
d$a[1:3] <- 1L - d$a[1:3]
d$b[1:3] <- 1L - d$b[1:3]
design <- gt_design("item", c("rater", "prompt"), random = ~ item + rater + prompt + item:rater)
families <- gt_family("binary", link = "probit")
pre_default <- gt_preflight(d, c("a", "b"), design, family = families,
  control = gt_control(discrete = list(engine = "sparse", max_random_dimension = 400L)))
stopifnot(identical(pre_default$resources$sparse_estimate_method, "complete_fill_bound"))
# Preflight orders the sources its own way, so its fill-reducing ordering can
# count a different fill than the hand-built groups above; the sharp boundary
# is therefore tested against preflight's own structural estimate.
pre_structural <- gt_preflight(d, c("a", "b"), design, family = families,
  control = gt_control(discrete = list(engine = "sparse", max_random_dimension = 400L, max_sparse_bytes = bound$total - 1)))
estimate <- pre_structural$resources$sparse_working_bytes_estimate
stopifnot(identical(pre_structural$resources$sparse_estimate_method, "structural_factorization"),
          estimate < bound$total, estimate > floor_total,
          pre_structural$resources$sparse_structural_entries$factor_entries >= dimension,
          pre_structural$resources$sparse_structural_entries$hessian_entries == structural$hessian_entries,
          !"sparse_memory_limit" %in% pre_structural$checks$check[!pre_structural$checks$passed])
pre_exact <- gt_preflight(d, c("a", "b"), design, family = families,
  control = gt_control(discrete = list(engine = "sparse", max_random_dimension = 400L, max_sparse_bytes = estimate)))
stopifnot(pre_exact$resources$sparse_working_bytes_estimate == estimate,
          !"sparse_memory_limit" %in% pre_exact$checks$check[!pre_exact$checks$passed])
pre_short <- gt_preflight(d, c("a", "b"), design, family = families,
  control = gt_control(discrete = list(engine = "sparse", max_random_dimension = 400L, max_sparse_bytes = estimate - 1)))
stopifnot(identical(pre_short$resources$sparse_estimate_method, "structural_factorization"),
          "sparse_memory_limit" %in% pre_short$checks$check[!pre_short$checks$passed])
pre_refused <- gt_preflight(d, c("a", "b"), design, family = families,
  control = gt_control(discrete = list(engine = "sparse", max_random_dimension = 400L, max_sparse_bytes = 1)))
stopifnot(identical(pre_refused$resources$sparse_estimate_method, "pair_bound_exceeds_budget"),
          "sparse_memory_limit" %in% pre_refused$checks$check[!pre_refused$checks$passed])
refusal <- tryCatch(gt_fit(d, c("a", "b"), design, family = families,
  control = gt_control(discrete = list(engine = "sparse", max_random_dimension = 400L, max_sparse_bytes = 1))),
  error = conditionMessage)
stopifnot(is.character(refusal), grepl("max_sparse_bytes", refusal, fixed = TRUE),
          grepl("structural nonzeros alone", refusal, fixed = TRUE))
cat("PASS: two-stage sparse memory estimate; pattern containment; preflight and fit refusals name the method.\n")
