# Property-based checks: things that must hold for every fit, not for one.
#
# A regression test pins one answer. These pin relationships between answers,
# which is a different kind of evidence: a bug that produces a plausible wrong
# number usually breaks one of these, because it has to respect an invariance
# it was never written to respect.
#
# Every property here is a mathematical consequence of the declared model, not
# an observation about the current implementation.
library(Gtheory4LLM)

failures <- character()
property <- function(label, condition) {
  ok <- isTRUE(tryCatch(condition, error = function(e)
    paste("error:", conditionMessage(e))))
  if (!ok) failures <<- c(failures, label)
  invisible(ok)
}
close_enough <- function(a, b, tolerance = 1e-6) {
  a <- unname(unlist(a))
  b <- unname(unlist(b))
  length(a) == length(b) &&
    isTRUE(all.equal(a, b, tolerance = tolerance, check.attributes = FALSE))
}
components <- function(fit) fit$covariance_components[order(names(fit$covariance_components))]
variances <- function(fit) unlist(lapply(components(fit), diag), use.names = TRUE)

set.seed(4711)
n_item <- 18L
n_rater <- 4L
n_occasion <- 2L
panel <- expand.grid(occasion = factor(seq_len(n_occasion)), rater = factor(seq_len(n_rater)),
                     item = factor(seq_len(n_item)))
index <- function(...) as.integer(interaction(..., drop = TRUE))
panel$y <- rnorm(n_item, sd = 1.1)[panel$item] + rnorm(n_rater, sd = .6)[panel$rater] +
  rnorm(n_occasion, sd = .4)[panel$occasion] +
  rnorm(n_item * n_rater, sd = .5)[index(panel$item, panel$rater)] +
  rnorm(nrow(panel), sd = .8)
panel$z <- .5 * rnorm(n_item, sd = 1.1)[panel$item] + rnorm(nrow(panel), sd = .9)

design <- gt_design("item", c("rater", "occasion"))
fit_panel <- function(data, outcomes = "y", ...)
  gt_fit(data, outcomes, design, ..., control = gt_control(gaussian = list(retry_seed = 5L)))
baseline <- fit_panel(panel)
stopifnot(baseline$numerically_accepted)

# --- 1. Every fitted covariance is a covariance ------------------------------
joint <- fit_panel(panel, c("y", "z"), covariance = "unstructured")
for (name in names(joint$covariance_components)) {
  M <- joint$covariance_components[[name]]
  property(paste(name, "is symmetric"), max(abs(M - t(M))) <= 1e-8 * max(1, max(abs(M))))
  eigenvalues <- eigen(M, symmetric = TRUE, only.values = TRUE)$values
  property(paste(name, "is positive semidefinite"),
           min(eigenvalues) >= -1e-8 * max(1, max(abs(eigenvalues))))
}

# --- 2. Row order carries no information -------------------------------------
# The panel is a set of measurements, so the order they arrive in cannot change
# a variance component. This is the property most likely to catch an indexing
# bug in the factorial-stratum preparation.
for (seed in c(1L, 2L, 3L)) {
  set.seed(seed)
  shuffled <- panel[sample(nrow(panel)), , drop = FALSE]
  rownames(shuffled) <- NULL
  property(paste0("row order does not change the estimates (seed ", seed, ")"),
           close_enough(variances(fit_panel(shuffled)), variances(baseline)))
}
# Reversing the rows is the worst case for an order-dependent index.
property("reversed rows do not change the likelihood",
         close_enough(fit_panel(panel[rev(seq_len(nrow(panel))), ])$minus2loglik,
                      baseline$minus2loglik))

# --- 3. Level labels are names, not values -----------------------------------
# Relabelling the raters changes which contrasts the engine builds, but not the
# space they span, so every variance component must be unchanged.
relabelled <- panel
levels(relabelled$rater) <- c("zeta", "alpha", "omega", "beta")
levels(relabelled$occasion) <- c("later", "earlier")
property("relabelling facet levels does not change the estimates",
         close_enough(variances(fit_panel(relabelled)), variances(baseline)))
property("relabelling facet levels does not change reliability",
         close_enough(gt_reliability(fit_panel(relabelled))$per_trait$Erho2,
                      gt_reliability(baseline)$per_trait$Erho2))

