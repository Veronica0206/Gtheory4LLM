#!/usr/bin/env Rscript
# Build the reference manual, preferring a customized cover and falling back to
# the ordinary supported route when R's generated LaTeX is not what this script
# knows how to reflow.
#
# The customized build reflows only the cover Description field; R's help-page
# and index rendering is untouched. It depends on the internal layout of the
# LaTeX that tools:::.Rd2pdf generates and on the AsIs definition in Rd.sty,
# and either can change between R versions. When it does, a plain correct
# manual is better than a failed release, so this falls back to
# `R CMD Rd2pdf` and records that it did. It never silently produces a
# different artifact than the one it reports.
#
# The overfull-box gate applies to the customized build, which owns its LaTeX
# log. The fallback checks the log only if `R CMD Rd2pdf` leaves one behind,
# and reports honestly when it could not.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L || length(args) > 2L)
  stop("Usage: Rscript scripts/build_manual.R output.pdf [build-directory]")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
# Some Rscript builds encode spaces in --file as ~+~, so an absolute invocation
# from a path containing a space resolves to a file that does not exist.
if (!file.exists(script)) script <- gsub("~+~", " ", script, fixed = TRUE)
root <- dirname(dirname(normalizePath(script, mustWork = TRUE)))
output <- normalizePath(args[1L], mustWork = FALSE)
work <- if (length(args) == 2L) args[2L] else tempfile("gtheory-manual-")
dir.create(work, recursive = TRUE, showWarnings = FALSE)
work <- normalizePath(work, mustWork = TRUE)
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)

# Resolve sibling TeX tools when pdflatex is exposed through a symlink.
pdflatex <- Sys.which("pdflatex")
if (!nzchar(pdflatex)) stop("pdflatex is required")
texbin <- dirname(normalizePath(pdflatex, mustWork = TRUE))
Sys.setenv(PATH = paste(texbin, Sys.getenv("PATH"), sep = .Platform$path.sep))
if (!nzchar(Sys.which("makeindex")))
  stop("makeindex is required; install it with your TeX distribution ",
       "(for TinyTeX: tlmgr install makeindex)")
if (!nzchar(Sys.getenv("R_PAPERSIZE"))) Sys.setenv(R_PAPERSIZE = "a4")

package <- read.dcf(file.path(root, "DESCRIPTION"))[1L, "Package"]

# Signal an unsupported generated-LaTeX layout distinctly from any other error,
# so only that specific cause selects the fallback.
unsupported <- function(message)
  stop(structure(list(message = message, call = NULL),
                 class = c("gt_manual_unsupported_layout", "error", "condition")))

customized_build <- function() {
  tex <- file.path(work, paste0(package, "-manual.tex"))
  # This is the same R generator used by R CMD Rd2pdf. Fail explicitly if R's
  # generated metadata layout changes, rather than altering function help pages.
  tools:::.Rd2pdf(pkgdir = root, outfile = tex, title = "",
                 files_or_dir = root, OSdir = "unix", silent = TRUE)
  document <- paste(readLines(tex, warn = FALSE), collapse = "\n")
  pattern <- "(?s)\\\\item\\[Description\\](.*?)(?=\\n\\\\(?:item\\[|end\\{description\\}))"
  matches <- gregexpr(pattern, document, perl = TRUE)[[1L]]
  if (length(matches) != 1L || matches[1L] < 0L)
    unsupported("Expected exactly one opening Description field in R-generated LaTeX")
  matched <- regmatches(document, regexec(pattern, document, perl = TRUE))[[1L]]
  paragraph <- gsub("[[:space:]]+", " ", matched[2L])
  # R can split one field into several AsIs fragments around DOI/URL commands.
  # Preserve those fragments and their TeX escaping. Only remove the AsIs
  # definition's verbatim newline/space and active-punctuation handling inside
  # this one field. The latter can swallow ordinary spaces after commas or
  # hyphens once verbatim spaces are disabled. Literal-special-character
  # handling is still required for %, _, &, etc.
  rd_style <- file.path(R.home("share"), "texmf", "tex", "latex", "Rd.sty")
  asis <- grep("^\\\\def\\\\AsIs\\{", readLines(rd_style, warn = FALSE), value = TRUE)
  required <- c("\\obeylines", "\\@vobeyspaces", "\\@noligs",
                "\\Rd@AsIs@dospecials", "\\Rd@AsIsX")
  if (length(asis) != 1L || !all(vapply(required, function(token)
      grepl(token, asis, fixed = TRUE), logical(1))))
    unsupported("Unsupported R AsIs rendering definition; cannot safely reflow Description")
  asis <- gsub("\\obeylines", "", asis, fixed = TRUE)
  asis <- gsub("\\@vobeyspaces", "", asis, fixed = TRUE)
  asis <- gsub("\\@noligs", "", asis, fixed = TRUE)
  replacement <- paste0(
    "\\item[Description]\\begingroup\\rightskip=0pt",
    "\\parfillskip=0pt plus 1fil\\relax\n\\makeatletter\n", asis,
    "\n\\makeatother\n", paragraph,
    "\\par\\endgroup\n")
  start <- matches[1L]
  end <- start + attr(matches, "match.length")[1L] - 1L
  document <- paste0(substr(document, 1L, start - 1L), replacement,
                     substr(document, end + 1L, nchar(document)))
  writeLines(document, tex, useBytes = TRUE)

  previous_directory <- setwd(work)
  on.exit(setwd(previous_directory), add = TRUE)
  tools::texi2pdf(tex, clean = FALSE, quiet = TRUE, texi2dvi = "emulation",
                 texinputs = file.path(R.home("share"), "texmf", "tex", "latex"))
  list(pdf = sub("\\.tex$", ".pdf", tex), log = sub("\\.tex$", ".log", tex),
       route = "customized_cover")
}

