# Generates the frozen fixture digests and source hashes for this study.
#
# Run from the project directory:
#   Rscript --vanilla validation-studies/discrete-sparse-equivalence/freeze-fixtures.R
#
# This is fixture generation, not qualification. It scores nothing, runs no
# backend, and produces no equivalence result. Its output pins WHICH panels the
# later qualification must run against, so a changed fixture is detectable
# rather than silent.
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))

# Canonical bytes, not a decimal rendering: format() is not portable across
# platforms and would report a difference where the data is identical.
digest_of <- function(...) {
  path <- tempfile("eq-digest-")
  on.exit(unlink(path), add = TRUE)
  connection <- file(path, "wb")
  tryCatch(for (value in list(...)) {
    if (is.factor(value)) value <- as.integer(value)
    if (is.character(value)) stop("refusing to digest character input")
    real <- is.double(value)
    writeBin(c(if (real) 2L else 1L, length(value)), connection, size = 4L, endian = "big")
    if (real) writeBin(value, connection, size = 8L, endian = "big")
    else writeBin(as.integer(value), connection, size = 4L, endian = "big")
  }, finally = base::close(connection))
  unname(tools::md5sum(path))
}

panel_for <- function(row) {
  geometry <- EQ_GEOMETRY[[row$geometry]]
  if (is.null(geometry)) stop("unknown geometry: ", row$geometry)
  switch(row$family,
    binary = .eq_binary_panel(geometry$objects, geometry$raters, geometry$reps),
    ordinal = .eq_ordinal_panel(geometry$objects, geometry$raters, geometry$reps,
                                .eq_ordinal_levels(row$geometry),
                                tail_mass = identical(row$geometry, "tail_mass")),
    categorical = .eq_categorical_panel(geometry$objects, geometry$raters, geometry$reps,
                                        c("a", "b", "c")),
    joint_binary = .eq_joint_panel(geometry$objects, geometry$raters, geometry$reps),
    stop("unknown family: ", row$family))
}

rows <- lapply(seq_len(nrow(EQ_CORE)), function(i) {
  row <- EQ_CORE[i, ]
  panel <- panel_for(row)
  outcomes <- if (identical(row$family, "joint_binary")) c("a", "b") else "y"
  columns <- c(list(panel$item, panel$rater, panel$rep, panel$occasion, panel$site),
               lapply(outcomes, function(nm) panel[[nm]]))
  data.frame(case = row$case, family = row$family, geometry = row$geometry,
             observations = nrow(panel), outcomes = paste(outcomes, collapse = "+"),
             panel_digest = do.call(digest_of, columns),
             stringsAsFactors = FALSE)
})
fixtures <- do.call(rbind, rows)
write.csv(fixtures, file.path(STUDY, "fixture-digests.csv"), row.names = FALSE)

sources <- c("PROTOCOL.md", "CALIBRATION.md", "README.md", "cases.R",
             "freeze-fixtures.R", "run-equivalence.R", "results-schema.csv")
present <- sources[file.exists(file.path(STUDY, sources))]
write.csv(data.frame(file = present,
                     md5 = unname(tools::md5sum(file.path(STUDY, present))),
                     stringsAsFactors = FALSE),
          file.path(STUDY, "source-hashes.csv"), row.names = FALSE)
cat("Froze ", nrow(fixtures), " fixture digests and ", length(present),
    " source hashes.\n", sep = "")
