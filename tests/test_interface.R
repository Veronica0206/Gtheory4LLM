# Run from the project root: Rscript tests/test_interface.R
# Interface tests exercise real encoding and Gaussian dispatch, and verify
# reliability against dense covariance aggregation independently of its formula.
for (file in c("design.R", "family.R", "gaussian_retry.R", "gaussian_engine.R", "gaussian.R",
                "discrete_response.R", "discrete.R", "fit.R", "reliability.R"))
  source(file.path("R", file))
near <- function(a, b, tolerance = 1e-8, label = "comparison") {
  if (!isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)))
    stop(label, " failed: maximum absolute difference ", max(abs(a - b)))
}
expect_error <- function(expr, pattern) {
  e <- tryCatch({ force(expr); NULL }, error = identity)
  if (is.null(e) || !grepl(pattern, conditionMessage(e), fixed = TRUE))
    stop("Expected error containing: ", pattern)
}

# Category labels, their ordering, and their reference are semantic inputs.
labels <- data.frame(flag = c("present", "absent", "present"),
                     rating = c("poor", "fair", "good"),
                     diagnosis = c("beta", "alpha", "gamma"), stringsAsFactors = FALSE)
families <- list(flag = gt_family("binary", levels = c("absent", "present")),
                 rating = gt_family("ordinal", levels = c("poor", "fair", "good")),
                 diagnosis = gt_family("categorical", levels = c("alpha", "beta", "gamma"), reference = "beta"))
resolved <- .gt_resolve_families(labels, names(labels), families[3:1])
stopifnot(identical(resolved$data$flag, c(1L, 0L, 1L)),
          is.ordered(resolved$data$rating), !is.ordered(resolved$data$diagnosis),
          identical(levels(resolved$data$rating), c("poor", "fair", "good")),
          identical(resolved$families$diagnosis$reference, "beta"),
          identical(names(resolved$families), names(labels)))
ordered_input <- data.frame(y = ordered(c("high", "low", "mid"), levels = c("low", "mid", "high")))
stopifnot(identical(.gt_resolve_families(ordered_input, "y", gt_family("ordinal"))$families$y$levels,
                    c("low", "mid", "high")))
logical_input <- .gt_resolve_families(data.frame(y = c(TRUE, FALSE)), "y", gt_family("binary"))
stopifnot(identical(logical_input$data$y, c(1L, 0L)))
expect_error(gt_family("ordinal", levels = c("a", "b")), "Use binary")
expect_error(gt_family("categorical", levels = c("a", "b")), "Use binary")
expect_error(gt_family("ordinal", reference = "low"), "reference applies only")
expect_error(gt_family("gaussian", link = "probit"), "Unsupported link")
expect_error(.gt_resolve_families(data.frame(y = 1:2), "y", gt_family("binary")), "0/1")
expect_error(.gt_resolve_families(data.frame(y = factor(1:3)), "y", gt_family("gaussian")), "never silently converted")
expect_error(.gt_resolve_families(data.frame(y = 1:3), "y", gt_family("ordinal")), "explicit ordered levels")
expect_error(.gt_resolve_families(data.frame(y = c("a", "b")), "y",
                                gt_family("categorical", levels = c("a", "b", "c"))), "absent categories")
expect_error(.gt_resolve_families(labels, names(labels), families[-1]), "matching outcomes exactly")
cat("PASS: binary, ordinal, and categorical encoding preserves their distinct semantics and rejects ambiguity.\n")

# Arbitrary facet names include a space; no formula parsing is used to build
# grouping kernels or allocate D-study counts.
design <- gt_design("person", c("assessment team", "wave.id"))
outcomes <- c("trait.A", "trait.B")
data <- expand.grid(person = 1:3, team = 1:3, wave = 1:2, KEEP.OUT.ATTRS = FALSE)
names(data)[2:3] <- design$facets
data$trait.A <- seq_len(nrow(data)); data$trait.B <- -seq_len(nrow(data))
design <- .gt_resolve_design(data, design, "gaussian")
mat <- function(a, b, off) matrix(c(a, off, off, b), 2, dimnames = list(outcomes, outcomes))
components <- list(person = mat(2, 1.5, .4), "assessment team" = mat(.8, .6, -.15),
  "wave.id" = mat(.3, .5, .1), "person:assessment team" = mat(.5, .7, .12),
  "person:wave.id" = mat(.4, .2, -.06), "assessment team:wave.id" = mat(.2, .3, .04),
  Residual = mat(1, .9, .25))
