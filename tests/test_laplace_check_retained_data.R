# Run from the project directory with Rscript tests/test_laplace_check_retained_data.R.
#
# gt_laplace_check() on a fit's retained data. A fit retains the engine's own
# prepared input: binary outcomes as 0/1 integers, ordinal and nominal outcomes
# as factors over the declared levels. The diagnostic must read that frame as
# the encoding it is rather than re-resolve it as new user data, which for a
# binary outcome with labels other than "0"/"1" refused the fit's own
# responses. Each case checks that the retained-data call succeeds and gives
# the same numbers as the same call on the original labeled data, and that
# data supplied by the caller still passes the strict resolver.
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
check <- function(fit, ...) gt_laplace_check(fit, method = "importance", draws = 200L, seed = 5L, ...)
same <- function(a, b) identical(a$available, b$available) && identical(a$method, b$method) &&
  identical(a$random_dimension, b$random_dimension) &&
  abs(a$laplace_minus2loglik - b$laplace_minus2loglik) <= 1e-10 &&
  (!isTRUE(a$available) || (abs(a$refined_minus2loglik - b$refined_minus2loglik) <= 1e-10 &&
                              abs(a$difference - b$difference) <= 1e-10))
fit_quiet <- function(...) suppressWarnings(gt_fit(...))

# --- Binary with labels, in both level orders -----------------------------------
for (levels in list(c("no", "yes"), c("yes", "no"))) {
  d <- panel(1)
  d$y <- factor(ifelse(d$z > 0, "yes", "no"), levels = levels)
  fit <- fit_quiet(d, "y", design, family = gt_family("binary", "logit", levels = levels))
  expect(is.integer(fit$data$y) && all(fit$data$y %in% 0:1) &&
           all(fit$data$y[d$y == levels[[1L]]] == 0L),
         paste("the fit retains the binary outcome as 0/1 integers with", levels[[1L]], "coded 0"))
  retained <- check(fit)
  explicit <- check(fit, data = d)
  expect(isTRUE(retained$available), paste("the retained-data check is available for levels", paste(levels, collapse = "/")))
  expect(same(retained, explicit), paste("retained and explicit data give the same comparison for levels", paste(levels, collapse = "/")))
  numeric_as_new <- d; numeric_as_new$y <- as.integer(d$y == levels[[2L]])
  expect(grepl("Numeric/logical binary input", outcome(check(fit, data = numeric_as_new))),
         "numeric 0/1 supplied as new data for a labeled family is still refused")
  relabeled <- d; relabeled$y <- factor(toupper(as.character(d$y)))
  expect(grepl("Undeclared categories", outcome(check(fit, data = relabeled))),
         "new data with undeclared labels is still refused")
}

# --- Numeric 0/1 binary is unaffected -------------------------------------------
d <- panel(2); d$y <- as.integer(d$z > 0)
fit <- fit_quiet(d, "y", design, family = gt_family("binary", "logit"))
expect(same(check(fit), check(fit, data = d)), "a numeric 0/1 binary outcome checks the same way from either source")

# --- Joint binary outcomes with different label sets ----------------------------
d <- panel(3)
d$y1 <- factor(ifelse(d$z > 0, "yes", "no"), levels = c("no", "yes"))
d$y2 <- factor(ifelse(d$z + rnorm(nrow(d)) > 0.2, "present", "absent"), levels = c("absent", "present"))
joint <- fit_quiet(d, c("y1", "y2"), design,
  family = list(y1 = gt_family("binary", "logit", levels = c("no", "yes")),
                y2 = gt_family("binary", "probit", levels = c("absent", "present"))))
expect(is.integer(joint$data$y1) && is.integer(joint$data$y2), "a joint fit retains both binary outcomes encoded")
expect(same(check(joint), check(joint, data = d)), "joint binary outcomes check the same way from retained and explicit data")

# --- Mixed families: labeled binary with ordinal, and with nominal --------------
d <- panel(4)
d$y <- factor(ifelse(d$z > 0, "yes", "no"), levels = c("no", "yes"))
d$grade <- cut(d$z + rnorm(nrow(d)), c(-Inf, -0.4, 0.4, Inf), labels = c("low", "mid", "high"), ordered_result = TRUE)
mixed <- fit_quiet(d, c("y", "grade"), design,
  family = list(y = gt_family("binary", "logit", levels = c("no", "yes")),
                grade = gt_family("ordinal", "probit", levels = c("low", "mid", "high"))))
expect(is.integer(mixed$data$y) && is.ordered(mixed$data$grade), "a mixed fit retains the binary encoded and the ordinal as an ordered factor")
expect(same(check(mixed), check(mixed, data = d)), "binary with ordinal checks the same way from retained and explicit data")
d$label <- factor(c("a", "b", "c")[1L + (d$item + d$rater) %% 3L], levels = c("a", "b", "c"))
nominal <- fit_quiet(d, c("y", "label"), design,
  family = list(y = gt_family("binary", "logit", levels = c("no", "yes")),
                label = gt_family("categorical", reference = "b")))
expect(is.factor(nominal$data$label) && !is.ordered(nominal$data$label), "a nominal outcome is retained as a factor")
expect(same(check(nominal), check(nominal, data = d)), "binary with nominal checks the same way from retained and explicit data")

# --- Retention off: the check needs data, and then behaves as with retention on
d <- panel(1)
d$y <- factor(ifelse(d$z > 0, "yes", "no"), levels = c("no", "yes"))
kept <- fit_quiet(d, "y", design, family = gt_family("binary", "logit", levels = c("no", "yes")))
dropped <- fit_quiet(d, "y", design, family = gt_family("binary", "logit", levels = c("no", "yes")),
  control = gt_control(retain = list(data = FALSE)))
expect(is.null(dropped$data), "retention off stores no data")
expect(grepl("retain = list(data = FALSE)", outcome(check(dropped)), fixed = TRUE),
       "without retained data the check asks for data =")
expect(same(check(dropped, data = d), check(kept)),
       "with retention off, explicit labeled data gives the same comparison as the retained-data call on the same fit")
cat("PASS: gt_laplace_check() reads retained encoded responses as the encoding they are; new data is still validated.\n")
