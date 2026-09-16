# Frozen case manifest for the dense/sparse equivalence qualification.
#
# NO RANDOM NUMBER GENERATION. Every panel is constructed arithmetically.
# rnorm() after a fixed seed is not bit-reproducible across architectures, so a
# seeded fixture is a different matrix on arm64 than on x86_64, and a
# qualification whose inputs differ by platform cannot separate an
# implementation difference from a fixture difference. set.seed, rnorm, rbinom
# and rlogis are banned here and the ban is asserted by the study's test.
#
# This file defines WHICH cases exist. It scores nothing and runs no backend.

# ---- deterministic panel builders --------------------------------------------

# Every panel carries the full set of structural columns, so any design in the
# manifest can be applied to any panel without the builder needing to know which
# one was selected. occasion and site are derived arithmetically from the row's
# own coordinates: site is a parent of rater, so rater levels are nested inside
# it rather than crossed with it.
# A fixture with no between-object variation sits at the zero-variance boundary
# and establishes nothing, while still looking like a valid panel. Asserted at
# construction so the failure is loud here rather than subtle downstream.
.eq_nondegenerate <- function(d, outcome) {
  value <- d[[outcome]]
  numeric_value <- if (is.factor(value)) as.integer(value) else value
  per_object <- tapply(numeric_value, d$item, mean)
  if (length(unique(round(per_object, 12))) < 2L)
    stop("Degenerate fixture: every object has the same mean of '", outcome,
         "'; the panel carries no between-object variation.", call. = FALSE)
  d
}

.eq_structure <- function(d, local_raters = 2L, occasions = 4L) {
  d$occasion <- 1L + ((d$rep + d$rater) %% occasions)
  # Parent-scoped nesting needs child labels that are LOCAL to the parent and
  # reused across parents. Deriving the parent as a one-to-one function of a
  # globally unique child (site = f(rater), injectively) makes the tuple
  # (site, rater) partition identical to rater alone, so the design never
  # exercises the failure mode parent scoping exists to distinguish.
  #
  # Here nested_rater is a small local label that repeats in every site, so
  # nested_rater alone is strictly coarser than (site, nested_rater): dropping
  # the parent genuinely merges distinct raters. The study's test asserts that.
  d$site <- 1L + ((d$rater - 1L) %/% local_raters)
  d$nested_rater <- 1L + ((d$rater - 1L) %% local_raters)
  d
}

# Varying per-object success counts, avoiding 0 and k (perfect separation) so
# every object carries real within-object variation.
.eq_binary_panel <- function(objects, raters, reps, spread = 5L) {
  d <- expand.grid(item = seq_len(objects), rater = seq_len(raters), rep = seq_len(reps))
  d <- d[order(d$item, d$rater, d$rep), ]
  per <- raters * reps
  # The object index advances by one, which is coprime to any modulus, so the
  # counts cycle through every residue. Multiplying the index by `spread`
  # instead would silently collapse whenever gcd(spread, per - 1) > 1 -- with
  # per = 6 and spread = 5 every object receives the identical count and the
  # panel has no between-object variation at all, which fits at the
  # zero-variance boundary and qualifies nothing.
  ones <- 1L + ((seq_len(objects) + spread) %% (per - 1L))
  d$y <- as.integer(ave(seq_len(nrow(d)), d$item, FUN = seq_along) <= ones[d$item])
  rownames(d) <- NULL
  .eq_nondegenerate(.eq_structure(d), "y")
}

