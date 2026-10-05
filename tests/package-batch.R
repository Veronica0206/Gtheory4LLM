# Installed checks for batch declarations: what may be declared, how inferred
# and recorded calls are audited against the data, that a Gaussian fit of equal
# fixed batches estimates one shared call effect, that any other declaration
# changes no estimate, and that every output says which of the two happened.
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
         is.null(plain$by) && identical(plain$sequential, 0L) && identical(plain$neighbor, 0L) &&
         is.null(plain$id),
       "a bare declaration has both positional patterns off and no recorded call column")
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
expect(identical(gt_batch(20, id = "call")$id, "call"), "id names the column that records the call")
expect_error(gt_batch(20, id = c("a", "b")), "id must be NULL or one column name", "id names one column")
expect_error(gt_batch(20, order = "sent", id = "sent"), "id and order must name different columns",
             "one column cannot be both the call and the order")

# --- carried by the design ----------------------------------------------------
bare <- gt_design("item", c("evaluator", "prompt"))
expect(!"batch" %in% names(bare), "a design without a declaration is the object it always was")
declared <- gt_design("item", c("evaluator", "prompt"), batch = gt_batch(20, by = "evaluator"))
expect(identical(declared$batch$size, 20L) && identical(declared$terms, bare$terms) &&
         identical(declared$term_members, bare$term_members),
       "a declaration is carried by the design and changes no source term")
expect(any(grepl("A Gaussian fit of equal fixed batches estimates one shared call effect", declared$notes, fixed = TRUE)) &&
         any(grepl("any other fit treats items in one call as independent", declared$notes, fixed = TRUE)),
       "a declaring design states when a fit uses the declaration")
expect_error(gt_design("item", "evaluator", batch = list(size = 20)), "created by gt_batch()",
             "only a gt_batch object is accepted")
expect_error(gt_design("item", "evaluator", batch = gt_batch(20, by = "prompt")),
             "must name a declared instrumentation facet", "by must be a facet of the design")
expect_error(gt_design("item", "evaluator", batch = gt_batch(20, order = "item")),
             "other than the object and the facets", "order is not a design column")
expect_error(gt_design("item", "evaluator", batch = gt_batch(20, id = "evaluator")),
             "id must be a column other than the object and the facets", "id is not a design column")

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
expect(identical(a$membership, "inferred") && grepl("cannot be detected", a$membership_scope, fixed = TRUE) &&
         isTRUE(a$fixed_composition) && a$calls_below_size == 0 && identical(a$smallest_observed_call, 20L),
       "batches cut from the item order are labelled as inferred, with what that cannot see")
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
# A short last call is a property of the data, not a mismatch.
five <- d[d$item %in% unique(d$item)[1:35], ]
u <- audit(five, gt_batch(20))
expect(!u$equal_sized && u$consistent && !length(u$problems) && identical(u$batches, 2L) &&
         identical(u$smallest_observed_call, 15L) && u$calls_below_size == 6 && u$calls == 12,
       "items that do not divide into equal calls leave a short last call, which is reported")
expect(any(grepl("2 batches of 20 items (the last holds 15) x 6 conditions = 12 calls",
                 capture.output(print(gt_preflight(five, "score",
                   gt_design("item", c("evaluator", "prompt"), batch = gt_batch(20))))), fixed = TRUE)),
       "the printed report states the short last call")
# Declarations that do not describe the data are reported, not repaired.
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

