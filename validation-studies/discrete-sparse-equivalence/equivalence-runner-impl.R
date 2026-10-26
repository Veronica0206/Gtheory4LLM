# Judging implementation for the dense/sparse equivalence qualification.
#
# Sourced by the frozen launcher run-equivalence.R, after it has confirmed that
# the calibrated tolerances and the pinned fixtures exist and has sourced
# cases.R. Everything that decides a verdict is inherited, not chosen here: the
# cases, fixtures, fixed points, controls, covariance profiles, injections,
# transforms and reference assignments from cases.R; the metric formulas
# (.eq_difference), the stage 1 witnesses (EQ_VALIDITY) and the stage 3 latent
# point from cases.R; and the tolerance values from tolerances.csv. This file
# redefines none of them, and tests/test_discrete_equivalence_freeze.R asserts
# that it assigns no name cases.R defines. What it adds is execution: which
# backend calls produce each quantity, how each stage is written down, and how
# the rows combine into a verdict.
#
# The record follows results-schema.csv, one row per case x backend x stage x
# quantity. A quantity measured more than once under one such key (stage 3 at
# its three frozen points, the stage 1 witnesses at the same points, a stage 5
# transform over several sub-quantities) is recorded as its largest difference,
# and detail.csv keeps every measurement. Every rule is "at most the tolerance",
# so the verdict on the largest is the verdict on each.
#
# Stages run in the protocol's order, each only on a case that survived every
# earlier stage; a case that stops records which applicable stages did not run
# and why. A required comparison that cannot be made is a failure, never a
# pass, and a negative overlay whose condition did not occur is reported as
# such.
#
# Before review this file is run only through eq_exercise_calibration(), on the
# non-scoring calibration set. eq_run_qualification() is what the launcher calls.

# The launcher sources the R files the freeze named. .gt_fit_discrete() has
# since come to call code in later files (the analytic gradient, the boundary
# escape, the information step, the preflight's resource rule), and latent G
# and Phi need the public interface, so the standalone loader completes the
# set: it sources every file in R/ and compiles src/ as the no-install path
# does, and loads nothing else.
source("load_functions.R")
suppressMessages(library(Matrix))

# ---- integrity of what is about to be measured --------------------------------
# The same normalized text digest and canonical numeric digest as
# freeze-fixtures.R, so the frozen sources and panels are checked against their
# pins before any case runs, not trusted.
.eqr_content_digest <- function(path) {
  normalized <- tempfile("eq-content-")
  on.exit(unlink(normalized), add = TRUE)
  connection <- file(normalized, "wb")
  tryCatch(writeBin(charToRaw(paste0(paste(readLines(path, warn = FALSE), collapse = "\n"), "\n")),
                    connection), finally = base::close(connection))
  unname(tools::md5sum(normalized))
}

.eqr_digest_of <- function(...) {
  path <- tempfile("eq-digest-")
  on.exit(unlink(path), add = TRUE)
  connection <- file(path, "wb")
  tryCatch(for (value in list(...)) {
    if (is.factor(value)) value <- as.integer(value)
    if (is.character(value)) stop("refusing to digest character input")
    real <- is.double(value)
    writeBin(c(if (real) 2L else 1L, length(value)), connection, size = 4L, endian = "big")
    if (real) writeBin(value, connection, size = 8L, endian = "big")
    else writeBin(as.integer(value), connection, size = 4L, endian = "big")
  }, finally = base::close(connection))
  unname(tools::md5sum(path))
}

# The panel digest exactly as freeze-fixtures.R computes it.
.eqr_panel_digest <- function(row, panel) {
  columns <- c(list(panel$item, panel$rater, panel$rep, panel$occasion, panel$site,
                    panel$nested_rater), lapply(.eq_outcomes(row$family), function(nm) panel[[nm]]))
  do.call(.eqr_digest_of, columns)
}

# What each backend is handed: parameter labels, start, bounds and the group
# indices. Labels are digested through their bytes, the numbers canonically.
.eqr_prepared_digest <- function(map) {
  labels <- tempfile("eq-labels-")
  on.exit(unlink(labels), add = TRUE)
  writeBin(charToRaw(paste(names(map$start), collapse = "\n")), labels)
  paste0(unname(tools::md5sum(labels)), ":",
         do.call(.eqr_digest_of, c(list(unname(map$start), unname(map$lower), unname(map$upper)),
                                   lapply(map$groups, `[[`, "index"))))
}

.eqr_verify_freeze <- function(study, cases, geometries, set) {
  recorded <- read.csv(file.path(study, "source-hashes.csv"), stringsAsFactors = FALSE)
  observed <- vapply(file.path(study, recorded$file), .eqr_content_digest, character(1), USE.NAMES = FALSE)
  moved <- recorded$file[observed != recorded$md5]
  if (length(moved))
    stop("Refusing to run: frozen study sources differ from their pins: ",
         paste(moved, collapse = ", "), call. = FALSE)
  pinned <- read.csv(file.path(study, "fixture-digests.csv"), stringsAsFactors = FALSE)
  pinned <- pinned[pinned$set == set, ]
  for (i in seq_len(nrow(cases))) {
    row <- cases[i, ]
    pin <- pinned[pinned$case == row$case, ]
    if (!nrow(pin)) next
    panel <- .eq_panel_for(row$family, row$geometry, geometries[[row$geometry]])
    if (!identical(.eqr_panel_digest(row, panel), pin$panel_digest[[1L]]))
      stop("Refusing to run: the ", row$case, " panel differs from its pinned digest.", call. = FALSE)
  }
  pinned
}

.eqr_environment <- function() {
  git <- function(...) tryCatch(suppressWarnings(system2("git", c(...), stdout = TRUE, stderr = FALSE)),
                                error = function(e) character())
  first <- function(x) if (length(x)) x[[1L]] else NA_character_
  cpu <- tryCatch(
    if (identical(Sys.info()[["sysname"]], "Darwin")) system("sysctl -n machdep.cpu.brand_string", intern = TRUE)
    else sub("^[^:]*:[[:space:]]*", "", grep("^model name", readLines("/proc/cpuinfo"), value = TRUE)[[1L]]),
    error = function(e) NA_character_)
  list(r_version = R.version.string, matrix_version = as.character(packageVersion("Matrix")),
       blas = extSoftVersion()[["BLAS"]], lapack_version = La_version(), lapack = La_library(),
       cpu_model = first(cpu), long_double = capabilities("long.double"),
       threads = Sys.getenv(c("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS",
                              "VECLIB_MAXIMUM_THREADS")),
       source_commit = first(git("rev-parse", "HEAD")),
       r_tree = first(git("rev-parse", "HEAD:R")), src_tree = first(git("rev-parse", "HEAD:src")),
       tracked_changes = length(git("status", "--short", "--untracked-files=no")),
       started_utc = format(Sys.time(), tz = "UTC", usetz = TRUE))
}

# ---- tolerances ----------------------------------------------------------------
# The tolerance table supplies values only. The two dimension-scaled rules are
# the ones the table names: c * random_dimension * eps for the log determinant
# and for the solve-validity bound, whose constant must equal the frozen
# EQ_VALIDITY_BOUND ruler.
.eqr_tolerance <- function(tolerances, quantity, dimension = NA_real_) {
  row <- tolerances[tolerances$quantity == quantity, , drop = FALSE]
  if (nrow(row) != 1L) stop("no frozen tolerance for ", quantity, call. = FALSE)
  value <- row$tolerance[[1L]]
  if (quantity %in% c("log_determinant", "solve_validity")) value <- value * dimension * .Machine$double.eps
  list(value = value, rule = row$rule_form[[1L]])
}

# ---- the record ------------------------------------------------------------------
.eqr_recorder <- function(columns, env, set) {
  state <- new.env(parent = emptyenv())
  state$rows <- list(); state$detail <- list(); state$problems <- character()
  blank <- stats::setNames(rep(list(NA), length(columns)), columns)
  fixed <- list(set = set, r_version = env$r_version, matrix_version = env$matrix_version,
                blas = env$blas, lapack_version = env$lapack_version, cpu_model = env$cpu_model)
  state$add <- function(ctx, ...) {
    row <- blank
    values <- c(fixed, ctx[intersect(names(ctx), columns)], list(...))
    row[names(values)] <- values
    state$rows[[length(state$rows) + 1L]] <- as.data.frame(row, stringsAsFactors = FALSE)
  }
  state$note <- function(...) state$detail[[length(state$detail) + 1L]] <-
    data.frame(..., stringsAsFactors = FALSE)
  state$problem <- function(...) state$problems <- c(state$problems, paste0(...))
  state
}

