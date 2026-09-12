# Public resource contracts: the approved LLM annotation panels and explicit families.
source("load_functions.R")
assert <- function(value, message) if (!isTRUE(value)) stop(message, call. = FALSE)
expect_error <- function(expr, pattern) {
  e <- tryCatch({ force(expr); NULL }, error = identity)
  assert(inherits(e, "error") && grepl(pattern, conditionMessage(e)), pattern)
}
catalog <- gt_example()
expected_names <- c("hate_speech", "mental_health_7L", "mental_health_3L", "mental_health_6flag",
                    "mental_health_3group", "drug_review", "drug_review_4aspect", "mental_health_nominal")
expected_family <- c("ordinal", "gaussian", "gaussian", "binary", "binary", "ordinal", "ordinal", "categorical")
assert(identical(catalog$name, expected_names), "Unexpected public example catalog")
assert(identical(catalog$native_family, expected_family), "Catalog families changed")
assert(identical(catalog$outcomes, c(1L, 1L, 1L, 6L, 3L, 1L, 4L, 1L)), "Outcome counts changed")
loaded <- list()
for (name in catalog$name) {
  native <- gt_example(name)
  assert(identical(native$source_provenance$data_kind, "public_llm_annotations"), "Public examples must identify their real LLM annotations")
  assert(nrow(native$data) == 21600L && !anyNA(native$data), "The approved annotation panel must contain 21,600 complete rows")
  assert(identical(names(native$data), c(native$object, native$facets, native$outcomes)), "Unexpected data columns")
  assert(!any(c("text", "raw_text", "review", "api_key") %in% names(native$data)), "Unexpected non-modeling columns")
  assert(file.exists(native$source), "Example resource does not exist")
  before <- tools::md5sum(native$source)
  assert(identical(native, gt_example(name)), "Example loading must be deterministic")
  assert(identical(before, tools::md5sum(native$source)), "Loading changed resource bytes")
  dimensions <- c(native$object, native$facets)
  counts <- vapply(native$data[dimensions], function(x) length(unique(x)), integer(1))
  assert(nrow(native$data) == prod(counts) && !anyDuplicated(native$data[dimensions]), "Annotations must retain their complete panel without duplicate cells")
  for (outcome in native$outcomes) {
    value <- native$data[[outcome]]
    family <- native$families[[outcome]]
    assert(identical(family$family, catalog$native_family[catalog$name == name]), "Family differs from catalog")
    if (family$family == "ordinal") assert(is.ordered(value), "Ordinal order was lost")
    if (family$family == "categorical") assert(is.factor(value) && !is.ordered(value), "Nominal categories acquired an order")
    if (family$family == "binary") assert(setequal(unique(value), c(0, 1)), "Binary example lacks a category")
    if (family$family == "gaussian") assert(is.numeric(value), "Gaussian scores are not numeric")
  }
  .gt_resolve_families(native$data, native$outcomes, native$families)
  if (name != "mental_health_nominal") {
    scored <- gt_example(name, coding = "manuscript")
    assert(identical(native$data[dimensions], scored$data[dimensions]), "Alternate scoring changed the panel")
    for (outcome in native$outcomes) {
      value <- native$data[[outcome]]
      expected <- if (is.ordered(value)) as.integer(value) else value
      assert(isTRUE(all.equal(as.numeric(scored$data[[outcome]]), as.numeric(expected))), "Alternate scoring changed numeric values")
      assert(scored$families[[outcome]]$family == "gaussian", "Numeric working score must use Gaussian family")
    }
  }
  loaded[[name]] <- native
}
flags <- loaded$mental_health_6flag$data
groups <- loaded$mental_health_3group$data
mental_names <- catalog$name[startsWith(catalog$name, "mental_health")]
dimensions <- c(loaded$mental_health_nominal$object, loaded$mental_health_nominal$facets)
for (name in mental_names)
  assert(identical(loaded[[name]]$data[dimensions], loaded$mental_health_nominal$data[dimensions]), "Mental-health codings changed row identities")
categories <- c("NORMAL", "STRESS", "ANXIETY", "DEPRESSION", "BIPOLAR", "PERSONALITY_DISORDER", "SUICIDAL")
nominal <- loaded$mental_health_nominal$data$label
assert(identical(levels(nominal), categories), "Nominal category definitions changed")
index <- match(as.character(nominal), categories)
assert(all(loaded$mental_health_7L$data$score == index), "Seven-level working-score mapping changed")
assert(all(loaded$mental_health_3L$data$score == c(1L, 1L, 2L, 2L, 3L, 3L, 3L)[index]), "Three-level working-score mapping changed")
assert(all(groups$stress == flags$stress), "Stress group changed its constituent")
assert(all(groups$anxiety_depression == as.integer(flags$anxiety + flags$depression > 0)), "Two-flag group changed")
assert(all(groups$bipolar_personality_suicidal == as.integer(flags$bipolar + flags$personality_disorder + flags$suicidal > 0)), "Three-flag group changed")
expect_error(gt_example("unknown"), "Unknown example")
expect_error(gt_example(NA_character_), "Unknown example")
expect_error(gt_example("hate_speech", coding = "unsupported"), "arg")
cat("PASS: eight real LLM annotation outcome sets and fifteen explicit codings retain their 21,600-row panels, families, and resource bytes.\n")
