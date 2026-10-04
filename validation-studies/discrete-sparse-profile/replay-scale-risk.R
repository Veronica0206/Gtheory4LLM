# Replay of the retained 2,400-row scale-risk specimen, with the failed
# evaluations' own records.
#
# Characterization, not qualification. The specimen in results.md section 3
# was recorded before a failed evaluation carried any iteration count or
# reason, so the profile could not say what its invalid evaluations were. This
# script regenerates that panel (its digest is checked against the recorded
# one), refits it through the sparse evaluator with every evaluation observed
# in detailed form, and replays every invalid evaluation and every valid solve
# that ended at the inner iteration budget through BOTH evaluators at the same
# parameters and the same tolerance, reading each backend's own reason,
# convergence flag, gradient and stopping cause.
#
# Run from the project directory. Writes its tables to the directory given as
# the first argument, or to a temporary directory:
#   Rscript --vanilla validation-studies/discrete-sparse-profile/replay-scale-risk.R [out_dir]
#
# Both backends are evaluated in one process: nothing here measures time or
# memory, so the one-backend-per-process rule of the profile does not apply.
arguments <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(arguments)) arguments[[1L]] else tempfile("gt-scale-risk-replay-")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
for (file in c("design.R", "family.R", "discrete_response.R", "discrete_dense.R",
               "discrete_sparse.R", "discrete_mode.R", "discrete_sparse_mode.R",
               "discrete.R"))
  source(file.path("R", file))
suppressMessages(library(Matrix))

# The same generator family as profile-medium.R, at the recorded size.
set.seed(4101)
items <- 150L
raters <- 16L
data <- expand.grid(item = seq_len(items), rater = seq_len(raters))
item_effect <- rnorm(items, sd = 0.8)
rater_effect <- rnorm(raters, sd = 0.4)
latent <- item_effect[data$item] + rater_effect[data$rater] + rlogis(nrow(data))
proportions <- c(0.10, 0.20, 0.40, 0.20, 0.10)
cuts <- unname(stats::quantile(latent, probs = cumsum(proportions)[-5L], names = FALSE))
data$y <- factor(paste0("c", findInterval(latent, cuts) + 1L), levels = paste0("c", 1:5))
design <- list(object = "item", facets = "rater",
               term_members = list(item = "item", rater = "rater"))
families <- list(list(family = "ordinal", link = "logit",
                      levels = paste0("c", 1:5), reference = NULL))

panel_digest <- local({
  panel_file <- tempfile("gt-panel-", fileext = ".csv")
  write.csv(data, panel_file, row.names = FALSE)
  normalized <- tempfile("gt-norm-")
  connection <- file(normalized, "wb")
  tryCatch(writeBin(charToRaw(paste0(paste(readLines(panel_file, warn = FALSE),
                                           collapse = "\n"), "\n")), connection),
           finally = close(connection))
  on.exit(unlink(c(normalized, panel_file)), add = TRUE)
  unname(tools::md5sum(normalized))
})
RECORDED_DIGEST <- "bad937e27a0ce3ee587b47ca1ae41b25"
cat(sprintf("panel_md5=%s recorded=%s same_panel=%s\n", panel_digest, RECORDED_DIGEST,
            identical(panel_digest, RECORDED_DIGEST)))
if (!identical(panel_digest, RECORDED_DIGEST))
  cat("The regenerated panel differs from the recorded specimen on this platform;",
      "the replay below characterizes THIS panel, not the recorded one.\n")

# 2400 rows exceed the dense guard; the guard is raised only so the sparse fit
# can be attempted, exactly as the profile did. No dense FIT is run here.
control <- .gt_d_control(list(max_observations = 2400L))
prep <- .gt_d_prepare(data, "y", families)
groups <- lapply(design$term_members, function(members) .gt_d_group(data, members))
setup <- .gt_d_covariance_setup(groups, prep$q, "unstructured", control, prep$dimensions)

