# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# General G-theory specification construction. No model fitting occurs here.

.gt_design_abort <- function(...) stop(..., call. = FALSE)

# Integer codes avoid collisions between user labels containing separators.
# Drop column names before do.call() so names such as sep, collapse, or
# recycle0 remain data columns rather than matching paste() control arguments.
.gt_tuple_key <- function(data, members) {
  codes <- lapply(data[members], function(x) match(x, unique(x)))
  do.call(paste, c(unname(codes), list(sep = ":")))
}

.gt_design_names <- function(x, label, allow_empty = FALSE) {
  if (!is.character(x) || (!allow_empty && !length(x)) || anyNA(x) ||
      any(!nzchar(x)) || any(trimws(x) != x) || anyDuplicated(x)) {
    .gt_design_abort(label, " must contain unique, nonempty column names.")
  }
  if (any(grepl(":", x, fixed = TRUE)) || any(x == "Residual")) {
    .gt_design_abort(label, " cannot contain ':' or the reserved name 'Residual'.")
  }
  unname(x)
}

.gt_design_order <- function(value, n, label) {
  if (is.character(value) && length(value) == 1L && !is.na(value)) {
    if (value == "complete") return(n)
    if (value == "additive") return(1L)
  }
  if (is.numeric(value) && length(value) == 1L && is.finite(value) &&
      value == floor(value) && value >= 1 && value <= n) return(as.integer(value))
  .gt_design_abort(label, " must be 'complete', 'additive', or an integer from 1 to ", n, ".")
}

.gt_design_subsets <- function(values, order, max_terms) {
  count <- sum(choose(length(values), seq_len(order)))
  if (!is.finite(count) || count > max_terms) {
    .gt_design_abort("Interaction expansion exceeds max_terms; use lower interaction orders or explicit random terms.")
  }
  unlist(lapply(seq_len(order), function(k)
    utils::combn(values, k, simplify = FALSE)), recursive = FALSE)
}

.gt_design_nested <- function(nested, facets, crossed) {
  children <- setdiff(facets, crossed)
  if (is.null(nested)) nested <- list()
  if (!is.list(nested) || (length(nested) &&
      (is.null(names(nested)) || anyNA(names(nested)) || anyDuplicated(names(nested))))) {
    .gt_design_abort("nested must be a named list mapping child facets to parent facets.")
  }
  if (length(intersect(names(nested), crossed)))
    .gt_design_abort("A crossed facet cannot also be a nested child.")
  if (!setequal(names(nested), children))
    .gt_design_abort("nested must specify every non-crossed facet exactly once and no other facet.")
  nested <- nested[children]
  for (child in children) {
    parents <- .gt_design_names(nested[[child]], paste0("Parents of ", child))
    if (any(!parents %in% facets))
      .gt_design_abort("Nested parents must be instrumentation facets; unknown parent or object-level nesting supplied for ", child, ".")
    if (child %in% parents) .gt_design_abort("A facet cannot be nested within itself: ", child, ".")
    nested[[child]] <- facets[facets %in% parents]
  }
  expanded <- list()
  resolve <- function(node, active = character()) {
    if (node %in% active) .gt_design_abort("Cycle detected in nested facet relationships.")
    if (node %in% crossed) return(node)
    if (!is.null(expanded[[node]])) return(expanded[[node]])
    members <- unique(c(node, unlist(lapply(nested[[node]], resolve,
                                           active = c(active, node)), use.names = FALSE)))
    members <- facets[facets %in% members]
    expanded[[node]] <<- members
    members
  }
  groups <- setNames(lapply(children, resolve), children)
  list(parents = nested, members = groups)
}

