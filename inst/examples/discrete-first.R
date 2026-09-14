# A first binary/ordinal G-theory fit, start to finish.
#
# Run with:
#   source(system.file("examples", "discrete-first.R", package = "Gtheory4LLM"))
#
# The one thing that trips up a first discrete fit is the object-by-all-facets
# source. With one observation per cell it cannot be told apart from the
# discrete observation model, so the package refuses it rather than dropping a
# source behind your back. Declare the design without it from the start:
# full_cell = FALSE removes exactly that one term and changes nothing else.
#
# Everything here is synthetic and needs no API key, network access or data.
library(Gtheory4LLM)

set.seed(20260913)
n_item <- 20L
n_rater <- 6L
panel <- expand.grid(rater = factor(seq_len(n_rater)), item = factor(seq_len(n_item)))
latent <- rnorm(n_item, sd = .9)[panel$item] + rnorm(n_rater, sd = .5)[panel$rater]

# ---- 1. Binary outcome -----------------------------------------------------
panel$label <- rbinom(nrow(panel), 1L, plogis(.3 + latent))

# Compare the two declarations. The default requests item:rater, which is the
# full cell of this design; the discrete engine explains why it cannot use it.
default_design <- gt_design("item", "rater")
message(tryCatch({
  gt_fit(panel, "label", default_design, gt_family("binary"))
  "unexpectedly fitted"
}, error = conditionMessage))

binary_design <- gt_design("item", "rater", full_cell = FALSE)
binary_design$terms_requested            # item, rater

# Preflight before fitting: it reports the resolved sources, the dense
# resource estimate and which reliability scale, if any, would be supported.
print(gt_preflight(panel, "label", binary_design, gt_family("binary")))

binary_fit <- gt_fit(panel, "label", binary_design, gt_family("binary"),
                     control = gt_control(discrete = list(maxit = 200L)))
print(binary_fit)

# Numerical acceptance is a precondition, not a result. Check it explicitly:
# a rejected fit refuses to produce coefficients, and that refusal is the
# intended behaviour rather than something to work around.
diagnostics <- gt_diagnostics(binary_fit)
stopifnot(isTRUE(diagnostics$numerically_accepted))
diagnostics$approximation_adequacy        # not_assessed_first_order_laplace

# Binary and ordinal coefficients live on the latent response scale and must
# be requested explicitly. They are not the reliability of observed labels,
# majority votes, or agreement rates, and they carry no interval: the dense
# Laplace engine computes no observed information.
print(gt_reliability(binary_fit, scale = "latent"))
print(gt_dstudy(binary_fit, data.frame(rater = c(3, 6, 12)), scale = "latent"))

# ---- 2. Ordinal outcome ----------------------------------------------------
# The same design declaration works for ordered categories. Declare the order
# with an ordered factor (or gt_family(levels = ...)); it is never inferred.
# The category boundaries apply to the latent response plus its own variation:
# a category that is a deterministic function of the random effects separates
# perfectly, which no threshold model can fit.
graded <- latent + rlogis(nrow(panel))
panel$grade <- ordered(c("low", "medium", "high")[
  1L + (graded > -.6) + (graded > .6)], levels = c("low", "medium", "high"))

ordinal_fit <- gt_fit(panel, "grade", gt_design("item", "rater", full_cell = FALSE),
                      gt_family("ordinal", "logit"),
                      control = gt_control(discrete = list(maxit = 200L)))
print(summary(ordinal_fit))
if (isTRUE(gt_diagnostics(ordinal_fit)$numerically_accepted))
  print(gt_reliability(ordinal_fit, scale = "latent"))

# ---- What this example does not establish ----------------------------------
# An accepted fit means the optimizer completed and the package's independent
# stationarity, restart and bound checks passed. It does not establish that the
# first-order Laplace approximation is accurate for this design, that the
# optimum is global, or that this many raters is scientifically enough. See
# docs/LIMITATIONS.md and docs/VALIDATION_SCOPE.md in the source repository.
invisible(NULL)
