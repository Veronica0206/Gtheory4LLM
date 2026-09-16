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
  "PROTOCOL.md" = "ae03173b56c39283e231bb0261664dfd",
  "CALIBRATION.md" = "7e07a789301012b00b981153c3e61fe4",
  "README.md" = "2f73e051d4be697fa35841eba91a9f81",
  "cases.R" = "59568d0521b92d16bab74419410dd366",
  "freeze-fixtures.R" = "8fd83f8762f7025a1c832128597241b8",
  "run-equivalence.R" = "b598b2c7bdd792325a733fca38f5012f",
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
ok(identical(EQ_CONTROL$maxit, 200L) && identical(EQ_CONTROL$inner_maxit, 100L) &&
     identical(EQ_CONTROL$alternative_starts, 2L), "the control settings are frozen")
ok(identical(EQ_FIXED_POINT_LABELS,
             c("start", "displaced_positive", "displaced_negative")),
   "three frozen fixed-parameter points")
points <- .eq_fixed_points(c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6))
ok(identical(length(points), 3L) && !identical(points$start, points$displaced_positive) &&
     !identical(points$start, points$displaced_negative),
   "the displacements are deterministic and differ from the start")
ok(identical(points, .eq_fixed_points(c(0.1, 0.2, 0.3, 0.4, 0.5, 0.6))),
   "the fixed-parameter points are reproducible")
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
  "K03" = "74c39aefcac96575c6e9b1a7e3c17a22",
  "K04" = "e18a2d7851e77a56b6ccdb2ece153b6c",
  "K05" = "e1dddcce3be9f8a72791affcd3b449b0",
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
  "K03" = 1200L,
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
  "C14" = 13L,
  "C15" = 28L,
  "K01" = 14L,
  "K02" = 34L,
  "K03" = 158L,
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
  }
}
near <- recorded[recorded$geometry == "near_limit", ]
ok(nrow(near) == 2L && all(near$random_dimension >= 180L) &&
     all(near$random_dimension <= 200L),
   "the near-limit cases genuinely approach the dense random-dimension ceiling")

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

# ---- execution remains blocked --------------------------------------------------
ok(!file.exists(file.path(STUDY, "tolerances.csv")),
   "no tolerance table exists yet, so no qualification case may be scored")
runner <- paste(readLines(file.path(STUDY, "run-equivalence.R"), warn = FALSE), collapse = "\n")
ok(grepl("Refusing to run", runner, fixed = TRUE),
   "the runner refuses to execute without a frozen tolerance table")
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
