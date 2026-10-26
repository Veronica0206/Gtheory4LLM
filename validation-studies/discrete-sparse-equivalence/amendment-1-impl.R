# Amendment 1 (AMENDMENT-1.md): the stage 3 judgment.
#
# Sourced after equivalence-runner-impl.R by run-equivalence-amendment-1.R. It
# replaces .eqr_stage3() and nothing else, so every other stage, the record and
# the stopping rules are the merged implementation's. It assigns no name that
# cases.R defines, and the frozen metric (.eq_difference) and tolerance values
# are used unchanged wherever the amendment keeps a frozen rule.
#
# Gating quantities at each frozen point:
#   predictor, conditional_objective, hessian    frozen rules at the common latent point
#   mode_score_summation_ratio                   A1, tolerance 1
#   conditional_mode_convexity_ratio             A2a, tolerance 1
#   conditional_objective_at_common_mode,
#   log_determinant_at_common_mode,
#   marginal_negative_log_likelihood_at_common_mode
#                                                A2b, frozen tolerances of the base quantity
# and, within each backend,
#   returned_conditional_objective,
#   returned_marginal_negative_log_likelihood    A2c, frozen tolerances of the base quantity
# The original "as produced" solved comparisons are recorded in detail.csv as
# information only.

.eqr1_gamma <- function(n) {
  u <- .Machine$double.eps / 2
  n * u / (1 - n * u)
}

# One backend's own evaluation at a given latent point: its design matrix, the
# shared response kernel, its Hessian and factorization. Nothing is solved.
.eqr1_at <- function(backend, map, theta, latent) {
  prep <- map$prep
  factors <- .gt_d_covariance_factors(theta[-seq_along(prep$start)], map$setup)
  W <- .eqr_design_matrix(backend, map, factors)
  eta <- .gt_d_baseline(theta, prep) + matrix(as.numeric(W %*% latent), prep$n, prep$q)
  kernel <- .gt_d_response_kernel(eta, theta, prep)
  if (!isTRUE(kernel$valid)) return(NULL)
  logdet <- if (identical(backend, "dense")) {
    2 * sum(log(diag(chol(.gt_d_dense_hessian(kernel$curvature, W, prep$n)))))
  } else .gt_d_sparse_logdet(.gt_d_sparse_factor(.gt_d_sparse_hessian(kernel$curvature, W, prep$n)))
  conditional <- kernel$nll + sum(latent^2) / 2
  list(eta = eta, gradient = as.numeric(kernel$gradient), conditional_objective = conditional,
       log_determinant = logdet, marginal_negative_log_likelihood = conditional + logdet / 2)
}

# A1: every score coordinate within twice the summation bound of its terms,
# given the shared predictor at the common latent point. The measurement is the
# largest ratio of difference to bound; a coordinate with no terms must agree
# exactly.
.eqr1_score_ratio <- function(Wd, Ws, eta_d, eta_s, gradient) {
  if (!identical(eta_d, eta_s)) return(NaN)
  dense <- as.numeric(crossprod(Wd, gradient))
  sparse <- as.numeric(Matrix::crossprod(Ws, gradient))
  bound <- 2 * .eqr1_gamma(nrow(Wd)) * as.numeric(crossprod(abs(Wd), abs(gradient)))
  difference <- abs(dense - sparse)
  if (!all(is.finite(difference)) || !all(is.finite(bound))) return(NaN)
  max(c(0, ifelse(bound > 0, difference / bound, ifelse(difference == 0, 0, Inf))))
}

