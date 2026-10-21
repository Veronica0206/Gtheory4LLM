# Fixed-point solver regressions from refused synthetic full-panel fits.
# This is not an outer fit, approximation check, coverage study or qualification
# of full-panel estimation. It uses five conditional solves, 819 latent effects,
# and the existing sparse major-array estimate of less than 45 MiB.
source("load_functions.R")

data <- expand.grid(item = seq_len(100L), evaluator = seq_len(4L),
  prompt = seq_len(3L), temperature = seq_len(6L), seed = seq_len(3L))
truth <- c(item = 1, evaluator = .2, prompt = .15, "item:evaluator" = .25,
  "item:prompt" = .2, "evaluator:prompt" = .1)
set.seed(2026102101L)
true_eta <- numeric(nrow(data))
generator_groups <- list()
for (name in names(truth)) {
  members <- strsplit(name, ":", fixed = TRUE)[[1L]]
  index <- do.call(interaction, c(data[members], list(drop = TRUE)))
  generator_groups[[name]] <- as.integer(index)
  true_eta <- true_eta + rnorm(nlevels(index), sd = sqrt(truth[[name]]))[as.integer(index)]
}
latent <- true_eta + rnorm(nrow(data))
data$y <- ordered(c("low", "middle", "high")[1L + (latent > -.7) + (latent > .6)],
  levels = c("low", "middle", "high"))
stopifnot(identical(as.integer(table(data$y)), c(7598L, 6719L, 7283L)))
design <- gt_design("item", c("evaluator", "prompt", "temperature", "seed"), random = names(truth))
families <- list(y = gt_family("ordinal", "probit", levels(data$y)))
prep <- .gt_d_prepare(data, "y", families)
groups <- lapply(design$term_members, function(x) .gt_d_group(data, x))
for (name in names(groups)) stopifnot(identical(groups[[name]]$index, generator_groups[[name]]))
dimension <- sum(vapply(groups, `[[`, integer(1), "nlevels"))
stopifnot(dimension == 819L, .gt_d_sparse_bytes(nrow(data), 1L, dimension, length(groups))$total < 45 * 1024^2)
control <- .gt_d_control(list(engine = "sparse", max_observations = 21600L, max_random_dimension = 819L))
setup <- .gt_d_covariance_setup(groups, 1L, "unstructured", control, "y")

# Direct normal CDF/density arithmetic is independent of the package's
# log-interval response kernel. Use the upper tail when lower CDF subtraction
# would lose precision. All probabilities in these fixtures are representable.
independent_response <- function(eta, thresholds) {
  category <- as.integer(data$y)
  cuts <- c(-Inf, thresholds, Inf)
  lo <- cuts[category] - eta
  hi <- cuts[category + 1L] - eta
  probability <- pnorm(hi) - pnorm(lo)
  upper <- lo > 0
  probability[upper] <- pnorm(lo[upper], lower.tail = FALSE) - pnorm(hi[upper], lower.tail = FALSE)
  stopifnot(all(is.finite(probability)), all(probability > 0))
  lower_density <- dnorm(lo)
  upper_density <- dnorm(hi)
  gradient <- (upper_density - lower_density) / probability
  lower_term <- upper_term <- numeric(length(eta))
  lower_term[is.finite(lo)] <- lo[is.finite(lo)] * lower_density[is.finite(lo)]
  upper_term[is.finite(hi)] <- hi[is.finite(hi)] * upper_density[is.finite(hi)]
  list(nll = -sum(log(probability)), gradient = gradient,
    curvature = gradient^2 + (upper_term - lower_term) / probability)
}

# Zero predictors give an independent multinomial NLL oracle; the actual
# generator predictors additionally exercise the full range of response tails.
truth_parameters <- c(prep$start, setup$start)
truth_parameters[1:2] <- c(-.7, log(1.3))
truth_parameters[paste0(names(truth), "::variance[y]")] <- truth
zero <- independent_response(rep(0, nrow(data)), c(-.7, .6))
probabilities <- c(pnorm(-.7), pnorm(.6) - pnorm(-.7), pnorm(.6, lower.tail = FALSE))
stopifnot(abs(zero$nll + sum(as.numeric(table(data$y)) * log(probabilities))) < 1e-8)
for (eta in list(rep(0, nrow(data)), true_eta)) {
  direct <- independent_response(eta, c(-.7, .6))
  kernel <- .gt_d_response_kernel(matrix(eta), truth_parameters, prep)
  stopifnot(kernel$valid, abs(kernel$nll - direct$nll) < 1e-8,
    max(abs(kernel$gradient - direct$gradient)) < 1e-10,
    max(abs(kernel$curvature[[1L]]$diagonal - direct$curvature)) < 1e-9)
}

