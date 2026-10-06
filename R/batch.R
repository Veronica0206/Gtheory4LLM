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
# Which items shared a call is either inferred or recorded. Without id the
# batches are cut from the item order, the same in every condition, which is
# all that data without a call column allow. With id the calls are read from
# the data, so they may differ between conditions and in size.
#
# size: Items per call. With id, the most a call may hold.
# order: Optional column giving the order in which items were submitted.
#   Without id: one distinct value per item, the same in every condition, and
#   NULL uses the order in which items first appear in the data. With id: the
#   position of each row's item in its call, and NULL uses the stored order of
#   the rows of each call.
# by: Optional instrumentation facet across whose levels the dependence may
#   differ, for example the evaluator.
# sequential: FALSE, or how many preceding items may affect an item. TRUE
#   means every preceding item in the call.
# neighbor: FALSE, or how many positions apart two items may be and still
#   affect each other. TRUE means any distance within the call.
# id: Optional column identifying the call that produced each row.
gt_batch <- function(size, order = NULL, by = NULL, sequential = FALSE, neighbor = FALSE,
                     id = NULL) {
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
  id <- one_name(id, "id")
  if (!is.null(id) && identical(id, order))
    stop("id and order must name different columns.", call. = FALSE)
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
                 id = id, assumption = paste(assumption, collapse = " ")), class = "gt_batch")
}

.gt_batch_order_values <- function(data, batch) {
  if (!batch$order %in% names(data))
    stop("The batch order column ", sQuote(batch$order), " is not in the data.", call. = FALSE)
  value <- data[[batch$order]]
  if (!is.numeric(value) || anyNA(value) || any(!is.finite(value)))
    stop("The batch order column must be numeric, finite and nonmissing.", call. = FALSE)
  value
}

# Which batch and position each item occupies when calls are not recorded.
#
# Returns the two per-row vectors when the declaration can be resolved, and the
# reasons when it cannot. A batch is fixed: the same items, in the same order,
# in every condition. The batches are cut from the items that are present, so
# an item removed after collection moves every later item up, unseen.
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
    value <- .gt_batch_order_values(data, batch)
    source <- paste("column", sQuote(batch$order))
    lowest <- tapply(value, code, min)
    highest <- tapply(value, code, max)
    varying <- sum(lowest != highest)
    if (varying) problems <- c(problems, paste0(varying, " item(s) have more than one order value, ",
      "so the order is not the same in every condition; record the calls in a column and name it in id"))
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

# Which call and position each row occupies when calls are recorded.
#
# The calls are read, not reconstructed, so they may hold different items in
# different conditions and fewer items than declared. What a recorded call
# cannot do is span conditions, hold an item twice, or exceed the declared size.
# Reading is still limited to the rows supplied: a call is known by the items
# of it that are present, a call with no row left is unknown, and a position is
# a rank among the items present, not the position at which an item was sent.
.gt_batch_recorded <- function(data, design, condition_code) {
  batch <- design$batch
  if (!batch$id %in% names(data))
    stop("The batch id column ", sQuote(batch$id), " is not in the data.", call. = FALSE)
  call <- data[[batch$id]]
  if (!is.atomic(call) || !is.null(dim(call)) || anyNA(call))
    stop("The batch id column must hold one nonmissing call identifier per row.", call. = FALSE)
  items <- data[[design$object]]
  item_code <- match(items, unique(items))
  call_code <- match(call, unique(call))
  n_calls <- max(call_code)
  size <- tabulate(call_code, n_calls)
  problems <- character()
  if (is.null(batch$order)) {
    position <- stats::ave(seq_along(call_code), call_code, FUN = seq_along)
    source <- paste("the stored order of the rows of each call in column", sQuote(batch$id))
  } else {
    value <- .gt_batch_order_values(data, batch)
    position <- as.integer(stats::ave(value, call_code,
      FUN = function(v) rank(v, ties.method = "first")))
    source <- paste("column", sQuote(batch$order), "within each call in column", sQuote(batch$id))
    tied <- sum(tapply(value, call_code, function(v) anyDuplicated(v) > 0L))
    if (tied) problems <- c(problems, paste0(tied, " call(s) hold two or more rows with one order value"))
  }
  spanning <- sum(tabulate(unique(cbind(call_code, condition_code))[, 1L], n_calls) > 1L)
  if (spanning) problems <- c(problems, paste0(spanning, " call(s) span more than one condition"))
  repeated <- length(unique(call_code[duplicated(cbind(call_code, item_code))]))
  if (repeated) problems <- c(problems, paste0(repeated, " call(s) hold an item more than once"))
  oversized <- sum(size > batch$size)
  if (oversized) problems <- c(problems, paste0(oversized, " call(s) hold more than the declared ",
    batch$size, " items; the largest holds ", max(size)))
  # A batch is a set of items submitted together; the same batch in the same
  # order may be submitted in many calls.
  by_position <- order(call_code, position)
  ordered <- vapply(split(item_code[by_position], call_code[by_position]),
    paste, character(1), collapse = ",")
  members <- vapply(split(item_code, call_code),
    function(i) paste(sort(i), collapse = ","), character(1))
  first <- !duplicated(call_code)
  call_condition <- condition_code[first][order(call_code[first])]
  layouts <- tapply(members, call_condition, function(m) paste(sort(unique(m)), collapse = "|"))
  list(problems = problems, source = source, items = max(item_code), item_code = item_code,
       call = call, call_code = call_code, position = position, sizes = size, calls = n_calls,
       batches = length(unique(members)), composition = match(members, unique(members)),
       fixed_composition = length(unique(layouts)) == 1L,
       fixed_order = length(unique(ordered)) == length(unique(members)))
}

