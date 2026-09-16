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
EQ_CONTROL <- list(maxit = 200L, inner_maxit = 100L, alternative_starts = 2L)

# Stage 3 evaluates at three frozen points per case: the prepared automatic
# start and two deterministic displacements of it. The displacement is a fixed
# function of coordinate index, so it is identical on every platform and needs
# no stored vector whose length would depend on the case.
EQ_FIXED_POINT_LABELS <- c("start", "displaced_positive", "displaced_negative")
.eq_fixed_points <- function(start) {
  shape <- ((seq_along(start) %% 5L) - 2L) / 4L
  list(start = start,
       displaced_positive = start + 0.25 * shape,
       displaced_negative = start - 0.40 * shape)
}

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

# T3 transforms the categorical case, which sparse does not support. Frozen
# decision: T3 is a DENSE-ONLY equivariance check. Sparse is recorded
# `unsupported` under rule R3 and contributes no equivalence result. The runner
# does not get to decide this.
EQ_TRANSFORM_SCOPE <- c(T1 = "both", T2 = "both", T3 = "dense_only",
                        T4 = "both", T5 = "both")

# ---- calibration set (NON-SCORING) ----------------------------------------------
#
# Disjoint from EQ_CORE in identity AND in data. Its geometries differ, so the
# calibration panels are different matrices from the scored ones: a tolerance
# derived from the very panels it will later judge is not a tolerance, it is a
# restatement of those panels' results.
EQ_CALIBRATION_GEOMETRY <- list(
  cal_small  = list(objects = 14L, raters = 3L, reps = 3L),
  cal_medium = list(objects = 30L, raters = 4L, reps = 2L),
  cal_limit  = list(objects = 150L, raters = 4L, reps = 2L))

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
