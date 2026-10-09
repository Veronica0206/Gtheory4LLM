library(Gtheory4LLM)
# Exercise exported functions from the installed package with a small actual fit.
set.seed(199)
panel <- expand.grid(item = 1:24, rater = 1:4, KEEP.OUT.ATTRS = FALSE)
panel$score <- rep(rnorm(24, sd = 2), 4) + rep(rnorm(4, sd = .5), each = 24) + rnorm(96)
fit <- gt_fit(panel, "score", gt_design("item", "rater"))
stopifnot(isTRUE(fit$numerically_accepted))
previous <- .Random.seed
simulation <- gt_simulate(fit, 16, c(rater = 3), seed = 3)
stopifnot(nrow(simulation) == 48L, identical(previous, .Random.seed))
plan <- gt_pilot_plan(fit, data.frame(n_items = 16), nsim = 1, seed = 3,
  target_counts = c(rater = 2), width_target = .5)
stopifnot(nrow(plan$replicates) == 1L, plan$summary$attempted == 1L,
  plan$scenario$target_counts[["rater"]] == 2L, identical(previous, .Random.seed))