# --- inferred batches against recorded calls ----------------------------------
# Twelve items went out in three calls of four; four items were removed after
# collection. Cutting the eight that remain into fours finds two batches and
# nothing wrong, because nothing in the rows shows what was removed. The
# recorded calls show three batches, each with fewer items present than it
# was sent, and the audit does not claim to know how many it was sent.
history <- expand.grid(item = 1:12, rater = 1:3)
history$score <- sin(history$item * history$rater)
history$call <- paste0("CALL_SENTINEL_r", history$rater, "_c", (history$item - 1) %/% 4 + 1)
history$sent <- (history$item - 1) %% 4 + 1
kept <- history[!history$item %in% c(2, 6, 10, 12), ]
by_order <- gt_preflight(kept, "score", gt_design("item", "rater", batch = gt_batch(4)))$batch_audit
by_call <- gt_preflight(kept, "score", gt_design("item", "rater", batch = gt_batch(4, id = "call")))
expect(identical(by_order$membership, "inferred") && identical(by_order$batches, 2L) && by_order$calls == 6 &&
         isTRUE(by_order$consistent),
       "inferred batches cannot see items removed after collection, and are labelled as inferred")
r <- by_call$batch_audit
expect(identical(r$membership, "recorded") && identical(r$id, "call") && identical(r$batches, 3L) &&
         r$calls == 9 && !r$equal_sized && r$calls_below_size == 9 && identical(r$smallest_observed_call, 2L) &&
         isTRUE(r$fixed_composition) && isTRUE(r$fixed_order) && isTRUE(r$consistent) &&
         !isTRUE(r$stored_rows$checked),
       "recorded calls are counted from the rows supplied, with the items present in each")
expect(grepl("may be fewer than it was sent", r$membership_scope, fixed = TRUE) &&
         grepl("A call with no row left is not counted", r$membership_scope, fixed = TRUE) &&
         !any(c("short_calls", "smallest_call") %in% names(r)),
       "the audit does not present the items present as the number a call was sent")
# One whole call lost: nothing in the remaining rows shows it was ever made.
lost <- gt_preflight(kept[kept$call != "CALL_SENTINEL_r3_c3", ], "score",
  gt_design("item", "rater", batch = gt_batch(4, id = "call")))$batch_audit
expect(lost$calls == 8 && grepl("A call with no row left is not counted", lost$membership_scope, fixed = TRUE),
       "a call with no row left is not counted, and the audit says it cannot be")
# Positions are ranks among the items present: sent at 1, 3 and 4, read as 1, 2 and 3.
ranked <- gt_preflight(kept, "score",
  gt_design("item", "rater", batch = gt_batch(4, order = "sent", id = "call")))$batch_audit
expect(identical(kept$sent[1:3], c(1, 3, 4)) && identical(ranked$examples$position[1:3], 1:3) &&
         grepl("ranks among the items present", ranked$position_scope, fixed = TRUE) &&
         grepl("ranks among the items present", by_order$position_scope, fixed = TRUE),
       "a position is a rank among the items present, and the audit says so for both kinds of membership")
expect(identical(names(r$examples), c("item", "call", "position")) &&
         identical(r$examples$item[1:4], c(1L, 3L, 4L, 5L)) && identical(r$examples$position[1:4], c(1L, 2L, 3L, 1L)) &&
         identical(r$examples$call[[1L]], "CALL_SENTINEL_r1_c1"),
       "recorded examples list items with their call and position")
recorded_output <- capture.output(print(by_call))
expect(any(grepl("Recorded calls: 9 in column", recorded_output, fixed = TRUE)) &&
         any(grepl("3 distinct batches of up to 4 items", recorded_output, fixed = TRUE)) &&
         any(grepl("9 call(s) have fewer than 4 items present (fewest 2): sent short, or rows removed since",
                   recorded_output, fixed = TRUE)) &&
         any(grepl("a call with no row left is not counted, and positions are ranks", recorded_output, fixed = TRUE)) &&
         !any(grepl("inferred", recorded_output, fixed = TRUE)),
       "the printed report states the recorded calls and what the rows supplied cannot show")
expect(!holds(gt_preflight(kept, "score", gt_design("item", "rater", batch = gt_batch(4, id = "call")),
                           max_examples = 0L)$batch_audit, "CALL_SENTINEL"),
       "max_examples = 0 keeps call identifiers out of the batch audit")