# One judged quantity. A missing measurement is recorded as unmeasured, never as
# a pass.
.eqr_judge <- function(rec, ctx, backend, stage, quantity, measured, tolerance, ...) {
  verdict <- if (!is.finite(measured)) "not_measured" else if (measured <= tolerance$value) "pass" else "fail"
  rec$add(ctx, row_kind = "quantity", backend = backend, stage = stage, quantity = quantity,
          measured_difference = measured, tolerance_applied = tolerance$value,
          tolerance_rule = tolerance$rule, disposition = verdict, ...)
  verdict
}

# ---- backend-local quantities at a solved mode -----------------------------------
# As in calibrate.R: the stage 1 witnesses and the log determinant, each
# evaluated on ONE backend against algebra (EQ_VALIDITY). The sparse factor is
# reconstructed in the original coordinate order through Matrix::expand2().
.eqr_dense_at_mode <- function(answer, theta, prep, Wd) {
  kernel <- .gt_d_response_kernel(answer$eta, theta, prep)
  H <- .gt_d_dense_hessian(kernel$curvature, Wd, prep$n)
  R <- chol(H)
  probes <- .gt_d_solve_probes(nrow(H))
  probe <- max(vapply(probes, function(b) {
    x <- backsolve(R, forwardsolve(t(R), b)); .gt_d_backward_error(H, b, x) }, numeric(1)))
  eig <- eigen(H, symmetric = TRUE, only.values = TRUE)$values
  logdet <- 2 * sum(log(diag(R)))
  list(logdet = logdet, factor_reconstruction = max(abs(crossprod(R) - H)) / max(abs(H)),
       logdet_witness = abs(logdet - sum(log(eig))), probe_backward_error = probe,
       package_factor_valid = isTRUE(.gt_d_final_factor_check(H, R)$valid), dimension = nrow(H))
}

.eqr_sparse_at_mode <- function(answer, theta, prep, Ws) {
  kernel <- .gt_d_response_kernel(answer$eta, theta, prep)
  H <- .gt_d_sparse_hessian(kernel$curvature, Ws, prep$n)
  fac <- .gt_d_sparse_factor(H)
  probes <- .gt_d_solve_probes(nrow(H))
  probe <- max(vapply(probes, function(b) .gt_d_backward_error(H, b, .gt_d_sparse_solve(fac, b)), numeric(1)))
  Hd <- as.matrix(H)
  Hhat <- as.matrix(Reduce(`%*%`, Matrix::expand2(fac$factor, LDL = FALSE)))
  eig <- eigen(Hd, symmetric = TRUE, only.values = TRUE)$values
  logdet <- .gt_d_sparse_logdet(fac)
  list(logdet = logdet, factor_reconstruction = max(abs(Hhat - Hd)) / max(abs(Hd)),
       logdet_witness = abs(logdet - sum(log(eig))), probe_backward_error = probe,
       package_factor_valid = isTRUE(.gt_d_sparse_final_factor_check(H, fac)$valid), dimension = nrow(H))
}

.eqr_evaluate <- function(backend, theta, map, evaluator) {
  if (identical(backend, "dense")) .gt_d_laplace(theta, map$prep, map$groups, map$setup, map$control, details = TRUE)
  else evaluator(theta, map$prep, map$groups, map$setup, map$control, details = TRUE)
}

.eqr_design_matrix <- function(backend, map, factors) {
  if (identical(backend, "dense")) .gt_d_dense_backend(map$groups, factors, map$prep$n, map$prep$q)$W
  else .gt_d_sparse_backend(map$groups, factors, map$prep$n, map$prep$q)$W
}

# ---- stages 1 to 4 ---------------------------------------------------------------
# PROTOCOL.md runs each stage only on cases that survived the one before, and an
# R1 event stops the case. The fixed points are therefore evaluated once, stage
# 1 is judged on those evaluations alone, and stages 2, 3 and 4 are judged in
# order, each only if every earlier stage passed (.eqr_case).

# Every backend evaluation at the three frozen points, with the backend-local
# quantities at each solved mode. An evaluation that errors is recorded as
# unusable, not raised.
.eqr_points <- function(map, backends) {
  points <- .eq_fixed_points(map$start, map$lower, map$upper, map$zero_coordinates)
  evaluator <- .gt_d_sparse_evaluator()
  evaluations <- lapply(stats::setNames(EQ_FIXED_POINT_LABELS, EQ_FIXED_POINT_LABELS), function(label) {
    theta <- points[[label]]
    lapply(stats::setNames(backends, backends), function(b) {
      answer <- tryCatch(.eqr_evaluate(b, theta, map, evaluator),
                         error = function(e) list(valid = FALSE, reason = conditionMessage(e)))
      at <- if (.gt_d_evaluation_usable(answer)) tryCatch({
        W <- .eqr_design_matrix(b, map, answer$factors)
        if (identical(b, "dense")) .eqr_dense_at_mode(answer, theta, map$prep, W)
        else .eqr_sparse_at_mode(answer, theta, map$prep, W)
      }, error = function(e) list(error = conditionMessage(e)))
      list(theta = theta, answer = answer, at = at)
    })
  })
  list(points = points, evaluations = evaluations)
}

# The stage 1 witnesses of one evaluation. A witness that could not be computed
# is NaN, and NaN never satisfies a bound, so it is an R1 event with its reason
# kept rather than an error.
.eqr_witnesses <- function(entry) {
  at <- entry$at
  numeric_witness <- function(name) {
    value <- if (is.list(at) && is.numeric(at[[name]]) && length(at[[name]]) == 1L) at[[name]] else NaN
    as.numeric(value)
  }
  answer <- entry$answer
  c(solve_backward_error = numeric_witness("probe_backward_error"),
    factor_reconstruction = numeric_witness("factor_reconstruction"),
    log_determinant_witness = numeric_witness("logdet_witness"),
    finite_mode = as.numeric(!(is.list(answer) && length(answer$mode) && all(is.finite(answer$mode)))),
    finite_objective = as.numeric(!.gt_d_evaluation_usable(answer)),
    package_factor_check = as.numeric(!(is.list(at) && isTRUE(at$package_factor_valid))))
}

.EQR_FLAG_WITNESSES <- c("finite_mode", "finite_objective", "package_factor_check")

.eqr_witness_holds <- function(name, value, bound)
  isTRUE(is.finite(value) && if (name %in% .EQR_FLAG_WITNESSES) value == 0 else value <= bound)

.eqr_stage1 <- function(rec, ctx, evaluated, backends, tolerances) {
  bound <- EQ_VALIDITY_BOUND(ctx$random_dimension)
  if (!isTRUE(all.equal(bound, .eqr_tolerance(tolerances, "solve_validity", ctx$random_dimension)$value)))
    stop("the tolerance table's solve-validity constant differs from EQ_VALIDITY_BOUND", call. = FALSE)
  r1 <- character()
  for (b in backends) {
    seen <- list()
    for (label in names(evaluated$evaluations)) {
      entry <- evaluated$evaluations[[label]][[b]]
      w <- .eqr_witnesses(entry)
      failing <- names(w)[!vapply(names(w), function(q) .eqr_witness_holds(q, w[[q]], bound), logical(1))]
      for (q in names(w)) rec$note(case = ctx$case, backend = b, stage = 1L, point = label, quantity = q,
                                   measured = w[[q]], bound = if (q %in% .EQR_FLAG_WITNESSES) 0 else bound,
                                   status = if (q %in% failing) "fail" else "pass", message = "")
      if (length(failing)) {
        r1 <- union(r1, b)
        reason <- c(if (is.list(entry$answer)) entry$answer$reason, if (is.list(entry$at)) entry$at$error)
        rec$problem(ctx$case, " ", label, " ", b, ": backend numerical-validity event (",
                    paste(c(paste("witness", paste(failing, collapse = ", ")), reason), collapse = "; "), ")")
      }
      seen[[label]] <- w
    }
    # The worst value per witness over the points; a non-finite one is kept as NaN.
    worst <- apply(do.call(rbind, seen), 2L, function(v) if (all(is.finite(v))) max(v) else NaN)
    for (q in names(worst)) {
      tol <- if (q %in% .EQR_FLAG_WITNESSES) list(value = 0, rule = "exact") else
        list(value = bound, rule = "32 * random_dimension * eps")
      verdict <- if (.eqr_witness_holds(q, worst[[q]], bound)) "pass" else "fail"
      rec$add(ctx, row_kind = "quantity", backend = b, stage = 1L, quantity = q,
              measured_difference = worst[[q]], tolerance_applied = tol$value,
              tolerance_rule = tol$rule, disposition = verdict)
    }
    if (b %in% r1) rec$add(ctx, row_kind = "validity_event", backend = b, stage = 1L,
                           quantity = "backend_numerical_validity", disposition = "validity_event")
  }
  r1
}

