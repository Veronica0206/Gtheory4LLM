# Run from the project directory with Rscript tests/test_discrete_equivalence_freeze.R.
#
# Contract test for the frozen dense/sparse equivalence study.
#
# It asserts that the study is FROZEN, not that any qualification passed: no
# qualification has been executed. What it protects is that the manifest, the
# fixtures, the numerical choices and the preconditions cannot drift between the
# freeze and the execution that scores against them.
#
# The expected digests live HERE, outside the files they govern. A pin that sits
# inside the governed set can be updated in the same edit that changes what it
# pins, which is not a pin at all.
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))
source(file.path("R", "design.R"))
source(file.path("R", "discrete_response.R"))
source(file.path("R", "discrete_dense.R"))
source(file.path("R", "discrete_mode.R"))
source(file.path("R", "discrete_sparse.R"))
source(file.path("R", "discrete.R"))

fails <- 0L
ok <- function(condition, label) {
  if (!isTRUE(condition)) { fails <<- fails + 1L; cat("FAIL: ", label, "\n", sep = "") }
}

# Git checks text files out with CRLF on Windows, so a raw byte hash would only
# reproduce on the platform that wrote it.
content_digest <- function(path) {
  normalized <- tempfile("eq-content-")
  on.exit(unlink(normalized), add = TRUE)
  connection <- file(normalized, "wb")
  tryCatch(writeBin(charToRaw(paste0(paste(readLines(path, warn = FALSE), collapse = "\n"), "\n")),
                    connection), finally = close(connection))
  unname(tools::md5sum(normalized))
}

# ---- the governed sources are pinned from outside themselves -------------------
FROZEN_SOURCES <- c(
  "PROTOCOL.md" = "c05807cfc9801a24fb003ee91e474af8",
  "CALIBRATION.md" = "2e7a53d66714dbaedd50380640ac6448",
  "README.md" = "2f73e051d4be697fa35841eba91a9f81",
  "cases.R" = "f0df69644c1c7c650465f2d865908da4",
  "freeze-fixtures.R" = "96a3ff727d433c5ff4d8c741aa0eaf85",
  "run-equivalence.R" = "7d4ac0eccc1d5d57d31b871fbb98d4a7",
  "results-schema.csv" = "387a602d1dcb6e70ad1eaa62f74cc150")
for (name in names(FROZEN_SOURCES))
  ok(identical(content_digest(file.path(STUDY, name)), unname(FROZEN_SOURCES[[name]])),
     paste0(name, " has moved since the protocol was frozen. If that is intended, the ",
            "new digest belongs in this test as a reviewed change, not as a silent edit."))

# The recorded manifest must agree with the independent recomputation above, so
# a tampered or stale source-hashes.csv is caught rather than believed.
recorded_sources <- read.csv(file.path(STUDY, "source-hashes.csv"), stringsAsFactors = FALSE)
ok(identical(sort(recorded_sources$file), sort(names(FROZEN_SOURCES))),
   "source-hashes.csv lists exactly the governed files")
for (name in names(FROZEN_SOURCES)) {
  row <- recorded_sources[recorded_sources$file == name, ]
  ok(identical(nrow(row), 1L) && identical(row$md5[[1L]], unname(FROZEN_SOURCES[[name]])),
     paste0("source-hashes.csv records the frozen digest for ", name))
}

# ---- no random number generation ------------------------------------------------
manifest <- readLines(file.path(STUDY, "cases.R"), warn = FALSE)
code <- manifest[!grepl("^\\s*#", manifest)]
for (banned in c("set.seed", "rnorm", "rbinom", "rlogis", "runif", "sample"))
  ok(!any(grepl(banned, code, fixed = TRUE)),
     paste0("the case manifest does not call ", banned))

# ---- matrix shape and coverage --------------------------------------------------
ok(identical(nrow(EQ_CORE), 15L), "fifteen core cases")
ok(identical(nrow(EQ_NEGATIVE), 6L), "six negative overlays")
ok(identical(nrow(EQ_TRANSFORM), 5L), "five equivariance transforms")
ok(identical(nrow(EQ_CALIBRATION), 6L), "six calibration cases")
ok(identical(EQ_CORE$sparse_supported[EQ_CORE$case == "C14"], "no_categorical"),
   "the categorical case is frozen as unsupported by sparse")
ok(identical(EQ_CORE$sparse_supported[EQ_CORE$case == "C15"], "no_joint"),
   "the joint case is frozen as unsupported by sparse")
