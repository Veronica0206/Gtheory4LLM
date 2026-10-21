library(Gtheory4LLM)
# Public interfaces only: installed exports, dispatch, accessors and examples.
expect_error <- function(expression, pattern) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}
d <- expand.grid(item = 1:12, rater = 1:4)
d$binary <- as.integer((d$item + 2 * d$rater) %% 5 < 2)
d$nominal <- factor(c("a", "b", "c")[(floor(d$item / 4) + d$rater) %% 3 + 1L],
  levels = c("a", "b", "c"))
d$call_id <- paste(ceiling(d$item / 3), d$rater, sep = "-")
design <- gt_design("item", "rater", random = ~ item + rater)
zero <- list(item = matrix(0), rater = matrix(0))
information_fit <- gt_fit(binary ~ item + rater, d, measured = "item",
  family = gt_family("binary", "logit"),
  control = gt_control(discrete = list(engine = "sparse", optimizer = "nlminb",
    fixed_covariance = zero, check_hessian = TRUE)))
information <- gt_diagnostics(information_fit)
stopifnot(information$numerically_accepted, information$standard_errors_available,
  grepl("sparse", information$engine), setequal(names(gt_components(information_fit)), c("item", "rater")),
  all(unlist(gt_components(information_fit)) == 0),
  setequal(information$component_standard_errors$component, c("item", "rater")),
  all(information$component_standard_errors$std_error == 0))
score <- as.data.frame(gt_categorical_target(information_fit, "score", n_items = 20,
  replications = 5, seed = 13))
decision <- as.data.frame(gt_categorical_target(information_fit, "decision", n_items = 20,
  replications = 5, seed = 13))
stopifnot(score$available, score$estimate == 0, score$mc_se == 0,
  decision$available, decision$estimate >= 0, decision$estimate <= 1,
  !score$parameter_uncertainty, !decision$parameter_uncertainty)
costed <- gt_plan(information_fit, data.frame(rater = c(1, 3)),
  cost = data.frame(annotation = c(1, 3)), currency = "USD", cost_date = "2026-10-20",
  study_items = 20, target = 0, coefficient = "observed_score", scale = "observed",
  integration = list(n_items = 20, replications = 5, seed = 13))
costed_table <- as.data.frame(costed)
stopifnot(nrow(costed_table) == 2L, all(costed_table$eligible),
  identical(costed_table$minimum_cost, c(TRUE, FALSE)),
  costed_table$total_annotations[1] == 20,
  all(costed_table$observed_score == 0), all(!costed_table$parameter_uncertainty))

nominal <- gt_fit(d, "nominal", design, family = gt_family("categorical", reference = "b"),
  control = gt_control(discrete = list(engine = "sparse", optimizer = "nlminb",
    fixed_covariance = list(item = matrix(0, 2, 2), rater = matrix(0, 2, 2)))))
stopifnot(gt_diagnostics(nominal)$numerically_accepted)
vector <- as.data.frame(gt_categorical_target(nominal, "category_vector", n_items = 20,
  replications = 5, seed = 14))
stopifnot(vector$available, vector$estimate == 0,
  identical(levels(gt_simulate(nominal, 6, seed = 14)$nominal), levels(d$nominal)))
expect_error(gt_pilot_plan(nominal, data.frame(n_items = 6), 1, 14, scale = "latent"),
  "not unordered nominal")
pilot <- gt_pilot_plan(nominal, data.frame(n_items = 6), 2, 14,
  coefficient = "category_vector", scale = "observed", target_counts = c(rater = 1),
  integration = list(n_items = 20, replications = 3, reference_replications = 5))
pilot_table <- as.data.frame(pilot)
stopifnot(pilot_table$attempted == 2, nrow(pilot$replicates) == 2,
  pilot$reference$estimate == 0, is.finite(pilot$reference$mc_se),
  identical(pilot$scenario$analysis, "point_target_operating_characteristics"),
  pilot$scenario$target_counts[["rater"]] == 1)

calls <- gt_fit(d, "binary", gt_design("item", "rater", random = ~ item + rater,
    batch = gt_batch(3, id = "call_id")), family = gt_family("binary", "logit"),
  control = gt_control(discrete = list(engine = "sparse", optimizer = "nlminb",
    fixed_covariance = list(item = matrix(.3), rater = matrix(.15), Call = matrix(.1)))))
call_diagnostics <- gt_diagnostics(calls)
call_simulation <- gt_simulate(calls, 12, counts = c(rater = 3), seed = 14)
call_decision <- as.data.frame(gt_categorical_target(calls, "decision", n_items = 12,
  replications = 3, seed = 14))
stopifnot(call_diagnostics$numerically_accepted, identical(call_diagnostics$batch$status, "modelled"),
  "Call" %in% names(gt_components(calls)), nrow(call_simulation) == 36L,
  all(table(call_simulation$call_id) == 3L), identical(call_decision$batch_status, "modelled"))
incomplete_calls <- gt_preflight(d[-1L, ], "binary",
  gt_design("item", "rater", random = ~ item + rater, batch = gt_batch(3)),
  family = gt_family("binary", "logit"))
stopifnot(!"Call" %in% incomplete_calls$sources$source,
  isFALSE(incomplete_calls$batch_audit$model$modelled),
  grepl("complete balanced", incomplete_calls$batch_audit$model$reason, fixed = TRUE))

if (requireNamespace("lme4", quietly = TRUE)) {
  set.seed(1317)
  gaussian_data <- expand.grid(item = 1:24, rater = 1:5)
  gaussian_data$y <- 8 + rnorm(24, sd = 2)[gaussian_data$item] +
    c(-2, -.8, .1, 1, 2.1)[gaussian_data$rater] + rnorm(nrow(gaussian_data), sd = .7)
  observed <- gaussian_data[-seq(4L, nrow(gaussian_data), by = 7L), ]
  gaussian <- gt_fit(y ~ item + rater, observed, measured = "item",
    control = gt_control(gaussian = list(engine = "lme4", panel = "observed")))
  stopifnot(gt_diagnostics(gaussian)$numerically_accepted)
  expect_error(gt_reliability(gaussian), "complete balanced")
  projection <- as.data.frame(gt_dstudy(gaussian, data.frame(rater = c(3, 6)), projection = "balanced"))
  stopifnot(nrow(projection) == 2L,
    all(projection$projection_target == "intended_complete_balanced"),
    all(is.finite(projection$Erho2)), all(is.na(projection$Erho2_lower)))
} else cat("SKIP: suggested lme4 is unavailable for the observed-row smoke.\n")
cat("Installed development APIs: sparse calls, information, simulation, targets, planning and projection passed.\n")
