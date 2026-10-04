# Installed structural checks and a complete synthetic LLM workflow.
library(Gtheory4LLM)
expect_error <- function(expr, text) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(text, conditionMessage(error), fixed = TRUE))
}

d <- expand.grid(item = 1:8, evaluator = 1:3, prompt = 1:2)
d$score <- sin(d$item) + d$evaluator / 5 + cos(d$item * d$prompt) / 4
design <- gt_design("item", c("evaluator", "prompt"))
original <- d
set.seed(947)
seed <- .Random.seed
p <- gt_preflight(d, "score", design)
stopifnot(p$fitting_feasible, identical(d, original), identical(seed, .Random.seed),
  identical(p$source_counts, c(requested = 7L, retained = 6L)),
  identical(p$aliased_terms, "item:evaluator:prompt"),
  p$parameters[["total"]] == 8, p$random_dimension == 59,
  identical(p$supported_reliability_scales, "observed"))

# The recorded call never carries the data. A plain object name is kept as
# written; a data frame embedded by do.call() or bquote(), or an inline
# expression, becomes a marker, so no unused column travels with the report.
holds <- function(object, sentinel)
  length(grepRaw(charToRaw(sentinel), serialize(object, NULL), fixed = TRUE)) > 0L
carried <- d
carried$unused <- "PREFLIGHT_UNUSED_SENTINEL"
embedded <- list(
  do.call(gt_preflight, list(carried, "score", design, max_examples = 0L)),
  do.call(gt_preflight, list(data = carried, outcomes = "score", design = design)),
  eval(bquote(gt_preflight(.(carried), "score", design))),
  gt_preflight(carried[seq_len(nrow(carried)), ], "score", design))
stopifnot(identical(p$call$data, as.name("d")),
  identical(gt_preflight(carried, "score", design)$call$data, as.name("carried")),
  holds(carried, "PREFLIGHT_UNUSED_SENTINEL"))
for (report in embedded)
  stopifnot(identical(report$call$data, as.name("<dropped>")),
    identical(report$call$outcomes, "score"),
    !holds(report, "PREFLIGHT_UNUSED_SENTINEL"),
    identical(report$checks, p$checks), identical(report$sources, p$sources))

# A full missing cell differs from duplicate or unevenly replicated cells.
incomplete <- gt_preflight(d[-1, ], "score", design)
stopifnot(!incomplete$fitting_feasible, !incomplete$complete_balanced_panel,
  !length(incomplete$supported_reliability_scales),
  "complete_coded_panel" %in% incomplete$checks$check[!incomplete$checks$passed])
duplicate <- gt_preflight(rbind(d, d[1, ]), "score", design)
stopifnot(!duplicate$fitting_feasible,
  "declared_replication" %in% duplicate$checks$check[!duplicate$checks$passed])
small_budget <- gt_preflight(d, "score", design,
  control = gt_control(gaussian = list(max_preparation_bytes = 1)))
stopifnot(!small_budget$fitting_feasible,
  "preparation_resource_limit" %in% small_budget$checks$check[!small_budget$checks$passed])

# Nonreference multinomial categories add predictor dimensions, whereas
# ordinal thresholds add observation parameters but not random dimensions.
d$binary <- rep(c(0L, 1L), length.out = nrow(d))
d$ordinal <- ordered(rep(c("low", "mid", "high"), length.out = nrow(d)),
                     levels = c("low", "mid", "high"))
d$nominal <- factor(rep(c("red", "green", "blue"), length.out = nrow(d)))
reduced <- gt_design("item", c("evaluator", "prompt"), random = ~ item + evaluator)
binary <- gt_preflight(d, "binary", reduced, gt_family("binary"))
stopifnot(binary$fitting_feasible, binary$random_dimension == 11,
  binary$parameters[["total"]] == 3,
  identical(binary$supported_reliability_scales, "latent"))
