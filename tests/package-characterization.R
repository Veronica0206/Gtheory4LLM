# Characterization baseline for the released numerical implementation.
#
# This file does not re-derive any statistical result. It pins what the current
# engines actually produce for ten canonical cases so that a later refactor has
# to answer one question explicitly: did the statistical result change on
# purpose, or by accident? Independent formula checks live in the other tests;
# this one is a regression net around them.
#
# Optimizer-dependent quantities are compared with tolerances, never bit for
# bit. Acceptance decisions, retained sources, and boundary findings are
# compared exactly, because those are decisions rather than numbers.
#
# Regenerate the stored baseline deliberately, never to make a failure go away:
#   GTHEORY_CHARACTERIZATION_CAPTURE=1 Rscript --vanilla tests/package-characterization.R
# Record in NEWS.md why a statistical result moved before updating this file.
#
# When this fails, read what moved before deciding what it means. A different
# platform or BLAS shows up as a small numeric difference with every decision
# unchanged; the answer there is to widen the specific tolerance and say why,
# not to recapture the baseline, because recapturing would also absorb a real
# change silently. A changed acceptance decision, a changed set of retained
# sources, or a changed boundary finding is never a platform difference.
#
# The stored values were captured on R 4.5.3, aarch64-apple-darwin20, with
# OpenMx 2.22.11.
library(Gtheory4LLM)

suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rejection"))
seeded <- function(seed) {
  suppressWarnings(RNGkind("Mersenne-Twister", "Inversion", "Rejection"))
  set.seed(seed)
}
index <- function(...) as.integer(interaction(..., drop = TRUE))

# --- canonical panels -------------------------------------------------------

data_crossed <- function() {
  seeded(20260913L)
  d <- expand.grid(occasion = factor(1:2), rater = factor(1:4), item = factor(1:24))
  d$score <- sqrt(1.5) * rnorm(24)[d$item] + sqrt(.30) * rnorm(4)[d$rater] +
    sqrt(.20) * rnorm(2)[d$occasion] +
    sqrt(.45) * rnorm(96)[index(d$item, d$rater)] +
    sqrt(.25) * rnorm(48)[index(d$item, d$occasion)] +
    sqrt(.10) * rnorm(8)[index(d$rater, d$occasion)] +
    rnorm(nrow(d), sd = sqrt(.60))
  d
}

data_multivariate <- function() {
  seeded(77L)
  d <- expand.grid(rater = factor(1:4), item = factor(1:20))
  item_effect <- matrix(rnorm(40), 20, 2) %*% chol(matrix(c(1.2, .6, .6, .9), 2, 2))
  rater_effect <- matrix(rnorm(8), 4, 2) %*% chol(matrix(c(.3, .1, .1, .2), 2, 2))
  noise <- matrix(rnorm(2 * nrow(d)), nrow(d), 2) %*% chol(matrix(c(.7, .2, .2, .5), 2, 2))
  d$y1 <- item_effect[d$item, 1] + rater_effect[d$rater, 1] + noise[, 1]
  d$y2 <- item_effect[d$item, 2] + rater_effect[d$rater, 2] + noise[, 2]
  d
}

# One instrumentation source generated with exactly zero variance.
data_boundary <- function() {
  seeded(505L)
  d <- expand.grid(rater = factor(1:4), item = factor(1:24))
  d$score <- sqrt(1.4) * rnorm(24)[d$item] + rnorm(nrow(d), sd = sqrt(.55))
  d
}

# p x (i:h) with within-parent item codes, so the coded panel stays complete.
data_nested <- function() {
  seeded(31415L)
  d <- expand.grid(item = factor(1:3), question = factor(1:2), person = factor(1:24))
  d$score <- sqrt(1.30) * rnorm(24)[d$person] + sqrt(.25) * rnorm(2)[d$question] +
    sqrt(.40) * rnorm(6)[index(d$item, d$question)] +
    sqrt(.35) * rnorm(48)[index(d$person, d$question)] +
    rnorm(nrow(d), sd = sqrt(.70))
  d
}

data_binary <- function() {
  seeded(9001L)
  d <- expand.grid(rater = factor(1:6), item = factor(1:18))
  eta <- .3 + rnorm(18, sd = .9)[d$item] + rnorm(6, sd = .5)[d$rater]
  d$label <- rbinom(nrow(d), 1L, plogis(eta))
  d
}