# Renaming a column renames its source, and nothing else.
renamed <- panel
names(renamed)[names(renamed) == "rater"] <- "judge"
renamed_fit <- gt_fit(renamed, "y", gt_design("item", c("judge", "occasion")),
                      control = gt_control(gaussian = list(retry_seed = 5L)))
property("renaming a facet renames its source and nothing else",
         close_enough(sort(unname(variances(renamed_fit))), sort(unname(variances(baseline)))))
property("the renamed source keeps its own variance",
         close_enough(renamed_fit$covariance_components[["item:judge"]],
                      baseline$covariance_components[["item:rater"]]))

# --- 4. Declaring facets in another order is the same design -----------------
# Source *names* follow the declared facet order, so "rater:occasion" becomes
# "occasion:rater". The model does not change: match sources by the set of
# variables they are built from, and every variance must agree.
by_members <- function(fit) {
  members <- vapply(strsplit(names(fit$covariance_components), ":", fixed = TRUE),
                    function(parts) paste(sort(parts), collapse = "+"), character(1))
  stats::setNames(vapply(fit$covariance_components, function(M) M[1L, 1L], numeric(1)), members)
}
reordered_design <- gt_design("item", c("occasion", "rater"))
reordered <- gt_fit(panel, "y", reordered_design,
                    control = gt_control(gaussian = list(retry_seed = 5L)))
property("facet declaration order does not change the likelihood",
         close_enough(reordered$minus2loglik, baseline$minus2loglik))
property("facet declaration order does not change any source variance",
         close_enough(by_members(reordered)[names(by_members(baseline))], by_members(baseline)))
property("facet declaration order does not change reliability",
         close_enough(gt_reliability(reordered)$per_trait[c("Erho2", "Phi")],
                      gt_reliability(baseline)$per_trait[c("Erho2", "Phi")]))
property("only the source labels differ",
         setequal(names(by_members(reordered)), names(by_members(baseline))) &&
           !identical(sort(names(reordered$covariance_components)),
                      sort(names(baseline$covariance_components))))

# --- 5. Scale equivariance ---------------------------------------------------
# Multiplying the outcome by c multiplies every variance by c squared, and
# leaves every reliability coefficient exactly where it was: a coefficient is a
# ratio of variances on the same scale.
for (scale in c(0.25, 10)) {
  scaled <- panel
  scaled$y <- scale * panel$y
  scaled_fit <- fit_panel(scaled)
  property(paste("variances scale by the square of", scale),
           close_enough(variances(scaled_fit), scale^2 * variances(baseline), 1e-5))
  property(paste("reliability is invariant to scaling by", scale),
           close_enough(gt_reliability(scaled_fit)$per_trait[c("Erho2", "Phi")],
                        gt_reliability(baseline)$per_trait[c("Erho2", "Phi")], 1e-6))
}

# --- 6. Location invariance --------------------------------------------------
shifted <- panel
shifted$y <- panel$y + 37
shifted_fit <- fit_panel(shifted)
property("shifting the outcome does not change any variance",
         close_enough(variances(shifted_fit), variances(baseline), 1e-5))
property("shifting the outcome shifts the mean by the same amount",
         close_enough(unname(shifted_fit$means) - unname(baseline$means), 37, 1e-6))

# --- 7. Outcome order is a labelling of the joint model ----------------------
swapped <- fit_panel(panel, c("z", "y"), covariance = "unstructured")
property("swapping outcomes permutes the covariance matrices consistently",
         close_enough(joint$covariance_components[["item"]],
                      swapped$covariance_components[["item"]][c("y", "z"), c("y", "z")], 1e-5))
property("swapping outcomes does not change the likelihood",
         close_enough(joint$minus2loglik, swapped$minus2loglik, 1e-6))
property("swapping outcomes does not change per-outcome reliability",
         close_enough(gt_reliability(joint)$per_trait$Erho2,
                      rev(gt_reliability(swapped)$per_trait$Erho2), 1e-6))

