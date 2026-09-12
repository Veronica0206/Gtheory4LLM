#!/usr/bin/env Rscript
# Run directly with Rscript; no testing package, data, or model fitting required.

.test_file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(.test_file_arg) != 1L) {
  stop("Run this file with Rscript so its source paths can be resolved.")
}
.test_path <- sub("^--file=", "", .test_file_arg)
# Some Rscript builds encode spaces in --file as ~+~.
if (!file.exists(.test_path)) .test_path <- gsub("~+~", " ", .test_path, fixed = TRUE)
.test_file <- normalizePath(.test_path, mustWork = TRUE)
.package_dir <- dirname(dirname(.test_file))
.project_dir <- .package_dir
.implementation <- new.env(parent = globalenv())
sys.source(file.path(.package_dir, "R", "design.R"), envir = .implementation)
gt_design <- .implementation$gt_design
if (!is.function(gt_design)) stop("R/design.R must define gt_design().")

.results <- list()
check <- function(label, code) {
  failure <- tryCatch({ force(code); NULL }, error = function(e) conditionMessage(e))
  .results[[label]] <<- failure
  # Assigning NULL removes a list entry, so preserve an explicit success record.
  if (is.null(failure)) .results[[label]] <<- TRUE
  cat(if (is.null(failure)) "PASS" else "FAIL", label,
      if (is.null(failure)) "" else paste0(": ", failure), "\n")
}
assert <- function(value, message = "Assertion failed") {
  if (!isTRUE(value)) stop(message, call. = FALSE)
}
same_set <- function(actual, expected, label = "Term sets differ") {
  assert(is.character(actual), paste(label, "(actual is not character)"))
  assert(!anyDuplicated(actual), paste(label, "(duplicate actual terms)"))
  assert(setequal(actual, expected), paste0(
    label, "; missing: ", paste(setdiff(expected, actual), collapse = ", "),
    "; extra: ", paste(setdiff(actual, expected), collapse = ", ")))
}
fails <- function(code) {
  caught <- tryCatch({ force(code); FALSE }, error = function(e) TRUE)
  assert(caught, "Expected an error, but the call succeeded")
}
canonical <- function(groups, dimensions) {
  vapply(strsplit(groups, ":", fixed = TRUE), function(parts) {
    paste(dimensions[dimensions %in% parts], collapse = ":")
  }, character(1), USE.NAMES = FALSE)
}
inspect_contract <- function(design) {
  assert(inherits(design, "gt_design"), "Missing gt_design class")
  expected_fields <- c("object", "facets", "crossed", "nested", "nested_groups",
                       "terms", "term_members", "direct_facets", "aliased_terms",
                       "replicates", "construction", "notes", "validated_data")
  assert(all(expected_fields %in% names(design)), "Missing output fields")
  assert(identical(design$validated_data, FALSE), "Constructor claimed data validation")
  assert(identical(design$terms,
                   canonical(design$terms, c(design$object, design$facets))),
         "Terms are not in canonical dimension order")
  assert(!anyDuplicated(design$terms), "Duplicate terms")
  assert(is.list(design$term_members), "term_members must be a list")
  assert(identical(names(design$term_members), design$terms),
         "term_members must be named in the same order as terms")
  for (term in design$terms) {
    assert(identical(unname(design$term_members[[term]]),
                     strsplit(term, ":", fixed = TRUE)[[1L]]),
           paste("Incorrect membership for", term))
  }
  if (!identical(design$construction, "custom")) {
    same_set(design$direct_facets, design$crossed, "direct_facets and crossed differ")
  }
}

facets4 <- c("evaluator", "prompt", "temp", "seed")
dimensions5 <- c("item", facets4)
chain_e <- list(prompt = "evaluator", temp = "prompt", seed = "temp")

check("all 15 nonempty choices of crossed facets", {
  for (k in seq_along(facets4)) {
    for (roots in combn(facets4, k, simplify = FALSE)) {
      children <- setdiff(facets4, roots)
      nesting <- setNames(vector("list", length(children)), children)
      for (j in seq_along(children)) {
        nesting[[j]] <- if (j == 1L) roots else children[j - 1L]
      }
      design <- gt_design("item", facets4, crossed = roots, nested = nesting)
      inspect_contract(design)
      expected_count <- 2^(k + 1L) + length(facets4) - k - 1L
      assert(length(design$terms) == expected_count, "Incorrect complete term count")
      actual_direct <- design$terms[vapply(design$term_members, function(parts) {
        length(parts) == 2L && "item" %in% parts
      }, logical(1))]
      same_set(actual_direct, paste("item", roots, sep = ":"),
               "Wrong direct item interactions")
      for (j in seq_along(children)) {
        expected_group <- canonical(paste(c(roots, children[seq_len(j)]),
                                          collapse = ":"), dimensions5)
        assert(identical(unname(design$nested_groups[[children[j]]]), expected_group),
               "Nested ancestor expansion differs")
      }
    }
  }
})