.gt_design_formula_terms <- function(random, max_terms) {
  # Deliberately walk a small formula grammar without evaluating supplied code.
  if (!inherits(random, "formula") || length(random) != 2L)
    .gt_design_abort("random must be a one-sided grouping-term formula or a character vector.")
  compact <- function(groups) {
    if (!length(groups)) return(groups)
    groups <- lapply(groups, unique)
    keys <- vapply(groups, function(x) paste(sort(x), collapse = ":"), character(1))
    groups <- groups[!duplicated(keys)]
    if (length(groups) > max_terms) .gt_design_abort("Formula expansion exceeds max_terms.")
    groups
  }
  product <- function(left, right) {
    if (!length(left) || !length(right)) return(list())
    if (length(left) * length(right) > max_terms)
      .gt_design_abort("Formula expansion exceeds max_terms.")
    compact(unlist(lapply(left, function(a) lapply(right, function(b) unique(c(a, b)))),
                   recursive = FALSE))
  }
  walk <- function(node) {
    if (is.symbol(node)) return(list(as.character(node)))
    if (is.numeric(node) && length(node) == 1L && node %in% c(0, 1)) return(list())
    if (!is.call(node)) .gt_design_abort("Unsupported expression in random formula.")
    op <- as.character(node[[1L]])
    if (length(op) != 1L) .gt_design_abort("Unsupported call in random formula.")
    if (op == "(" && length(node) == 2L) return(walk(node[[2L]]))
    if (op == "+" && length(node) == 2L) return(walk(node[[2L]]))
    if (!op %in% c("+", ":", "*") || length(node) != 3L)
      .gt_design_abort("Only names, '+', ':', '*', parentheses, and 0/1 are allowed in random; use nested for nesting.")
    left <- walk(node[[2L]])
    right <- walk(node[[3L]])
    if (op == "+") return(compact(c(left, right)))
    interaction <- product(left, right)
    if (op == ":") return(interaction)
    compact(c(left, right, interaction))
  }
  walk(random[[2L]])
}

