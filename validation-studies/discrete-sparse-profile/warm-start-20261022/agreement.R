# Warm against cold objective agreement at 18 parameter vectors, at the coarse
# and at the validation inner tolerance. Run from the project directory:
#   Rscript --vanilla validation-studies/discrete-sparse-profile/warm-start-20261022/agreement.R
# Each vector is evaluated as a gradient probe ("warm_probe") seeded from the
# mode at a centre ("warm"), and cold from zero modes by a fresh evaluator.
# Writes agreement.csv beside this file.
HERE <- file.path("validation-studies", "discrete-sparse-profile", "warm-start-20261022")
suppressMessages(library(Matrix)); source("load_functions.R")
source(file.path("validation-studies", "discrete-sparse-equivalence", "cases.R"))
source(file.path(HERE, "synthetic-panel.R"))
rows <- list()
measure <- function(label, centre, vector, prep, groups, setup, control) {
  for (tolerance in c("coarse", "validation")) {
    settings <- control
    if (tolerance == "validation") settings$inner_tol <- min(control$inner_tol, control$validation_inner_tol)
    centre_role <- settings; centre_role$inner_start <- "warm"
    probe_role <- settings; probe_role$inner_start <- "warm_probe"
    warm <- .gt_d_sparse_evaluator()
    invisible(warm(centre, prep, groups, setup, centre_role, details = TRUE))
    w <- warm(vector, prep, groups, setup, probe_role, details = TRUE)
    k <- .gt_d_sparse_evaluator()(vector, prep, groups, setup, settings, details = TRUE)
    stopifnot(isTRUE(w$valid), isTRUE(k$valid), isTRUE(w$inner_warm_started))
    rows[[length(rows) + 1L]] <<- data.frame(vector = label, tolerance = tolerance,
      inner_tol = settings$inner_tol, random_dimension = length(k$mode),
      warm_objective = w$nll, cold_objective = k$nll, objective_difference = abs(w$nll - k$nll),
      max_mode_difference = max(abs(w$mode - k$mode)),
      warm_newton_steps = w$inner_iterations, cold_newton_steps = k$inner_iterations,
      stringsAsFactors = FALSE)
  }
}
for (i in seq_len(nrow(EQ_CALIBRATION))) {
  row <- EQ_CALIBRATION[i, ]
  map <- .eq_parameter_map(row, EQ_CALIBRATION_GEOMETRY[[row$geometry]])
  points <- .eq_fixed_points(map$start, map$lower, map$upper, map$zero_coordinates)
  for (label in c("displaced_positive", "displaced_negative"))
    measure(paste(row$case, label), points$start, points[[label]], map$prep, map$groups, map$setup, map$control)
}
panel <- synthetic_panel()
control <- .gt_d_control(list(engine = "sparse", max_observations = 21600L, max_random_dimension = 819L))
prep <- .gt_d_prepare(panel$data, "y", panel$families)
groups <- lapply(panel$members, function(m) .gt_d_group(panel$data, m))
setup <- .gt_d_covariance_setup(groups, prep$q, "diagonal", control, prep$dimensions)
before <- jsonlite::fromJSON(file.path(HERE, "before-synthetic-21600-lbfgsb-summary.json"), simplifyVector = FALSE)
centre <- c(prep$start, setup$start)
for (attempt in before$diagnostics$attempts)
  measure(paste("synthetic", attempt$label), centre, setNames(unlist(attempt$parameters), names(centre)),
          prep, groups, setup, control)
measure("synthetic optimum", centre, setNames(unlist(before$diagnostics$stability$tight_parameters[[1L]]), names(centre)),
        prep, groups, setup, control)
native <- gt_example("hate_speech", coding = "native")$data
design <- gt_design("item", c("evaluator", "prompt", "temp", "seed"), crossed = c("evaluator", "prompt"),
                    nested = list(temp = c("evaluator", "prompt"), seed = "temp"), item_nested = "temp")
control <- .gt_d_control(list(engine = "sparse", max_observations = 21600L, max_random_dimension = 9507L,
                              max_parameters = 12L, max_sparse_bytes = 6 * 1024^3))
prep <- .gt_d_prepare(native, "score", list(list(family = "ordinal", link = "probit", levels = levels(native$score))))
groups <- lapply(design$term_members, function(m) .gt_d_group(native, m))
setup <- .gt_d_covariance_setup(groups, prep$q, "diagonal", control, prep$dimensions)
start <- c(prep$start, setup$start)
neighbour <- start; j <- length(prep$start) + 1L; neighbour[[j]] <- neighbour[[j]] + 1e-3 * max(1, abs(neighbour[[j]]))
measure("native starting values", neighbour, start, prep, groups, setup, control)
ledger <- do.call(rbind, rows)
write.csv(ledger, file.path(HERE, "agreement.csv"), row.names = FALSE)
print(aggregate(objective_difference ~ tolerance, ledger, max))