fit <- structure(list(data = data, outcomes = outcomes, design = design,
  covariance_components = components, families = setNames(rep(list(gt_family()), 2), outcomes),
  estimator = "REML", diagnostics = list(test_fixture = TRUE)), class = "gt_fit")
score <- gt_score(c(trait.B = -.4, trait.A = 1.2))

# Average score covariance from explicit observation-by-observation kernels.
# Half the variance of the difference between two objects removes their shared
# instrumentation effects, independently recovering relative error variance.
dense_errors <- function(counts, components, replicates = 1L) {
  grid <- expand.grid(person = 1:2, team = seq_len(counts[["assessment team"]]),
                      wave = seq_len(counts[["wave.id"]]), replicate = seq_len(replicates),
                      KEEP.OUT.ATTRS = FALSE)
  names(grid)[2:3] <- c("assessment team", "wave.id")
  N <- nrow(grid); D <- 2L; V <- matrix(0, N * D, N * D)
  for (source in setdiff(names(components), "person")) {
    if (source == "Residual") kernel <- diag(N) else {
      vars <- strsplit(source, ":", fixed = TRUE)[[1L]]
      kernel <- Reduce(`*`, lapply(grid[vars], function(x) outer(x, x, `==`)))
    }
    V <- V + kronecker(kernel, components[[source]])
  }
  one <- as.numeric(grid$person == 1L); one <- one / sum(one)
  two <- as.numeric(grid$person == 2L); two <- two / sum(two)
  average <- kronecker(matrix(one, 1L), diag(D))
  difference <- kronecker(matrix(one - two, 1L), diag(D))
  list(absolute = average %*% V %*% t(average),
       relative = difference %*% V %*% t(difference) / 2)
}
counts <- c("assessment team" = 3, "wave.id" = 2)
check_reliability <- function(fit, counts, score, scale = NULL, dense_components = components) {
  value <- gt_reliability(fit, scale = scale, score = score, design = counts)
  expected <- dense_errors(counts, dense_components, fit$design$replicates)
  near(value$relative_error_covariance, expected$relative, label = "Dense relative covariance")
  near(value$absolute_error_covariance, expected$absolute, label = "Dense absolute covariance")
  U <- dense_components$person
  near(value$per_trait$Erho2, diag(U) / diag(U + expected$relative))
  near(value$per_trait$Phi, diag(U) / diag(U + expected$absolute))
  w <- score$weights[outcomes]
  q <- function(M) drop(crossprod(w, M %*% w))
  near(value$composite$Erho2, q(U) / q(U + expected$relative))
  near(value$composite$Phi, q(U) / q(U + expected$absolute))
  value
}
value <- check_reliability(fit, counts, score)
stopifnot(identical(value$scale, "observed"), !value$extrapolated,
          identical(value$score$weights, score$weights))
# Multiplying all weights preserves reliability; changing their ratio need not.
rescaled <- gt_reliability(fit, score = gt_score(7 * score$weights))
near(unlist(value$composite), unlist(rescaled$composite))
extracted <- gt_components(fit)
near(extracted$person, components$person)
near(gt_components(fit, correlation = TRUE)$person[1, 2], .4 / sqrt(2 * 1.5))
zero <- fit; zero$covariance_components$person[1, ] <- 0; zero$covariance_components$person[, 1] <- 0
stopifnot(is.na(gt_components(zero, correlation = TRUE)$person[1, 1]),
          is.na(gt_components(zero, correlation = TRUE)$person[1, 2]))
cat("PASS: Gaussian per-trait and weighted composite coefficients match independent dense score aggregation.\n")

allocations <- data.frame(team = c(1, 3, 5), wave = c(2, 1, 4), check.names = FALSE)
names(allocations) <- names(counts)
study <- gt_dstudy(fit, allocations, score = score)
stopifnot(identical(study$allocations, allocations), nrow(study$results) == 9L,
          identical(unname(study$measurements_per_object), c(2, 3, 20)),
          identical(unname(study$extrapolated), c(FALSE, FALSE, TRUE)))