# Can the declared batches enter the exact balanced Gaussian likelihood, and
# if so which batch and slot does each row occupy?
#
# The engine needs the calls to form a complete factorial with the facets: the
# same batches in every condition, every batch at the declared size, at least
# two batches, and one row in each cell. A declaration that does not meet this
# stays declared and unmodelled, with the reason. The slot is only a label
# for an item within its batch; the model gives it no effect of its own.
.gt_batch_model <- function(data, design) {
  batch <- design$batch
  no <- function(reason) list(modelled = FALSE, reason = reason)
  if (!identical(as.integer(design$replicates), 1L))
    return(no("the design declares more than one row in a cell"))
  conditions <- if (length(design$facets)) .gt_tuple_key(data, design$facets) else rep("1", nrow(data))
  if (is.null(batch$id)) {
    found <- .gt_batch_resolve(data, design)
    if (!found$resolved) return(no(paste(found$problems, collapse = "; ")))
    batch_code <- found$batch
  } else {
    found <- .gt_batch_recorded(data, design, match(conditions, unique(conditions)))
    if (length(found$problems)) return(no(paste(found$problems, collapse = "; ")))
    if (!found$fixed_composition) return(no("the recorded batches differ between conditions"))
    batch_code <- found$composition[found$call_code]
  }
  first <- !duplicated(found$item_code)
  sizes <- tabulate(batch_code[first])
  if (any(sizes != batch$size))
    return(no(paste0("not every batch holds the declared ", batch$size, " items")))
  if (length(sizes) < 2L) return(no("there are fewer than two batches"))
  # One slot per item, the same in every condition: its rank in its batch.
  slot_of_item <- integer(found$items)
  slot_of_item[found$item_code[first]] <- stats::ave(found$item_code[first], batch_code[first],
    FUN = function(i) rank(i, ties.method = "first"))
  list(modelled = TRUE, reason = NA_character_, term = .GT_CALL_TERM,
       batches = length(sizes), size = batch$size,
       calls = as.double(length(sizes)) * length(unique(conditions)),
       batch = batch_code, slot = as.integer(slot_of_item[found$item_code]))
}

