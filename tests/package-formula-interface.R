# Installed-package checks for the model-formula route of gt_fit() and
# gt_preflight().
#
# A formula is a second way of saying what gt_design() says; it must never be a
# second model. Every check here therefore compares the formula route with the
# design route on the same data and asks for identical sources, identical
# estimates, and identical refusals, in both argument orders and with a family
# in the position glm() users put it.
library(Gtheory4LLM)

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
outcome <- function(expr) tryCatch({ force(expr); "accepted" }, error = conditionMessage)
same <- function(a, b, label) expect(isTRUE(all.equal(a, b)), label)

d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
d$second <- cos(d$item) + d$rater / 7 + sin(d$item * d$rater) / 3
quiet <- gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42, extra_tries = 2))

# --- One model, three spellings ------------------------------------------------
design <- gt_design("item", "rater", random = ~ item + rater)
by_design <- gt_fit(d, "score", design, control = quiet)
by_formula <- gt_fit(d, score ~ item + rater, control = quiet)
formula_first <- gt_fit(score ~ item + rater, d, control = quiet)
expect(identical(class(by_design), c("gt_gaussian_fit", "gt_fit")), "a Gaussian fit has one class vector")
expect(identical(class(by_formula), class(by_design)), "the formula route gives the same class")
same(gt_components(by_formula), gt_components(by_design), "formula and design fits agree")
same(gt_components(formula_first), gt_components(by_design), "the formula may come first")
expect(identical(by_formula$design$terms_requested, by_design$design$terms_requested),
       "the formula requests the same sources")
expect(identical(by_formula$design$formula, "score ~ item + rater"), "the design records its formula")
expect(is.null(by_design$design$formula), "a design built by gt_design() records none")
expect(identical(by_formula$outcomes, "score"), "the left-hand side names the outcome")
expect(identical(formula_first$call$data, quote(d)) &&
         inherits(eval(formula_first$call$outcomes), "formula"),
       "a formula-first call is recorded with the data as data")
expect(identical(deviance(by_formula), by_formula$minus2loglik), "deviance is the fitted objective")

# --- Joint outcomes, crossing and nesting ---------------------------------------
joint <- gt_fit(d, cbind(score, second) ~ item * rater, control = quiet)
joint_design <- gt_fit(d, c("score", "second"), gt_design("item", "rater"), control = quiet)
expect(identical(joint$outcomes, c("score", "second")), "cbind() names several outcomes")
expect(setequal(joint$design$terms_requested, c("item", "rater", "item:rater")), "* expands the crossing")
same(gt_components(joint), gt_components(joint_design), "a joint formula fit equals the design fit")
nested <- gt_preflight(score ~ item + rater / item, d)
nested_design <- gt_preflight(d, "score",
  gt_design("item", "rater", random = ~ item + rater + rater:item))
expect(inherits(nested, "gt_preflight"), "preflight accepts a formula")
expect(identical(nested$sources, nested_design$sources) && nested$source_counts[["requested"]] == 3L,
       "/ nests as R's formula algebra reads it")
expect(identical(gt_preflight(score ~ item + rater, d)$call$data, quote(d)),
       "a formula-first preflight records the data as data")

# --- A family after the formula, as in glm() -------------------------------------
b <- expand.grid(item = 1:6, rater = 1:3)
b$binary <- rep(c(0L, 1L, 1L), length.out = nrow(b))
zero <- gt_control(discrete = list(fixed_covariance =
  list(item = matrix(0, 1, 1), rater = matrix(0, 1, 1))))
binary_design <- gt_fit(b, "binary", design, gt_family("binary", "logit"), control = zero)
binary_formula <- gt_fit(binary ~ item + rater, b, gt_family("binary", "logit"), control = zero)
binary_named <- gt_fit(b, binary ~ item + rater, family = gt_family("binary", "logit"), control = zero)
expect(identical(class(binary_design), c("gt_discrete_fit", "gt_fit")), "a discrete fit has one class vector")
same(gt_components(binary_formula), gt_components(binary_design), "a family may follow the formula")
same(gt_components(binary_named), gt_components(binary_design), "or be named")
expect(identical(deviance(binary_formula), binary_formula$minus2loglik), "discrete deviance is the objective")

# --- Refusals are shared by fitting and preflight ----------------------------------
refusals <- list(
  both = function(f) f(d, score ~ item + rater, design),
  family_twice = function(f) f(d, score ~ item + rater, gt_family(), family = gt_family()),
  one_sided = function(f) f(d, ~ item + rater),
  transformed_outcome = function(f) f(d, log(score) ~ item + rater),
  object_alone = function(f) f(d, score ~ item),
  formula_without_data = function(f) f(score ~ item + rater, "score"),
  unknown_column = function(f) f(d, score ~ item + judge),
  outcome_on_both_sides = function(f) f(d, score ~ score + rater),
  no_design = function(f) f(d, "score"))
expected <- c(both = "not both", family_twice = "supplied twice", one_sided = "outcomes on the left",
  transformed_outcome = "left-hand side", object_alone = "at least one instrumentation facet",
  formula_without_data = "comes second", unknown_column = "Missing outcome or design columns",
  outcome_on_both_sides = "must differ", no_design = "gt_design() to declare the design")
for (name in names(refusals)) {
  fitted <- outcome(refusals[[name]](function(...) gt_fit(..., control = quiet)))
  checked <- outcome(refusals[[name]](gt_preflight))
  expect(grepl(expected[[name]], fitted, fixed = TRUE),
         paste0("gt_fit refuses '", name, "' for the documented reason; got: ", fitted))
  expect(grepl(expected[[name]], checked, fixed = TRUE),
         paste0("gt_preflight refuses '", name, "' for the same reason; got: ", checked))
}

# --- Nothing in a formula is evaluated ---------------------------------------------
probe <- new.env(parent = emptyenv())
probe$called <- FALSE
armed <- score ~ item + { probe$called <- TRUE; rater }
expect(!identical(outcome(gt_fit(d, armed, control = quiet)), "accepted"), "executable blocks are refused")
expect(!probe$called, "and never run")

cat("PASS: the formula route declares the same model as gt_design(), in either order, with a family where glm() puts it.\n")