check("true all-order crossing and cell replication", {
  single <- gt_design("item", facets4)
  replicated <- gt_design("item", facets4, replicates = 2L)
  full <- paste(dimensions5, collapse = ":")
  assert(length(single$terms) == 31L, "All requested terms must remain present")
  same_set(single$potential_aliases, full)
  assert(length(single$aliased_terms) == 0L, "Family-specific alias resolved too early")
  assert(length(replicated$terms) == 31L, "Expected 31 replicated terms")
  assert(length(replicated$aliased_terms) == 0L, "Replicated top term incorrectly aliased")
  same_set(replicated$terms, c(single$terms, full))
  inspect_contract(single)
  inspect_contract(replicated)
})
check("pairwise sources contain every main effect and pair", {
  design <- gt_design("item", facets4, instrument_interactions = 2L,
                      item_interactions = "additive")
  expected <- c(dimensions5, vapply(combn(dimensions5, 2L, simplify=FALSE),
                                    paste, character(1), collapse=":"))
  same_set(design$terms, expected)
  assert(length(design$terms) == 15L, "Pairwise model should have 15 terms")
})
check("interaction-order selectors are independent", {
  additive <- gt_design("item", facets4, item_interactions = "additive")
  assert(length(additive$terms) == 20L, "Complete instrument interactions were lost")
  second_order <- gt_design("item", facets4, item_interactions = 2L,
                            instrument_interactions = "additive")
  assert(length(second_order$terms) == 15L, "Incorrect selected interaction count")
  assert("item:evaluator:prompt" %in% second_order$terms, "Missing item triple")
  assert(!"evaluator:prompt" %in% second_order$terms, "Unexpected instrument pair")
})
check("generic one, two, three, and five instrumentation facets", {
  for (n in c(1L, 2L, 3L, 5L)) {
    labels <- paste0("facet_", seq_len(n))
    design <- gt_design("participant", labels)
    inspect_contract(design)
    assert(length(design$terms) == 2^(n + 1L) - 1L, "Hard-coded dimension count")
    same_set(design$potential_aliases, paste(c("participant", labels), collapse = ":"))
  }
})
check("parent declaration order and redundant ancestors do not change groups", {
  expected <- gt_design("item", facets4, crossed = "evaluator", nested = chain_e)
  unordered <- gt_design("item", facets4, crossed = "evaluator",
                        nested = list(seed = "temp", temp = c("prompt", "evaluator"),
                                      prompt = "evaluator"))
  same_set(unordered$terms, expected$terms)
})
check("nested extension adds only its selected ancestor-closed group", {
  design <- gt_design("item", facets4, crossed = "evaluator", nested = chain_e,
                      item_nested = "temp")
  same_set(design$terms, c("item", "evaluator", "evaluator:prompt", "item:evaluator",
                            "evaluator:prompt:temp", "evaluator:prompt:temp:seed",
                            "item:evaluator:prompt:temp"))
  assert(!"item:evaluator:prompt" %in% design$terms, "Implicit ancestor item extension")
})
check("branching nested children do not invent sibling interactions", {
  design <- gt_design("person", c("rater", "occasion", "device"), crossed = "rater",
                      nested = list(occasion = "rater", device = "rater"))
  same_set(design$terms, c("person", "rater", "person:rater", "rater:occasion",
                            "rater:device"))
})
check("column names with spaces are treated literally", {
  design <- gt_design("Text object", c("Panel name", "Sampling round"))
  same_set(design$terms, c("Text object", "Panel name", "Sampling round",
                          "Panel name:Sampling round", "Text object:Panel name",
                          "Text object:Sampling round", "Text object:Panel name:Sampling round"))
  inspect_contract(design)
})