# Repeats declared through replicates each need a call of their own.
twice <- expand.grid(item = 1:8, rater = 1:2, run = 1:2)
twice$score <- sin(twice$item * twice$rater + twice$run)
repeated <- gt_preflight(twice, "score", gt_design("item", "rater", replicates = 2, batch = gt_batch(4)))
expect(repeated$batch_audit$calls == 8 && identical(repeated$batch_audit$batches, 2L) &&
         any(grepl("2 batches of 4 items x 2 conditions x 2 repeats = 8 calls", capture.output(print(repeated)),
                   fixed = TRUE)),
       "implied calls count one for each batch, condition and declared replicate")
twice$call <- paste(twice$rater, twice$run, (twice$item - 1) %/% 4)
recorded_design <- function(...) gt_design("item", "rater", replicates = 2, batch = gt_batch(4, ...))
expect(gt_preflight(twice, "score", recorded_design(id = "call"))$batch_audit$calls == 8,
       "recorded calls agree with the implied count when each repeat was a call")
# Recorded calls may regroup items between conditions, or reorder them.
regrouped <- history
regrouped$call <- ifelse(regrouped$rater == 1L, paste("a", (regrouped$item - 1) %/% 4),
                         paste(regrouped$rater, regrouped$item %% 3))
g2 <- gt_preflight(regrouped, "score", gt_design("item", "rater", batch = gt_batch(4, id = "call")))$batch_audit
expect(isTRUE(g2$consistent) && !g2$fixed_composition && identical(g2$batches, 6L) && g2$calls == 9 &&
         isTRUE(g2$equal_sized),
       "batches that differ between conditions are read from recorded calls and reported")
reordered <- history
reordered$sent <- ifelse(reordered$rater == 2L, -reordered$item, reordered$item)
g3 <- gt_preflight(reordered, "score",
  gt_design("item", "rater", batch = gt_batch(4, order = "sent", id = "call")))$batch_audit
expect(isTRUE(g3$consistent) && isTRUE(g3$fixed_composition) && !g3$fixed_order && identical(g3$batches, 3L),
       "one batch submitted in more than one order is reported")
# Recorded calls that cannot be calls are reported, not repaired.
recorded_problems <- function(data, ...)
  gt_preflight(data, "score", gt_design("item", "rater", batch = gt_batch(4, ...)))$batch_audit$problems
spanning <- history; spanning$call <- paste((spanning$item - 1) %/% 4)
expect(any(grepl("3 call(s) span more than one condition", recorded_problems(spanning, id = "call"), fixed = TRUE)),
       "a call spanning conditions is reported")
oversized <- history; oversized$call <- paste(oversized$rater, (oversized$item - 1) %/% 6)
expect(any(grepl("hold more than the declared 4 items; the largest holds 6",
                 recorded_problems(oversized, id = "call"), fixed = TRUE)),
       "a call larger than the declared size is reported")
tied_call <- history; tied_call$sent <- 1
expect(any(grepl("hold two or more rows with one order value",
                 recorded_problems(tied_call, order = "sent", id = "call"), fixed = TRUE)),
       "tied positions within a recorded call are reported")
doubled <- twice; doubled$call <- paste(doubled$rater, (doubled$item - 1) %/% 4)
expect(any(grepl("4 call(s) hold an item more than once",
                 gt_preflight(doubled, "score", gt_design("item", "rater", replicates = 2,
                   batch = gt_batch(8, id = "call")))$batch_audit$problems, fixed = TRUE)),
       "a call holding an item twice is reported")
expect_error(recorded_problems(history, id = "absent"), "is not in the data", "a missing id column is an error")
unknown <- history; unknown$call[[3L]] <- NA
expect_error(recorded_problems(unknown, id = "call"), "one nonmissing call identifier per row",
             "a missing call identifier is an error")

# --- a batch that cannot be modelled changes no estimate ------------------------
without <- gt_preflight(d, "score", gt_design("item", c("evaluator", "prompt")))
with <- gt_preflight(d, "score", gt_design("item", c("evaluator", "prompt"), batch = gt_batch(20)))
expect(is.null(without$batch_audit) && !any(grepl("batch", without$notes, fixed = TRUE)),
       "a design without a declaration has no batch audit and no batch note")
