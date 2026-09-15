# Fitted smoke matrix for a sparse discrete backend.
#
# Sourced by run-dense-oracle.R, which records the dense baseline, and later by
# the test that checks a sparse fitted backend reproduces the frozen contract.
# Both must evaluate the same cases, so neither defines them itself.
#
# This is a fitted study. It is deliberately separate from
# validation-studies/discrete-sparse-reference/, which is a fixed-parameter
# reference in which no outer optimizer runs and which makes no claim about
# fitted agreement. Neither study may be used to satisfy the other's contract.
#
# Panels are LOADED, never regenerated. panels.csv holds the authoritative
# rows; freeze-panels.R records how they were produced and is not run as part
# of qualification. set.seed() does not imply bitwise identical continuous
# draws across architectures, so a study that regenerated its panels would on
# some platforms be comparing two backends on two different datasets.
for (file in c("design.R", "family.R", "discrete_response.R", "discrete_dense.R",
               "discrete_mode.R", "discrete.R"))
  source(file.path("R", file))

smoke_dir <- file.path("validation-studies", "discrete-sparse-fitted-smoke")
family_spec <- function(family, link, levels, reference = NULL)
  list(family = family, link = link, levels = levels, reference = reference)

crossed <- list(object = "item", facets = "rater",
                term_members = list(item = "item", rater = "rater"))
single <- list(object = "item", facets = character(),
               term_members = list(item = "item"))

frozen_panels <- read.csv(file.path(smoke_dir, "panels.csv"), stringsAsFactors = FALSE,
                          colClasses = c(panel = "character", item = "integer",
                                         rater = "integer", y = "character"))
load_panel <- function(name, levels) {
  rows <- frozen_panels[frozen_panels$panel == name, c("item", "rater", "y"), drop = FALSE]
  if (!nrow(rows)) stop("panels.csv has no rows for panel ", name, ".")
  rows$y <- if (identical(levels, c("0", "1"))) as.integer(rows$y) else
    factor(rows$y, levels = levels)
  if (anyNA(rows$y)) stop("panel ", name, " has outcomes outside its declared levels.")
  rownames(rows) <- NULL
  rows
}

BINARY <- c("0", "1")
THREE <- paste0("c", 1:3)
FIVE <- paste0("c", 1:5)

# --- Accepted cases -----------------------------------------------------------
# Seven structures, each the fitted counterpart of a family whose
# fixed-parameter behaviour the separate reference study already freezes.
accepted <- list(
  list(key = "fit_binary_logit_single_source", panel = "binary_logit_single_source",
       levels = BINARY, families = list(family_spec("binary", "logit", BINARY)),
       design = single, covariance = "unstructured", control = list(maxit = 200L)),
  list(key = "fit_binary_probit_crossed", panel = "binary_probit_crossed",
       levels = BINARY, families = list(family_spec("binary", "probit", BINARY)),
       design = crossed, covariance = "unstructured", control = list(maxit = 200L)),
  # Binary logit on a crossed design whose second source carries no variance.
  # Covers the exact-zero boundary and is the only accepted case exercising
  # binary logit crossed.
  list(key = "fit_binary_logit_zero_source", panel = "binary_logit_zero_source",
       levels = BINARY, families = list(family_spec("binary", "logit", BINARY)),
       design = crossed, covariance = "unstructured", control = list(maxit = 200L)),
  list(key = "fit_ordinal_logit_crossed", panel = "ordinal_logit_crossed",
       levels = THREE, families = list(family_spec("ordinal", "logit", THREE)),
       design = crossed, covariance = "unstructured", control = list(maxit = 200L)),
  list(key = "fit_ordinal_probit_crossed", panel = "ordinal_probit_crossed",
       levels = THREE, families = list(family_spec("ordinal", "probit", THREE)),
       design = crossed, covariance = "unstructured", control = list(maxit = 200L)),
  # 400 rows: a 5% category must not be represented by a handful of rows.
  list(key = "fit_ordinal_logit_tail_mass", panel = "ordinal_logit_tail_mass",
       levels = FIVE, families = list(family_spec("ordinal", "logit", FIVE)),
       design = crossed, covariance = "unstructured", control = list(maxit = 200L)),
  list(key = "fit_binary_probit_fixed_covariance", panel = "binary_probit_fixed_covariance",
       levels = BINARY, families = list(family_spec("binary", "probit", BINARY)),
       design = crossed, covariance = "unstructured",
       control = list(maxit = 200L,
                      fixed_covariance = list(item = matrix(0.6), rater = matrix(0.25)))))

# --- Negative controls --------------------------------------------------------
# Each reuses an accepted panel literally, by name, and changes exactly one
# control, so the outcome is attributable to that control and not to the data.
# Three mechanisms: inner solve, outer optimizer, numerical acceptance.
# Deliberate parameter-bound contact belongs to the comprehensive failure
# matrix in #4, not here.
#
# Dispositions are "accepted", "rejected" (a fit is returned and acceptance
# says no) and "refused" (no fit is returned). The inner case is a refusal, and
# that was established from dense behaviour before any sparse work existed:
#
#   inner_maxit 1-2  refused, the conditional mode is unsolvable everywhere
#   inner_maxit 3    rejected, tight_final_mode_unavailable
#   inner_maxit 4-6  rejected, but inner_gradient is 1e-14 to 1e-16 and
#                    tight_final_mode is TRUE, so the inner solve has converged
#                    and the rejection is an outer or stability failure rather
#                    than a conditional-mode one
#   inner_maxit 8    accepted
#
# The conditional-mode rejection band is one iteration wide, and at that single
# value inner_converged passes by 16% (8.37e-07 against 1e-06). A contract
# pinned there would sit against the refusal boundary with no margin, and a
# small platform difference could change the outcome class. The refusal fails
# by several orders of magnitude and is two iterations wide, so it is used
# instead. Measuring the narrow rejection band belongs in #4.
#
# A refusal is also the stronger control: a sparse backend that returned a fit
# where dense refuses to produce one is exactly what these cases exist to catch.
negatives <- list(
  list(key = "refuse_truncated_inner_solve", source = "fit_binary_probit_crossed",
       control = list(maxit = 200L, inner_maxit = 1L), disposition = "refused",
       class = "conditional_mode_unavailable_at_start", mechanism = "conditional mode"),
  list(key = "reject_truncated_outer_optimizer", source = "fit_ordinal_logit_crossed",
       control = list(maxit = 1L), disposition = "rejected",
       class = "optimizer_incomplete", mechanism = "outer optimizer"),
  list(key = "reject_zero_restart_budget", source = "fit_binary_logit_single_source",
       control = list(maxit = 200L, alternative_starts = 0L), disposition = "rejected",
       class = "restart_or_tolerance_stability_failed", mechanism = "numerical acceptance"))

for (i in seq_along(accepted)) {
  accepted[[i]]$disposition <- "accepted"
  accepted[[i]]$class <- NA_character_
  accepted[[i]]$data <- load_panel(accepted[[i]]$panel, accepted[[i]]$levels)
}
for (i in seq_along(negatives)) {
  from <- Filter(function(a) identical(a$key, negatives[[i]]$source), accepted)[[1L]]
  negatives[[i]] <- utils::modifyList(negatives[[i]],
    from[c("panel", "levels", "families", "design", "covariance", "data")])
}

for (i in seq_along(accepted)) accepted[[i]]$outcomes <- "y"
for (i in seq_along(negatives)) negatives[[i]]$outcomes <- "y"
cases <- c(accepted, negatives)
accepted_keys <- vapply(accepted, `[[`, character(1), "key")
negative_keys <- vapply(negatives, `[[`, character(1), "key")
