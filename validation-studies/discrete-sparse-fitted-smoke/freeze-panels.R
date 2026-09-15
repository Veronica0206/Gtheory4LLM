# Generate the fitted smoke panels once and freeze their actual rows.
#
# Run once. Do not re-run to "refresh" the study: panels.csv is the
# authoritative data, not this recipe. set.seed() does not imply bitwise
# identical continuous draws across architectures, which the issue #14
# portability work established directly, so a qualification that regenerated
# its panels would be comparing two backends on two datasets on some
# platforms. The generators are retained here as provenance for how the frozen
# rows were produced, and for review.
out_dir <- file.path("validation-studies", "discrete-sparse-fitted-smoke")

binary_fitted <- function(seed, items, raters, link, rater_sd = 0.5,
                          item_sd = 0.9, intercept = -0.2) {
  set.seed(seed)
  d <- expand.grid(item = seq_len(items), rater = seq_len(raters))
  item_effect <- rnorm(items, sd = item_sd)
  rater_effect <- if (rater_sd > 0) rnorm(raters, sd = rater_sd) else numeric(raters)
  eta <- intercept + item_effect[d$item] + rater_effect[d$rater]
  d$y <- as.character(rbinom(nrow(d), 1L, if (link == "probit") pnorm(eta) else plogis(eta)))
  d
}

# Categories are cut at predeclared empirical quantiles of the simulated latent
# score rather than at fixed population thresholds. The proportions are frozen
# before any sparse implementation exists, and the construction guarantees
# every category is occupied whatever the seed does. Fixed thresholds with a
# thin tail can empty a category at these sample sizes.
ordinal_fitted <- function(seed, items, raters, link, proportions,
                           item_sd = 0.8, rater_sd = 0.4) {
  set.seed(seed)
  d <- expand.grid(item = seq_len(items), rater = seq_len(raters))
  item_effect <- rnorm(items, sd = item_sd)
  rater_effect <- rnorm(raters, sd = rater_sd)
  noise <- if (link == "probit") rnorm(nrow(d)) else rlogis(nrow(d))
  latent <- item_effect[d$item] + rater_effect[d$rater] + noise
  interior <- cumsum(proportions)[-length(proportions)]
  cuts <- unname(stats::quantile(latent, probs = interior, names = FALSE))
  labels <- paste0("c", seq_along(proportions))
  d$y <- labels[findInterval(latent, cuts) + 1L]
  d
}

THREE <- c(0.25, 0.50, 0.25)
TAIL_FIVE <- c(0.05, 0.20, 0.50, 0.20, 0.05)

panels <- list(
  binary_logit_single_source = binary_fitted(301, 30, 10, "logit", rater_sd = 0),
  binary_probit_crossed = binary_fitted(302, 30, 10, "probit"),
  binary_logit_zero_source = binary_fitted(303, 30, 10, "logit", rater_sd = 0),
  ordinal_logit_crossed = ordinal_fitted(304, 30, 10, "logit", THREE),
  ordinal_probit_crossed = ordinal_fitted(305, 30, 10, "probit", THREE),
  ordinal_logit_tail_mass = ordinal_fitted(306, 40, 10, "logit", TAIL_FIVE),
  binary_probit_fixed_covariance = binary_fitted(307, 30, 10, "probit"))

rows <- do.call(rbind, lapply(names(panels), function(name)
  data.frame(panel = name, panels[[name]], stringsAsFactors = FALSE)))
rows$item <- as.integer(rows$item)
rows$rater <- as.integer(rows$rater)
write.csv(rows, file.path(out_dir, "panels.csv"), row.names = FALSE, quote = FALSE)
cat("froze", nrow(rows), "rows across", length(panels), "panels\n")
for (name in names(panels))
  cat(sprintf("  %-34s rows=%-4d categories=%s\n", name, nrow(panels[[name]]),
              paste(sort(unique(panels[[name]]$y)), collapse = ",")))