# Stage 2, before anything is fitted: what each backend was handed at the start
# point must be identical -- the random-effect design entry by entry, the source
# factors each evaluation used, and the latent layout of its mode and predictor.
.eqr_stage2 <- function(rec, ctx, map, evaluated) {
  start <- evaluated$evaluations[["start"]]
  identical_rule <- list(value = 0, rule = "identical")
  factors <- .gt_d_covariance_factors(evaluated$points$start[-seq_along(map$prep$start)], map$setup)
  Wd <- .eqr_design_matrix("dense", map, factors)
  Ws <- as.matrix(.eqr_design_matrix("sparse", map, factors))
  fd <- start$dense$answer$factors; fs <- start$sparse$answer$factors
  layout <- function(a) list(length(a$mode), dim(as.matrix(a$eta)))
  c(.eqr_judge(rec, ctx, "dense_vs_sparse", 2L, "random_effect_design",
               if (identical(dim(Wd), dim(Ws))) max(abs(Wd - Ws)) else Inf, identical_rule),
    .eqr_judge(rec, ctx, "dense_vs_sparse", 2L, "covariance_factors",
               if (is.list(fd) && is.list(fs) && identical(lengths(fd), lengths(fs)))
                 max(c(0, unlist(Map(function(a, b) abs(a - b), fd, fs)))) else Inf, identical_rule),
    .eqr_judge(rec, ctx, "dense_vs_sparse", 2L, "latent_layout",
               as.numeric(!identical(layout(start$dense$answer), layout(start$sparse$answer))), identical_rule))
}

.eqr_stage3 <- function(rec, ctx, map, evaluated, tolerances) {
  values <- lapply(names(evaluated$evaluations), function(label) {
    e <- evaluated$evaluations[[label]]
    tryCatch(.eqr_stage3_point(map, e$dense$theta, list(dense = e$dense$answer, sparse = e$sparse$answer),
                               list(dense = e$dense$at, sparse = e$sparse$at)),
             error = function(err) { rec$problem(ctx$case, " ", label, ": stage 3 ", conditionMessage(err)); NULL })
  })
  names(values) <- names(evaluated$evaluations)
  verdicts <- character()
  for (q in c(EQ_STAGE3_AT_COMMON_LATENT, EQ_STAGE3_SOLVED)) {
    measured <- vapply(values, function(v) if (is.null(v)) NaN else v[[q]], numeric(1))
    for (label in names(measured)) rec$note(case = ctx$case, backend = "dense_vs_sparse", stage = 3L, point = label,
                                            quantity = q, measured = measured[[label]], bound = NA_real_)
    verdicts <- c(verdicts, .eqr_judge(rec, ctx, "dense_vs_sparse", 3L, q,
                                       if (all(is.finite(measured))) max(measured) else NaN,
                                       .eqr_tolerance(tolerances, q, ctx$random_dimension)))
  }
  verdicts
}

.eqr_stage3_point <- function(map, theta, answers, at) {
  prep <- map$prep
  fixed_length <- length(prep$start)
  factors <- .gt_d_covariance_factors(theta[-seq_len(fixed_length)], map$setup)
  Wd <- .gt_d_dense_backend(map$groups, factors, prep$n, prep$q)$W
  Ws <- .gt_d_sparse_backend(map$groups, factors, prep$n, prep$q)$W
  baseline <- .gt_d_baseline(theta, prep)
  u0 <- rep(EQ_STAGE3_LATENT_POINT, ncol(Wd))
  eta_d <- baseline + matrix(Wd %*% u0, prep$n, prep$q)
  eta_s <- baseline + matrix(as.numeric(Ws %*% u0), prep$n, prep$q)
  kd <- .gt_d_response_kernel(eta_d, theta, prep)
  ks <- .gt_d_response_kernel(eta_s, theta, prep)
  c(predictor = .eq_difference(eta_d, eta_s, "predictor"),
    conditional_objective = .eq_difference(kd$nll + sum(u0^2) / 2, ks$nll + sum(u0^2) / 2, "conditional_objective"),
    mode_score = .eq_difference(as.vector(crossprod(Wd, kd$gradient)) + u0,
                                as.numeric(Matrix::crossprod(Ws, ks$gradient)) + u0, "mode_score"),
    hessian = .eq_difference(.gt_d_dense_hessian(kd$curvature, Wd, prep$n),
                             as.matrix(.gt_d_sparse_hessian(ks$curvature, Ws, prep$n)), "hessian"),
    conditional_mode = .eq_difference(answers$dense$mode, answers$sparse$mode, "conditional_mode"),
    log_determinant = .eq_difference(at$dense$logdet, at$sparse$logdet, "log_determinant"),
    marginal_negative_log_likelihood = .eq_difference(answers$dense$nll, answers$sparse$nll,
                                                      "marginal_negative_log_likelihood"))
}

# ---- fits ------------------------------------------------------------------------
.eqr_scalar <- function(x, default = NA) if (is.null(x) || !length(x)) default else x[[1L]]

.eqr_fit <- function(row, map, backend, control = .eq_control_for(row$covariance)) {
  design <- EQ_DESIGNS[[row$structure]]
  profile <- EQ_COVARIANCE_PROFILE[[row$covariance]]
  evaluator <- if (identical(backend, "dense")) .gt_d_laplace else .gt_d_sparse_evaluator()
  label <- if (identical(backend, "dense")) "dense_marginal_laplace" else "sparse_marginal_laplace"
  started <- Sys.time()
  fit <- tryCatch(suppressWarnings(.gt_fit_discrete(map$panel, .eq_outcomes(row$family), design,
    .eq_families(row$family, row$link, row$geometry), covariance = profile$covariance,
    control = control, .laplace = evaluator, .engine = label)), error = function(e) e)
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  if (inherits(fit, "error"))
    return(list(disposition = "refused", message = conditionMessage(fit), elapsed = elapsed))
  e <- fit$diagnostics$evaluations
  list(disposition = if (isTRUE(fit$numerically_accepted)) "accepted" else "rejected", fit = fit,
       optimizer_completed = isTRUE(fit$optimizer_completed), elapsed = elapsed,
       attempt_labels = vapply(fit$diagnostics$attempts, function(a) as.character(.eqr_scalar(a$label, "")), character(1)),
       parameter_bounds = as.character(unlist(fit$diagnostics$parameter_bounds)),
       nll = -.eqr_scalar(fit$logLik, NA_real_), parameters = fit$parameters,
       message = paste(sort(unique(unlist(fit$diagnostics$acceptance_failures))), collapse = "|"),
       inner_evaluations = .eqr_scalar(e$count, NA_integer_), invalid_evaluations = .eqr_scalar(e$invalid, NA_integer_),
       budget_terminations = .eqr_scalar(e$valid_at_inner_budget, NA_integer_),
       solve_validity_failures = .eqr_scalar(e$validity_events, NA_integer_))
}

.eqr_disposition_row <- function(rec, ctx, backend, stage, result, quantity = "disposition")
  rec$add(ctx, row_kind = "case_disposition", backend = backend, stage = stage,
          quantity = quantity, disposition = result$disposition,
          inner_evaluations = .eqr_scalar(result$inner_evaluations, NA_integer_),
          invalid_evaluations = .eqr_scalar(result$invalid_evaluations, NA_integer_),
          budget_terminations = .eqr_scalar(result$budget_terminations, NA_integer_),
          solve_validity_failures = .eqr_scalar(result$solve_validity_failures, NA_integer_))

# Whether latent G and Phi are DEFINED for a case is decided from its structure
# before anything is fitted: a binary or ordinal outcome, at least one facet, a
# complete balanced coded panel, and a public design that reproduces the frozen
# sources. For an eligible case the comparison is required, so a public fit
# that is refused, rejected or not computable leaves the quantity unmeasured,
# which fails the stage. An ineligible case is recorded as not applicable, with
# its reason.
#
# The frozen designs name their sources by alias: the nested design's `rater`
# is the pair (site, nested_rater), not a column. The public random terms are
# therefore built from each source's member columns, a several-column source
# being their interaction, which for parent-scoped codes is the child within
# its parent; for the nested design this is the documented
# ~ item + site/nested_rater. Sources are matched by their member sets, not by
# name, and the replication declared is the panel's actual equal count per
# coded cell.
.eqr_latent_eligibility <- function(row, map, geometry) {
  design <- EQ_DESIGNS[[row$structure]]
  no <- function(reason) list(eligible = FALSE, reason = reason)
  if (!row$family %in% c("binary", "ordinal")) return(no("latent G and Phi are compared for binary and ordinal cases"))
  if (!length(design$facets)) return(no("the public interface requires at least one facet"))
  counts <- table(map$panel[c("item", design$facets)])
  if (!length(counts) || any(counts == 0L) || any(counts != counts[[1L]]))
    return(no("the panel is not a complete balanced coded panel"))
  terms <- unname(vapply(design$term_members, function(m) paste(m, collapse = ":"), character(1)))
  gdesign <- tryCatch(gt_design("item", design$facets, random = stats::reformulate(terms),
                                replicates = as.integer(counts[[1L]])), error = function(e) e)
  if (inherits(gdesign, "error")) return(no(paste("the public design cannot express the frozen sources:",
                                                  conditionMessage(gdesign))))
  key <- function(members) sort(vapply(members, function(m) paste(sort(m), collapse = "+"), character(1)))
  if (!identical(unname(key(gdesign$term_members)), unname(key(design$term_members))))
    return(no("the public design does not reproduce the frozen sources"))
  list(eligible = TRUE, design = gdesign, reason = "")
}