data_ordinal <- function() {
  seeded(4242L)
  d <- expand.grid(rater = factor(1:6), item = factor(1:18))
  eta <- rnorm(18, sd = .8)[d$item] + rnorm(6, sd = .4)[d$rater] + rnorm(nrow(d))
  d$grade <- ordered(c("low", "mid", "high")[1L + (eta > -.7) + (eta > .6)],
                     levels = c("low", "mid", "high"))
  d
}

data_categorical <- function() {
  seeded(606L)
  d <- expand.grid(rater = factor(1:6), item = factor(1:16))
  shift <- rnorm(16, sd = .8)[d$item]
  utility <- cbind(0, .2 + shift, -.3 + shift / 2) +
    matrix(-log(-log(runif(3 * nrow(d)))), nrow(d), 3)
  d$topic <- factor(c("a", "b", "c")[max.col(utility)], levels = c("a", "b", "c"))
  d
}

# --- canonical cases --------------------------------------------------------

cases <- list(
  gaussian_ml = function() {
    fit <- gt_fit(data_crossed(), "score", gt_design("item", c("rater", "occasion")),
                  estimator = "ML")
    list(fit = fit, reliability = gt_reliability(fit))
  },
  gaussian_reml = function() {
    fit <- gt_fit(data_crossed(), "score", gt_design("item", c("rater", "occasion")),
                  estimator = "REML")
    list(fit = fit, reliability = gt_reliability(fit),
         dstudy = gt_dstudy(fit, expand.grid(rater = c(2, 4, 8), occasion = c(1, 2))))
  },
  gaussian_multivariate = function() {
    fit <- gt_fit(data_multivariate(), c("y1", "y2"), gt_design("item", "rater"),
                  estimator = "REML", covariance = "unstructured")
    list(fit = fit, reliability = gt_reliability(fit, score = gt_score(c(y1 = .5, y2 = .5))))
  },
  gaussian_boundary = function() {
    fit <- gt_fit(data_boundary(), "score", gt_design("item", "rater"), estimator = "REML")
    list(fit = fit, reliability = gt_reliability(fit))
  },
  gaussian_fixed_facet = function() {
    fit <- gt_fit(data_crossed(), "score", gt_design("item", c("rater", "occasion")),
                  estimator = "REML")
    list(fit = fit, reliability = gt_reliability(fit, fixed = "occasion"))
  },
  gaussian_nested = function() {
    design <- gt_design("person", c("item", "question"), crossed = "question",
                        nested = list(item = "question"))
    fit <- gt_fit(data_nested(), "score", design, estimator = "REML")
    list(fit = fit, reliability = gt_reliability(fit),
         dstudy = gt_dstudy(fit, expand.grid(item = c(3, 6), question = c(2, 4))))
  },
  discrete_binary = function() {
    fit <- gt_fit(data_binary(), "label", gt_design("item", "rater", full_cell = FALSE),
                  gt_family("binary"), control = gt_control(discrete = list(maxit = 200L)))
    list(fit = fit, reliability = gt_reliability(fit, scale = "latent"))
  },
  discrete_ordinal = function() {
    fit <- gt_fit(data_ordinal(), "grade", gt_design("item", "rater", full_cell = FALSE),
                  gt_family("ordinal"), control = gt_control(discrete = list(maxit = 200L)))
    list(fit = fit, reliability = gt_reliability(fit, scale = "latent"))
  },
  discrete_categorical = function() {
    fit <- gt_fit(data_categorical(), "topic", gt_design("item", "rater", full_cell = FALSE),
                  gt_family("categorical"), control = gt_control(discrete = list(maxit = 200L)))
    list(fit = fit)
  },
  discrete_rejected = function() {
    # alternative_starts = 0 deliberately removes the restart-stability
    # evidence, so this fit must stay rejected and must refuse coefficients.
    fit <- gt_fit(data_binary(), "label", gt_design("item", "rater", full_cell = FALSE),
                  gt_family("binary"),
                  control = gt_control(discrete = list(maxit = 200L, alternative_starts = 0L)))
    rejection <- tryCatch({ gt_reliability(fit, scale = "latent"); NA_character_ },
                          error = conditionMessage)
    list(fit = fit, rejection = rejection)
  }
)

