# Calibration phase of the frozen dense/sparse equivalence study (CALIBRATION.md).
#
# Run from the project directory:
#   Rscript --vanilla validation-studies/discrete-sparse-equivalence/calibrate.R
# The record is written to validation-studies/discrete-sparse-equivalence/calibration/
# (an explicit output directory may be given as the only argument).
#
# Non-scoring. It evaluates the six frozen calibration cases (EQ_CALIBRATION)
# in both backends at the three frozen fixed-parameter points, under the frozen
# controls, with the frozen metrics (.eq_difference) and validity witnesses
# (EQ_VALIDITY), fits each case through the public interface in both engines
# for the latent G/Phi rule, and applies the frozen equivariance transforms
# within each backend. It writes observations and a PROPOSED tolerance table.
# It commits nothing and never adopts an observed maximum as a tolerance.
args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) <= 1L)
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
OUT <- if (length(args)) args[[1L]] else file.path(STUDY, "calibration")
if (dir.exists(OUT) && length(list.files(OUT)))
  stop("Refusing to overwrite an existing calibration record in ", OUT, call. = FALSE)
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
suppressMessages(library(Matrix))
source("load_functions.R")
source(file.path(STUDY, "cases.R"))

log_line <- function(...) { cat(format(Sys.time(), "%H:%M:%S"), ..., "\n"); flush.console() }
EPS <- .Machine$double.eps

# ---- environment record ---------------------------------------------------------
env <- list(
  r_version = R.version.string,
  matrix_version = as.character(packageVersion("Matrix")),
  blas = extSoftVersion()[["BLAS"]], lapack = La_library(), lapack_version = La_version(),
  long_double = capabilities("long.double"),
  cpu = tryCatch(system("sysctl -n machdep.cpu.brand_string", intern = TRUE), error = function(e) NA),
  source_commit = tryCatch(system("git rev-parse HEAD", intern = TRUE), error = function(e) NA),
  tracked_changes = tryCatch(length(system("git status --short --untracked-files=no", intern = TRUE)), error = function(e) NA),
  untracked_files = tryCatch(paste(system("git status --short --untracked-files=all | grep '^??' | sed 's/^?? //'", intern = TRUE), collapse = " "), error = function(e) NA),
  threads = Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "VECLIB_MAXIMUM_THREADS")),
  started_utc = format(Sys.time(), tz = "UTC", usetz = TRUE))
writeLines(c(paste0(names(env), ": ", vapply(env, function(v) paste(v, collapse = " "), "")),
             "", "Frozen study digests (normalized md5):",
             readLines(file.path(STUDY, "source-hashes.csv"))), file.path(OUT, "environment.txt"))

# ---- observation sinks ----------------------------------------------------------
obs <- list(); val <- list(); fits <- list(); problems <- list()
add_obs <- function(...) obs[[length(obs) + 1L]] <<- data.frame(..., stringsAsFactors = FALSE)
add_val <- function(...) val[[length(val) + 1L]] <<- data.frame(..., stringsAsFactors = FALSE)
add_fit <- function(...) fits[[length(fits) + 1L]] <<- data.frame(..., stringsAsFactors = FALSE)
add_problem <- function(...) problems[[length(problems) + 1L]] <<- paste0(...)

