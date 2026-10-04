# Descriptive outcome information, without fitting or adequacy thresholds.
library(Gtheory4LLM)
expect_error <- function(expr, text) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(text, conditionMessage(error), fixed = TRUE))
}

d <- expand.grid(item = 1:4, rater = 1:2, KEEP.OUT.ATTRS = FALSE)
d$rating <- ordered(rep(c("low", "high"), 4), levels = c("low", "middle", "high"))
design <- gt_design("item", "rater", random = ~ item + rater)
original <- d
set.seed(814)
seed <- .Random.seed
p <- gt_preflight(d, "rating", design, gt_family("ordinal"), max_examples = 2L)
profile <- p$outcome_profile$rating
stopifnot(identical(d, original), identical(seed, .Random.seed),
  identical(names(p$outcome_profile), "rating"),
  identical(profile$categories$category, c("low", "middle", "high")),
  identical(profile$categories$count, c(4L, 0L, 4L)),
  identical(profile$categories$proportion, c(.5, 0, .5)),
  identical(profile$categories$observed, c(TRUE, FALSE, TRUE)),
  identical(profile$category_coverage$groups_present, c(2L, 0L, 2L, 2L, 0L, 2L)),
  identical(profile$by_variable$no_variation_groups, c(4L, 0L)),
  all(profile$by_variable$single_row_groups == 0L),
  identical(profile$examples$shown, c(2L, 0L)),
  identical(profile$examples$truncated, c(TRUE, FALSE)),
  !p$fitting_feasible, !length(p$supported_reliability_scales),
  !p$checks$passed[p$checks$check == "outcome_category_coverage"],
  identical(p$kernel_check, "skipped_after_structural_or_resource_failure"))
expect_error(gt_fit(d, "rating", design, gt_family("ordinal")), "absent categories")

# Shared resolution stays strict for fitting; binary and nominal absent
# declarations are diagnostic-only too. Invalid categories still raise errors.
d$binary <- 0L
binary <- gt_preflight(d, "binary", design, gt_family("binary"))
stopifnot(identical(binary$outcome_profile$binary$categories$count, c(8L, 0L)),
  all(binary$outcome_profile$binary$by_variable$no_variation_proportion == 1),
  !binary$fitting_feasible)
expect_error(gt_fit(d, "binary", design, gt_family("binary")), "absent categories")
d$nominal <- factor(rep(c("red", "blue"), 4), levels = c("red", "green", "blue"))
nominal <- gt_preflight(d, "nominal", design, gt_family("categorical", reference = "green"))
stopifnot(identical(nominal$outcome_profile$nominal$categories$count, c(4L, 0L, 4L)),
  identical(nominal$families$nominal$reference, "green"), !nominal$fitting_feasible)
expect_error(gt_fit(d, "nominal", design, gt_family("categorical", reference = "green")), "absent categories")
bad <- d
bad$rating <- as.character(bad$rating)
bad$rating[1L] <- "not declared"
expect_error(gt_preflight(bad, "rating", design,
  gt_family("ordinal", levels = c("low", "middle", "high"))), "Undeclared categories")
bad$rating[1L] <- NA_character_
expect_error(gt_preflight(bad, "rating", design,
  gt_family("ordinal", levels = c("low", "middle", "high"))), "missing or unsupported")
expect_error(gt_preflight(d, "rating", design), "categories are never silently converted")
expect_error(gt_preflight(d, "binary", design), "nonconstant")

# Rare and within-group constant responses are counts, not a new acceptance
# rule. A single positive row is visible without an invented minimum count.
rare <- expand.grid(item = 1:20, rater = 1:2, KEEP.OUT.ATTRS = FALSE)
rare$y <- c(1L, rep(0L, 39L))
rare_check <- gt_preflight(rare, "y", design, gt_family("binary"), max_examples = 0L)
rp <- rare_check$outcome_profile$y
stopifnot(rare_check$fitting_feasible, identical(rp$categories$count, c(39L, 1L)),
  identical(rp$categories$proportion, c(.975, .025)),
  all(vapply(rp$no_variation_examples, nrow, integer(1)) == 0L),
  all(rp$examples$shown == 0L), any(rp$examples$truncated))

# A nested run is scoped by its site. Reused run IDs must not pool distinct
# parent groups into apparently variable groups.
nested <- expand.grid(item = 1:3, site = c("A", "B"), run = 1:2, KEEP.OUT.ATTRS = FALSE)
nested$y <- as.integer(nested$site == "B")
nested_design <- gt_design("item", c("site", "run"), crossed = "site", nested = list(run = "site"))
nested_check <- gt_preflight(nested, "y", nested_design, gt_family("binary"))
np <- nested_check$outcome_profile$y
run <- np$by_variable[np$by_variable$variable == "run", ]
stopifnot(run$total_groups == 4L, run$no_variation_groups == 4L,
  identical(run$grouping_scope, "declared_parent_scoped"),
  identical(np$group_members$run, c("site", "run")),
  identical(np$category_coverage$groups_present[np$category_coverage$variable == "run"], c(2L, 2L)),
  all(c("site", "run") %in% names(np$no_variation_examples$run)))

