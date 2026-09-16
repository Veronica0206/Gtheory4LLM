# Run from the project directory with Rscript tests/test_discrete_solve_validity.R.
#
# Regression for the dense conditional-solve validity invariant.
#
# PROVENANCE. This check exists because of a real captured failure, retained as
# evidence rather than as a test input. On GitHub Actions run 35070451698, job
# 104710498377 (ubuntu-22.04 / R 4.5.0, OpenBLAS 0.3.20 / LAPACK 3.10.0, on an
# Intel(R) Xeon(R) 6973P-C), base chol() returned SUCCESSFULLY and its factor:
#
#     failed R'R = H by                 8.949e-02
#     failed to solve its own system by 3.873e-01
#     disagreed with the eigenvalues by 0.4503449   (33.743979332922 vs
#                                                    33.2936344600959)
#
# measured on the invariant below as eta = 4.82807e-02, against a worst healthy
# observation of 9.65945e-16 over 53,770 solves. The identical matrix bytes
# factor correctly on other hardware, so the matrix was not pathological.
#
# The regression below does NOT depend on ever seeing that hardware again, and
# deliberately uses no RNG: rnorm() is not bit-reproducible across
# architectures, so a fixture built from a seed would not be the same matrix on
# every platform. Every matrix here is constructed arithmetically, and the
# malformed factors are produced by deterministic corruption.
source(file.path("R", "design.R"))
source(file.path("R", "discrete_response.R"))
source(file.path("R", "discrete_dense.R"))
source(file.path("R", "discrete_mode.R"))
source(file.path("R", "discrete.R"))
source(file.path("R", "diagnostics_stages.R"))

fails <- 0L
ok <- function(condition, label) {
  if (!isTRUE(condition)) { fails <<- fails + 1L; cat("FAIL: ", label, "\n", sep = "") }
}
close <- function(a, b, tol = 1e-12) isTRUE(max(abs(a - b)) <= tol)

# A conditional Hessian of the real shape, I + W' D W with D >= 0, built with no
# RNG so every platform tests the same matrix.
build <- function(levels, replicates, curvature_scale) {
  n <- levels * replicates
  W <- matrix(0, n, levels)
  W[cbind(seq_len(n), rep(seq_len(levels), each = replicates))] <- 1
  d <- curvature_scale * (1 + (seq_len(n) %% 7) / 7)
  H <- diag(levels) + crossprod(W, W * d)
  (H + t(H)) / 2
}
H <- build(12L, 5L, 0.8)
b <- (seq_len(nrow(H)) %% 5) - 2 + 0.25
R <- chol(H)
x <- backsolve(R, forwardsolve(t(R), b))

# ---- the quantity itself -----------------------------------------------------
eta <- .gt_d_backward_error(H, b, x)
ok(eta >= 0 && eta <= 4 * .Machine$double.eps, "healthy solve is at machine precision")
ok(.gt_d_solve_valid(H, b, x), "healthy solve passes the invariant")

# Computed against an independent hand evaluation of the definition, not against
# the implementation's own arithmetic re-run.
manual <- max(abs(as.numeric(H %*% x) - b)) /
  (max(rowSums(abs(H))) * max(abs(x)) + max(abs(b)))
ok(close(eta, manual), "eta matches the definition computed independently")

# ---- the bound ---------------------------------------------------------------
ok(close(.gt_d_solve_bound(42), 32 * 42 * .Machine$double.eps),
   "bound is 32 * random_dimension * eps")
ok(.gt_d_solve_bound(200) > .gt_d_solve_bound(42), "bound scales with dimension")

# ---- degenerate arithmetic ---------------------------------------------------
zero <- matrix(0, 2, 2)
ok(close(.gt_d_backward_error(zero, c(0, 0), c(0, 0)), 0),
   "exactly zero residual on an exactly zero problem is exact, not undefined")
ok(!is.finite(.gt_d_backward_error(zero, c(0, 0), c(1, 1))) ||
     .gt_d_backward_error(zero, c(0, 0), c(1, 1)) == 0,
   "zero matrix with a non-zero step is handled without error")
ok(!.gt_d_solve_valid(H, b, rep(NaN, nrow(H))), "NaN step is refused")
ok(!.gt_d_solve_valid(H, b, rep(Inf, nrow(H))), "infinite step is refused")
ok(!.gt_d_solve_valid(H, rep(NA_real_, nrow(H)), x), "NA right-hand side is refused")

# ---- deterministic corruption of the step ------------------------------------
# The invariant must reject a step that does not solve the system, at a
# magnitude far below the captured specimen's 4.83e-02.
for (scale in c(1e-6, 1e-3, 1e-1)) {
  bad <- x
  bad[[1L]] <- bad[[1L]] + scale
  ok(!.gt_d_solve_valid(H, b, bad),
     paste0("step perturbed by ", scale, " is refused"))
}
# And must not reject a step perturbed only at the level of rounding.
tiny <- x * (1 + 4 * .Machine$double.eps)
ok(.gt_d_solve_valid(H, b, tiny), "step perturbed at rounding level is accepted")