ok(sum(EQ_CORE$sparse_supported == "yes") == 13L, "thirteen sparse-supported cases")
ok(all(c("logit", "probit") %in% EQ_CORE$link[EQ_CORE$family == "binary"]),
   "both binary links are covered")
ok(all(c("logit", "probit") %in% EQ_CORE$link[EQ_CORE$family == "ordinal"]),
   "both ordinal links are covered")
ok(all(c("single", "crossed2", "crossed3", "nested") %in% EQ_CORE$structure),
   "single, crossed and parent-scoped structures are covered")
ok(all(c("diagonal", "unstructured", "fixed", "zero_capable", "log_cholesky") %in%
         EQ_CORE$covariance), "every covariance coordinate is covered")
ok(all(c("small", "medium", "near_limit", "tail_mass") %in% EQ_CORE$geometry),
   "small, medium, near-limit and tail-mass geometries are covered")

# The calibration set must not reuse the scored panels. A tolerance derived from
# the panels it will later judge is a restatement of their results.
ok(!any(EQ_CALIBRATION$geometry %in% EQ_CORE$geometry),
   "calibration geometries are disjoint from the scored geometries")
ok(!any(EQ_CALIBRATION$case %in% EQ_CORE$case),
   "calibration case identifiers are disjoint from the scored cases")

# ---- parent-scoped nesting actually nests --------------------------------------
# The nested design exists to distinguish a child label reused under different
# parents from a globally unique one. If the parent were a one-to-one function
# of the child, the tuple partition would equal the child partition and the case
# would test nothing. Assert that dropping the parent genuinely merges raters.
nest_panel <- .eq_binary_panel(24L, 4L, 3L)
child_alone <- .gt_d_group(nest_panel, "nested_rater")$nlevels
with_parent <- .gt_d_group(nest_panel, c("site", "nested_rater"))$nlevels
ok(with_parent > child_alone,
   "dropping the parent changes the grouping, so parent scoping is exercised")
reuse <- table(nest_panel$site, nest_panel$nested_rater) > 0L
ok(any(colSums(reuse) > 1L),
   "at least one child label is reused under more than one parent")
ok(identical(.eq_design_nested$term_members$rater, c("site", "nested_rater")),
   "the nested design groups the child within its parent")

# ---- frozen numerical choices exist and hold -----------------------------------
ok(identical(EQ_FIXED_POINT_LABELS,
             c("start", "displaced_positive", "displaced_negative")),
   "three frozen fixed-parameter points")
probe_start <- c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6)
probe_lower <- rep(0, 6L)
probe_upper <- rep(5, 6L)
points <- .eq_fixed_points(probe_start, probe_lower, probe_upper)
ok(identical(length(points), 3L) && !identical(points$start, points$displaced_positive) &&
     !identical(points$start, points$displaced_negative),
   "the displacements are deterministic and differ from the start")
ok(identical(points, .eq_fixed_points(probe_start, probe_lower, probe_upper)),
   "the fixed-parameter points are reproducible")
# The clamp must bind: an unclamped displacement of -0.40 * 0.5 from a start of
# 0.1 would land at -0.1, below the variance lower bound of zero.
tight <- .eq_fixed_points(rep(0.1, 6L), rep(0, 6L), rep(5, 6L))
ok(all(vapply(tight, function(v) all(v >= 0), logical(1))),
   "the displacement is clamped inside a zero lower bound")
ok(identical(EQ_C05_FIXED_COVARIANCE$item, matrix(0.64, 1L, 1L)) &&
     identical(EQ_C05_FIXED_COVARIANCE$rater, matrix(0.25, 1L, 1L)),
   "C05's fixed source matrices are frozen as values")
ok(identical(EQ_C06_ZERO$source, "rater") && identical(EQ_C06_ZERO$value, 0),
   "C06's exact-zero coordinate is frozen")
ok(identical(sort(names(EQ_NEGATIVE_INJECTION)), sort(EQ_NEGATIVE$overlay)),
   "every negative overlay has a frozen injection")
ok(identical(EQ_NEGATIVE_INJECTION$N1$intercept, -15) &&
     identical(EQ_NEGATIVE_INJECTION$N1$factor, 20),
   "the saturating overlay is frozen as numbers, not as an adjective")
ok(identical(EQ_NEGATIVE_INJECTION$N4$value, 3L),
   "the truncated-optimizer overlay is frozen as an exact budget")
ok(identical(EQ_NEGATIVE_INJECTION$N5$scale, 1.09),
   "the malformed-factor overlay is frozen as an exact corruption")
