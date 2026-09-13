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