# Exact stored coordinates, including the actual perturbation. These are not
# estimates we endorse. The first is a tight nlminb threshold-spacing probe;
# the second is a coarse L-BFGS-B negative evaluator-variance probe.
parameter_names <- c("y::threshold_parameter1", "y::threshold_parameter2",
  "evaluator::variance[y]", "item::variance[y]", "prompt::variance[y]",
  "evaluator:prompt::variance[y]", "item:evaluator::variance[y]", "item:prompt::variance[y]")
points <- list(
  nlminb_stationarity = setNames(c(-0.38678920669900513, 0.25588258731782226,
    0.10282421092334858, 0.49102019135462666, 0.10628945260275492,
    0.08387086856064517, 0.36678678128870812, 0.25548547163762481), parameter_names),
  lbfgsb_neighbor = setNames(c(-0.37401009503493715, 0.2987105073717185,
    0.14348963468685855, 24.957347184523726, 0.12175412090417109,
    0.086361813108614349, 18.061881834559731, 1.2947404368987327), parameter_names),
  # These later failures have decrements 1.6 to 8.3 times the small plateau
  # window. Their full steps reach stationary modes, independently checked below.
  nlminb_item_derivative = setNames(c(-0.54124396416108933, 0.25368848190070359,
    0.17048730508502219, 0.68792145464510546, 0.094896366363645873,
    0.049856224789776943, 0.28439243758667981, 0.17136225500931179), parameter_names),
  lbfgsb_alternative_path = setNames(c(-0.25518269235378249, 0.17616082580689249,
    rep(0.46118363886741603, 6)), parameter_names),
  lbfgsb_prompt_boundary = setNames(c(-0.41533071839007413, 0.25314687853367585,
    0.17541459564712297, 0.90584668173633653, 0,
    0.05591154715614622, 0.27660941825862806, 0.17478535020283403), parameter_names))
tolerances <- c(nlminb_stationarity = 1e-9, lbfgsb_neighbor = 1e-7,
  nlminb_item_derivative = 1e-9, lbfgsb_alternative_path = 1e-7, lbfgsb_prompt_boundary = 1e-7)
for (name in names(points)) {
  parameters <- points[[name]][names(truth_parameters)]
  stopifnot(!anyNA(parameters))
  settings <- control
  settings$inner_tol <- tolerances[[name]]
  stopifnot(settings$inner_maxit == 60L)
  factors <- .gt_d_covariance_factors(parameters[-seq_along(prep$start)], setup)
  backend <- .gt_d_sparse_backend(groups, factors, nrow(data), 1L)
  result <- .gt_d_sparse_mode(parameters, prep, backend, settings, details = TRUE)
  stopifnot(isTRUE(result$valid), isTRUE(result$inner_converged),
    result$inner_gradient <= 10 * settings$inner_tol, result$inner_iterations <= settings$inner_maxit)
  thresholds <- c(parameters[[1L]], parameters[[1L]] + exp(parameters[[2L]]))
  direct <- independent_response(as.numeric(result$eta), thresholds)
  fresh_score <- as.numeric(Matrix::crossprod(backend$W, direct$gradient)) + result$mode
  stopifnot(max(abs(fresh_score)) <= 10 * settings$inner_tol,
    abs(result$conditional_nll - direct$nll) < 1e-8,
    max(abs(as.numeric(backend$W %*% result$mode) - as.numeric(result$eta))) < 1e-12)
  # Independently assemble the Hessian from the direct density derivatives.
  # Its final factor must pass the existing unchanged backward-error probes.
  H <- Matrix::crossprod(backend$W, Matrix::Diagonal(x = direct$curvature) %*% backend$W) +
    Matrix::Diagonal(ncol(backend$W))
  factor <- .gt_d_sparse_factor(H)
  stopifnot(isTRUE(.gt_d_sparse_final_factor_check(H, factor)$valid))
  independently_assembled_nll <- direct$nll + sum(result$mode^2) / 2 + .gt_d_sparse_logdet(factor) / 2
  stopifnot(abs(result$nll - independently_assembled_nll) < 1e-7)
  cat("PASS:", name, "fixed-point score and factor gates; independent ordinal-probit arithmetic.\n")
}
cat("Full-panel conditional-mode regressions passed; no full-fit qualification is implied.\n")
