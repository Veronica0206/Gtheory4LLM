# Run from the project directory with Rscript tests/test_discrete_equivalence_measure.R.
#
# Contract test for the equivalence measurement layer.
#
# It checks that the layer measures what PROTOCOL.md names, computed the way
# cases.R freezes it, and that it judges nothing. Every fixture here is disjoint
# from the fifteen scored cases and the six calibration cases: measuring either
# set is a later, separately reviewed step, and a test that did so would execute
# calibration or qualification under the name of a unit test.
#
# Each property is asserted in a form that fails if the property is broken, not
# merely one that passes when it holds.
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode",
            "discrete_sparse", "discrete_sparse_mode", "discrete"))
  source(file.path("R", paste0(f, ".R")))
MEASURE <- file.path(STUDY, "equivalence-measure.R")
source(MEASURE)

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
eps <- .Machine$double.eps

# Disjoint from every frozen geometry, scored or calibration.
TEST_GEOMETRY <- list(objects = 7L, raters = 3L, reps = 2L)
frozen <- c(lapply(EQ_GEOMETRY, unlist), lapply(EQ_CALIBRATION_GEOMETRY, unlist))
expect(!any(vapply(frozen, function(g) identical(unname(g), unname(unlist(TEST_GEOMETRY))),
                   logical(1))),
       "the test geometry is not any scored or calibration geometry")
test_row <- function(family, link, structure, covariance)
  list(case = "TEST", family = family, link = link, structure = structure,
       covariance = covariance, geometry = "t_small")

# --- The layer measures and does not judge -----------------------------------
# Checked on the code's symbols rather than its text, so a comment that names a
# forbidden thing does not trip it and code that uses one cannot hide it.
code <- parse(MEASURE, keep.source = FALSE)
expect(all(vapply(code, function(e) is.call(e) && identical(e[[1L]], as.name("<-")),
                  logical(1))),
       "sourcing the layer only defines objects; it executes no case")
symbols <- unique(unlist(lapply(code, all.names)))
for (forbidden in c("read.csv", "write.csv", "file.exists", "readLines", "EQ_CORE",
                    "EQ_CALIBRATION", "EQ_NEGATIVE", "EQ_TRANSFORM", "EQ_REFERENCE"))
  expect(!forbidden %in% symbols,
         paste0("the layer does not use ", forbidden, ": it reads no tolerance, ",
                "writes no record and iterates over no frozen case set"))
expect(!file.exists(file.path(STUDY, "tolerances.csv")) &&
         !file.exists(file.path(STUDY, EQ_RUNNER_IMPLEMENTATION)),
       "adding the measurement layer does not unblock the launcher")
expect(all(c("solve_right_hand_sides", "witness_system", "conditional_objective",
             "log_determinant", "design_identity") %in% names(EQ_MEASUREMENT_CHOICES)),
       "every operand choice the frozen protocol left open is named for review")

# --- Construction is the frozen construction ----------------------------------
binary <- test_row("binary", "logit", "crossed2", "diagonal")
map <- eq_case_map(binary, TEST_GEOMETRY)
expect(identical(map, .eq_parameter_map(binary, TEST_GEOMETRY)),
       "the case map is .eq_parameter_map(), not a second construction")
points <- eq_case_points(map)
expect(identical(points, .eq_fixed_points(map$start, map$lower, map$upper,
                                          map$zero_coordinates)),
       "the stage 3 points are .eq_fixed_points(), not chosen here")
expect(identical(names(points), EQ_FIXED_POINT_LABELS), "all three frozen points are used")

# --- Stage 2: prepared-design identity ------------------------------------------
design <- eq_measure_design(map, points$start)
expect(identical(unname(design$random_dimension), rep(design$production_random_dimension, 2L)),
       "both backends build the production random dimension, sum(levels) * q")
expect(identical(design$design_max_abs_difference, 0),
       "the dense and sparse random designs agree entry for entry")

