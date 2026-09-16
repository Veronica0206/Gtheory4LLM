# Immutable launcher for the dense/sparse equivalence qualification.
#
# This file is one of the externally pinned frozen sources and MUST NOT CHANGE.
# It contains no comparison logic, deliberately: the code that judges the cases
# has to be reviewable on its own before it is allowed to produce the record it
# reports, and a runner whose judging logic lived here could only be added by
# editing a file the protocol says may never move.
#
# The separation is therefore structural. This launcher enforces the ordering;
# the implementation named below arrives in its own later change and receives
# its own review, without either one being able to redefine the other's rules.
#
# Run from the project directory, after calibration has been frozen:
#   Rscript --vanilla validation-studies/discrete-sparse-equivalence/run-equivalence.R
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
TOLERANCES <- file.path(STUDY, "tolerances.csv")
IMPLEMENTATION <- file.path(STUDY, "equivalence-runner-impl.R")

if (!file.exists(TOLERANCES))
  stop("Refusing to run: ", TOLERANCES, " does not exist. The calibrated ",
       "tolerance values must be frozen, in their own change against the merged ",
       "protocol, before any qualification case is executed. See CALIBRATION.md.",
       call. = FALSE)

fixtures <- file.path(STUDY, "fixture-digests.csv")
if (!file.exists(fixtures))
  stop("Refusing to run: ", fixtures, " does not exist. Run freeze-fixtures.R ",
       "first so the panels this scores against are pinned.", call. = FALSE)

if (!file.exists(IMPLEMENTATION))
  stop("Refusing to run: ", IMPLEMENTATION, " does not exist. The judging ",
       "implementation is added by its own change, reviewed separately from this ",
       "protocol and from the calibrated tolerances.", call. = FALSE)

source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode",
            "discrete_sparse", "discrete_sparse_mode", "discrete", "diagnostics_stages"))
  source(file.path("R", paste0(f, ".R")))

# The implementation inherits the frozen rulers from cases.R and the frozen
# tolerance VALUES from tolerances.csv. It may not redefine either: the metric
# formulas, the stage 3 latent evaluation point and the stage 1 validity
# witnesses are fixed here, and only the numbers were left to calibration.
source(IMPLEMENTATION)
eq_run_qualification(study = STUDY, tolerances = read.csv(TOLERANCES,
                                                          stringsAsFactors = FALSE))
