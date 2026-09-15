# Run from the project directory with Rscript tests/test_discrete_fitted_smoke.R.
#
# Exercises the frozen fitted smoke matrix on the dense backend and requires
# every case to reproduce the class entries recorded in dense-baseline.csv.
#
# This runs before any sparse fitted backend exists, and that is the point. The
# contract is only worth freezing if it is known to hold on every supported
# platform; a contract that silently fails on Windows would otherwise be
# discovered when a sparse backend was blamed for it.
#
# Only class entries are compared. Provenance entries are fitted coordinates
# recorded on one machine on one day, and requiring other platforms to
# reproduce them would assert exactly what the layered tolerances exist to
# avoid asserting: a fit is reached by an optimizer taking finite-difference
# gradients, so two runs can follow different paths to the same optimum.
source(file.path("validation-studies", "discrete-sparse-fitted-smoke", "cases.R"))

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
frozen <- read.csv(file.path(smoke_dir, "dense-baseline.csv"), stringsAsFactors = FALSE,
                   colClasses = "character")
contract <- frozen[frozen$kind == "class", , drop = FALSE]
expect(nrow(contract) > 0L, "the dense baseline records a class contract")

observed_for <- function(cs) {
  fit <- tryCatch(.gt_fit_discrete(cs$data, cs$outcomes, cs$design, cs$families,
                                   covariance = cs$covariance, control = cs$control),
                  error = function(e) structure(list(message = conditionMessage(e)),
                                                class = "gt_smoke_refusal"))
  if (inherits(fit, "gt_smoke_refusal"))
    return(list(disposition = "refused", panel = cs$panel,
                rows = as.character(nrow(cs$data))))
  failures <- fit$diagnostics$acceptance_failures
  list(disposition = if (isTRUE(fit$numerically_accepted)) "accepted" else "rejected",
       panel = cs$panel, rows = as.character(nrow(cs$data)),
       acceptance_failures = if (length(failures)) paste(failures, collapse = "|") else "",
       optimizer_completed = as.character(isTRUE(fit$optimizer_completed)),
       numerically_accepted = as.character(isTRUE(fit$numerically_accepted)),
       inner_converged = as.character(isTRUE(fit$diagnostics$inner_converged)),
       tight_final_mode = as.character(isTRUE(fit$diagnostics$tight_final_mode)))
}

for (cs in cases) {
  label <- paste0("case ", cs$key)
  wanted <- contract[contract$case == cs$key, , drop = FALSE]
  expect(nrow(wanted) > 0L, paste(label, "has a frozen class contract"))
  got <- observed_for(cs)

  # The declared disposition is checked against the case definition as well as
  # against the recorded baseline, so a baseline edited to match a regression
  # still fails here.
  expect(identical(got$disposition, cs$disposition),
         paste0(label, " was declared ", cs$disposition, " and produced ", got$disposition))

  for (i in seq_len(nrow(wanted))) {
    quantity <- wanted$quantity[[i]]
    expect(quantity %in% names(got),
           paste0(label, " records no ", quantity, " to compare with the baseline"))
    expect(identical(got[[quantity]], wanted$value[[i]]),
           paste0(label, " ", quantity, ": frozen ", wanted$value[[i]],
                  ", observed ", got[[quantity]]))
  }
}

# The negative controls must reuse an accepted panel literally, not merely a
# panel generated the same way. If that stops being true the controls no longer
# isolate the control they change.
for (neg in negatives) {
  from <- Filter(function(a) identical(a$key, neg$source), accepted)[[1L]]
  expect(identical(neg$data, from$data),
         paste0("negative control ", neg$key, " reuses the ", neg$source, " panel exactly"))
  expect(!identical(neg$control, from$control),
         paste0("negative control ", neg$key, " changes a control"))
}

# The panels are loaded, not regenerated. A study that regenerated them would
# compare two backends on two datasets on some platforms.
smoke_source <- readLines(file.path(smoke_dir, "cases.R"), warn = FALSE)
code <- grep("^\\s*#", smoke_source, value = TRUE, invert = TRUE)
for (banned in c("rnorm(", "rbinom(", "rlogis(", "set.seed("))
  expect(!any(grepl(banned, code, fixed = TRUE)),
         paste0("the case definitions never call ", banned, "; panels.csv is authoritative"))

cat("PASS: all ", length(cases), " fitted smoke cases reproduce their frozen dense contract.\n",
    sep = "")