# --- Stage 3 at the common latent point -----------------------------------------
parameters <- points$displaced_positive
factors <- .eq_factors(map, parameters)
dense_W <- .gt_d_dense_backend(map$groups, factors, map$prep$n, map$prep$q)$W
baseline <- as.numeric(.gt_d_baseline(parameters, map$prep))
for (backend in EQ_BACKENDS) {
  common <- eq_measure_common_latent(map, parameters, backend)
  expect(isTRUE(common$valid), paste(backend, "evaluates at the common latent point"))
  expect(all(common$latent_point == EQ_STAGE3_LATENT_POINT) && all(common$latent_point == 0),
         paste(backend, "is evaluated at the frozen latent point zero"))
  # At u = 0 the predictor is the baseline exactly. Evaluating at a backend's
  # own conditional mode instead would move it by W u and fail here.
  expect(identical(common$predictor, baseline),
         paste(backend, "reports the predictor at u = 0, not at its own mode"))
  kernel <- .gt_d_response_kernel(matrix(baseline, map$prep$n, map$prep$q), parameters, map$prep)
  expect(identical(common$conditional_objective, kernel$nll),
         paste(backend, "reports the response negative log likelihood as the conditional objective"))
  expect(max(abs(common$mode_score - as.numeric(crossprod(dense_W, kernel$gradient)))) <=
           64 * eps * max(1, abs(common$mode_score)),
         paste(backend, "reports the mode score W'g + u at u = 0"))
  # Independent of both assembly routines: I + W' diag(c) W written out.
  independent <- diag(ncol(dense_W)) +
    crossprod(dense_W, dense_W * pmax(0, kernel$curvature[[1L]]$diagonal))
  expect(max(abs(common$hessian - independent)) <= 64 * eps * max(abs(independent)),
         paste(backend, "reports the conditional Hessian I + W'CW"))
}

# --- Solved quantities -------------------------------------------------------------
solved <- lapply(setNames(EQ_BACKENDS, EQ_BACKENDS),
                 function(b) eq_measure_solved(map, parameters, b))
for (backend in EQ_BACKENDS) {
  s <- solved[[backend]]
  expect(isTRUE(s$valid), paste(backend, "solves the conditional mode"))
  # The full log determinant, not half of it. Half would leave every mode and
  # Hessian entry in agreement and put the Laplace identity off by logdet / 4.
  expect(abs(s$laplace_identity_residual) <= 64 * eps * max(1, abs(s$marginal_negative_log_likelihood)),
         paste(backend, "reports a log determinant that satisfies the Laplace identity"))
  expect(abs(s$log_determinant) > 1e-6,
         paste(backend, "fixture has a log determinant large enough for halving to be visible"))
  expect(s$witnesses$log_determinant_witness <= s$witnesses$bound,
         paste(backend, "reports the full log determinant of the final-mode Hessian"))
  expect(identical(s$random_dimension, design$production_random_dimension),
         paste(backend, "reports the production random dimension"))
}

# --- Stage 1 witnesses --------------------------------------------------------------
final_H <- function(backend) {
  s <- solved[[backend]]
  W <- .eq_design_for(backend, map, .eq_factors(map, parameters))$W
  k <- .gt_d_response_kernel(.gt_d_baseline(parameters, map$prep) +
                               matrix(as.numeric(W %*% s$conditional_mode), map$prep$n, map$prep$q),
                             parameters, map$prep)
  .eq_hessian(backend, k$curvature, W, map$prep$n)
}
for (backend in EQ_BACKENDS) {
  w <- solved[[backend]]$witnesses
  expect(identical(w$bound, EQ_VALIDITY_BOUND(w$random_dimension)),
         paste(backend, "witnesses carry the frozen #34 bound"))
  for (name in c("solve_backward_error", "factor_reconstruction", "log_determinant_witness"))
    expect(is.finite(w[[name]]) && w[[name]] <= w$bound,
           paste(backend, name, "is within the frozen bound on a healthy fixture"))
  expect(isTRUE(w$finite_mode) && isTRUE(w$finite_objective),
         paste(backend, "reports finite mode and objective"))
}

# The backward error is taken on the frozen #34 probes, through the backend's own
# factor. Recomputed by hand here; a witness built on the gradient instead would
# not match.
H <- as.matrix(final_H("sparse"))
factor <- .eq_factorize("sparse", final_H("sparse"))
by_hand <- max(vapply(.gt_d_solve_probes(nrow(H)),
                      function(b) .gt_d_backward_error(H, b, factor$solve(b)), numeric(1)))
expect(identical(solved$sparse$witnesses$solve_backward_error, by_hand),
       "the backward-error witness is evaluated on the frozen probes")
# And it detects a solve that does not solve its system.
wrong <- factor
wrong$solve <- function(b) factor$solve(b) * (1 + 1e-6)
corrupted <- eq_validity_witnesses("sparse", final_H("sparse"),
                                   solved$sparse$conditional_mode,
                                   solved$sparse$marginal_negative_log_likelihood, wrong)
