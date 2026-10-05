# Installed checks for batch declarations: what may be declared, how a
# declaration is audited against the data, and that declaring one changes no
# estimate in this version.
library(Gtheory4LLM)
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
expect_error <- function(expr, pattern, label) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  expect(inherits(error, "error") && grepl(pattern, conditionMessage(error), fixed = TRUE), label)
}
holds <- function(object, sentinel)
  length(grepRaw(charToRaw(sentinel), serialize(object, NULL), fixed = TRUE)) > 0L

# --- the declaration ----------------------------------------------------------
plain <- gt_batch(20)
expect(inherits(plain, "gt_batch") && identical(plain$size, 20L) && is.null(plain$order) &&
         is.null(plain$by) && identical(plain$sequential, 0L) && identical(plain$neighbor, 0L),
       "a bare declaration has both positional patterns off")
expect(grepl("equally", plain$assumption, fixed = TRUE) &&
         !grepl("Sequential", plain$assumption, fixed = TRUE) &&
         !grepl("Neighbour", plain$assumption, fixed = TRUE),
       "the default assumption is equal dependence within a call")
reach <- gt_batch(20, order = "position", by = "evaluator", sequential = 3, neighbor = TRUE)
expect(identical(reach$sequential, 3L) && identical(reach$neighbor, 19L),
       "a reach is stored in positions, and TRUE is the whole call")
expect(grepl("up to 3 positions submitted before it", reach$assumption, fixed = TRUE) &&
         grepl("within 19 positions", reach$assumption, fixed = TRUE),
       "each declared pattern is stated in the assumption with its reach")
expect(identical(gt_batch(5, sequential = TRUE)$sequential, 4L) &&
         identical(gt_batch(5, neighbor = 1)$neighbor, 1L), "reaches run from 1 to size - 1")
for (bad in list(1, 0, 2.5, NA, "20", c(2, 3), Inf))
  expect_error(gt_batch(bad), "size must be one integer of at least 2", "an invalid size is refused")
for (bad in list(20, 0, 2.5, NA, "2", c(1, 2)))
  expect_error(gt_batch(20, sequential = bad), "sequential must be TRUE, FALSE, or a whole number",
               "a sequential reach must be less than the batch size")
expect_error(gt_batch(20, neighbor = 20), "from 1 to 19", "a neighbour reach must be less than the batch size")
expect_error(gt_batch(20, order = c("a", "b")), "order must be NULL or one column name", "order names one column")
expect_error(gt_batch(20, by = ""), "by must be NULL or one column name", "by names one facet")

# --- carried by the design ----------------------------------------------------
bare <- gt_design("item", c("evaluator", "prompt"))
expect(!"batch" %in% names(bare), "a design without a declaration is the object it always was")
declared <- gt_design("item", c("evaluator", "prompt"), batch = gt_batch(20, by = "evaluator"))
expect(identical(declared$batch$size, 20L) && identical(declared$terms, bare$terms) &&
         identical(declared$term_members, bare$term_members),
       "a declaration is carried by the design and changes no source term")
expect(any(grepl("still treat items in one call as independent", declared$notes, fixed = TRUE)),
       "a declaring design says the estimates do not use it yet")
expect_error(gt_design("item", "evaluator", batch = list(size = 20)), "created by gt_batch()",
             "only a gt_batch object is accepted")
expect_error(gt_design("item", "evaluator", batch = gt_batch(20, by = "prompt")),
             "must name a declared instrumentation facet", "by must be a facet of the design")
expect_error(gt_design("item", "evaluator", batch = gt_batch(20, order = "item")),
             "other than the object and the facets", "order is not a design column")

# --- audited by preflight -----------------------------------------------------
d <- expand.grid(item = paste0("BATCH_ITEM_", sprintf("%02d", 1:40)), evaluator = 1:3, prompt = 1:2,
                 stringsAsFactors = FALSE)
d$score <- sin(seq_len(40))[match(d$item, unique(d$item))] + d$evaluator / 5 +
  cos(match(d$item, unique(d$item)) * d$prompt) / 4
audit <- function(data, batch, ...) gt_preflight(data, "score",
  gt_design("item", c("evaluator", "prompt"), batch = batch), ...)$batch_audit