sparse_evaluator <- .gt_d_sparse_evaluator()
records <- list()
field <- function(value, name, default) if (is.list(value) && !is.null(value[[name]])) value[[name]] else default
observed <- function(parameters, prep, groups, setup, control, details = FALSE,
                     factors_override = NULL) {
  value <- sparse_evaluator(parameters, prep, groups, setup, control,
                            details = TRUE, factors_override = factors_override)
  valid <- .gt_d_evaluation_usable(value)
  records[[length(records) + 1L]] <<- list(
    parameters = parameters, inner_tol = control$inner_tol, valid = valid,
    inner_iterations = field(value, "inner_iterations", NA_integer_),
    inner_converged = field(value, "inner_converged", NA),
    inner_gradient = field(value, "inner_gradient", NA_real_),
    reason = field(value, "reason", NA_character_),
    line_search_failed = field(value, "inner_line_search_failed", NA))
  if (details) value else if (valid) value$nll else 1e100
}
fit <- tryCatch(.gt_fit_discrete(data, "y", design, families, covariance = "unstructured",
                                 control = list(max_observations = 2400L),
                                 .laplace = observed, .engine = "sparse_marginal_laplace"),
                error = function(e) structure(list(message = conditionMessage(e)),
                                              class = "refused"))
cat(sprintf("sparse fit: %s\n", if (inherits(fit, "refused")) paste("refused:", fit$message) else
  paste0("accepted=", isTRUE(fit$numerically_accepted), " failures=",
         paste(fit$diagnostics$acceptance_failures, collapse = ","))))
if (!inherits(fit, "refused")) {
  log <- fit$diagnostics$evaluations
  cat(sprintf("fit log: evaluations=%d invalid=%d valid_at_inner_budget=%d retained=%d\n",
              log$count, log$invalid, log$valid_at_inner_budget, length(log$retained_invalid)))
}
valid <- vapply(records, `[[`, logical(1), "valid")
iterations <- vapply(records, function(r) as.integer(r$inner_iterations), integer(1))
cat(sprintf("observed: evaluations=%d valid=%d invalid=%d valid_at_inner_maxit=%d\n",
            length(records), sum(valid), sum(!valid),
            sum(valid & !is.na(iterations) & iterations >= control$inner_maxit)))

describe <- function(value, prefix) {
  valid <- .gt_d_evaluation_usable(value)
  out <- list(valid = valid,
              reason = field(value, "reason", NA_character_),
              converged = field(value, "inner_converged", NA),
              iterations = field(value, "inner_iterations", NA_integer_),
              gradient = field(value, "inner_gradient", NA_real_),
              line_search_failed = field(value, "inner_line_search_failed", NA),
              backward_error = field(value, "solve_backward_error", NA_real_),
              nll = if (valid) value$nll else NA_real_)
  names(out) <- paste0(prefix, "_", names(out))
  out
}
replay <- function(index) {
  r <- records[[index]]
  replay_control <- control
  replay_control$inner_tol <- r$inner_tol
  dense <- .gt_d_laplace(r$parameters, prep, groups, setup, replay_control, details = TRUE)
  sparse <- sparse_evaluator(r$parameters, prep, groups, setup, replay_control, details = TRUE)
  as.data.frame(c(list(evaluation = index, inner_tol = r$inner_tol,
                       phase = if (r$inner_tol < control$inner_tol) "tight" else "coarse",
                       recorded_valid = r$valid, recorded_iterations = r$inner_iterations,
                       recorded_gradient = r$inner_gradient,
                       recorded_line_search_failed = r$line_search_failed),
                  describe(sparse, "sparse"), describe(dense, "dense")),
                stringsAsFactors = FALSE)
}
invalid_index <- which(!valid)
budget_index <- which(valid & !is.na(iterations) & iterations >= control$inner_maxit)
cat(sprintf("replaying %d invalid and %d at-budget evaluations through both backends\n",
            length(invalid_index), length(budget_index)))