# Reduce one case to the quantities a refactor must preserve.
record_case <- function(case) {
  fit <- case$fit
  diagnostics <- gt_diagnostics(fit)
  components <- fit$covariance_components
  # Radix sorting keeps the stored order independent of the runner's locale.
  ordered <- function(x) sort(as.character(x), method = "radix")
  record <- list(
    minus2loglik = unname(fit$minus2loglik),
    variances = unlist(lapply(components[ordered(names(components))],
                              function(M) stats::setNames(diag(M), rownames(M)))),
    numerically_accepted = isTRUE(fit$numerically_accepted),
    optimizer_completed = isTRUE(fit$optimizer_completed),
    acceptance_failures = ordered(diagnostics$acceptance_failures),
    boundary_sources = ordered(diagnostics$boundary_sources),
    terms = ordered(fit$design$terms))
  if (!is.null(case$reliability)) {
    record$Erho2 <- stats::setNames(case$reliability$per_trait$Erho2,
                                    case$reliability$per_trait$outcome)
    record$Phi <- stats::setNames(case$reliability$per_trait$Phi,
                                  case$reliability$per_trait$outcome)
    if (!is.null(case$reliability$composite))
      record$composite <- c(Erho2 = case$reliability$composite$Erho2,
                            Phi = case$reliability$composite$Phi)
  }
  if (!is.null(case$dstudy)) record$dstudy_Erho2 <- case$dstudy$results$Erho2
  if (!is.null(case$rejection)) record$rejection <- case$rejection
  record
}

deparse_record <- function(name, record) {
  entries <- vapply(names(record), function(field) {
    value <- record[[field]]
    text <- paste(deparse(value, width.cutoff = 70L,
                          control = c("keepNA", "keepInteger", "niceNames",
                                      "showAttributes", "digits17")),
                  collapse = "\n      ")
    paste0("    ", field, " = ", text)
  }, character(1))
  paste0("  ", name, " = list(\n", paste(entries, collapse = ",\n"), "),")
}