# Construct a flexible G-theory random-source specification
#
# The object of measurement is separate from the N instrumentation facets.
# Choose any nonempty subset as crossed roots and explicitly declare the
# remaining facets' nesting parents. Nesting scopes instrumentation within
# instrumentation; these groups remain shared across objects. This constructor
# validates the specification only. It does not inspect data or fit a model.
#
# object: One object-of-measurement column name.
# facets: Unique instrumentation column names, excluding the object.
# crossed: Any nonempty subset of facets. Defaults to all facets.
# nested: Named list mapping each non-crossed facet to its parent facets.
#   Multiple parents mean their joint group. Ancestors are expanded recursively;
#   input list order does not define nesting. Object-level nesting is unsupported
#   in this automatic generator; use an explicit custom specification if needed.
# item_interactions: "complete", "additive", or a maximum number of
#   crossed facets in an object interaction. "additive" adds only object-by-
#   individual-crossed-facet interactions. The object is not counted in the order.
# instrument_interactions: "complete", "additive", or maximum interaction
#   order among crossed instrumentation facets. Does not remove declared nested
#   components. Instrument interactions and object interactions are independent.
# item_nested: Names of nested children whose full ancestor-expanded
#   groups also interact with the object. Does not imply ancestor object terms.
# random: Optional explicit one-sided formula or character vector of
#   grouping terms. Cannot be combined with explicit automatic selector options.
#   Formula grammar is restricted to names, +, :, *, parentheses, and 0/1.
# full_cell: Retain the object-by-all-facets source when the requested
#   expansion contains it. FALSE removes exactly that one term and changes
#   nothing else, which is how a binary/ordinal study with one observation per
#   cell declares the same design without an unidentified observation-level
#   source. Combinable with random.
# replicates: Declared observations per complete object-by-facets cell.
#   Requested sources are retained here. Fitting validates observed cell counts
#   and resolves any residual alias according to the response family.
# max_terms: Upper bound on source expansion, checked before allocation.
# Returns: A gt_design object retaining all requested terms, expanded nested
#   groups, and pending family-specific alias and data validation metadata.
gt_design <- function(object, facets, crossed = facets, nested = NULL,
                      item_interactions = "complete",
                      instrument_interactions = "complete",
                      item_nested = character(), random = NULL,
                      full_cell = TRUE, replicates = 1L, max_terms = 4096L) {
  custom <- !is.null(random)
  explicit_selectors <- !missing(crossed) || !missing(nested) ||
    !missing(item_interactions) || !missing(instrument_interactions) || !missing(item_nested)
  if (custom && explicit_selectors)
    .gt_design_abort("Use either random or the automatic crossed/nested/interaction selectors, not both.")
  if (!is.logical(full_cell) || length(full_cell) != 1L || is.na(full_cell))
    .gt_design_abort("full_cell must be TRUE or FALSE.")
  object <- .gt_design_names(object, "object")
  if (length(object) != 1L) .gt_design_abort("object must name one column.")
  facets <- .gt_design_names(facets, "facets")
  if (object %in% facets) .gt_design_abort("facets must exclude the object of measurement.")
  integer_scalar <- function(x) is.numeric(x) && length(x) == 1L &&
    !is.na(x) && is.finite(x) && x >= 1 && x == floor(x) && x <= .Machine$integer.max
  if (!integer_scalar(replicates)) .gt_design_abort("replicates must be a positive integer.")
  if (!integer_scalar(max_terms)) .gt_design_abort("max_terms must be a positive integer.")
  variables <- c(object, facets)
  notes <- c("Specification only: actual data balance, level counts, nesting, kernel rank, and replication have not been validated.")
  expanded <- list(parents = list(), members = list())
  orders <- c(instrument = NA_integer_, item = NA_integer_)
  if (custom) {
    if (inherits(random, "formula")) {
      groups <- .gt_design_formula_terms(random, max_terms)
    } else {
      if (!is.character(random) || !length(random) || anyNA(random) ||
          any(!nzchar(trimws(random)))) .gt_design_abort("random must contain nonempty grouping terms.")
      if (length(random) > max_terms) .gt_design_abort("Explicit terms exceed max_terms.")
      groups <- lapply(random, function(term) {
        parts <- trimws(strsplit(term, ":", fixed = TRUE)[[1L]])
        if (!length(parts) || any(!nzchar(parts)) || anyDuplicated(parts) ||
            grepl(":$", trimws(term))) .gt_design_abort("Invalid grouping term: ", term, ".")
        parts
      })
    }
    crossed <- character()
    construction <- "custom"
    notes <- c(notes, "Custom source terms do not infer physical crossing or nesting; the sampling design requires a separate data check.")
  } else {
    crossed <- .gt_design_names(crossed, "crossed")
    if (any(!crossed %in% facets)) .gt_design_abort("crossed must be a subset of facets.")
    crossed <- facets[facets %in% crossed]
    item_nested <- .gt_design_names(item_nested, "item_nested", allow_empty = TRUE)
    expanded <- .gt_design_nested(nested, facets, crossed)
    if (any(!item_nested %in% names(expanded$parents)))
      .gt_design_abort("item_nested must name declared nested children.")
    orders <- c(instrument = .gt_design_order(instrument_interactions, length(crossed), "instrument_interactions"),
                item = .gt_design_order(item_interactions, length(crossed), "item_interactions"))
    instrument_count <- sum(choose(length(crossed), seq_len(orders[["instrument"]])))
    item_count <- sum(choose(length(crossed), seq_len(orders[["item"]])))
    total <- 1 + instrument_count + item_count + length(expanded$parents) + length(item_nested)
    if (!is.finite(total) || total > max_terms)
      .gt_design_abort("Interaction expansion exceeds max_terms; reduce interaction orders or supply explicit random terms.")
    instrument <- .gt_design_subsets(crossed, orders[["instrument"]], max_terms)
    item <- lapply(.gt_design_subsets(crossed, orders[["item"]], max_terms),
                   function(x) c(object, x))
    extensions <- lapply(expanded$members[item_nested], function(x) c(object, x))
    groups <- c(list(object), instrument, unname(expanded$members), item, unname(extensions))
    construction <- if (length(expanded$parents)) "crossed_nested" else "crossed"
    if (length(expanded$parents)) notes <- c(notes,
      "Nesting parents define instrumentation groups shared across objects; nested sibling interactions are not automatically included.")
  }
  unknown <- setdiff(unique(unlist(groups, use.names = FALSE)), variables)
  if (length(unknown)) .gt_design_abort("Unknown variables in random terms: ", paste(unknown, collapse = ", "), ".")
  groups <- lapply(groups, function(x) variables[variables %in% x])
  keys <- vapply(groups, paste, collapse = ":", FUN.VALUE = character(1))
  if (custom && is.character(random) && anyDuplicated(keys))
    .gt_design_abort("Duplicate grouping terms after canonical normalization.")
  keep <- !duplicated(keys)
  groups <- groups[keep]
  keys <- keys[keep]
  full_cell_term <- paste(variables, collapse = ":")
  if (!full_cell && full_cell_term %in% keys) {
    keep <- keys != full_cell_term
    groups <- groups[keep]
    keys <- keys[keep]
    notes <- c(notes, paste0("full_cell = FALSE removed the requested object-by-all-facets source ",
      full_cell_term, " before any data or family check. No other requested source changed."))
  }
  if (!length(keys)) .gt_design_abort("full_cell = FALSE removed every requested source; declare additional random terms.")
  if (!object %in% keys) .gt_design_abort("The object main-effect component is required.")
  if (length(keys) > max_terms) .gt_design_abort("Source terms exceed max_terms.")
  # Store deterministic order while preserving actual column-name identity.
  ord <- order(lengths(groups), keys)
  groups <- groups[ord]
  keys <- keys[ord]
  names(groups) <- keys
  all_term <- paste(variables, collapse = ":")
  potential_alias <- if (replicates == 1L) intersect(keys, all_term) else character()
  if (length(potential_alias)) notes <- c(notes,
    paste0("Requested full-cell source ", all_term,
           " requires family-specific resolution after observed replication is checked."))
  direct <- if (custom) facets[vapply(facets, function(f)
    paste(object, f, sep = ":") %in% keys, logical(1))] else crossed
  structure(list(
    object = object, facets = facets, n_facets = length(facets),
    crossed = crossed, direct_facets = direct, nested = expanded$parents,
    nested_groups = vapply(expanded$members, paste, collapse = ":", FUN.VALUE = character(1)),
    item_nested = if (custom) character() else item_nested, full_cell = full_cell,
    interaction_orders = orders, terms_requested = keys,
    terms = keys, term_members = groups, term_members_requested = groups,
    potential_aliases = potential_alias, alias_resolution = "pending_family_and_data",
    aliased_terms = character(), residual = "Residual", replicates = as.integer(replicates),
    construction = construction, validated_data = FALSE, notes = notes
  ), class = "gt_design")
}