ok(all(EQ_REFERENCE$case %in% EQ_CORE$case) && nrow(EQ_REFERENCE) >= 3L,
   "stage 7 references are predeclared against named cases")
ok(identical(unname(EQ_TRANSFORM_SCOPE[["T3"]]), "dense_only"),
   "T3 is frozen as a dense-only equivariance check")
ok(identical(sort(names(EQ_TRANSFORM_SCOPE)), sort(EQ_TRANSFORM$transform)),
   "every transform has a frozen scope")
ok(length(intersect(EQ_INHERITED_PARITY, EQ_CALIBRATED_QUANTITIES)) == 0L,
   "no quantity is both inherited-parity and calibrated")
ok(all(c("marginal_negative_log_likelihood", "conditional_objective") %in%
         EQ_INHERITED_PARITY),
   "the inherited 1e-10 scope is frozen to the quantities #3 and #30 qualified")

# ---- frozen fixtures ------------------------------------------------------------
FROZEN_DIGESTS <- c(
  "C01" = "ed269332df4cfec404da97c432705e50",
  "C02" = "ed269332df4cfec404da97c432705e50",
  "C03" = "6b969e5b1374aa3c441f1f7253a30000",
  "C04" = "6b969e5b1374aa3c441f1f7253a30000",
  "C05" = "6b969e5b1374aa3c441f1f7253a30000",
  "C06" = "ed269332df4cfec404da97c432705e50",
  "C07" = "6b969e5b1374aa3c441f1f7253a30000",
  "C08" = "5d11fcf6cfc19f44ff4e752b26f7d30d",
  "C09" = "8e3345bcd7c1290044f002a29cf72bc8",
  "C10" = "8e3345bcd7c1290044f002a29cf72bc8",
  "C11" = "187b115a4d3fb7d0c6775ced96b2eed1",
  "C12" = "8f5a64f79160c220f4a022e0491f9d10",
  "C13" = "fd218716d6557fabda7770ccecd8d8ec",
  "C14" = "e78b1a5578d045561e5f1e87919a7076",
  "C15" = "79f552dfab1f265fd138042db5277496",
  "K01" = "cc31a7a33aeb97d3a60c227d73a79fdd",
  "K02" = "03ef8e4d9c792e2500c75dc5751a59e3",
  "K03" = "70ed6c22fcda96a6f11ee40402f61845",
  "K04" = "e18a2d7851e77a56b6ccdb2ece153b6c",
  "K05" = "c31d3ed8439fc056344072bd88b7ad4e",
  "K06" = "cc31a7a33aeb97d3a60c227d73a79fdd")
FROZEN_OBSERVATIONS <- c(
  "C01" = 90L,
  "C02" = 90L,
  "C03" = 288L,
  "C04" = 288L,
  "C05" = 288L,
  "C06" = 90L,
  "C07" = 288L,
  "C08" = 1080L,
  "C09" = 90L,
  "C10" = 90L,
  "C11" = 288L,
  "C12" = 288L,
  "C13" = 1080L,
  "C14" = 90L,
  "C15" = 288L,
  "K01" = 126L,
  "K02" = 240L,
  "K03" = 1086L,
  "K04" = 240L,
  "K05" = 240L,
  "K06" = 126L)
FROZEN_DIMENSIONS <- c(
  "C01" = 10L,
  "C02" = 10L,
  "C03" = 28L,
  "C04" = 28L,
  "C05" = 28L,
  "C06" = 13L,
  "C07" = 30L,
  "C08" = 187L,
  "C09" = 10L,
  "C10" = 10L,
  "C11" = 28L,
  "C12" = 28L,
  "C13" = 185L,
  "C14" = 26L,
  "C15" = 56L,
  "K01" = 14L,
  "K02" = 34L,
  "K03" = 188L,
  "K04" = 34L,
  "K05" = 34L,
  "K06" = 17L)
FROZEN_SOURCE_LEVELS <- c(
  "C01" = 10L,
  "C02" = 10L,
  "C03" = 28L,
  "C04" = 28L,
  "C05" = 28L,
  "C06" = 13L,
  "C07" = 30L,
  "C08" = 187L,
  "C09" = 10L,
  "C10" = 10L,
  "C11" = 28L,
  "C12" = 28L,
  "C13" = 185L,
  "C14" = 13L,
  "C15" = 28L,
  "K01" = 14L,
  "K02" = 34L,
  "K03" = 188L,
  "K04" = 34L,
  "K05" = 34L,
  "K06" = 17L)