# The ordinary supported route. --no-clean keeps the build directory so the
# overfull-box gate still has a LaTeX log to read where one is produced.
fallback_build <- function() {
  pdf <- file.path(work, paste0(package, "-manual-fallback.pdf"))
  if (file.exists(pdf)) unlink(pdf)
  previous_directory <- setwd(work)
  on.exit(setwd(previous_directory), add = TRUE)
  status <- system2(file.path(R.home("bin"), "R"),
    c("CMD", "Rd2pdf", "--batch", "--no-preview", "--force", "--no-clean",
      paste0("--output=", shQuote(pdf)), shQuote(root)),
    stdout = file.path(work, "Rd2pdf.out"), stderr = file.path(work, "Rd2pdf.err"))
  if (status != 0L || !file.exists(pdf))
    stop("Fallback R CMD Rd2pdf failed; inspect ", file.path(work, "Rd2pdf.err"))
  logs <- list.files(work, pattern = "\\.log$", recursive = TRUE, full.names = TRUE)
  list(pdf = pdf, log = if (length(logs)) logs[[which.max(file.info(logs)$mtime)]] else NA_character_,
       route = "plain_Rd2pdf")
}

reason <- NA_character_
result <- withCallingHandlers(
  tryCatch(customized_build(), gt_manual_unsupported_layout = function(condition) {
    reason <<- conditionMessage(condition)
    NULL
  }), warning = function(w) invokeRestart("muffleWarning"))
if (is.null(result)) {
  message("Customized manual cover unavailable (", reason, "); using R CMD Rd2pdf.")
  result <- fallback_build()
}

boxes_checked <- FALSE
if (!is.na(result$log) && file.exists(result$log)) {
  log_lines <- readLines(result$log, warn = FALSE)
  boxes_checked <- TRUE
  if (any(grepl("Overfull \\\\", log_lines)))
    stop("Manual contains overfull boxes; inspect build log ", result$log)
}
if (!file.copy(result$pdf, output, overwrite = TRUE))
  stop("Could not copy completed manual")

summary <- list(package = package, output = output, build_directory = work,
                route = result$route, customized = identical(result$route, "customized_cover"),
                fallback_reason = reason, overfull_boxes_checked = boxes_checked,
                r_version = as.character(getRversion()))
writeLines(vapply(names(summary), function(name)
  paste0(name, ": ", if (is.na(summary[[name]])) "none" else as.character(summary[[name]])),
  character(1)))
saveRDS(summary, file.path(work, "manual-build-summary.rds"))
if (!boxes_checked)
  message("NOTE: no LaTeX log was available, so the overfull-box gate did not run. ",
          "This manual is not certified free of overfull boxes.")
cat("Manual:", output, "\nBuild files:", work, "\n")
