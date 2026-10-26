# Launcher for the qualification under Amendment 1 (AMENDMENT-1.md).
#
# Like the frozen launcher it contains no comparison logic, and it refuses to
# run without the calibrated tolerances, the pinned fixtures and both judging
# implementations. It sources the merged implementation and then the
# amendment's stage 3, and writes to results-amendment-1/ unless EQ_RESULTS_DIR
# names another new directory. The original record in results/ is not touched.
#
# Run from the project directory, with one numerical thread:
#   Rscript --vanilla validation-studies/discrete-sparse-equivalence/run-equivalence-amendment-1.R
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
TOLERANCES <- file.path(STUDY, "tolerances.csv")
IMPLEMENTATION <- file.path(STUDY, "equivalence-runner-impl.R")
AMENDMENT <- file.path(STUDY, "amendment-1-impl.R")

for (required in c(TOLERANCES, file.path(STUDY, "fixture-digests.csv"), IMPLEMENTATION, AMENDMENT))
  if (!file.exists(required))
    stop("Refusing to run: ", required, " does not exist.", call. = FALSE)

source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode",
            "discrete_sparse", "discrete_sparse_mode", "discrete", "diagnostics_stages"))
  source(file.path("R", paste0(f, ".R")))
source(IMPLEMENTATION)
source(AMENDMENT)
eq1_run_qualification(study = STUDY, tolerances = read.csv(TOLERANCES, stringsAsFactors = FALSE))