FROZEN_RANKS <- c(
  "C01" = 1L,
  "C02" = 1L,
  "C03" = 2L,
  "C04" = 2L,
  "C05" = 2L,
  "C06" = 2L,
  "C07" = 3L,
  "C08" = 3L,
  "C09" = 1L,
  "C10" = 1L,
  "C11" = 2L,
  "C12" = 2L,
  "C13" = 3L,
  "C14" = 2L,
  "C15" = 2L,
  "K01" = 1L,
  "K02" = 2L,
  "K03" = 3L,
  "K04" = 2L,
  "K05" = 2L,
  "K06" = 2L)
recorded <- read.csv(file.path(STUDY, "fixture-digests.csv"), stringsAsFactors = FALSE)
ok(identical(nrow(recorded), 21L), "twenty-one frozen fixture digests")
ok(identical(sort(recorded$case), sort(names(FROZEN_DIGESTS))),
   "the frozen fixture set is exactly the manifest")
for (case in names(FROZEN_DIGESTS)) {
  row <- recorded[recorded$case == case, ]
  ok(identical(nrow(row), 1L), paste0("one fixture row for ", case))
  if (nrow(row) == 1L) {
    ok(identical(row$panel_digest, unname(FROZEN_DIGESTS[[case]])),
       paste0("the frozen panel digest for ", case, " is unchanged"))
    ok(identical(as.integer(row$observations), unname(FROZEN_OBSERVATIONS[[case]])),
       paste0("the frozen observation count for ", case, " is unchanged"))
    # Pinned so a "near-limit" geometry cannot quietly shrink into a small one.
    ok(identical(as.integer(row$random_dimension), unname(FROZEN_DIMENSIONS[[case]])),
       paste0("the frozen random dimension for ", case, " is unchanged"))
    ok(identical(as.integer(row$kernel_rank), unname(FROZEN_RANKS[[case]])),
       paste0("the frozen kernel rank for ", case, " is unchanged"))
    # random_dimension is the production quantity, source levels times q. The
    # two differ exactly where q > 1, which is the categorical and joint rows.
    ok(identical(as.integer(row$source_levels), unname(FROZEN_SOURCE_LEVELS[[case]])),
       paste0("the frozen source-level count for ", case, " is unchanged"))
    ok(identical(as.integer(row$random_dimension),
                 unname(FROZEN_SOURCE_LEVELS[[case]]) * as.integer(row$latent_dimensions)),
       paste0(case, "'s random dimension is source levels times q"))
  }
}
# Calibration must reach at least the largest scored dimension: the
# log-determinant rule is dimension-dependent, so calibrating below the scored
# maximum would extrapolate it past the regime it was measured in.
ok(max(recorded$random_dimension[recorded$set == "calibration"]) >=
     max(recorded$random_dimension[recorded$set == "qualification"]),
   "the calibration set reaches at least the largest scored random dimension")

near <- recorded[recorded$geometry == "near_limit", ]
ok(nrow(near) == 2L && all(near$random_dimension >= 180L) &&
     all(near$random_dimension <= 200L),
   "the near-limit cases genuinely approach the dense random-dimension ceiling")

# ---- ordinal category composition ------------------------------------------------
# A digest pins WHICH panel a case uses; it cannot say whether that panel is the
# one the case is meant to be. K05 was pinned through the whole first freeze while
# the top category of its "rare tail" held 68.75% of observations, because the
# level selector and the panel builder recognised tail geometries by different
# rules. So the composition itself is asserted here, for every ordinal fixture,
# scored and calibration alike.
#
# "Rare" is defined without choosing a number: each extreme category is below the
# uniform share 1/k, and below every interior category.
ordinal_shares <- function(y, levels) {
  counts <- as.integer(table(factor(y, levels = levels)))
  counts / sum(counts)
}
extremes_rare <- function(y, levels) {
  share <- ordinal_shares(y, levels)
  k <- length(levels)
  extremes <- share[c(1L, k)]
  k >= 3L && all(extremes < 1 / k) && max(extremes) < min(share[-c(1L, k)])
}
ok(all(EQ_TAIL_GEOMETRIES %in% c(names(EQ_GEOMETRY), names(EQ_CALIBRATION_GEOMETRY))),
   "every declared tail geometry is a real scored or calibration geometry")