# ---- backend-local quantities at a solved mode (stage 1 witnesses + log det) ----
dense_at_mode <- function(answer, theta, prep, Wd) {
  kernel <- .gt_d_response_kernel(answer$eta, theta, prep)
  H <- .gt_d_dense_hessian(kernel$curvature, Wd, prep$n)
  R <- chol(H)
  d <- nrow(H)
  probes <- .gt_d_solve_probes(d)
  probe_err <- max(vapply(probes, function(b) {
    x <- backsolve(R, forwardsolve(t(R), b)); .gt_d_backward_error(H, b, x) }, numeric(1)))
  g <- as.vector(crossprod(Wd, kernel$gradient)) + answer$mode
  newton <- .gt_d_backward_error(H, g, backsolve(R, forwardsolve(t(R), g)))
  eig <- eigen(H, symmetric = TRUE, only.values = TRUE)$values
  logdet <- 2 * sum(log(diag(R)))
  list(logdet = logdet, factor_reconstruction = max(abs(crossprod(R) - H)) / max(abs(H)),
       logdet_witness = abs(logdet - sum(log(eig))), probe_backward_error = probe_err,
       newton_backward_error_at_mode = newton,
       package_factor_valid = isTRUE(.gt_d_final_factor_check(H, R)$valid),
       conditional_nll = answer$conditional_nll, dimension = d)
}
sparse_at_mode <- function(answer, theta, prep, Ws) {
  kernel <- .gt_d_response_kernel(answer$eta, theta, prep)
  H <- .gt_d_sparse_hessian(kernel$curvature, Ws, prep$n)
  fac <- .gt_d_sparse_factor(H)
  d <- nrow(H)
  probes <- .gt_d_solve_probes(d)
  probe_err <- max(vapply(probes, function(b) {
    x <- .gt_d_sparse_solve(fac, b); .gt_d_backward_error(H, b, x) }, numeric(1)))
  g <- as.numeric(Matrix::crossprod(Ws, kernel$gradient)) + answer$mode
  newton <- .gt_d_backward_error(H, g, .gt_d_sparse_solve(fac, g))
  Hd <- as.matrix(H)
  Hhat <- as.matrix(Reduce(`%*%`, Matrix::expand2(fac$factor, LDL = FALSE)))
  eig <- eigen(Hd, symmetric = TRUE, only.values = TRUE)$values
  logdet <- .gt_d_sparse_logdet(fac)
  list(logdet = logdet, factor_reconstruction = max(abs(Hhat - Hd)) / max(abs(Hd)),
       logdet_witness = abs(logdet - sum(log(eig))), probe_backward_error = probe_err,
       newton_backward_error_at_mode = newton,
       package_factor_valid = isTRUE(.gt_d_sparse_final_factor_check(H, fac)$valid),
       conditional_nll = answer$conditional_nll, dimension = d)
}
record_validity <- function(case, point, transform, backend, at, answer) {
  bound <- EQ_VALIDITY_BOUND(at$dimension)
  add_val(case = case, point = point, transform = transform, backend = backend,
          random_dimension = at$dimension, validity_bound = bound,
          solve_backward_error_probes = at$probe_backward_error,
          newton_backward_error_at_mode = at$newton_backward_error_at_mode,
          factor_reconstruction = at$factor_reconstruction,
          log_determinant_witness = at$logdet_witness,
          finite_mode = all(is.finite(answer$mode)),
          finite_objective = is.finite(answer$nll) && answer$nll < 1e99,
          package_factor_valid = at$package_factor_valid,
          inner_iterations = answer$inner_iterations,
          inner_roundoff_steps = if (is.null(answer$inner_roundoff_steps)) NA_integer_ else answer$inner_roundoff_steps,
          inner_warm_started = isTRUE(answer$inner_warm_started),
          r1_event = !(at$probe_backward_error <= bound && at$factor_reconstruction <= bound &&
                       at$logdet_witness <= bound && all(is.finite(answer$mode)) &&
                       is.finite(answer$nll) && at$package_factor_valid))
}

