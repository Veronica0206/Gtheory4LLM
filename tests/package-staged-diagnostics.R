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

# --- A legacy record missing its governing tolerance is not flattered ---------
# A real fit records the tolerance that governed its tightened solve, so this
# condition is reached by older or externally modified objects, not by a fresh
# fit. The retained gradient of a healthy fit clears both tolerances, which
# would make a comparison on it pass whichever tolerance were read. This record
# therefore carries a gradient strictly between them: it misses the governing
# 1e-9 and meets the ordinary 1e-7, so the public verdict depends on which one
# the summary uses, and reading the looser one is visible as an improvement.
expect(!is.null(dfit$diagnostics$stability$validation_inner_tol),
       "a fresh discrete fit does record the tolerance that governed its solve")
expect(isTRUE(dfit$diagnostics$tight_final_mode),
       "the fit used for this check really did record a tight final mode")
governing <- dfit$diagnostics$stability$validation_inner_tol
ordinary <- dfit$diagnostics$stability$inner_tol
expect(governing < ordinary, "the governing tolerance is the stricter of the two")

between <- dfit
between$diagnostics$inner_gradient <- sqrt(governing * ordinary)
expect(between$diagnostics$inner_gradient > governing &&
         between$diagnostics$inner_gradient <= ordinary,
       "the probe gradient lies strictly between the two tolerances")
expect(identical(stage(between, "conditional_mode")$status, "inconclusive"),
       "a gradient that misses the governing tolerance is inconclusive on the public path")

legacy <- between
legacy$diagnostics$stability$validation_inner_tol <- NULL
expect(identical(legacy$diagnostics$inner_gradient, between$diagnostics$inner_gradient),
       "only the governing tolerance was removed; the gradient is still retained")
legacy_mode <- stage(legacy, "conditional_mode")$status
expect(!identical(legacy_mode, "passed"),
       paste0("losing the governing tolerance must not upgrade the public verdict to passed; got ",
              legacy_mode))
expect(rank[[legacy_mode]] <= rank[["inconclusive"]],
       paste0("losing the governing tolerance is not more favorable; got ", legacy_mode))
expect(is.null(stage(legacy, "conditional_mode")$measurements$inner_requested_tolerance),
       "no requested tolerance is reported when the governing value is unknown")

# The correction is presentation only: the fit's own decision and every
# eligibility gate behave exactly as they did with the field present.
expect(identical(legacy$numerically_accepted, dfit$numerically_accepted),
       "dropping diagnostic evidence does not move the acceptance decision")
expect(identical(stage(legacy, "numerical_acceptance")$status,
                 stage(dfit, "numerical_acceptance")$status),
       "the acceptance stage is unchanged by the conditional-mode correction")

# Eligibility is checked with calls that are valid for this fixture. An
# otherwise accepted binary fit is refused when the latent scale is omitted, so
# comparing generic refusal labels cannot establish that numerical-acceptance
# eligibility is preserved: the calls may fail for different reasons.
reliability_call <- function(x) gt_reliability(x, scale = "latent")
dstudy_call <- function(x) gt_dstudy(x, data.frame(rater = 2), scale = "latent")
outcome <- function(fit, f)
  tryCatch({ f(fit); "allowed" }, error = function(e) conditionMessage(e))
accepted_only <- "require a numerically converged fit"

# Accepted case: the prerequisite is asserted rather than assumed, and both
# valid calls must actually succeed on the record with and without the field.
expect(isTRUE(dfit$numerically_accepted),
       "the baseline fit for the eligibility check is numerically accepted")
for (case in list(full = between, missing_tolerance = legacy)) {
  expect(identical(outcome(case, reliability_call), "allowed"),
         "an accepted fit remains eligible for latent-scale reliability")
  expect(identical(outcome(case, dstudy_call), "allowed"),
         "an accepted fit remains eligible for a latent-scale D study")
}

# Rejected case: both calls must fail for the acceptance restriction
# specifically. A scale, panel or argument error would not demonstrate that the
# acceptance gate is what refused them.
rejected <- legacy
rejected$numerically_accepted <- FALSE
for (call in list(reliability_call, dstudy_call)) {
  message <- outcome(rejected, call)
  expect(!identical(message, "allowed"),
         "a rejected fit is refused even when its diagnostic evidence is incomplete")
  expect(grepl(accepted_only, message, fixed = TRUE),
         paste0("the refusal is the numerical-acceptance restriction, not another rule; got: ",
                message))
}

# --- Printing shows the stages -----------------------------------------------
printed <- capture.output(print(gt_diagnostics(dfit)))
for (label in c("optimizer completion", "conditional mode", "independent stationarity",
                "restart/tolerance stability", "numerical acceptance",
                "approximation assessment"))
  expect(any(grepl(label, printed, fixed = TRUE)),
         paste0("print(gt_diagnostics(fit)) shows the ", label, " stage"))

cat("PASS: staged diagnostics are truthful on installed public fits.\n")