# Without this, dropping a geometry from the tail set would quietly turn its case
# into an ordinary three-level panel that every composition check below accepts.
ok(.eq_is_tail_geometry(EQ_CORE$geometry[EQ_CORE$case == "C12"]) &&
     .eq_is_tail_geometry(EQ_CALIBRATION$geometry[EQ_CALIBRATION$case == "K05"]),
   "C12 and K05, the scored and calibration tail-mass cases, are built as tail geometries")
for (set in list(list(table = EQ_CORE, geometries = EQ_GEOMETRY),
                 list(table = EQ_CALIBRATION, geometries = EQ_CALIBRATION_GEOMETRY))) {
  rows <- set$table[set$table$family == "ordinal", ]
  for (i in seq_len(nrow(rows))) {
    row <- rows[i, ]
    tail <- .eq_is_tail_geometry(row$geometry)
    levels <- .eq_ordinal_levels(row$geometry)
    panel <- .eq_panel_for("ordinal", row$geometry, set$geometries[[row$geometry]])
    ok(identical(length(levels), if (tail) 5L else 3L),
       paste0(row$case, ": a tail geometry receives five levels and any other receives three"))
    ok(identical(levels(panel$y), levels) &&
         identical(.eq_families("ordinal", row$link, row$geometry)[[1L]]$levels, levels),
       paste0(row$case, ": the panel and the family specification declare the same levels"))
    ok(all(ordinal_shares(panel$y, levels) > 0),
       paste0(row$case, ": every declared category is observed"))
    if (tail) ok(extremes_rare(panel$y, levels),
                 paste0(row$case, ": both extreme categories are rarer than uniform and than ",
                        "every interior category"))
  }
}

# The pre-correction K05, rebuilt from its original inputs: the rare-extreme
# construction given three levels. Reproducing its composition exactly, and
# showing the rarity rule rejects it, is what makes the check above
# discriminating rather than merely satisfied by the corrected fixture.
K05_BEFORE_CORRECTION_DIGEST <- "e1dddcce3be9f8a72791affcd3b449b0"
cal_tail <- EQ_CALIBRATION_GEOMETRY$cal_tail
three_levels <- c("low", "mid", "high")
k05_before <- .eq_ordinal_panel(cal_tail$objects, cal_tail$raters, cal_tail$reps,
                                three_levels, tail_mass = TRUE)
ok(identical(as.integer(table(k05_before$y)), c(15L, 60L, 165L)),
   "the pre-correction K05 composition is reproduced exactly: 15, 60 and 165 of 240")
ok(!extremes_rare(k05_before$y, three_levels),
   "the rarity rule rejects the pre-correction K05, whose top category held 68.75%")
ok(!identical(FROZEN_DIGESTS[["K05"]], K05_BEFORE_CORRECTION_DIGEST),
   "K05 is no longer pinned to its pre-correction panel")

# ---- degeneracy guard -----------------------------------------------------------
# Three separate builders in this study were degenerate before this guard: a
# binary spread that was a multiple of its modulus, a categorical pattern whose
# object term vanished mod the category count, and an ordinal pattern whose row
# offset and object coefficient summed to a multiple of the modulus. Each looked
# healthy in an overall category table while giving every object one mean.
degenerate <- tryCatch({
  flat <- data.frame(item = rep(seq_len(5), each = 4), y = 1L)
  .eq_nondegenerate(flat, "y"); FALSE
}, error = function(e) TRUE)
ok(degenerate, "the non-degeneracy guard rejects a constant panel")

for (name in names(EQ_GEOMETRY)) {
  g <- EQ_GEOMETRY[[name]]
  ok(g$objects * g$raters * g$reps <= 1200L,
     paste0("geometry ", name, " stays within max_observations"))
}
for (name in names(EQ_CALIBRATION_GEOMETRY)) {
  g <- EQ_CALIBRATION_GEOMETRY[[name]]
  ok(g$objects * g$raters * g$reps <= 1200L,
     paste0("calibration geometry ", name, " stays within max_observations"))
}

# ---- the frozen numerical policy is the production policy ----------------------
# A more generous budget can turn a default rejection into an accepted result,
# which is the disposition change this study exists to detect rather than
# engineer away. These must track the package defaults.
production <- .gt_d_control(list())
for (field in c("maxit", "inner_maxit", "alternative_starts", "inner_tol", "reltol",
                "start_sd", "stationarity_tol", "validation_reltol", "validation_inner_tol",
                "stability_objective_tol", "stability_parameter_tol", "bound_tol",
                "optimizer"))
  ok(identical(EQ_CONTROL[[field]], production[[field]]),
     paste0("the frozen control ", field, " equals the production default"))