# Describe a declared batch structure against the observed data.
#
# Counts and bounded examples only. Nothing here estimates dependence or
# changes a fit: it says whether the declaration can be laid over these data,
# and, for inferred batches whose rows are stored call by call, whether that
# storage agrees with it. Inferred membership is not evidence about how the
# data were collected.
.gt_batch_audit <- function(data, design, max_examples) {
  batch <- design$batch
  conditions <- if (length(design$facets)) .gt_tuple_key(data, design$facets) else rep("1", nrow(data))
  condition_code <- match(conditions, unique(conditions))
  n_conditions <- max(condition_code)
  recorded <- !is.null(batch$id)
  fields <- c(if (recorded) "call" else "batch", "position")
  metadata <- stats::setNames(fields, fields)
  # Keep the established names unless an object column would duplicate one.
  # The mapping lets callers retrieve the audit fields without guessing which
  # prefix was needed, while the object's own column keeps its original name.
  if (design$object %in% metadata) {
    prefix <- ".gt_"
    while (design$object %in% paste0(prefix, fields)) prefix <- paste0(".", prefix)
    metadata[] <- paste0(prefix, fields)
  }
  stored <- list(checked = FALSE, conditions = n_conditions, batches_agree = NA_integer_,
    order_agrees = NA_integer_,
    scope = if (recorded) "Not checked: the calls are recorded, so stored rows decide nothing." else
      "Checked only when every condition holds each item once; rows must be stored call by call for agreement to mean anything.")
  examples <- NULL
  if (recorded) {
    found <- .gt_batch_recorded(data, design, condition_code)
    problems <- found$problems
    n_items <- found$items
    n_batches <- found$batches
    calls <- as.double(found$calls)
    smallest <- min(found$sizes)
    below <- as.double(sum(found$sizes < batch$size))
    equal <- all(found$sizes == batch$size)
    fixed_composition <- found$fixed_composition
    fixed_order <- found$fixed_order
    shown <- utils::head(order(found$call_code, found$position), max_examples)
    examples <- data.frame(item = data[[design$object]][shown], call = found$call[shown],
      position = found$position[shown], stringsAsFactors = FALSE)
    if (is.factor(examples$call)) examples$call <- droplevels(examples$call)
    membership_scope <- paste("Calls are the distinct identifiers in column", sQuote(batch$id),
      "among the rows supplied, and are as reliable as that column.",
      "A call is counted by the items of it that are present, which may be fewer than it was sent:",
      "a call sent short and a call that lost rows after collection look the same.",
      "A call with no row left is not counted.")
  } else {
    found <- .gt_batch_resolve(data, design)
    problems <- found$problems
    n_items <- found$items
    n_batches <- as.integer(ceiling(n_items / batch$size))
    smallest <- as.integer(n_items - (n_batches - 1L) * batch$size)
    equal <- n_items %% batch$size == 0L
    # One call per batch, condition and declared repeat: a call holds an item
    # once, so each repeat of a cell needs a call of its own.
    per_batch <- as.double(n_conditions) * design$replicates
    calls <- n_batches * per_batch
    below <- if (equal) 0 else per_batch
    fixed_composition <- fixed_order <- found$resolved
    if (found$resolved) {
      per_condition <- tabulate(condition_code)
      if (all(per_condition == n_items) && !anyDuplicated(cbind(condition_code, found$item_code))) {
        # Rows in stored order within each condition, cut into consecutive blocks
        # of the declared size. A block agrees when it holds one declared batch,
        # and its order agrees when positions run 1, 2, ... within it.
        within <- stats::ave(seq_along(condition_code), condition_code, FUN = seq_along)
        block <- (within - 1L) %/% batch$size
        key <- paste(condition_code, block)
        one_batch <- tapply(found$batch, key, function(b) length(unique(b)) == 1L)
        in_order <- tapply(found$position, key, function(p) all(diff(p) == 1L) && p[[1L]] == 1L)
        block_condition <- tapply(condition_code, key, function(k) k[[1L]])
        stored$checked <- TRUE
        stored$batches_agree <- sum(tapply(one_batch, block_condition, all))
        stored$order_agrees <- sum(tapply(one_batch & in_order, block_condition, all))
      }
      first <- !duplicated(found$item_code)
      shown <- utils::head(order(found$batch[first], found$position[first]), max_examples)
      examples <- data.frame(item = data[[design$object]][first][shown],
        batch = found$batch[first][shown], position = found$position[first][shown],
        stringsAsFactors = FALSE)
    }
    membership_scope <- paste("Batches are cut from the item order of the rows supplied; no recorded call was read.",
      "Items removed after collection, calls of other sizes and regrouping between conditions cannot be detected.",
      "Record the call in a column and name it in id to audit them.")
  }
  if (!is.null(examples)) {
    if (is.factor(examples$item)) examples$item <- droplevels(examples$item)
    names(examples) <- c(design$object, unname(metadata))
    rownames(examples) <- NULL
  }
  list(size = batch$size, membership = if (recorded) "recorded" else "inferred",
    membership_scope = membership_scope, id = batch$id, order = found$source, by = batch$by,
    sequential = batch$sequential, neighbor = batch$neighbor,
    assumption = batch$assumption, items = n_items, batches = n_batches,
    conditions = n_conditions, replicates = design$replicates, calls = calls,
    equal_sized = equal, calls_below_size = below, smallest_observed_call = smallest,
    position_scope = paste("Positions are ranks among the items present in a call.",
      "They are the positions at which items were sent only if no item was removed after collection;",
      "gaps in an order column are not kept."),
    by_levels = if (is.null(batch$by)) NA_integer_ else length(unique(data[[batch$by]])),
    fixed_composition = fixed_composition, fixed_order = fixed_order,
    consistent = !length(problems), problems = problems, stored_rows = stored, examples = examples,
    metadata_columns = metadata,
    examples_shown = if (is.null(examples)) 0L else nrow(examples), examples_limit = max_examples,
    scope = paste("A declared structure compared with the observed items and conditions.",
      "It estimates no dependence itself; model says whether a fit of these data would.",
      "Examples list item identifiers, and call identifiers when calls are recorded; they are bounded by max_examples."))
}