# Ordered categories assigned by a deterministic rotation. `tail_mass = TRUE`
# concentrates the extreme categories to a small share, which is the regime
# where cumulative-link tail behaviour is most easily got wrong.
.eq_ordinal_panel <- function(objects, raters, reps, levels, tail_mass = FALSE) {
  d <- expand.grid(item = seq_len(objects), rater = seq_len(raters), rep = seq_len(reps))
  d <- d[order(d$item, d$rater, d$rep), ]
  # Composition, not phase -- for the same reason as the categorical builder.
  # A modular pattern that traverses a full cycle inside each object gives every
  # object identical category COUNTS whatever the phase, so the per-object means
  # coincide and the panel is degenerate while still looking healthy in an
  # overall category table. The earlier form here did exactly that: the row
  # offset and the object coefficient combined to a multiple of the modulus
  # ((i-1)*9 + 3i = 12i - 9, and 12i is 0 mod 12), so the object term vanished
  # and every object received three of each category.
  k <- length(levels)
  within <- ave(seq_len(nrow(d)), d$item, FUN = seq_along)
  per <- raters * reps
  index <- if (tail_mass) {
    # Extreme categories genuinely rare, at most one row each per object, while
    # the per-object composition still varies.
    #
    # With only three levels those two goals are in direct conflict: the mean is
    # (2*per - low + high)/per, so it depends solely on (high - low), and making
    # the means differ forces the extremes to be common. Tail mass is therefore
    # specified with five levels (see .eq_ordinal_levels), which lets the three
    # interior categories carry the varying composition while categories 1 and k
    # stay rare.
    low <- seq_len(objects) %% 2L
    high <- (seq_len(objects) + 1L) %% 2L
    head_run <- 1L + ((seq_len(objects) + 2L) %% 3L)
    low_for <- low[d$item]
    high_for <- high[d$item]
    head_for <- head_run[d$item]
    interior <- within - low_for
    ifelse(within <= low_for, 1L,
           ifelse(within > per - high_for, k,
                  ifelse(interior <= head_for, 2L,
                         3L + ((interior - head_for - 1L) %% max(1L, k - 3L)))))
  } else {
    head_run <- 1L + ((seq_len(objects) + 1L) %% max(2L, per - k + 1L))
    head_for <- head_run[d$item]
    ifelse(within <= head_for, 1L,
           2L + ((within - head_for - 1L) %% max(1L, k - 1L)))
  }
  index <- pmin(pmax(index, 1L), k)
  d$y <- factor(levels[index], levels = levels)
  rownames(d) <- NULL
  .eq_nondegenerate(.eq_structure(d), "y")
}

.eq_categorical_panel <- function(objects, raters, reps, levels) {
  d <- expand.grid(item = seq_len(objects), rater = seq_len(raters), rep = seq_len(reps))
  d <- d[order(d$item, d$rater, d$rep), ]
  # Composition, not phase.
  #
  # Any modular pattern that traverses a full cycle within each object gives
  # every object the SAME category counts, however the phase is shifted, so the
  # per-object means coincide and the panel is degenerate. Two separate
  # attempts here failed that way: indexing mod k directly, and then a coprime
  # intermediate modulus, where the object term vanished because the row offset
  # per object combined with the coefficient to a multiple of the modulus
  # ((i-1)*9 + 5i = 14i - 9, and 14i is 0 mod 7).
  #
  # The fix is to vary the COUNTS rather than the order: object i gives its
  # first `head[i]` rows to the first category and cycles the remainder through
  # the others. head[i] advances with the object index, which is coprime to any
  # modulus, so the counts genuinely differ between objects.
  k <- length(levels)
  within <- ave(seq_len(nrow(d)), d$item, FUN = seq_along)
  per <- raters * reps
  head_run <- 1L + ((seq_len(objects) + 2L) %% max(2L, per - k + 1L))
  head_for_row <- head_run[d$item]
  index <- ifelse(within <= head_for_row, 1L,
                  2L + ((within - head_for_row - 1L) %% max(1L, k - 1L)))
  index <- pmin(pmax(index, 1L), k)
  d$y <- factor(levels[index], levels = levels)
  rownames(d) <- NULL
  .eq_nondegenerate(.eq_structure(d), "y")
}

# Two correlated binary outcomes sharing an object-level pattern.
.eq_joint_panel <- function(objects, raters, reps) {
  d <- .eq_binary_panel(objects, raters, reps, spread = 5L)
  names(d)[names(d) == "y"] <- "a"
  shifted <- .eq_binary_panel(objects, raters, reps, spread = 7L)
  d$b <- shifted$y
  .eq_nondegenerate(.eq_nondegenerate(d, "a"), "b")
}

