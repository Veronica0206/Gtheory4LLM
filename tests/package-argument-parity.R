# Installed-package checks that preflight and fitting accept and reject exactly
# the same requests, and that argument checks report what is wrong.
#
# A preflight that permits what fitting refuses is worse than no preflight: it
# tells a user their design is ready and then fails at the expensive step. The
# two paths now share one definition of these rules, and this test is what keeps
# them sharing it.
library(Gtheory4LLM)

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
outcome <- function(expr) tryCatch({ force(expr); "accepted" }, error = conditionMessage)

d <- expand.grid(item = 1:12, rater = 1:3)
d$score <- sin(d$item) + d$rater / 5 + cos(d$item * d$rater) / 4
design <- gt_design("item", "rater", random = ~ item + rater)
quiet <- gt_control(gaussian = list(check_hessian = FALSE))

preflight_outcome <- function(...) outcome(gt_preflight(d, "score", design, ...))
fit_outcome <- function(...) outcome(gt_fit(d, "score", design, ..., control = quiet))

# --- Covariance requests -----------------------------------------------------
covariance_requests <- list(
  valid_scalar = "diagonal",
  valid_override = c(item = "unstructured"),
  residual_override = c(Residual = "diagonal"),
  unknown_source = c(nonsense = "diagonal"),
  unknown_structure = c(item = "bogus"),
  unnamed_vector = c("diagonal", "unstructured"),
  empty = character(),
  missing_name = stats::setNames(c("diagonal", "unstructured"), c("item", NA)),
  duplicate_name = stats::setNames(c("diagonal", "unstructured"), c("item", "item")),
  not_character = 1)
for (name in names(covariance_requests)) {
  request <- covariance_requests[[name]]
  before <- preflight_outcome(covariance = request)
  after <- fit_outcome(covariance = request)
  expect(identical(before, after),
         paste0("covariance request '", name, "' must be treated identically: preflight said '",
                before, "', fitting said '", after, "'"))
}
# The two requests that must be refused, with a message that says what to do.
expect(grepl("residual argument", preflight_outcome(covariance = c(Residual = "diagonal"))),
       "a Residual override points at the residual argument")
expect(grepl("retained random sources",
             preflight_outcome(covariance = c(nonsense = "diagonal"))),
       "an unknown override names the sources it could have used")
expect(identical(preflight_outcome(covariance = c(item = "unstructured")), "accepted"),
       "a valid named override is accepted")

# --- Residual requests -------------------------------------------------------
for (residual in list("unstructured", "diagonal", "pooled", "un", "Diagonal", "",
                      NA_character_, c("diagonal", "pooled"), 1)) {
  before <- preflight_outcome(residual = residual)
  after <- fit_outcome(residual = residual)
  expect(identical(before, after),
         paste0("residual request '", paste(format(residual), collapse = ", "),
                "' must be treated identically: preflight said '", before,
                "', fitting said '", after, "'"))
}
expect(identical(preflight_outcome(residual = "un"), preflight_outcome(residual = "bogus")),
       "an abbreviation is not silently completed in either path")

# --- Discrete covariance -----------------------------------------------------
set.seed(11)
binary_panel <- expand.grid(rater = factor(1:5), item = factor(1:14))
binary_panel$label <- rbinom(nrow(binary_panel), 1L,
                             plogis(rnorm(14, sd = .7)[binary_panel$item]))
reduced <- gt_design("item", "rater", full_cell = FALSE)
for (request in list("diagonal", "unstructured", c(item = "diagonal"), "bogus",
                     c("diagonal", "unstructured"))) {
  before <- outcome(gt_preflight(binary_panel, "label", reduced, gt_family("binary"),
                                 covariance = request))
  after <- outcome(gt_fit(binary_panel, "label", reduced, gt_family("binary"),
                          covariance = request,
                          control = gt_control(discrete = list(maxit = 120L))))
  expect(identical(before, after),
         paste0("discrete covariance request '", paste(format(request), collapse = ", "),
                "' must be treated identically: preflight said '", before,
                "', fitting said '", after, "'"))
}
# A Gaussian residual structure has no meaning for a discrete outcome.
expect(identical(outcome(gt_preflight(binary_panel, "label", reduced, gt_family("binary"),
                                      residual = "diagonal")),
                 outcome(gt_fit(binary_panel, "label", reduced, gt_family("binary"),
                                residual = "diagonal"))),
       "a Gaussian residual request on a discrete outcome is refused identically")

# --- plot() argument checking ------------------------------------------------
fit <- gt_fit(d, "score", design, control = quiet)
study <- gt_dstudy(fit, data.frame(rater = c(2, 3, 6)))
for (bad in list(NULL, NA, NA_character_, character(), c("Erho2", "Phi"), 1, "erho2", "")) {
  message <- outcome(plot(study, coefficient = bad))
  expect(grepl("coefficient must be one of", message, fixed = TRUE),
         paste0("plot(coefficient = ", paste(deparse(bad), collapse = ""),
                ") must say what is wrong, not fail on a zero-length condition; got: ", message))
}
for (bad in list(NULL, NA, "yes", c(TRUE, FALSE)))
  expect(grepl("interval must be TRUE or FALSE", outcome(plot(study, interval = bad)), fixed = TRUE),
         "plot(interval = ...) reports an invalid flag")
# Both valid coefficients still plot to the null device.
grDevices::pdf(NULL)
on.exit(grDevices::dev.off(), add = TRUE)
for (coefficient in c("Erho2", "Phi"))
  expect(identical(outcome(plot(study, coefficient = coefficient)), "accepted"),
         paste("plot accepts", coefficient))

cat("PASS: preflight and fitting share one definition of every covariance and residual rule.\n")