# ---- deterministic corruption of the factor ----------------------------------
ok(.gt_d_final_factor_valid(H, R), "an honest factor passes the probe check")
for (scale in c(1.001, 1.09, 2)) {
  bad <- R
  bad[1L, 1L] <- bad[1L, 1L] * scale
  ok(!.gt_d_final_factor_valid(H, bad),
     paste0("factor with a diagonal scaled by ", scale, " is refused"))
  # The corruption really does break the factorization, so the test is not
  # merely asserting that an arbitrary edit trips an arbitrary threshold.
  ok(max(abs(crossprod(bad) - H)) / max(abs(H)) > 1e-6,
     paste0("diagonal scaled by ", scale, " genuinely breaks R'R = H"))
}
# An off-diagonal corruption too: a malformed factor need not be diagonal-only.
off <- R
off[1L, 2L] <- off[1L, 2L] + 0.05
ok(!.gt_d_final_factor_valid(H, off), "factor with a corrupted off-diagonal is refused")

# ---- the probes --------------------------------------------------------------
probes <- .gt_d_solve_probes(6L)
ok(length(probes) == 2L, "two probes")
ok(all(vapply(probes, function(p) max(abs(p)) == 1, logical(1))),
   "probes are infinity-normalized")
ok(abs(sum(probes[[1L]] * probes[[2L]])) < sqrt(sum(probes[[1L]]^2)) * sqrt(sum(probes[[2L]]^2)),
   "probes are not collinear")
ok(identical(.gt_d_solve_probes(6L), probes), "probes are deterministic")

# ---- end to end: a malformed native factor is refused, never accepted --------
# chol() is shadowed so the sourced solver resolves to this one. It corrupts the
# returned factor exactly the way the specimen's was invalid: returned without
# error, and not a factor of its input.
# Deterministic and non-degenerate: item rates must actually differ, or the fit
# sits at the zero-variance boundary and the control proves nothing. The counts
# avoid 0 and 9 so no item is perfectly separated.
d <- expand.grid(item = seq_len(10), rater = seq_len(3), rep = seq_len(3))
d <- d[order(d$item, d$rater, d$rep), ]
ones <- c(2L, 3L, 4L, 5L, 6L, 7L, 3L, 4L, 5L, 6L)
d$y <- as.integer(ave(seq_len(nrow(d)), d$item, FUN = seq_along) <= ones[d$item])
rownames(d) <- NULL
design <- list(object = "item", facets = "rater",
               term_members = list(item = "item", rater = "rater"))
family <- list(list(family = "binary", link = "probit", levels = c("0", "1")))
honest <- .gt_fit_discrete(d, "y", design, family, control = list(maxit = 60L))
ok(isTRUE(honest$numerically_accepted), "the uncorrupted control fit is accepted")
ok(!length(honest$diagnostics$acceptance_failures),
   "the uncorrupted control fit has no acceptance failures")

corrupt_after <- 0L
chol <- function(x, ...) {
  R <- base::chol(x, ...)
  corrupt_after <<- corrupt_after + 1L
  if (corrupt_after > 2L) R[1L, 1L] <- R[1L, 1L] * 1.09
  R
}
corrupted <- tryCatch(.gt_fit_discrete(d, "y", design, family, control = list(maxit = 60L)),
                      error = function(e) structure(list(error = conditionMessage(e)),
                                                    class = "refused"))
rm(chol)
# Either outcome is containment: an explicit error, or a completed call that is
# NOT numerically accepted. What must never happen is an accepted fit built on a
# factor that does not solve its own system.
accepted <- !inherits(corrupted, "refused") && isTRUE(corrupted$numerically_accepted)
ok(!accepted, "a fit built on a malformed native factor is never numerically accepted")
if (!inherits(corrupted, "refused"))
  ok(length(corrupted$diagnostics$acceptance_failures) > 0L,
     "the refusal is recorded in acceptance_failures")

# ---- the two reasons are distinguishable -------------------------------------
prep <- .gt_d_prepare(d, "y", family)
groups <- lapply(design$term_members, function(m) .gt_d_group(d, m))
control <- .gt_d_control(list(maxit = 60L))
setup <- .gt_d_covariance_setup(groups, prep$q, "diagonal", control, prep$dimensions)
start <- c(prep$start, setup$start)
factors <- .gt_d_covariance_factors(start[-seq_along(prep$start)], setup)
backend <- .gt_d_dense_backend(groups, factors, prep$n, prep$q)
ok(isTRUE(.gt_d_dense_mode(start, prep, backend, control, details = TRUE)$valid),
   "the honest dense mode solve is valid")