# Ordinal category count by geometry. Tail mass needs five levels so the
# interior can carry between-object variation while the extremes stay rare;
# three levels cannot do both at once.
.eq_ordinal_levels <- function(geometry) {
  if (identical(geometry, "tail_mass"))
    c("lowest", "low", "mid", "high", "highest")
  else
    c("low", "mid", "high")
}

# ---- structures ---------------------------------------------------------------
.eq_design_single <- list(object = "item", facets = character(0),
                          term_members = list(item = "item"))
.eq_design_crossed2 <- list(object = "item", facets = "rater",
                            term_members = list(item = "item", rater = "rater"))
.eq_design_crossed3 <- list(object = "item", facets = c("rater", "occasion"),
                            term_members = list(item = "item", rater = "rater",
                                                occasion = "occasion"))
.eq_design_nested <- list(object = "item", facets = c("nested_rater", "site"),
                          term_members = list(item = "item", site = "site",
                                              rater = c("site", "nested_rater")))

# ---- the frozen core matrix ----------------------------------------------------
#
# Fifteen cases, chosen for coverage rather than as a Cartesian product. Both
# binary links and both ordinal links; single, crossed and parent-scoped
# structures; diagonal, unstructured, fixed, exact-zero-capable and
# log-Cholesky covariance coordinates; small, medium and near-dense-limit
# geometries; and ordinal tail mass.
#
# `sparse_supported` is a STATEMENT OF THE SUPPORT ENVELOPE, frozen here so it
# is not rediscovered during execution. .gt_d_sparse_hessian() refuses
# categorical curvature explicitly, and sparse joint outcomes are outside the
# 0.2 envelope. Those rows are scored `unsupported`, which is neither a pass
# nor a failure (PROTOCOL.md, rule R3).
EQ_CORE <- data.frame(stringsAsFactors = FALSE, rbind(
  c("C01", "binary",      "logit",   "single",   "diagonal",     "small",   "yes"),
  c("C02", "binary",      "probit",  "single",   "diagonal",     "small",   "yes"),
  c("C03", "binary",      "logit",   "crossed2", "diagonal",     "medium",  "yes"),
  c("C04", "binary",      "probit",  "crossed2", "unstructured", "medium",  "yes"),
  c("C05", "binary",      "probit",  "crossed2", "fixed",        "medium",  "yes"),
  c("C06", "binary",      "probit",  "crossed2", "zero_capable", "small",   "yes"),
  c("C07", "binary",      "logit",   "nested",   "diagonal",     "medium",  "yes"),
  c("C08", "binary",      "probit",  "crossed3", "log_cholesky", "near_limit", "yes"),
  c("C09", "ordinal",     "logit",   "single",   "diagonal",     "small",   "yes"),
  c("C10", "ordinal",     "probit",  "single",   "diagonal",     "small",   "yes"),
  c("C11", "ordinal",     "probit",  "crossed2", "diagonal",     "medium",  "yes"),
  c("C12", "ordinal",     "logit",   "crossed2", "diagonal",     "tail_mass", "yes"),
  c("C13", "ordinal",     "probit",  "nested",   "log_cholesky", "near_limit", "yes"),
  c("C14", "categorical", "softmax", "crossed2", "diagonal",     "small",   "no_categorical"),
  c("C15", "joint_binary","probit",  "crossed2", "unstructured", "medium",  "no_joint")))
names(EQ_CORE) <- c("case", "family", "link", "structure", "covariance",
                    "geometry", "sparse_supported")

