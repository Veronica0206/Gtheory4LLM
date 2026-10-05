# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Declared batches: which items one call annotated together, and in what order.

# Declare that items were annotated several to a call
#
# Without a declaration every function treats items as independent given the
# declared sources, which is what the package has always done. A declaration
# says that items submitted in one call are not: by default they are assumed
# to affect each other equally, whatever their order.
#
# That the dependence varies with position in the call is a separate, optional
# claim, and two patterns fit it. In a sequential pattern an item is affected
# by items submitted before it. In a neighbour pattern items close together
# affect each other, in either direction. Data with a fixed order cannot always
# tell the two apart, so each is declared on its own, both are off by default,
# and declaring one asks for it to be examined rather than asserting it. Each
# takes a reach: how many positions the influence extends, which is at most
# one less than the number of items in a call.
#
# size: Items per call.
# order: Optional column giving the order in which items were submitted. One
#   distinct value per item, the same in every condition. NULL uses the order
#   in which items first appear in the data.
# by: Optional instrumentation facet across whose levels the dependence may
#   differ, for example the evaluator.
# sequential: FALSE, or how many preceding items may affect an item. TRUE
#   means every preceding item in the call.
# neighbor: FALSE, or how many positions apart two items may be and still
#   affect each other. TRUE means any distance within the call.
gt_batch <- function(size, order = NULL, by = NULL, sequential = FALSE, neighbor = FALSE) {
  if (!is.numeric(size) || length(size) != 1L || is.na(size) || !is.finite(size) ||
      size != floor(size) || size < 2 || size > .Machine$integer.max)
    stop("size must be one integer of at least 2, the number of items in a call. ",
         "Leave batch undeclared for independent items.", call. = FALSE)
  size <- as.integer(size)
  one_name <- function(x, label) {
    if (is.null(x)) return(NULL)
    if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x) || trimws(x) != x)
      stop(label, " must be NULL or one column name.", call. = FALSE)
    x
  }
  # A reach of zero is the pattern switched off.
  reach <- function(x, label) {
    if (is.logical(x) && length(x) == 1L && !is.na(x)) return(if (x) size - 1L else 0L)
    if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) || x != floor(x) ||
        x < 1 || x > size - 1L)
      stop(label, " must be TRUE, FALSE, or a whole number of positions from 1 to ", size - 1L,
           ", one less than the number of items in a call.", call. = FALSE)
    as.integer(x)
  }
  order <- one_name(order, "order")
  by <- one_name(by, "by")
  sequential <- reach(sequential, "sequential")
  neighbor <- reach(neighbor, "neighbor")
  positions <- function(k) if (k == 1L) "1 position" else paste(k, "positions")
  assumption <- c(
    "Items in one call may affect each other equally, whatever their order.",
    if (sequential) paste0("Sequential: an item may also be affected by up to ", positions(sequential),
      " submitted before it."),
    if (neighbor) paste0("Neighbour: items within ", positions(neighbor),
      " of each other may also affect each other, in either direction."),
    "Items in different calls are independent given the declared sources.")
  structure(list(size = size, order = order, by = by, sequential = sequential, neighbor = neighbor,
                 assumption = paste(assumption, collapse = " ")), class = "gt_batch")
}

# Which batch and position each item occupies, from the declared order.
#
# Returns the two per-row vectors when the declaration can be resolved, and the
# reasons when it cannot. A batch is fixed: the same items, in the same order,
# in every condition. An order that changes between conditions describes a
# different design, which this version does not audit.
.gt_batch_resolve <- function(data, design) {
  batch <- design$batch
  items <- data[[design$object]]
  code <- match(items, unique(items))
  n_items <- max(code)
  problems <- character()
  if (is.null(batch$order)) {
    rank <- seq_len(n_items)
    source <- "the order in which items first appear in the data"
  } else {
    if (!batch$order %in% names(data))
      stop("The batch order column ", sQuote(batch$order), " is not in the data.", call. = FALSE)
    value <- data[[batch$order]]
    if (!is.numeric(value) || anyNA(value) || any(!is.finite(value)))
      stop("The batch order column must be numeric, finite and nonmissing.", call. = FALSE)
    source <- paste("column", sQuote(batch$order))
    lowest <- tapply(value, code, min)
    highest <- tapply(value, code, max)
    varying <- sum(lowest != highest)
    if (varying) problems <- c(problems, paste0(varying, " item(s) have more than one order value, ",
      "so the order is not the same in every condition"))
    if (anyDuplicated(as.numeric(lowest))) problems <- c(problems,
      "two or more items share an order value")
    rank <- rank(as.numeric(lowest), ties.method = "first")
  }
  if (length(problems))
    return(list(resolved = FALSE, problems = problems, source = source, items = n_items))
  list(resolved = TRUE, problems = character(), source = source, items = n_items,
       batch = ((rank - 1L) %/% batch$size + 1L)[code],
       position = ((rank - 1L) %% batch$size + 1L)[code], item_code = code)
}

