# Gtheory4LLM: a complete workflow using synthetic LLM judgments.
# All values below are simulated. No source-study data, manuscript results,
# API access, authentication, or repository-relative files are used.
library(Gtheory4LLM)

# 1. State the target and sampling model before fitting.
# Target: reliability of an item's mean continuous subjective-quality score
# over exchangeable evaluators, prompts, and repeated runs. These artificial
# scores follow a Gaussian working model; they are not ordinal categories.
set.seed(20260912)
llm_data <- expand.grid(item = factor(seq_len(24)),
  evaluator = factor(paste0("model_", seq_len(4))),
  prompt = factor(paste0("prompt_", seq_len(3))),
  run = factor(seq_len(2)))

# Run 1 for one evaluator/prompt pair is a different group from run 1 for
# another pair. Each group labels all items. The study treats run effects as
# common shifts across items; item-by-run differences remain in the residual.
# Item interactions are included for evaluator and prompt, and are not
# automatically added for every recorded facet. This is a model assumption
# motivated here by the known simulation, not a general recommendation.
llm_design <- gt_design("item", c("evaluator", "prompt", "run"),
  crossed = c("evaluator", "prompt"),
  nested = list(run = c("evaluator", "prompt")),
  item_interactions = "additive", instrument_interactions = "additive")
llm_design$terms_requested

source_sd <- c(item = 1.2, evaluator = 0.4, prompt = 0.3,
  "item:evaluator" = 0.5, "item:prompt" = 0.4,
  "evaluator:prompt:run" = 0.25)
llm_data$quality <- 0
for (source in names(source_sd)) {
  members <- strsplit(source, ":", fixed = TRUE)[[1L]]
  group <- do.call(interaction, c(llm_data[members], list(drop = TRUE)))
  effects <- rnorm(nlevels(group), sd = source_sd[[source]])
  llm_data$quality <- llm_data$quality + effects[as.integer(group)]
}
llm_data$quality <- llm_data$quality + rnorm(nrow(llm_data), sd = 0.6)

# 2. Inspect observed design and backend limits before requesting a fit.
preflight <- gt_preflight(llm_data, "quality", llm_design)
print(preflight)
preflight$sources
stopifnot(preflight$fitting_feasible)

# 3. Fit the declared Gaussian model with a reproducible trial budget.
# extra_tries is additional trials after the initial fit, not a new dataset.
# The optimizer stays fixed across trials. An unsupported local optimizer
# should be addressed explicitly; do not relabel a rejected fit as accepted.
fit <- gt_fit(llm_data, "quality", llm_design,
  control = gt_control(gaussian = list(optimizer = "CSOLNP",
    extra_tries = 2L, retry_seed = 415L, threads = 1L)))
print(summary(fit))
diagnostics <- gt_diagnostics(fit)
print(diagnostics[c("numerically_accepted", "selected_attempt",
                    "acceptance_failures", "approximation_adequacy")])
stopifnot(isTRUE(diagnostics$numerically_accepted))
gt_components(fit)

# 4. G concerns relative comparisons; Phi also includes absolute shifts
# attributable to the evaluator/prompt/run sources. Both use the observed
# Gaussian score scale and the declared averaging design.
reliability <- gt_reliability(fit)
reliability$per_trait
reliability$interpretation

# 5. Compare allocations and their measurement budgets per item.
# Counts denote the declared exchangeable facet populations. For nested runs,
# run is the number of runs within each evaluator/prompt pair.
grid <- expand.grid(evaluator = c(2L, 4L, 6L),
  prompt = c(2L, 3L, 4L), run = c(1L, 2L))
dstudy <- gt_dstudy(fit, grid)
allocation <- dstudy$allocations
allocation$measurements_per_item <- dstudy$measurements_per_object
allocation$extrapolated <- dstudy$extrapolated
planning <- cbind(allocation,
  dstudy$results[, c("outcome", "Erho2", "Phi")])
planning <- planning[order(planning$measurements_per_item, -planning$Phi), ]
rownames(planning) <- NULL
print(planning)

# A threshold of 0.80 is illustrative; justify a threshold for your own task.
# Extrapolated rows use more facet levels than observed and rely on the fitted
# variance model. Point estimates do not supply uncertainty guarantees.
planning[planning$Phi >= 0.80, ]

# Interpretation: this script checks the installed workflow with synthetic
# data. It does not validate any real evaluator, prompt set, accuracy against
# human labels, or number of LLMs required for a real application.
# Binary/ordinal models require a separate explicit family and scale="latent";
# unordered categorical models have no implemented scalar G/Phi. Do not
# silently coerce their categories to the continuous quality score above.
