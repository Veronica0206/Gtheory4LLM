# Installed-package checks for Brennan (2001) mixed-model fixed facets and for
# declaring a design without its observation-level source. Every expected value
# is written out from the published formulas rather than taken from the engine.
library(Gtheory4LLM)
near <- function(a, b, tolerance = 1e-9, label = "comparison") {
  if (!isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)))
    stop(label, " failed: maximum absolute difference ", max(abs(a - b)))
}
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
}

set.seed(42)
objects <- 30L
raters <- 4L
occasions <- 2L
d <- expand.grid(occasion = factor(seq_len(occasions)), rater = factor(seq_len(raters)),
                 item = factor(seq_len(objects)))
index <- function(...) as.integer(interaction(..., drop = TRUE))
d$score <- sqrt(1.6) * rnorm(objects)[d$item] + sqrt(.3) * rnorm(raters)[d$rater] +
  sqrt(.2) * rnorm(occasions)[d$occasion] +
  sqrt(.5) * rnorm(objects * raters)[index(d$item, d$rater)] +
  sqrt(.25) * rnorm(objects * occasions)[index(d$item, d$occasion)] +
  sqrt(.15) * rnorm(raters * occasions)[index(d$rater, d$occasion)] +
  rnorm(nrow(d), sd = sqrt(.6))
design <- gt_design("item", c("rater", "occasion"))
fit <- gt_fit(d, "score", design)
stopifnot(fit$numerically_accepted,
          setequal(fit$design$terms, c("item", "rater", "occasion", "item:rater",
                                       "item:occasion", "rater:occasion")))
v <- function(source) fit$covariance_components[[source]][1, 1]

# Fully random p x i x h design (Brennan 2001, chapter 3).
tau <- v("item")
delta <- v("item:rater") / raters + v("item:occasion") / occasions +
  v("Residual") / (raters * occasions)
Delta <- delta + v("rater") / raters + v("occasion") / occasions +
  v("rater:occasion") / (raters * occasions)
random <- gt_reliability(fit)
near(random$per_trait$Erho2, tau / (tau + delta), 1e-12, "random-model G")
near(random$per_trait$Phi, tau / (tau + Delta), 1e-12, "random-model Phi")
stopifnot(!length(random$fixed_facets),
          identical(random$model, "fully random facets"),
          all(random$source_roles[c("item")] == "universe"))

# Occasion fixed (Brennan 2001, chapter 4): the object-by-occasion variance is
# averaged over its levels and joins the universe score, and the occasion main
# effect leaves the model because it shifts every object equally.
tau_mixed <- v("item") + v("item:occasion") / occasions
delta_mixed <- v("item:rater") / raters + v("Residual") / (raters * occasions)
Delta_mixed <- delta_mixed + v("rater") / raters +
  v("rater:occasion") / (raters * occasions)
mixed <- gt_reliability(fit, fixed = "occasion")
near(mixed$per_trait$Erho2, tau_mixed / (tau_mixed + delta_mixed), 1e-12, "mixed-model G")
near(mixed$per_trait$Phi, tau_mixed / (tau_mixed + Delta_mixed), 1e-12, "mixed-model Phi")
stopifnot(identical(mixed$fixed_facets, "occasion"),
          identical(unname(mixed$source_roles[["item:occasion"]]),
                    "universe_after_fixed_facet_averaging"),
          identical(unname(mixed$source_roles[["occasion"]]),
                    "dropped_fixed_instrumentation_constant"),
          identical(unname(mixed$source_roles[["rater:occasion"]]), "absolute_error"),
          identical(unname(mixed$source_roles[["item:rater"]]), "relative_and_absolute_error"),
          mixed$per_trait$Erho2 > random$per_trait$Erho2,
          mixed$per_trait$Phi > random$per_trait$Phi)
# Removing item-by-occasion error must also tighten the universe-score share, so
# the mixed coefficients still carry finite standard errors.
stopifnot(all(is.finite(unlist(mixed$per_trait[c("Erho2_se", "Phi_se")]))))

# Declaring every facet fixed leaves no sampling error to generalize over.
expect_error(gt_reliability(fit, fixed = c("rater", "occasion")),
             "At least one facet must remain random")
expect_error(gt_reliability(fit, fixed = "unknown_facet"), "unknown facet")
expect_error(gt_reliability(fit, fixed = c("rater", "rater")), "unique, nonempty")
expect_error(gt_reliability(fit, counts = c(occasion = 5), fixed = "occasion"),
             "cannot be changed")
expect_error(gt_dstudy(fit, data.frame(occasion = c(2, 4)), fixed = "occasion"),
             "cannot project over a fixed facet")

# A decision study over the remaining random facet keeps the fixed facet pinned.
study <- gt_dstudy(fit, data.frame(rater = c(2, 4, 8)), fixed = "occasion")
stopifnot(identical(study$fixed_facets, "occasion"),
          all(study$allocations$occasion == occasions),
          nrow(study$results) == 3L)
near(study$results$Erho2[study$allocations$rater == raters],
     mixed$per_trait$Erho2, 1e-12, "mixed D-study at the observed allocation")

# full_cell = FALSE removes exactly the object-by-all-facets source.
complete <- gt_design("item", c("rater", "occasion"))
reduced <- gt_design("item", c("rater", "occasion"), full_cell = FALSE)
stopifnot(setequal(setdiff(complete$terms_requested, reduced$terms_requested),
                   "item:rater:occasion"),
          setequal(reduced$terms_requested,
                   setdiff(complete$terms_requested, "item:rater:occasion")),
          isFALSE(reduced$full_cell), isTRUE(complete$full_cell),
          any(grepl("full_cell = FALSE removed", reduced$notes)))
for (bad in list(NA, "yes", c(TRUE, TRUE), NULL))
  expect_error(gt_design("item", "rater", full_cell = bad), "full_cell must be TRUE or FALSE")

# It also composes with an explicit random specification.
explicit <- gt_design("item", "rater", random = ~ item * rater, full_cell = FALSE)
stopifnot(setequal(explicit$terms_requested, c("item", "rater")))

# The discrete rejection message must name the argument that resolves it, and
# the reduced design must then fit where the default one cannot.
binary_panel <- expand.grid(rater = factor(seq_len(6)), item = factor(seq_len(20)))
set.seed(2)
binary_panel$y <- rbinom(nrow(binary_panel), 1, plogis(rnorm(20)[binary_panel$item]))
expect_error(gt_fit(binary_panel, "y", gt_design("item", "rater"), gt_family("binary")),
             "full_cell = FALSE")
binary_fit <- gt_fit(binary_panel, "y", gt_design("item", "rater", full_cell = FALSE),
                     gt_family("binary"), control = gt_control(discrete = list(maxit = 200L)))
stopifnot(binary_fit$numerically_accepted,
          setequal(binary_fit$design$terms, c("item", "rater")),
          is.finite(gt_reliability(binary_fit, scale = "latent")$per_trait$Erho2))
cat("PASS: Brennan mixed-model fixed facets, fixed-facet guards, and full_cell design reduction.\n")