for (i in seq_len(nrow(allocations))) {
  candidate <- check_reliability(fit, unlist(allocations[i, ], use.names = TRUE), score)
  rows <- study$results[study$results$design_id == i, ]
  near(rows$Erho2, c(candidate$per_trait$Erho2, candidate$composite$Erho2))
  near(rows$Phi, c(candidate$per_trait$Phi, candidate$composite$Phi))
}
partial <- gt_dstudy(fit, data.frame(wave.id = c(1, 3)), score = score)
stopifnot(identical(partial$allocations[["assessment team"]], c(3L, 3L)))
expect_error(gt_reliability(fit, design = c(person = 2)), "instrumentation facets")
expect_error(gt_reliability(fit, score = gt_score(c(trait.A = 1))), "every outcome")
expect_error(gt_dstudy(fit, data.frame(wave.id = 1.5)), "positive finite integers")
expect_error(gt_reliability(fit, scale = "latent"), "observed Gaussian")
cat("PASS: D-study allocations, arbitrary facet names, partial count overrides, and extrapolation flags match dense calculations.\n")

# Identified latent residual variances differ by link and are never interpreted
# as the reliability of observed binary/ordinal scores.
discrete <- fit
discrete$families <- list(trait.A = gt_family("binary", "probit", c("no", "yes")),
                          trait.B = gt_family("ordinal", "logit", c("low", "mid", "high")))
discrete$covariance_components$Residual <- NULL
latent <- components; latent$Residual <- diag(c(1, pi^2 / 3))
invisible(check_reliability(discrete, counts, score, scale = "latent", dense_components = latent))
expect_error(gt_reliability(discrete), "explicitly request scale='latent'")
expect_error(gt_reliability(discrete, scale = "observed"), "identified latent")
nominal <- discrete; nominal$families$trait.B <- gt_family("categorical", levels = c("x", "y", "z"))
expect_error(gt_reliability(nominal, scale = "latent"), "no default scalar")
bad_panel <- fit; bad_panel$data <- rbind(data[-1, ], data[2, ])
expect_error(gt_reliability(bad_panel), "equal within-cell replication")
cat("PASS: binary/ordinal latent scale uses link-specific residuals; categorical scalar and incomplete-panel coefficients are rejected.\n")

# Only two small real fits are needed to exercise exported Gaussian dispatch.
set.seed(5481L)
actual <- expand.grid(person = 1:8, team = 1:3, wave = 1:2, KEEP.OUT.ATTRS = FALSE)
names(actual)[2:3] <- c("assessment team", "wave.id")
actual$trait.A <- rnorm(nrow(actual)) + rnorm(8)[actual$person] +
  2 * actual[["assessment team"]] + actual$wave.id
actual$trait.B <- .5 * actual$trait.A + rnorm(nrow(actual))
small_design <- gt_design("person", c("assessment team", "wave.id"),
                          random = c("person", "assessment team", "wave.id"))
control <- gt_control(gaussian = list(check_hessian = FALSE, extra_tries = 2L,
                                     tolerance = 1e-10, retry_seed = 425L))
one <- gt_fit(actual, "trait.A", small_design, control = control)
joint <- gt_fit(actual, outcomes, small_design, covariance = "diagonal", residual = "diagonal", control = control)
stopifnot(inherits(one, "gt_fit"), inherits(joint, "gt_fit"), one$converged, joint$converged,
          identical(one$families$trait.A$family, "gaussian"),
          identical(joint$outcomes, outcomes), identical(joint$N, nrow(actual)),
          identical(joint$D, 2L), identical(joint$estimator, "REML"),
          identical(names(joint$means), outcomes),
          identical(unique(joint$estimates$trait), outcomes),
          all(vapply(joint$covariance_components, function(M)
            identical(dimnames(M), list(outcomes, outcomes)), logical(1))),
          identical(names(joint$covariance_components), c(small_design$terms, "Residual")),
          identical(joint$design$validation_scope, one$design$validation_scope))
near(one$minus2loglik, one$backend_fit$output$fit)
stopifnot(all(is.finite(gt_reliability(joint, score = score)$per_trait$Erho2)),
          all(dim(gt_components(joint)$person) == c(2L, 2L)),
          !is.null(summary(joint)$diagnostics),
          isTRUE(gt_diagnostics(joint)$diagnostics$independent_likelihood_matches))
actual$flag <- rep(c(0, 1), length.out = nrow(actual))
expect_error(gt_fit(actual, c("trait.A", "flag"), small_design,
                    family = list(trait.A = gt_family(), flag = gt_family("binary"))), "Joint Gaussian-discrete")
