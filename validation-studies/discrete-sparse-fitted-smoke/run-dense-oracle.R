# Record the dense baseline for the fitted smoke matrix.
#
# What this freezes, and what it deliberately does not.
#
# Frozen as a cross-platform contract: the panels, the case definitions, the
# controls, the declared disposition of each case, and the declared stage or
# reason class of each negative control. A future run on any platform must
# reproduce those.
#
# NOT frozen as a cross-platform contract: the fitted coordinates below. They
# are provenance and review material, recorded from one machine on one day. A
# fit is reached by an optimizer taking finite-difference gradients, and a
# 1e-15 difference in the objective perturbs an FD gradient by roughly 1e-15/h
# with h ~ 1e-8, so two backends can follow measurably different paths to the
# same optimum. Requiring future platforms to reproduce these coordinates would
# assert exactly the thing the layered tolerances exist to avoid asserting.
#
# The sparse qualification therefore compares a dense fit and a sparse fit
# produced together in the same run, not a sparse fit against these numbers.
source(file.path("validation-studies", "discrete-sparse-fitted-smoke", "cases.R"))

out_dir <- smoke_dir
rows <- list()
record <- function(...) rows[[length(rows) + 1L]] <<-
  data.frame(..., stringsAsFactors = FALSE)

# Git checks text files out with CRLF on Windows, so hashing raw bytes would
# record a digest that only reproduces on the platform that wrote it.
content_digest <- function(path) {
  normalized <- tempfile("gt-smoke-")
  on.exit(unlink(normalized), add = TRUE)
  connection <- file(normalized, "wb")
  tryCatch(writeBin(charToRaw(paste0(paste(readLines(path, warn = FALSE), collapse = "\n"), "\n")),
                    connection), finally = close(connection))
  unname(tools::md5sum(normalized))
}

for (cs in cases) {
  started <- Sys.time()
  fit <- tryCatch(.gt_fit_discrete(cs$data, cs$outcomes, cs$design, cs$families,
                                   covariance = cs$covariance, control = cs$control),
                  error = function(e) structure(list(message = conditionMessage(e)),
                                                class = "gt_smoke_refusal"))
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  refused <- inherits(fit, "gt_smoke_refusal")
  observed <- if (refused) "refused" else
    if (isTRUE(fit$numerically_accepted)) "accepted" else "rejected"
  if (!identical(observed, cs$disposition))
    stop("case ", cs$key, " was declared ", cs$disposition, " and dense produced ",
         observed, ". The test design must be corrected before any sparse work, ",
         "and the correction recorded.")

  record(case = cs$key, quantity = "disposition", value = observed, kind = "class")
  record(case = cs$key, quantity = "panel", value = cs$panel, kind = "class")
  record(case = cs$key, quantity = "rows", value = as.character(nrow(cs$data)), kind = "class")
  if (refused) {
    record(case = cs$key, quantity = "refusal_message", value = fit$message, kind = "provenance")
    next
  }
  failures <- fit$diagnostics$acceptance_failures
  record(case = cs$key, quantity = "acceptance_failures",
         value = if (length(failures)) paste(failures, collapse = "|") else "", kind = "class")
  for (stage in c("optimizer_completed", "numerically_accepted"))
    record(case = cs$key, quantity = stage, value = as.character(isTRUE(fit[[stage]])), kind = "class")
  for (stage in c("inner_converged", "tight_final_mode"))
    record(case = cs$key, quantity = stage,
           value = as.character(isTRUE(fit$diagnostics[[stage]])), kind = "class")
  # Provenance below this line.
  record(case = cs$key, quantity = "minus2loglik",
         value = format(fit$minus2loglik, digits = 17), kind = "provenance")
  for (i in seq_along(fit$parameters))
    record(case = cs$key, quantity = paste0("parameter_", names(fit$parameters)[[i]]),
           value = format(fit$parameters[[i]], digits = 17), kind = "provenance")
  for (source_name in names(fit$covariance_components)) {
    S <- fit$covariance_components[[source_name]]
    for (i in seq_along(S))
      record(case = cs$key, quantity = paste0("covariance_", source_name, "_", i),
             value = format(S[[i]], digits = 17), kind = "provenance")
  }
  record(case = cs$key, quantity = "elapsed_seconds",
         value = format(round(elapsed, 3)), kind = "provenance")
}

baseline <- do.call(rbind, rows)
write.csv(baseline, file.path(out_dir, "dense-baseline.csv"), row.names = FALSE)

sources <- c("R/design.R", "R/family.R", "R/discrete_response.R", "R/discrete_dense.R",
             "R/discrete_mode.R", "R/discrete.R",
             file.path(out_dir, "cases.R"), file.path(out_dir, "freeze-panels.R"),
             file.path(out_dir, "panels.csv"))
write.csv(data.frame(file = sources, md5 = vapply(sources, content_digest, character(1)),
                     stringsAsFactors = FALSE),
          file.path(out_dir, "source-hashes.csv"), row.names = FALSE)

cat("dense oracle recorded:", nrow(baseline), "entries across", length(cases), "cases\n")
cat("panels.csv digest:", content_digest(file.path(out_dir, "panels.csv")), "\n")
cat("R version:", R.version.string, "\n")