# ---- negative overlays ---------------------------------------------------------
#
# Applied to named bases rather than multiplied across every model. The point
# is that a sparse path must not convert any of these into an accepted fit, and
# that is established by a handful of decisive conditions, not by a product.
EQ_NEGATIVE <- data.frame(stringsAsFactors = FALSE, rbind(
  c("N1", "C02", "failed_mode_solve",        "saturating intercept with a large factor"),
  c("N2", "C04", "nonfinite_probe",          "parameter probe driven to a nonfinite predictor"),
  c("N3", "C03", "zero_restart_budget",      "alternative_starts set to zero"),
  c("N4", "C11", "truncated_optimizer",      "outer maxit forced below completion"),
  c("N5", "C01", "malformed_factor_refusal", "solve-validity invariant violated by injection"),
  c("N6", "C06", "artificial_bound_contact", "variance coordinate driven onto its bound")))
names(EQ_NEGATIVE) <- c("overlay", "base_case", "condition", "description")

# ---- equivariance and repeatability transforms ---------------------------------
EQ_TRANSFORM <- data.frame(stringsAsFactors = FALSE, rbind(
  c("T1", "C04", "row_permutation",          "observation order reversed"),
  c("T2", "C04", "covariance_reordering",    "named source order reversed"),
  c("T3", "C14", "reference_transformation", "categorical reference level changed"),
  c("T4", "C08", "repeated_evaluation",      "identical inputs evaluated twice"),
  c("T5", "C13", "group_relabelling",        "group labels permuted, structure preserved")))
names(EQ_TRANSFORM) <- c("transform", "base_case", "kind", "description")

# ---- geometry table ------------------------------------------------------------
# near_limit stays inside max_random_dimension (200) and max_observations (1200);
# it exercises the top of the supported envelope, it does not probe the guard.
EQ_GEOMETRY <- list(
  small      = list(objects = 10L, raters = 3L, reps = 3L),
  medium     = list(objects = 24L, raters = 4L, reps = 3L),
  tail_mass  = list(objects = 24L, raters = 4L, reps = 3L),
  near_limit = list(objects = 180L, raters = 3L, reps = 2L))

# ---- frozen numerical choices ---------------------------------------------------
#
# Everything a runner would otherwise have to invent AFTER results become
# possible. A protocol that fixes the model shape but leaves the parameter
# points, the negative magnitudes, the fixed matrices and the reference
# assignments open is not frozen: those choices move the numbers, and choosing
# them once results exist is choosing them with the answer in view.

# Controls for every fitted case, unless a negative overlay replaces a named
# field. Frozen here rather than defaulted, so a later change to package
# defaults is visible as a qualification change instead of silently rescoring.
# Frozen as the CURRENT PRODUCTION NUMERICAL POLICY, field for field, not as a
# more generous budget. A larger inner budget, a larger outer budget or an extra
# restart can turn a default rejection into an accepted result, which is exactly
# the disposition change #4 exists to detect rather than to engineer away. Every
# numerically relevant control is listed, so a later change to package defaults
# shows up as a qualification change instead of silently rescoring the study.
EQ_CONTROL <- list(
  maxit = 150L, inner_maxit = 60L, alternative_starts = 1L,
  inner_tol = 1e-7, reltol = 1e-7, start_sd = 0.4,
  stationarity_tol = 1e-3, validation_reltol = 1e-10, validation_inner_tol = 1e-9,
  stability_objective_tol = 1e-6, stability_parameter_tol = 0.02,
  bound_tol = 1e-4, optimizer = "L-BFGS-B")

# A high-budget variant exists only for separately recorded characterization
# evidence. It is NEVER used for a qualification verdict.
EQ_CHARACTERIZATION_CONTROL <- list(maxit = 200L, inner_maxit = 100L,
                                    alternative_starts = 2L)

# Stage 3 evaluates at three frozen points per case: the prepared automatic
# start and two deterministic displacements of it. The displacement is a fixed
# function of coordinate index, so it is identical on every platform and needs
# no stored vector whose length would depend on the case.
EQ_FIXED_POINT_LABELS <- c("start", "displaced_positive", "displaced_negative")

