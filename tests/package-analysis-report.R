# Installed-package checks for portable, aggregate-only analysis snapshots.
library(Gtheory4LLM)
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
expect_error <- function(expr, pattern, label) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  expect(inherits(error, "error") && grepl(pattern, conditionMessage(error)), label)
}
contains <- function(object, sentinel)
  length(grepRaw(charToRaw(sentinel), serialize(object, NULL), fixed = TRUE)) > 0L

set.seed(207)
d <- expand.grid(item = paste0("PRIVATE_PARTICIPANT_", 1:24), rater = 1:4)
outcome <- "<script>alert(1)</script> & a deliberately long outcome label for report layout"
d[[outcome]] <- rnorm(24)[match(d$item, unique(d$item))] + rnorm(4, sd = .5)[d$rater] +
  rnorm(nrow(d), sd = .7)
d$unused <- "PRIVATE_UNUSED_COLUMN"
design <- gt_design("item", "rater", random = ~ item + rater)
# do.call records the literal data frame in the fit call; the report must not.
fit <- do.call(gt_fit, list(data = d, outcomes = outcome, design = design,
                            control = gt_control(gaussian = list(retry_seed = 42))))
preflight <- do.call(gt_preflight, list(data = d, outcomes = outcome, design = design))
rel <- gt_reliability(fit)
study <- gt_dstudy(fit, data.frame(rater = c(2L, 4L, 6L)))
fit$diagnostics$optimizer_message <- "PRIVATE_DIAGNOSTIC_TEXT"
fit$control$gaussian$arbitrary_note <- "PRIVATE_CONTROL_TEXT"
fit$session$otherPkgs$Gtheory4LLM$Version <- "0.0.0-recorded-session"
fit$session$otherPkgs$Gtheory4LLM$LibPath <- "/PRIVATE_LIBRARY_PATH"
report <- gt_report(fit, preflight, rel, study)
expect(inherits(report, "gt_report") && identical(report$schema_version, "1.0"),
       "the snapshot has an explicit serialization schema")
for (sentinel in c("PRIVATE_PARTICIPANT_", "PRIVATE_UNUSED_COLUMN", "PRIVATE_DIAGNOSTIC_TEXT",
                   "PRIVATE_CONTROL_TEXT", "PRIVATE_LIBRARY_PATH"))
  expect(!contains(report, sentinel), paste("snapshot omits", sentinel))
expect(any(report$provenance$fitting_session$packages$version == "0.0.0-recorded-session", na.rm = TRUE),
       "fitting-session versions come from the retained session")
expect(!any(report$provenance$report_runtime$packages$version == "0.0.0-recorded-session", na.rm = TRUE),
       "report runtime is recorded independently")
expect(grepl("cannot establish", report$preflight$association),
       "aggregate preflight correspondence is not claimed as data identity")
expect(nrow(report$dstudy) == nrow(study$results), "all D-study rows survive the snapshot")

# ReadRDS/export needs no fitting functions or model object.
directory <- tempfile("gtheory-report-")
dir.create(directory)
rds <- file.path(directory, "snapshot.rds")
saveRDS(report, rds)
loaded <- readRDS(rds)
expect(identical(report, loaded), "RDS preserves the versioned snapshot exactly")
file <- file.path(directory, "analysis.html")
gt_export_report(loaded, file)
html <- paste(readLines(file, warn = FALSE), collapse = "\n")
expect(grepl("<svg", html, fixed = TRUE) && grepl("<table", html, fixed = TRUE),
       "the standalone HTML contains inline figures and tables")
expect(!grepl("<script", html, ignore.case = TRUE) &&
         grepl("&lt;script&gt;alert(1)&lt;/script&gt;", html, fixed = TRUE),
       "user labels are escaped, never executable HTML")
expect(!grepl("src=|<link|<iframe", html), "the report loads no remote or sidecar assets")
for (sentinel in c("PRIVATE_PARTICIPANT_", "PRIVATE_UNUSED_COLUMN", "PRIVATE_DIAGNOSTIC_TEXT",
                   "PRIVATE_CONTROL_TEXT", "PRIVATE_LIBRARY_PATH"))
  expect(!grepl(sentinel, html, fixed = TRUE), paste("HTML omits", sentinel))
before <- readBin(file, "raw", n = file.info(file)$size)
expect_error(gt_export_report(report, file), "already exists", "existing reports are protected")
expect(identical(before, readBin(file, "raw", n = file.info(file)$size)),
       "a refused overwrite leaves the original file intact")
gt_export_report(report, file, overwrite = TRUE)
bad_schema <- report
bad_schema$schema_version <- "999"
expect_error(gt_export_report(bad_schema, file, overwrite = TRUE), "schema_version",
             "unknown schemas are refused")
expect_error(gt_export_report(report, file.path(directory, "result.txt")), "html",
             "the destination explicitly identifies HTML")

