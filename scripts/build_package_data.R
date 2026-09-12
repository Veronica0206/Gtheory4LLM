# Generate original synthetic examples authored by Jin Liu under GPL-3.
# Run from the repository root: Rscript --vanilla scripts/build_package_data.R
# --verify-only regenerates expected objects in memory and reads existing files;
# it never creates, rewrites, or touches resources or their manifest.
arguments <- commandArgs(trailingOnly = TRUE)
if (any(!arguments %in% "--verify-only")) stop("Only --verify-only is supported.")
verify_only <- "--verify-only" %in% arguments
source(file.path("R", "family.R"))
destination <- file.path("inst", "extdata")
if (!verify_only) dir.create(destination, recursive = TRUE, showWarnings = FALSE)

# All labels, prevalences, and patterns below are synthetic. This deterministic
# integer construction uses no source study, fitted result, random generator,
# machine-dependent floating-point distribution function, or external input.
index <- expand.grid(item = seq_len(24L), evaluator = seq_len(3L),
  prompt = seq_len(2L), temp = seq_len(2L), seed = seq_len(2L),
  KEEP.OUT.ATTRS = FALSE)
design_columns <- names(index)
panel <- data.frame(item = factor(sprintf("item_%02d", index$item)),
  evaluator = factor(paste0("evaluator_", index$evaluator)),
  prompt = factor(paste0("prompt_", index$prompt)),
  temp = factor(paste0("temperature_", index$temp)),
  seed = factor(paste0("seed_", index$seed)))
synthetic_code <- function(salt) {
  salt <- as.integer(salt)
  z <- (97L * index$item + 43L * index$evaluator + 71L * index$prompt +
    113L * index$temp + 151L * index$seed + 179L * salt) %% 65521L
  for (step in seq_len(3L))
    z <- ((z %% 251L) * (z %% 241L) * 17L + 43L * z +
      31L * salt + 19L * step) %% 65521L
  as.integer(z)
}
category <- function(salt, n) 1L + synthetic_code(salt) %% as.integer(n)
mental_levels <- c("NORMAL", "STRESS", "ANXIETY", "DEPRESSION", "BIPOLAR",
                   "PERSONALITY_DISORDER", "SUICIDAL")
mental_label <- mental_levels[category(2L, 7L)]
flag_names <- c("depression", "anxiety", "suicidal", "stress", "bipolar",
                "personality_disorder")
flags <- stats::setNames(lapply(seq_along(flag_names), function(j)
  as.integer(synthetic_code(10L + j) %% 7L < 2L)), flag_names)
groups <- list(stress = flags$stress,
  anxiety_depression = as.integer(flags$anxiety == 1L | flags$depression == 1L),
  bipolar_personality_suicidal = as.integer(flags$bipolar == 1L |
    flags$personality_disorder == 1L | flags$suicidal == 1L))
aspect_names <- c("efficacy", "safety", "burden", "cost")
aspect_levels <- c("NEGATIVE", "NEUTRAL", "POSITIVE")
aspects <- stats::setNames(lapply(seq_along(aspect_names), function(j)
  ordered(aspect_levels[category(20L + j, 3L)], levels = aspect_levels)), aspect_names)
native_outcomes <- list(
  hate_speech = list(score = ordered(category(1L, 3L), levels = 1:3)),
  mental_health_7L = list(score = as.integer(match(mental_label, mental_levels))),
  mental_health_3L = list(score = c(1L, 1L, 2L, 2L, 3L, 3L, 3L)[match(mental_label, mental_levels)]),
  mental_health_6flag = flags,
  mental_health_3group = groups,
  drug_review = list(score = ordered(category(3L, 5L), levels = 1:5)),
  drug_review_4aspect = aspects,
  mental_health_nominal = list(label = factor(mental_label, levels = mental_levels)))
native_kinds <- c(hate_speech = "ordinal", mental_health_7L = "gaussian",
  mental_health_3L = "gaussian", mental_health_6flag = "binary",
  mental_health_3group = "binary", drug_review = "ordinal",
  drug_review_4aspect = "ordinal", mental_health_nominal = "categorical")