# ---- one fixed-parameter comparison ---------------------------------------------
compare_point <- function(case, point, transform, theta, prep, groups, setup, control,
                          evaluator, dimension, rank) {
  fixed_length <- length(prep$start)
  factors <- .gt_d_covariance_factors(theta[-seq_len(fixed_length)], setup)
  Wd <- .gt_d_dense_backend(groups, factors, prep$n, prep$q)$W
  Ws <- .gt_d_sparse_backend(groups, factors, prep$n, prep$q)$W
  baseline <- .gt_d_baseline(theta, prep)
  u0 <- numeric(ncol(Wd))
  eta_d0 <- baseline + matrix(Wd %*% u0, prep$n, prep$q)
  eta_s0 <- baseline + matrix(as.numeric(Ws %*% u0), prep$n, prep$q)
  k_d0 <- .gt_d_response_kernel(eta_d0, theta, prep)
  k_s0 <- .gt_d_response_kernel(eta_s0, theta, prep)
  stopifnot(isTRUE(k_d0$valid), isTRUE(k_s0$valid))
  rec <- function(stage, quantity, a, b) add_obs(case = case, point = point, transform = transform,
    stage = stage, quantity = quantity, metric = EQ_METRIC[[quantity]]$form,
    difference = .eq_difference(a, b, quantity), scale = max(max(abs(a)), max(abs(b))),
    random_dimension = dimension, kernel_rank = rank)
  rec(3L, "predictor", eta_d0, eta_s0)
  rec(3L, "conditional_objective", k_d0$nll + sum(u0^2) / 2, k_s0$nll + sum(u0^2) / 2)
  rec(3L, "mode_score", as.vector(crossprod(Wd, k_d0$gradient)) + u0,
      as.numeric(Matrix::crossprod(Ws, k_s0$gradient)) + u0)
  rec(3L, "hessian", .gt_d_dense_hessian(k_d0$curvature, Wd, prep$n),
      as.matrix(.gt_d_sparse_hessian(k_s0$curvature, Ws, prep$n)))
  dense <- .gt_d_laplace(theta, prep, groups, setup, control, details = TRUE)
  sparse <- evaluator(theta, prep, groups, setup, control, details = TRUE)
  if (!isTRUE(dense$valid) || !isTRUE(sparse$valid)) {
    add_problem(case, "/", point, "/", transform, ": solved evaluation unavailable (dense valid=",
                isTRUE(dense$valid), ", sparse valid=", isTRUE(sparse$valid), "; reasons: ",
                paste(c(dense$reason, sparse$reason), collapse = "|"), ")")
    return(invisible(list(dense = dense, sparse = sparse)))
  }
  at_d <- dense_at_mode(dense, theta, prep, Wd)
  at_s <- sparse_at_mode(sparse, theta, prep, Ws)
  record_validity(case, point, transform, "dense", at_d, dense)
  record_validity(case, point, transform, "sparse", at_s, sparse)
  rec(3L, "conditional_mode", dense$mode, sparse$mode)
  rec(3L, "log_determinant", at_d$logdet, at_s$logdet)
  rec(3L, "marginal_negative_log_likelihood", dense$nll, sparse$nll)
  # Not a calibrated quantity: the conditional objective at each backend's own
  # mode, recorded as an observation only.
  add_obs(case = case, point = point, transform = transform, stage = 3L,
          quantity = "conditional_objective_at_own_mode", metric = "absolute",
          difference = abs(dense$conditional_nll - sparse$conditional_nll),
          scale = max(abs(dense$conditional_nll), abs(sparse$conditional_nll)),
          random_dimension = dimension, kernel_rank = rank)
  invisible(list(dense = dense, sparse = sparse, logdet = c(dense = at_d$logdet, sparse = at_s$logdet)))
}

# ---- equivariance within one backend (stage 5 rule) ---------------------------
eq_rec <- function(case, backend, transform, quantity, a, b, dimension, rank)
  add_obs(case = case, point = "start", transform = paste0(transform, ":", backend), stage = 5L,
          quantity = "equivariance", metric = "symmetric_relative",
          difference = .eq_difference(a, b, "equivariance"), scale = max(max(abs(a)), max(abs(b))),
          random_dimension = dimension, kernel_rank = rank, sub_quantity = quantity)