expect(identical(with$checks, without$checks) && identical(with$fitting_feasible, without$fitting_feasible) &&
         identical(with$sources, without$sources) && identical(with$panel_audit, without$panel_audit),
       "the audit enters no check and changes no other part of the preflight report")
output <- capture.output(print(with))
expect(any(grepl("Implied calls: 2 batches of 20 items x 6 conditions = 12 calls", output, fixed = TRUE)) &&
         any(grepl("inferred from item order, not read from recorded calls", output, fixed = TRUE)),
       "the printed report states the implied calls and that their membership is inferred")
set.seed(4040)
g <- expand.grid(item = 1:40, evaluator = 1:4, prompt = 1:3)
g$score <- rnorm(40)[g$item] + rnorm(4, sd = .5)[g$evaluator] + rnorm(3, sd = .3)[g$prompt] + rnorm(nrow(g), sd = .7)
control <- gt_control(gaussian = list(retry_seed = 42, threads = 1L))
fit_plain <- gt_fit(g, "score", gt_design("item", c("evaluator", "prompt")), control = control)
# Forty items in batches of 16 leave a short last batch, which the exact engine
# cannot model: the declaration is kept and the fit is the independent one.
fit_batch <- gt_fit(g, "score", gt_design("item", c("evaluator", "prompt"),
  batch = gt_batch(16, by = "evaluator", sequential = 2, neighbor = 3)), control = control)
expect(identical(fit_batch$covariance_components, fit_plain$covariance_components) &&
         identical(fit_batch$minus2loglik, fit_plain$minus2loglik) &&
         identical(gt_reliability(fit_batch)$per_trait, gt_reliability(fit_plain)$per_trait),
       "a batch that cannot be modelled changes no component, likelihood or coefficient")
expect(any(grepl("any other fit treats items in one call as independent", gt_diagnostics(fit_batch)$notes, fixed = TRUE)) &&
         !any(grepl("batch", gt_diagnostics(fit_plain)$notes, fixed = TRUE)),
       "a fit from a declaring design carries the note; one without does not")
expect(identical(fit_batch$design$batch$sequential, 2L) && identical(fit_batch$design$batch$neighbor, 3L),
       "the declaration survives fitting")

# --- every output says so -----------------------------------------------------
# A declared batch is not modelled yet. That has to reach the reader of a
# coefficient, a screened design or an exported table, not only the reader of
# the fit's notes.
said <- function(object) any(grepl(paste("Batches of 16 items declared (membership inferred) but not modelled:",
  "items in one call are treated as independent. Reason: not every batch holds the declared 16 items."),
  capture.output(print(object)), fixed = TRUE))
outputs <- function(fit) {
  reliability <- gt_reliability(fit)
  study <- gt_dstudy(fit, data.frame(evaluator = c(2, 4, 8)))
  list(fit = fit, diagnostics = gt_diagnostics(fit), reliability = reliability, study = study,
       target = gt_dstudy_target(study, 0.5), report = gt_report(fit, reliability = reliability, dstudy = study))
}
o_batch <- outputs(fit_batch); o_plain <- outputs(fit_plain)
printed <- c("fit", "diagnostics", "reliability", "study")
expect(all(vapply(o_batch[printed], said, logical(1))) && !any(vapply(o_plain[printed], said, logical(1))) &&
         said(summary(fit_batch)),
       "the fit, its diagnostics, the coefficients and the decision study print that batches are not modelled")
expect(identical(o_batch$diagnostics$batch, list(status = "declared_not_modelled", size = 16L, membership = "inferred",
           reason = "not every batch holds the declared 16 items", not_modelled = c("sequential", "neighbor", "by"))) &&
         identical(o_plain$diagnostics$batch$status, "not_declared") &&
         identical(o_batch$reliability$batch, o_batch$diagnostics$batch) &&
         identical(o_batch$study$batch, o_batch$diagnostics$batch),
       "the status is a structured field on the diagnostics and on each coefficient object")