# The displacement must respect the parameterization's declared bounds.
# Variance coordinates have a lower bound of exactly zero and start at
# start_sd^2 = 0.16, so an unclamped displacement of -0.40 * 0.5 = -0.20 lands
# at -0.04, outside the bound, for EVERY variance coordinate rather than only
# for a declared zero. The points are therefore clamped strictly inside the
# bounds: sitting exactly on a bound is artificial-bound contact, which is what
# overlay N6 exists to test, not what the ordinary stage 3 points should probe.
#
# A coordinate declared exactly zero stays exactly zero at all three points.
# Zero is the lower bound of the variance parameterization and is admissible
# there; displacing it would destroy the exact-zero property the case exists to
# exercise.
.eq_fixed_points <- function(start, lower, upper, zero_coordinates = integer(0)) {
  shape <- ((seq_along(start) %% 5L) - 2L) / 4L
  margin <- 1e-6 * pmax(1, abs(upper - lower))
  inside <- function(x) pmin(pmax(x, lower + margin), upper - margin)
  at_zero <- function(x) { if (length(zero_coordinates)) x[zero_coordinates] <- 0; x }
  list(start = at_zero(start),
       displaced_positive = at_zero(inside(start + 0.25 * shape)),
       displaced_negative = at_zero(inside(start - 0.40 * shape)))
}

# The manifest's covariance column names a PROFILE, not the production argument.
# `covariance=` accepts only "diagonal" or "unstructured"; the parameterization
# is a separate control, and "auto" resolves a q = 1 model to "variance", so
# C08 and C13 would never exercise log-Cholesky coordinates unless the runner
# were left to decide that. Frozen here instead.
EQ_COVARIANCE_PROFILE <- list(
  diagonal     = list(covariance = "diagonal",     parameterization = "auto"),
  unstructured = list(covariance = "unstructured", parameterization = "auto"),
  zero_capable = list(covariance = "diagonal",     parameterization = "variance"),
  log_cholesky = list(covariance = "diagonal",     parameterization = "log_cholesky"),
  fixed        = list(covariance = "diagonal",     parameterization = "fixed"))

# Cases that place a named source at an exact zero variance. Frozen by source
# name rather than coordinate index, because the index depends on how many
# fixed-effect coordinates precede it.
EQ_ZERO_SOURCES <- c(C06 = "rater", K06 = "rater")

# C05 supplies fixed source matrices rather than estimating them. q = 1 for this
# case, so each is one by one.
EQ_C05_FIXED_COVARIANCE <- list(item = matrix(0.64, 1L, 1L),
                                rater = matrix(0.25, 1L, 1L))

# C06 places one source at an exact zero variance, which is the coordinate the
# zero-capable parameterization exists to represent exactly.
EQ_C06_ZERO <- list(source = "rater", value = 0)

# C08 and C13 use positive-definite log-Cholesky coordinates. The joint case
# C15 estimates an unstructured 2x2 across its two outcomes.
EQ_JOINT_OUTCOMES <- c("a", "b")

# Exact injections for the negative overlays. "A saturating intercept with a
# large factor" is not a specification; -15 and 20 are.
EQ_NEGATIVE_INJECTION <- list(
  N1 = list(kind = "fixture",   intercept = -15, factor = 20),
  N2 = list(kind = "parameter", coordinate = 1L, value = 1e6),
  N3 = list(kind = "control",   field = "alternative_starts", value = 0L),
  N4 = list(kind = "control",   field = "maxit", value = 3L),
  N5 = list(kind = "injection", target = "chol_diagonal", scale = 1.09),
  N6 = list(kind = "start",     source = "rater", at = "lower_bound"))

# Stage 7 case-to-reference assignment, predeclared. An independent reference
# that is chosen after the equivalence result is known is not independent.
EQ_REFERENCE <- data.frame(stringsAsFactors = FALSE, rbind(
  c("C01", "lme4::glmer",                "binomial logit, identical model"),
  c("C02", "dense_adaptive_integration", "binary probit, small enough to integrate directly"),
  c("C09", "ordinal::clmm",              "cumulative logit, identical model"),
  c("C10", "ordinal::clmm",              "cumulative probit, identical model")))
