# Fuzzing the declaration parsers, the validators, and the resource guards.
#
# These are the surfaces a user reaches first and reaches wrong: a design
# formula, a family declaration, a control list, a set of weights. The contract
# fuzzed here is narrow and absolute: every call either returns a well-formed
# object of the documented class, or raises an error with a message that says
# something. Never a malformed object, never a silent NULL, never a bare
# warning standing in for a refusal, and never evaluating what was handed in.
#
# The inputs are pseudo-random but seeded, so a failure is reproducible.
library(Gtheory4LLM)

failures <- character()
record <- function(...) failures <<- c(failures, paste0(...))
describe <- function(x) paste(utils::capture.output(utils::str(x, max.level = 2L,
  give.attr = FALSE, vec.len = 3L)), collapse = " ")

# Every call must land in exactly one of: a value, or an error that explains
# itself. A warning is not a refusal, and neither is NULL.
resolve <- function(expression, label) {
  warned <- character()
  value <- withCallingHandlers(
    tryCatch(force(expression), error = function(e) {
      message <- conditionMessage(e)
      if (!is.character(message) || length(message) != 1L || !nzchar(trimws(message)))
        record(label, ": refused with an empty message")
      structure(list(message = message), class = "gt_fuzz_refusal")
    }),
    warning = function(w) {
      warned <<- c(warned, conditionMessage(w))
      invokeRestart("muffleWarning")
    })
  if (length(warned)) record(label, ": warned instead of deciding: ", warned[[1L]])
  value
}
refused <- function(value) inherits(value, "gt_fuzz_refusal")

# --- Random ingredients ------------------------------------------------------
set.seed(20260913)
HOSTILE <- list(
  NULL, NA, NA_character_, NA_integer_, character(), list(), "", " ", "  x  ",
  ":", "a:b", "Residual", c("a", "a"), c("a", NA), c("a", ""), 1, 1L, TRUE,
  list("a"), list(a = "b"), matrix(1:4, 2), factor("a"), sum, quote(x),
  strrep("x", 400L), "é中", c(a = "b"), Inf, -1, 0, 2.5, NaN)
pick <- function() HOSTILE[[sample.int(length(HOSTILE), 1L)]]
NAMES <- c("item", "rater", "occasion", "prompt", "Residual", "a:b", "", NA, "item")

# --- 1. gt_design accepts a valid design or explains its refusal -------------
valid_design <- function(value) {
  if (!inherits(value, "gt_design")) return("not a gt_design")
  if (!is.character(value$object) || length(value$object) != 1L || is.na(value$object) ||
      !nzchar(value$object)) return("object is not one name")
  if (!length(value$terms_requested)) return("no requested terms")
  if (!value$object %in% value$terms_requested) return("object main effect missing")
  if (anyDuplicated(value$terms_requested)) return("duplicate terms")
  if (!setequal(names(value$term_members_requested), value$terms_requested))
    return("term members do not match the terms")
  known <- c(value$object, value$facets)
  if (any(!unlist(value$term_members_requested, use.names = FALSE) %in% known))
    return("a term uses an undeclared variable")
  if (length(value$terms_requested) > 4096L) return("more terms than max_terms")
  NULL
}
# A harness that crashes on a violation says less than one that names it, so
# inspecting a returned object is itself guarded.
check_design <- function(value, label) {
  if (refused(value)) return(invisible(NULL))
  problem <- tryCatch(valid_design(value), error = function(e)
    paste("inspecting the returned object failed:", conditionMessage(e)))
  if (!is.null(problem)) record(label, ": accepted but ", problem)
  invisible(NULL)
}

for (trial in seq_len(400L)) {
  arguments <- list(object = pick(), facets = pick())
  if (runif(1) < .5) arguments$crossed <- pick()
  if (runif(1) < .4) arguments$nested <- pick()
  if (runif(1) < .3) arguments$item_interactions <- pick()
  if (runif(1) < .3) arguments$instrument_interactions <- pick()
  if (runif(1) < .3) arguments$full_cell <- pick()
  if (runif(1) < .3) arguments$replicates <- pick()
  if (runif(1) < .2) arguments$max_terms <- pick()
  label <- paste0("gt_design trial ", trial, " ", describe(arguments))
  value <- resolve(do.call(gt_design, arguments), label)
  check_design(value, label)
}

# Valid skeletons with hostile extras must still hold the invariants.
for (trial in seq_len(200L)) {
  facets <- unique(sample(c("rater", "occasion", "prompt"), sample.int(3L, 1L)))
  arguments <- list(object = "item", facets = facets)
  if (runif(1) < .5) arguments$crossed <- sample(c(facets, sample(NAMES, 1L)),
                                                 sample.int(length(facets) + 1L, 1L))
  if (runif(1) < .5) arguments$nested <- stats::setNames(
    as.list(sample(NAMES, length(facets), replace = TRUE)), facets)
  if (runif(1) < .5) arguments$item_interactions <- sample(
    list("complete", "additive", 1L, 2L, 99L, "other"), 1L)[[1L]]
  if (runif(1) < .3) arguments$item_nested <- sample(NAMES, 1L)
  if (runif(1) < .3) arguments$replicates <- sample(c(1L, 2L, 0L, -1L), 1L)
  label <- paste0("gt_design skeleton ", trial, " ", describe(arguments))
  value <- resolve(do.call(gt_design, arguments), label)
  check_design(value, label)
}

