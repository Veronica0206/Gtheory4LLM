# Run from the project directory with Rscript tests/test_laplace_check_retained_data.R.
#
# gt_laplace_check() on a fit's retained data. A fit retains the engine's own
# prepared input: binary outcomes as 0/1 integers, ordinal and nominal outcomes
# as factors over the declared levels. The diagnostic must read that frame as
# the encoding it is rather than re-resolve it as new user data, which for a
# binary outcome with labels other than "0"/"1" refused the fit's own
# responses. Every fixture below is a numerically accepted fit, every
# comparison is required to be available from retained and from original data
# with the same numbers, and the usability verdict is asserted explicitly:
# the quick 200-draw comparisons are expected to fail the effective-sample-size
# screen, and one 2,000-draw case is expected to pass it. Joint and mixed
# fixtures fix their source covariances so that acceptance does not depend on
# the platform; integration precision itself is validated elsewhere.
source("load_functions.R")
expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
outcome <- function(expr) tryCatch({ force(expr); "accepted" }, error = conditionMessage)

design <- gt_design("item", "rater", full_cell = FALSE)
panel <- function(seed) {
  set.seed(seed)
  d <- expand.grid(item = 1:6, rater = 1:3)
  d$z <- rnorm(6, sd = 1.1)[d$item] + rnorm(nrow(d))
  d
}
check <- function(fit, draws = 200L, ...)
  gt_laplace_check(fit, method = "importance", draws = draws, seed = 5L, ...)
fit_quiet <- function(...) suppressWarnings(gt_fit(...))
accepted <- function(fit, label) {
  expect(isTRUE(fit$numerically_accepted) && isTRUE(fit$converged), paste(label, "fixture is numerically accepted"))
  fit
}
# Retained and explicit data must give one comparison: both available, the
# same method, dimension, usability verdict and numbers.
same <- function(a, b, label, usable) {
  expect(isTRUE(a$available) && isTRUE(b$available), paste(label, "comparison is available from retained and explicit data"))
  expect(identical(a$method, "importance") && identical(a$method, b$method) &&
           identical(a$random_dimension, b$random_dimension), paste(label, "uses the same method and dimension"))
  expect(identical(isTRUE(a$usable), usable) && identical(isTRUE(b$usable), usable),
         paste(label, "has the expected usability verdict", usable))
  expect(abs(a$laplace_minus2loglik - b$laplace_minus2loglik) <= 1e-10 &&
           abs(a$refined_minus2loglik - b$refined_minus2loglik) <= 1e-10 &&
           abs(a$difference - b$difference) <= 1e-10, paste(label, "numbers agree to 1e-10"))
  if (!usable) expect(grepl("effective sample size", a$reason, fixed = TRUE) &&
                        grepl("effective sample size", b$reason, fixed = TRUE),
                      paste(label, "names the effective-sample-size screen as the reason"))
}
fixed <- function(...) gt_control(discrete = list(fixed_covariance = list(...)))
cov2 <- matrix(c(0.6, 0.1, 0.1, 0.4), 2L)
cov3 <- matrix(c(0.6, 0.1, 0.05, 0.1, 0.5, 0.1, 0.05, 0.1, 0.4), 3L)

# --- Binary with labels, in both level orders -----------------------------------
for (levels in list(c("no", "yes"), c("yes", "no"))) {
  label <- paste("binary", paste(levels, collapse = "/"))
  d <- panel(1)
  d$y <- factor(ifelse(d$z > 0, "yes", "no"), levels = levels)
  fit <- accepted(fit_quiet(d, "y", design, family = gt_family("binary", "logit", levels = levels),
                            control = fixed(item = matrix(0.8), rater = matrix(0.3))), label)
  expect(is.integer(fit$data$y) && all(fit$data$y %in% 0:1) &&
           all(fit$data$y[d$y == levels[[1L]]] == 0L),
         paste(label, "is retained as 0/1 integers with", levels[[1L]], "coded 0"))
  same(check(fit), check(fit, data = d), label, usable = FALSE)
  same(check(fit, draws = 2000L), check(fit, draws = 2000L, data = d), paste(label, "at 2,000 draws"), usable = TRUE)
  numeric_as_new <- d; numeric_as_new$y <- as.integer(d$y == levels[[2L]])
  expect(grepl("Numeric/logical binary input", outcome(check(fit, data = numeric_as_new))),
         paste(label, ": numeric 0/1 supplied as new data is still refused"))
  relabeled <- d; relabeled$y <- factor(toupper(as.character(d$y)))
  expect(grepl("Undeclared categories", outcome(check(fit, data = relabeled))),
         paste(label, ": new data with undeclared labels is still refused"))
}

# --- An estimated-covariance binary fit on the same path -------------------------
d <- panel(1)
d$y <- factor(ifelse(d$z > 0, "yes", "no"), levels = c("no", "yes"))
estimated <- fit_quiet(d, "y", design, family = gt_family("binary", "logit", levels = c("no", "yes")))
if (isTRUE(estimated$numerically_accepted)) {
  same(check(estimated), check(estimated, data = d), "estimated binary", usable = FALSE)
} else cat("NOTE: the estimated-covariance binary fixture was refused on this platform; its comparison is not asserted.\n")

# --- Numeric 0/1 binary is unaffected -------------------------------------------
d <- panel(2); d$y <- as.integer(d$z > 0)
fit <- accepted(fit_quiet(d, "y", design, family = gt_family("binary", "logit"),
                          control = fixed(item = matrix(0.8), rater = matrix(0.3))), "numeric binary")
same(check(fit), check(fit, data = d), "numeric binary", usable = FALSE)

