# Installed-package checks for nested designs: reliability, mixed fixed/nested
# weighting, and decision studies that project a nested child count.
#
# Every expected coefficient is written out from the published Brennan (2001)
# formulas for the design in question. Nothing here calls an internal helper to
# produce the answer it then checks, so an error shared between the weighting
# code and the test cannot hide.
#
# A nested facet is declared with a within-parent code, which is what keeps the
# coded panel complete: item 1 of question 1 and item 1 of question 2 are
# different items sharing a code, and the item:question source is their
# identity. See help("gt_design") for the contrast with globally unique labels.
library(Gtheory4LLM)

near <- function(a, b, tolerance = 1e-9, label = "comparison") {
  if (!isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)))
    stop(label, " failed: maximum absolute difference ", max(abs(a - b)))
}
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
}
index <- function(...) as.integer(interaction(..., drop = TRUE))

# ---------------------------------------------------------------------------
# 1. p x (i:h): items nested within questions, both crossed with persons.
# ---------------------------------------------------------------------------
set.seed(20260913)
n_person <- 24L
n_item <- 3L
n_question <- 2L
panel <- expand.grid(item = factor(seq_len(n_item)), question = factor(seq_len(n_question)),
                     person = factor(seq_len(n_person)))
panel$score <-
  rnorm(n_person, sd = sqrt(1.30))[panel$person] +
  rnorm(n_question, sd = sqrt(.25))[panel$question] +
  rnorm(n_item * n_question, sd = sqrt(.40))[index(panel$item, panel$question)] +
  rnorm(n_person * n_question, sd = sqrt(.35))[index(panel$person, panel$question)] +
  rnorm(nrow(panel), sd = sqrt(.70))

nested_design <- gt_design("person", c("item", "question"), crossed = "question",
                           nested = list(item = "question"))
stopifnot(setequal(nested_design$terms_requested,
                   c("person", "question", "item:question", "person:question")),
          identical(unname(nested_design$nested_groups[["item"]]), "item:question"),
          identical(nested_design$construction, "crossed_nested"))

fit <- gt_fit(panel, "score", nested_design, estimator = "REML")
stopifnot(fit$numerically_accepted,
          setequal(fit$design$terms, c("person", "question", "item:question", "person:question")))
# The object-by-all-facets source is the Gaussian residual here: no separate
# person:item:question component is requested, estimated, or reported.
stopifnot(!"person:item:question" %in% names(fit$covariance_components),
          !length(fit$design$aliased_terms))

v <- function(source) fit$covariance_components[[source]][1, 1]

# Brennan (2001) p x (i:h), n_i items within each of n_h questions:
#   G   = s2_p / (s2_p + s2_ph/n_h + s2_pi:h/(n_i n_h))
#   Phi = G's denominator + s2_h/n_h + s2_i:h/(n_i n_h)
brennan_nested <- function(n_i, n_h) {
  tau <- v("person")
  delta <- v("person:question") / n_h + v("Residual") / (n_i * n_h)
  Delta <- delta + v("question") / n_h + v("item:question") / (n_i * n_h)
  c(G = tau / (tau + delta), Phi = tau / (tau + Delta))
}

observed <- brennan_nested(n_item, n_question)
random <- gt_reliability(fit)
near(random$per_trait$Erho2, observed[["G"]], 1e-12, "p x (i:h) G")
near(random$per_trait$Phi, observed[["Phi"]], 1e-12, "p x (i:h) Phi")
stopifnot(random$per_trait$Erho2 > random$per_trait$Phi,
          identical(unname(random$source_roles[["person"]]), "universe"),
          identical(unname(random$source_roles[["person:question"]]), "relative_and_absolute_error"),
          identical(unname(random$source_roles[["item:question"]]), "absolute_error"),
          identical(unname(random$source_roles[["question"]]), "absolute_error"),
          identical(unname(random$source_roles[["Residual"]]), "relative_and_absolute_error"))

# The nested source divides by the joint level count of child and parent, and
# the object-by-parent source divides by the parent count alone.
near(random$source_weights$absolute[["item:question"]], 1 / (n_item * n_question),
     1e-15, "nested-source absolute weight")
near(random$source_weights$relative[["person:question"]], 1 / n_question,
     1e-15, "object-by-parent relative weight")
near(random$source_weights$relative[["Residual"]], 1 / (n_item * n_question),
     1e-15, "nested residual weight")
stopifnot(random$source_weights$universe[["person"]] == 1,
          random$source_weights$relative[["question"]] == 0,
          random$source_weights$relative[["item:question"]] == 0)

# ---------------------------------------------------------------------------
# 2. Decision study projecting the nested child count and its parent count.
# ---------------------------------------------------------------------------
grid <- expand.grid(item = c(1, 3, 6), question = c(2, 4))
study <- gt_dstudy(fit, grid)
stopifnot(nrow(study$results) == nrow(grid),
          all(study$allocations$item == grid$item),
          all(study$allocations$question == grid$question),
          all(study$measurements_per_object == grid$item * grid$question))
