# Public resource contracts: deterministic synthetic panels and explicit families.
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
  assert(identical(native$source_provenance$data_kind, "synthetic"), "Public examples must be explicitly synthetic")
  assert(nrow(native$data) > 0L && !anyNA(native$data), "Example has missing or empty data")
  assert(identical(names(native$data), c(native$object, native$facets, native$outcomes)), "Unexpected data columns")
  assert(!any(c("text", "raw_text", "review", "api_key") %in% names(native$data)), "Unexpected non-modeling columns")
  assert(file.exists(native$source), "Example resource does not exist")
  before <- tools::md5sum(native$source)
  assert(identical(native, gt_example(name)), "Example loading must be deterministic")
  assert(identical(before, tools::md5sum(native$source)), "Loading changed resource bytes")
  dimensions <- c(native$object, native$facets)
  counts <- vapply(native$data[dimensions], function(x) length(unique(x)), integer(1))
  assert(nrow(native$data) == prod(counts), "Public illustration must retain its complete panel")
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
assert(all(groups$stress == flags$stress), "Stress group changed its constituent")
assert(all(groups$anxiety_depression == as.integer(flags$anxiety + flags$depression > 0)), "Two-flag group changed")
assert(all(groups$bipolar_personality_suicidal == as.integer(flags$bipolar + flags$personality_disorder + flags$suicidal > 0)), "Three-flag group changed")
expect_error(gt_example("unknown"), "Unknown example")
expect_error(gt_example(NA_character_), "Unknown example")
expect_error(gt_example("hate_speech", coding = "unsupported"), "arg")
cat("PASS: eight synthetic public examples and fifteen explicit codings retain their panel, families, and resource bytes.\n")