a <- audit(d, gt_batch(20, by = "evaluator"))
expect(identical(a$items, 40L) && identical(a$batches, 2L) && identical(a$conditions, 6L) && a$calls == 12 &&
         isTRUE(a$equal_sized) && isTRUE(a$fixed_order) && isTRUE(a$consistent) && !length(a$problems) &&
         identical(a$by_levels, 3L),
       "the audit counts items, batches, conditions and calls")
expect(isTRUE(a$stored_rows$checked) && identical(a$stored_rows$batches_agree, 6L) &&
         identical(a$stored_rows$order_agrees, 6L),
       "rows stored call by call agree with the declared batches and their order")
expect(identical(a$examples$batch, rep(1L, 10)) && identical(a$examples$position, 1:10) &&
         identical(a$examples$item, sprintf("BATCH_ITEM_%02d", 1:10)),
       "examples list items in batch and position order, bounded by max_examples")
# An explicit order column decides the batches, whatever order the rows are in.
d$sent <- 41 - match(d$item, unique(d$item))
b <- audit(d, gt_batch(20, order = "sent"))
expect(isTRUE(b$consistent) && identical(b$examples$item[[1L]], "BATCH_ITEM_40") &&
         identical(b$stored_rows$batches_agree, 6L) && identical(b$stored_rows$order_agrees, 0L),
       "an order column defines batches and positions; stored rows then hold the batches in another order")
shuffled <- d[sample(nrow(d)), ]
s <- audit(shuffled, gt_batch(20, order = "sent"))
expect(isTRUE(s$consistent) && s$stored_rows$batches_agree < 6L,
       "rows not stored call by call are reported as not agreeing, without failing the declaration")
# Declarations that do not describe the data are reported, not repaired.
five <- d[d$item %in% unique(d$item)[1:35], ]
u <- audit(five, gt_batch(20))
expect(!u$equal_sized && !u$consistent && identical(u$last_batch_size, 15L) &&
         any(grepl("do not divide into calls of 20", u$problems, fixed = TRUE)),
       "items that do not divide into equal calls are reported")
moving <- d; moving$sent[moving$evaluator == 2] <- rev(moving$sent[moving$evaluator == 2])
m <- audit(moving, gt_batch(20, order = "sent"))
expect(!m$fixed_order && !m$consistent && is.null(m$examples) &&
         any(grepl("more than one order value", m$problems, fixed = TRUE)),
       "an order that changes between conditions is reported as outside this version")
tied <- d; tied$sent[tied$item == "BATCH_ITEM_02"] <- tied$sent[tied$item == "BATCH_ITEM_01"][[1L]]
expect(any(grepl("share an order value", audit(tied, gt_batch(20, order = "sent"))$problems, fixed = TRUE)),
       "tied order values are reported")
expect_error(audit(d, gt_batch(20, order = "absent")), "is not in the data", "a missing order column is an error")
text_order <- d; text_order$sent <- as.character(text_order$sent)
expect_error(audit(text_order, gt_batch(20, order = "sent")), "must be numeric", "the order column is numeric")
quiet <- gt_preflight(d, "score", gt_design("item", c("evaluator", "prompt"), batch = gt_batch(20)),
                      max_examples = 0L)
expect(identical(nrow(quiet$batch_audit$examples), 0L) && !holds(quiet$batch_audit, "BATCH_ITEM_"),
       "max_examples = 0 keeps item identifiers out of the batch audit")

# --- changes no estimate ------------------------------------------------------
without <- gt_preflight(d, "score", gt_design("item", c("evaluator", "prompt")))
with <- gt_preflight(d, "score", gt_design("item", c("evaluator", "prompt"), batch = gt_batch(20)))
expect(is.null(without$batch_audit) && !any(grepl("batch", without$notes, fixed = TRUE)),
       "a design without a declaration has no batch audit and no batch note")
expect(identical(with$checks, without$checks) && identical(with$fitting_feasible, without$fitting_feasible) &&
         identical(with$sources, without$sources) && identical(with$panel_audit, without$panel_audit),
       "the audit enters no check and changes no other part of the preflight report")
output <- capture.output(print(with))
expect(any(grepl("Declared calls: 2 batches of 20 items x 6 conditions = 12 calls", output, fixed = TRUE)),
       "the printed report states the declared calls")
