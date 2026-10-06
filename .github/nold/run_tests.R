# Run each installed test file of the unpacked archive against the installed
# package. Every file is run and reported before the result is decided, and
# the result is a failure if any file failed, could not be run, or none was
# found: this script is a gate, not only a report.
arguments <- commandArgs(trailingOnly = TRUE)
library_path <- arguments[[1L]]
tests_directory <- arguments[[2L]]
output_directory <- arguments[[3L]]
dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
files <- sort(list.files(tests_directory, pattern = "^package-.*[.]R$", full.names = TRUE))
if (!length(files)) stop("No package test files were found in ", tests_directory, call. = FALSE)
# This script runs in its own R process. Set the library there so every child
# inherits it: system2(env=...) does not portably set Rscript's environment on
# Windows, and a library path containing spaces must remain one value.
Sys.setenv(R_LIBS = library_path)
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
status <- vapply(files, function(file) {
  out <- suppressWarnings(system2(rscript, c("--vanilla", shQuote(file)),
    stdout = TRUE, stderr = TRUE))
  writeLines(out, file.path(output_directory, paste0(basename(file), "out")), useBytes = TRUE)
  code <- attr(out, "status")
  if (is.null(code)) code <- 0L
  if (is.na(code) || code != 0L)
    cat("\n#### FAILED:", file, "\n", paste(utils::tail(out, 40L), collapse = "\n"), "\n")
  as.integer(code)
}, integer(1))
cat("\n==== installed tests ====\n")
cat(sprintf("%-46s %s\n", basename(files), ifelse(!is.na(status) & status == 0L, "ok", "FAILED")), sep = "")
write.csv(data.frame(test = basename(files), exit_code = status),
          file.path(output_directory, "test-status.csv"), row.names = FALSE)
failed <- is.na(status) | status != 0L
cat(sum(failed), "of", length(files), "failed\n")
if (any(failed)) quit(save = "no", status = 1L, runLast = FALSE)