table_invalid <- do.call(rbind, lapply(invalid_index, replay))
table_budget <- do.call(rbind, lapply(budget_index, replay))
write.csv(table_invalid, file.path(out_dir, "replay-invalid.csv"), row.names = FALSE)
write.csv(table_budget, file.path(out_dir, "replay-at-budget.csv"), row.names = FALSE)

count <- function(x) if (is.null(x) || !length(x)) 0L else sum(x, na.rm = TRUE)
threshold <- function(tol) 10 * tol
cat("\n== invalid evaluations ==\n")
cat(sprintf("phase: tight=%d coarse=%d\n", count(table_invalid$phase == "tight"),
            count(table_invalid$phase == "coarse")))
cat(sprintf("sparse reason: solve/factor invariant=%d none (non-convergence)=%d\n",
            count(!is.na(table_invalid$sparse_reason)), count(is.na(table_invalid$sparse_reason))))
cat(sprintf("sparse stopped: line search failed=%d at iteration budget=%d other=%d\n",
            count(isTRUE(table_invalid$sparse_line_search_failed) | table_invalid$sparse_line_search_failed %in% TRUE),
            count(!(table_invalid$sparse_line_search_failed %in% TRUE) &
                    table_invalid$sparse_iterations >= control$inner_maxit),
            count(!(table_invalid$sparse_line_search_failed %in% TRUE) &
                    table_invalid$sparse_iterations < control$inner_maxit)))
cat(sprintf("sparse replay reproduces the invalid verdict: %d of %d\n",
            count(!table_invalid$sparse_valid), nrow(table_invalid)))
cat(sprintf("dense at the same points: invalid=%d valid=%d; dense solve/factor reasons=%d\n",
            count(!table_invalid$dense_valid), count(table_invalid$dense_valid),
            count(!is.na(table_invalid$dense_reason))))
straddle <- table_invalid$dense_valid
if (any(straddle)) {
  cat("dense-valid at sparse-invalid points (gradient vs relaxed threshold 10 * inner_tol):\n")
  print(data.frame(evaluation = table_invalid$evaluation[straddle],
                   phase = table_invalid$phase[straddle],
                   threshold = threshold(table_invalid$inner_tol[straddle]),
                   sparse_gradient = signif(table_invalid$sparse_gradient[straddle], 3),
                   dense_gradient = signif(table_invalid$dense_gradient[straddle], 3),
                   dense_iterations = table_invalid$dense_iterations[straddle]), row.names = FALSE)
}
cat("\n== valid evaluations that ended at the inner iteration budget ==\n")
cat(sprintf("phase: tight=%d coarse=%d\n", count(table_budget$phase == "tight"),
            count(table_budget$phase == "coarse")))
cat(sprintf("dense at the same points: valid=%d (of which at budget=%d) invalid=%d; dense solve/factor reasons=%d\n",
            count(table_budget$dense_valid),
            count(table_budget$dense_valid & table_budget$dense_iterations >= control$inner_maxit),
            count(!table_budget$dense_valid), count(!is.na(table_budget$dense_reason))))
straddle <- !table_budget$dense_valid
if (any(straddle)) {
  cat("dense-invalid at sparse-valid points (gradient vs relaxed threshold 10 * inner_tol):\n")
  print(data.frame(evaluation = table_budget$evaluation[straddle],
                   phase = table_budget$phase[straddle],
                   threshold = threshold(table_budget$inner_tol[straddle]),
                   sparse_gradient = signif(table_budget$sparse_gradient[straddle], 3),
                   dense_gradient = signif(table_budget$dense_gradient[straddle], 3),
                   dense_line_search_failed = table_budget$dense_line_search_failed[straddle]),
        row.names = FALSE)
}
agree <- table_budget$dense_valid & table_budget$sparse_valid
if (any(agree))
  cat(sprintf("where both are valid, max |dense nll - sparse nll| = %.3g\n",
              max(abs(table_budget$dense_nll[agree] - table_budget$sparse_nll[agree]))))
cat(sprintf("\ntables written to %s\n", out_dir))