partial_binary <- gt_preflight(d[-1, ], "binary", reduced, gt_family("binary"))
stopifnot(partial_binary$fitting_feasible,
          !length(partial_binary$supported_reliability_scales))
joint <- gt_preflight(d, c("binary", "ordinal", "nominal"), reduced,
  list(binary = gt_family("binary"), ordinal = gt_family("ordinal"),
       nominal = gt_family("categorical")))
stopifnot(joint$fitting_feasible, joint$predictor_dimensions == 4,
  joint$random_dimension == 44, joint$parameters[["observation"]] == 5,
  joint$parameters[["source_covariance"]] == 20,
  !length(joint$supported_reliability_scales))
diagonal <- gt_preflight(d, c("binary", "ordinal", "nominal"), reduced,
  list(binary = gt_family("binary"), ordinal = gt_family("ordinal"),
       nominal = gt_family("categorical")), covariance = "diagonal")
stopifnot(diagonal$parameters[["source_covariance"]] == 8)
fixed <- gt_preflight(d, "binary", reduced, gt_family("binary"),
  control = gt_control(discrete = list(fixed_covariance =
    list(item = matrix(0, 1, 1), evaluator = matrix(0, 1, 1)))))
stopifnot(fixed$fitting_feasible, fixed$parameters[["source_covariance"]] == 0,
  fixed$kernel_check == "not_required_for_fixed_covariance")
budget <- gt_preflight(d, "binary", reduced, gt_family("binary"),
  control = gt_control(discrete = list(max_random_dimension = 10L)))
stopifnot(!budget$fitting_feasible,
  budget$kernel_check == "skipped_after_structural_or_resource_failure")

# Perfectly aliased item/evaluator grouping kernels must not be blessed by
# a small dimension count or repeated observations within each group.
alias_data <- expand.grid(item = 1:6, run = 1:2)
alias_data$evaluator <- alias_data$item
alias_data$binary <- rep(c(0L, 1L), length.out = nrow(alias_data))
aliased <- gt_preflight(alias_data, "binary",
  gt_design("item", c("evaluator", "run"), random = ~ item + evaluator),
  gt_family("binary"))
stopifnot(!aliased$fitting_feasible,
  "source_kernel_independence" %in% aliased$checks$check[!aliased$checks$passed])
unsupported <- gt_preflight(d, "binary", design, gt_family("binary"))
stopifnot(!unsupported$fitting_feasible,
  "family_design_resolution" %in% unsupported$checks$check[!unsupported$checks$passed])
expect_error(gt_preflight(d, "nominal", reduced), "categories are never silently converted")
expect_error(gt_preflight(d, c("score", "binary"), reduced,
  list(score = gt_family("gaussian"), binary = gt_family("binary"))),
  "Joint Gaussian-discrete")

# Mutually exclusive cell classes, exact counts, and independently bounded
# examples. Missing cells are distinct from observed cells with too few rows.
stopifnot(identical(p$panel_audit$summary$cell_count, c(48, 0, 0, 0)),
  identical(p$panel_audit$summary$cell_count_exact, c("48", "0", "0", "0")),
  !any(p$panel_audit$examples$truncated))
