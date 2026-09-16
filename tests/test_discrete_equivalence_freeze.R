# Run from the project directory with Rscript tests/test_discrete_equivalence_freeze.R.
#
# Contract test for the frozen dense/sparse equivalence study. It asserts that
# the study is FROZEN, not that any qualification passed: no qualification has
# been executed yet. What it protects is that the manifest, the fixtures and the
# preconditions cannot drift between the freeze and the execution that scores
# against them.
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))

fails <- 0L
ok <- function(condition, label) {
  if (!isTRUE(condition)) { fails <<- fails + 1L; cat("FAIL: ", label, "\n", sep = "") }
}

# The fixtures must never depend on the random number generator. rnorm after a
# fixed seed is not bit-reproducible across architectures, so a seeded fixture
# is a different matrix on arm64 than on x86_64 and a qualification run on it
# could not separate an implementation difference from a fixture difference.
manifest <- readLines(file.path(STUDY, "cases.R"), warn = FALSE)
code <- manifest[!grepl("^\\s*#", manifest)]
for (banned in c("set.seed", "rnorm", "rbinom", "rlogis", "runif", "sample"))
  ok(!any(grepl(banned, code, fixed = TRUE)),
     paste0("the case manifest does not call ", banned))

# The frozen matrix shape. A case silently added or removed changes what the
# qualification covers without changing anything that reads as a contract.
ok(identical(nrow(EQ_CORE), 15L), "fifteen core cases")
ok(identical(nrow(EQ_NEGATIVE), 6L), "six negative overlays")
ok(identical(nrow(EQ_TRANSFORM), 5L), "five equivariance transforms")
ok(identical(sort(EQ_CORE$case), sort(c("C01", "C02", "C03", "C04", "C05", "C06", "C07", "C08", "C09", "C10", "C11", "C12", "C13", "C14", "C15"))), "the core case identifiers are frozen")

# The support envelope is a frozen statement, not a discovery. Sparse refuses
# categorical curvature and joint outcomes are outside the 0.2 envelope.
ok(identical(EQ_CORE$sparse_supported[EQ_CORE$case == "C14"], "no_categorical"),
   "the categorical case is frozen as unsupported by sparse")
ok(identical(EQ_CORE$sparse_supported[EQ_CORE$case == "C15"], "no_joint"),
   "the joint case is frozen as unsupported by sparse")
ok(sum(EQ_CORE$sparse_supported == "yes") == 13L, "thirteen sparse-supported cases")

# Coverage the protocol claims.
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

# The frozen panels. A changed fixture must be detectable rather than silent.
FROZEN_DIGESTS <- c(
  C01 = "98d1af4f56237352865b3534f1380b79",
  C02 = "98d1af4f56237352865b3534f1380b79",
  C03 = "41ae2f12d91fee21de0978f2cada38e5",
  C04 = "41ae2f12d91fee21de0978f2cada38e5",
  C05 = "41ae2f12d91fee21de0978f2cada38e5",
  C06 = "98d1af4f56237352865b3534f1380b79",
  C07 = "41ae2f12d91fee21de0978f2cada38e5",
  C08 = "b24e6ad54bebd280adf394af05a1d1fd",
  C09 = "292077810f8b004a1cb88985d9846322",
  C10 = "292077810f8b004a1cb88985d9846322",
  C11 = "6e59626edb94bb179d8818cd56167c21",
  C12 = "5b3d72a56d3bf926fd8e64e5761c6ba4",
  C13 = "e465a89f9945e80432b6cb96a0f0163a",
  C14 = "b063c885c390c675668483de8c1ef3e8",
  C15 = "5399d08b9d0601649e2b894aa308857d")
FROZEN_OBSERVATIONS <- c(
  C01 = 90L,
  C02 = 90L,
  C03 = 288L,
  C04 = 288L,
  C05 = 288L,
  C06 = 90L,
  C07 = 288L,
  C08 = 1080L,
  C09 = 90L,
  C10 = 90L,
  C11 = 288L,
  C12 = 288L,
  C13 = 1080L,
  C14 = 90L,
  C15 = 288L)
recorded <- read.csv(file.path(STUDY, "fixture-digests.csv"), stringsAsFactors = FALSE)
ok(identical(nrow(recorded), 15L), "fifteen frozen fixture digests")
for (case in names(FROZEN_DIGESTS)) {
  row <- recorded[recorded$case == case, ]
  ok(identical(nrow(row), 1L), paste0("one digest row for ", case))
  if (nrow(row) == 1L) {
    ok(identical(row$panel_digest, unname(FROZEN_DIGESTS[[case]])),
       paste0("the frozen panel digest for ", case, " is unchanged"))
    ok(identical(as.integer(row$observations), unname(FROZEN_OBSERVATIONS[[case]])),
       paste0("the frozen observation count for ", case, " is unchanged"))
  }
}

# Every panel must carry real between-object variation. A panel whose objects
# all share one mean sits at the zero-variance boundary and qualifies nothing,
# while still looking healthy in an overall category table -- which is exactly
# how two builders in this file were wrong before the guard was added.
degenerate <- tryCatch({
  flat <- data.frame(item = rep(seq_len(5), each = 4), y = 1L)
  .eq_nondegenerate(flat, "y"); FALSE
}, error = function(e) TRUE)
ok(degenerate, "the non-degeneracy guard rejects a constant panel")

# Every geometry stays inside the declared dense limits.
for (name in names(EQ_GEOMETRY)) {
  g <- EQ_GEOMETRY[[name]]
  ok(g$objects * g$raters * g$reps <= 1200L,
     paste0("geometry ", name, " stays within max_observations"))
}

# Execution must remain blocked until the calibrated tolerances are frozen.
ok(!file.exists(file.path(STUDY, "tolerances.csv")),
   "no tolerance table exists yet, so no qualification case may be scored")
runner <- paste(readLines(file.path(STUDY, "run-equivalence.R"), warn = FALSE), collapse = "\n")
ok(grepl("Refusing to run", runner, fixed = TRUE),
   "the runner refuses to execute without a frozen tolerance table")

# No qualification results may be present in the freeze.
ok(!file.exists(file.path(STUDY, "results.csv")),
   "the freeze contains no qualification results")
schema <- readLines(file.path(STUDY, "results-schema.csv"), warn = FALSE)
ok(identical(length(schema), 1L), "the result schema is a header only")
for (column in c("stage", "disposition", "approximation_reference", "approximation_error",
                 "inner_evaluations", "invalid_evaluations", "budget_terminations",
                 "solve_validity_failures", "tolerance_applied"))
  ok(grepl(column, schema[[1L]], fixed = TRUE),
     paste0("the result schema declares ", column))

if (fails) { cat("FAILURES: ", fails, "\n", sep = ""); quit(status = 1) }
cat("Equivalence study freeze verified: manifest shape, coverage, support envelope, ",
    "frozen fixtures, degeneracy guard, blocked execution, and a results-free schema.\n", sep = "")
