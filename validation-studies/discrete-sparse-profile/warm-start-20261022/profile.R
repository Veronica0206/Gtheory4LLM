# Per-evaluation profile: one cold and one warm evaluation, the components of
# one Newton step, and the fixed-pattern Hessian assembly prototype that was
# measured and not adopted. Run from the project directory with the panel name:
#   Rscript --vanilla validation-studies/discrete-sparse-profile/warm-start-20261022/profile.R synthetic
#   Rscript --vanilla validation-studies/discrete-sparse-profile/warm-start-20261022/profile.R native
# Light before-measurements: one cold and one warm evaluation, step components,
# and a fixed-pattern Hessian assembly prototype timed against the current one.
suppressMessages(library(Matrix)); source("load_functions.R")
HERE <- file.path("validation-studies", "discrete-sparse-profile", "warm-start-20261022")
source(file.path(HERE, "synthetic-panel.R"))
panel <- commandArgs(TRUE)[[1]]
med <- function(expr, k = 3L) { e <- substitute(expr); env <- parent.frame(); t <- numeric(k)
  for (i in seq_len(k)) t[i] <- system.time(eval(e, env))[["elapsed"]]; median(t) }
if (panel == "native") {
  data <- gt_example("hate_speech", coding = "native")$data
  design <- gt_design("item", c("evaluator", "prompt", "temp", "seed"), crossed = c("evaluator", "prompt"),
                      nested = list(temp = c("evaluator", "prompt"), seed = "temp"), item_nested = "temp")
  members <- design$term_members; outcome <- "score"
  families <- list(list(family = "ordinal", link = "probit", levels = levels(data[[outcome]])))
  control <- .gt_d_control(list(engine = "sparse", max_observations = 21600L, max_random_dimension = 9507L,
                                max_parameters = 12L, max_sparse_bytes = 6 * 1024^3))
} else {
  synthetic <- synthetic_panel(); data <- synthetic$data; outcome <- "y"
  members <- synthetic$members; families <- synthetic$families
  control <- .gt_d_control(list(engine = "sparse", max_observations = 21600L, max_random_dimension = 819L))
}
cat("sources:", paste(names(members), collapse = ", "), "\n")
prep <- .gt_d_prepare(data, outcome, families)
groups <- lapply(members, function(m) .gt_d_group(data, m))
setup <- .gt_d_covariance_setup(groups, prep$q, "diagonal", control, prep$dimensions)
theta <- c(prep$start, setup$start)
if (panel != "native") theta <- setNames(unlist(jsonlite::fromJSON(file.path(HERE, "before-synthetic-21600-lbfgsb-summary.json"), simplifyVector = FALSE)$diagnostics$stability$tight_parameters[[1]]), names(theta))
d <- sum(vapply(groups, `[[`, integer(1), "nlevels")) * prep$q
cat(sprintf("n=%d  parameters=%d  random dimension=%d\n", prep$n, length(theta), d))
ctx <- .gt_d_sparse_context(groups, prep$n, prep$q)
factors <- .gt_d_covariance_factors(theta[-seq_along(prep$start)], setup)
backend <- .gt_d_sparse_backend_from(ctx, factors); W <- backend$W
t0 <- system.time(cold <- .gt_d_sparse_mode(theta, prep, backend, control, details = TRUE))[["elapsed"]]
cat(sprintf("cold evaluation: %.2f s, valid=%s, %d Newton steps, nll=%.6f\n", t0, isTRUE(cold$valid), cold$inner_iterations, cold$nll))
j <- length(prep$start) + 1L; theta_nb <- theta; theta_nb[[j]] <- theta_nb[[j]] + 1e-3 * max(1, abs(theta_nb[[j]]))
nb <- .gt_d_sparse_mode(theta_nb, prep, .gt_d_sparse_backend_from(ctx, .gt_d_covariance_factors(theta_nb[-seq_along(prep$start)], setup)), control, details = TRUE)
t1 <- system.time(warm <- .gt_d_sparse_mode(theta, prep, backend, control, details = TRUE, start = nb$mode))[["elapsed"]]
cat(sprintf("warm evaluation from neighbour's mode: %.2f s, %d Newton steps, nll diff %.2e, max|mode diff| %.2e\n",
            t1, warm$inner_iterations, warm$nll - cold$nll, max(abs(warm$mode - cold$mode))))