tables <- function(o) list(as.data.frame(o$reliability), as.data.frame(o$study), o$target,
                           o$report$reliability, o$report$dstudy)
status_is <- function(table, value) identical(unique(table$batch_status), value)
expect(all(vapply(tables(o_batch), status_is, logical(1), "declared_not_modelled")) &&
         all(vapply(tables(o_plain), status_is, logical(1), "not_declared")),
       "every exported table carries the status as a column")
expect(identical(attr(as.data.frame(o_batch$reliability), "batch")$membership, "inferred") &&
         identical(attr(o_batch$target, "target_context")$batch_status, "declared_not_modelled") &&
         identical(attr(o_plain$target, "target_context")$batch_status, "not_declared"),
       "the export attribute and the screening context carry it too")
same_but_status <- function(a, b) {
  keep <- setdiff(names(a), "batch_status")
  identical(names(a), names(b)) && isTRUE(all.equal(a[keep], b[keep], check.attributes = FALSE))
}
expect(all(mapply(same_but_status, tables(o_batch)[1:3], tables(o_plain)[1:3])),
       "the status is the only difference a declaration makes to an exported table")
expect(identical(o_batch$report$analysis$batch_status, "declared_not_modelled") &&
         identical(o_plain$report$analysis$batch_status, "not_declared") &&
         any(grepl("declared (membership inferred) but not modelled", o_batch$report$limitations, fixed = TRUE)) &&
         identical(length(o_batch$report$limitations), length(o_plain$report$limitations) + 1L),
       "the portable report records the status and states it as a limitation")
html <- tempfile(fileext = ".html")
gt_export_report(o_batch$report, html)
page <- readLines(html, warn = FALSE)
gt_export_report(o_plain$report, html, overwrite = TRUE)
expect(any(grepl("declared_not_modelled", page, fixed = TRUE)) && any(grepl("but not modelled", page, fixed = TRUE)) &&
         !any(grepl("not modelled", readLines(html, warn = FALSE), fixed = TRUE)),
       "the exported report shows the status, and shows nothing of the kind without a declaration")
unlink(html)
# A coefficient object made before the status existed could not have declared a batch.
legacy <- o_plain$reliability; legacy$batch <- NULL
expect(status_is(as.data.frame(legacy), "not_declared") &&
         inherits(gt_report(fit_plain, reliability = legacy), "gt_report"),
       "an object without the field reads as not declared and still enters a report")
# A caller's own subtitle must not remove the statement from a figure. The text
# a plot draws is read back from an uncompressed PDF.
drawn_text <- function(object, ...) {
  file <- tempfile(fileext = ".pdf")
  on.exit(unlink(file), add = TRUE)
  grDevices::pdf(file, compress = FALSE, useKerning = FALSE)
  tryCatch(plot(object, ...), finally = grDevices::dev.off())
  bytes <- readBin(file, "raw", file.size(file))
  function(text) length(grepRaw(text, bytes, fixed = TRUE)) > 0L
}
for (object in list(o_batch$reliability, o_batch$study)) {
  default <- drawn_text(object); custom <- drawn_text(object, sub = "CALLER_SUBTITLE")
  expect(default("Declared batches not modelled") && custom("Declared batches not modelled") &&
           custom("CALLER_SUBTITLE") && !default("CALLER_SUBTITLE"),
         "a plot states that declared batches are not modelled, beside a caller's own subtitle")
}
for (object in list(o_plain$reliability, o_plain$study))
  expect(!drawn_text(object)("not modelled"), "a plot of a design without a declaration says nothing of batches")