.eqr_public_fit <- function(row, map, gdesign, engine) {
  panel <- map$panel
  spec <- .eq_families(row$family, row$link, row$geometry)[[1L]]
  if (identical(row$family, "binary")) panel$y <- factor(as.character(panel$y), levels = c("0", "1"))
  profile <- EQ_COVARIANCE_PROFILE[[row$covariance]]
  discrete <- c(EQ_CONTROL, list(engine = engine))
  if (identical(profile$parameterization, "fixed")) discrete$fixed_covariance <- EQ_C05_FIXED_COVARIANCE
  else if (!identical(profile$parameterization, "auto")) discrete$covariance_parameterization <- profile$parameterization
  fit <- tryCatch(suppressWarnings(gt_fit(panel, "y", design = gdesign,
    family = gt_family(spec$family, spec$link, levels = spec$levels), covariance = profile$covariance,
    control = gt_control(discrete = discrete))), error = function(e) e)
  if (inherits(fit, "error")) return(list(status = "refused", message = conditionMessage(fit)))
  if (!isTRUE(fit$numerically_accepted)) return(list(status = "rejected", message = "public fit not accepted"))
  latent <- tryCatch(as.data.frame(gt_reliability(fit, scale = "latent")), error = function(e) e)
  if (inherits(latent, "error")) return(list(status = "unavailable", message = conditionMessage(latent)))
  if (!all(is.finite(c(latent$Erho2, latent$Phi))))
    return(list(status = "unavailable", message = "latent G or Phi is not finite"))
  list(status = "accepted", Erho2 = latent$Erho2, Phi = latent$Phi, message = "")
}

.eqr_stage4 <- function(rec, ctx, row, map, geometry, fits, tolerances) {
  for (b in names(fits)) .eqr_disposition_row(rec, ctx, b, 4L, fits[[b]])
  identical_rule <- list(value = 0, rule = "identical")
  agree <- identical(fits$dense$disposition, fits$sparse$disposition)
  verdicts <- .eqr_judge(rec, ctx, "dense_vs_sparse", 4L, "disposition_agreement", as.numeric(!agree),
                         list(value = 0, rule = "identical disposition"))
  if (!agree) rec$problem(ctx$case, ": dispositions differ (dense ", fits$dense$disposition,
                          ", sparse ", fits$sparse$disposition, ")")
  both <- agree && identical(fits$dense$disposition, "accepted")
  layout <- function(f) list(names(f$fit$parameters), lapply(f$fit$covariance_components, dim),
    names(f$fit$covariance_components), f$fit$link_dimensions, f$fit$counts, f$fit$group_counts,
    f$fit$nobs, f$fit$npar)
  verdicts <- c(verdicts,
    .eqr_judge(rec, ctx, "dense_vs_sparse", 4L, "fitted_layout",
               if (both) as.numeric(!identical(layout(fits$dense), layout(fits$sparse))) else NA_real_, identical_rule),
    .eqr_judge(rec, ctx, "dense_vs_sparse", 4L, "fitted_objective_relative",
               if (both) abs(fits$dense$nll - fits$sparse$nll) / max(abs(fits$dense$nll), abs(fits$sparse$nll)) else NA_real_,
               .eqr_tolerance(tolerances, "fitted_objective_relative")),
    .eqr_judge(rec, ctx, "dense_vs_sparse", 4L, "fitted_parameter_distance",
               if (both) .gt_d_fit_distance(fits$dense$parameters, fits$sparse$parameters, map$prep, map$setup) else NA_real_,
               .eqr_tolerance(tolerances, "fitted_parameter_distance")))
  eligibility <- .eqr_latent_eligibility(row, map, geometry)
  if (!isTRUE(eligibility$eligible)) {
    rec$add(ctx, row_kind = "quantity", backend = "dense_vs_sparse", stage = 4L, quantity = "latent_g_phi",
            disposition = "not_applicable")
    rec$note(case = ctx$case, backend = "dense_vs_sparse", stage = 4L, point = "fitted", quantity = "latent_g_phi",
             measured = NA_real_, bound = NA_real_, status = "not_applicable", message = eligibility$reason)
    return(verdicts)
  }
  public <- lapply(c(dense = "dense", sparse = "sparse"), function(e) .eqr_public_fit(row, map, eligibility$design, e))
  for (b in names(public)) {
    rec$add(ctx, row_kind = "case_disposition", backend = b, stage = 4L, quantity = "public_fit_disposition",
            disposition = public[[b]]$status)
    rec$note(case = ctx$case, backend = b, stage = 4L, point = "fitted", quantity = "public_fit_disposition",
             measured = NA_real_, bound = NA_real_, status = public[[b]]$status, message = public[[b]]$message)
  }
  statuses <- vapply(public, `[[`, character(1), "status")
  measured <- if (all(statuses == "accepted"))
    max(abs(public$dense$Erho2 - public$sparse$Erho2), abs(public$dense$Phi - public$sparse$Phi)) else NA_real_
  if (!all(statuses == "accepted"))
    rec$problem(ctx$case, ": latent G and Phi are defined for this case but could not be compared (dense ",
                statuses[["dense"]], ", sparse ", statuses[["sparse"]], ")")
  c(verdicts,
    .eqr_judge(rec, ctx, "dense_vs_sparse", 4L, "public_disposition_agreement",
               as.numeric(!identical(statuses[["dense"]], statuses[["sparse"]])), list(value = 0, rule = "identical disposition")),
    .eqr_judge(rec, ctx, "dense_vs_sparse", 4L, "latent_g_phi", measured, .eqr_tolerance(tolerances, "latent_g_phi")))
}

# ---- stage 5: equivariance within one backend ----------------------------------
.eqr_solve <- function(backend, theta, prep, groups, setup, control, factors_override = NULL) {
  answer <- if (identical(backend, "dense"))
    .gt_d_laplace(theta, prep, groups, setup, control, details = TRUE, factors_override = factors_override)
  else .gt_d_sparse_evaluator()(theta, prep, groups, setup, control, details = TRUE, factors_override = factors_override)
  if (!.gt_d_evaluation_usable(answer)) return(NULL)
  W <- if (identical(backend, "dense")) .gt_d_dense_backend(groups, answer$factors, prep$n, prep$q)$W
       else .gt_d_sparse_backend(groups, answer$factors, prep$n, prep$q)$W
  at <- if (identical(backend, "dense")) .eqr_dense_at_mode(answer, theta, prep, W)
        else .eqr_sparse_at_mode(answer, theta, prep, W)
  c(answer, list(logdet = at$logdet))
}

.eqr_offsets <- function(groups) cumsum(c(0L, vapply(groups, `[[`, integer(1), "nlevels")))

