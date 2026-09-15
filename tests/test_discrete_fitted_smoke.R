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

# --- The study is frozen, not merely self-consistent ---------------------------
# Without these, cases.R, panels.csv and dense-baseline.csv could be edited
# together into a new mutually consistent state and every other assertion in
# this file would still pass. Deleting the hardest case from the definitions
# and from the baseline would be invisible. The contract has to be pinned from
# outside the files it governs, so the digests and the case list live here.
#
# Changing any of them is then a deliberate, reviewable edit to this test
# rather than a quiet edit to a data file. Implementations move to satisfy the
# oracle; the oracle does not move to satisfy an implementation.
#
# Production sources are deliberately NOT pinned. They must be free to change
# when the sparse fitted backend is written; the study is what must not.
FROZEN_DIGESTS <- c(
  "cases.R" = "b3052dc58b916704a51b65d104727202",
  "panels.csv" = "68dd08af3937bac4561c6ee5d50c89c4",
  "dense-baseline.csv" = "4fc37d45f53bc50d9c88d31efdf9f2e8",
  "freeze-panels.R" = "867cb1a25b9a41f3df3fed90f57ea9c4")

FROZEN_CASES <- c(
  "fit_binary_logit_single_source", "fit_binary_probit_crossed",
  "fit_binary_logit_zero_source", "fit_ordinal_logit_crossed",
  "fit_ordinal_probit_crossed", "fit_ordinal_logit_tail_mass",
  "fit_binary_probit_fixed_covariance", "refuse_truncated_inner_solve",
  "reject_truncated_outer_optimizer", "reject_zero_restart_budget")

# Git checks text files out with CRLF on Windows, so raw bytes would only
# reproduce on the platform that wrote them.
content_digest <- function(path) {
  normalized <- tempfile("gt-smoke-")
  on.exit(unlink(normalized), add = TRUE)
  connection <- file(normalized, "wb")
  tryCatch(writeBin(charToRaw(paste0(paste(readLines(path, warn = FALSE), collapse = "\n"), "\n")),
                    connection), finally = close(connection))
  unname(tools::md5sum(normalized))
}
for (name in names(FROZEN_DIGESTS))
  expect(identical(content_digest(file.path(smoke_dir, name)), unname(FROZEN_DIGESTS[[name]])),
         paste0(name, " has moved since the contract was frozen. If that is intended, ",
                "the new digest belongs in this test as a reviewed change, not as a ",
                "silent edit to the study."))

observed_cases <- vapply(cases, `[[`, character(1), "key")
expect(identical(sort(observed_cases), sort(FROZEN_CASES)),
       paste0("exactly the frozen ten cases are defined; found ",
              paste(sort(setdiff(observed_cases, FROZEN_CASES)), collapse = ","), " extra and ",
              paste(sort(setdiff(FROZEN_CASES, observed_cases)), collapse = ","), " missing"))
expect(!anyDuplicated(observed_cases), "no case key is defined twice")

frozen <- read.csv(file.path(smoke_dir, "dense-baseline.csv"), stringsAsFactors = FALSE,
                   colClasses = "character")
contract <- frozen[frozen$kind == "class", , drop = FALSE]
expect(nrow(contract) > 0L, "the dense baseline records a class contract")

classify_refusal <- function(message) {
  if (grepl("inner mode", message, fixed = TRUE) &&
      grepl("starting values", message, fixed = TRUE))
    return("conditional_mode_unavailable_at_start")
  if (grepl("dimension|do not match|Invalid|invalid|malformed", message))
    return("malformed_internal_input")
  "other_refusal"
}

observed_for <- function(cs) {
  fit <- tryCatch(.gt_fit_discrete(cs$data, cs$outcomes, cs$design, cs$families,
                                   covariance = cs$covariance, control = cs$control),
                  error = function(e) structure(list(message = conditionMessage(e)),
                                                class = "gt_smoke_refusal"))
  # A refusal carries its mechanism. Comparing only the disposition would let a
  # backend refuse for an entirely unrelated reason and still satisfy Layer 3.
  if (inherits(fit, "gt_smoke_refusal"))
    return(list(disposition = "refused", panel = cs$panel,
                rows = as.character(nrow(cs$data)),
                refusal_class = classify_refusal(fit$message)))
  failures <- sort(unique(fit$diagnostics$acceptance_failures))
  zeros <- sort(unique(as.character(fit$diagnostics$zero_variance_parameters)))
  list(disposition = if (isTRUE(fit$numerically_accepted)) "accepted" else "rejected",
       panel = cs$panel, rows = as.character(nrow(cs$data)),
       acceptance_failures = if (length(failures)) paste(failures, collapse = "|") else "",
       zero_variance_parameters = if (length(zeros)) paste(zeros, collapse = "|") else "",
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

# The class each negative declares in cases.R must be the class the baseline
# froze. Two places state it, and they must not be allowed to disagree.
for (neg in negatives) {
  frozen_class <- contract$value[contract$case == neg$key & contract$quantity ==
    if (identical(neg$disposition, "refused")) "refusal_class" else "acceptance_failures"]
  expect(length(frozen_class) == 1L, paste0(neg$key, " froze exactly one class field"))
  if (identical(neg$disposition, "refused"))
    expect(identical(neg$class, frozen_class),
           paste0(neg$key, " declares class ", neg$class, " and the baseline froze ",
                  frozen_class))
  else
    expect(grepl(neg$class, frozen_class, fixed = TRUE),
           paste0(neg$key, " declares class ", neg$class,
                  " which is absent from the frozen failure set ", frozen_class))
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