# --- 2. Formula grammar: parsed, never evaluated ----------------------------
# The formula walker exists so that a grouping term is read as structure rather
# than run as code. A call inside a formula must be refused, and must leave no
# trace of having been evaluated.
side_effect <- new.env()
side_effect$triggered <- FALSE
trip <- function(...) {
  side_effect$triggered <- TRUE
  quote(item)
}
formulas <- list(
  ~ item, ~ item + rater, ~ item * rater, ~ item:rater, ~ (item + rater):occasion,
  ~ item + 0, ~ item + 1, ~ 1, ~ 0, ~ .,
  ~ item / rater, ~ item ^ 2, ~ item - rater, ~ item | rater, ~ -item,
  ~ trip(), ~ item + trip(), ~ c(item, rater), ~ eval(quote(item)),
  ~ item + get("rater"), ~ `a:b`, ~ item + Residual, ~ unknown_variable,
  ~ item:item, ~ item + item, ~ ((item)), ~ item + (rater * occasion))
for (index in seq_along(formulas)) {
  label <- paste0("random formula ", index, ": ", paste(deparse(formulas[[index]]), collapse = ""))
  value <- resolve(gt_design("item", c("rater", "occasion"), random = formulas[[index]]), label)
  check_design(value, label)
}
if (side_effect$triggered)
  record("a formula term was evaluated instead of parsed: the walker must never call user code")

# Character grouping terms take the same contract.
for (trial in seq_len(150L)) {
  terms <- replicate(sample.int(4L, 1L),
    paste(sample(NAMES, sample.int(3L, 1L), replace = TRUE), collapse = ":"))
  label <- paste0("character terms ", trial, ": ", paste(terms, collapse = " | "))
  value <- resolve(gt_design("item", c("rater", "occasion"), random = terms), label)
  check_design(value, label)
}

# --- 3. Families, controls, and weights --------------------------------------
for (trial in seq_len(250L)) {
  arguments <- list(family = pick())
  if (runif(1) < .6) arguments$link <- pick()
  if (runif(1) < .6) arguments$levels <- pick()
  if (runif(1) < .4) arguments$reference <- pick()
  label <- paste0("gt_family trial ", trial, " ", describe(arguments))
  value <- resolve(do.call(gt_family, arguments), label)
  if (!refused(value)) {
    if (!inherits(value, "gt_family")) record(label, ": accepted but not a gt_family")
    else if (!value$family %in% c("gaussian", "binary", "ordinal", "categorical"))
      record(label, ": accepted an undeclared family")
    else if (length(value$link) != 1L || is.na(value$link))
      record(label, ": accepted without a link")
  }
}
for (trial in seq_len(250L)) {
  arguments <- list()
  if (runif(1) < .7) arguments$gaussian <- pick()
  if (runif(1) < .7) arguments$discrete <- pick()
  if (runif(1) < .7) arguments$retain <- pick()
  label <- paste0("gt_control trial ", trial, " ", describe(arguments))
  value <- resolve(do.call(gt_control, arguments), label)
  if (!refused(value)) {
    if (!inherits(value, "gt_control")) record(label, ": accepted but not a gt_control")
    else if (!is.logical(value$retain) || anyNA(value$retain) ||
             !setequal(names(value$retain), c("data", "model", "retry_log", "session")))
      record(label, ": accepted with an ill-formed retention record")
  }
}
for (trial in seq_len(150L)) {
  label <- paste0("gt_score trial ", trial)
  value <- resolve(gt_score(pick()), label)
  if (!refused(value)) {
    if (!inherits(value, "gt_score")) record(label, ": accepted but not a gt_score")
    else if (!is.numeric(value$weights) || any(!is.finite(value$weights)) ||
             is.null(names(value$weights)) || !any(value$weights != 0))
      record(label, ": accepted an unusable weight vector")
  }
}

# --- 4. Resource guards ------------------------------------------------------
# A guard must decide, not crash: either the report says the model is feasible,
# or it says which check blocked it. Limits are fuzzed, including absurd ones.
set.seed(5150)
guard_panel <- expand.grid(rater = factor(1:5), item = factor(1:12))
guard_panel$label <- rbinom(nrow(guard_panel), 1L, .5)
guard_design <- gt_design("item", "rater", full_cell = FALSE)
limits <- list(1L, 2L, 10L, 1000L, 1e9, 0, -1, NA, Inf, NaN, "many", TRUE, c(1, 2))
for (trial in seq_len(120L)) {
  control <- list()
  for (name in c("max_observations", "max_random_dimension", "max_parameters", "max_dense_bytes"))
    if (runif(1) < .6) control[[name]] <- limits[[sample.int(length(limits), 1L)]]
  label <- paste0("resource guard trial ", trial, " ", describe(control))
  value <- resolve(gt_preflight(guard_panel, "label", guard_design, gt_family("binary"),
                                control = gt_control(discrete = control)), label)
  if (!refused(value)) {
    if (!inherits(value, "gt_preflight")) record(label, ": accepted but not a gt_preflight")
    else if (!is.logical(value$fitting_feasible) || length(value$fitting_feasible) != 1L ||
             is.na(value$fitting_feasible))
      record(label, ": reported no feasibility decision")
    else if (!value$fitting_feasible && all(value$checks$passed))
      record(label, ": reported blocked without naming a failed check")
    else if (value$fitting_feasible && any(!value$checks$passed))
      record(label, ": reported feasible with a failed check")
  }
}

if (length(failures))
  stop(length(failures), " fuzzing failure(s):\n",
       paste0("- ", utils::head(failures, 20L), collapse = "\n"),
       if (length(failures) > 20L) "\n- ..." else "")
cat("PASS: parsers, validators, and resource guards decide cleanly on hostile input.\n")