# --- a batch the exact engine can model ---------------------------------------
# The same batches in every condition, each at the declared size: a Gaussian
# fit then estimates one shared call effect beside the declared sources. The
# fit is checked against the restricted likelihood written out with dense
# matrices, which shares nothing with the engine's factorial contrasts.
set.seed(2718)
cm <- expand.grid(item = sprintf("it%02d", 1:24), rater = 1:4, run = 1:3, stringsAsFactors = FALSE)
item_index <- match(cm$item, unique(cm$item))
cm$batch <- (item_index - 1L) %/% 6L + 1L
call_index <- as.integer(interaction(cm$batch, cm$rater, cm$run, drop = TRUE))
cm$score <- 1 + rnorm(24)[item_index] + rnorm(4, sd = .5)[cm$rater] +
  rnorm(96, sd = .4)[as.integer(interaction(item_index, cm$rater))] +
  rnorm(48, sd = .7)[call_index] + rnorm(nrow(cm), sd = .8)
cm$call <- paste0("c", call_index)
call_random <- ~ item + rater + item:rater
call_design <- function(...) gt_design("item", c("rater", "run"), random = call_random, ...)
independent <- gt_fit(cm, "score", call_design(), control = control)
with_calls <- gt_fit(cm, "score", call_design(batch = gt_batch(6)), control = control)
estimate <- function(fit) vapply(fit$covariance_components, function(M) M[1, 1], numeric(1))
expect(identical(names(with_calls$covariance_components), c("item", "rater", "item:rater", "Call", "Residual")) &&
         identical(with_calls$design$terms, independent$design$terms) &&
         isTRUE(with_calls$numerically_accepted),
       "a modelled batch adds one source, Call, and leaves the declared sources as they were")
dense_reml <- function(v) {
  n <- nrow(cm)
  same <- function(index) outer(index, index, "==")
  V <- diag(v[["Residual"]], n) + v[["item"]] * same(item_index) + v[["rater"]] * same(cm$rater) +
    v[["item:rater"]] * same(interaction(item_index, cm$rater)) +
    (if ("Call" %in% names(v)) v[["Call"]] else 0) * same(call_index)
  L <- chol(V); Vi <- chol2inv(L); one <- rep(1, n)
  weight <- sum(Vi %*% one); mean_hat <- sum(Vi %*% cm$score) / weight; r <- cm$score - mean_hat
  (n - 1) * log(2 * pi) + 2 * sum(log(diag(L))) + log(weight) + sum(r * (Vi %*% r))
}
fitted <- estimate(with_calls)
expect(abs(dense_reml(fitted) - with_calls$minus2loglik) < 1e-7 &&
         abs(dense_reml(estimate(independent)) - independent$minus2loglik) < 1e-7,
       "the restricted likelihood of a call-effect fit equals its dense-matrix value")
nearby <- vapply(names(fitted), function(source) vapply(c(.9, 1.1), function(factor) {
  moved <- fitted; moved[[source]] <- moved[[source]] * factor; dense_reml(moved) }, numeric(1)), numeric(2))
expect(all(nearby >= with_calls$minus2loglik - 1e-9) && fitted[["Call"]] > .2 &&
         with_calls$minus2loglik < independent$minus2loglik - 20,
       "the fitted components minimise the dense criterion, and the call effect improves on independence")
status <- gt_diagnostics(with_calls)$batch
expect(identical(status$status, "modelled") && is.na(status$reason) && !length(status$not_modelled) &&
         any(grepl("Batches of 6 items modelled (membership inferred): one shared call effect, reported as source Call.",
                   capture.output(print(with_calls)), fixed = TRUE)) &&
         "Call" %in% summary(with_calls)$variances$source &&
         is.finite(summary(with_calls)$variances$std_error[summary(with_calls)$variances$source == "Call"]),
       "the fit says the batches are modelled and reports the call variance with its standard error")
expect_error(gt_reliability(with_calls), "coefficients that account for which items share a call are not implemented yet",
             "a fit with a call effect has no reliability coefficients yet")
expect_error(gt_dstudy(with_calls, data.frame(rater = 2:3)), "are not implemented yet",
             "a fit with a call effect has no decision study yet")
expect(identical(gt_report(with_calls)$analysis$batch_status, "modelled") &&
         "Call" %in% gt_report(with_calls)$random_sources &&
         "Call" %in% gt_report(with_calls)$source_variances$source,
       "the portable report records the modelled status and the call source")