chol <- function(x, ...) { R <- base::chol(x, ...); R[1L, 1L] <- R[1L, 1L] * 1.09; R }
first <- .gt_d_dense_mode(start, prep, backend, control, details = TRUE)
rm(chol)
ok(identical(first$valid, FALSE), "a corrupted factor invalidates the dense mode solve")
ok(identical(first$reason, "dense_newton_solve_invalid"),
   "the Newton-step failure carries its own reason")

# The final-mode reason is exercised directly: isolating it end to end would
# require corrupting only the last factorization of one evaluation, which is a
# less honest construction than checking the function that decides it.
ok(!.gt_d_final_factor_valid(H, {bad <- R; bad[1L, 1L] <- bad[1L, 1L] * 1.09; bad}),
   "the final-factor check rejects the same corruption")

# ---- the diagnostic form carries the measurement ----------------------------
good <- .gt_d_solve_check(H, b, x)
ok(isTRUE(good$valid), "the diagnostic form agrees with the predicate on a healthy solve")
ok(identical(good$random_dimension, nrow(H)), "the diagnostic form reports the dimension")
ok(close(good$solve_validity_bound, .gt_d_solve_bound(nrow(H))),
   "the diagnostic form reports the bound it applied")
worse <- x; worse[[1L]] <- worse[[1L]] + 1e-3
bad <- .gt_d_solve_check(H, b, worse)
ok(identical(bad$valid, FALSE) && bad$solve_backward_error > bad$solve_validity_bound,
   "a refusal reports a backward error above its bound")
probe_bad <- .gt_d_final_factor_check(H, {r <- R; r[1L, 1L] <- r[1L, 1L] * 1.09; r})
ok(identical(probe_bad$valid, FALSE), "the probe check refuses a corrupted factor")
ok(identical(probe_bad$probe_index, 1L), "the probe check names which probe failed")
ok(is.na(.gt_d_final_factor_check(H, R)$probe_index),
   "a passing factor names no failing probe")

# ---- a start-value refusal is diagnosable ------------------------------------
# Injected through the private evaluator seam rather than by corrupting chol(),
# so the two cases below differ in exactly one respect: whether the detailed
# replay reproduces the failure.
message_of <- function(expr) tryCatch({ force(expr); NA_character_ },
                                      error = function(e) conditionMessage(e))
reproduces <- function(parameters, prep, groups, setup, control, details = FALSE, ...) {
  if (details) list(valid = FALSE, reason = "dense_newton_solve_invalid",
                    solve_backward_error = 4.82807e-02,
                    solve_validity_bound = 2.98e-13, random_dimension = 42L) else 1e100
}
reported <- message_of(.gt_fit_discrete(d, "y", design, family,
                                        control = list(maxit = 60L), .laplace = reproduces))
ok(grepl("did not yield a converged finite inner mode at starting values", reported, fixed = TRUE),
   "the established error prefix is preserved")
ok(grepl("reason=dense_newton_solve_invalid", reported, fixed = TRUE),
   "a start-value refusal names the invariant that failed")
ok(grepl("backward_error=", reported, fixed = TRUE) &&
     grepl("solve_validity_bound=", reported, fixed = TRUE),
   "a start-value refusal reports the measurement and the bound it was judged against")
ok(grepl("backward_error_over_bound=", reported, fixed = TRUE),
   "a start-value refusal reports how far over the bound it was")
ok(grepl("random_dimension=42", reported, fixed = TRUE),
   "a start-value refusal reports the dimension")

# ---- the diagnostic replay must never rescue ---------------------------------
# The scalar evaluation refuses and the detailed replay then succeeds, which is
# exactly what an intermittent native defect looks like. The fit must still
# refuse: a second call behaving is not evidence that the first was valid, and
# the alternative is a numerical policy of retrying until the library complies.
calls <- 0L
intermittent <- function(parameters, prep, groups, setup, control, details = FALSE, ...) {
  calls <<- calls + 1L
  if (calls == 1L)
    return(if (details) list(valid = FALSE, reason = "dense_newton_solve_invalid") else 1e100)
  .gt_d_laplace(parameters, prep, groups, setup, control, details = details, ...)
}
rescued <- message_of(.gt_fit_discrete(d, "y", design, family,
                                       control = list(maxit = 60L), .laplace = intermittent))
ok(!is.na(rescued), "an intermittent invalid start still refuses when the replay succeeds")
ok(grepl("diagnostic replay did not reproduce the invalid solve", rescued, fixed = TRUE),
   "the refusal records that the replay did not reproduce, instead of silently retrying")
ok(identical(calls, 2L), "exactly one diagnostic replay is performed, never a retry loop")

if (fails) { cat("FAILURES: ", fails, "\n", sep = ""); quit(status = 1) }
cat("Dense solve-validity checks passed: backward error, bound, degenerate arithmetic, ",
    "step and factor corruption, probe properties, end-to-end refusal, reason codes, ",
    "diagnosable start-value refusal, and no rescue from the diagnostic replay.\n", sep = "")
