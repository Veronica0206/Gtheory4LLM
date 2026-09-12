# Restore exact validation dependencies without activating a project .Rprofile.
# Usage: Rscript --vanilla scripts/restore_validation.R /path/to/empty/library
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% 1:2) stop("Supply the destination R library and optionally a lockfile path.")
script_argument <- grep("^--file=", commandArgs(), value = TRUE)
script <- sub("^--file=", "", script_argument[[1L]])
if (!file.exists(script)) script <- gsub("~+~", " ", script, fixed=TRUE)
root <- dirname(dirname(normalizePath(script)))
library_path <- path.expand(args[[1L]])
dir.create(library_path, recursive = TRUE, showWarnings = FALSE)
library_path <- normalizePath(library_path)
lockfile <- if (length(args) == 2L) normalizePath(args[2L], mustWork=TRUE) else file.path(root, "renv.lock")

# renv is an environment-restoration tool, not a runtime model dependency.
# Pin its bootstrap separately so a fresh machine can use this script directly.
bootstrap <- tempfile("gtheory-renv-bootstrap-")
dir.create(bootstrap)
tryCatch({
  install.packages("https://cran.r-project.org/src/contrib/Archive/renv/renv_1.1.5.tar.gz",
                   repos = NULL, type = "source", lib = bootstrap, quiet = TRUE)
  .libPaths(c(bootstrap, .libPaths()))
  stopifnot(as.character(packageVersion("renv")) == "1.1.5")
  expected_r <- renv::lockfile_read(lockfile)$R$Version
  if (as.character(getRversion()) != expected_r)
    stop("Selected validation lock requires R ", expected_r, "; current R is ", getRversion())
  # Prebuilt Linux OpenMx/RcppParallel binaries can carry different TBB ABIs
  # despite matching package versions. Build the locked stack consistently.
  if (identical(Sys.info()[["sysname"]], "Linux")) {
    cran <- "https://cloud.r-project.org"
    options(pkgType = "source", repos = c(CRAN = cran),
            renv.config.repos.override = cran)
    # setup-r can inject an explicit binary repository override. Disabling
    # automatic PPM URL conversion alone does not override that repository.
    Sys.setenv(RENV_CONFIG_PPM_ENABLED = "FALSE",
               RENV_CONFIG_REPOS_OVERRIDE = cran)
    cat("Linux restore repository: ", cran, " (source packages)\n", sep = "")
  }
  renv::restore(project = root, library = library_path,
                lockfile = lockfile, prompt = FALSE)
  cat("Restored validation library: ", library_path, "\n", sep = "")
}, finally = unlink(bootstrap, recursive = TRUE))