for (row in seq_len(nrow(grid))) {
  expected <- brennan_nested(grid$item[row], grid$question[row])
  near(study$results$Erho2[row], expected[["G"]], 1e-12,
       paste0("nested D-study G at n_i=", grid$item[row], ", n_h=", grid$question[row]))
  near(study$results$Phi[row], expected[["Phi"]], 1e-12,
       paste0("nested D-study Phi at n_i=", grid$item[row], ", n_h=", grid$question[row]))
}
# Doubling only the children leaves the object-by-parent error untouched, so
# relative error must fall by less than half: the denominator behaviour that
# separates a nested child from a crossed facet.
base_row <- which(grid$item == 3 & grid$question == 2)
doubled_row <- which(grid$item == 6 & grid$question == 2)
relative_error <- function(n_i, n_h) v("person:question") / n_h + v("Residual") / (n_i * n_h)
near(relative_error(6, 2), v("person:question") / 2 + v("Residual") / 12, 1e-15,
     "hand-written nested relative error")
stopifnot(relative_error(6, 2) > relative_error(3, 2) / 2,
          study$results$Erho2[doubled_row] > study$results$Erho2[base_row])
# One allocation matches the fitted panel exactly and must reproduce it.
near(study$results$Erho2[base_row], random$per_trait$Erho2, 1e-12,
     "nested D-study at the observed allocation")

# ---------------------------------------------------------------------------
# 3. p x (i:h) with the nesting parent fixed.
# ---------------------------------------------------------------------------
# With h fixed, the object-by-h interaction is averaged over its n_h levels and
# joins the universe score; h itself shifts every person equally and leaves the
# model. The nested i:h source keeps a random child, so it stays absolute error.
tau_fixed <- v("person") + v("person:question") / n_question
delta_fixed <- v("Residual") / (n_item * n_question)
Delta_fixed <- delta_fixed + v("item:question") / (n_item * n_question)
mixed <- gt_reliability(fit, fixed = "question")
near(mixed$per_trait$Erho2, tau_fixed / (tau_fixed + delta_fixed), 1e-12,
     "p x (i:h) with fixed h, G")
near(mixed$per_trait$Phi, tau_fixed / (tau_fixed + Delta_fixed), 1e-12,
     "p x (i:h) with fixed h, Phi")
stopifnot(identical(mixed$fixed_facets, "question"),
          identical(unname(mixed$source_roles[["person:question"]]),
                    "universe_after_fixed_facet_averaging"),
          identical(unname(mixed$source_roles[["question"]]),
                    "dropped_fixed_instrumentation_constant"),
          identical(unname(mixed$source_roles[["item:question"]]), "absolute_error"),
          mixed$per_trait$Erho2 > random$per_trait$Erho2)

# A fixed parent still allows projecting its random children.
child_study <- gt_dstudy(fit, data.frame(item = c(3, 6)), fixed = "question")
for (row in 1:2) {
  n_i <- c(3, 6)[row]
  delta <- v("Residual") / (n_i * n_question)
  near(child_study$results$Erho2[row], tau_fixed / (tau_fixed + delta), 1e-12,
       paste0("fixed-parent nested D-study G at n_i=", n_i))
}
expect_error(gt_dstudy(fit, data.frame(question = c(2, 4)), fixed = "question"),
             "cannot project over a fixed facet")
expect_error(gt_reliability(fit, counts = c(question = 4), fixed = "question"),
             "cannot be changed")
expect_error(gt_reliability(fit, fixed = c("item", "question")),
             "At least one facet must remain random")

# ---------------------------------------------------------------------------
# 4. p x (i:h) x r, written out explicitly, with the crossed facet fixed.
# ---------------------------------------------------------------------------
# The automatic generator does not invent nested-sibling interactions, so the
# textbook eleven-component model is declared in full. This is the design where
# fixed-facet weighting and nesting have to hold at the same time.
set.seed(8080)
n_rater <- 3L
crossed <- expand.grid(rater = factor(seq_len(n_rater)), item = factor(seq_len(n_item)),
                       question = factor(seq_len(n_question)),
                       person = factor(seq_len(n_person)))
