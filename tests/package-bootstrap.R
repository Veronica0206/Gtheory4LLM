# The object bootstrap, run from sources and from an installed archive. A
# replicate must be the fit of a resample built independently here from its
# recorded seed; coefficient intervals must be the percentiles of closed-form
# coefficients of the replicate components; BCa must match a hand calculation
# and reduce to the percentile interval without bias or skew. Replicates must
# not depend on the number of cores or the attempt budget, the caller's random
# state must be untouched, refused and failed refits must be recorded and never
# counted, and every guard must refuse with its reason.
if (identical(Sys.getenv("GT_BOOTSTRAP_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
check <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label, call. = FALSE)
expect_error <- function(expr, text, label) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  check(inherits(error, "error") && grepl(text, conditionMessage(error), fixed = TRUE),
        paste0(label, " (", if (inherits(error, "error")) conditionMessage(error) else "no error", ")"))
}
seeded <- function(seed) {
  suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rejection"))
  set.seed(seed)
}
forks <- !identical(.Platform$OS.type, "windows")

# --- a Gaussian item-by-rater fit and its bootstrap ------------------------------
seeded(2L)
d <- expand.grid(rater = factor(1:4), item = factor(sprintf("t%02d", 1:30)))
d$score <- rnorm(30)[d$item] + rnorm(4, sd = .5)[d$rater] + rnorm(nrow(d), sd = .7)
fit <- gt_fit(d, "score", gt_design("item", "rater"))
seeded(77L)
before <- .Random.seed
boot <- gt_bootstrap(fit, replicates = 60, seed = 11, jackknife = TRUE)
check(identical(.Random.seed, before), "the caller's random state is untouched")
check(inherits(boot, "gt_bootstrap") && boot$accepted == 60L && boot$attempts == 60L &&
        identical(boot$unit, "item") && boot$objects == 30L && length(boot$components) == 60L &&
        all(boot$records$status == "accepted") && isTRUE(boot$jackknife$complete) &&
        identical(boot$jackknife$records$left_out, levels(d$item)),
      "the bootstrap records every attempt and the leave-one-out refits")

# A replicate is the fit of a resample built here from its recorded seed:
# the drawn items' complete panels, each draw a distinct item.
for (b in c(1L, 37L)) {
  record <- boot$records[b, ]
  draw <- local({ seeded(record$seed); sample.int(30L, 30L, replace = TRUE) })
  labels <- levels(d$item)
  pieces <- lapply(seq_along(draw), function(k) {
    rows <- d[d$item == labels[[draw[[k]]]], ]
    rows$item <- k
    rows
  })
  sample <- do.call(rbind, pieces)
  sample$item <- factor(sample$item, levels = seq_along(draw))
  check(nrow(sample) == nrow(d) && all(table(sample$item) == 4L), "a resample keeps every drawn item's full panel")
  direct <- gt_fit(sample, "score", gt_design("item", "rater"),
                   control = gt_control(gaussian = list(retry_seed = record$retry_seed)))
  difference <- max(abs(unlist(direct$covariance_components) - unlist(boot$components[[b]])))
  check(difference < 1e-8, sprintf("replicate %d equals the direct fit of its resample (%.2e)", b, difference))
}
cat("PASS: resamples and replicates\n")

# --- determinism ----------------------------------------------------------------------
again <- gt_bootstrap(fit, replicates = 60, seed = 11)
check(identical(again$components, boot$components) && is.null(again$jackknife),
      "the same seed gives the same replicates")
longer <- gt_bootstrap(fit, replicates = 20, seed = 11, max_attempts = 500)
check(identical(longer$components, boot$components[1:20]),
      "the attempt budget does not change the replicates")
other <- gt_bootstrap(fit, replicates = 20, seed = 12)
check(!identical(other$components, boot$components[1:20]), "another seed gives other replicates")
if (forks) {
  forked <- gt_bootstrap(fit, replicates = 60, seed = 11, jackknife = TRUE, cores = 2)
  same <- setdiff(names(boot$records), "seconds")
  check(identical(forked$components, boot$components) && identical(forked$records[same], boot$records[same]) &&
          identical(forked$jackknife$components, boot$jackknife$components),
        "two cores give the same replicates and records as one")
}
cat("PASS: determinism\n")

# --- coefficient intervals against closed forms ---------------------------------
# Item-by-rater with four raters: Erho2 = item / (item + residual / 4) and
# Phi = item / (item + (rater + residual) / 4).
closed <- function(components) {
  item <- components$item[1, 1]
  rater <- components$rater[1, 1]
  residual <- components$Residual[1, 1]
  c(Erho2 = item / (item + residual / 4), Phi = item / (item + (rater + residual) / 4))
}
values <- t(vapply(boot$components, closed, numeric(2)))
jack <- t(vapply(boot$jackknife$components, closed, numeric(2)))
original <- closed(fit$covariance_components)
table <- as.data.frame(gt_reliability(fit, bootstrap = boot))
for (coefficient in c("Erho2", "Phi")) {
  expected <- quantile(values[, coefficient], c(0.025, 0.975), type = 6, names = FALSE)
  check(abs(table[[coefficient]] - original[[coefficient]]) < 1e-12 &&
          max(abs(c(table[[paste0(coefficient, "_lower")]], table[[paste0(coefficient, "_upper")]]) - expected)) < 1e-12 &&
          abs(table[[paste0(coefficient, "_se")]] - sd(values[, coefficient])) < 1e-12,
        paste(coefficient, "percentile interval and standard error match the closed form"))
}
check(identical(table$uncertainty_method, "object_bootstrap_percentile") && isTRUE(table$uncertainty_available) &&
        !isTRUE(table$uncertainty_conditional),
      "the table names the bootstrap")
wald <- as.data.frame(gt_reliability(fit))
check(identical(wald$Erho2, table$Erho2) && wald$Erho2_lower != table$Erho2_lower &&
        identical(wald$uncertainty_method, fit$uncertainty$method),
      "without a bootstrap the delta-method intervals are unchanged")

# BCa by hand: bias from the share of replicates below the estimate, and
# acceleration from the leave-one-out skewness. An adjusted percentile beyond
# [1 / (B + 1), B / (B + 1)] has no replicate support; here Phi's upper one is.
bca <- as.data.frame(gt_reliability(fit, bootstrap = boot, interval_type = "bca"))
supported <- c(Erho2 = TRUE, Phi = FALSE)
for (coefficient in c("Erho2", "Phi")) {
  v <- values[, coefficient]
  theta <- original[[coefficient]]
  z0 <- qnorm(mean(v < theta) + 0.5 * mean(v == theta))
  u <- mean(jack[, coefficient]) - jack[, coefficient]
  a <- sum(u^3) / (6 * sum(u^2)^1.5)
  z <- qnorm(c(0.025, 0.975))
  p <- pnorm(z0 + (z0 + z) / (1 - a * (z0 + z)))
  check(identical(all(p >= 1 / 61 & p <= 60 / 61), supported[[coefficient]]),
        paste(coefficient, "BCa percentiles fall where this fixture expects"))
  bounds <- c(bca[[paste0(coefficient, "_lower")]], bca[[paste0(coefficient, "_upper")]])
  check(if (supported[[coefficient]]) max(abs(bounds - quantile(v, p, type = 6, names = FALSE))) < 1e-12 else
          all(is.na(bounds)) && is.finite(bca[[paste0(coefficient, "_se")]]),
        paste(coefficient, "BCa interval matches the hand calculation and its tail rule"))
}
check(identical(bca$uncertainty_method, "object_bootstrap_bca"), "the BCa table names its method")
interval <- internal(".gt_bootstrap_interval")
symmetric <- c(seq(-1, 1, length.out = 201))
check(max(abs(interval(0, symmetric, rep(1, 10), 0.9, "bca") - interval(0, symmetric, NULL, 0.9, "percentile"))) < 1e-12,
      "without bias or acceleration BCa is the percentile interval")
check(all(is.na(interval(0, symmetric[1:49], NULL, 0.95, "percentile")[c("lower", "upper")])) &&
        all(is.na(interval(NA_real_, symmetric, NULL, 0.95, "percentile")[c("lower", "upper")])) &&
        all(is.na(interval(0, symmetric[1:60], NULL, 0.99, "percentile")[c("lower", "upper")])) &&
        all(is.na(interval(0, symmetric, c(1, NA), 0.95, "bca")[c("lower", "upper")])),
      "too few replicates, a missing estimate, an unsupported tail or a missing leave-one-out estimate give no interval")

# Variance components and D studies.
components <- summary(boot)
item_values <- vapply(boot$components, function(x) x$item[1, 1], numeric(1))
row <- components[components$source == "item", ]
check(nrow(components) == 3L && abs(row$estimate - fit$covariance_components$item[1, 1]) < 1e-12 &&
        max(abs(c(row$lower, row$upper) - quantile(item_values, c(.025, .975), type = 6, names = FALSE))) < 1e-12 &&
        row$finite == 60L,
      "component intervals are the percentiles of the replicate components")
study <- as.data.frame(gt_dstudy(fit, data.frame(rater = c(4, 8)), bootstrap = boot))
eight <- t(vapply(boot$components, function(x) {
  item <- x$item[1, 1]
  c(item / (item + x$Residual[1, 1] / 8), item / (item + (x$rater[1, 1] + x$Residual[1, 1]) / 8))
}, numeric(2)))
check(abs(study$Erho2_lower[1] - table$Erho2_lower) < 1e-12 &&
        max(abs(c(study$Erho2_lower[2], study$Erho2_upper[2]) -
                quantile(eight[, 1], c(.025, .975), type = 6, names = FALSE))) < 1e-12 &&
        max(abs(c(study$Phi_lower[2], study$Phi_upper[2]) -
                quantile(eight[, 2], c(.025, .975), type = 6, names = FALSE))) < 1e-12 &&
        all(study$uncertainty_method == "object_bootstrap_percentile"),
      "D-study intervals are the percentiles of each replicate's projection")
printed <- paste(capture.output(print(gt_reliability(fit, bootstrap = boot))), collapse = "\n")
check(grepl("percentile, item bootstrap with 60 accepted refits of 60 attempts", printed, fixed = TRUE) &&
        grepl("facet sampling is not reflected", printed, fixed = TRUE), "the print names the bootstrap")
cat("PASS: coefficient, component and D-study intervals\n")

# --- a joint composite --------------------------------------------------------------
seeded(3L)
joint <- expand.grid(rater = factor(1:3), item = factor(1:25))
shared <- rnorm(25)
joint$a <- shared[joint$item] + rnorm(nrow(joint), sd = .6)
joint$b <- .7 * shared[joint$item] + rnorm(25, sd = .5)[joint$item] + rnorm(nrow(joint), sd = .6)
joint_fit <- gt_fit(joint, c("a", "b"), gt_design("item", "rater"))
joint_boot <- gt_bootstrap(joint_fit, replicates = 50, seed = 4)
weights <- c(a = 0.5, b = 0.5)
composite <- vapply(joint_boot$components, function(x) {
  universe <- drop(crossprod(weights, x$item %*% weights))
  universe / (universe + drop(crossprod(weights, x$Residual %*% weights)) / 3)
}, numeric(1))
joint_table <- as.data.frame(gt_reliability(joint_fit, score = gt_score(weights), bootstrap = joint_boot))
row <- joint_table[joint_table$kind == "composite", ]
check(joint_boot$accepted == 50L &&
        max(abs(c(row$Erho2_lower, row$Erho2_upper) - quantile(composite, c(.025, .975), type = 6, names = FALSE))) < 1e-12,
      "a composite's interval is the percentile interval of the replicate composites")
cat("PASS: joint composite\n")

# The lme4 route takes no retry seed or Hessian setting; its refits run with
# the fit's own controls.
if (requireNamespace("lme4", quietly = TRUE)) {
  lme4_fit <- gt_fit(d, "score", gt_design("item", "rater"), control = gt_control(gaussian = list(engine = "lme4")))
  lme4_boot <- gt_bootstrap(lme4_fit, replicates = 5, seed = 11)
  check(lme4_boot$accepted == 5L && all(lme4_boot$records$status == "accepted") &&
          max(abs(unlist(lme4_boot$components) - unlist(boot$components[1:5]))) < 1e-3,
        "an lme4 fit is bootstrapped from the same resamples as the exact engine")
  cat("PASS: lme4 route\n")
}

# --- discrete fits: warm starts, refusals and errors ---------------------------------
seeded(9001L)
binary <- expand.grid(rater = factor(1:6), item = factor(1:18))
binary$label <- rbinom(nrow(binary), 1L, plogis(.3 + rnorm(18, sd = .9)[binary$item] + rnorm(6, sd = .5)[binary$rater]))
binary_fit <- suppressWarnings(gt_fit(binary, "label", gt_design("item", "rater", full_cell = FALSE), gt_family("binary")))
check(identical(binary_fit$diagnostics$boundary_sources, "rater"), "the binary fit's rater variance is on its boundary")
start <- internal(".gt_bootstrap_start")(binary_fit)
check(identical(start[["rater::variance[label]"]], binary_fit$starting_parameters[["rater::variance[label]"]]) &&
        identical(start[c(1L, 2L)], binary_fit$parameters[c(1L, 2L)]),
      "a warm start keeps the estimates except at the boundary source")
binary_boot <- gt_bootstrap(binary_fit, replicates = 50, seed = 8)
cold <- gt_bootstrap(binary_fit, replicates = 50, seed = 8, warm_start = FALSE)
binary_table <- as.data.frame(gt_reliability(binary_fit, scale = "latent", bootstrap = binary_boot))
cold_table <- as.data.frame(gt_reliability(binary_fit, scale = "latent", bootstrap = cold))
check(binary_boot$accepted == 50L && is.finite(binary_table$Erho2_lower) &&
        abs(binary_table$Erho2_upper - cold_table$Erho2_upper) < 1e-4,
      "a binary bootstrap from warm and cold starts reaches the same interval")
# A one-iteration optimizer cannot be accepted: every attempt is refused,
# recorded, never counted, and no interval is reported.
refusing <- gt_bootstrap(binary_fit, replicates = 3, seed = 8, max_attempts = 5,
  control = gt_control(discrete = list(maxit = 1L)))
refused_table <- as.data.frame(gt_reliability(binary_fit, scale = "latent", bootstrap = refusing))
check(refusing$accepted == 0L && refusing$attempts == 5L && all(refusing$records$status == "refused") &&
        all(grepl("optimizer_incomplete", refusing$records$reason, fixed = TRUE)) &&
        !isTRUE(refused_table$uncertainty_available) && is.na(refused_table$Erho2_lower) &&
        grepl("at least 50", refused_table$uncertainty_reason, fixed = TRUE),
      "refused refits are recorded, never counted, and leave no interval")
# An ordinal category seen in one item only is missing from some resamples;
# those refits fail with the fit's own error and are recorded.
seeded(5L)
rare <- expand.grid(rater = factor(1:4), item = factor(1:12))
rare$grade <- ordered(ifelse(rnorm(nrow(rare)) + rnorm(12)[rare$item] > 0, "high", "low"), levels = c("low", "mid", "high"))
rare$grade[rare$item == "3" & rare$rater == "1"] <- "mid"
rare_fit <- suppressWarnings(gt_fit(rare, "grade", gt_design("item", "rater", full_cell = FALSE), gt_family("ordinal")))
check(isTRUE(rare_fit$numerically_accepted), "the rare-category fit is accepted")
failing <- gt_bootstrap(rare_fit, replicates = 4, seed = 2, max_attempts = 12)
errors <- failing$records[failing$records$status == "error", ]
accepted <- which(failing$records$status == "accepted")
check(nrow(errors) > 0L && all(grepl("Every declared category must occur", errors$reason, fixed = TRUE)) &&
        failing$accepted == 4L && length(failing$components) == 4L && length(accepted) == 4L &&
        failing$attempts == max(accepted) && nrow(failing$records) == failing$attempts && failing$attempts > 4L,
      "failed refits are recorded as errors and never counted; attempts run to the last accepted replicate")
cat("PASS: discrete warm starts, refusals and errors\n")

# --- guards ----------------------------------------------------------------------------
expect_error(gt_bootstrap(fit, replicates = 5), "seed is required", "a seed is required")
for (bad in list(0, 1.5, NA, "10", c(5, 6))) expect_error(gt_bootstrap(fit, replicates = bad, seed = 1),
  "replicates must be one whole number", "a malformed replicate count is refused")
expect_error(gt_bootstrap(fit, replicates = 10, max_attempts = 5, seed = 1), "max_attempts must be one whole number of at least 10",
             "the attempt budget cannot be below the replicate count")
expect_error(gt_bootstrap(fit, replicates = 5, seed = 1, jackknife = NA), "jackknife must be TRUE or FALSE", "jackknife is a flag")
expect_error(gt_bootstrap(fit, replicates = 5, seed = 1, cores = 0), "cores must be one whole number", "cores is a count")
expect_error(gt_bootstrap(fit, replicates = 5, seed = 1, control = list()), "control must be created by gt_control()",
             "control is a gt_control")
unaccepted <- fit
unaccepted$numerically_accepted <- FALSE
expect_error(gt_bootstrap(unaccepted, replicates = 5, seed = 1), "numerically accepted fit", "an unaccepted fit is refused")
dropped <- gt_fit(d, "score", gt_design("item", "rater"), control = gt_control(retain = list(data = FALSE)))
expect_error(gt_bootstrap(dropped, replicates = 5, seed = 1), "stored without its data", "a fit without data needs data =")
from_data <- gt_bootstrap(dropped, replicates = 5, seed = 11, data = d)
check(identical(from_data$components, boot$components[1:5]), "supplied data reproduces the retained-data replicates")
expect_error(gt_bootstrap(dropped, replicates = 5, seed = 1, data = d[-1, ]), "does not describe the panel",
             "data from another panel is refused")
batched <- fit
batched$design$batch <- list(size = 5L)
expect_error(gt_bootstrap(batched, replicates = 5, seed = 1), "Declared batches", "a batched design is refused")
expect_error(gt_reliability(fit, bootstrap = joint_boot), "not made from this fit", "a bootstrap of another fit is refused")
expect_error(gt_reliability(fit, interval_type = "percentile"), "need bootstrap", "a percentile interval needs a bootstrap")
expect_error(gt_reliability(fit, bootstrap = boot, interval_type = "wald"), "A bootstrap was supplied", "wald with a bootstrap is refused")
expect_error(gt_reliability(fit, bootstrap = boot, interval_type = "normal"), "interval_type must be", "an unknown interval is refused")
no_jack <- as.data.frame(gt_reliability(fit, bootstrap = again, interval_type = "bca"))
check(!isTRUE(no_jack$uncertainty_available) && grepl("jackknife = TRUE", no_jack$uncertainty_reason, fixed = TRUE) &&
        is.na(no_jack$Erho2_lower), "BCa without the leave-one-out refits is unavailable with its reason")
printed <- paste(capture.output(print(boot)), collapse = "\n")
check(grepl("Object bootstrap of 30 items | 60 accepted of 60 requested | 60 attempts", printed, fixed = TRUE) &&
        grepl("BCa acceleration available", printed, fixed = TRUE) && identical(as.data.frame(boot), boot$records),
      "the bootstrap prints its counts and returns its records")
cat("PASS: guards\n")
