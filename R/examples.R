# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Example modeling tables and explicit CSV loading.

# Load a documented outcome set without raw text or API metadata
# name: Outcome-set name; NULL lists the available sets.
# coding: native retains binary/ordinal/nominal observation types;
#   manuscript is the legacy name for seven Gaussian numeric-score codings.
# directory: Directory containing example RDS resources or source CSVs. The
#   installed package uses bundled modeling tables when directory is omitted.
#   Standalone use requires installed resources or an explicit local directory.
gt_example <- function(name = NULL, coding = c("native", "manuscript"), directory = NULL) {
  catalog <- data.frame(
    name = c("hate_speech", "mental_health_7L", "mental_health_3L", "mental_health_6flag",
             "mental_health_3group", "drug_review", "drug_review_4aspect", "mental_health_nominal"),
    native_family = c("ordinal", "gaussian", "gaussian", "binary", "binary", "ordinal", "ordinal", "categorical"),
    outcomes = c(1L, 1L, 1L, 6L, 3L, 1L, 4L, 1L), stringsAsFactors = FALSE)
  if (is.null(name)) return(catalog)
  if (!is.character(name) || length(name) != 1L || is.na(name) || !name %in% catalog$name)
    stop("Unknown example name; call gt_example() for the available sets.", call. = FALSE)
  coding <- match.arg(coding)
  if (name == "mental_health_nominal" && coding == "manuscript")
    stop("The nominal example has native unordered coding only; choose an explicitly named 7L/3L set for numeric-score coding.", call. = FALSE)
  # A standalone loader may configure its own enclosing environment. Never
  # search callers, attached environments, or the global workspace on behalf
  # of an installed package: those must not redirect its bundled examples.
  enclosing <- parent.env(environment())
  if (is.null(directory) && !isNamespace(enclosing))
    directory <- get0(".gt_example_data_dir", envir = enclosing, inherits = FALSE)
  if (!is.null(directory) && (!is.character(directory) || length(directory) != 1L ||
      is.na(directory) || !nzchar(directory)))
    stop("directory must be NULL or one nonempty directory path.", call. = FALSE)
  bundled <- if (is.null(directory))
    system.file("extdata", paste0(name, ".rds"), package = "Gtheory4LLM") else
      file.path(directory, paste0(name, ".rds"))
  if (is.null(directory) && !nzchar(bundled))
    stop("Supply directory, source load_functions.R, or install Gtheory4LLM to use bundled modeling tables.", call. = FALSE)
  if (file.exists(bundled)) {
    resource <- readRDS(bundled)
    if (!identical(resource$schema_version, 1L) || !identical(resource$name, name) ||
        is.null(resource$codings[[coding]]))
      stop("The example resource has an unsupported schema or coding.", call. = FALSE)
    result <- resource$codings[[coding]]
    result$source <- normalizePath(bundled, mustWork = TRUE)
    result$source_provenance <- resource$source_provenance
    return(result)
  }
  filename <- if (name == "hate_speech") "hate_labeling_final.csv" else
    if (startsWith(name, "mental_health")) "mh_labeling_final.csv" else "drug_labeling_final.csv"
  path <- file.path(directory, filename)
  if (!file.exists(path))
    stop("Example CSV file not found: ", path, ".", call. = FALSE)
  raw <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  needed <- c("item_id", "evaluator", "prompt_type", "temperature", "seed")
  if (!all(needed %in% names(raw))) stop("Dataset is missing instrumentation columns.")
  data <- data.frame(item = factor(raw$item_id), evaluator = factor(raw$evaluator),
                     prompt = factor(raw$prompt_type), temp = factor(raw$temperature), seed = factor(raw$seed))
  families <- list()
  notes <- character()
  if (name %in% c("hate_speech", "drug_review")) {
    permitted <- if (name == "hate_speech") 1:3 else 1:5
    value <- suppressWarnings(as.numeric(as.character(raw$severity)))
    if (anyNA(value) || any(!value %in% permitted)) stop("Invalid severity scores.")
    data$score <- if (coding == "native") ordered(value, levels = permitted) else value
    families$score <- if (coding == "native") gt_family("ordinal", levels = permitted) else gt_family()
  } else if (name == "drug_review_4aspect") {
    traits <- c("efficacy", "safety", "burden", "cost")
    cats <- c("NEGATIVE", "NEUTRAL", "POSITIVE")
    for (trait in traits) {
      value <- toupper(trimws(as.character(raw[[paste0("ai_", trait)]])))
      if (length(value) != nrow(raw) || anyNA(value) || any(!value %in% cats)) stop("Invalid aspect labels.")
      data[[trait]] <- if (coding == "native") ordered(value, levels = cats) else match(value, cats)
      families[[trait]] <- if (coding == "native") gt_family("ordinal", levels = cats) else gt_family()
    }
  } else if (name %in% c("mental_health_6flag", "mental_health_3group")) {
    traits <- c("depression", "anxiety", "suicidal", "stress", "bipolar", "personality_disorder")
    flags <- lapply(traits, function(trait) {
      value <- tolower(trimws(as.character(raw[[paste0(trait, "_present")]])))
      if (length(value) != nrow(raw) || anyNA(value) || any(!value %in% c("true", "false", "1", "0")))
        stop("Invalid binary flag; validate constituents before forming groups.")
      as.integer(value %in% c("true", "1"))
    })
    names(flags) <- traits
    if (name == "mental_health_3group") flags <- list(
      stress = flags$stress,
      anxiety_depression = as.integer(flags$anxiety == 1 | flags$depression == 1),
      bipolar_personality_suicidal = as.integer(flags$bipolar == 1 | flags$personality_disorder == 1 | flags$suicidal == 1))
    for (trait in names(flags)) {
      data[[trait]] <- flags[[trait]]
      families[[trait]] <- if (coding == "native") gt_family("binary") else gt_family()
    }
  } else {
    cats <- c("NORMAL", "STRESS", "ANXIETY", "DEPRESSION", "BIPOLAR", "PERSONALITY_DISORDER", "SUICIDAL")
    value <- toupper(trimws(as.character(raw$label)))
    if (anyNA(value) || any(!value %in% cats)) stop("Invalid Mental-Health labels.")
    if (name == "mental_health_nominal") {
      data$label <- factor(value, levels = cats, ordered = FALSE)
      families$label <- gt_family("categorical", levels = cats, reference = "NORMAL")
    } else {
      mapped <- if (name == "mental_health_7L") seq_along(cats) else c(1L, 1L, 2L, 2L, 3L, 3L, 3L)
      data$score <- mapped[match(value, cats)]
      families$score <- gt_family()
      notes <- c(notes, "The 7L/3L coding is a manuscript working score, not an established clinical severity order. Use mental_health_nominal for unordered categories.")
    }
  }
  if (anyNA(data)) stop("Prepared example contains missing values.")
  list(data = data, outcomes = names(families), families = families,
       object = "item", facets = c("evaluator", "prompt", "temp", "seed"),
       name = name, coding = coding, source = normalizePath(path), notes = notes)
}