# Modified or unrelated coefficients cannot be associated with this fit.
wrong <- rel
wrong$per_trait$Phi <- wrong$per_trait$Phi / 2
expect_error(gt_report(fit, reliability = wrong), "does not agree", "edited estimates are refused")
wrong <- rel
wrong$uncertainty$restricted_to_interior <- !isTRUE(wrong$uncertainty$restricted_to_interior)
expect_error(gt_report(fit, reliability = wrong), "does not agree", "uncertainty settings are verified")
wrong_preflight <- gt_preflight(d, outcome, gt_design("item", "rater", random = ~ item))
expect_error(gt_report(fit, preflight = wrong_preflight), "does not match", "different source models are refused")
joint_data <- d
joint_data$second <- rnorm(nrow(d)) + rnorm(24)[match(d$item, unique(d$item))]
joint_fit <- gt_fit(joint_data, c(outcome, "second"), design,
  covariance = "diagonal", residual = "diagonal",
  control = gt_control(gaussian = list(check_hessian = FALSE)))
wrong_covariance <- gt_preflight(joint_data, c(outcome, "second"), design,
  covariance = "unstructured", residual = "unstructured")
expect_error(gt_report(joint_fit, preflight = wrong_covariance), "does not match",
             "preflight covariance parameter counts must agree with the fitted model")
shuffled <- study
shuffled$results <- shuffled$results[3:1, ]
expect(nrow(gt_report(fit, dstudy = shuffled)$dstudy) == 3L,
       "legitimate result-row reordering preserves compatibility")
lean <- fit
lean$data <- lean$model <- lean$backend_fit <- lean$session <- NULL
lean$retained[c("data", "model", "session")] <- FALSE
lean_report <- gt_report(lean, reliability = rel, dstudy = study)
expect(!lean_report$provenance$fitting_session$available &&
         all(is.na(lean_report$provenance$fitting_session$packages$version)),
       "missing retained session metadata remains unknown")
legacy <- fit
legacy$session <- legacy$retained <- NULL
expect(all(is.na(gt_report(legacy)$retention$retained)), "missing legacy retention flags stay unknown")
rejected <- fit
rejected$numerically_accepted <- FALSE
expect(isFALSE(gt_report(rejected)$analysis$numerically_accepted), "rejected fits can be documented honestly")
expect_error(gt_report(rejected, reliability = rel), "numerically converged",
             "report generation never authorizes rejected-fit coefficients")

# Ordinal category labels may be identifying. Only stable category aliases and
# aggregate coverage counts enter the portable report, never those labels.
ordinal_data <- expand.grid(item = paste0("PRIVATE_ORDINAL_ID_", 1:8), rater = 1:3)
ordinal_data$grade <- ordered(rep(c("PRIVATE_LOW", "PRIVATE_MIDDLE", "PRIVATE_HIGH"), 8L),
  levels = c("PRIVATE_LOW", "PRIVATE_MIDDLE", "PRIVATE_HIGH"))
ordinal_design <- gt_design("item", "rater", random = ~ item + rater, full_cell = FALSE)
ordinal_fit <- gt_fit(ordinal_data, "grade", ordinal_design, gt_family("ordinal"),
  control = gt_control(discrete = list(optimizer = "nlminb",
    fixed_covariance = list(item = matrix(0), rater = matrix(0)))))
ordinal_preflight <- gt_preflight(ordinal_data, "grade", ordinal_design, gt_family("ordinal"),
  control = gt_control(discrete = list(fixed_covariance = list(item = matrix(0), rater = matrix(0)))))
ordinal_report <- gt_report(ordinal_fit, ordinal_preflight,
  gt_reliability(ordinal_fit, scale = "latent"))
expect(!contains(ordinal_report, "PRIVATE_"), "category aliases and aggregate profiles omit original identifiers")
expect(identical(ordinal_report$preflight$category_counts[[1L]]$category,
                 c("category_1", "category_2", "category_3")), "category aliases preserve declared order")
expect(ordinal_report$provenance$fitting_session$available,
       "new discrete fits record their fitting session")
expect(all(ordinal_report$source_variances$covariance_fixed),
       "user-fixed discrete covariance components are distinguished from estimates")
ordinal_html <- file.path(directory, "ordinal.html")
gt_export_report(ordinal_report, ordinal_html)
expect(any(grepl("Aliased category coverage", readLines(ordinal_html), fixed = TRUE)),
       "portable ordinal reports include an aggregate coverage heatmap")
lean_ordinal <- gt_fit(ordinal_data, "grade", ordinal_design, gt_family("ordinal"),
  control = gt_control(retain = list(session = FALSE),
    discrete = list(optimizer = "nlminb", fixed_covariance = list(item = matrix(0), rater = matrix(0)))))
expect(!gt_report(lean_ordinal)$provenance$fitting_session$available,
       "explicit session retention removal is respected for discrete fits")
huge <- report$dstudy[1L, ]
huge$measurements_per_object <- 1e307
svg <- getFromNamespace(".gt_report_svg", "Gtheory4LLM")(huge, study = TRUE)
expect(grepl("<circle", svg, fixed = TRUE) && !grepl("[xy]='Inf'", svg),
       "finite huge allocations use finite SVG coordinates without intermediate overflow")
unlink(directory, recursive = TRUE)
cat("PASS: portable reports preserve aggregate results, privacy, association checks, provenance and overwrite protection.\n")
