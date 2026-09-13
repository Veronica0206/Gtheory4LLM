# Run from the development folder: Rscript examples/standalone_usage.R
# Or source this file from any working directory. No package installation is
# needed; only the Gaussian engine requires the already installed OpenMx.
# The returned gt_example_results contains the designs, fits, and D studies.

gt_example_results <- local({
  # Resolve this file for both source() and Rscript without changing getwd().
  source_files <- lapply(sys.frames(), function(frame)
    get0("ofile", envir = frame, inherits = FALSE))
  source_files <- Filter(function(x) is.character(x) && length(x) == 1L, source_files)
  if (length(source_files)) {
    this_file <- tail(source_files, 1L)[[1L]]
  } else {
    file_arg <- commandArgs(trailingOnly = FALSE)
    file_arg <- file_arg[startsWith(file_arg, "--file=")]
    if (!length(file_arg)) stop("Run or source examples/standalone_usage.R.")
    this_file <- sub("^--file=", "", file_arg[[1L]])
  }
  if (!file.exists(this_file)) this_file <- gsub("~+~", " ", this_file, fixed=TRUE)
  project <- dirname(dirname(normalizePath(this_file, mustWork = TRUE)))
  source(file.path(project, "load_functions.R"), local = environment())

  run_examples <- function() {
    # Reproducible simulations without changing the caller's RNG state.
    had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
    saved_seed <- if (had_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
    saved_kind <- RNGkind()
    on.exit({
      do.call(RNGkind, as.list(saved_kind))
      if (had_seed) assign(".Random.seed", saved_seed, envir = .GlobalEnv) else
        if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
          rm(".Random.seed", envir = .GlobalEnv)
    }, add = TRUE)

    # Four instrumentation facets, with k=1,...,4 crossed roots. Remaining
    # facets are explicitly nested: the first child within all crossed roots,
    # then each further child within the preceding child and its ancestors.
    # Crossed roots have object interactions through the requested full order.
    # Nested children do not acquire object interactions unless item_nested is
    # requested explicitly. These are design specifications, not model fits.
    facets <- c("rater", "prompt", "temperature", "seed")
    four_facet_designs <- setNames(lapply(seq_along(facets), function(k) {
      crossed <- facets[seq_len(k)]
      children <- setdiff(facets, crossed)
      nested <- setNames(vector("list", length(children)), children)
      if (length(children)) for (j in seq_along(children))
        nested[[j]] <- if (j == 1L) crossed else children[[j - 1L]]
      gt_design(object = "item", facets = facets, crossed = crossed,
                nested = nested, item_interactions = "complete",
                instrument_interactions = "complete")
    }), paste0("k", seq_along(facets)))
    full_crossed <- gt_design("item", facets)
    stopifnot(identical(four_facet_designs$k4$terms, full_crossed$terms))
    # A fifth example lets a selected nested group interact with the object.
    selected_nested <- gt_design("item", facets, crossed = c("rater", "prompt"),
                                  nested = list(temperature = c("rater", "prompt"),
                                                seed = "temperature"),
                                  item_nested = "temperature")
    design_table <- data.frame(
      k = seq_along(facets),
      direct_facets = vapply(four_facet_designs, function(x)
        paste(x$direct_facets, collapse = ", "), character(1)),
      random_sources = vapply(four_facet_designs, function(x) length(x$terms), integer(1)),
      row.names = NULL)
    cat("Four-facet specifications (all requests retained; full-cell alias resolved at Gaussian fitting):\n")
    print(design_table, row.names = FALSE)

    # Gaussian: a complete item x rater panel. One outcome and two jointly
    # modeled outcomes use the same function and source covariance structure.
    set.seed(1201)
    normal_data <- expand.grid(item = seq_len(20), rater = seq_len(6))
    object_effect <- matrix(rnorm(40), 20, 2) %*% chol(matrix(c(1.2, .65, .65, .9), 2))
    rater_effect <- matrix(rnorm(12), 6, 2) %*% chol(matrix(c(.25, .1, .1, .2), 2))
    error <- matrix(rnorm(2 * nrow(normal_data)), nrow(normal_data), 2) %*%
      chol(matrix(c(.6, .18, .18, .7), 2))
    normal_data$quality <- 2 + object_effect[normal_data$item, 1] +
      rater_effect[normal_data$rater, 1] + error[, 1]
    normal_data$helpfulness <- 1 + object_effect[normal_data$item, 2] +
      rater_effect[normal_data$rater, 2] + error[, 2]
    normal_design <- gt_design("item", "rater")
    gaussian_control <- gt_control(gaussian = list(silent = TRUE, threads = 1L,
                                                   extra_tries = 2L, retry_seed = 1201L))
    gaussian <- gt_fit(normal_data, "quality", normal_design,
                        family = gt_family("gaussian"), control = gaussian_control)
    gaussian_joint <- gt_fit(normal_data, c("quality", "helpfulness"), normal_design,
                              family = gt_family("gaussian"), covariance = "unstructured",
                              control = gaussian_control)
    composite <- gt_score(c(quality = .5, helpfulness = .5))
    gaussian_reliability <- gt_reliability(gaussian_joint, scale = "observed", score = composite)
    gaussian_dstudy <- gt_dstudy(gaussian_joint, data.frame(rater = c(2L, 4L, 6L, 8L)),
                                  scale = "observed", score = composite)

    # Binary and ordinal: repeated measurements with distinct observation
    # models. The binary uses logit here; the ordinal uses ordered probit.
    set.seed(912)
    discrete_data <- expand.grid(item = seq_len(24), rater = seq_len(4), replicate = seq_len(3))
    object_effect <- rnorm(24, sd = .9)
    rater_effect <- c(-.5, -.1, .1, .5)
    eta <- -.2 + object_effect[discrete_data$item] + rater_effect[discrete_data$rater]
    discrete_data$success <- rbinom(nrow(discrete_data), 1, plogis(eta))
    discrete_data$rating <- cut(eta + rnorm(nrow(discrete_data)), c(-Inf, -.4, .7, Inf),
                                labels = c("low", "mid", "high"), ordered_result = TRUE)
    # Explicit additive source specification avoids introducing an unrequested
    # item-by-rater interaction; replication is declared independently.
    discrete_design <- gt_design("item", "rater", random = ~ item + rater, replicates = 3L)
    discrete_control <- gt_control(discrete = list(maxit = 200L))
    binary <- gt_fit(discrete_data, "success", discrete_design,
                      family = gt_family("binary", link = "logit"), control = discrete_control)
    ordinal <- gt_fit(discrete_data, "rating", discrete_design,
                       family = gt_family("ordinal", link = "probit",
                                          levels = c("low", "mid", "high")),
                       control = discrete_control)
    # These are latent-response G/Phi. Observed binary-proportion or ordinal-
    # score reliability requires integration and is not implemented yet.
    # Numerical rejection is an inspectable result, not permission to calculate
    # coefficients. This example preserves the original data/model regardless
    # of whether the new independent acceptance checks pass.
    coefficient_if_accepted <- function(fit) {
      if (isTRUE(fit$numerically_accepted)) gt_reliability(fit, scale="latent") else NULL
    }
    dstudy_if_accepted <- function(fit) {
      if (isTRUE(fit$numerically_accepted))
        gt_dstudy(fit, data.frame(rater=c(2L,4L,6L)), scale="latent") else NULL
    }
    binary_reliability <- coefficient_if_accepted(binary)
    ordinal_reliability <- coefficient_if_accepted(ordinal)
    binary_dstudy <- dstudy_if_accepted(binary)
    ordinal_dstudy <- dstudy_if_accepted(ordinal)

    # Unordered categorical: three labels with an explicit reference category.
    # A softmax likelihood fits the categories jointly, without ordering them.
    set.seed(901)
    nominal_data <- expand.grid(item = seq_len(12), rater = seq_len(3), replicate = seq_len(3))
    category_effect <- matrix(rnorm(24, sd = .6), 12, 2)
    contrast <- cbind(.3 + category_effect[nominal_data$item, 1],
                       -.4 + category_effect[nominal_data$item, 2])
    probability <- cbind(1, exp(contrast))
    probability <- probability / rowSums(probability)
    nominal_data$class <- factor(vapply(seq_len(nrow(nominal_data)), function(i)
      sample(c("a", "b", "c"), 1, prob = probability[i, ]), character(1)),
      levels = c("a", "b", "c"))
    categorical <- gt_fit(nominal_data, "class", discrete_design,
                           family = gt_family("categorical", levels = c("a", "b", "c"), reference = "a"),
                           covariance = "diagonal", control = discrete_control)
    # Nominal classes have no default scalar G/Phi. A meaningful score or
    # category-probability estimand must be defined before adding reliability.
    # These predictions condition on fitted random-effect modes; they are not
    # population-marginal probabilities.
    nominal_probability <- categorical$conditional_probabilities$class
    stopifnot(max(abs(rowSums(nominal_probability) - 1)) < 1e-10)

    fits <- list(gaussian = gaussian, gaussian_joint = gaussian_joint,
                  binary = binary, ordinal = ordinal, categorical = categorical)
    convergence <- data.frame(
      model = names(fits),
      estimator = vapply(fits, `[[`, character(1), "estimator"),
      rows = vapply(fits, function(x) as.integer(x$N), integer(1)),
      optimizer_completed = vapply(fits, function(x) isTRUE(x$optimizer_completed), logical(1)),
      numerically_accepted = vapply(fits, function(x) isTRUE(x$numerically_accepted), logical(1)),
      minus2loglik = vapply(fits, `[[`, numeric(1), "minus2loglik"), row.names = NULL)
    cat("\nSmall simulated fits (likelihoods across families are not comparable):\n")
    print(convergence, row.names = FALSE)
    stopifnot(gaussian$numerically_accepted, gaussian_joint$numerically_accepted,
      all(vapply(fits, function(f) identical(f$converged, f$numerically_accepted), logical(1))))
    for (name in c("binary", "ordinal", "categorical")) {
      fit <- fits[[name]]
      # A bounded optimizer may evaluate a variance coordinate a few ulps below
      # its zero lower bound. That is arithmetic on the boundary, not a model
      # failure, and must never be recorded as a computation failure. Assert the
      # arithmetic rather than the acceptance verdict: optimizer trajectories
      # differ across platforms, so asserting acceptance here would go red for
      # reasons that are not defects.
      recorded <- unlist(lapply(fit$diagnostics$attempts, `[[`, "error"))
      if (any(grepl("nonnegative", recorded, fixed = TRUE)))
        stop("Discrete fit '", name, "' treated a variance coordinate at its zero ",
             "boundary as invalid instead of projecting it.", call. = FALSE)
      if (!fit$numerically_accepted) {
        cat("Numerically rejected", name, ":", paste(fit$diagnostics$acceptance_failures, collapse=", "), "\n")
        if (name != "categorical") stopifnot(inherits(tryCatch(
          gt_reliability(fit, scale="latent"), error=identity), "error"))
      }
    }
    cat("\nJoint Gaussian observed-scale reliability:\n")
    print(gaussian_reliability$per_trait, row.names = FALSE)
    cat("Composite:\n"); print(gaussian_reliability$composite, row.names = FALSE)
    cat("\nBinary latent-scale reliability:\n")
    if (is.null(binary_reliability)) cat("Unavailable: numerical acceptance failed.\n") else
      print(binary_reliability$per_trait, row.names = FALSE)
    cat("\nOrdinal latent-scale reliability:\n")
    if (is.null(ordinal_reliability)) cat("Unavailable: numerical acceptance failed.\n") else
      print(ordinal_reliability$per_trait, row.names = FALSE)
    cat("\nJoint Gaussian D-study:\n")
    print(gaussian_dstudy$results, row.names = FALSE)
    cat("\nNominal reference contrasts:\n")
    print(categorical$link_dimensions, row.names = FALSE)
    cat("\nInspect gt_diagnostics(fit) before interpreting any fitted coefficients.\n")
    list(designs = four_facet_designs, full_crossed = full_crossed,
         selected_nested = selected_nested, design_table = design_table,
         fits = fits, convergence = convergence,
         reliability = list(gaussian = gaussian_reliability, binary = binary_reliability,
                              ordinal = ordinal_reliability),
         dstudies = list(gaussian = gaussian_dstudy, binary = binary_dstudy, ordinal = ordinal_dstudy))
  }
  run_examples()
})
