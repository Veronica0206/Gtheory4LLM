# Run from the project directory with Rscript tests/test_discrete_attempt_names.R.
#
# Every discrete optimization attempt keeps the prepared parameter names: the
# primary attempt, the alternative starts (whose clipped start used to take
# the unnamed bounds' names, that is none), their tightened refinements and
# the selected solution. The documented warm-start interface requires a
# uniquely named vector, so a selected alternative solution must be accepted
# by it. The alternative attempts run on every fit, so their names are
# checked on every fixture whether or not the alternative is selected; the
# warm-start refit is exercised on the first fixture whose alternative wins.
source("load_functions.R")
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)

design <- gt_design("item", "rater", full_cell = FALSE)
family <- gt_family("binary", "logit")
alternative_selected <- FALSE
fixtures <- 0L
for (seed in 1:40) {
  set.seed(seed)
  d <- expand.grid(item = 1:8, rater = 1:3)
  d$y <- as.integer(rnorm(8, sd = 1.2)[d$item] + rnorm(nrow(d)) > 0)
  if (length(unique(d$y)) < 2L) next
  fit <- tryCatch(suppressWarnings(gt_fit(d, "y", design, family = family)), error = function(e) NULL)
  if (is.null(fit)) next
  fixtures <- fixtures + 1L
  expected <- names(fit$starting_parameters)
  expect(!is.null(expected) && !anyDuplicated(expected), paste("seed", seed, "has named starting parameters"))
  for (attempt in fit$diagnostics$attempts)
    expect(identical(names(attempt$parameters), expected) && identical(names(attempt$start), expected),
           paste("seed", seed, "attempt", attempt$label, "keeps the parameter names on its start and its solution"))
  expect(identical(names(fit$parameters), expected),
         paste("seed", seed, "selected attempt", gt_diagnostics(fit)$selected_attempt, "keeps the parameter names"))
  if (!alternative_selected && grepl("^alternative", gt_diagnostics(fit)$selected_attempt)) {
    alternative_selected <- TRUE
    refit <- suppressWarnings(gt_fit(d, "y", design, family = family,
      control = gt_control(discrete = list(start = fit$parameters))))
    expect(inherits(refit, "gt_fit") && identical(names(refit$starting_parameters), expected),
           "a warm-start refit from a selected alternative solution is accepted in the same named coordinates")
  }
}
expect(fixtures >= 10L, "enough fixtures fitted to exercise the alternative attempts")
if (!alternative_selected)
  cat("NOTE: no fixture selected an alternative attempt on this platform; names were still checked on every alternative attempt.\n")
cat("PASS: every discrete attempt and the selected solution keep their parameter names",
    if (alternative_selected) "including a selected alternative, from which a warm-start refit is accepted" else "", "\n")