ok(!identical(EQ_CHARACTERIZATION_CONTROL$maxit, EQ_CONTROL$maxit),
   "the characterization budget is distinct from the qualification policy")

# ---- the covariance profile map resolves to real production arguments ----------
for (name in names(EQ_COVARIANCE_PROFILE)) {
  profile <- EQ_COVARIANCE_PROFILE[[name]]
  ok(profile$covariance %in% c("diagonal", "unstructured"),
     paste0("profile ", name, " names a real covariance argument"))
  ok(profile$parameterization %in% c("auto", "variance", "log_cholesky", "fixed"),
     paste0("profile ", name, " names a real parameterization"))
}
# auto resolves a q = 1 model to variance, so the log-Cholesky cases must ask
# for it explicitly or they would never exercise those coordinates at all.
ok(identical(EQ_COVARIANCE_PROFILE$log_cholesky$parameterization, "log_cholesky"),
   "the log-Cholesky profile requests that parameterization explicitly")
ok(identical(EQ_COVARIANCE_PROFILE$zero_capable$parameterization, "variance"),
   "the zero-capable profile requests the variance parameterization explicitly")

# ---- every frozen parameter point is admissible --------------------------------
# Fixture validation, not qualification: build the parameter map each case would
# actually be fitted with, and prove the three frozen stage 3 points are finite,
# inside the declared bounds, and decode into covariance factors, with any
# declared exact zero preserved exactly. Variance coordinates have a lower bound
# of exactly zero, so an unclamped displacement would leave EVERY such
# coordinate out of bounds, not merely a declared zero.
validate_points <- function(row, geometry, label) {
  map <- tryCatch(.eq_parameter_map(row, geometry), error = function(e) NULL)
  ok(!is.null(map), paste0(label, " builds a parameter map"))
  if (is.null(map)) return(invisible(NULL))
  points <- .eq_fixed_points(map$start, map$lower, map$upper, map$zero_coordinates)
  ok(identical(length(points), 3L), paste0(label, " has three frozen points"))
  if (length(map$zero_coordinates))
    ok(length(map$zero_coordinates) >= 1L,
       paste0(label, " resolves its declared exact-zero source to a coordinate"))
  for (name in names(points)) {
    value <- points[[name]]
    ok(all(is.finite(value)), paste0(label, " point ", name, " is finite"))
    ok(all(value >= map$lower) && all(value <= map$upper),
       paste0(label, " point ", name, " lies inside the declared bounds"))
    decoded <- tryCatch(
      .gt_d_covariance_factors(value[-seq_along(map$prep$start)], map$setup),
      error = function(e) NULL)
    ok(!is.null(decoded), paste0(label, " point ", name, " decodes into covariance factors"))
    if (length(map$zero_coordinates))
      ok(all(value[map$zero_coordinates] == 0),
         paste0(label, " point ", name, " keeps the declared zero exactly zero"))
  }
  invisible(map)
}
for (i in seq_len(nrow(EQ_CORE)))
  validate_points(EQ_CORE[i, ], EQ_GEOMETRY[[EQ_CORE$geometry[[i]]]],
                  paste0("case ", EQ_CORE$case[[i]]))
for (i in seq_len(nrow(EQ_CALIBRATION)))
  validate_points(EQ_CALIBRATION[i, ],
                  EQ_CALIBRATION_GEOMETRY[[EQ_CALIBRATION$geometry[[i]]]],
                  paste0("calibration ", EQ_CALIBRATION$case[[i]]))

# The declared exact-zero cases must actually resolve to a coordinate; a label
# with no matching parameter would silently exercise nothing.
for (case in names(EQ_ZERO_SOURCES)) {
  table <- if (case %in% EQ_CORE$case) EQ_CORE else EQ_CALIBRATION
  geometries <- if (case %in% EQ_CORE$case) EQ_GEOMETRY else EQ_CALIBRATION_GEOMETRY
  row <- table[table$case == case, ]
  map <- tryCatch(.eq_parameter_map(row, geometries[[row$geometry]]), error = function(e) NULL)
  ok(!is.null(map) && length(map$zero_coordinates) == 1L,
     paste0(case, " resolves exactly one exact-zero coordinate"))
}

# ---- transform and reference mechanics are frozen as data ----------------------
ok(identical(sort(names(EQ_TRANSFORM_DETAIL)), sort(EQ_TRANSFORM$transform)),
   "every transform has frozen mechanics")