solve_both <- function(theta, prep, groups, setup, control) {
  d <- .gt_d_laplace(theta, prep, groups, setup, control, details = TRUE)
  s <- .gt_d_sparse_evaluator()(theta, prep, groups, setup, control, details = TRUE)
  stopifnot(isTRUE(d$valid), isTRUE(s$valid))
  Wd <- .gt_d_dense_backend(groups, d$factors, prep$n, prep$q)$W
  Ws <- .gt_d_sparse_backend(groups, s$factors, prep$n, prep$q)$W
  list(dense = c(d, list(logdet = dense_at_mode(d, theta, prep, Wd)$logdet)),
       sparse = c(s, list(logdet = sparse_at_mode(s, theta, prep, Ws)$logdet)))
}
block_offsets <- function(groups) cumsum(c(0L, vapply(groups, `[[`, integer(1), "nlevels")))
equivariance <- function(case, row, map, theta, dimension, rank) {
  prep <- map$prep; groups <- map$groups; setup <- map$setup; control <- map$control
  profile <- EQ_COVARIANCE_PROFILE[[row$covariance]]
  base <- solve_both(theta, prep, groups, setup, control)
  n <- prep$n
  # T4: identical inputs evaluated twice.
  again <- solve_both(theta, prep, groups, setup, control)
  for (b in c("dense", "sparse")) {
    eq_rec(case, b, "T4_repeat", "marginal_nll", base[[b]]$nll, again[[b]]$nll, dimension, rank)
    eq_rec(case, b, "T4_repeat", "conditional_mode", base[[b]]$mode, again[[b]]$mode, dimension, rank)
    eq_rec(case, b, "T4_repeat", "log_determinant", base[[b]]$logdet, again[[b]]$logdet, dimension, rank)
  }
  # T1: observation order reversed. Level numbering follows first appearance,
  # so each source's coordinates are permuted; map them back through the rows.
  panel_r <- map$panel[rev(seq_len(n)), , drop = FALSE]; rownames(panel_r) <- NULL
  prep_r <- .gt_d_prepare(panel_r, .eq_outcomes(row$family), .eq_families(row$family, row$link, row$geometry))
  design <- EQ_DESIGNS[[row$structure]]
  groups_r <- lapply(design$term_members, function(m) .gt_d_group(panel_r, m))
  setup_r <- .gt_d_covariance_setup(groups_r, prep_r$q, profile$covariance, control, prep_r$dimensions)
  stopifnot(isTRUE(all.equal(c(prep_r$start, setup_r$start), unname(c(prep$start, setup$start)), check.attributes = FALSE)))
  rev_r <- solve_both(theta, prep_r, groups_r, setup_r, control)
  off <- block_offsets(groups); off_r <- block_offsets(groups_r)
  map_mode <- function(mode_r) {
    out <- numeric(length(mode_r))
    for (s in seq_along(groups)) {
      g <- groups[[s]]$index; gr <- groups_r[[s]]$index
      for (a in seq_len(groups[[s]]$nlevels)) {
        i <- which(g == a)[[1L]]
        out[off[[s]] + a] <- mode_r[off_r[[s]] + gr[[n + 1L - i]]]
      }
    }
    out
  }
  for (b in c("dense", "sparse")) {
    eq_rec(case, b, "T1_row_reversal", "marginal_nll", base[[b]]$nll, rev_r[[b]]$nll, dimension, rank)
    eq_rec(case, b, "T1_row_reversal", "conditional_objective", base[[b]]$conditional_nll, rev_r[[b]]$conditional_nll, dimension, rank)
    eq_rec(case, b, "T1_row_reversal", "log_determinant", base[[b]]$logdet, rev_r[[b]]$logdet, dimension, rank)
    eq_rec(case, b, "T1_row_reversal", "conditional_mode", base[[b]]$mode, map_mode(rev_r[[b]]$mode), dimension, rank)
    eq_rec(case, b, "T1_row_reversal", "predictor", as.numeric(base[[b]]$eta), as.numeric(rev_r[[b]]$eta)[rev(seq_len(n))], dimension, rank)
  }
  # T2: source order reversed (one covariance coordinate per source here, q = 1).
  if (length(groups) > 1L && prep$q == 1L) {
    groups_2 <- rev(groups)
    setup_2 <- .gt_d_covariance_setup(groups_2, prep$q, profile$covariance, control, prep$dimensions)
    fixed_length <- length(prep$start)
    cov <- theta[-seq_len(fixed_length)]
    stopifnot(length(cov) == length(groups), length(setup_2$start) == length(cov))
    theta_2 <- c(theta[seq_len(fixed_length)], rev(cov))
    rev_2 <- solve_both(theta_2, prep, groups_2, setup_2, control)
    sizes <- vapply(groups, `[[`, integer(1), "nlevels")
    perm <- unlist(lapply(rev(seq_along(groups)), function(s) off[[s]] + seq_len(sizes[[s]])))
    for (b in c("dense", "sparse")) {
      eq_rec(case, b, "T2_source_reversal", "marginal_nll", base[[b]]$nll, rev_2[[b]]$nll, dimension, rank)
      eq_rec(case, b, "T2_source_reversal", "log_determinant", base[[b]]$logdet, rev_2[[b]]$logdet, dimension, rank)
      eq_rec(case, b, "T2_source_reversal", "conditional_mode", base[[b]]$mode[perm], rev_2[[b]]$mode, dimension, rank)
      eq_rec(case, b, "T2_source_reversal", "predictor", as.numeric(base[[b]]$eta), as.numeric(rev_2[[b]]$eta), dimension, rank)
    }
  }
  # T5: level labels reversed within each source, structure preserved.
  groups_5 <- lapply(groups, function(g) list(index = g$nlevels + 1L - g$index, nlevels = g$nlevels))
  rev_5 <- solve_both(theta, prep, groups_5, setup, control)
  perm5 <- unlist(lapply(seq_along(groups), function(s) off[[s]] + rev(seq_len(groups[[s]]$nlevels))))
  for (b in c("dense", "sparse")) {
    eq_rec(case, b, "T5_level_relabelling", "marginal_nll", base[[b]]$nll, rev_5[[b]]$nll, dimension, rank)
    eq_rec(case, b, "T5_level_relabelling", "log_determinant", base[[b]]$logdet, rev_5[[b]]$logdet, dimension, rank)
    eq_rec(case, b, "T5_level_relabelling", "conditional_mode", base[[b]]$mode[perm5], rev_5[[b]]$mode, dimension, rank)
    eq_rec(case, b, "T5_level_relabelling", "predictor", as.numeric(base[[b]]$eta), as.numeric(rev_5[[b]]$eta), dimension, rank)
  }
}