expect(corrupted$solve_backward_error > 1e3 * corrupted$bound,
       "a solve that misses its system by one part in a million breaks the witness")
unavailable <- eq_validity_witnesses("dense", H, solved$dense$conditional_mode,
                                     solved$dense$marginal_negative_log_likelihood, NULL)
expect(!unavailable$factor_available &&
         all(is.infinite(c(unavailable$solve_backward_error, unavailable$factor_reconstruction,
                           unavailable$log_determinant_witness))),
       "a missing factor reports infinite witnesses, never a fabricated pass")

# The sparse reconstruction is permutation-aware, and this fixture proves it
# matters: the permutation is not the identity, and the unpermuted product
# really does miss H.
parts <- Matrix::expand2(.gt_d_sparse_factor(final_H("sparse"))$factor, LDL = FALSE)
expect(!identical(as.integer(parts$P1@perm), seq_len(nrow(H))),
       "the fixture's CHOLMOD permutation is not the identity")
unpermuted <- max(abs(as.matrix(parts$L %*% Matrix::t(parts$L)) - H)) / max(abs(H))
expect(unpermuted > solved$sparse$witnesses$bound,
       "an unpermuted L L' comparison would fail on this fixture")
expect(solved$sparse$witnesses$factor_reconstruction <= solved$sparse$witnesses$bound,
       "the permutation-aware reconstruction satisfies the bound")

# --- Differences go through the frozen ruler -------------------------------------
common <- lapply(setNames(EQ_BACKENDS, EQ_BACKENDS),
                 function(b) eq_measure_common_latent(map, parameters, b))
differences <- eq_stage3_differences(common$dense, common$sparse, solved$dense, solved$sparse)
expect(identical(names(differences), c(EQ_STAGE3_AT_COMMON_LATENT, EQ_STAGE3_SOLVED)),
       "every stage 3 quantity is measured")
for (q in EQ_STAGE3_AT_COMMON_LATENT)
  expect(identical(differences[[q]], .eq_difference(common$dense[[q]], common$sparse[[q]], q)),
         paste(q, "is measured with the frozen .eq_difference()"))
for (q in EQ_STAGE3_SOLVED)
  expect(identical(differences[[q]], .eq_difference(solved$dense[[q]], solved$sparse[[q]], q)),
         paste(q, "is measured with the frozen .eq_difference()"))
expect(identical(differences,
                 eq_stage3_differences(common$sparse, common$dense, solved$sparse, solved$dense)),
       "exchanging the backends leaves every difference unchanged (rule R2)")
missing <- eq_stage3_differences(list(valid = FALSE), common$sparse, solved$dense, solved$sparse)
expect(all(is.infinite(missing[EQ_STAGE3_AT_COMMON_LATENT])),
       "a quantity one backend could not produce is Inf, not skipped")

# --- Refusals are not converted into measurements ----------------------------------
categorical <- eq_case_map(test_row("categorical", "softmax", "crossed2", "diagonal"),
                           TEST_GEOMETRY)
start <- eq_case_points(categorical)$start
refused <- function(expr) tryCatch({ force(expr); FALSE }, error = function(e) TRUE)
expect(refused(eq_measure_common_latent(categorical, start, "sparse")),
       "sparse categorical curvature is refused, not measured")
expect(refused(eq_measure_solved(categorical, start, "sparse")),
       "a sparse categorical solve is refused, not measured")
expect(isTRUE(eq_measure_common_latent(categorical, start, "dense")$valid),
       "the dense backend still measures the categorical case")

truncated <- map
truncated$control$inner_maxit <- 1L
truncated$control$inner_tol <- 1e-14
for (backend in EQ_BACKENDS) {
  t <- eq_measure_solved(truncated, parameters, backend)
  expect(isFALSE(t$valid), paste(backend, "reports a truncated solve as invalid"))
  expect(is.null(t$conditional_mode) && is.null(t$witnesses) && is.null(t$log_determinant),
         paste(backend, "fabricates no solved quantity or witness for an invalid solve"))
  expect(is.null(t$inner_iterations),
         paste(backend, "does not report an invalid solve as one that ended at its budget"))
}
expect(refused(eq_measure_solved(map, parameters, "cholmod")), "an unknown backend is refused")

cat("PASS: the equivalence measurement layer measures the frozen quantities and judges nothing.\n")