cells <- expand.grid(item = 1:3, rater = c("A", "B"),
                     KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
cells$score <- seq_len(nrow(cells))
uneven_data <- cells[c(2, 3, 3, 3, 4, 4, 5, 5, 6, 6), ]
uneven_design <- gt_design("item", "rater", random = ~ item + rater, replicates = 2L)
uneven <- gt_preflight(uneven_data, "score", uneven_design, max_examples = 1L)
audit <- uneven$panel_audit
columns <- audit$metadata_columns
stopifnot(identical(audit$summary$cell_count, c(3, 1, 1, 1)),
  identical(audit$summary$status, c("complete", "under_replicated", "over_replicated", "missing")),
  identical(audit$expected_cells_exact, "6"),
  nrow(audit$missing_cells) == 1L,
  audit$missing_cells$item == 1L, audit$missing_cells$rater == "A",
  nrow(audit$replication_issues) == 1L,
  audit$replication_issues$item == 2L,
  audit$replication_issues[[columns[["status"]]]] == "under_replicated",
  audit$replication_issues[[columns[["observed_replicates"]]]] == 1L,
  audit$replication_issues[[columns[["declared_replicates"]]]] == 2L,
  audit$row_examples[[columns[["row"]]]] == 1L,
  !"score" %in% names(audit$row_examples),
  identical(audit$examples$total, c(1, 2, 4)),
  identical(audit$examples$shown, c(1L, 1L, 1L)),
  identical(audit$examples$truncated, c(FALSE, TRUE, TRUE)))
all_examples <- gt_preflight(uneven_data, "score", uneven_design)$panel_audit
stopifnot(identical(all_examples$replication_issues[[columns[["status"]]]],
                    c("under_replicated", "over_replicated")),
  identical(all_examples$row_examples[[columns[["row"]]]], 1:4),
  !any(all_examples$examples$truncated))
no_examples <- gt_preflight(uneven_data, "score", uneven_design, max_examples = 0)$panel_audit
stopifnot(identical(no_examples$summary, audit$summary),
  all(no_examples$examples$shown == 0L), all(no_examples$examples$truncated),
  identical(names(no_examples$missing_cells), c("item", "rater")))

# Numeric IDs that collapse under ordinary character formatting must remain
# distinct. Factor/Date classes, unused factor levels and non-syntactic names
# survive both absent-cell and replication examples, including metadata clashes.
precise <- expand.grid(id = 1:2, rater = 1:2, day = 1:2,
                       KEEP.OUT.ATTRS = FALSE)
precise$id <- 1e15 + precise$id
precise$rater <- factor(c("r one", "r two")[precise$rater],
                        levels = c("r two", "r one", "unused"))
precise$day <- as.Date("2020-01-01") + precise$day
names(precise) <- c("item id", ".gt_status", "day name")
precise$score <- seq_len(nrow(precise))
precise[[".gt_row"]] <- "unrelated large text"
precise <- rbind(precise[-1, ], precise[2, ])
precise_original <- precise
precise_seed <- .Random.seed
precise_check <- gt_preflight(precise, "score",
  gt_design("item id", c(".gt_status", "day name"),
            random = c("item id", ".gt_status", "day name")))
pa <- precise_check$panel_audit
stopifnot(identical(precise, precise_original), identical(.Random.seed, precise_seed),
  identical(pa$summary$cell_count, c(6, 0, 1, 1)),
  identical(pa$missing_cells[["item id"]], 1e15 + 1),
  identical(pa$missing_cells[[".gt_status"]], factor("r one")),
  identical(pa$missing_cells[["day name"]], as.Date("2020-01-02")),
  identical(pa$replication_issues[["item id"]], 1e15 + 2),
  inherits(pa$replication_issues[[".gt_status"]], "factor"),
  inherits(pa$row_examples[["day name"]], "Date"),
  !any(pa$metadata_columns %in% names(precise)),
  identical(names(pa$missing_cells), c("item id", ".gt_status", "day name")),
  !".gt_row" %in% names(pa$row_examples), !"score" %in% names(pa$row_examples))

# 10^24 possible cells from only 100 input rows. Exact strings account for the
# observed cells even beyond the integer precision of a double; examples stay
# bounded and no Cartesian array can be allocated by this test fixture.
huge <- as.data.frame(stats::setNames(rep(list(1:100), 12L), paste0("axis", 1:12)))
huge$score <- seq_len(nrow(huge))
huge_original <- huge
huge_seed <- .Random.seed
huge_check <- gt_preflight(huge, "score",
  gt_design("axis1", paste0("axis", 2:12), random = paste0("axis", 1:12)),
  max_examples = 2L)
ha <- huge_check$panel_audit
stopifnot(identical(ha$expected_cells_exact, "1000000000000000000000000"),
  identical(ha$summary$cell_count_exact, c("100", "0", "0", "999999999999999999999900")),
  nrow(ha$missing_cells) == 2L, ha$examples$truncated[1L],
  identical(ha$missing_cells$axis1, 2:3), all(ha$missing_cells$axis2 == 1L),
  identical(huge, huge_original), identical(.Random.seed, huge_seed),
  !huge_check$fitting_feasible)

for (bad in list(-1, 0.5, Inf, -Inf, NA_real_, NaN, c(1, 2), numeric(),
                 TRUE, "2", 1 + 1i, .Machine$integer.max + 1))
  expect_error(gt_preflight(d, "score", design, max_examples = bad), "max_examples must be")
bad_design <- d
bad_design$item[c(2, 4)] <- NA
expect_error(gt_preflight(bad_design, "score", design, max_examples = 1L),
             "Invalid rows: 2 (2 total; examples truncated)")
expect_error(gt_preflight(d[-1], "score", design), "Missing outcome or design columns: ")

# Exercise installed S3 plotting with both types and a truncated source plot.
# Temporary output, RNG state, input data and the user's graphics settings are
# not changed by preflight or retained after this test.
plot_path <- tempfile(fileext = ".pdf")
grDevices::pdf(plot_path, width = 10, height = 7)
plot_parameters <- graphics::par(c("mar", "las", "xpd", "cex"))
plot_seed <- .Random.seed
stopifnot(identical(plot(uneven), uneven),
  identical(plot(p, type = "sources", max_sources = 2L, col = "grey"), p),
  identical(plot(huge_check), huge_check),
  identical(plot_parameters, graphics::par(c("mar", "las", "xpd", "cex"))),
  identical(plot_seed, .Random.seed))
for (bad in list(0, -1, 1.5, Inf, NA_real_, c(1, 2), TRUE))
  expect_error(plot(p, type = "sources", max_sources = bad), "max_sources must be")
grDevices::dev.off()
stopifnot(file.exists(plot_path), file.info(plot_path)$size > 0)
unlink(plot_path)
cat("PASS: bounded panel diagnostics, exact identifiers/counts, and preflight plots.\n")
cat("PASS: observed structure, alias handling, dimensions, limits, and scale boundaries before fitting.\n")

# Exercise the actual installed tutorial, using no repository or study data.
# The tutorial script and its HTML are vignette build products. A check run that
# could not build vignettes has neither; say so loudly rather than reporting a
# pass that silently skipped the whole workflow.
tutorial <- system.file("doc", "LLM-workflow.R", package = "Gtheory4LLM")
guide <- system.file("doc", "LLM-workflow.html", package = "Gtheory4LLM")
if (!nzchar(tutorial) || !nzchar(guide)) {
  cat("NOT RUN: the installed tutorial is absent, so this check was skipped.\n",
      "The vignette was not built for this archive; the end-to-end workflow is\n",
      "therefore unverified in this run. Build vignettes to exercise it.\n", sep = "")
  quit(save = "no", status = 0L)
}
workflow <- new.env(parent = globalenv())
invisible(capture.output(sys.source(tutorial, envir = workflow)))
stopifnot(workflow$fit$numerically_accepted,
  workflow$preflight$parameters[["total"]] == workflow$fit$n_model_parameters,
  identical(workflow$reliability$scale, "observed"),
  nrow(workflow$planning) == 18L,
  all(workflow$planning$Phi <= workflow$planning$Erho2),
  all(workflow$planning$Phi >= 0 & workflow$planning$Erho2 <= 1),
  any(workflow$planning$extrapolated), any(!workflow$planning$extrapolated))
co <- workflow$reliability$per_trait
current <- with(workflow$planning, evaluator == 4 & prompt == 3 & run == 2)
stopifnot(sum(current) == 1L,
          abs(workflow$planning$Phi[current] - co$Phi) < 1e-12)
cat("PASS: installed synthetic LLM tutorial through accepted fit, G/Phi, and D study.\n")