# Each transform returns, per backend, a named vector of sub-quantity
# differences under the frozen equivariance metric. The transformation applied
# is the one EQ_TRANSFORM_DETAIL fixes.
.eqr_transform <- function(transform, row, map, theta, backend) {
  detail <- EQ_TRANSFORM_DETAIL[[transform]]
  prep <- map$prep; groups <- map$groups; setup <- map$setup; control <- map$control
  profile <- EQ_COVARIANCE_PROFILE[[row$covariance]]
  base <- .eqr_solve(backend, theta, prep, groups, setup, control)
  if (is.null(base)) return(c(evaluation_unavailable = Inf))
  e <- function(a, b) .eq_difference(a, b, "equivariance")
  n <- prep$n
  switch(detail$rule,
    repeat_identical_evaluation = {
      out <- numeric()
      for (k in seq_len(detail$repeats - 1L)) {
        again <- .eqr_solve(backend, theta, prep, groups, setup, control)
        if (is.null(again)) return(c(evaluation_unavailable = Inf))
        out <- pmax(if (length(out)) out else 0, c(marginal_nll = e(base$nll, again$nll),
          conditional_mode = e(base$mode, again$mode), log_determinant = e(base$logdet, again$logdet)))
      }
      out
    },
    reverse_observation_order = {
      panel_r <- map$panel[rev(seq_len(n)), , drop = FALSE]; rownames(panel_r) <- NULL
      prep_r <- .gt_d_prepare(panel_r, .eq_outcomes(row$family), .eq_families(row$family, row$link, row$geometry))
      design <- EQ_DESIGNS[[row$structure]]
      groups_r <- lapply(design$term_members, function(m) .gt_d_group(panel_r, m))
      setup_r <- .gt_d_covariance_setup(groups_r, prep_r$q, profile$covariance, control, prep_r$dimensions)
      if (!isTRUE(all.equal(unname(c(prep_r$start, setup_r$start)), unname(c(prep$start, setup$start)))))
        stop("row reversal changed the prepared start; the transform is not a pure reordering", call. = FALSE)
      r <- .eqr_solve(backend, theta, prep_r, groups_r, setup_r, control)
      if (is.null(r)) return(c(evaluation_unavailable = Inf))
      off <- .eqr_offsets(groups); off_r <- .eqr_offsets(groups_r)
      mapped <- numeric(length(r$mode))
      for (s in seq_along(groups)) for (a in seq_len(groups[[s]]$nlevels)) {
        i <- which(groups[[s]]$index == a)[[1L]]
        mapped[off[[s]] + a] <- r$mode[off_r[[s]] + groups_r[[s]]$index[[n + 1L - i]]]
      }
      c(marginal_nll = e(base$nll, r$nll), conditional_objective = e(base$conditional_nll, r$conditional_nll),
        log_determinant = e(base$logdet, r$logdet), conditional_mode = e(base$mode, mapped),
        predictor = e(as.numeric(base$eta), as.numeric(as.matrix(r$eta)[rev(seq_len(n)), , drop = FALSE])))
    },
    reverse_source_order = {
      fixed_length <- length(prep$start)
      cov <- theta[-seq_len(fixed_length)]
      if (prep$q != 1L || length(cov) != length(groups))
        stop("source reversal is defined here for one covariance coordinate per source", call. = FALSE)
      groups_2 <- rev(groups)
      setup_2 <- .gt_d_covariance_setup(groups_2, prep$q, profile$covariance, control, prep$dimensions)
      r <- .eqr_solve(backend, c(theta[seq_len(fixed_length)], rev(cov)), prep, groups_2, setup_2, control)
      if (is.null(r)) return(c(evaluation_unavailable = Inf))
      off <- .eqr_offsets(groups)
      perm <- unlist(lapply(rev(seq_along(groups)), function(s) off[[s]] + seq_len(groups[[s]]$nlevels)))
      c(marginal_nll = e(base$nll, r$nll), log_determinant = e(base$logdet, r$logdet),
        conditional_mode = e(base$mode[perm], r$mode), predictor = e(as.numeric(base$eta), as.numeric(r$eta)))
    },
    reverse_level_labels_within_each_source = {
      groups_5 <- lapply(groups, function(g) list(index = g$nlevels + 1L - g$index, nlevels = g$nlevels))
      r <- .eqr_solve(backend, theta, prep, groups_5, setup, control)
      if (is.null(r)) return(c(evaluation_unavailable = Inf))
      off <- .eqr_offsets(groups)
      perm <- unlist(lapply(seq_along(groups), function(s) off[[s]] + rev(seq_len(groups[[s]]$nlevels))))
      c(marginal_nll = e(base$nll, r$nll), log_determinant = e(base$logdet, r$logdet),
        conditional_mode = e(base$mode[perm], r$mode), predictor = e(as.numeric(base$eta), as.numeric(r$eta)))
    },
    categorical_reference = .eqr_reference_change(row, map, theta, backend, base, detail),
    stop("no implementation for transform rule ", detail$rule, call. = FALSE))
}

# A categorical reference change is a linear change of the latent coordinates:
# with reference `from`, the predictor of level k is eta_k (eta_from = 0); with
# reference `to`, it is eta_k - eta_to. The same model is that map applied to
# the intercepts and to every source covariance, Sigma' = A Sigma A'. A diagonal
# Sigma does not stay diagonal under A, so the transformed covariance enters as
# an exact factor of A Sigma A' (factors_override) rather than through the
# diagonal parameterization, which would describe a different model. The
# Laplace objective is invariant under this change of the integration variable,
# so the marginal objective, the log determinant, the conditional objective at
# the mode and the mapped predictor are compared.
.eqr_reference_change <- function(row, map, theta, backend, base, detail) {
  prep <- map$prep; control <- map$control
  spec <- .eq_families(row$family, row$link, row$geometry)
  if (!identical(spec[[1L]]$reference, detail$from)) stop("T3 base reference is not the frozen one", call. = FALSE)
  spec[[1L]]$reference <- detail$to
  prep_t <- .gt_d_prepare(map$panel, .eq_outcomes(row$family), spec)
  levels <- spec[[1L]]$levels
  old <- setdiff(levels, detail$from); new <- setdiff(levels, detail$to)
  # Full predictor over all levels from the old coordinates, then differences.
  E <- matrix(0, length(levels), length(old), dimnames = list(levels, old))
  E[cbind(old, old)] <- 1
  A <- E[new, , drop = FALSE] - matrix(E[detail$to, ], length(new), length(old), byrow = TRUE)
  fixed_length <- length(prep$start)
  beta <- theta[seq_len(fixed_length)]
  beta_t <- as.numeric(A %*% beta)
  names(beta_t) <- names(prep_t$start)
  factors <- .gt_d_covariance_factors(theta[-seq_len(fixed_length)], map$setup)
  factors_t <- lapply(factors, function(L) t(chol(A %*% tcrossprod(L) %*% t(A))))
  setup_t <- .gt_d_covariance_setup(map$groups, prep_t$q, EQ_COVARIANCE_PROFILE[[row$covariance]]$covariance,
                                    control, prep_t$dimensions)
  theta_t <- c(beta_t, setup_t$start)
  r <- .eqr_solve(backend, theta_t, prep_t, map$groups, setup_t, control, factors_override = factors_t)
  if (is.null(r)) return(c(evaluation_unavailable = Inf))
  e <- function(a, b) .eq_difference(a, b, "equivariance")
  c(marginal_nll = e(base$nll, r$nll), conditional_objective = e(base$conditional_nll, r$conditional_nll),
    log_determinant = e(base$logdet, r$logdet),
    predictor = e(as.numeric(as.matrix(base$eta) %*% t(A)), as.numeric(r$eta)))
}

# ---- stage 6: negative and rejection conditions ---------------------------------
.eqr_covariance_value <- function(setup, factor) switch(setup$parameterization,
  variance = factor^2, cholesky = factor, log_cholesky = log(factor),
  stop("no injected value for parameterization ", setup$parameterization, call. = FALSE))

.eqr_evaluation_class <- function(answer) if (.gt_d_evaluation_usable(answer)) "usable" else "unusable"

