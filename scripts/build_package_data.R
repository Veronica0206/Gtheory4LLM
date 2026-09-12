# Verify bundled public annotation resources, or rebuild from explicitly supplied
# copies of the three source CSVs from https://doi.org/10.17605/OSF.IO/K9CAJ.
# Default and --verify-only are read-only and require no external data/network.
# Rebuild: Rscript --vanilla scripts/build_package_data.R --source-directory PATH
arguments <- commandArgs(trailingOnly = TRUE)
verify_only <- !length(arguments) || identical(arguments, "--verify-only")
if (!verify_only && !(length(arguments) == 2L && arguments[1L] == "--source-directory"))
  stop("Use --verify-only or --source-directory PATH.")
source("load_functions.R")
destination <- file.path("inst", "extdata")
source_directory <- if (verify_only) NULL else normalizePath(arguments[2L], mustWork = TRUE)
source_files <- c(hate_speech = "hate_labeling_final.csv",
  mental_health = "mh_labeling_final.csv", drug_review = "drug_labeling_final.csv")
source_md5 <- c(hate_speech = "ce3b4c82acaf957c183adcab192013e6",
  mental_health = "93824779124843e34c426c8988dd629e",
  drug_review = "b5ca9480feb284c5a71971cd4b33a6a9")
source_urls <- c(hate_speech = "https://osf.io/download/69e524194f19c8ae52affcfd/",
  mental_health = "https://osf.io/download/69e5242881add1ab75fd88e6/",
  drug_review = "https://osf.io/download/63zr5/")
allowed_design <- c("item", "evaluator", "prompt", "temp", "seed")
design_counts <- c(item = 100L, evaluator = 4L, prompt = 3L, temp = 6L, seed = 3L)
contains_environment <- function(x) {
  if (is.environment(x) || is.function(x) || typeof(x) == "externalptr") return(TRUE)
  if (is.list(x)) return(any(vapply(x, contains_environment, logical(1))))
  FALSE
}
manifest <- list()
for (name in gt_example()$name) {
  task <- if (name == "hate_speech") "hate_speech" else
    if (startsWith(name, "mental_health")) "mental_health" else "drug_review"
  codings <- if (name == "mental_health_nominal") "native" else c("native", "manuscript")
  path <- file.path(destination, paste0(name, ".rds"))
  provenance <- list(data_kind = "public_llm_annotations", author = "Jin Liu",
    license = "CC-BY-4.0", source_file = unname(source_files[task]),
    source_md5 = unname(source_md5[task]), source_url = unname(source_urls[task]),
    source_doi = "10.17605/OSF.IO/K9CAJ",
    license_source = "https://osf.io/download/69e52a44fa0947a9f3fd89c0/",
    rows = 21600L, design_columns = allowed_design, design_counts = design_counts,
    included_content = "Design identifiers and modeled LLM annotations only; no source texts, original human labels, or raw API responses.",
    coding_method = "gt_example(): explicit native response types or historical Gaussian working-score mappings; original preprocessing retained.",
    interpretation = "LLM-generated annotations from three public panels; not independently adjudicated human measurements.")
  if (verify_only) {
    if (!file.exists(path)) stop("Missing resource: ", basename(path))
    resource <- readRDS(path)
  } else {
    input <- file.path(source_directory, source_files[task])
    if (!file.exists(input) || !identical(unname(tools::md5sum(input)), unname(source_md5[task])))
      stop("Source file is missing or differs from the documented public deposit: ", source_files[task])
    tables <- setNames(lapply(codings, function(coding) {
      value <- gt_example(name, coding, directory = source_directory)
      value$source <- NULL
      value
    }), codings)
    resource <- list(schema_version = 1L, name = name, codings = tables,
      source_provenance = provenance)
  }
  stopifnot(identical(resource$schema_version, 1L), identical(resource$name, name),
    identical(names(resource$codings), codings), identical(resource$source_provenance, provenance),
    !contains_environment(resource))
  for (coding in codings) {
    value <- resource$codings[[coding]]
    stopifnot(identical(names(value$data), c(allowed_design, value$outcomes)),
      nrow(value$data) == 21600L, !anyNA(value$data),
      identical(vapply(value$data[allowed_design], nlevels, integer(1)), design_counts),
      !anyDuplicated(value$data[allowed_design]))
    .gt_resolve_families(value$data, value$outcomes, value$families)
  }
  text <- as.character(unlist(resource, recursive = TRUE, use.names = FALSE))
  stopifnot(!any(grepl("/Users/|/home/|/private/|(^|[[:space:]])[A-Za-z]:[/\\\\]", text)))
  if (!verify_only) saveRDS(resource, path, compress = "xz", version = 3L)
  stopifnot(identical(resource, readRDS(path)))
  manifest[[name]] <- data.frame(name = name, resource = basename(path),
    data_kind = provenance$data_kind, source_file = provenance$source_file,
    source_md5 = provenance$source_md5, source_url = provenance$source_url,
    resource_md5 = unname(tools::md5sum(path)), rows = 21600L,
    codings = paste(codings, collapse = ";"), stringsAsFactors = FALSE)
}
manifest_table <- do.call(rbind, manifest)
rownames(manifest_table) <- NULL
manifest_path <- file.path(destination, "manifest.csv")
if (verify_only) {
  stopifnot(identical(manifest_table, utils::read.csv(manifest_path, stringsAsFactors = FALSE)))
} else utils::write.csv(manifest_table, manifest_path, row.names = FALSE)
cat(if (verify_only) "Verified" else "Prepared", length(manifest),
  "public LLM annotation resources with fifteen response codings.\n")
