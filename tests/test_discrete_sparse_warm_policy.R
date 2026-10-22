# Run from the project directory with Rscript tests/test_discrete_sparse_warm_policy.R.
#
# Warm starts within an optimizer attempt (.gt_d_sparse_evaluator). The
# conditional objective is strictly concave in the random effects, so a start
# changes the path to the mode and never the mode; what this checks is the
# policy around that fact: an attempt's first solve is cold, later solves start
# from the attempt's centre mode, the two finite-difference probes of a
# coordinate share that centre and neither replaces it, a reset makes the next
# solve cold again, an evaluation made without the request is cold, a warm
# solve that stops short is replaced by the cold solve, and a fit through the
# public interface counts its warm starts while its final evaluation is cold.
source(file.path("validation-studies", "discrete-sparse-equivalence", "cases.R"))
source("load_functions.R")
suppressMessages(library(Matrix))

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)

row <- EQ_CALIBRATION[EQ_CALIBRATION$case == "K02", ]
map <- .eq_parameter_map(row, EQ_CALIBRATION_GEOMETRY[[row$geometry]])
prep <- map$prep; groups <- map$groups; setup <- map$setup; control <- map$control
theta <- map$start
warm <- control
warm$inner_start <- "warm"

# --- an attempt's first solve is cold and sets the centre -----------------------
evaluator <- .gt_d_sparse_evaluator()
first <- evaluator(theta, prep, groups, setup, warm, details = TRUE)
expect(isTRUE(first$valid) && is.null(first$inner_warm_started),
       "the first solve of an attempt is cold even when warm starts are requested")

# --- probes of one coordinate are warm from the same centre ---------------------
j <- length(prep$start) + 1L
plus <- theta; plus[[j]] <- plus[[j]] + 1e-3
minus <- theta; minus[[j]] <- minus[[j]] - 1e-3
positive <- evaluator(plus, prep, groups, setup, warm, details = TRUE)
negative <- evaluator(minus, prep, groups, setup, warm, details = TRUE)
expect(isTRUE(positive$inner_warm_started) && isTRUE(negative$inner_warm_started),
       "finite-difference probes start from the centre mode")
repeated <- evaluator(minus, prep, groups, setup, warm, details = TRUE)
expect(identical(repeated$mode, negative$mode) && identical(repeated$nll, negative$nll),
       "a probe does not replace the centre: repeating it reproduces it exactly")

# --- the mode is the same point whatever the start ------------------------------
reference <- .gt_d_sparse_evaluator()
cold_plus <- reference(plus, prep, groups, setup, control, details = TRUE)
expect(abs(positive$nll - cold_plus$nll) <= 1e-8,
       paste0("warm and cold objectives agree at the coarse tolerance (",
              format(abs(positive$nll - cold_plus$nll), digits = 3), ")"))
expect(max(abs(positive$mode - cold_plus$mode)) <= 1e-6,
       "warm and cold modes agree within the inner tolerance")

# --- a move of more than one coordinate becomes the new centre ------------------
moved <- theta; moved[1:2] <- moved[1:2] + c(0.05, -0.05)
new_centre <- evaluator(moved, prep, groups, setup, warm, details = TRUE)
expect(isTRUE(new_centre$inner_warm_started), "a new centre is reached by a warm solve from the old one")
probe_from_new <- evaluator(plus, prep, groups, setup, warm, details = TRUE)
expect(isTRUE(probe_from_new$inner_warm_started), "later probes are warm from the new centre")

# --- no request, no warm start; a reset makes the next solve cold --------------
cold_again <- evaluator(theta, prep, groups, setup, control, details = TRUE)
expect(is.null(cold_again$inner_warm_started), "an evaluation without inner_start = 'warm' is cold")
expect(is.function(attr(evaluator, "reset")), "the evaluator exposes a reset for the fit")
attr(evaluator, "reset")()
after_reset <- evaluator(plus, prep, groups, setup, warm, details = TRUE)
expect(is.null(after_reset$inner_warm_started), "after a reset the next solve is cold")
expect(is.null(attr(.gt_d_laplace, "reset")), "the dense evaluator has no warm-start state to reset")

# --- a warm solve that stops short is replaced by the cold solve -----------------
fallback <- .gt_d_sparse_evaluator()
invisible(fallback(theta, prep, groups, setup, warm, details = TRUE))
starved <- warm
starved$inner_maxit <- 1L
short <- fallback(moved, prep, groups, setup, starved, details = TRUE)
expect(!isTRUE(short$inner_warm_started) && is.list(short$inner_warm_attempt) &&
         isFALSE(short$inner_warm_attempt$inner_converged),
       "a warm solve that stops short is replaced by the cold solve, and the warm attempt travels with it")

# --- through the public interface: warm starts are counted, the final solve is cold
panel <- map$panel
panel$y <- factor(as.character(panel$y), levels = c("0", "1"))
fit <- suppressWarnings(gt_fit(panel, "y",
  design = gt_design("item", "rater", random = c("item", "rater"), replicates = 2L),
  family = gt_family("binary", "logit", levels = c("0", "1")), covariance = "diagonal",
  control = gt_control(discrete = list(engine = "sparse"))))
log <- fit$diagnostics$evaluations
expect(isTRUE(fit$numerically_accepted), "the sparse fit is numerically accepted")
expect(is.numeric(log$warm_started) && log$warm_started > 0L && log$warm_started < log$count,
       "the fit counts its warm-started evaluations, and not every evaluation is one")
expect(identical(log$cold_fallbacks, 0L) && identical(log$warm_rescued, 0L),
       "no cold fallback and no rescue were needed on this panel")
expect(!isTRUE(fit$diagnostics$inner_warm_started), "the final evaluation of the fit is a cold solve")
dense <- suppressWarnings(gt_fit(panel, "y",
  design = gt_design("item", "rater", random = c("item", "rater"), replicates = 2L),
  family = gt_family("binary", "logit", levels = c("0", "1")), covariance = "diagonal",
  control = gt_control(discrete = list(engine = "dense"))))
expect(abs(dense$logLik - fit$logLik) / max(1, abs(dense$logLik)) <= 1e-6,
       "the warm-started sparse fit reaches the dense objective within the fitted tolerance")
cat("PASS: warm starts within an attempt: cold first solve, shared probe centre, reset, no-request and",
    "short-solve fallbacks, counted in the fit with a cold final evaluation.\n")