# The frozen injections are applied unchanged. Whether the condition each one
# names actually occurred is then established from the backends' own records,
# never assumed from the injection:
#   failed_mode_solve, nonfinite_probe  at least one evaluation is unusable;
#   zero_restart_budget                 every fit that ran made no alternative attempt;
#   truncated_optimizer                 at least one optimizer did not complete;
#   artificial_bound_contact            at least one fit reports artificial bound contact;
#   malformed_factor_refusal            the malformed factor violates the solve invariant,
#                                       measured on each backend independently of its check.
# When the condition occurred, each backend must independently not accept: an
# unusable evaluation, a fit that is not accepted, or a refused factor. Agreement
# between the backends is required as well, but agreement alone is never
# credited, since two backends that both accept have both failed. An overlay
# whose condition did not occur is reported as condition_not_produced.
.eqr_overlay_outcome <- function(overlay, row, map) {
  injection <- EQ_NEGATIVE_INJECTION[[overlay]]
  condition <- EQ_NEGATIVE$condition[EQ_NEGATIVE$overlay == overlay]
  fit_both <- function(control) list(dense = .eqr_fit(row, map, "dense", control),
                                     sparse = .eqr_fit(row, map, "sparse", control))
  ran <- function(fits) Filter(function(f) !is.null(f$fit), fits)
  switch(injection$kind,
    fixture = , parameter = {
      theta <- map$start
      if (identical(injection$kind, "fixture")) {
        # A saturating intercept with a large source factor: the first fixed
        # coordinate takes the frozen intercept and every source covariance
        # coordinate the frozen factor in its parameterization.
        theta[[1L]] <- injection$intercept
        theta[-seq_along(map$prep$start)] <- .eqr_covariance_value(map$setup, injection$factor)
      } else theta[[injection$coordinate]] <- injection$value
      evaluator <- .gt_d_sparse_evaluator()
      answers <- lapply(c(dense = "dense", sparse = "sparse"), function(b)
        tryCatch(.eqr_evaluate(b, theta, map, evaluator), error = function(e) list(valid = FALSE, reason = conditionMessage(e))))
      classes <- vapply(answers, .eqr_evaluation_class, character(1))
      list(dispositions = lapply(classes, function(x) list(disposition = x)), accepting = "usable",
           produced = any(classes == "unusable"),
           evidence = paste0(names(classes), " ", classes, " (",
                             vapply(answers, function(a) paste(.eqr_scalar(a$reason, "valid"), collapse = "; "), character(1)),
                             ")", collapse = "; "))
    },
    control = {
      control <- .eq_control_for(row$covariance)
      control[[injection$field]] <- injection$value
      fits <- fit_both(control)
      done <- ran(fits)
      produced <- switch(condition,
        zero_restart_budget = length(done) > 0L &&
          all(vapply(done, function(f) !any(startsWith(f$attempt_labels, "alternative")), logical(1))),
        truncated_optimizer = any(vapply(done, function(f) !isTRUE(f$optimizer_completed), logical(1))),
        stop("no condition rule for ", condition, call. = FALSE))
      list(dispositions = fits, accepting = "accepted", produced = isTRUE(produced),
           evidence = paste0(names(fits), " ", vapply(fits, `[[`, character(1), "disposition"), " (attempts ",
                             vapply(fits, function(f) paste(f$attempt_labels, collapse = ","), character(1)),
                             "; optimizer completed ", vapply(fits, function(f) isTRUE(f$optimizer_completed), logical(1)),
                             ")", collapse = "; "))
    },
    start = {
      control <- .eq_control_for(row$covariance)
      start <- map$start
      coordinates <- which(startsWith(names(start), paste0(injection$source, "::")))
      start[coordinates] <- map$lower[coordinates]
      control$start <- start
      fits <- fit_both(control)
      contact <- vapply(fits, function(f) length(f$parameter_bounds) > 0L, logical(1))
      final <- vapply(fits, function(f) if (is.null(f$parameters)) NA_real_ else
        max(f$parameters[coordinates]), numeric(1))
      list(dispositions = fits, accepting = "accepted", produced = any(contact),
           evidence = paste0(names(fits), " ", vapply(fits, `[[`, character(1), "disposition"),
                             " (bound contact: ", vapply(fits, function(f) paste(c(f$parameter_bounds, "none")[1L], collapse = ","), character(1)),
                             "; injected coordinate ends at ", format(final, digits = 10), ")", collapse = "; "))
    },
    injection = {
      # The factor's diagonal is scaled by the frozen amount. The dense factor is
      # the upper triangular chol(H); the sparse one is the CHOLMOD factor of the
      # matrix that the malformed factor reproduces, so each backend judges the
      # same malformation in its own representation.
      evaluator <- .gt_d_sparse_evaluator()
      outcome <- lapply(c(dense = "dense", sparse = "sparse"), function(b) {
        answer <- .eqr_evaluate(b, map$start, map, evaluator)
        kernel <- .gt_d_response_kernel(answer$eta, map$start, map$prep)
        W <- .eqr_design_matrix(b, map, answer$factors)
        probe <- .gt_d_solve_probes(ncol(W))[[1L]]
        if (identical(b, "dense")) {
          H <- .gt_d_dense_hessian(kernel$curvature, W, map$prep$n)
          R <- chol(H); diag(R) <- diag(R) * injection$scale
          check <- .gt_d_final_factor_check(H, R)
          violation <- .gt_d_backward_error(H, probe, backsolve(R, forwardsolve(t(R), probe)))
        } else {
          H <- .gt_d_sparse_hessian(kernel$curvature, W, map$prep$n)
          parts <- Matrix::expand2(.gt_d_sparse_factor(H)$factor, LDL = FALSE)
          L <- parts[[2L]]; Matrix::diag(L) <- Matrix::diag(L) * injection$scale
          parts[[2L]] <- L; parts[[3L]] <- Matrix::t(L)
          malformed <- .gt_d_sparse_factor(Matrix::forceSymmetric(methods::as(Reduce(`%*%`, parts), "CsparseMatrix")))
          check <- .gt_d_sparse_final_factor_check(H, malformed)
          violation <- .gt_d_backward_error(H, probe, .gt_d_sparse_solve(malformed, probe))
        }
        list(disposition = if (isTRUE(check$valid)) "accepted" else "refused",
             violated = isTRUE(is.finite(violation) && violation > .gt_d_solve_bound(nrow(H))) || !is.finite(violation),
             violation = violation)
      })
      list(dispositions = outcome, accepting = "accepted",
           produced = all(vapply(outcome, `[[`, logical(1), "violated")),
           evidence = paste0(names(outcome), " ", vapply(outcome, `[[`, character(1), "disposition"),
                             " (malformed backward error ", format(vapply(outcome, `[[`, numeric(1), "violation"), digits = 4),
                             ")", collapse = "; "))
    },
    stop("no implementation for injection kind ", injection$kind, call. = FALSE))
}

.eqr_overlay <- function(rec, ctx, overlay, row, map, tolerances) {
  octx <- c(ctx, list(overlay = overlay))
  condition <- EQ_NEGATIVE$condition[EQ_NEGATIVE$overlay == overlay]
  outcome <- .eqr_overlay_outcome(overlay, row, map)
  for (b in names(outcome$dispositions)) .eqr_disposition_row(rec, octx, b, 6L, outcome$dispositions[[b]])
  d <- vapply(outcome$dispositions, `[[`, character(1), "disposition")
  rec$note(case = ctx$case, overlay = overlay, backend = "dense_vs_sparse", stage = 6L, point = "injected",
           quantity = "condition_produced", measured = as.numeric(isTRUE(outcome$produced)), bound = NA_real_,
           status = condition, message = outcome$evidence)
  verdicts <- .eqr_judge(rec, octx, "dense_vs_sparse", 6L, "disposition_agreement",
                         as.numeric(!identical(d[["dense"]], d[["sparse"]])), list(value = 0, rule = "identical disposition"))
  if (!isTRUE(outcome$produced)) return(c(verdicts, "condition_not_produced"))
  for (b in names(d))
    verdicts <- c(verdicts, .eqr_judge(rec, octx, b, 6L, "required_nonacceptance",
                                       as.numeric(identical(d[[b]], outcome$accepting)),
                                       list(value = 0, rule = "not accepted under the produced condition")))
  verdicts
}

# ---- stage 7: independent approximation references -----------------------------
# Recorded, never gating. Each reference fits the identical single-source model
# at higher accuracy; the recorded approximation error is the difference between
# the first-order Laplace fit and the reference in the source variance and in the
# maximized log likelihood.
.eqr_gauss_hermite <- function(nodes) {
  i <- seq_len(nodes - 1L)
  J <- matrix(0, nodes, nodes)
  J[cbind(i, i + 1L)] <- J[cbind(i + 1L, i)] <- sqrt(i / 2)
  e <- eigen(J, symmetric = TRUE)
  list(x = e$values, w = sqrt(pi) * e$vectors[1L, ]^2)
}

# Binary probit with one source, integrated item by item with adaptive
# Gauss-Hermite quadrature centred at each item's conditional mode.
.eqr_adaptive_probit <- function(panel, nodes) {
  gh <- .eqr_gauss_hermite(nodes)
  items <- split(panel$y, panel$item)
  loglik <- function(beta, sigma) sum(vapply(items, function(y) {
    s <- 2 * y - 1
    g <- function(z) sum(pnorm(s * (beta + sigma * z), log.p = TRUE)) + dnorm(z, log = TRUE)
    z <- stats::optimize(function(z) -g(z), c(-12, 12))$minimum
    h <- (g(z + 1e-4) - 2 * g(z) + g(z - 1e-4)) / 1e-8
    scale <- sqrt(2 / max(-h, 1e-8))
    values <- vapply(gh$x, function(x) g(z + scale * x), numeric(1)) + gh$x^2
    m <- max(values)
    log(scale) + m + log(sum(gh$w * exp(values - m)))
  }, numeric(1)))
  start <- c(stats::qnorm(mean(panel$y)), log(0.5))
  opt <- stats::optim(start, function(p) -loglik(p[[1L]], exp(p[[2L]])), method = "BFGS",
                      control = list(reltol = 1e-12, maxit = 1000L))
  list(variance = exp(2 * opt$par[[2L]]), loglik = -opt$value, converged = opt$convergence == 0L)
}