# Resolve statistical aliases only after the observation family and actual
# replication are known. Reconstruct from requested terms to make this
# idempotent, including when a fitted design is reused with another family.
.gt_resolve_design <- function(data, design, family) {
  variables <- c(design$object, design$facets)
  frequencies <- table(.gt_tuple_key(data, variables))
  if (any(frequencies != design$replicates))
    stop("Observed within-cell replication does not match declared replicates. Supply the correct replication or an explicit replicate facet; incomplete whole cells are permitted for discrete fitting.", call. = FALSE)
  requested <- design$terms_requested
  members <- design$term_members_requested
  if (is.null(members)) members <- setNames(lapply(requested, function(x)
    strsplit(x, ":", fixed = TRUE)[[1L]]), requested)
  full <- paste(variables, collapse = ":")
  observation_source <- if (design$replicates == 1L) intersect(requested, full) else character()
  if (family != "gaussian" && length(observation_source))
    stop("Requested observation-level source '", observation_source,
      "' is unsupported for discrete outcomes with one observation per cell; it cannot be silently combined with an identified discrete residual. ",
      "It is not removed automatically because dropping a source changes the model. ",
      "Add full_cell = FALSE to the same gt_design() call to drop exactly this source and keep every other requested source, ",
      "or declare the reduced model explicitly, for example ",
      "gt_design('item', 'rater', random = ~ item + rater); adapt names and retain the interactions required by your study.", call. = FALSE)
  design$aliased_terms <- if (family == "gaussian") observation_source else character()
  design$terms <- setdiff(requested, design$aliased_terms)
  design$term_members <- members[design$terms]
  design$alias_resolution <- if (length(design$aliased_terms)) "gaussian_full_cell_combined_with_residual" else "no_residual_alias"
  design$replication_validated <- TRUE
  design$observed_replication <- unique(as.integer(frequencies))
  design$notes <- unique(c(design$notes, if (length(design$aliased_terms))
    "Gaussian full-cell source and free residual have identical observed kernels and are combined as Residual." else
    "No requested source was dropped for this observation family."))
  design
}

# Replace pending constructor notes only after an engine completes its data
# checks. The scope records what was checked without claiming identification.
.gt_design_validated <- function(design, scope) {
  pending <- c(
    "Specification only: actual data balance, level counts, nesting, kernel rank, and replication have not been validated.",
    "Custom source terms do not infer physical crossing or nesting; the sampling design requires a separate data check.",
    paste0("Requested full-cell source ", paste(c(design$object, design$facets), collapse = ":"),
      " requires family-specific resolution after observed replication is checked."))
  design$notes <- setdiff(design$notes, pending)
  if (identical(design$construction, "custom"))
    design$notes <- unique(c(design$notes,
      "Custom source terms do not infer physical crossing or nesting; sampling-design interpretation remains the user's responsibility."))
  design$validation_scope <- scope
  design$validated_data <- TRUE
  design
}