# Recorded calls give the same model, whatever order the rows are in.
recorded_calls <- gt_fit(cm[sample(nrow(cm)), ], "score", call_design(batch = gt_batch(6, id = "call")), control = control)
expect(identical(gt_diagnostics(recorded_calls)$batch$status, "modelled") &&
         identical(gt_diagnostics(recorded_calls)$batch$membership, "recorded") &&
         max(abs(estimate(recorded_calls) - fitted)) < 1e-5 &&
         abs(recorded_calls$minus2loglik - with_calls$minus2loglik) < 1e-8,
       "recorded calls and shuffled rows give the fit that inferred batches give")
# No call effect in the data: the variance goes to its boundary and the other
# sources return to the independent fit.
quiet_calls <- cm
quiet_calls$score <- 1 + sin(item_index) + cm$rater / 3 + cos(item_index * cm$rater) / 2 + sin(seq_len(nrow(cm)) * 1.7) / 2
none <- gt_fit(quiet_calls, "score", call_design(batch = gt_batch(6)), control = control)
none_plain <- gt_fit(quiet_calls, "score", call_design(), control = control)
expect(estimate(none)[["Call"]] < 1e-6 && abs(none$minus2loglik - none_plain$minus2loglik) < 1e-5 &&
         max(abs(estimate(none)[names(estimate(none_plain))] - estimate(none_plain))) < 1e-4,
       "data without a call effect give a call variance of zero and the independent estimates")
# What preflight says before the fit.
planned <- gt_preflight(cm, "score", call_design(batch = gt_batch(6)))
unplanned <- gt_preflight(cm, "score", call_design(batch = gt_batch(5)))
expect(isTRUE(planned$batch_audit$model$modelled) && identical(planned$batch_audit$model$source, "Call") &&
         planned$parameters[["total"]] == gt_preflight(cm, "score", call_design())$parameters[["total"]] + 1 &&
         !length(planned$supported_reliability_scales) &&
         any(grepl("A fit will estimate one shared call effect, reported as source Call.", capture.output(print(planned)), fixed = TRUE)),
       "preflight says a fit will model the batches, counts the extra parameter and offers no coefficient scale")
expect(!unplanned$batch_audit$model$modelled &&
         identical(unplanned$batch_audit$model$reason, "not every batch holds the declared 5 items") &&
         identical(unplanned$supported_reliability_scales, "observed") &&
         any(grepl("A fit will not model the batches: not every batch holds the declared 5 items.",
                   capture.output(print(unplanned)), fixed = TRUE)),
       "preflight says when and why a fit will not model the batches")
# Declarations the exact engine cannot model are kept, with the reason.
regrouped_calls <- cm
regrouped_calls$call <- ifelse(cm$rater == 1L, paste("a", cm$run, (item_index - 1L) %/% 6L),
                               paste(cm$rater, cm$run, item_index %% 4L))
moved <- gt_fit(regrouped_calls, "score", call_design(batch = gt_batch(6, id = "call")), control = control)
expect(identical(gt_diagnostics(moved)$batch$status, "declared_not_modelled") &&
         identical(gt_diagnostics(moved)$batch$reason, "the recorded batches differ between conditions") &&
         identical(moved$covariance_components, independent$covariance_components),
       "batches that differ between conditions are not modelled, and the fit is the independent one")
one_batch <- gt_fit(cm[item_index <= 6, ], "score", call_design(batch = gt_batch(6)), control = control)
expect(identical(gt_diagnostics(one_batch)$batch$reason, "there are fewer than two batches"),
       "a single batch cannot separate a call effect and is not modelled")
# Several continuous outcomes: the call source carries a covariance between them.
two <- cm; two$second <- cm$score / 2 + rnorm(48, sd = .6)[call_index] + rnorm(nrow(cm), sd = .7)
joint_calls <- gt_fit(two, c("score", "second"), call_design(batch = gt_batch(6)),
  covariance = c(item = "unstructured", Call = "unstructured"), residual = "diagonal", control = control)