# A reference is usable only when it converged and returned a finite variance
# and log likelihood; glmer must also report optimizer code 0 with no lme4
# convergence message. Anything else is recorded as reference_unavailable with
# its reason, never as an approximation error.
.eqr_reference_fit <- function(reference, row, panel) {
  settings <- EQ_REFERENCE_SETTINGS[[reference]]
  tryCatch(switch(reference,
    "lme4::glmer" = {
      if (!requireNamespace("lme4", quietly = TRUE)) stop("lme4 is not installed")
      d <- data.frame(y = panel$y, item = factor(panel$item))
      m <- suppressWarnings(lme4::glmer(y ~ 1 + (1 | item), data = d, nAGQ = settings$nAGQ,
                                         family = stats::binomial(link = row$link)))
      conv <- m@optinfo$conv
      list(variance = as.numeric(lme4::VarCorr(m)$item[1L, 1L]), loglik = as.numeric(stats::logLik(m)),
           converged = !length(conv$lme4$messages) && identical(as.integer(.eqr_scalar(conv$opt, NA_integer_)), 0L))
    },
    "ordinal::clmm" = {
      if (!requireNamespace("ordinal", quietly = TRUE)) stop("ordinal is not installed")
      d <- data.frame(y = ordered(panel$y, levels = levels(panel$y)), item = factor(panel$item))
      m <- ordinal::clmm(y ~ 1 + (1 | item), data = d, link = row$link, nAGQ = settings$nAGQ)
      list(variance = as.numeric(ordinal::VarCorr(m)$item[1L, 1L]), loglik = as.numeric(stats::logLik(m)),
           converged = identical(as.integer(.eqr_scalar(m$optRes$convergence, NA_integer_)), 0L))
    },
    "dense_adaptive_integration" = .eqr_adaptive_probit(panel, settings$nodes),
    stop("no implementation for reference ", reference)), error = function(e) list(error = conditionMessage(e)))
}

.eqr_reference_usable <- function(ref) {
  if (!is.null(ref$error)) return(ref$error)
  if (!isTRUE(ref$converged)) return("the reference did not converge")
  scalar <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
  if (!scalar(ref$variance) || !scalar(ref$loglik)) return("the reference returned a non-finite or non-scalar result")
  ""
}

.eqr_stage7 <- function(rec, ctx, reference, row, map, fits) {
  ref <- .eqr_reference_fit(reference, row, map$panel)
  problem <- .eqr_reference_usable(ref)
  for (b in names(fits)) {
    f <- fits[[b]]
    why <- if (nzchar(problem)) problem else
      if (!identical(f$disposition, "accepted")) paste("the", b, "fit was not accepted") else ""
    variance <- if (nzchar(why)) NA_real_ else abs(as.numeric(f$fit$covariance_components[[1L]][1L, 1L]) - ref$variance)
    loglik <- if (nzchar(why)) NA_real_ else abs(-f$nll - ref$loglik)
    for (q in c("source_variance", "maximized_log_likelihood"))
      rec$add(ctx, row_kind = "quantity", backend = b, stage = 7L, quantity = q,
              disposition = if (nzchar(why)) "reference_unavailable" else "recorded",
              approximation_reference = reference,
              approximation_error = if (q == "source_variance") variance else loglik)
    rec$note(case = ctx$case, backend = b, stage = 7L, point = "fitted", quantity = "reference",
             measured = NA_real_, bound = NA_real_, status = if (nzchar(why)) "reference_unavailable" else "recorded",
             message = if (nzchar(why)) why else sprintf("reference variance %.10g, log likelihood %.10g",
                                                          ref$variance, ref$loglik))
  }
}

# ---- one case --------------------------------------------------------------------
.eqr_failed <- function(verdicts) any(verdicts %in% c("fail", "not_measured"))

.eqr_case <- function(rec, row, geometries, tolerances, pinned, transforms, overlays, references) {
  geometry <- geometries[[row$geometry]]
  supported <- identical(row$sparse_supported, "yes")
  backends <- if (supported) c("dense", "sparse") else "dense"
  map <- .eq_parameter_map(row, geometry)
  dimension <- as.integer(sum(vapply(map$groups, `[[`, integer(1), "nlevels")) * map$prep$q)
  pin <- pinned[pinned$case == row$case, ]
  ctx <- list(case = row$case, family = row$family, link = row$link, structure = row$structure,
              covariance = row$covariance, geometry = row$geometry, sparse_supported = row$sparse_supported,
              random_dimension = dimension, kernel_rank = .gt_d_kernel_rank(map$groups)$rank,
              panel_digest = .eqr_panel_digest(row, map$panel), prepared_digest = .eqr_prepared_digest(map))
  if (nrow(pin) && (!identical(as.integer(pin$random_dimension), dimension) ||
                    !identical(as.integer(pin$kernel_rank), as.integer(ctx$kernel_rank))))
    stop(row$case, ": random dimension or kernel rank differs from the pinned fixture", call. = FALSE)
  my_transforms <- transforms$transform[transforms$base_case == row$case]
  my_overlays <- overlays$overlay[overlays$base_case == row$case]
  my_references <- references$reference[references$case == row$case]
  extra <- list()
  stopped <- NA_integer_; reason <- ""
  halt <- function(stage, why) { stopped <<- stage; reason <<- why; rec$problem(row$case, ": stopped at stage ", stage, " (", why, ")") }
  live <- function() is.na(stopped)

  evaluated <- .eqr_points(map, backends)
  r1 <- .eqr_stage1(rec, ctx, evaluated, backends, tolerances)
  if (length(r1)) halt(1L, paste("backend numerical-validity event on", paste(r1, collapse = " and ")))
  if (live() && supported && .eqr_failed(.eqr_stage2(rec, ctx, map, evaluated)))
    halt(2L, "the prepared design differs between backends")
  if (live() && supported && .eqr_failed(.eqr_stage3(rec, ctx, map, evaluated, tolerances)))
    halt(3L, "a fixed-parameter quantity exceeds its tolerance or was not measured")
  fits <- NULL
  if (live()) {
    fits <- lapply(stats::setNames(backends, backends), function(b) .eqr_fit(row, map, b))
    if (supported) {
      if (.eqr_failed(.eqr_stage4(rec, ctx, row, map, geometry, fits, tolerances)))
        halt(4L, "a fitted comparison failed or was not measured")
    } else {
      .eqr_disposition_row(rec, ctx, "dense", 4L, fits$dense)
      rec$add(ctx, row_kind = "case_disposition", backend = "sparse", stage = 4L, quantity = "disposition",
              disposition = "unsupported")
    }
  }
  for (t in my_transforms) {
    scope <- EQ_TRANSFORM_SCOPE[[t]]
    if (identical(scope, "dense_only") && supported)
      stop("a dense-only transform on a sparse-supported base contradicts the frozen scope", call. = FALSE)
    for (b in if (identical(scope, "dense_only")) "dense" else backends) {
      if (!live()) { extra[[length(extra) + 1L]] <- list(case = row$case, transform = t, backend = b, verdict = "not_run"); next }
      tctx <- c(ctx, list(transform = t))
      values <- tryCatch(.eqr_transform(t, row, map, evaluated$points$start, b),
                         error = function(e) { rec$problem(row$case, " ", t, " ", b, ": ", conditionMessage(e)); c(error = NaN) })
      for (q in names(values)) rec$note(case = row$case, transform = t, backend = b, stage = 5L, point = "start",
                                        quantity = q, measured = values[[q]], bound = NA_real_)
      v <- .eqr_judge(rec, tctx, b, 5L, "equivariance", if (all(is.finite(values))) max(values) else NaN,
                      .eqr_tolerance(tolerances, "equivariance"))
      extra[[length(extra) + 1L]] <- list(case = row$case, transform = t, backend = b, verdict = v)
    }
    if (identical(scope, "dense_only") && live())
      rec$add(c(ctx, list(transform = t)), row_kind = "case_disposition", backend = "sparse", stage = 5L,
              quantity = "equivariance", disposition = "unsupported")
  }
  if (live() && any(vapply(extra, function(x) x$verdict %in% c("fail", "not_measured"), logical(1))))
    halt(5L, "an equivariance transform failed")
  for (o in my_overlays) {
    if (!live()) { extra[[length(extra) + 1L]] <- list(case = row$case, overlay = o, verdict = "not_run"); next }
    v <- tryCatch(.eqr_overlay(rec, ctx, o, row, map, tolerances),
                  error = function(e) { rec$problem(row$case, " ", o, ": ", conditionMessage(e)); "not_measured" })
    verdict <- if (.eqr_failed(v)) "fail" else if ("condition_not_produced" %in% v) "condition_not_produced" else "pass"
    extra[[length(extra) + 1L]] <- list(case = row$case, overlay = o, verdict = verdict)
    if (identical(verdict, "fail")) halt(6L, paste("overlay", o, "failed"))
  }
  for (r in my_references) if (live()) .eqr_stage7(rec, ctx, r, row, map, fits)

  # Every stage that applied to this case but did not run is recorded with the
  # stage that stopped it.
  if (!live()) {
    applicable <- c(if (supported) 2:4 else 4L, if (length(my_transforms)) 5L,
                    if (length(my_overlays)) 6L, if (length(my_references)) 7L)
    for (s in applicable[applicable > stopped])
      for (b in backends) rec$add(ctx, row_kind = "case_disposition", backend = b, stage = s,
                                  quantity = "stage_not_run", disposition = paste0("not_run_after_stage_", stopped))
  }
  # Rule R3: a case outside the sparse support envelope is unsupported whatever
  # happens in its dense-only checks; a failed dense-only transform stays
  # visible as its own entry and never makes the case a compared one.
  verdict <- if (length(r1)) "validity_event" else if (!supported) "unsupported" else if (!live()) "fail" else "pass"
  list(outcome = list(case = row$case, verdict = verdict, stopped = stopped, reason = reason), extra = extra)
}