# ---- fitted comparison (stage 4 rule) --------------------------------------------
# Dispositions, objectives and parameter distance come from the frozen internal
# designs through the private evaluator seam, exactly as the fitted smoke
# contract does, so every calibration case contributes. Latent G and Phi are
# the package's own gt_reliability() values, which need the public interface:
# a design with at least one facet and a complete balanced coded panel. The
# single-source case has no facet and the three-facet case is unbalanced in
# that sense, so those two contribute no G/Phi observation and say so.
scalar <- function(x, default = NA_real_) if (is.null(x) || !length(x)) default else x[[1L]]
summarize_fit <- function(fit, elapsed) {
  if (inherits(fit, "error")) return(list(status = "refused", message = conditionMessage(fit), elapsed = elapsed))
  list(status = if (isTRUE(fit$numerically_accepted)) "accepted" else "rejected", fit = fit, elapsed = elapsed,
       backend = scalar(fit$diagnostics$marginal_backend, NA_character_),
       nll = -scalar(fit$logLik), parameters = fit$parameters,
       failures = paste(sort(unique(unlist(fit$diagnostics$acceptance_failures))), collapse = "|"),
       evaluations = scalar(fit$diagnostics$evaluations$count, NA_integer_),
       invalid = scalar(fit$diagnostics$evaluations$invalid, NA_integer_))
}
internal_fit <- function(row, map, evaluator, label) {
  design <- EQ_DESIGNS[[row$structure]]
  profile <- EQ_COVARIANCE_PROFILE[[row$covariance]]
  started <- Sys.time()
  fit <- tryCatch(suppressWarnings(.gt_fit_discrete(
    map$panel, .eq_outcomes(row$family), design, .eq_families(row$family, row$link, row$geometry),
    covariance = profile$covariance, control = .eq_control_for(row$covariance),
    .laplace = evaluator, .engine = label)), error = function(e) e)
  summarize_fit(fit, as.numeric(difftime(Sys.time(), started, units = "secs")))
}
public_fit <- function(row, map, engine) {
  design <- EQ_DESIGNS[[row$structure]]
  if (!length(design$facets))
    return(list(status = "not_expressible", message = "the public interface requires at least one facet"))
  geometry <- EQ_CALIBRATION_GEOMETRY[[row$geometry]]
  replicates <- if (identical(row$structure, "crossed2")) geometry$reps else 1L
  gdesign <- tryCatch(gt_design("item", design$facets, random = names(design$term_members),
                                replicates = replicates), error = function(e) e)
  if (inherits(gdesign, "error")) return(list(status = "not_expressible", message = conditionMessage(gdesign)))
  panel <- map$panel
  spec <- .eq_families(row$family, row$link, row$geometry)[[1L]]
  if (identical(row$family, "binary")) panel$y <- factor(as.character(panel$y), levels = c("0", "1"))
  family <- gt_family(spec$family, spec$link, levels = spec$levels)
  profile <- EQ_COVARIANCE_PROFILE[[row$covariance]]
  discrete <- c(EQ_CONTROL, list(engine = engine))
  if (!identical(profile$parameterization, "auto") && !identical(profile$parameterization, "fixed"))
    discrete$covariance_parameterization <- profile$parameterization
  started <- Sys.time()
  fit <- tryCatch(suppressWarnings(gt_fit(panel, "y", design = gdesign, family = family,
    covariance = profile$covariance, control = gt_control(discrete = discrete))), error = function(e) e)
  out <- summarize_fit(fit, as.numeric(difftime(Sys.time(), started, units = "secs")))
  if (inherits(fit, "error")) return(out)
  out$same_terms <- identical(sort(names(fit$design$term_members)), sort(names(design$term_members))) &&
    all(vapply(names(design$term_members), function(k)
      identical(sort(fit$design$term_members[[k]]), sort(design$term_members[[k]])), logical(1)))
  latent <- if (isTRUE(fit$numerically_accepted))
    tryCatch(as.data.frame(gt_reliability(fit, scale = "latent")),
             error = function(e) structure(list(message = conditionMessage(e)), class = "latent_unavailable"))
  else structure(list(message = "fit not accepted"), class = "latent_unavailable")
  out$latent_message <- if (inherits(latent, "latent_unavailable")) latent$message else ""
  out$Erho2 <- if (is.data.frame(latent)) scalar(latent$Erho2) else NA_real_
  out$Phi <- if (is.data.frame(latent)) scalar(latent$Phi) else NA_real_
  out
}