check("custom terms are canonical and permit reduced models", {
  design <- gt_design("item", facets4,
                      random = c("item", "prompt:evaluator", "seed:item"))
  same_set(design$terms, c("item", "evaluator:prompt", "item:seed"))
  same_set(design$direct_facets, "seed", "Custom direct interaction was not inferred")
  assert(length(design$crossed) == 0L, "Custom model inferred a physical crossing design")
  inspect_contract(design)
})
check("custom formula expands crossing without evaluating expressions", {
  design <- gt_design("item", c("rater", "occasion"),
                      random = ~ item * rater + occasion + item:occasion)
  same_set(design$terms, c("item", "rater", "item:rater", "occasion",
                            "item:occasion"))
})
check("custom highest-order term preserves residual alias metadata", {
  design <- gt_design("item", c("rater", "occasion"),
                      random = ~ item * rater * occasion)
  assert(length(design$terms) == 7L, "Custom complete expansion differs")
  same_set(design$potential_aliases, "item:rater:occasion")
})
check("custom terms cannot be combined with automatic selectors", {
  fails(gt_design("item", facets4, random = ~ item + evaluator,
                  crossed = "evaluator", nested = chain_e))
  fails(gt_design("item", facets4, random = ~ item + evaluator,
                  item_interactions = "additive"))
  fails(gt_design("item", facets4, random = ~ item + evaluator,
                  instrument_interactions = "additive"))
})
check("custom formula rejects calls, slash nesting, and executable blocks", {
  fails(gt_design("item", facets4, random = ~ item + log(evaluator)))
  fails(gt_design("item", facets4, random = ~ item + evaluator / prompt))
  .injection_probe <- new.env(parent = emptyenv())
  .injection_probe$called <- FALSE
  malicious <- ~ item + { .injection_probe$called <- TRUE; evaluator }
  fails(gt_design("item", facets4, random = malicious))
  assert(!.injection_probe$called, "Formula expressions were evaluated")
})

check("invalid topology is rejected", {
  fails(gt_design("item", facets4, crossed = "unknown"))
  fails(gt_design("item", facets4, crossed = character(), nested = chain_e))
  fails(gt_design("item", facets4, crossed = "evaluator", nested = list(prompt = "evaluator")))
  fails(gt_design("item", facets4, crossed = "evaluator",
                  nested = list(prompt = "unknown", temp = "prompt", seed = "temp")))
  fails(gt_design("item", facets4, crossed = "evaluator",
                  nested = list(prompt = "temp", temp = "prompt", seed = "temp")))
  fails(gt_design("item", facets4, crossed = "evaluator",
                  nested = list(prompt = "prompt", temp = "prompt", seed = "temp")))
  fails(gt_design("item", facets4, crossed = "evaluator",
                  nested = c(chain_e, list(evaluator = "prompt"))))
  fails(gt_design("item", facets4, crossed = "evaluator",
                  nested = list(prompt = "item", temp = "prompt", seed = "temp")))
  fails(gt_design("item", facets4, crossed = "evaluator", nested = chain_e,
                  item_nested = "evaluator"))
  fails(gt_design("item", facets4, crossed = "evaluator", nested = chain_e,
                  item_nested = "unknown"))
})
check("ambiguous names and malformed controls are rejected", {
  fails(gt_design("item", c("a", "a")))
  fails(gt_design("item", c("item", "a")))
  fails(gt_design("item", c("a:b", "c")))
  fails(gt_design("item:part", c("a", "b")))
  fails(gt_design("item", c("a", NA_character_)))
  fails(gt_design("item", c("a", "")))
  fails(gt_design("item", facets4, crossed = c("evaluator", "evaluator")))
  fails(gt_design("item", facets4, item_interactions = 0L))
  fails(gt_design("item", facets4, item_interactions = 1.5))
  fails(gt_design("item", facets4, instrument_interactions = "unsupported"))
  fails(gt_design("item", facets4, replicates = 0L))
  fails(gt_design("item", facets4, replicates = 1.5))
  fails(gt_design("item", facets4, max_terms = 0L))
})
check("custom malformed, unknown, and duplicate terms are rejected", {
  fails(gt_design("item", facets4, random = c("item", "unknown")))
  fails(gt_design("item", facets4, random = c("item", "evaluator::prompt")))
  fails(gt_design("item", facets4, random = c("item", "evaluator:evaluator")))
  fails(gt_design("item", facets4,
                  random = c("item", "evaluator:prompt", "prompt:evaluator")))
})
check("combinatorial growth respects max_terms", {
  fails(gt_design("item", paste0("facet", seq_len(12L)), max_terms = 64L))
})

.failed <- !vapply(.results, isTRUE, logical(1))
cat("\n", sum(!.failed), "/", length(.results), " design tests passed.\n", sep = "")
if (any(.failed)) {
  stop(paste("Failed tests:", paste(names(.results)[.failed], collapse = "; ")),
       call. = FALSE)
}
