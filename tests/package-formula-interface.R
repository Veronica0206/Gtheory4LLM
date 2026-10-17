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
         inherits(eval(formula_first$call$formula), "formula") && is.null(formula_first$call$outcomes),
       "a formula-first call is recorded with the data as data and the formula as formula")
expect(identical(deviance(by_formula), by_formula$minus2loglik), "deviance is the fitted objective")

# --- The object of measurement is explicit or visibly defaulted ------------------
named <- gt_fit(formula = score ~ item + rater, data = d, control = quiet)
same(gt_components(named), gt_components(by_design), "the formula may be given under its own name")
reordered <- gt_fit(d, score ~ rater + item, control = quiet)
measured <- gt_fit(d, score ~ rater + item, measured = "item", control = quiet)
expect(identical(reordered$design$object, "rater") && identical(measured$design$object, "item"),
       "without measured the first right-hand variable is the object; measured overrides it")
same(gt_components(reordered), gt_components(by_design), "re-ordering leaves the variance components unchanged")
same(gt_reliability(measured)$per_trait, gt_reliability(by_design)$per_trait,
     "the same object of measurement gives the same coefficients")
expect(!isTRUE(all.equal(gt_reliability(reordered)$per_trait$Phi, gt_reliability(by_design)$per_trait$Phi)),
       "a different object of measurement gives different coefficients")
expect(identical(reordered$design$object_rule, "first right-hand variable") &&
         identical(measured$design$object_rule, "declared"), "the design records which rule applied")
expect(any(grepl("object of measurement: rater (first right-hand variable)",
                 capture.output(print(reordered$design)), fixed = TRUE)),
       "the design print says which variable is measured and why")
expect(any(grepl("Object of measurement: rater | facets: item", capture.output(print(reordered)), fixed = TRUE)),
       "the fit print names the object of measurement")

# --- formula() and update() work for fits declared either way ------------------
expect(identical(formula(by_formula), score ~ item + rater), "formula() returns the declared formula")
expect(identical(formula(by_design), score ~ item + rater), "formula() reconstructs a design fit's formula")
crossed_design <- gt_fit(d, "score", gt_design("item", "rater"), control = quiet)
expect(identical(formula(crossed_design), score ~ item + rater + item:rater),
       "the reconstructed formula lists the requested sources")
updated <- update(by_design, . ~ . + item:rater)
same(gt_components(updated), gt_components(crossed_design), "update() refits the edited model")
expect(identical(updated$design$object, "item") && identical(updated$call$measured, "item"),
       "update() carries the object of measurement explicitly")
expect(identical(update(by_formula, estimator = "ML")$estimator, "ML"), "update() replaces an argument")
expect(identical(update(reordered, . ~ ., measured = "item")$design$object, "item"),
       "update() can redeclare the object of measurement")
expect(is.call(update(by_formula, . ~ . + item:rater, evaluate = FALSE)), "evaluate = FALSE returns the call")
expect(identical(names(by_formula$call)[2:3], c("data", "formula")), "the recorded call names the formula")

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
  no_design = function(f) f(d, "score"),
  measured_with_design = function(f) f(d, "score", design, measured = "item"),
  measured_not_in_formula = function(f) f(d, score ~ item + rater, measured = "judge"),
  outcomes_and_formula = function(f) f(d, "score", formula = score ~ item + rater),
  formula_not_a_formula = function(f) f(d, formula = "score ~ item + rater"))
expected <- c(both = "not both", family_twice = "supplied twice", one_sided = "outcomes on the left",
  transformed_outcome = "left-hand side", object_alone = "at least one instrumentation facet",
  formula_without_data = "comes second", unknown_column = "Missing outcome or design columns",
  outcome_on_both_sides = "must differ", no_design = "gt_design() to declare the design",
  measured_with_design = "applies with a model formula",
  measured_not_in_formula = "measured must name one variable",
  outcomes_and_formula = "Supply the model once", formula_not_a_formula = "formula must be")
for (name in names(refusals)) {
  fitted <- outcome(refusals[[name]](function(...) gt_fit(..., control = quiet)))
  checked <- outcome(refusals[[name]](gt_preflight))
  expect(grepl(expected[[name]], fitted, fixed = TRUE),
         paste0("gt_fit refuses '", name, "' for the documented reason; got: ", fitted))
  expect(grepl(expected[[name]], checked, fixed = TRUE),
         paste0("gt_preflight refuses '", name, "' for the same reason; got: ", checked))
}

# --- update() refuses what a formula cannot carry -------------------------------------
dropped <- gt_fit(d, score ~ item + rater,
  control = gt_control(gaussian = list(check_hessian = FALSE, retry_seed = 42), retain = list(data = FALSE)))
expect(grepl("without its data", outcome(update(dropped, . ~ . + item:rater)), fixed = TRUE),
       "a fit stored without data asks for data =")
same(gt_components(update(dropped, . ~ . + item:rater, data = d)), gt_components(crossed_design),
     "and refits once data = is supplied")
# Recorded design states that no formula can express, exercised on a copy of an
# accepted fit so the guard is tested apart from the engines' own support.
with_replicates <- by_design
with_replicates$design$replicates <- 2L
with_batch <- by_design
with_batch$design$batch <- gt_batch(2)
for (blocked in list(with_replicates, with_batch))
  expect(grepl("cannot carry a batch declaration or replicates",
               outcome(update(blocked, . ~ . + item:rater)), fixed = TRUE),
         "a design with replicates or a batch declaration refuses a formula update")
expect(identical(update(with_batch, estimator = "ML")$estimator, "ML"),
       "but other arguments can still be updated")

# --- Nothing in a formula is evaluated ---------------------------------------------
probe <- new.env(parent = emptyenv())
probe$called <- FALSE
armed <- score ~ item + { probe$called <- TRUE; rater }
expect(!identical(outcome(gt_fit(d, armed, control = quiet)), "accepted"), "executable blocks are refused")
expect(!probe$called, "and never run")

cat("PASS: the formula route declares the same model as gt_design(), in either order, with a family where glm() puts it.\n")
