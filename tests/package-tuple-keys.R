# Column-name and label invariance checked against the installed package.
library(Gtheory4LLM)
internal <- function(name) getFromNamespace(name, "Gtheory4LLM")
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"),
            grepl(pattern, conditionMessage(error), fixed = TRUE))
}
same <- function(a, b)
  stopifnot(isTRUE(all.equal(a, b, tolerance = 1e-12)))

# These labels contain a pair of tuples that would collide if pasted directly.
# A deterministic row permutation also prevents reliance on factorial row order.
panel <- expand.grid(item = c("a:b", "a", "other"),
                     rater = c("c", "b:c"), occasion = c("first", "second"),
                     KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
panel <- panel[c(8, 3, 1, 12, 7, 5, 10, 4, 9, 2, 11, 6), ]
rownames(panel) <- NULL
ordinary <- names(panel)
name_sets <- list(ordinary = ordinary)
for (role in 1:2) for (name in c("sep", "collapse", "recycle0")) {
  renamed <- ordinary
  renamed[[role]] <- name
  name_sets[[paste(role, name, sep = "/")]] <- renamed
}
name_sets$all_paste_arguments <- c("sep", "collapse", "recycle0")

fixture <- function(variables, replicates = 1L, discrete = FALSE) {
  data <- panel[rep(seq_len(nrow(panel)), replicates), ]
  rownames(data) <- NULL
  names(data) <- variables
  if (discrete) {
    data$y <- rep(c(0L, 1L), length.out = nrow(data))
    data$z <- ordered(rep(c("low", "medium", "high"), length.out = nrow(data)),
                      levels = c("low", "medium", "high"))
    families <- list(y = gt_family("binary", "logit"), z = gt_family("ordinal", "probit"))
  } else {
    data$y <- seq_len(nrow(data))
    data$z <- cos(seq_len(nrow(data)))
    families <- list(y = gt_family(), z = gt_family())
  }
  interaction <- paste(variables[1:2], collapse = ":")
  design <- gt_design(variables[[1]], variables[-1],
                      random = c(variables, interaction), replicates = replicates)
  design <- internal(".gt_resolve_design")(data, design,
                                           if (discrete) "discrete" else "gaussian")
  covariance <- function(a, b, off)
    matrix(c(a, off, off, b), 2L, dimnames = list(c("y", "z"), c("y", "z")))
  components <- setNames(list(covariance(4, 3, .4), covariance(2, 1, .2),
    covariance(.5, .8, -.1), covariance(1, .6, .15), covariance(.75, 1.2, .1)),
    c(variables, interaction, "Residual"))
  structure(list(data = data, design = design, outcomes = c("y", "z"),
    families = families, covariance_components = components,
    converged = TRUE, numerically_accepted = TRUE,
    engine = if (discrete) "dense_joint_discrete_laplace" else "test_fixture",
    estimator = if (discrete) "ML_Laplace" else "REML",
    diagnostics = list(test_fixture = TRUE)), class = "gt_fit")
}
score <- gt_score(c(y = 1.2, z = -.4))
grid <- data.frame(rater = c(1, 2, 4), occasion = c(2, 3, 1))

for (replicates in c(1L, 2L)) for (discrete in c(FALSE, TRUE)) {
  reference <- fixture(ordinary, replicates, discrete)
  scale <- if (discrete) "latent" else "observed"
  reference_reliability <- gt_reliability(reference, scale = scale, score = score)
  reference_study <- gt_dstudy(reference, grid, scale = scale, score = score)
  for (variables in name_sets) {
    fit <- fixture(variables, replicates, discrete)
    same(fit$design$observed_replication, replicates)
    same(internal(".gt_tuple_key")(fit$data, variables),
         internal(".gt_tuple_key")(reference$data, ordinary))
    stopifnot(internal(".gt_d_group")(fit$data, variables)$nlevels == 12L,
              internal(".gt_d_group")(fit$data, variables[1:2])$nlevels == 6L)
    for (positions in c(as.list(seq_along(variables)), list(1:2, 1:3)))
      same(internal(".gt_d_group")(fit$data, variables[positions]),
           internal(".gt_d_group")(reference$data, ordinary[positions]))

    reliability <- gt_reliability(fit, scale = scale, score = score)
    for (part in c("per_trait", "composite", "universe_covariance",
                   "relative_error_covariance", "absolute_error_covariance"))
      same(reliability[[part]], reference_reliability[[part]])
    renamed_grid <- grid
    names(renamed_grid) <- variables[-1]
    study <- gt_dstudy(fit, renamed_grid, scale = scale, score = score)
    same(study$results, reference_study$results)
    same(study$measurements_per_object, reference_study$measurements_per_object)
    same(study$extrapolated, reference_study$extrapolated)
    same(unname(study$allocations), unname(reference_study$allocations))

    if (!discrete && replicates == 1L) {
      prepared <- internal(".gt_gaussian_engine")(variables)$prepare(
        fit$data, fit$outcomes, setNames(variables, variables))
      original <- internal(".gt_gaussian_engine")(ordinary)$prepare(
        reference$data, reference$outcomes, setNames(ordinary, ordinary))
      same(prepared$strata, original$strata)
      same(prepared$means, original$means)
      same(unname(prepared$counts), unname(original$counts))
    }
  }
}
cat("PASS: object/facet paste argument names preserve tuple groups, replication, Gaussian preparation, and Gaussian/joint-discrete G/Phi and D studies.\n")

# Name safety must preserve structural errors and the different missing-cell
# policies of discrete fitting, Gaussian preparation, and analytic reliability.
for (variables in name_sets) {
  fit <- fixture(variables)
  duplicated <- fit$data
  duplicated[nrow(duplicated), ] <- duplicated[1L, ]
  for (family in c("gaussian", "discrete"))
    expect_error(internal(".gt_resolve_design")(duplicated, fit$design, family),
                 "Observed within-cell replication")
  invalid <- fit
  invalid$data <- duplicated
  expect_error(gt_reliability(invalid), "equal within-cell replication")
  expect_error(gt_dstudy(invalid, setNames(grid, variables[-1])),
               "equal within-cell replication")

  incomplete <- fit$data[-nrow(fit$data), ]
  resolved <- internal(".gt_resolve_design")(incomplete, fit$design, "discrete")
  same(resolved$observed_replication, 1L)
  invalid$data <- incomplete
  expect_error(gt_reliability(invalid), "complete balanced coded panel")
  expect_error(gt_dstudy(invalid, setNames(grid, variables[-1])),
               "complete balanced coded panel")
  expect_error(internal(".gt_gaussian_engine")(variables)$prepare(
    incomplete, fit$outcomes, setNames(variables, variables)), "Missing cells are not dropped")

  missing <- fit$data
  missing[1L, variables[[1]]] <- NA
  expect_error(internal(".gt_d_group")(missing, variables), "Missing grouping values")
  expect_error(gt_fit(missing, fit$outcomes, fit$design), "nonmissing levels")
}
cat("PASS: collision-prone labels remain distinct; unequal replication, missing groups, and incomplete analytic panels retain their guards.\n")