# ---- the run -----------------------------------------------------------------------
.eqr_run <- function(study, tolerances, cases, geometries, set, transforms, overlays, references, out) {
  if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE)))
    stop("Refusing to overwrite an existing record in ", out, call. = FALSE)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  pinned <- .eqr_verify_freeze(study, cases, geometries,
                               if (identical(set, "qualification")) "qualification" else "calibration")
  env <- .eqr_environment()
  columns <- strsplit(readLines(file.path(study, "results-schema.csv"), warn = FALSE)[[1L]], ",", fixed = TRUE)[[1L]]
  rec <- .eqr_recorder(columns, env, set)
  writeLines(c(paste0(names(env), ": ", vapply(env, function(v) paste(v, collapse = " "), "")),
               paste0("tolerances: ", .eqr_content_digest(file.path(study, "tolerances.csv")))),
             file.path(out, "environment.txt"))
  outcomes <- list(); extra <- list()
  for (i in seq_len(nrow(cases))) {
    row <- cases[i, ]
    cat(format(Sys.time(), "%H:%M:%S"), row$case, row$family, row$link, row$structure, row$covariance,
        row$geometry, "\n"); flush.console()
    result <- tryCatch(.eqr_case(rec, row, geometries, tolerances, pinned, transforms, overlays, references),
                       error = function(e) {
                         rec$problem(row$case, ": ", conditionMessage(e))
                         list(outcome = list(case = row$case, verdict = "error", stopped = NA_integer_,
                                             reason = conditionMessage(e)), extra = list())
                       })
    outcomes[[length(outcomes) + 1L]] <- result$outcome
    extra <- c(extra, result$extra)
  }
  record <- do.call(rbind, rec$rows)[columns]
  write.csv(record, file.path(out, "results.csv"), row.names = FALSE, na = "NA")
  detail <- do.call(rbind, lapply(rec$detail, function(d) {
    for (k in c("overlay", "transform", "status", "message")) if (is.null(d[[k]])) d[[k]] <- NA_character_
    d[c("case", "overlay", "transform", "backend", "stage", "point", "quantity", "measured", "bound", "status", "message")]
  }))
  write.csv(detail, file.path(out, "detail.csv"), row.names = FALSE, na = "NA")
  summary <- rbind(
    data.frame(kind = "case", id = vapply(outcomes, `[[`, character(1), "case"), backend = "dense_vs_sparse",
               verdict = vapply(outcomes, `[[`, character(1), "verdict"),
               stopped_at_stage = vapply(outcomes, function(x) as.integer(x$stopped), integer(1)),
               reason = vapply(outcomes, function(x) as.character(x$reason), character(1)), stringsAsFactors = FALSE),
    if (length(extra)) do.call(rbind, lapply(extra, function(x) data.frame(
      kind = if (!is.null(x$overlay)) "overlay" else "transform",
      id = paste0(if (!is.null(x$overlay)) x$overlay else x$transform, ":", x$case),
      backend = if (is.null(x$backend)) "dense_vs_sparse" else x$backend, verdict = x$verdict,
      stopped_at_stage = NA_integer_, reason = "", stringsAsFactors = FALSE))))
  write.csv(summary, file.path(out, "summary.csv"), row.names = FALSE, na = "NA")
  writeLines(if (length(rec$problems)) rec$problems else "none", file.path(out, "problems.txt"))
  writeLines(capture.output(sessionInfo()), file.path(out, "session-info.txt"))
  failed <- summary$verdict %in% c("fail", "error", "not_measured")
  cat("\n==== summary ====\n"); print(summary[c("kind", "id", "backend", "verdict", "stopped_at_stage")], row.names = FALSE)
  cat("\nscored cases compared:", sum(summary$kind == "case" & summary$verdict %in% c("pass", "fail")),
      "| passed:", sum(summary$kind == "case" & summary$verdict == "pass"),
      "| validity events:", sum(summary$verdict == "validity_event"),
      "| unsupported:", sum(summary$verdict == "unsupported"),
      "| overlays without their condition:", sum(summary$verdict == "condition_not_produced"),
      "| not run:", sum(summary$verdict == "not_run"),
      "| failures or errors:", sum(failed), "\n")
  invisible(list(record = record, summary = summary, detail = detail, problems = rec$problems, out = out))
}

# Called by the launcher. The record is written to results/ in the study
# directory unless EQ_RESULTS_DIR names another new directory.
eq_run_qualification <- function(study, tolerances) {
  out <- Sys.getenv("EQ_RESULTS_DIR", file.path(study, "results"))
  .eqr_run(study, tolerances, EQ_CORE, EQ_GEOMETRY, "qualification", EQ_TRANSFORM, EQ_NEGATIVE,
           EQ_REFERENCE, out)
}

# ---- exercising the implementation without a scored case ------------------------
# Runs every stage on the non-scoring calibration panels, never on a
# qualification case: the stage 1-5 machinery on K01-K06; each overlay and
# transform on a calibration case of the same family and structure where one
# exists; and the references on K01. Four additional panels built from the
# calibration geometry cover what the calibration set lacks: an ordinal
# single-source panel for clmm, a categorical panel for the reference change,
# and two parent-scoped nested panels, complete (two sites with two raters
# each, so latent G and Phi are defined) and incomplete (three raters, so the
# second site has one).
# Its output is set "calibration_exercise", produces no qualification verdict
# and is not committed. tests/test_discrete_equivalence_runner.R uses the same
# tables.
.eqr_exercise_tables <- function() {
  cases <- EQ_CALIBRATION
  cases$sparse_supported <- "yes"
  cases <- rbind(cases,
    data.frame(case = "X09", family = "ordinal", link = "logit", structure = "single",
               covariance = "diagonal", geometry = "cal_small", sparse_supported = "yes"),
    data.frame(case = "X14", family = "categorical", link = "softmax", structure = "crossed2",
               covariance = "diagonal", geometry = "cal_small", sparse_supported = "no_categorical"),
    data.frame(case = "X07", family = "binary", link = "logit", structure = "nested",
               covariance = "diagonal", geometry = "cal_medium", sparse_supported = "yes"),
    data.frame(case = "X13", family = "ordinal", link = "probit", structure = "nested",
               covariance = "log_cholesky", geometry = "cal_small", sparse_supported = "yes"))
  list(cases = cases,
       transforms = data.frame(transform = c("T1", "T2", "T3", "T4", "T5"),
                               base_case = c("K02", "K02", "X14", "K03", "X13"), stringsAsFactors = FALSE),
       overlays = data.frame(overlay = c("N1", "N2", "N3", "N4", "N5", "N6"),
                             base_case = c("K01", "K02", "K02", "K04", "K01", "K06"), stringsAsFactors = FALSE),
       references = data.frame(case = c("K01", "K01", "X09"),
                               reference = c("lme4::glmer", "dense_adaptive_integration", "ordinal::clmm"),
                               stringsAsFactors = FALSE))
}

eq_exercise_calibration <- function(study, tolerances, out) {
  tables <- .eqr_exercise_tables()
  .eqr_run(study, tolerances, tables$cases, EQ_CALIBRATION_GEOMETRY, "calibration_exercise", tables$transforms,
           tables$overlays, tables$references, out)
}