# Native identifiers, non-syntactic names, metadata collisions and data types
# survive only in capped grouping examples; unrelated/response rows do not.
precise <- expand.grid(id = 1:2, judge = 1:2, KEEP.OUT.ATTRS = FALSE)
precise$id <- 1e15 + precise$id
precise$judge <- factor(c("judge one", "judge two")[precise$judge])
names(precise) <- c("item id", ".gt_row_count")
precise[["rating label"]] <- c(0L, 1L, 0L, 1L)
precise$private_text <- "unrelated text must not be copied"
pc <- gt_preflight(precise, "rating label",
  gt_design("item id", ".gt_row_count", random = c("item id", ".gt_row_count")), gt_family("binary"))
pp <- pc$outcome_profile[["rating label"]]
stopifnot(identical(pp$no_variation_examples[["item id"]][["item id"]], 1e15 + 1:2),
  inherits(pp$no_variation_examples[[".gt_row_count"]][[".gt_row_count"]], "factor"),
  !any(pp$metadata_columns %in% names(precise)),
  !any(c("rating label", "private_text") %in% names(pp$no_variation_examples[["item id"]])))

# Factor attributes must not retain identifiers omitted by the example limit.
# This checks complete serialized objects, not merely zero displayed rows.
private <- expand.grid(item = factor(c("PRIVATE_ID_ALICE", "PRIVATE_ID_BOB", "PRIVATE_ID_CAROL")),
                       occasion = 1:2, KEEP.OUT.ATTRS = FALSE)
private$y <- c(0L, 1L, 0L, 0L, 1L, 0L)
private_design <- gt_design("item", "occasion", random = ~ item)
private_none <- gt_preflight(private, "y", private_design, gt_family("binary"), max_examples = 0L)
private_one <- gt_preflight(private, "y", private_design, gt_family("binary"), max_examples = 1L)
stopifnot(length(levels(private_none$outcome_profile$y$no_variation_examples$item$item)) == 0L,
  identical(levels(private_one$outcome_profile$y$no_variation_examples$item$item), "PRIVATE_ID_ALICE"))
panel_none <- gt_preflight(rbind(private[-1L, ], private[2L, ]), "y", private_design,
                          gt_family("binary"), max_examples = 0L)$panel_audit
for (table in c("missing_cells", "replication_issues", "row_examples"))
  stopifnot(length(levels(panel_none[[table]]$item)) == 0L)
panel_one <- gt_preflight(rbind(private[-1L, ], private[2L, ]), "y", private_design,
                         gt_family("binary"), max_examples = 1L)$panel_audit
stopifnot(identical(levels(panel_one$missing_cells$item), "PRIVATE_ID_ALICE"),
  identical(levels(panel_one$replication_issues$item), "PRIVATE_ID_BOB"),
  identical(levels(panel_one$row_examples$item), "PRIVATE_ID_BOB"))
encoded_examples <- serialize(private_none$outcome_profile$y$no_variation_examples, NULL, ascii = TRUE)
stopifnot(!grepl("PRIVATE_ID_", rawToChar(encoded_examples), fixed = TRUE))

# Gaussian profiles use numeric summaries and native-value distinctness, not
# categorical coercion; groups of one row are separately identifiable.
g <- expand.grid(item = 1:4, rater = 1:2, KEEP.OUT.ATTRS = FALSE)
g$score <- 1e15 + g$item
gp <- gt_preflight(g, "score", design)$outcome_profile$score
stopifnot(is.null(gp$categories), is.null(gp$category_coverage),
  gp$summary$distinct_values == 4L, gp$summary$minimum == 1e15 + 1,
  gp$summary$maximum == 1e15 + 4, is.finite(gp$summary$standard_deviation),
  identical(gp$by_variable$no_variation_groups, c(4L, 0L)))
single <- g[1:4, ]
single$rater <- 1:4
sp <- gt_preflight(single, "score", design)$outcome_profile$score
stopifnot(all(sp$by_variable$single_row_groups == 4L),
  all(sp$by_variable$no_variation_groups == 4L))

# Multiple outcomes retain caller order and require explicit plot selection.
joint <- gt_preflight(d, c("nominal", "rating"), design,
  list(rating = gt_family("ordinal"), nominal = gt_family("categorical")))
stopifnot(identical(names(joint$outcome_profile), c("nominal", "rating")))
plot_path <- tempfile(fileext = ".pdf")
grDevices::pdf(plot_path, width = 7, height = 5)
parameters <- graphics::par(c("mar", "las", "xpd", "cex"))
plot_seed <- .Random.seed
stopifnot(identical(plot(p, "outcomes"), p),
  identical(plot(nested_check, "outcomes", max_categories = 1L, max_variables = 1L), nested_check),
  identical(plot(joint, "outcomes", outcome = "nominal"), joint),
  identical(parameters, graphics::par(c("mar", "las", "xpd", "cex"))), identical(plot_seed, .Random.seed))
expect_error(plot(joint, "outcomes"), "Select one outcome")
expect_error(plot(p, "outcomes", outcome = "unknown"), "exactly one")
expect_error(plot(gt_preflight(g, "score", design), "outcomes"), "Gaussian outcomes have no category heatmap")
for (bad_limit in list(0L, 1.5, NA_real_, Inf, TRUE, c(1, 2), 1 + 1i)) {
  expect_error(plot(p, "outcomes", max_categories = bad_limit), "max_categories must be")
  expect_error(plot(p, "outcomes", max_variables = bad_limit), "max_variables must be")
}
expect_error(plot(p, "outcomes", max_label_chars = 3L), "at least 4")
grDevices::dev.off()
stopifnot(file.info(plot_path)$size > 0)
unlink(plot_path)
cat("PASS: descriptive outcome information, absent-category refusal, nested coverage, privacy bounds and plots.\n")
