# The declared optimizer metric is identical in source and installed tests.
if (identical(Sys.getenv("GT_SCALING_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
expect_error <- function(expr, text) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(text, conditionMessage(error), fixed = TRUE))
}
control <- internal(".gt_d_control")
for (bad in list(NULL, NA, 1, "automatic", c("none", "start")))
  expect_error(control(list(optimizer_scaling = bad)), "optimizer_scaling")
expect_error(control(list(optimizer = "nlminb", optimizer_scaling = "start")), "requires")

# A diagonal quadratic has known curvature and a one-step Newton solution
# under this metric. Large and small coordinate units both reach the target.
at <- c(a = 100, b = 0.16, c = -20)
n <- 1600
units <- pmax(1, abs(at))
target <- at + c(-30, 0.2, 5)
seen <- list()
objective <- function(x) {
  seen[[length(seen) + 1L]] <<- x
  n * sum(((x - target) / units)^2) / 2
}
base <- list(maxit = 2L, factr = 1e7)
metric <- internal(".gt_d_optimizer_metric")
stopifnot(identical(metric(at, n, base, "none"), base))
scaled <- metric(at, n, base, "start")
invisible(internal(".gt_d_optimize")(at, objective, rep(-1000, 3), rep(1000, 3),
  scaled, "known_curvature", gradient = function(x) n * (x - target) / units^2))
stopifnot(max(abs(seen[[2L]] - target)) < 1e-8,
          identical(scaled$parscale, units / sqrt(n)))

# A genuine estimated interior model must retain the same optimum and full
# independent acceptance, with each metric derived from its own attempt start.
d <- expand.grid(occasion = 1:12, item = 1:8)
d$y <- as.integer(d$occasion <= c(2, 3, 4, 5, 7, 8, 9, 10)[d$item])
design <- gt_design("item", "occasion", random = ~ item)
fit_with <- function(policy, engine) gt_fit(d, "y", design, gt_family("binary", "logit"),
  control = gt_control(discrete = list(engine = engine, optimizer_scaling = policy,
    check_hessian = TRUE, maxit = 300)))
reference <- fit_with("none", "dense")
for (engine in c("dense", "sparse")) {
  fit <- fit_with("start", engine)
  stopifnot(reference$numerically_accepted, fit$numerically_accepted,
    abs(fit$minus2loglik - reference$minus2loglik) < 1e-6,
    abs(gt_components(fit)$item[1, 1] - gt_components(reference)$item[1, 1]) < 1e-4,
    fit$diagnostics$outer_stationarity$tolerance == 1e-3,
    fit$diagnostics$stability$alternative_starts == 1L,
    all(vapply(fit$diagnostics$attempts, function(a)
      identical(a$optimizer_control$parscale, pmax(1, abs(a$start)) / sqrt(nrow(d))) &&
      is.null(a$first_step_rescue), logical(1))))
}
stopifnot(all(vapply(reference$diagnostics$attempts, function(a)
  is.null(a$optimizer_control$parscale), logical(1))))
cat("PASS: declared scaling balances known curvature and preserves independently accepted dense/sparse interior fits and default paths.\n")