ok(identical(EQ_TRANSFORM_DETAIL$T3$to, "c"),
   "T3 names the exact reference level it changes to")
ok(identical(EQ_TRANSFORM_DETAIL$T4$repeats, 2L),
   "T4 names the exact number of repeats")
ok(all(EQ_REFERENCE$reference %in% names(EQ_REFERENCE_SETTINGS)),
   "every predeclared reference has frozen settings")
# glmer and clmm both default to nAGQ = 1, which is itself Laplace: defaults
# would compare the approximation against itself and record it as independent.
ok(EQ_REFERENCE_SETTINGS[["lme4::glmer"]]$nAGQ > 1L,
   "the glmer reference uses quadrature rather than its Laplace default")
ok(EQ_REFERENCE_SETTINGS[["ordinal::clmm"]]$nAGQ > 1L,
   "the clmm reference uses quadrature rather than its Laplace default")

# ---- execution remains blocked --------------------------------------------------
ok(!file.exists(file.path(STUDY, "tolerances.csv")),
   "no tolerance table exists yet, so no qualification case may be scored")
runner <- paste(readLines(file.path(STUDY, "run-equivalence.R"), warn = FALSE), collapse = "\n")
ok(grepl("Refusing to run", runner, fixed = TRUE),
   "the launcher refuses to execute without a frozen tolerance table")

# The launcher is frozen and immutable, so it must carry no judging logic: the
# implementation that scores the cases has to be reviewable on its own, and if
# it lived here it could only be added by editing a pinned file.
ok(!file.exists(file.path(STUDY, EQ_RUNNER_IMPLEMENTATION)),
   "the judging implementation is absent from the protocol freeze")
ok(grepl(EQ_RUNNER_IMPLEMENTATION, runner, fixed = TRUE),
   "the launcher names the exact future implementation file")
ok(grepl("does not exist. The judging", runner, fixed = TRUE),
   "the launcher refuses to execute without that implementation")
# Ordering: tolerances are checked before the implementation is reachable.
ok(regexpr("TOLERANCES", runner, fixed = TRUE) <
     regexpr("source(IMPLEMENTATION)", runner, fixed = TRUE),
   "the launcher checks the tolerance table before sourcing any judging code")

# ---- the ruler is frozen --------------------------------------------------------
ok(identical(EQ_STAGE3_LATENT_POINT, 0),
   "stage 3's common latent evaluation point is frozen at zero")
ok(all(c("predictor", "conditional_objective", "mode_score", "hessian") %in%
         EQ_STAGE3_AT_COMMON_LATENT),
   "the unsolved stage 3 quantities are compared at a common latent point")
ok(length(intersect(EQ_STAGE3_AT_COMMON_LATENT, EQ_STAGE3_SOLVED)) == 0L,
   "no quantity is both common-latent and solved")
ok(all(c(EQ_INHERITED_PARITY, setdiff(EQ_CALIBRATED_QUANTITIES, "equivariance")) %in%
         names(EQ_METRIC)),
   "every judged quantity has a frozen metric")
# Symmetric, or the ruler privileges one backend and contradicts rule R2.
left <- c(1, 2, 3)
right <- c(1.1, 2, 3)
for (quantity in names(EQ_METRIC))
  ok(identical(.eq_difference(left, right, quantity),
               .eq_difference(right, left, quantity)),
     paste0("the metric for ", quantity, " is symmetric in its two arguments"))
for (quantity in names(EQ_METRIC)) {
  metric <- EQ_METRIC[[quantity]]
  ok(metric$form %in% c("absolute", "symmetric_relative"),
     paste0(quantity, " names a frozen metric form"))
  if (identical(metric$form, "symmetric_relative"))
    ok(is.numeric(metric$floor) && metric$floor > 0,
       paste0(quantity, " carries a positive absolute floor"))
}
ok(identical(EQ_METRIC$marginal_negative_log_likelihood$form, "absolute") &&
     identical(EQ_METRIC$conditional_objective$form, "absolute"),
   "the inherited contract is recorded as the absolute difference it was qualified as")
ok(!is.finite(.eq_difference(c(1, NaN), c(1, 2), "predictor")),
   "a non-finite input makes the difference non-finite rather than passing")
ok(!is.finite(.eq_difference(c(1, 2), c(1, 2, 3), "predictor")),
   "a length mismatch makes the difference non-finite rather than passing")