# Describe a declared batch structure against the observed data.
#
# Counts and bounded examples only. Nothing here estimates dependence or
# changes a fit: it says whether the declaration describes these data, and,
# where the rows are stored call by call, whether that storage agrees with it.
.gt_batch_audit <- function(data, design, max_examples) {
  batch <- design$batch
  resolved <- .gt_batch_resolve(data, design)
  conditions <- if (length(design$facets)) .gt_tuple_key(data, design$facets) else rep("1", nrow(data))
  n_conditions <- length(unique(conditions))
  n_batches <- as.integer(ceiling(resolved$items / batch$size))
  last <- as.integer(resolved$items - (n_batches - 1L) * batch$size)
  equal <- resolved$items %% batch$size == 0L
  problems <- c(resolved$problems, if (!equal) paste0("the ", resolved$items,
    " items do not divide into calls of ", batch$size, "; the last call holds ", last))
  stored <- list(checked = FALSE, conditions = n_conditions, batches_agree = NA_integer_,
    order_agrees = NA_integer_,
    scope = "Checked only when every condition holds each item once; rows must be stored call by call for agreement to mean anything.")
  examples <- NULL
  if (resolved$resolved) {
    per_condition <- tabulate(match(conditions, unique(conditions)))
    if (all(per_condition == resolved$items) && !anyDuplicated(paste(conditions, resolved$item_code))) {
      # Rows in stored order within each condition, cut into consecutive blocks
      # of the declared size. A block agrees when it holds one declared batch,
      # and its order agrees when positions run 1, 2, ... within it.
      condition_code <- match(conditions, unique(conditions))
      within <- stats::ave(seq_along(condition_code), condition_code, FUN = seq_along)
      block <- (within - 1L) %/% batch$size
      key <- paste(condition_code, block)
      one_batch <- tapply(resolved$batch, key, function(b) length(unique(b)) == 1L)
      in_order <- tapply(resolved$position, key, function(p) all(diff(p) == 1L) && p[[1L]] == 1L)
      block_condition <- tapply(condition_code, key, function(k) k[[1L]])
      stored$checked <- TRUE
      stored$batches_agree <- sum(tapply(one_batch, block_condition, all))
      stored$order_agrees <- sum(tapply(one_batch & in_order, block_condition, all))
    }
    first <- !duplicated(resolved$item_code)
    shown <- utils::head(order(resolved$batch[first], resolved$position[first]), max_examples)
    examples <- data.frame(item = data[[design$object]][first][shown],
      batch = resolved$batch[first][shown], position = resolved$position[first][shown],
      stringsAsFactors = FALSE)
    if (is.factor(examples$item)) examples$item <- droplevels(examples$item)
    names(examples)[[1L]] <- design$object
    rownames(examples) <- NULL
  }
  list(size = batch$size, order = resolved$source, by = batch$by,
    sequential = batch$sequential, neighbor = batch$neighbor,
    assumption = batch$assumption, items = resolved$items, batches = n_batches,
    equal_sized = equal, last_batch_size = last, conditions = n_conditions,
    calls = as.double(n_batches) * n_conditions,
    by_levels = if (is.null(batch$by)) NA_integer_ else length(unique(data[[batch$by]])),
    fixed_order = resolved$resolved, consistent = resolved$resolved && equal,
    problems = problems, stored_rows = stored, examples = examples,
    examples_shown = if (is.null(examples)) 0L else nrow(examples), examples_limit = max_examples,
    scope = paste("A declared structure compared with the observed items and conditions.",
      "It does not estimate dependence, and estimates in this version treat items as independent.",
      "Examples list item identifiers and are bounded by max_examples."))
}