expect_error(gt_fit(actual, "flag", small_design, family = gt_family("binary"), estimator = "REML"), "ML_Laplace")
expect_error(gt_fit(actual, "flag", small_design, family = gt_family("binary"), residual = "diagonal"), "Gaussian residual")
cat("PASS: exported Gaussian univariate/joint dispatch, extraction, summaries, reliability, and incompatible-estimator guards work.\n")
# One-facet allocations must retain the facet name when a data-frame row
# contains only one column. This also checks single-row and multirow grids.
single_design <- gt_design("item", "judge", random = ~ item + judge)
single_data <- expand.grid(item = 1:3, judge = 1:2, KEEP.OUT.ATTRS = FALSE)
single_data$y <- seq_len(nrow(single_data))
single <- structure(list(data = single_data, outcomes = "y", design = single_design,
  covariance_components = list(item = matrix(2), judge = matrix(.6), Residual = matrix(1.2)),
  families = list(y = gt_family()), estimator = "REML", converged = TRUE,
  diagnostics = list(test_fixture = TRUE)), class = "gt_fit")
one_facet_study <- gt_dstudy(single, data.frame(judge = c(1, 3)))
near(one_facet_study$results$Erho2, 2 / (2 + 1.2 / c(1, 3)))
near(one_facet_study$results$Phi, 2 / (2 + 1.8 / c(1, 3)))
stopifnot(identical(names(one_facet_study$allocations), "judge"),
          identical(unname(one_facet_study$measurements_per_object), c(1, 3)))
near(gt_dstudy(single, data.frame(judge = 3))$results$Erho2,
     one_facet_study$results$Erho2[2L])
cat("PASS: one-facet D studies preserve allocation names and match analytic coefficients.\n")