# Stage 1 witnesses carry their own frozen formulas and bounds, so R1
# classification cannot be invented after a disagreement appears.
for (witness in names(EQ_VALIDITY)) {
  entry <- EQ_VALIDITY[[witness]]
  ok(is.character(entry$formula) && nzchar(entry$formula),
     paste0("validity witness ", witness, " has a frozen formula"))
  ok(is.character(entry$bound) && nzchar(entry$bound),
     paste0("validity witness ", witness, " has a frozen bound"))
}
ok(identical(EQ_VALIDITY_BOUND(187), 32 * 187 * .Machine$double.eps),
   "the validity bound is the scale-aware rule frozen in #34")

# The factor-reconstruction witness must be backend-neutral in substance, not
# only in label. CHOLMOD is called with perm = TRUE and its contract is
# P H P' = L L', so a bare max|R'R - H| is a dense-only formula.
reconstruction <- EQ_VALIDITY$factor_reconstruction
ok(grepl("ORIGINAL H coordinate order", reconstruction$formula, fixed = TRUE),
   "the reconstruction witness requires the original coordinate order")
ok(is.character(reconstruction$dense) && is.character(reconstruction$sparse),
   "the reconstruction witness freezes a realization for each backend")
ok(grepl("P' L L' P", reconstruction$sparse, fixed = TRUE),
   "the sparse realization undoes the permutation")

# And the distinction is asserted numerically, so a later implementation cannot
# quietly compare crossprod(L) against unpermuted H. C06's permutation is not a
# symmetry of its Hessian, so the unpermuted comparison is enormous there.
reconstruction_row <- EQ_CORE[EQ_CORE$case == "C06", ]
reconstruction_map <- tryCatch(
  .eq_parameter_map(reconstruction_row, EQ_GEOMETRY[[reconstruction_row$geometry]]),
  error = function(e) NULL)
ok(!is.null(reconstruction_map), "C06 builds a map for the reconstruction check")
if (!is.null(reconstruction_map)) {
  cov_factors <- .gt_d_covariance_factors(
    reconstruction_map$start[-seq_along(reconstruction_map$prep$start)],
    reconstruction_map$setup)
  backend <- .gt_d_sparse_backend(reconstruction_map$groups, cov_factors,
                                  reconstruction_map$prep$n, reconstruction_map$prep$q)
  kernel <- .gt_d_response_kernel(
    .gt_d_baseline(reconstruction_map$start, reconstruction_map$prep),
    reconstruction_map$start, reconstruction_map$prep)
  sparse_h <- .gt_d_sparse_hessian(kernel$curvature, backend$W, reconstruction_map$prep$n)
  dense_h <- as.matrix(Matrix::forceSymmetric(sparse_h))
  factorization <- .gt_d_sparse_factor(sparse_h)
  scale <- max(abs(dense_h))
  bound <- EQ_VALIDITY_BOUND(nrow(dense_h))
  unpermuted <- max(abs(as.matrix(Matrix::tcrossprod(
    methods::as(factorization$factor, "CsparseMatrix"))) - dense_h)) / scale
  aware <- max(abs(as.matrix(Reduce(`%*%`,
    Matrix::expand2(factorization$factor, LDL = FALSE))) - dense_h)) / scale
  ok(unpermuted > bound,
     "the unpermuted comparison really does fail, so the distinction is not cosmetic")
  ok(aware <= bound,
     "the permutation-aware reconstruction satisfies the frozen validity bound")
}
ok(!file.exists(file.path(STUDY, "results.csv")),
   "the freeze contains no qualification results")
ok(!file.exists(file.path(STUDY, "calibration-results.csv")),
   "the freeze contains no calibration results")
schema <- readLines(file.path(STUDY, "results-schema.csv"), warn = FALSE)
ok(identical(length(schema), 1L), "the result schema is a header only")
for (column in c("row_kind", "stage", "quantity", "disposition", "approximation_reference",
                 "approximation_error", "inner_evaluations", "invalid_evaluations",
                 "budget_terminations", "solve_validity_failures", "tolerance_applied",
                 "random_dimension"))
  ok(grepl(column, schema[[1L]], fixed = TRUE),
     paste0("the result schema declares ", column))

if (fails) { cat("FAILURES: ", fails, "\n", sep = ""); quit(status = 1) }
cat("Equivalence study freeze verified: source pinning, no RNG, matrix shape and ",
    "coverage, calibration disjointness, parent-scoped nesting, frozen numerical ",
    "choices, fixture digests and dimensions, degeneracy guard, and blocked execution.\n",
    sep = "")