# A2a: the two returned modes against the strong-convexity bound. g_b is each
# backend's reported max-norm gradient at its mode; e_b bounds the rounding of
# that report. Measured in the frozen symmetric relative metric for the mode.
.eqr1_mode_ratio <- function(answers, Wd, at_modes) {
  d <- length(answers$dense$mode)
  rounding <- function(at, mode)
    .eqr1_gamma(nrow(Wd) + 1L) * max(as.numeric(crossprod(abs(Wd), abs(at$gradient))) + abs(mode))
  reported <- c(answers$dense$inner_gradient, answers$sparse$inner_gradient)
  if (length(reported) != 2L || !all(is.finite(reported))) return(NaN)
  slack <- sum(reported) + rounding(at_modes$dense$dense, answers$dense$mode) +
    rounding(at_modes$sparse$dense, answers$sparse$mode)
  scale <- 1 + max(max(abs(answers$dense$mode)), max(abs(answers$sparse$mode)))
  observed <- .eq_difference(answers$dense$mode, answers$sparse$mode, "conditional_mode")
  if (!is.finite(observed)) return(NaN)
  observed / (sqrt(d) * slack / scale)
}

.eqr1_stage3_point <- function(map, theta, answers, at) {
  prep <- map$prep
  factors <- .gt_d_covariance_factors(theta[-seq_along(prep$start)], map$setup)
  Wd <- .gt_d_dense_backend(map$groups, factors, prep$n, prep$q)$W
  Ws <- .gt_d_sparse_backend(map$groups, factors, prep$n, prep$q)$W
  u0 <- rep(EQ_STAGE3_LATENT_POINT, ncol(Wd))
  eta_d <- .gt_d_baseline(theta, prep) + matrix(Wd %*% u0, prep$n, prep$q)
  eta_s <- .gt_d_baseline(theta, prep) + matrix(as.numeric(Ws %*% u0), prep$n, prep$q)
  kd <- .gt_d_response_kernel(eta_d, theta, prep)
  ks <- .gt_d_response_kernel(eta_s, theta, prep)
  # Each backend's algebra at each returned mode.
  at_modes <- lapply(c(dense = "dense", sparse = "sparse"), function(m)
    lapply(c(dense = "dense", sparse = "sparse"), function(b) .eqr1_at(b, map, theta, answers[[m]]$mode)))
  common <- function(q) {
    values <- vapply(c("dense", "sparse"), function(m) {
      a <- at_modes[[m]]$dense; b <- at_modes[[m]]$sparse
      if (is.null(a) || is.null(b)) NaN else .eq_difference(a[[q]], b[[q]], q)
    }, numeric(1))
    if (all(is.finite(values))) max(values) else NaN
  }
  usable <- all(vapply(unlist(at_modes, recursive = FALSE), Negate(is.null), logical(1)))
  # A2c: the objectives each evaluator returned, against its own algebra at its
  # own returned mode. The evaluator returns the data term of the conditional
  # objective and adds the penalty at its mode, as is done here.
  returned <- function(b, value, q) {
    own <- at_modes[[b]][[b]]
    if (is.null(own) || length(value) != 1L || !is.finite(value)) NaN else .eq_difference(value, own[[q]], q)
  }
  conditional <- function(b) answers[[b]]$conditional_nll + sum(answers[[b]]$mode^2) / 2
  c(dense_returned_conditional_objective = returned("dense", conditional("dense"), "conditional_objective"),
    sparse_returned_conditional_objective = returned("sparse", conditional("sparse"), "conditional_objective"),
    dense_returned_marginal_negative_log_likelihood =
      returned("dense", answers$dense$nll, "marginal_negative_log_likelihood"),
    sparse_returned_marginal_negative_log_likelihood =
      returned("sparse", answers$sparse$nll, "marginal_negative_log_likelihood"),
    predictor = .eq_difference(eta_d, eta_s, "predictor"),
    conditional_objective = .eq_difference(kd$nll + sum(u0^2) / 2, ks$nll + sum(u0^2) / 2, "conditional_objective"),
    hessian = .eq_difference(.gt_d_dense_hessian(kd$curvature, Wd, prep$n),
                             as.matrix(.gt_d_sparse_hessian(ks$curvature, Ws, prep$n)), "hessian"),
    mode_score_summation_ratio = .eqr1_score_ratio(Wd, Ws, eta_d, eta_s, as.numeric(kd$gradient)),
    conditional_mode_convexity_ratio = if (usable) .eqr1_mode_ratio(answers, Wd, at_modes) else NaN,
    conditional_objective_at_common_mode = common("conditional_objective"),
    log_determinant_at_common_mode = common("log_determinant"),
    marginal_negative_log_likelihood_at_common_mode = common("marginal_negative_log_likelihood"),
    # Information only: the original comparisons of the solved quantities.
    conditional_mode = .eq_difference(answers$dense$mode, answers$sparse$mode, "conditional_mode"),
    log_determinant = .eq_difference(at$dense$logdet, at$sparse$logdet, "log_determinant"),
    marginal_negative_log_likelihood = .eq_difference(answers$dense$nll, answers$sparse$nll,
                                                      "marginal_negative_log_likelihood"))
}

