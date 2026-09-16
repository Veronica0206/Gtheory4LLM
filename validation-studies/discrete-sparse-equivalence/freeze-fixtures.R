# Generates the frozen fixture digests, random dimensions and source hashes.
#
# Run from the project directory:
#   Rscript --vanilla validation-studies/discrete-sparse-equivalence/freeze-fixtures.R
#
# This is fixture generation, not qualification. It scores nothing, runs no
# backend and produces no equivalence result. Its output pins WHICH panels the
# later qualification and calibration must run against, and how large the
# resulting random-effect coordinate systems are, so a changed fixture or a
# quietly shrunken "near-limit" geometry is detectable rather than silent.
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode", "discrete"))
  source(file.path("R", paste0(f, ".R")))

# Canonical bytes for numeric data. Hashing a decimal rendering instead would
# make the digest depend on format(), which is not portable across platforms.
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

# Normalized text, because git checks text files out with CRLF on Windows and a
# raw byte hash would only reproduce on the platform that wrote it.
content_digest <- function(path) {
  normalized <- tempfile("eq-content-")
  on.exit(unlink(normalized), add = TRUE)
  connection <- file(normalized, "wb")
  tryCatch(writeBin(charToRaw(paste0(paste(readLines(path, warn = FALSE), collapse = "\n"), "\n")),
                    connection), finally = base::close(connection))
  unname(tools::md5sum(normalized))
}

.eq_designs <- list(single = .eq_design_single, crossed2 = .eq_design_crossed2,
                    crossed3 = .eq_design_crossed3, nested = .eq_design_nested)

panel_for <- function(family, geometry_name, geometry) {
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

describe <- function(table, geometries, set) do.call(rbind, lapply(seq_len(nrow(table)), function(i) {
  row <- table[i, ]
  geometry <- geometries[[row$geometry]]
  if (is.null(geometry)) stop("unknown geometry: ", row$geometry)
  panel <- panel_for(row$family, row$geometry, geometry)
  outcomes <- if (identical(row$family, "joint_binary")) EQ_JOINT_OUTCOMES else "y"
  design <- .eq_designs[[row$structure]]
  if (is.null(design)) stop("unknown structure: ", row$structure)
  groups <- lapply(design$term_members, function(members) .gt_d_group(panel, members))
  columns <- c(list(panel$item, panel$rater, panel$rep, panel$occasion,
                    panel$site, panel$nested_rater),
               lapply(outcomes, function(nm) panel[[nm]]))
  data.frame(set = set, case = row$case, family = row$family, structure = row$structure,
             geometry = row$geometry, observations = nrow(panel),
             outcomes = paste(outcomes, collapse = "+"),
             # Per latent dimension. The fitted random dimension is this times q.
             random_dimension = sum(vapply(groups, `[[`, integer(1), "nlevels")),
             kernel_rank = .gt_d_kernel_rank(groups)$rank,
             panel_digest = do.call(digest_of, columns),
             stringsAsFactors = FALSE)
}))

fixtures <- rbind(describe(EQ_CORE, EQ_GEOMETRY, "qualification"),
                  describe(EQ_CALIBRATION, EQ_CALIBRATION_GEOMETRY, "calibration"))
write.csv(fixtures, file.path(STUDY, "fixture-digests.csv"), row.names = FALSE)

sources <- c("PROTOCOL.md", "CALIBRATION.md", "README.md", "cases.R",
             "freeze-fixtures.R", "run-equivalence.R", "results-schema.csv")
missing <- sources[!file.exists(file.path(STUDY, sources))]
if (length(missing)) stop("missing frozen source: ", paste(missing, collapse = ", "))
write.csv(data.frame(file = sources,
                     md5 = vapply(file.path(STUDY, sources), content_digest, character(1),
                                  USE.NAMES = FALSE),
                     stringsAsFactors = FALSE),
          file.path(STUDY, "source-hashes.csv"), row.names = FALSE)
cat("Froze ", nrow(fixtures), " fixture digests (",
    sum(fixtures$set == "qualification"), " qualification, ",
    sum(fixtures$set == "calibration"), " calibration) and ", length(sources),
    " normalized source hashes.\n", sep = "")