# ================================================================================
started_all <- Sys.time()
for (i in seq_len(nrow(EQ_CALIBRATION))) {
  row <- EQ_CALIBRATION[i, ]
  case <- row$case
  log_line("==", case, row$family, row$link, row$structure, row$covariance, row$geometry)
  result <- tryCatch({
    geometry <- EQ_CALIBRATION_GEOMETRY[[row$geometry]]
    map <- .eq_parameter_map(row, geometry)
    dimension <- as.integer(sum(vapply(map$groups, `[[`, integer(1), "nlevels")) * map$prep$q)
    rank <- .gt_d_kernel_rank(map$groups)$rank
    points <- .eq_fixed_points(map$start, map$lower, map$upper, map$zero_coordinates)
    evaluator <- .gt_d_sparse_evaluator()
    for (label in EQ_FIXED_POINT_LABELS) {
      log_line("   point", label)
      compare_point(case, label, "none", points[[label]], map$prep, map$groups, map$setup,
                    map$control, evaluator, dimension, rank)
    }
    log_line("   equivariance transforms")
    equivariance(case, row, map, points$start, dimension, rank)
    log_line("   internal fits (frozen designs)")
    fd <- internal_fit(row, map, .gt_d_laplace, "dense_marginal_laplace")
    fs <- internal_fit(row, map, .gt_d_sparse_evaluator(), "sparse_marginal_laplace")
    distance <- if (!is.null(fd$parameters) && !is.null(fs$parameters))
      tryCatch(.gt_d_fit_distance(fd$parameters, fs$parameters, map$prep, map$setup),
               error = function(e) NA_real_) else NA_real_
    log_line("   public fits (latent G/Phi)")
    pd <- public_fit(row, map, "dense")
    ps <- public_fit(row, map, "sparse")
    add_fit(case = case, random_dimension = dimension,
            dense_status = fd$status, sparse_status = fs$status,
            dense_backend = scalar(fd$backend, NA_character_), sparse_backend = scalar(fs$backend, NA_character_),
            dense_nll = scalar(fd$nll), sparse_nll = scalar(fs$nll),
            objective_relative_difference = if (is.na(scalar(fd$nll)) || is.na(scalar(fs$nll))) NA_real_ else
              abs(fd$nll - fs$nll) / max(abs(fd$nll), abs(fs$nll)),
            parameter_max_abs_difference = if (is.null(fd$parameters) || is.null(fs$parameters)) NA_real_ else
              max(abs(fd$parameters - fs$parameters)),
            fit_distance = scalar(distance),
            dense_failures = scalar(if (is.null(fd$failures)) fd$message else fd$failures, ""),
            sparse_failures = scalar(if (is.null(fs$failures)) fs$message else fs$failures, ""),
            dense_evaluations = scalar(fd$evaluations, NA_integer_), sparse_evaluations = scalar(fs$evaluations, NA_integer_),
            dense_invalid = scalar(fd$invalid, NA_integer_), sparse_invalid = scalar(fs$invalid, NA_integer_),
            dense_seconds = scalar(fd$elapsed), sparse_seconds = scalar(fs$elapsed),
            public_dense_status = pd$status, public_sparse_status = ps$status,
            public_same_terms_as_frozen = isTRUE(pd$same_terms) && isTRUE(ps$same_terms),
            public_objective_relative_difference = if (is.na(scalar(pd$nll)) || is.na(scalar(ps$nll))) NA_real_ else
              abs(pd$nll - ps$nll) / max(abs(pd$nll), abs(ps$nll)),
            dense_Erho2 = scalar(pd$Erho2), sparse_Erho2 = scalar(ps$Erho2),
            dense_Phi = scalar(pd$Phi), sparse_Phi = scalar(ps$Phi),
            Erho2_difference = abs(scalar(pd$Erho2) - scalar(ps$Erho2)),
            Phi_difference = abs(scalar(pd$Phi) - scalar(ps$Phi)),
            latent_note = scalar(if (is.null(pd$latent_message)) pd$message else pd$latent_message, ""),
            public_dense_seconds = scalar(pd$elapsed), public_sparse_seconds = scalar(ps$elapsed))
    if (!identical(fd$status, fs$status))
      add_problem(case, ": internal dispositions differ (dense ", fd$status, ", sparse ", fs$status, ")")
    if (is.na(scalar(pd$Erho2)) || is.na(scalar(ps$Erho2)))
      add_problem(case, ": latent G/Phi not observed (", scalar(if (is.null(pd$latent_message)) pd$message else pd$latent_message, pd$status), ")")
    TRUE
  }, error = function(e) { add_problem(case, ": ", conditionMessage(e)); FALSE })
  log_line("   done:", result)
}