# --- stored baseline --------------------------------------------------------
# Captured from the 0.1.0 candidate implementation. Optimizer-dependent
# quantities carry the tolerances below, not exact equality.
BASELINE <- list(
  gaussian_ml = list(
    minus2loglik = 643.18145016330539,
    variances = c(Residual.score = 0.68166192586207297, item.score = 2.0456614830256381, 
      "item:occasion.score" = 0.30814312674419464, "item:rater.score" = 0.39711230397653563, 
      occasion.score = 1.8856162230230968e-10, rater.score = 3.2367595000269231e-12, 
      "rater:occasion.score" = 0.18201804052415246),
    numerically_accepted = TRUE,
    optimizer_completed = TRUE,
    acceptance_failures = character(0),
    boundary_sources = c("occasion", "rater"),
    terms = c("item", "item:occasion", "item:rater", "occasion", "rater", "rater:occasion"
      ),
    Erho2 = c(score = 0.85800071237784969),
    Phi = c(score = 0.84989033207967946)),
  gaussian_reml = list(
    minus2loglik = 643.42906041187587,
    variances = c(Residual.score = 0.68130985789317888, item.score = 2.1298638499324012, 
      "item:occasion.score" = 0.3083877444679588, "item:rater.score" = 0.39736728776030894, 
      occasion.score = 3.6494449039760574e-10, rater.score = 8.5922195010064569e-13, 
      "rater:occasion.score" = 0.18881875031198214),
    numerically_accepted = TRUE,
    optimizer_completed = TRUE,
    acceptance_failures = character(0),
    boundary_sources = c("occasion", "rater"),
    terms = c("item", "item:occasion", "item:rater", "occasion", "rater", "rater:occasion"
      ),
    Erho2 = c(score = 0.86279491813859899),
    Phi = c(score = 0.85462371865292563),
    dstudy_Erho2 = c(0.71529785172411686, 0.78653104860743783, 0.82774678081258601, 0.80279253422727281, 
      0.86279491813859899, 0.89629021569376888)),
  gaussian_multivariate = list(
    minus2loglik = 445.81086931415712,
    variances = c(Residual.y1 = 0.92088205443812565, Residual.y2 = 0.44328378479798092, 
      item.y1 = 1.2988435242086966, item.y2 = 1.8772164697498366, rater.y1 = 0.071191975219206338, 
      rater.y2 = 0.13349471586336994),
    numerically_accepted = TRUE,
    optimizer_completed = TRUE,
    acceptance_failures = character(0),
    boundary_sources = "rater",
    terms = c("item", "rater"),
    Erho2 = c(y1 = 0.84943697064641865, y2 = 0.94425610639396562),
    Phi = c(y1 = 0.83966345909072315, y2 = 0.92866635315891111),
    composite = c(Erho2 = 0.92000266660125418, Phi = 0.90563468428294991)),
  gaussian_boundary = list(
    minus2loglik = 275.57507373614294,
    variances = c(Residual.score = 0.59166664434194338, item.score = 1.2264650367122647, 
      rater.score = 4.2101857382500907e-13),
    numerically_accepted = TRUE,
    optimizer_completed = TRUE,
    acceptance_failures = character(0),
    boundary_sources = "rater",
    terms = c("item", "rater"),
    Erho2 = c(score = 0.89237585066615699),
    Phi = c(score = 0.8923758506660886)),
  gaussian_fixed_facet = list(
    minus2loglik = 643.42906041187587,
    variances = c(Residual.score = 0.68130985789317888, item.score = 2.1298638499324012, 
      "item:occasion.score" = 0.3083877444679588, "item:rater.score" = 0.39736728776030894, 
      occasion.score = 3.6494449039760574e-10, rater.score = 8.5922195010064569e-13, 
      "rater:occasion.score" = 0.18881875031198214),
    numerically_accepted = TRUE,
    optimizer_completed = TRUE,
    acceptance_failures = character(0),
    boundary_sources = c("occasion", "rater"),
    terms = c("item", "item:occasion", "item:rater", "occasion", "rater", "rater:occasion"
      ),
    Erho2 = c(score = 0.9252579198820261),
    Phi = c(score = 0.91649515735038189)),
  gaussian_nested = list(
    minus2loglik = 488.17915375162079,
    variances = c(Residual.score = 0.87016758474617151, "item:question.score" = 0.29683752182424206, 
      person.score = 1.4791900600563059, "person:question.score" = 0.61288336609376926, 
      question.score = 0.052561015062579867),
    numerically_accepted = TRUE,
    optimizer_completed = TRUE,
    acceptance_failures = character(0),
    boundary_sources = character(0),
    terms = c("item:question", "person", "person:question", "question"),
    Erho2 = c(score = 0.76615784752613569),
    Phi = c(score = 0.7372310611315428),
    dstudy_Erho2 = c(0.76615784752613569, 0.79605708706849609, 0.86759838436784797, 0.88644964884474964
      )),
  discrete_binary = list(
    minus2loglik = 147.44722690283956,
    variances = c(item.label = 0.18283533501736599, rater.label = 0),
    numerically_accepted = TRUE,
    optimizer_completed = TRUE,
    acceptance_failures = character(0),
    boundary_sources = "rater",
    terms = c("item", "rater"),
    Erho2 = c(label = 0.52313100965486969),
    Phi = c(label = 0.52313100965486969)),
  discrete_ordinal = list(
    minus2loglik = 211.40113668689509,
    variances = c(item.grade = 1.016555237687347, rater.grade = 0.075184312311275689),
    numerically_accepted = TRUE,
    optimizer_completed = TRUE,
    acceptance_failures = character(0),
    boundary_sources = character(0),
    terms = c("item", "rater"),
    Erho2 = c(grade = 0.85914166560527017),
    Phi = c(grade = 0.85013841330763384)),
  discrete_categorical = list(
    minus2loglik = 200.98073819767097,
    variances = c("item.topic::b_vs_a" = 1.4145610733496314, "item.topic::c_vs_a" = 1.0764268371450318, 
      "rater.topic::b_vs_a" = 0.043628750345263048, "rater.topic::c_vs_a" = 0.20238347453536687
      ),
    numerically_accepted = TRUE,
    optimizer_completed = TRUE,
    acceptance_failures = character(0),
    boundary_sources = "item",
    terms = c("item", "rater")),
  discrete_rejected = list(
    minus2loglik = 147.44722690283956,
    variances = c(item.label = 0.18283533501736599, rater.label = 0),
    numerically_accepted = FALSE,
    optimizer_completed = TRUE,
    acceptance_failures = "restart_or_tolerance_stability_failed",
    boundary_sources = "rater",
    terms = c("item", "rater"),
    rejection = "Reliability and D studies require a numerically converged fit. Inspect gt_diagnostics(fit) and resolve the fitting failure first."))