contains_environment <- function(x) {
  if (is.environment(x) || is.function(x) || typeof(x) == "externalptr") return(TRUE)
  if (is.list(x)) return(any(vapply(x, contains_environment, logical(1))))
  FALSE
}
manifest <- list()
for (name in names(native_outcomes)) {
  codings <- if (name == "mental_health_nominal") "native" else c("native", "manuscript")
  tables <- stats::setNames(lapply(codings, function(coding) {
    outcomes <- native_outcomes[[name]]
    if (coding == "manuscript") outcomes <- lapply(outcomes, function(x)
      if (is.ordered(x)) as.integer(x) else x)
    families <- lapply(outcomes, function(x) {
      kind <- if (coding == "manuscript") "gaussian" else native_kinds[[name]]
      if (kind == "categorical") gt_family(kind, levels = levels(x), reference = "NORMAL") else
        if (kind == "ordinal") gt_family(kind, levels = levels(x)) else
          if (kind == "binary") gt_family(kind, levels = c("0", "1")) else gt_family()
    })
    data <- panel
    data[names(outcomes)] <- outcomes
    notes <- c("Entirely synthetic observations produced by deterministic integer arithmetic; not real texts, LLM outputs, human ratings, or clinical measurements.",
      "These toy patterns illustrate data structure and category handling, not a fitted generative model, population prevalence, or parameter-recovery experiment.")
    if (coding == "manuscript") notes <- c(notes,
      "The legacy coding name 'manuscript' selects numeric-score compatibility; these synthetic values reproduce no manuscript observations or results.")
    if (name %in% c("mental_health_7L", "mental_health_3L")) notes <- c(notes,
      "The 7L/3L numerical coding is a working-score illustration, not an established clinical severity order.")
    .gt_resolve_families(data, names(outcomes), families)
    stopifnot(identical(names(data), c(design_columns, names(outcomes))),
      nrow(data) == 576L, !anyNA(data))
    list(data = data, outcomes = names(outcomes), families = families,
      object = "item", facets = design_columns[-1L], name = name,
      coding = coding, notes = notes)
  }), codings)
  provenance <- list(data_kind = "synthetic", author = "Jin Liu", license = "GPL-3",
    generator = "scripts/build_package_data.R", generator_version = 1L,
    construction = "Deterministic bounded integer arithmetic; no source observations or fitted parameters.",
    rows = 576L, design_columns = design_columns,
    design_counts = c(item = 24L, evaluator = 3L, prompt = 2L, temp = 2L, seed = 2L),
    included_content = "Synthetic design identifiers and simulated outcomes only",
    coding_method = "Explicit native categories or legacy numeric-score compatibility mapping",
    interpretation = "Synthetic software examples only; not LLM-generated evidence or clinical data.")
  resource <- list(schema_version = 1L, name = name, codings = tables,
                   source_provenance = provenance)
  stopifnot(!contains_environment(resource))
  text <- as.character(unlist(resource, recursive = TRUE, use.names = FALSE))
  stopifnot(!any(grepl("/Users/|/home/|/private/|[A-Za-z]:[/\\\\]", text)))
  path <- file.path(destination, paste0(name, ".rds"))
  if (verify_only) {
    if (!file.exists(path)) stop("Missing package example resource: ", basename(path))
  } else saveRDS(resource, path, compress = "xz", version = 3L)
  stopifnot(identical(resource, readRDS(path)))
  manifest[[name]] <- data.frame(name = name, resource = basename(path),
    data_kind = "synthetic", generator = provenance$generator,
    generator_version = provenance$generator_version,
    resource_md5 = unname(tools::md5sum(path)), rows = 576L,
    codings = paste(codings, collapse = ";"), stringsAsFactors = FALSE)
}
manifest_table <- do.call(rbind, manifest)
rownames(manifest_table) <- NULL
manifest_path <- file.path(destination, "manifest.csv")
if (verify_only) {
  if (!file.exists(manifest_path)) stop("Missing example manifest.")
  recorded <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
  stopifnot(identical(manifest_table, recorded))
} else utils::write.csv(manifest_table, manifest_path, row.names = FALSE)
cat(if (verify_only) "Verified" else "Prepared", length(manifest),
  "synthetic example resources with fifteen explicit codings.\n")