.EQR1_GATING <- c("predictor", "conditional_objective", "hessian", "mode_score_summation_ratio",
                  "conditional_mode_convexity_ratio", "conditional_objective_at_common_mode",
                  "log_determinant_at_common_mode", "marginal_negative_log_likelihood_at_common_mode")
.EQR1_RETURNED <- c("returned_conditional_objective", "returned_marginal_negative_log_likelihood")
.EQR1_INFORMATION <- c("conditional_mode", "log_determinant", "marginal_negative_log_likelihood")

.eqr1_tolerance <- function(tolerances, quantity, dimension) switch(quantity,
  mode_score_summation_ratio = list(value = 1,
    rule = "A1: max_j |dense - sparse| / (2 gamma_n sum_i |W_ij g_i|)"),
  conditional_mode_convexity_ratio = list(value = 1,
    rule = "A2a: frozen mode metric / (sqrt(d) (g_dense + e_dense + g_sparse + e_sparse) / (1 + max|u|))"),
  .eqr_tolerance(tolerances, sub("^returned_", "", sub("_at_common_mode$", "", quantity)), dimension))

# Replaces the merged implementation's stage 3 (AMENDMENT-1.md).
.eqr_stage3 <- function(rec, ctx, map, evaluated, tolerances) {
  values <- lapply(names(evaluated$evaluations), function(label) {
    e <- evaluated$evaluations[[label]]
    tryCatch(.eqr1_stage3_point(map, e$dense$theta, list(dense = e$dense$answer, sparse = e$sparse$answer),
                                list(dense = e$dense$at, sparse = e$sparse$at)),
             error = function(err) { rec$problem(ctx$case, " ", label, ": stage 3 ", conditionMessage(err)); NULL })
  })
  names(values) <- names(evaluated$evaluations)
  verdicts <- character()
  for (q in .EQR1_RETURNED) for (b in c("dense", "sparse")) {
    measured <- vapply(values, function(v) if (is.null(v)) NaN else v[[paste0(b, "_", q)]], numeric(1))
    for (label in names(measured))
      rec$note(case = ctx$case, backend = b, stage = 3L, point = label, quantity = q,
               measured = measured[[label]], bound = NA_real_, status = "gating", message = "")
    verdicts <- c(verdicts, .eqr_judge(rec, ctx, b, 3L, q, if (all(is.finite(measured))) max(measured) else NaN,
                                       .eqr1_tolerance(tolerances, q, ctx$random_dimension)))
  }
  for (q in c(.EQR1_GATING, .EQR1_INFORMATION)) {
    measured <- vapply(values, function(v) if (is.null(v)) NaN else v[[q]], numeric(1))
    gating <- q %in% .EQR1_GATING
    for (label in names(measured))
      rec$note(case = ctx$case, backend = "dense_vs_sparse", stage = 3L, point = label, quantity = q,
               measured = measured[[label]], bound = NA_real_, status = if (gating) "gating" else "information",
               message = "")
    if (gating)
      verdicts <- c(verdicts, .eqr_judge(rec, ctx, "dense_vs_sparse", 3L, q,
                                         if (all(is.finite(measured))) max(measured) else NaN,
                                         .eqr1_tolerance(tolerances, q, ctx$random_dimension)))
  }
  verdicts
}