# --- Joint binary outcomes with different label sets and links --------------------
d <- panel(3)
d$y1 <- factor(ifelse(d$z > 0, "yes", "no"), levels = c("no", "yes"))
d$y2 <- factor(ifelse(d$z + rnorm(nrow(d)) > 0.2, "present", "absent"), levels = c("absent", "present"))
joint <- accepted(fit_quiet(d, c("y1", "y2"), design,
  family = list(y1 = gt_family("binary", "logit", levels = c("no", "yes")),
                y2 = gt_family("binary", "probit", levels = c("absent", "present"))),
  control = fixed(item = cov2, rater = cov2)), "joint binary")
expect(is.integer(joint$data$y1) && is.integer(joint$data$y2), "a joint fit retains both binary outcomes encoded")
same(check(joint), check(joint, data = d), "joint binary", usable = FALSE)

# --- Mixed families: labeled binary with ordinal, and with nominal --------------
d <- panel(4)
d$y <- factor(ifelse(d$z > 0, "yes", "no"), levels = c("no", "yes"))
d$grade <- cut(d$z + rnorm(nrow(d)), c(-Inf, -0.4, 0.4, Inf), labels = c("low", "mid", "high"), ordered_result = TRUE)
mixed <- accepted(fit_quiet(d, c("y", "grade"), design,
  family = list(y = gt_family("binary", "logit", levels = c("no", "yes")),
                grade = gt_family("ordinal", "probit", levels = c("low", "mid", "high"))),
  control = fixed(item = cov2, rater = cov2)), "binary with ordinal")
expect(is.integer(mixed$data$y) && is.ordered(mixed$data$grade), "a mixed fit retains the binary encoded and the ordinal as an ordered factor")
same(check(mixed), check(mixed, data = d), "binary with ordinal", usable = FALSE)
d$label <- factor(c("a", "b", "c")[1L + (d$item + d$rater) %% 3L], levels = c("a", "b", "c"))
nominal <- accepted(fit_quiet(d, c("y", "label"), design,
  family = list(y = gt_family("binary", "logit", levels = c("no", "yes")),
                label = gt_family("categorical", reference = "b")),
  control = fixed(item = cov3, rater = cov3)), "binary with nominal")
expect(is.factor(nominal$data$label) && !is.ordered(nominal$data$label), "a nominal outcome is retained as a factor")
same(check(nominal), check(nominal, data = d), "binary with nominal", usable = FALSE)

# --- Retention off: the check needs data, and then behaves as with retention on
d <- panel(1)
d$y <- factor(ifelse(d$z > 0, "yes", "no"), levels = c("no", "yes"))
kept <- accepted(fit_quiet(d, "y", design, family = gt_family("binary", "logit", levels = c("no", "yes")),
                           control = fixed(item = matrix(0.8), rater = matrix(0.3))), "retention on")
dropped <- accepted(fit_quiet(d, "y", design, family = gt_family("binary", "logit", levels = c("no", "yes")),
  control = gt_control(discrete = list(fixed_covariance = list(item = matrix(0.8), rater = matrix(0.3))),
                       retain = list(data = FALSE))), "retention off")
expect(is.null(dropped$data), "retention off stores no data")
expect(grepl("retain = list(data = FALSE)", outcome(check(dropped)), fixed = TRUE),
       "without retained data the check asks for data =")
same(check(dropped, data = d), check(kept), "retention off with explicit data against retention on", usable = FALSE)

# Saved auto requests must retain the coordinates that the fitting version
# resolved. Before the Cholesky default changed, the following explicit fit
# would have recorded an auto request with these same log-Cholesky parameters.
# A deliberately short fit is sufficient: this diagnostic describes the
# recorded point and must not alter its covariance coordinates.
legacy_panel <- expand.grid(item = 1:4, rater = 1:6)
legacy_panel$y <- as.integer((legacy_panel$item + legacy_panel$rater) %% 3L > 0L)
legacy_panel$z <- as.integer((2L * legacy_panel$item + legacy_panel$rater) %% 4L > 1L)
legacy_fit <- suppressWarnings(gt_fit(legacy_panel, c("y", "z"),
  gt_design("item", "rater", random = "item"), gt_family("binary", "logit"),
  covariance = "unstructured", control = gt_control(discrete = list(
    covariance_parameterization = "log_cholesky", maxit = 2L, alternative_starts = 0L))))
legacy_explicit <- gt_laplace_check(legacy_fit, draws = 100L, seed = 71L)
expect(identical(legacy_fit$diagnostics$covariance_parameterization, "log_cholesky"),
       "the fixture records resolved log-Cholesky coordinates")
legacy_fit$control$discrete$covariance_parameterization <- "auto"
legacy_auto <- gt_laplace_check(legacy_fit, draws = 100L, seed = 71L)
legacy_fit$control$discrete$covariance_parameterization <- NULL
legacy_default <- gt_laplace_check(legacy_fit, draws = 100L, seed = 71L)
for (comparison in list(legacy_auto, legacy_default)) {
  expect(isTRUE(comparison$available) && isTRUE(comparison$recomputed_agrees) &&
           abs(comparison$laplace_minus2loglik - legacy_explicit$laplace_minus2loglik) < 1e-10 &&
           abs(comparison$refined_minus2loglik - legacy_explicit$refined_minus2loglik) < 1e-10,
         "saved auto and omitted requests use their recorded covariance coordinates")
}
legacy_fit$diagnostics$covariance_parameterization <- "future_coordinates"
expect(grepl("unsupported covariance parameterization",
             outcome(gt_laplace_check(legacy_fit, draws = 100L, seed = 71L)), fixed = TRUE),
       "unknown recorded coordinates are refused rather than reinterpreted")
cat("PASS: retained response and covariance coordinates, integration and diagnostic safeguards.\n")
