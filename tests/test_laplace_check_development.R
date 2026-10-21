# Small public sparse-fit regression: Call reconstruction and dense budgets.
# The larger existing Laplace-accuracy study and mandatory draw counts remain
# unchanged. These fixtures exercise integration and early refusal only.
source("load_functions.R")
expect <- function(ok, message) if (!isTRUE(ok)) stop(message)
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  expect(inherits(error, "error") && grepl(pattern, conditionMessage(error)),
         paste("Expected refusal containing", pattern))
}
panel <- expand.grid(item = seq_len(8L), rater = seq_len(2L))
# Non-adjacent recorded batches make re-inferring from row order incorrect.
panel$call_id <- paste((panel$item - 1L) %% 4L, panel$rater, sep = "-")
panel$y <- as.integer((panel$item + panel$rater) %% 3L > 0L)
design <- gt_design("item", "rater", random = c("item", "rater"),
  batch = gt_batch(2, id = "call_id"))
fit <- gt_fit(panel, "y", design, gt_family("binary", "logit"),
  control = gt_control(discrete = list(engine = "sparse", optimizer = "nlminb",
    fixed_covariance = list(item = matrix(0.1), rater = matrix(0.05), Call = matrix(0.3)))))
expect(isTRUE(fit$numerically_accepted), "The sparse Call fixture passes all acceptance gates")
expect(!"call_id" %in% names(fit$data), "Retained model data omit the original auxiliary call IDs")
actual <- .gt_laplace_call_group(fit$data, fit$design, fit$covariance_components)
expect(identical(outer(actual$index, actual$index, `==`),
                 outer(panel$call_id, panel$call_id, `==`)),
       "Reconstructed groups agree with independently recorded call membership")
check <- gt_laplace_check(fit, method = "importance", draws = 100L, seed = 71L)
expect(check$available && check$recomputed_agrees && check$random_dimension == 18L,
       "The dense checker reconstructs every source and matches the sparse fitted objective")
expect(!check$usable && check$draws == 100L,
       "A small integration regression cannot bypass the mandatory 200-ESS screen")
expect(check$resources$total > check$resources$dense$total && check$resources$integration > 0,
       "The diagnostic reports dense and integration workspace estimates")

# Removing retained data still permits the documented modeled-only data input;
# row permutations preserve the likelihood and the stored item-to-batch map.
private <- fit
private$data <- NULL
permutation <- c(seq(2L, nrow(panel), 2L), seq(1L, nrow(panel), 2L))
reordered <- gt_laplace_check(private, method = "importance", draws = 100L, seed = 71L,
  data = panel[permutation, c("item", "rater", "y")])
expect(reordered$available && reordered$recomputed_agrees &&
         abs(reordered$laplace_minus2loglik - check$laplace_minus2loglik) < 1e-7,
       "Call reconstruction is independent of row order and auxiliary-column retention")
provided <- gt_laplace_check(private, method = "importance", draws = 100L, seed = 71L, data = panel)
expect(provided$available && provided$recomputed_agrees,
       "Supplied call IDs are checked against retained membership")
changed <- panel
changed$call_id <- paste(ceiling(changed$item / 2L), changed$rater, sep = "-")
expect_error(gt_laplace_check(private, method = "importance", draws = 100L, seed = 71L,
  data = changed), "disagree with the fitted Call layout")
expect_error(gt_laplace_check(private, method = "importance", draws = 100L, seed = 71L,
  data = panel[-1L, ]), "complete balanced panel")
missing_layout <- fit
missing_layout$design$batch_model$item_batches <- NULL
expect_error(gt_laplace_check(missing_layout, seed = 71L), "retained item-to-batch layout")
missing_item <- panel
missing_item$item[missing_item$item == 8L] <- 9L
expect_error(gt_laplace_check(private, seed = 71L, data = missing_item), "items do not match")
stopped <- fit
stopped$numerically_accepted <- FALSE
at_stop <- gt_laplace_check(stopped, method = "importance", draws = 100L, seed = 71L)
expect(at_stop$available && !at_stop$numerically_accepted,
       "The diagnostic still describes a rejected fit's fixed stopping point")

# Call is not reserved when it names an ordinary declared source without a
# modelled batch. It follows the standard source path, never virtual grouping.
ordinary <- panel[c("item", "rater", "y")]
names(ordinary)[names(ordinary) == "rater"] <- "Call"
ordinary_fit <- gt_fit(ordinary, "y", gt_design("item", "Call", random = c("item", "Call")),
  gt_family("binary", "logit"), control = gt_control(discrete = list(engine = "sparse",
    optimizer = "nlminb", fixed_covariance = list(item = matrix(0.1), Call = matrix(0.3)))))
ordinary_check <- gt_laplace_check(ordinary_fit, method = "importance", draws = 100L, seed = 71L)
expect(ordinary_fit$numerically_accepted && ordinary_check$available &&
         ordinary_check$recomputed_agrees && ordinary_check$random_dimension == 10L,
       "An ordinary declared Call source without a batch remains supported")
unexplained <- fit
unexplained$design$batch_model <- NULL
expect_error(gt_laplace_check(unexplained, seed = 71L), "no retained modelled layout")

# Deliberately fault the dense allocator: both a dense reconstruction overrun
# and an integration-only overrun must refuse before reaching it. No large
# matrix or one-million-draw vector is actually allocated by these tests.
saved_backend <- .gt_d_dense_backend
.gt_d_dense_backend <- function(...) stop("DENSE_BACKEND_REACHED")
tryCatch({
  tiny <- fit
  tiny$control$discrete$max_dense_bytes <- 1
  expect_error(gt_laplace_check(tiny, method = "importance", draws = 100L, seed = 71L),
               "exceeding max_dense_bytes")
  proposal_limited <- fit
  proposal_limited$control$discrete$max_dense_bytes <- 2 * check$resources$dense$total
  expect_error(gt_laplace_check(proposal_limited, method = "importance", draws = 1000000L, seed = 71L),
               "exceeding max_dense_bytes")
  expect_error(gt_laplace_check(fit, method = "importance", draws = 99L, seed = 71L),
               "draws must be")
  expect_error(gt_laplace_check(fit, method = "importance", draws = 101L,
    max_evaluations = 100L, seed = 71L), "more than max_evaluations")
}, finally = { .gt_d_dense_backend <- saved_backend })
quadrature <- .gt_laplace_resources(16L, 1L, 3L, "quadrature", 20L, 100L)
expect(quadrature$total > quadrature$dense$total && quadrature$integration > 0,
       "Quadrature grids are also included in the dense workspace budget")
cat("PASS: retained Call reconstruction, sparse-fit dense diagnostics, and pre-allocation budgets.\n")