# ---- entry points --------------------------------------------------------------------
# The merged runner verifies the frozen sources and the fixture pins of the set
# it is told; the amended set carries its own label, so the qualification
# panels, dimensions and kernel ranks are verified here first.
.eqr1_verify_qualification <- function(study) {
  pinned <- .eqr_verify_freeze(study, EQ_CORE, EQ_GEOMETRY, "qualification")
  for (i in seq_len(nrow(EQ_CORE))) {
    row <- EQ_CORE[i, ]
    map <- .eq_parameter_map(row, EQ_GEOMETRY[[row$geometry]])
    pin <- pinned[pinned$case == row$case, ]
    dimension <- as.integer(sum(vapply(map$groups, `[[`, integer(1), "nlevels")) * map$prep$q)
    if (nrow(pin) != 1L || !identical(as.integer(pin$random_dimension), dimension) ||
        !identical(as.integer(pin$kernel_rank), as.integer(.gt_d_kernel_rank(map$groups)$rank)))
      stop("Refusing to run: ", row$case, " differs from its pinned dimension or kernel rank.", call. = FALSE)
  }
  invisible(TRUE)
}

# The reviewed runtime pins (amendment-1-pins.csv, whose own digest the
# launcher holds): every listed file must match its pin before anything runs.
# The tolerance table is parsed from the same bytes that were verified, and is
# the only table the qualification uses.
.eqr1_verify_pins <- function(study) {
  pins <- read.csv(file.path(study, "amendment-1-pins.csv"), stringsAsFactors = FALSE)
  if (!"tolerances.csv" %in% pins$file)
    stop("Refusing to run: amendment-1-pins.csv does not pin tolerances.csv.", call. = FALSE)
  lines <- lapply(stats::setNames(pins$file, pins$file), function(name)
    if (file.exists(file.path(study, name))) readLines(file.path(study, name), warn = FALSE))
  digest <- vapply(lines, function(x) {
    if (is.null(x)) return(NA_character_)
    normalized <- tempfile("eq-pin-")
    on.exit(unlink(normalized), add = TRUE)
    writeBin(charToRaw(paste0(paste(x, collapse = "\n"), "\n")), normalized)
    unname(tools::md5sum(normalized))
  }, character(1))
  moved <- pins$file[is.na(digest) | digest != pins$md5]
  if (length(moved))
    stop("Refusing to run: ", paste(moved, collapse = ", "), " differ from the reviewed pins in ",
         "amendment-1-pins.csv.", call. = FALSE)
  list(pins = pins, tolerances = read.csv(text = lines[["tolerances.csv"]], stringsAsFactors = FALSE))
}

# The qualification reads its tolerances from the verified file. A supplied
# table must be that table exactly; any other is refused, not recorded.
eq1_run_qualification <- function(study, tolerances = NULL) {
  verified <- .eqr1_verify_pins(study)
  if (!is.null(tolerances) && !identical(tolerances, verified$tolerances))
    stop("Refusing to run: the supplied tolerance table is not the reviewed tolerances.csv.", call. = FALSE)
  .eqr1_verify_qualification(study)
  out <- Sys.getenv("EQ_RESULTS_DIR", file.path(study, "results-amendment-1"))
  on.exit(if (file.exists(file.path(out, "environment.txt")))
    cat(paste0("amendment_pins: ", verified$pins$file, " ", verified$pins$md5), sep = "\n",
        file = file.path(out, "environment.txt"), append = TRUE), add = TRUE)
  .eqr_run(study, verified$tolerances, EQ_CORE, EQ_GEOMETRY, "qualification_amendment_1", EQ_TRANSFORM,
           EQ_NEGATIVE, EQ_REFERENCE, out)
}

# The same non-scoring calibration exercise as the merged implementation's,
# judged under the amendment.
eq1_exercise_calibration <- function(study, tolerances, out) {
  tables <- .eqr_exercise_tables()
  .eqr_run(study, tolerances, tables$cases, EQ_CALIBRATION_GEOMETRY, "calibration_exercise_amendment_1",
           tables$transforms, tables$overlays, tables$references, out)
}