expect(identical(dim(joint_calls$covariance_components$Call), c(2L, 2L)) &&
         all(diag(joint_calls$covariance_components$Call) > 0) &&
         abs(joint_calls$covariance_components$Call[1, 2]) > 0 &&
         joint_calls$covariance_components[["item:rater"]][1, 2] == 0,
       "with several outcomes the call source has its own covariance structure, chosen like any other source")
expect_error(gt_fit(transform(cm, Call = rater), "score",
                    gt_design("item", c("Call", "run"), random = ~ item + Call, batch = gt_batch(6)), control = control),
             "cannot be combined with a modelled batch", "a declared source named Call is refused beside a modelled batch")

# --- every outcome type, one outcome or several ---------------------------------
# The declaration and its audit belong to the design, not to an outcome family:
# binary, ordinal and unordered outcomes, alone or jointly, get the same audit
# as a continuous one. Only what a fit would do with it differs: the call
# effect is estimated for continuous outcomes, and a declaration changes no
# discrete estimate.
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
expect(isTRUE(reference$model$modelled), "a continuous outcome in equal fixed batches would be modelled")
described <- function(audit) audit[setdiff(names(audit), "model")]
cases <- list(
  binary = list("flag", gt_family("binary")),
  ordinal = list("grade", gt_family("ordinal")),
  categorical = list("kind", gt_family("categorical")),
  joint = list(c("flag", "grade"), list(flag = gt_family("binary"), grade = gt_family("ordinal"))))
for (label in names(cases)) {
  outcomes <- cases[[label]][[1L]]; family <- cases[[label]][[2L]]
  audited <- gt_preflight(k, outcomes, with_batch, family)$batch_audit
  expect(identical(described(audited), described(reference)) && identical(audited$batches, 2L) && audited$calls == 8,
         paste("the audit is the same for", label, "outcomes as for a continuous one"))
  expect(!audited$model$modelled &&
           identical(audited$model$reason, "the call effect is estimated for Gaussian outcomes only"),
         paste("preflight says a", label, "fit will not model the batches, and why"))
}
two_scores <- k; two_scores$second <- signal + rnorm(nrow(k))
joint_audit <- gt_preflight(two_scores, c("score", "second"), gt_design("item", "rater", batch = calls),
                           covariance = "diagonal", residual = "diagonal")$batch_audit
expect(identical(described(joint_audit), described(reference)) && isTRUE(joint_audit$model$modelled) &&
         joint_audit$model$covariance_parameters == 2,
       "the audit is the same for several continuous outcomes, whose call source has a variance for each")
for (label in c("binary", "ordinal", "joint")) {
  outcomes <- cases[[label]][[1L]]; family <- cases[[label]][[2L]]
  plain_fit <- suppressWarnings(gt_fit(k, outcomes, without_batch, family))
  batch_fit <- suppressWarnings(gt_fit(k, outcomes, with_batch, family))
  expect(identical(batch_fit$covariance_components, plain_fit$covariance_components) &&
           identical(batch_fit$minus2loglik, plain_fit$minus2loglik) &&
           identical(batch_fit$numerically_accepted, plain_fit$numerically_accepted),
         paste("declaring a batch changes no", label, "estimate or acceptance decision"))
  expect(any(grepl("any other fit treats items in one call as independent", gt_diagnostics(batch_fit)$notes, fixed = TRUE)) &&
           identical(gt_diagnostics(batch_fit)$batch$status, "declared_not_modelled") &&
           identical(gt_diagnostics(batch_fit)$batch$reason, "the call effect is estimated for Gaussian outcomes only") &&
           identical(gt_diagnostics(plain_fit)$batch$status, "not_declared") &&
           any(grepl("but not modelled", capture.output(print(batch_fit)), fixed = TRUE)),
         paste("a", label, "fit from a declaring design carries the note and the status"))
}
cat("PASS: batch declarations are validated, carried, audited, modelled where the exact engine can, and reported by every output.\n")