crossed$score <-
  rnorm(n_person, sd = sqrt(1.20))[crossed$person] +
  rnorm(n_question, sd = sqrt(.30))[crossed$question] +
  rnorm(n_rater, sd = sqrt(.25))[crossed$rater] +
  rnorm(n_question * n_rater, sd = sqrt(.10))[index(crossed$question, crossed$rater)] +
  rnorm(n_item * n_question, sd = sqrt(.35))[index(crossed$item, crossed$question)] +
  rnorm(n_item * n_question * n_rater, sd = sqrt(.12))[index(crossed$item, crossed$question, crossed$rater)] +
  rnorm(n_person * n_question, sd = sqrt(.40))[index(crossed$person, crossed$question)] +
  rnorm(n_person * n_rater, sd = sqrt(.20))[index(crossed$person, crossed$rater)] +
  rnorm(n_person * n_question * n_rater, sd = sqrt(.15))[index(crossed$person, crossed$question, crossed$rater)] +
  rnorm(n_person * n_item * n_question, sd = sqrt(.30))[index(crossed$person, crossed$item, crossed$question)] +
  rnorm(nrow(crossed), sd = sqrt(.50))

crossed_design <- gt_design("person", c("item", "question", "rater"),
  random = ~ person + question + rater + question:rater + item:question +
    item:question:rater + person:question + person:rater +
    person:question:rater + person:item:question)
stopifnot(length(crossed_design$terms_requested) == 10L,
          identical(crossed_design$construction, "custom"),
          !paste(c("person", "item", "question", "rater"), collapse = ":") %in%
            crossed_design$terms_requested)

crossed_fit <- gt_fit(crossed, "score", crossed_design, estimator = "REML")
stopifnot(crossed_fit$numerically_accepted,
          length(crossed_fit$covariance_components) == 11L)
w <- function(source) crossed_fit$covariance_components[[source]][1, 1]

# Brennan (2001) p x (i:h) x R with the rater facet fixed:
#   universe   = s2_p + s2_pr/n_r
#   relative   = s2_ph/n_h + s2_pi:h/(n_i n_h) + s2_phr/(n_h n_r) + s2_pir:h/(n_i n_h n_r)
#   absolute   = relative + s2_h/n_h + s2_i:h/(n_i n_h) + s2_hr/(n_h n_r) + s2_ir:h/(n_i n_h n_r)
tau3 <- w("person") + w("person:rater") / n_rater
delta3 <- w("person:question") / n_question +
  w("person:item:question") / (n_item * n_question) +
  w("person:question:rater") / (n_question * n_rater) +
  w("Residual") / (n_item * n_question * n_rater)
Delta3 <- delta3 + w("question") / n_question +
  w("item:question") / (n_item * n_question) +
  w("question:rater") / (n_question * n_rater) +
  w("item:question:rater") / (n_item * n_question * n_rater)
fixed_rater <- gt_reliability(crossed_fit, fixed = "rater")
near(fixed_rater$per_trait$Erho2, tau3 / (tau3 + delta3), 1e-12,
     "p x (i:h) x R with fixed R, G")
near(fixed_rater$per_trait$Phi, tau3 / (tau3 + Delta3), 1e-12,
     "p x (i:h) x R with fixed R, Phi")
stopifnot(
  identical(unname(fixed_rater$source_roles[["person:rater"]]),
            "universe_after_fixed_facet_averaging"),
  identical(unname(fixed_rater$source_roles[["rater"]]),
            "dropped_fixed_instrumentation_constant"),
  identical(unname(fixed_rater$source_roles[["person:question:rater"]]),
            "relative_and_absolute_error"),
  identical(unname(fixed_rater$source_roles[["item:question:rater"]]), "absolute_error"),
  identical(unname(fixed_rater$source_roles[["person:item:question"]]),
            "relative_and_absolute_error"))

# With every facet random the same fit must reproduce the fully random weights.
tau3_random <- w("person")
delta3_random <- delta3 + w("person:rater") / n_rater
Delta3_random <- Delta3 + w("person:rater") / n_rater + w("rater") / n_rater
all_random <- gt_reliability(crossed_fit)
near(all_random$per_trait$Erho2, tau3_random / (tau3_random + delta3_random), 1e-12,
     "p x (i:h) x r fully random, G")
near(all_random$per_trait$Phi, tau3_random / (tau3_random + Delta3_random), 1e-12,
     "p x (i:h) x r fully random, Phi")
stopifnot(fixed_rater$per_trait$Erho2 > all_random$per_trait$Erho2)

# Projecting the nested child in the three-facet design keeps the raters fixed.
three_facet_study <- gt_dstudy(crossed_fit, data.frame(item = c(3, 9)), fixed = "rater")
for (row in 1:2) {
  n_i <- c(3, 9)[row]
  delta <- w("person:question") / n_question +
    w("person:item:question") / (n_i * n_question) +
    w("person:question:rater") / (n_question * n_rater) +
    w("Residual") / (n_i * n_question * n_rater)
  near(three_facet_study$results$Erho2[row], tau3 / (tau3 + delta), 1e-12,
       paste0("three-facet nested D-study G at n_i=", n_i))
}
stopifnot(all(three_facet_study$allocations$rater == n_rater))

cat("PASS: nested reliability, mixed fixed/nested weighting, and nested D studies.\n")