observations <- do.call(rbind, lapply(obs, function(d) { if (is.null(d$sub_quantity)) d$sub_quantity <- NA_character_; d }))
validity <- do.call(rbind, val)
fitted <- do.call(rbind, fits)
write.csv(observations, file.path(OUT, "observations.csv"), row.names = FALSE)
write.csv(validity, file.path(OUT, "validity.csv"), row.names = FALSE)
write.csv(fitted, file.path(OUT, "fits.csv"), row.names = FALSE)
writeLines(if (length(problems)) unlist(problems) else "none", file.path(OUT, "problems.txt"))

# ---- proposed tolerance table ----------------------------------------------------
# The observed maximum is never adopted. Proposal: at least one hundred times the
# observed maximum, rounded up to a power of ten, and never below 64 eps.
# The log determinant is proposed as c * random_dimension * eps, c from the
# dimension-normalized observation, because its attainable agreement grows with
# dimension (CALIBRATION.md).
r1 <- unique(validity[validity$r1_event, c("case", "point", "transform")])
is_r1 <- function(d) paste(d$case, d$point, d$transform) %in% paste(r1$case, r1$point, r1$transform)
scored <- observations[!is_r1(observations), ]
propose <- function(observed) 10^ceiling(log10(max(100 * observed, 64 * EPS)))
rows <- list()
for (q in c("predictor", "mode_score", "hessian", "conditional_mode")) {
  d <- scored[scored$quantity == q, ]
  m <- max(d$difference)
  rows[[q]] <- data.frame(quantity = q, rule_form = EQ_METRIC[[q]]$form, observed_maximum = m,
    proposed_tolerance = propose(m), margin = propose(m) / m,
    dimension_range = paste(range(d$random_dimension), collapse = "-"),
    observations = nrow(d), stringsAsFactors = FALSE)
}
d <- scored[scored$quantity == "log_determinant", ]
normalized <- d$difference / (d$random_dimension * EPS)
c_prop <- 10^ceiling(log10(max(100 * max(normalized), 1)))
rows$log_determinant <- data.frame(quantity = "log_determinant",
  rule_form = "absolute, c * random_dimension * eps", observed_maximum = max(d$difference),
  proposed_tolerance = c_prop, margin = c_prop / max(normalized),
  dimension_range = paste(range(d$random_dimension), collapse = "-"), observations = nrow(d),
  stringsAsFactors = FALSE)