set.seed(4040)
g <- expand.grid(item = 1:40, evaluator = 1:4, prompt = 1:3)
g$score <- rnorm(40)[g$item] + rnorm(4, sd = .5)[g$evaluator] + rnorm(3, sd = .3)[g$prompt] + rnorm(nrow(g), sd = .7)
control <- gt_control(gaussian = list(retry_seed = 42, threads = 1L))
fit_plain <- gt_fit(g, "score", gt_design("item", c("evaluator", "prompt")), control = control)
fit_batch <- gt_fit(g, "score", gt_design("item", c("evaluator", "prompt"),
  batch = gt_batch(20, by = "evaluator", sequential = 2, neighbor = 3)), control = control)
expect(identical(fit_batch$covariance_components, fit_plain$covariance_components) &&
         identical(fit_batch$minus2loglik, fit_plain$minus2loglik) &&
         identical(gt_reliability(fit_batch)$per_trait, gt_reliability(fit_plain)$per_trait),
       "declaring a batch changes no component, likelihood or coefficient")
expect(any(grepl("still treat items in one call as independent", gt_diagnostics(fit_batch)$notes, fixed = TRUE)) &&
         !any(grepl("batch", gt_diagnostics(fit_plain)$notes, fixed = TRUE)),
       "a fit from a declaring design carries the note; one without does not")
expect(identical(fit_batch$design$batch$sequential, 2L) && identical(fit_batch$design$batch$neighbor, 3L),
       "the declaration survives fitting")
# --- every outcome type, one outcome or several ---------------------------------
# The declaration and its audit belong to the design, not to an outcome family:
# binary, ordinal and unordered outcomes, alone or jointly, get the same audit
# as a continuous one, and a declaration changes no discrete estimate either.
set.seed(808)
k <- expand.grid(item = 1:20, rater = 1:4)
signal <- rnorm(20)[k$item]
k$score <- signal + rnorm(nrow(k))
k$flag <- as.integer(signal + rnorm(nrow(k)) > 0)
k$grade <- ordered(cut(signal + rnorm(nrow(k)), c(-Inf, -.5, .5, Inf), labels = c("low", "mid", "high")))
k$kind <- factor(c("a", "b", "c")[1L + (k$item + k$rater) %% 3L])
calls <- gt_batch(10, by = "rater", sequential = 2, neighbor = 3)
with_batch <- gt_design("item", "rater", full_cell = FALSE, batch = calls)
without_batch <- gt_design("item", "rater", full_cell = FALSE)
reference <- gt_preflight(k, "score", gt_design("item", "rater", batch = calls))$batch_audit
cases <- list(
  binary = list("flag", gt_family("binary")),
  ordinal = list("grade", gt_family("ordinal")),
  categorical = list("kind", gt_family("categorical")),
  joint = list(c("flag", "grade"), list(flag = gt_family("binary"), grade = gt_family("ordinal"))))
for (label in names(cases)) {
  outcomes <- cases[[label]][[1L]]; family <- cases[[label]][[2L]]
  audited <- gt_preflight(k, outcomes, with_batch, family)$batch_audit
  expect(identical(audited, reference) && identical(audited$batches, 2L) && audited$calls == 8,
         paste("the audit is the same for", label, "outcomes as for a continuous one"))
}
two_scores <- k; two_scores$second <- signal + rnorm(nrow(k))
expect(identical(gt_preflight(two_scores, c("score", "second"), gt_design("item", "rater", batch = calls),
                              covariance = "diagonal", residual = "diagonal")$batch_audit, reference),
       "the audit is the same for several continuous outcomes fitted jointly")
for (label in c("binary", "ordinal", "joint")) {
  outcomes <- cases[[label]][[1L]]; family <- cases[[label]][[2L]]
  plain_fit <- suppressWarnings(gt_fit(k, outcomes, without_batch, family))
  batch_fit <- suppressWarnings(gt_fit(k, outcomes, with_batch, family))
  expect(identical(batch_fit$covariance_components, plain_fit$covariance_components) &&
           identical(batch_fit$minus2loglik, plain_fit$minus2loglik) &&
           identical(batch_fit$numerically_accepted, plain_fit$numerically_accepted),
         paste("declaring a batch changes no", label, "estimate or acceptance decision"))
  expect(any(grepl("still treat items in one call as independent", gt_diagnostics(batch_fit)$notes, fixed = TRUE)),
         paste("a", label, "fit from a declaring design carries the note"))
}
cat("PASS: batch declarations are validated, carried, audited against the data, and change no estimate.\n")
