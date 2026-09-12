#!/usr/bin/env Rscript
# Preserve R's help-page and index rendering, reflowing only the cover Description.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L || length(args) > 2L)
  stop("Usage: Rscript scripts/build_manual.R output.pdf [build-directory]")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1L])
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
if (!nzchar(Sys.which("makeindex"))) stop("makeindex is required")
if (!nzchar(Sys.getenv("R_PAPERSIZE"))) Sys.setenv(R_PAPERSIZE = "a4")

package <- read.dcf(file.path(root, "DESCRIPTION"))[1L, "Package"]
tex <- file.path(work, paste0(package, "-manual.tex"))
# This is the same R generator used by R CMD Rd2pdf. Fail explicitly if R's
# generated metadata layout changes, rather than altering function help pages.
tools:::.Rd2pdf(pkgdir = root, outfile = tex, title = "",
               files_or_dir = root, OSdir = "unix", silent = TRUE)
document <- paste(readLines(tex, warn = FALSE), collapse = "\n")
pattern <- "(?s)\\\\item\\[Description\\](.*?)(?=\\n\\\\(?:item\\[|end\\{description\\}))"
matches <- gregexpr(pattern, document, perl = TRUE)[[1L]]
if (length(matches) != 1L || matches[1L] < 0L)
  stop("Expected exactly one opening Description field in R-generated LaTeX")
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
  stop("Unsupported R AsIs rendering definition; cannot safely reflow Description")
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
tools::texi2pdf(tex, clean = FALSE, quiet = TRUE, texi2dvi = "emulation",
               texinputs = file.path(R.home("share"), "texmf", "tex", "latex"))
setwd(previous_directory)
pdf <- sub("\\.tex$", ".pdf", tex)
log <- readLines(sub("\\.tex$", ".log", tex), warn = FALSE)
if (any(grepl("Overfull \\\\", log))) stop("Manual contains overfull boxes; inspect build log")
if (!file.copy(pdf, output, overwrite = TRUE)) stop("Could not copy completed manual")
cat("Manual:", output, "\nBuild files:", work, "\n")
