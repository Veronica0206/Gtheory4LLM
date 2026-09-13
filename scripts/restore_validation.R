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

# renv is an environment-restoration tool, not a runtime model dependency. Its
# bootstrap is pinned separately so a fresh machine can use this script.
#
# Pinning a version fixes which renv is used; it does not guarantee that the
# exact file can still be retrieved, or that what arrives is what was reviewed.
# The bootstrap descriptor records the URL and the expected SHA-256, and this
# verifies the digest before installing. A cached copy is preferred over the
# network: set GTHEORY_RENV_BOOTSTRAP to a verified tarball, or let CI populate
# the cache directory, so a restore does not depend on the archive being
# reachable. When the descriptor records no digest yet, the observed digest is
# printed for the maintainer to check against the source and record.
bootstrap_descriptor <- file.path(root, "scripts", "dependency-locks", "renv-bootstrap.json")
if (!file.exists(bootstrap_descriptor)) stop("Missing renv bootstrap descriptor: ", bootstrap_descriptor)
descriptor_lines <- readLines(bootstrap_descriptor, warn = FALSE)
descriptor_value <- function(field, quoted = TRUE) {
  pattern <- if (quoted) paste0('"', field, '"\\s*:\\s*"([^"]*)"') else
    paste0('"', field, '"\\s*:\\s*([^,\\s}]+)')
  hit <- regmatches(descriptor_lines, regexec(pattern, descriptor_lines))
  hit <- Filter(function(x) length(x) == 2L, hit)
  if (!length(hit)) return(NA_character_)
  hit[[1L]][[2L]]
}
renv_version <- descriptor_value("version")
renv_url <- descriptor_value("url")
# A quoted sha256 is a recorded digest; a literal null means none is recorded
# yet, and the observed one is printed instead of being trusted silently.
renv_sha256 <- descriptor_value("sha256")
if (is.na(renv_version) || is.na(renv_url))
  stop("The renv bootstrap descriptor must record a version and a URL.")

bootstrap <- tempfile("gtheory-renv-bootstrap-")
dir.create(bootstrap)
tryCatch({
  # Prefer a file that is already here over the network, in this order: an
  # explicitly supplied tarball, a populated cache directory, then a download.
  # The digest is verified afterwards whichever path supplied the file.
  supplied <- Sys.getenv("GTHEORY_RENV_BOOTSTRAP")
  cache_directory <- Sys.getenv("GTHEORY_RENV_BOOTSTRAP_CACHE")
  tarball <- file.path(bootstrap, basename(renv_url))
  if (nzchar(supplied)) {
    if (!file.exists(supplied)) stop("GTHEORY_RENV_BOOTSTRAP does not exist: ", supplied)
    file.copy(supplied, tarball, overwrite = TRUE)
    cat("renv bootstrap source: supplied file ", supplied, "\n", sep = "")
  } else {
    cached <- if (nzchar(cache_directory)) {
      dir.create(cache_directory, recursive = TRUE, showWarnings = FALSE)
      file.path(cache_directory, basename(renv_url))
    } else NA_character_
    if (!is.na(cached) && file.exists(cached)) {
      file.copy(cached, tarball, overwrite = TRUE)
      cat("renv bootstrap source: cache ", cached, "\n", sep = "")
    } else {
      utils::download.file(renv_url, tarball, mode = "wb", quiet = TRUE)
      cat("renv bootstrap source: ", renv_url, "\n", sep = "")
      if (!is.na(cached)) file.copy(tarball, cached, overwrite = TRUE)
    }
  }
  observed <- unname(tools::sha256sum(tarball))
  if (is.na(renv_sha256)) {
    cat("renv bootstrap SHA-256 (unrecorded; verify and record it in ",
        basename(bootstrap_descriptor), "): ", observed, "\n", sep = "")
  } else if (!identical(observed, renv_sha256)) {
    stop("renv bootstrap checksum mismatch.\n  expected: ", renv_sha256,
         "\n  observed: ", observed,
         "\nRefusing to install an environment-restoration tool that is not the reviewed one.")
  } else {
    cat("renv bootstrap SHA-256 verified against the recorded digest.\n")
  }
  install.packages(tarball, repos = NULL, type = "source", lib = bootstrap, quiet = TRUE)
  .libPaths(c(bootstrap, .libPaths()))
  stopifnot(as.character(packageVersion("renv")) == renv_version)
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