names(EQ_REFERENCE) <- c("case", "reference", "note")

# Reference settings, frozen. glmer() and clmm() both default to nAGQ = 1, which
# IS a Laplace approximation: leaving the defaults would compare first-order
# Laplace against first-order Laplace and record it as an independent
# higher-accuracy reference, which it is not.
EQ_REFERENCE_SETTINGS <- list(
  "lme4::glmer" = list(nAGQ = 11L),
  "ordinal::clmm" = list(nAGQ = 11L),
  "dense_adaptive_integration" = list(nodes = 41L))

# T3 transforms the categorical case, which sparse does not support. Frozen
# decision: T3 is a DENSE-ONLY equivariance check. Sparse is recorded
# `unsupported` under rule R3 and contributes no equivalence result. The runner
# does not get to decide this.
EQ_TRANSFORM_SCOPE <- c(T1 = "both", T2 = "both", T3 = "dense_only",
                        T4 = "both", T5 = "both")

# The exact transformation, not a description of one. "The reference level is
# changed" does not say to which level, and "group labels are permuted" does not
# say by which permutation; both would otherwise be chosen during execution.
EQ_TRANSFORM_DETAIL <- list(
  T1 = list(rule = "reverse_observation_order"),
  T2 = list(rule = "reverse_source_order"),
  T3 = list(rule = "categorical_reference", from = "a", to = "c"),
  T4 = list(rule = "repeat_identical_evaluation", repeats = 2L),
  T5 = list(rule = "reverse_level_labels_within_each_source"))

# ---- calibration set (NON-SCORING) ----------------------------------------------
#
# Disjoint from EQ_CORE in identity AND in data. Its geometries differ, so the
# calibration panels are different matrices from the scored ones: a tolerance
# derived from the very panels it will later judge is not a tolerance, it is a
# restatement of those panels' results.
EQ_CALIBRATION_GEOMETRY <- list(
  cal_small  = list(objects = 14L, raters = 3L, reps = 3L),
  cal_medium = list(objects = 30L, raters = 4L, reps = 2L),
  # Above the largest scored random dimension, not merely large. The
  # log-determinant rule is explicitly dimension-dependent, so calibrating only
  # to 158 and then judging 187 would extrapolate the rule past the regime it
  # was measured in. 181 objects give crossed-3 dimension 188 while remaining a
  # different panel from C08's 180.
  cal_limit  = list(objects = 181L, raters = 3L, reps = 2L))

EQ_CALIBRATION <- data.frame(stringsAsFactors = FALSE, rbind(
  c("K01", "binary",  "probit", "single",   "diagonal",     "cal_small"),
  c("K02", "binary",  "logit",  "crossed2", "diagonal",     "cal_medium"),
  c("K03", "binary",  "probit", "crossed3", "log_cholesky", "cal_limit"),
  c("K04", "ordinal", "probit", "crossed2", "diagonal",     "cal_medium"),
  c("K05", "ordinal", "logit",  "crossed2", "diagonal",     "cal_tail"),
  c("K06", "binary",  "probit", "crossed2", "zero_capable", "cal_small")))
names(EQ_CALIBRATION) <- c("case", "family", "link", "structure", "covariance", "geometry")

# cal_tail reuses the cal_medium shape with the tail-mass composition, matching
# how tail_mass relates to medium in the scored set.
EQ_CALIBRATION_GEOMETRY$cal_tail <- EQ_CALIBRATION_GEOMETRY$cal_medium

# Where the inherited 1e-10 parity limit applies, and where it does not.
#
# The existing contract covers the marginal objective and the conditional
# objective at fixed parameters, which is what #3 and #30 qualified. It does NOT
# extend to every stage 3 quantity: the mode score is near zero at the mode, so
# a relative rule is undefined there, and the log determinant is a sum whose
# attainable agreement grows with dimension. Those receive calibrated
# per-quantity rules instead. Frozen here so the boundary is not redrawn during
# execution.
EQ_INHERITED_PARITY <- c("marginal_negative_log_likelihood", "conditional_objective")
EQ_CALIBRATED_QUANTITIES <- c("predictor", "mode_score", "hessian", "conditional_mode",
                              "log_determinant", "latent_g_phi", "equivariance")

