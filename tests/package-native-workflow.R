# Installed-archive integration plus negative replay-gate checks. Never fits
# a native whole-data model during R CMD check.
library(Gtheory4LLM)
check <- function(x, label) if (!isTRUE(x)) stop(label, call. = FALSE)
e <- new.env(parent = globalenv())
source(system.file("examples", "native_1_0_workflow.R", package = "Gtheory4LLM", mustWork = TRUE), local = e)
check(is.function(e$gt_native_workflow), "Sourcing defines the workflow without running it.")
refs <- new.env(parent = baseenv())
sys.source(system.file("examples", "native_1_0_reference.R", package = "Gtheory4LLM", mustWork = TRUE), refs)
r <- refs$.gt_native_reference$models$drug_review_efficacy_safety
m <- r$platforms$mac
tol <- refs$.gt_native_reference$tolerance
compare <- function(components = m$components, reliability = m$reliability,
                    single = m$reliability_single, deviance = m$deviance, accepted = TRUE, information = FALSE)
  e$.gt_native_compare(deviance, components, reliability, single, accepted, information, r, tol)
check(all(compare()$passed), "Both historical platforms agree within the declared gates.")
check(all(compare(components = m$components[nrow(m$components):1L, ])$passed), "Component matching uses keys, not row order.")
check(!any(compare(components = m$components[-1L, ])$passed), "Missing components cannot pass.")
bad <- m$components; bad$covariance[[1L]] <- NA_real_
check(!any(compare(components = bad)$passed), "Non-finite components cannot pass.")
bad <- m$components; bad[1L, ] <- bad[2L, ]
check(!any(compare(components = bad)$passed), "Duplicate component keys cannot pass.")
bad <- m$reliability; bad$outcome[[1L]] <- "wrong-outcome"
check(!any(compare(reliability = bad)$passed), "Mismatched outcome keys cannot pass.")
check(!any(compare(deviance = NA_real_)$passed), "A missing objective cannot pass.")
bad <- m$reliability_single; bad$Phi[[1L]] <- bad$Phi[[1L]] + 0.01
check(!any(compare(single = bad)$passed), "A single-measurement reliability mismatch cannot pass.")
# A fabricated result that matches different fields from different platforms
# must fail both complete, same-origin comparisons.
artificial <- r
artificial$platforms$linux <- m
artificial$platforms$linux$deviance <- m$deviance + 10
artificial$platforms$linux$components$covariance <- m$components$covariance + 10
mixed <- e$.gt_native_compare(m$deviance, artificial$platforms$linux$components,
  m$reliability, m$reliability_single, TRUE, FALSE, artificial, tol)
check(!any(mixed$passed), "Fields cannot be mixed across reference platforms.")
check(!any(compare(accepted = FALSE)$passed), "A refused fit cannot pass numerical replay.")
check(!any(compare(information = TRUE)$passed), "Changed information availability cannot pass historical replay.")
check(!any(compare(information = NA)$passed), "Unavailable information status cannot pass historical replay.")
one_platform <- e$.gt_native_compare(m$deviance, m$components, m$reliability, m$reliability_single,
  TRUE, FALSE, artificial, tol)
check(any(one_platform$passed) && !all(one_platform$passed), "A match on only one platform is insufficient.")

# Construct native protocols without fitting: full rows, exact source/formula
# requests and probit coding remain inspectable through public APIs.
for (id in names(refs$.gt_native_reference$models)) {
  spec <- e$.gt_native_spec(id)
  check(nrow(spec$data) == 21600L && all(vapply(spec$family, function(x) x$link == "probit", logical(1))),
        "A native protocol retains every row and the probit links.")
  check(spec$control$discrete$maxit == 2000L && spec$control$discrete$gradient == "analytic" &&
        spec$control$discrete$boundary_escape == "projected" && is.null(spec$control$discrete$start),
        "The replay retains the frozen driver overrides and automatic starts.")
}

# Unsafe/incomplete replay setup produces auditable refusals before fitting.
refusal_dir <- tempfile("native-refusal-")
refused <- e$gt_native_workflow("full", refusal_dir)
check(all(refused$status$status == "refused") && all(is.na(refused$status$deviance)),
      "A missing archive refuses full fitting and retains an explicit status.")
check(file.exists(file.path(refusal_dir, "status.csv")) && file.exists(file.path(refusal_dir, "summary.txt")),
      "A refused run leaves machine-readable and readable status evidence.")
error <- tryCatch(e$gt_native_workflow("smoke", refusal_dir), error = identity)
check(inherits(error, "error") && grepl("already exists", conditionMessage(error), fixed = TRUE),
      "Previous output is never overwritten.")

set.seed(7541L); before <- .Random.seed
smoke_dir <- tempfile("native-smoke-")
smoke <- e$gt_native_workflow("smoke", smoke_dir)
check(identical(.Random.seed, before), "The synthetic generator preserves caller RNG state.")
check(identical(smoke$status$model, "synthetic_joint") && identical(smoke$status$status, "accepted") &&
        isTRUE(smoke$status$numerical_acceptance), "The installed synthetic workflow fits successfully.")
check(smoke$status$reference_comparison == "not_applicable_synthetic", "Synthetic fitting never claims native qualification.")
path <- file.path(smoke_dir, "synthetic_joint")
check(all(file.exists(file.path(path, c("components.csv", "reliability.csv", "reliability-single.csv", "dstudy.csv", "report.html", "protocol.R", "diagnostics.R", "fit.rds")))),
      "Successful fitting writes public component, coefficient, diagnostic and report outputs.")
coef <- read.csv(file.path(path, "reliability.csv"))
check(all(is.finite(coef$Erho2)) && all(is.finite(coef$Phi)), "Accepted coefficients are finite.")
check(identical(as.logical(coef$uncertainty_available), rep(smoke$status$observed_information == "available", nrow(coef))),
      "Status and coefficient uncertainty availability agree.")
unlink(c(refusal_dir, smoke_dir), recursive = TRUE)
cat("PASS: installed native workflow smoke, preserved refusals and strict reference comparison\n")