# An intentionally interrupted real optimizer must remain inspectable while
# preventing its provisional covariance estimates from being used as G/Phi.
failed_data <- expand.grid(item = 1:6, rater = 1:3)
failed_data$y <- c(0, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 0, 0, 1, 1, 1)
failed_warnings <- character()
failed <- withCallingHandlers(gt_fit(failed_data, "y", gt_design("item", "rater", random = ~ item + rater),
  gt_family("binary"), control = gt_control(discrete = list(maxit = 1))),
  warning = function(w) {
    failed_warnings <<- c(failed_warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  })
stopifnot(isFALSE(failed$converged), failed$diagnostics$optimizer_code != 0,
          any(grepl("did not converge", failed_warnings, fixed = TRUE)),
          is.list(gt_components(failed)), is.list(gt_diagnostics(failed)))
expect_error(gt_reliability(failed, scale = "latent"), "numerically converged fit")
expect_error(gt_dstudy(failed, data.frame(rater = 2), scale = "latent"), "numerically converged fit")
failed_gaussian <- joint; failed_gaussian$converged <- FALSE
expect_error(gt_reliability(failed_gaussian), "numerically converged fit")
cat("PASS: failed real discrete optimization warns and cannot supply reliability or D-study estimates.\n")
# A requested observation-level random source has family-specific meaning.
full <- gt_design("person", c("assessment team", "wave.id"))
stopifnot(length(full$terms) == 7L, length(full$aliased_terms) == 0L)
gaussian_full <- .gt_resolve_design(actual, full, "gaussian")
stopifnot(length(gaussian_full$terms) == 6L,
  identical(gaussian_full$aliased_terms, "person:assessment team:wave.id"))
expect_error(gt_fit(actual, "flag", full, gt_family("binary")), "Requested observation-level source")
expect_error(.gt_resolve_design(rbind(actual, actual[1L, ]), full, "gaussian"), "Observed within-cell replication")
expect_error(.gt_resolve_design(actual, gt_design("person", c("assessment team", "wave.id"), replicates=2L), "discrete"), "Observed within-cell replication")
replicated <- .gt_resolve_design(rbind(actual, actual),
  gt_design("person", c("assessment team", "wave.id"), replicates=2L), "discrete")
stopifnot(length(replicated$terms) == 7L, replicated$replication_validated)
# Reusing a Gaussian-resolved design with a discrete outcome must reconstruct
# its requested source list rather than silently inherit the dropped term.
expect_error(.gt_resolve_design(actual, gaussian_full, "discrete"), "Requested observation-level source")
cat("PASS: family-specific alias resolution preserves requests and validates actual replication.\n")

near_boundary <- fit
near_boundary$covariance_components$person <- matrix(c(1e-12,9e-7,9e-7,1), 2,
  dimnames=list(outcomes,outcomes))
near_boundary$prepared <- list(observed_variances=c(1,1))
public <- gt_components(near_boundary, correlation=TRUE)$person
internal <- .gt_covariance_correlation(near_boundary$covariance_components$person, scale=c(1,1))
stopifnot(identical(public, internal), is.na(public[1,2]), public[2,2] == 1)
near(gt_components(near_boundary, correlation=TRUE, tolerance=0)$person[1,2], .9)
expect_error(gt_components(fit, correlation=TRUE, tolerance=-1), "tolerance")
cat("PASS: public and internal correlations share the near-zero variance policy.\n")
# Mixed-model fixed facets, checked against the published formulas on a fixture
# with known source covariances rather than on an estimated fit.
mixed_design <- gt_design("item", c("rater", "occasion"))
mixed_data <- expand.grid(item = 1:5, rater = 1:4, occasion = 1:2, KEEP.OUT.ATTRS = FALSE)
mixed_data$y <- seq_len(nrow(mixed_data))
sources <- list(item = 1.6, rater = .3, occasion = .2, "item:rater" = .5,
                "item:occasion" = .25, "rater:occasion" = .15, Residual = .6)
mixed_fit <- structure(list(data = mixed_data, outcomes = "y",
  design = .gt_resolve_design(mixed_data, mixed_design, "gaussian"),
  covariance_components = lapply(sources, matrix),
  families = list(y = gt_family()), estimator = "REML", converged = TRUE,
  diagnostics = list(test_fixture = TRUE)), class = "gt_fit")
stopifnot(length(mixed_fit$design$terms) == 6L)
v <- function(name) sources[[name]]
tau <- v("item")
delta <- v("item:rater") / 4 + v("item:occasion") / 2 + v("Residual") / 8
Delta <- delta + v("rater") / 4 + v("occasion") / 2 + v("rater:occasion") / 8
random_model <- gt_reliability(mixed_fit)
near(random_model$per_trait$Erho2, tau / (tau + delta), 1e-12, "random-model G")
near(random_model$per_trait$Phi, tau / (tau + Delta), 1e-12, "random-model Phi")
# Occasion fixed: its object interaction is averaged into the universe score and
# its main effect leaves the model entirely.
tau_fixed <- v("item") + v("item:occasion") / 2
delta_fixed <- v("item:rater") / 4 + v("Residual") / 8
Delta_fixed <- delta_fixed + v("rater") / 4 + v("rater:occasion") / 8
fixed_model <- gt_reliability(mixed_fit, fixed = "occasion")
near(fixed_model$per_trait$Erho2, tau_fixed / (tau_fixed + delta_fixed), 1e-12, "mixed-model G")
near(fixed_model$per_trait$Phi, tau_fixed / (tau_fixed + Delta_fixed), 1e-12, "mixed-model Phi")
stopifnot(identical(fixed_model$fixed_facets, "occasion"),
  identical(unname(fixed_model$source_roles[["occasion"]]), "dropped_fixed_instrumentation_constant"),
  identical(unname(fixed_model$source_roles[["item:occasion"]]), "universe_after_fixed_facet_averaging"),
  identical(unname(fixed_model$source_roles[["rater:occasion"]]), "absolute_error"))
expect_error(gt_reliability(mixed_fit, fixed = c("rater", "occasion")), "At least one facet must remain random")
expect_error(gt_reliability(mixed_fit, fixed = "wave"), "unknown facet")
expect_error(gt_reliability(mixed_fit, counts = c(occasion = 4), fixed = "occasion"), "cannot be changed")
expect_error(gt_dstudy(mixed_fit, data.frame(occasion = c(2, 4)), fixed = "occasion"),
             "cannot project over a fixed facet")
mixed_study <- gt_dstudy(mixed_fit, data.frame(rater = c(2, 4)), fixed = "occasion")
stopifnot(all(mixed_study$allocations$occasion == 2L))
near(mixed_study$results$Erho2[2L], fixed_model$per_trait$Erho2, 1e-12,
     "mixed D study at the observed allocation")
# A fixture with no parameter covariance matrix must report missing intervals
# and an explicit reason, never a fabricated standard error.
stopifnot(all(is.na(random_model$per_trait[c("Erho2_se", "Erho2_lower", "Phi_upper")])),
          isFALSE(random_model$uncertainty$available),
          nzchar(random_model$uncertainty$reason),
          all(is.na(mixed_study$results$Erho2_se)))
expect_error(gt_reliability(mixed_fit, level = 1), "strictly between 0 and 1")
cat("PASS: Brennan mixed-model fixed facets, their guards, and missing-interval reporting.\n")
cat("All standalone interface tests passed.\n")
