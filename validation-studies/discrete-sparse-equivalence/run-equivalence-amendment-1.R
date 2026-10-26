# Launcher for the qualification under Amendment 1 (AMENDMENT-1.md).
#
# Like the frozen launcher it contains no comparison logic. Before it sources
# anything it verifies the reviewed runtime pins: amendment-1-pins.csv must have
# the digest written below, and every file it lists (this amendment, both
# judging implementations, the calibrated tolerances, the fixture pins and the
# frozen source manifest) must match its pin. It then sources the merged
# implementation and the amendment's stage 3, whose entry point repeats the
# check and reads the tolerances from the verified file. It writes to
# results-amendment-1/ unless EQ_RESULTS_DIR names another new directory. The
# original record in results/ is not touched.
#
# Run from the project directory, with one numerical thread:
#   Rscript --vanilla validation-studies/discrete-sparse-equivalence/run-equivalence-amendment-1.R
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
PINS <- file.path(STUDY, "amendment-1-pins.csv")
PINS_DIGEST <- "22d709a297e5d3f4b2c2751d71803058"

content_digest <- function(path) {
  normalized <- tempfile("eq-launch-")
  on.exit(unlink(normalized), add = TRUE)
  writeBin(charToRaw(paste0(paste(readLines(path, warn = FALSE), collapse = "\n"), "\n")), normalized)
  unname(tools::md5sum(normalized))
}
if (!file.exists(PINS) || !identical(content_digest(PINS), PINS_DIGEST))
  stop("Refusing to launch: ", PINS, " is not the reviewed manifest of runtime pins.", call. = FALSE)
pins <- read.csv(PINS, stringsAsFactors = FALSE)
moved <- pins$file[!file.exists(file.path(STUDY, pins$file)) |
                     vapply(file.path(STUDY, pins$file), function(p) if (file.exists(p)) content_digest(p) else "",
                            character(1), USE.NAMES = FALSE) != pins$md5]
if (length(moved))
  stop("Refusing to launch: ", paste(moved, collapse = ", "), " differ from the reviewed pins in ", PINS, ".",
       call. = FALSE)

source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode",
            "discrete_sparse", "discrete_sparse_mode", "discrete", "diagnostics_stages"))
  source(file.path("R", paste0(f, ".R")))
source(file.path(STUDY, "equivalence-runner-impl.R"))
source(file.path(STUDY, "amendment-1-impl.R"))
eq1_run_qualification(study = STUDY)