rows$log_determinant$note <- paste0("observed max of |difference|/(d*eps) = ", format(max(normalized), digits = 4),
  "; proposed c = ", c_prop, " gives ", format(c_prop * 187 * EPS, digits = 3), " at d = 187")
g <- fitted[is.finite(fitted$Erho2_difference) & is.finite(fitted$Phi_difference), ]
mg <- if (nrow(g)) max(c(g$Erho2_difference, g$Phi_difference)) else NA_real_
rows$latent_g_phi <- data.frame(quantity = "latent_g_phi", rule_form = "absolute",
  observed_maximum = mg, proposed_tolerance = if (is.na(mg)) NA_real_ else propose(mg),
  margin = if (is.na(mg)) NA_real_ else propose(mg) / mg,
  dimension_range = if (nrow(g)) paste(range(g$random_dimension), collapse = "-") else "",
  observations = 2L * nrow(g), stringsAsFactors = FALSE)
e <- scored[scored$quantity == "equivariance", ]
me <- max(e$difference)
rows$equivariance <- data.frame(quantity = "equivariance", rule_form = "symmetric_relative",
  observed_maximum = me, proposed_tolerance = propose(me), margin = propose(me) / me,
  dimension_range = paste(range(e$random_dimension), collapse = "-"), observations = nrow(e),
  stringsAsFactors = FALSE)
for (q in EQ_INHERITED_PARITY) {
  d <- scored[scored$quantity == q, ]
  rows[[q]] <- data.frame(quantity = q, rule_form = "absolute (inherited 1e-10, not recalibrated)",
    observed_maximum = max(d$difference), proposed_tolerance = 1e-10,
    margin = 1e-10 / max(d$difference),
    dimension_range = paste(range(d$random_dimension), collapse = "-"), observations = nrow(d),
    stringsAsFactors = FALSE)
}
table <- do.call(rbind, lapply(rows, function(r) { if (is.null(r$note)) r$note <- ""; r }))
rownames(table) <- NULL
write.csv(table, file.path(OUT, "calibration-table.csv"), row.names = FALSE)
cat("\n==== proposed calibration table ====\n")
print(table, digits = 4, right = FALSE)
cat("\n==== validity witnesses (max per backend) ====\n")
print(aggregate(cbind(solve_backward_error_probes, factor_reconstruction, log_determinant_witness) ~ backend,
                validity, max), digits = 4)
cat("R1 events:", nrow(r1), "\n")
cat("\n==== fits ====\n")
print(fitted[, c("case", "random_dimension", "dense_status", "sparse_status",
                 "objective_relative_difference", "fit_distance", "dense_evaluations", "sparse_evaluations",
                 "dense_seconds", "sparse_seconds")], digits = 4)
cat("\n==== latent G/Phi through the public interface ====\n")
print(fitted[, c("case", "public_dense_status", "public_sparse_status", "public_same_terms_as_frozen",
                 "public_objective_relative_difference", "dense_Erho2", "sparse_Erho2", "Erho2_difference",
                 "Phi_difference", "latent_note")], digits = 4)
cat("\nproblems:", if (length(problems)) paste0("\n  ", unlist(problems)) else "none", "\n")
cat("elapsed minutes:", round(as.numeric(difftime(Sys.time(), started_all, units = "mins")), 1), "\n")
