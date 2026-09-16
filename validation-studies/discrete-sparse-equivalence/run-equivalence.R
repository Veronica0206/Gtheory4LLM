# Qualification runner for the dense/sparse equivalence study.
#
# REFUSES TO RUN until the calibration table exists. The protocol requires
# tolerances to be set before results are recorded, and a runner that will
# happily execute without them makes that requirement advisory. The check below
# is what makes it structural.
#
# Run from the project directory, after calibration has been frozen:
#   Rscript --vanilla validation-studies/discrete-sparse-equivalence/run-equivalence.R
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
TOLERANCES <- file.path(STUDY, "tolerances.csv")

if (!file.exists(TOLERANCES))
  stop("Refusing to run: ", TOLERANCES, " does not exist. The three calibrated ",
       "tolerance rules must be frozen, in their own change against the merged ",
       "protocol, before any qualification case is executed. See CALIBRATION.md.",
       call. = FALSE)

fixtures <- file.path(STUDY, "fixture-digests.csv")
if (!file.exists(fixtures))
  stop("Refusing to run: ", fixtures, " does not exist. Run freeze-fixtures.R ",
       "first so the panels this scores against are pinned.", call. = FALSE)

source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode",
            "discrete_sparse", "discrete_sparse_mode", "discrete", "diagnostics_stages"))
  source(file.path("R", paste0(f, ".R")))

# Stage 1 is the backend-neutral validity gate and runs before any comparison.
# Rule R1: a failure here is a backend numerical-validity event, recorded as
# such, and the case stops rather than being scored as an equivalence failure.
# Rule R2: neither backend is the oracle, so this gate is applied to each
# implementation against algebra, never against the other implementation.
#
# The comparison stages are written against the frozen tolerance table and are
# deliberately not implemented here: doing so before the tolerances exist would
# bake in a placeholder that someone later mistakes for a decision.
stop("The comparison stages are implemented in the execution change, against ",
     "the frozen tolerance table. This runner currently validates only that ",
     "the freeze preconditions are met.", call. = FALSE)
