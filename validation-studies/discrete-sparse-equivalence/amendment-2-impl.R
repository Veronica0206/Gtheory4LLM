# Amendment 2 (AMENDMENT-2.md): the stage 4 judgment when both backends reject
# a fit.
#
# Sourced after equivalence-runner-impl.R and amendment-1-impl.R by
# run-equivalence-amendment-2.R. It replaces .eqr_stage4() and nothing else, so
# stage 3 is judged under Amendment 1, and every other stage, the record and the
# stopping rules are the merged implementation's. Every case outside rule B,
# both fits rejected, is handed to the merged stage 4 unchanged. It assigns no
# name that cases.R defines.
#
# Gating quantities added when both fits are rejected:
#   rejection_reason_agreement        B1, identical acceptance failures
#   rejected_fit_layout               B2, identical
#   rejected_fit_objective_relative,
#   rejected_fit_parameter_distance   B2, frozen fitted tolerances
# The merged fitted_layout, fitted_objective_relative and
# fitted_parameter_distance rows are then recorded as not applicable.

if (exists(".eqr2_frozen_stage4", inherits = FALSE))
  stop("amendment-2-impl.R has already been sourced into this environment.", call. = FALSE)
.eqr2_frozen_stage4 <- .eqr_stage4

# Replaces the merged implementation's stage 4 (AMENDMENT-2.md). From the
# latent G/Phi eligibility onwards the body is the merged one, verbatim; the
# amendment's test checks that it has not drifted.
.eqr_stage4 <- function(rec, ctx, row, map, geometry, fits, tolerances) {
  rejected <- vapply(fits, function(f) identical(f$disposition, "rejected") && !is.null(f$fit), logical(1))
  if (length(fits) != 2L || !all(rejected))
    return(.eqr2_frozen_stage4(rec, ctx, row, map, geometry, fits, tolerances))
  for (b in names(fits)) .eqr_disposition_row(rec, ctx, b, 4L, fits[[b]])
  identical_rule <- list(value = 0, rule = "identical")
  verdicts <- .eqr_judge(rec, ctx, "dense_vs_sparse", 4L, "disposition_agreement", 0,
                         list(value = 0, rule = "identical disposition"))
  # B1: the same refusal, read from each fit's own acceptance failures.
  same <- identical(fits$dense$message, fits$sparse$message)
  rec$note(case = ctx$case, backend = "dense_vs_sparse", stage = 4L, point = "fitted",
           quantity = "rejection_reasons", measured = NA_real_, bound = NA_real_, status = "information",
           message = paste0("dense: ", fits$dense$message, "; sparse: ", fits$sparse$message))
  verdicts <- c(verdicts, .eqr_judge(rec, ctx, "dense_vs_sparse", 4L, "rejection_reason_agreement",
                                     as.numeric(!same), list(value = 0, rule = "identical acceptance failures")))
  if (!same) rec$problem(ctx$case, ": both fits rejected, for different reasons (dense ", fits$dense$message,
                         ", sparse ", fits$sparse$message, ")")
  # B2: the rejected fits, compared as the merged rule compares accepted ones.
  layout <- function(f) list(names(f$fit$parameters), lapply(f$fit$covariance_components, dim),
    names(f$fit$covariance_components), f$fit$link_dimensions, f$fit$counts, f$fit$group_counts,
    f$fit$nobs, f$fit$npar)
  verdicts <- c(verdicts,
    .eqr_judge(rec, ctx, "dense_vs_sparse", 4L, "rejected_fit_layout",
               if (same) as.numeric(!identical(layout(fits$dense), layout(fits$sparse))) else NA_real_, identical_rule),
    .eqr_judge(rec, ctx, "dense_vs_sparse", 4L, "rejected_fit_objective_relative",
               if (same) abs(fits$dense$nll - fits$sparse$nll) / max(abs(fits$dense$nll), abs(fits$sparse$nll)) else NA_real_,
               .eqr_tolerance(tolerances, "fitted_objective_relative")),
    .eqr_judge(rec, ctx, "dense_vs_sparse", 4L, "rejected_fit_parameter_distance",
               if (same) .gt_d_fit_distance(fits$dense$parameters, fits$sparse$parameters, map$prep, map$setup) else NA_real_,
               .eqr_tolerance(tolerances, "fitted_parameter_distance")))
  for (q in c("fitted_layout", "fitted_objective_relative", "fitted_parameter_distance")) {
    rec$add(ctx, row_kind = "quantity", backend = "dense_vs_sparse", stage = 4L, quantity = q,
            disposition = "not_applicable")
    rec$note(case = ctx$case, backend = "dense_vs_sparse", stage = 4L, point = "fitted", quantity = q,
             measured = NA_real_, bound = NA_real_, status = "not_applicable",
             message = "both fits rejected; compared as the rejected_fit quantities under Amendment 2")
  }
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

# ---- entry points --------------------------------------------------------------------
# The reviewed runtime pins (amendment-2-pins.csv, whose own digest the
# launcher holds): every listed file must match its pin before anything runs.
# The tolerance table is parsed from the same bytes that were verified, and is
# the only table the qualification uses. Only the launcher authenticates the
# manifest itself, so the launcher is the supported invocation. Called
# directly, this check still catches a changed file, but not a manifest
# re-pinned to match it.
.eqr2_verify_pins <- function(study) {
  pins <- read.csv(file.path(study, "amendment-2-pins.csv"), stringsAsFactors = FALSE)
  if (!"tolerances.csv" %in% pins$file)
    stop("Refusing to run: amendment-2-pins.csv does not pin tolerances.csv.", call. = FALSE)
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
         "amendment-2-pins.csv.", call. = FALSE)
  list(pins = pins, tolerances = read.csv(text = lines[["tolerances.csv"]], stringsAsFactors = FALSE))
}

# The qualification reads its tolerances from the verified file. A supplied
# table must be that table exactly; any other is refused, not recorded.
eq2_run_qualification <- function(study, tolerances = NULL) {
  verified <- .eqr2_verify_pins(study)
  if (!is.null(tolerances) && !identical(tolerances, verified$tolerances))
    stop("Refusing to run: the supplied tolerance table is not the reviewed tolerances.csv.", call. = FALSE)
  .eqr1_verify_qualification(study)
  out <- Sys.getenv("EQ_RESULTS_DIR", file.path(study, "results-amendment-2"))
  # An existing record is refused before the pins are set to be appended, so a
  # refused run leaves it as it was, and the file they are appended to is
  # always this run's own.
  if (dir.exists(out) && length(list.files(out, all.files = TRUE, no.. = TRUE)))
    stop("Refusing to overwrite an existing record in ", out, call. = FALSE)
  on.exit(if (file.exists(file.path(out, "environment.txt")))
    cat(paste0("amendment_2_pins: ", verified$pins$file, " ", verified$pins$md5), sep = "\n",
        file = file.path(out, "environment.txt"), append = TRUE), add = TRUE)
  .eqr_run(study, verified$tolerances, EQ_CORE, EQ_GEOMETRY, "qualification_amendment_2", EQ_TRANSFORM,
           EQ_NEGATIVE, EQ_REFERENCE, out)
}

# The same non-scoring calibration exercise as the merged implementation's,
# judged under Amendments 1 and 2.
eq2_exercise_calibration <- function(study, tolerances, out) {
  tables <- .eqr_exercise_tables()
  .eqr_run(study, tolerances, tables$cases, EQ_CALIBRATION_GEOMETRY, "calibration_exercise_amendment_2",
           tables$transforms, tables$overlays, tables$references, out)
}