# The frozen family specification per case. Needed to resolve prep$q, which the
# production engine multiplies into the random dimension, and which differs from
# one only for the categorical and joint rows.
.eq_families <- function(family, link, geometry_name) {
  switch(family,
    binary = list(list(family = "binary", link = link, levels = c("0", "1"))),
    ordinal = list(list(family = "ordinal", link = link,
                        levels = .eq_ordinal_levels(geometry_name))),
    categorical = list(list(family = "categorical", link = "softmax",
                            levels = c("a", "b", "c"), reference = "a")),
    joint_binary = rep(list(list(family = "binary", link = link,
                                 levels = c("0", "1"))), 2L),
    stop("unknown family: ", family))
}

.eq_outcomes <- function(family)
  if (identical(family, "joint_binary")) EQ_JOINT_OUTCOMES else "y"

EQ_DESIGNS <- list(single = .eq_design_single, crossed2 = .eq_design_crossed2,
                   crossed3 = .eq_design_crossed3, nested = .eq_design_nested)

.eq_panel_for <- function(family, geometry_name, geometry) {
  switch(family,
    binary = .eq_binary_panel(geometry$objects, geometry$raters, geometry$reps),
    ordinal = .eq_ordinal_panel(geometry$objects, geometry$raters, geometry$reps,
                                .eq_ordinal_levels(geometry_name),
                                tail_mass = grepl("tail", geometry_name, fixed = TRUE)),
    categorical = .eq_categorical_panel(geometry$objects, geometry$raters, geometry$reps,
                                        c("a", "b", "c")),
    joint_binary = .eq_joint_panel(geometry$objects, geometry$raters, geometry$reps),
    stop("unknown family: ", family))
}

# The production control list for a case, built from the frozen profile rather
# than assembled during execution.
.eq_control_for <- function(covariance_profile) {
  profile <- EQ_COVARIANCE_PROFILE[[covariance_profile]]
  if (is.null(profile)) stop("unknown covariance profile: ", covariance_profile)
  control <- EQ_CONTROL
  if (identical(profile$parameterization, "fixed"))
    control$fixed_covariance <- EQ_C05_FIXED_COVARIANCE
  else if (!identical(profile$parameterization, "auto"))
    control$covariance_parameterization <- profile$parameterization
  control
}

# The full prepared parameter map for a case: the start vector the engine would
# build, its bounds, and which coordinates are declared exactly zero. Used by
# the freeze test to prove the three frozen stage 3 points are admissible before
# anything is executed against them.
.eq_parameter_map <- function(row, geometry) {
  profile <- EQ_COVARIANCE_PROFILE[[row$covariance]]
  panel <- .eq_panel_for(row$family, row$geometry, geometry)
  outcomes <- .eq_outcomes(row$family)
  control <- .gt_d_control(.eq_control_for(row$covariance))
  prep <- .gt_d_prepare(panel, outcomes, .eq_families(row$family, row$link, row$geometry))
  design <- EQ_DESIGNS[[row$structure]]
  groups <- lapply(design$term_members, function(members) .gt_d_group(panel, members))
  setup <- .gt_d_covariance_setup(groups, prep$q, profile$covariance, control,
                                  prep$dimensions)
  start <- c(prep$start, setup$start)
  zero_source <- unname(EQ_ZERO_SOURCES[row$case])
  zero <- if (is.na(zero_source)) integer(0) else
    which(startsWith(names(start), paste0(zero_source, "::")))
  list(start = start, lower = c(prep$lower, setup$lower),
       upper = c(prep$upper, setup$upper), zero_coordinates = zero,
       parameterization = setup$parameterization, panel = panel,
       prep = prep, groups = groups, setup = setup, control = control)
}