baseline <- .gt_d_baseline(theta, prep)
eta <- baseline + matrix(as.numeric(W %*% cold$mode), prep$n, prep$q)
kernel <- .gt_d_response_kernel(eta, theta, prep)
t_kernel <- med(.gt_d_response_kernel(eta, theta, prep))
t_hess <- med(H <- .gt_d_sparse_hessian(kernel$curvature, W, prep$n))
sym <- Matrix::forceSymmetric(H)
t_chol <- med(fac_raw <- Matrix::Cholesky(sym, perm = TRUE, LDL = FALSE, super = FALSE))
t_upd <- med(Matrix::update(fac_raw, sym))
t_counts <- med({ Matrix::nnzero(methods::as(fac_raw, "CsparseMatrix")); Matrix::nnzero(H); Matrix::nnzero(Matrix::tril(Matrix::forceSymmetric(H))) })
fac <- .gt_d_sparse_factor(H)
gradient <- as.numeric(Matrix::crossprod(W, kernel$gradient)) + cold$mode
t_solve <- med(.gt_d_sparse_solve(fac, gradient))
t_line <- med({ ne <- baseline + matrix(as.numeric(W %*% (cold$mode - gradient)), prep$n, prep$q); .gt_d_response_kernel(ne, theta, prep) })
cat(sprintf("fill: H nnz %d, factor nnz %d (%.1fx the triangle)\n", fac$hessian_entries, fac$factor_entries, fac$factor_entries / fac$hessian_triangle_entries))
cat(sprintf("step components (s): kernel %.4f | assembly %.4f | Cholesky fresh %.4f | Cholesky update() %.4f | nnzero counts %.4f | solve %.4f | line-search trial %.4f\n",
            t_kernel, t_hess, t_chol, t_upd, t_counts, t_solve, t_line))
# ---- fixed-pattern assembly prototype (q = 1, diagonal curvature) -------------
stopifnot(prep$q == 1L)
k <- length(groups); n <- prep$n
cols <- lapply(seq_len(k), function(s) ctx$offsets[[s]] + groups[[s]]$index)
Lv <- vapply(factors, function(L) L[1, 1], numeric(1))
pairs <- which(upper.tri(matrix(0, k, k), diag = TRUE), arr.ind = TRUE)  # s <= t
t_pre <- system.time({
  keys <- unlist(lapply(seq_len(nrow(pairs)), function(p) { s <- pairs[p, 1]; t <- pairs[p, 2]
    r <- pmin(cols[[s]], cols[[t]]); cc <- pmax(cols[[s]], cols[[t]]); (cc - 1) * d + r }))
  ukeys <- sort(unique(keys)); pos <- match(keys, ukeys)
  skeleton <- Matrix::sparseMatrix(i = (ukeys - 1) %% d + 1, j = (ukeys - 1) %/% d + 1, x = 0, dims = c(d, d), symmetric = TRUE)
  diag_slots <- which(((ukeys - 1) %% d + 1) == ((ukeys - 1) %/% d + 1))
  stopifnot(length(skeleton@x) == length(ukeys))
})[["elapsed"]]
assemble_fixed <- function(curv_diag) {
  values <- as.vector(outer(pmax(0, curv_diag), Lv[pairs[, 1]] * Lv[pairs[, 2]]))
  x <- as.numeric(rowsum(values, pos, reorder = TRUE)); x[diag_slots] <- x[diag_slots] + 1
  Hn <- skeleton; Hn@x <- x; Hn
}
t_fixed <- med(Hn <- assemble_fixed(kernel$curvature[[1]]$diagonal))
gap <- max(abs(as.matrix(Hn) - as.matrix(H))) / max(abs(as.matrix(H)))
t_chol_n <- med(Matrix::Cholesky(Hn, perm = TRUE, LDL = FALSE, super = FALSE))
cat(sprintf("fixed-pattern assembly: precompute %.3f s once; per evaluation %.4f s vs current %.4f s (%.1fx); max relative entry gap %.1e; Cholesky on it %.4f s; contributions %d -> stored %d\n",
            t_pre, t_fixed, t_hess, t_hess / t_fixed, gap, t_chol_n, length(keys), length(ukeys)))