# --- 8. More measurements cannot reduce reliability --------------------------
# Every error component carries a facet count in its divisor and the universe
# score carries none, so in the fully random model both coefficients are
# non-decreasing in every facet count. This is exact arithmetic on fitted
# components, not an empirical tendency.
grid <- expand.grid(rater = c(1, 2, 4, 8, 16), occasion = c(1, 2, 4))
study <- gt_dstudy(baseline, grid)
for (fixed_occasion in unique(grid$occasion)) {
  rows <- which(study$allocations$occasion == fixed_occasion)
  rows <- rows[order(study$allocations$rater[rows])]
  for (coefficient in c("Erho2", "Phi"))
    property(paste0(coefficient, " is non-decreasing in raters at occasion=", fixed_occasion),
             all(diff(study$results[[coefficient]][rows]) >= -1e-12))
}
for (fixed_rater in unique(grid$rater)) {
  rows <- which(study$allocations$rater == fixed_rater)
  rows <- rows[order(study$allocations$occasion[rows])]
  for (coefficient in c("Erho2", "Phi"))
    property(paste0(coefficient, " is non-decreasing in occasions at rater=", fixed_rater),
             all(diff(study$results[[coefficient]][rows]) >= -1e-12))
}
property("Phi never exceeds G", all(study$results$Phi <= study$results$Erho2 + 1e-12))
property("both coefficients stay in the unit interval",
         all(study$results$Erho2 >= 0 & study$results$Erho2 <= 1 &
             study$results$Phi >= 0 & study$results$Phi <= 1))

# Fixing a facet can only move variance from error into the universe score, so
# it can never lower either coefficient.
fixed <- gt_reliability(baseline, fixed = "occasion")
random <- gt_reliability(baseline)
property("fixing a facet does not lower G", fixed$per_trait$Erho2 >= random$per_trait$Erho2 - 1e-12)
property("fixing a facet does not lower Phi", fixed$per_trait$Phi >= random$per_trait$Phi - 1e-12)

# --- 9. A composite of one outcome is that outcome ---------------------------
single <- gt_reliability(joint, score = gt_score(c(y = 1, z = 0)))
property("a degenerate composite reproduces its single outcome",
         close_enough(single$composite$Erho2,
                      gt_reliability(joint)$per_trait$Erho2[1L], 1e-10))
property("rescaling composite weights does not change the composite",
         close_enough(gt_reliability(joint, score = gt_score(c(y = 2, z = 2)))$composite$Erho2,
                      gt_reliability(joint, score = gt_score(c(y = .5, z = .5)))$composite$Erho2,
                      1e-10))

# --- 10. Discrete fits share the invariances that do not involve scale -------
set.seed(88)
discrete_panel <- expand.grid(rater = factor(1:6), item = factor(1:16))
discrete_panel$label <- rbinom(nrow(discrete_panel), 1L,
  plogis(rnorm(16, sd = .8)[discrete_panel$item] + rnorm(6, sd = .4)[discrete_panel$rater]))
reduced <- gt_design("item", "rater", full_cell = FALSE)
discrete_fit <- function(data) suppressWarnings(gt_fit(data, "label", reduced,
  gt_family("binary"), control = gt_control(discrete = list(maxit = 200L))))
discrete_baseline <- discrete_fit(discrete_panel)

set.seed(9)
discrete_shuffled <- discrete_panel[sample(nrow(discrete_panel)), , drop = FALSE]
rownames(discrete_shuffled) <- NULL
property("row order does not change a discrete likelihood",
         close_enough(discrete_fit(discrete_shuffled)$minus2loglik,
                      discrete_baseline$minus2loglik, 1e-6))
property("row order does not change discrete variance components",
         close_enough(variances(discrete_fit(discrete_shuffled)),
                      variances(discrete_baseline), 1e-4))
discrete_relabelled <- discrete_panel
levels(discrete_relabelled$rater) <- rev(letters[1:6])
property("relabelling groups does not change a discrete likelihood",
         close_enough(discrete_fit(discrete_relabelled)$minus2loglik,
                      discrete_baseline$minus2loglik, 1e-6))
# Swapping which label is the positive category flips the sign of the intercept
# and leaves the latent variance, and therefore the coefficient, alone.
flipped <- discrete_panel
flipped$label <- 1L - discrete_panel$label
flipped_fit <- discrete_fit(flipped)
property("flipping the binary coding negates the intercept",
         close_enough(unname(coef(flipped_fit)), -unname(coef(discrete_baseline)), 1e-4))
property("flipping the binary coding leaves latent reliability unchanged",
         close_enough(gt_reliability(flipped_fit, scale = "latent")$per_trait$Erho2,
                      gt_reliability(discrete_baseline, scale = "latent")$per_trait$Erho2, 1e-4))

if (length(failures))
  stop("Properties violated:\n", paste0("- ", failures, collapse = "\n"))
cat("PASS: invariance, equivariance, and monotonicity properties of fits and coefficients.\n")