# Optimizer-dependent comparisons. A variance resting on its zero boundary is
# reported as an arbitrary tiny number, so variances are compared relative to
# their own size but never to a scale below a millionth of the largest variance
# in the same fit: two optimizers agreeing that a source is zero must agree.
LIKELIHOOD_TOLERANCE <- 1e-4   # absolute, on -2 log L
VARIANCE_TOLERANCE <- 1e-4     # relative, on source variances
VARIANCE_FLOOR_FRACTION <- 1e-6
COEFFICIENT_TOLERANCE <- 1e-5  # absolute, on G/Phi

failures <- character()
note <- function(...) failures <<- c(failures, paste0(...))

compare_numeric <- function(case, field, observed, expected, tolerance, relative,
                            floor_fraction = 0) {
  if (length(observed) != length(expected)) {
    note(case, "/", field, ": length changed from ", length(expected), " to ", length(observed))
    return(invisible(NULL))
  }
  if (!identical(names(observed), names(expected))) {
    note(case, "/", field, ": names changed from [",
         paste(names(expected), collapse = ", "), "] to [",
         paste(names(observed), collapse = ", "), "]")
    return(invisible(NULL))
  }
  scale <- if (relative)
    pmax(abs(expected), floor_fraction * max(abs(expected)), 1e-12) else 1
  difference <- abs(unname(observed) - unname(expected)) / scale
  if (any(!is.finite(difference)) || max(difference) > tolerance)
    note(case, "/", field, ": ", if (relative) "relative" else "absolute",
         " difference ", format(max(difference), digits = 4),
         " exceeds ", tolerance)
  invisible(NULL)
}

compare_exact <- function(case, field, observed, expected) {
  if (!identical(observed, expected))
    note(case, "/", field, ": decision changed from [",
         paste(format(expected), collapse = ", "), "] to [",
         paste(format(observed), collapse = ", "), "]")
  invisible(NULL)
}

NUMERIC_FIELDS <- list(
  minus2loglik = list(tolerance = LIKELIHOOD_TOLERANCE, relative = FALSE),
  variances = list(tolerance = VARIANCE_TOLERANCE, relative = TRUE,
                   floor_fraction = VARIANCE_FLOOR_FRACTION),
  Erho2 = list(tolerance = COEFFICIENT_TOLERANCE, relative = FALSE),
  Phi = list(tolerance = COEFFICIENT_TOLERANCE, relative = FALSE),
  composite = list(tolerance = COEFFICIENT_TOLERANCE, relative = FALSE),
  dstudy_Erho2 = list(tolerance = COEFFICIENT_TOLERANCE, relative = FALSE))

capture <- nzchar(Sys.getenv("GTHEORY_CHARACTERIZATION_CAPTURE"))
captured <- character()
for (name in names(cases)) {
  record <- record_case(cases[[name]]())
  if (capture) {
    captured <- c(captured, deparse_record(name, record))
    next
  }
  expected <- BASELINE[[name]]
  if (is.null(expected)) {
    note(name, ": no stored baseline; regenerate deliberately")
    next
  }
  if (!setequal(names(record), names(expected))) {
    note(name, ": recorded fields changed from [", paste(sort(names(expected)), collapse = ", "),
         "] to [", paste(sort(names(record)), collapse = ", "), "]")
    next
  }
  for (field in names(record)) {
    numeric_field <- NUMERIC_FIELDS[[field]]
    if (is.null(numeric_field)) compare_exact(name, field, record[[field]], expected[[field]])
    else compare_numeric(name, field, record[[field]], expected[[field]],
                         numeric_field$tolerance, numeric_field$relative,
                         if (is.null(numeric_field$floor_fraction)) 0 else
                           numeric_field$floor_fraction)
  }
}

if (capture) {
  writeLines(sub(",$", "", paste(captured, collapse = "\n")))
} else if (length(failures)) {
  stop("Characterization baseline changed:\n", paste0("- ", failures, collapse = "\n"),
       "\nIf the change is intended, record why in NEWS.md and regenerate the baseline.")
} else {
  cat("PASS: characterization baseline reproduced for", length(cases), "canonical cases.\n")
}
