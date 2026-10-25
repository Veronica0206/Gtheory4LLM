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
                    single = m$reliability_single, deviance = m$deviance, accepted = TRUE)
  e$.gt_native_compare(deviance, components, reliability, single, accepted, r, tol)
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
  m$reliability, m$reliability_single, TRUE, artificial, tol)
check(!any(mixed$passed), "Fields cannot be mixed across reference platforms.")
check(!any(compare(accepted = FALSE)$passed), "A refused fit cannot pass numerical replay.")
one_platform <- e$.gt_native_compare(m$deviance, m$components, m$reliability, m$reliability_single,
  TRUE, artificial, tol)
check(any(one_platform$passed) && !all(one_platform$passed), "A match on only one platform is insufficient.")
missing_platform <- r; missing_platform$platforms$linux <- NULL
missing_error <- tryCatch(e$.gt_native_compare(m$deviance, m$components, m$reliability,
  m$reliability_single, TRUE, missing_platform, tol), error = identity)
check(inherits(missing_error, "error"), "An incomplete platform reference set cannot pass vacuously.")

# The new conditional-information contract is a separate reference, not a
# rewrite of the historical unavailable-information point-fit record.
with_intervals <- function(point, intervals) {
  x <- merge(point, intervals, by = "outcome")
  for (flag in c("uncertainty_available", "uncertainty_conditional", "Erho2_interval_available", "Phi_interval_available")) x[[flag]] <- TRUE
  x
}
rel <- with_intervals(m$reliability, r$conditional$reliability)
one <- with_intervals(m$reliability_single, r$conditional$reliability_single)
u <- r$conditional[c("available", "conditional", "fixed_components")]
conditional <- function(uncertainty = u, full = rel, single = one)
  e$.gt_native_uncertainty_compare(uncertainty, full, single, r, tol)
check(isTRUE(conditional()$passed), "Saved conditional contract and intervals pass independently of old point-fit information.")
bad <- u; bad$available <- FALSE
check(!conditional(bad)$passed, "Unavailable current information cannot satisfy the conditional contract.")
bad <- u; bad$conditional <- FALSE
check(!conditional(bad)$passed, "Unconditional information cannot masquerade as conditional information.")
bad <- u; bad$fixed_components <- bad$fixed_components[-1L]
check(!conditional(bad)$passed, "Missing held sources cannot pass.")
bad <- rel; bad$Erho2_lower[[1L]] <- NA_real_
check(!conditional(full = bad)$passed, "Non-finite conditional intervals cannot pass.")
bad <- rel; bad$uncertainty_conditional[[1L]] <- FALSE
check(!conditional(full = bad)$passed, "Coefficient conditioning metadata must match the report.")
bad <- rel; bad$Erho2_se[[1L]] <- bad$Erho2_se[[1L]] + 0.01
check(!conditional(full = bad)$passed, "Interval arithmetic outside the prospective tolerance cannot pass.")

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
