# Installed-package checks that the staged summary tells the truth about a real
# public fit.
#
# The source-mode tests build fit objects by hand, which is how three defects
# survived them: a hand-made object recorded adequacy as "exact", a string the
# package never writes, and always carried complete evidence. These checks use
# the public API only, so the stages are read from objects the package itself
# produced.
library(Gtheory4LLM)

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
stage <- function(fit, name) gt_diagnostics(fit)$stages[[name]]

# --- A balanced Gaussian fit has an exact likelihood -------------------------
set.seed(4001)
gaussian <- expand.grid(item = seq_len(12), rater = seq_len(3))
gaussian$score <- rnorm(12, sd = 1.1)[gaussian$item] + rnorm(nrow(gaussian), sd = .6)
gfit <- gt_fit(gaussian, "score", gt_design("item", "rater", random = ~ item + rater),
               control = gt_control(gaussian = list(check_hessian = FALSE)))
expect(identical(stage(gfit, "approximation_assessment")$status, "passed"),
       paste("an exact balanced Gaussian likelihood is reported as exact, not unassessed; got",
             stage(gfit, "approximation_assessment")$status))
expect(identical(stage(gfit, "conditional_mode")$status, "not_assessed"),
       "an exact Gaussian fit has no conditional mode to assess")

# --- An ordinary discrete fit never claims Laplace adequacy ------------------
set.seed(4002)
discrete <- expand.grid(item = seq_len(12), rater = seq_len(3))
discrete$y <- rbinom(nrow(discrete), 1L, plogis(rnorm(12, sd = .9)[discrete$item]))
dfit <- gt_fit(discrete, "y", gt_design("item", "rater", full_cell = FALSE), gt_family("binary"))
expect(identical(stage(dfit, "approximation_assessment")$status, "not_assessed"),
       "first-order Laplace adequacy is not claimed from numerical success")

# Every stage of a real fit reports a recognized state with a reason.
for (name in names(gt_diagnostics(dfit)$stages)) {
  entry <- stage(dfit, name)
  expect(entry$status %in% c("passed", "failed", "not_assessed", "inconclusive"),
         paste("stage", name, "reports a recognized state"))
  expect(is.character(entry$reason) && nzchar(entry$reason),
         paste("stage", name, "gives a reason"))
}

# The inner tolerances survive the public control object, which does not carry
# them: reading them from user control reported nothing for an ordinary fit.
inner <- stage(dfit, "conditional_mode")$measurements
for (name in c("inner_requested_tolerance", "inner_iteration_budget", "inner_iterations",
               "inner_strict_tolerance_met", "inner_iteration_budget_exhausted"))
  expect(!is.null(inner[[name]]), paste("a public discrete fit reports", name))

# --- Acceptance is mirrored, never recomputed --------------------------------
expect(identical(stage(dfit, "numerical_acceptance")$measurements$numerically_accepted,
                 isTRUE(dfit$numerically_accepted)),
       "the acceptance stage mirrors the fit's own decision")
if (isFALSE(dfit$numerically_accepted))
  expect(any(vapply(gt_diagnostics(dfit)$stages,
                    function(s) identical(s$status, "failed"), logical(1))),
         "a rejected fit names at least one failed stage")

# --- Retention must not flatter a fit ----------------------------------------
# Dropping retained evidence can only make a stage less certain, never more
# favorable: a summary that improves when evidence is discarded is worthless.
lean <- gt_fit(discrete, "y", gt_design("item", "rater", full_cell = FALSE), gt_family("binary"),
               control = gt_control(retain = c(data = FALSE, model = FALSE)))
rank <- c(passed = 3L, inconclusive = 2L, not_assessed = 1L, failed = 0L)
for (name in names(gt_diagnostics(lean)$stages)) {
  full_status <- stage(dfit, name)$status
  lean_status <- stage(lean, name)$status
  if (identical(full_status, "failed")) next
  expect(rank[[lean_status]] <= rank[[full_status]],
         paste0("retention-reduced stage ", name, " is not more favorable: ",
                full_status, " became ", lean_status))
}

# --- Coefficient eligibility is untouched ------------------------------------
# The staged summary is presentation. It must not make a rejected fit eligible
# for reliability or D studies, which is the guarantee #7 exists to preserve.
if (isFALSE(dfit$numerically_accepted)) {
  refused <- tryCatch({ gt_reliability(dfit); "accepted" }, error = function(e) "refused")
  expect(identical(refused, "refused"),
         "a rejected fit is still refused by gt_reliability despite a staged summary")
}

# --- Printing shows the stages -----------------------------------------------
printed <- capture.output(print(gt_diagnostics(dfit)))
for (label in c("optimizer completion", "conditional mode", "independent stationarity",
                "restart/tolerance stability", "numerical acceptance",
                "approximation assessment"))
  expect(any(grepl(label, printed, fixed = TRUE)),
         paste0("print(gt_diagnostics(fit)) shows the ", label, " stage"))

cat("PASS: staged diagnostics are truthful on installed public fits.\n")
