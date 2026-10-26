# Run from the project directory with Rscript tests/test_discrete_equivalence_runner.R.
#
# Regression checks for the equivalence study's judging implementation
# (validation-studies/discrete-sparse-equivalence/equivalence-runner-impl.R).
# Each check reproduces one counterexample from the implementation's review on
# the non-scoring calibration panels, never on a qualification case. A
# deliberately planted result stands in where the counterexample needs one,
# and each check asserts that the judge gives the intended verdict:
#
#   * a required latent G/Phi comparison that cannot be made is a failure, and
#     a parent-scoped nested design is eligible when its panel is complete;
#   * an overlay whose named condition did not occur is not a pass, and a
#     produced condition needs each backend's own non-acceptance;
#   * an unconverged reference records no approximation error;
#   * an R1 event, including a non-finite witness, or a failed stage stops the
#     case, and the later stages are recorded as not run;
#   * a case outside the sparse support envelope stays unsupported when a
#     dense-only check fails, and is never counted as compared;
#   * the repeated-evaluation transform records each of its three quantities on
#     each backend, and a planted repeat discrepancy still fails it.
STUDY <- file.path("validation-studies", "discrete-sparse-equivalence")
source(file.path(STUDY, "cases.R"))
for (f in c("design", "discrete_response", "discrete_dense", "discrete_mode",
            "discrete_sparse", "discrete_sparse_mode", "discrete", "diagnostics_stages"))
  source(file.path("R", paste0(f, ".R")))
source(file.path(STUDY, "equivalence-runner-impl.R"))
tolerances <- read.csv(file.path(STUDY, "tolerances.csv"), stringsAsFactors = FALSE)

fails <- 0L
ok <- function(condition, label) {
  if (!isTRUE(condition)) { fails <<- fails + 1L; cat("FAIL: ", label, "\n", sep = "") }
}
tables <- .eqr_exercise_tables()
case <- function(id) tables$cases[tables$cases$case == id, ]
none <- list(transforms = tables$transforms[0, ], overlays = tables$overlays[0, ], references = tables$references[0, ])
run <- function(cases, transforms = none$transforms, overlays = none$overlays, references = none$references) {
  out <- tempfile("eq-runner-test-")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  capture.output(result <- .eqr_run(STUDY, tolerances, cases, EQ_CALIBRATION_GEOMETRY, "runner_test",
                                    transforms, overlays, references, out))
  result
}
rows <- function(result, ...) {
  r <- result$record
  keep <- rep(TRUE, nrow(r))
  for (k in names(list(...))) keep <- keep & r[[k]] %in% list(...)[[k]]
  r[keep, , drop = FALSE]
}
verdict <- function(result, kind, id) result$summary$verdict[result$summary$kind == kind & result$summary$id == id]
original <- list(public = .eqr_public_fit, fit = .eqr_fit, reference = .eqr_reference_fit,
                 dense_at_mode = .eqr_dense_at_mode, evaluator = .gt_d_sparse_evaluator,
                 reference_change = .eqr_reference_change, solve = .eqr_solve)
restore <- function() {
  .eqr_public_fit <<- original$public; .eqr_fit <<- original$fit; .eqr_reference_fit <<- original$reference
  .eqr_dense_at_mode <<- original$dense_at_mode; .gt_d_sparse_evaluator <<- original$evaluator
}

# ---- a required latent G/Phi comparison ------------------------------------------
baseline <- run(case("K02"))
ok(identical(verdict(baseline, "case", "K02"), "pass") &&
     nrow(rows(baseline, stage = 4L, quantity = "latent_g_phi", disposition = "pass")) == 1L,
   "K02 is eligible for latent G/Phi and passes with the comparison present")
for (status in c("rejected", "unavailable", "refused")) {
  .eqr_public_fit <- function(row, map, gdesign, engine) {
    out <- original$public(row, map, gdesign, engine)
    if (identical(engine, "sparse")) list(status = status, message = "planted") else out
  }
  planted <- run(case("K02"))
  restore()
  ok(identical(verdict(planted, "case", "K02"), "fail") &&
       nrow(rows(planted, stage = 4L, quantity = "latent_g_phi", disposition = "not_measured")) == 1L,
     paste0("a sparse public fit that is ", status, " leaves the required G/Phi comparison unmeasured and fails"))
}
.eqr_public_fit <- function(row, map, gdesign, engine) {
  out <- original$public(row, map, gdesign, engine)
  if (identical(engine, "sparse") && identical(out$status, "accepted")) out$Erho2 <- out$Erho2 + 0.1
  out
}
shifted <- run(case("K02"))
restore()
ok(identical(verdict(shifted, "case", "K02"), "fail") &&
     nrow(rows(shifted, stage = 4L, quantity = "latent_g_phi", disposition = "fail")) == 1L,
   "a sparse G increased by 0.1 fails the latent G/Phi comparison")
# The nested design's `rater` is an alias for (site, nested_rater). With every
# site carrying both rater codes the panel is complete and G/Phi is required;
# with three raters the second site has one code and the panel is incomplete.
nested <- run(case("X07"))
ok(identical(verdict(nested, "case", "X07"), "pass") &&
     nrow(rows(nested, stage = 4L, quantity = "latent_g_phi", disposition = "pass")) == 1L &&
     nrow(rows(nested, stage = 4L, quantity = "public_fit_disposition", disposition = "accepted")) == 2L,
   "a complete nested panel is eligible and its latent G/Phi comparison is made")
incomplete <- run(case("X13"))
reason <- incomplete$detail$message[incomplete$detail$quantity == "latent_g_phi"]
ok(nrow(rows(incomplete, stage = 4L, quantity = "latent_g_phi", disposition = "not_applicable")) == 1L &&
     identical(reason, "the panel is not a complete balanced coded panel"),
   "an incomplete nested panel is ineligible for the incomplete panel, not for its source names")
single <- run(case("K01"))
ok(identical(verdict(single, "case", "K01"), "pass") &&
     nrow(rows(single, stage = 4L, quantity = "latent_g_phi", disposition = "not_applicable")) == 1L,
   "a case without a facet records latent G/Phi as not applicable rather than failing")

# ---- negative overlays ---------------------------------------------------------------
# K06's rater variance starts on its natural zero bound and both fits leave it
# for the interior, with no artificial bound contact: the condition N6 names
# did not occur.
n6 <- run(case("K06"), overlays = data.frame(overlay = "N6", base_case = "K06"))
ok(identical(verdict(n6, "overlay", "N6:K06"), "condition_not_produced") &&
     !nrow(rows(n6, stage = 6L, quantity = "required_nonacceptance")),
   "N6 without artificial bound contact is condition_not_produced, not a pass")
# Two backends that both accept under a zero restart budget have both failed;
# their agreement earns nothing.
.eqr_fit <- function(row, map, backend, control = .eq_control_for(row$covariance)) {
  out <- original$fit(row, map, backend, control)
  if (identical(control$alternative_starts, 0L)) out$disposition <- "accepted"
  out
}
n3 <- run(case("K02"), overlays = data.frame(overlay = "N3", base_case = "K02"))
restore()
ok(identical(verdict(n3, "overlay", "N3:K02"), "fail") &&
     nrow(rows(n3, stage = 6L, quantity = "disposition_agreement", disposition = "pass")) == 1L &&
     nrow(rows(n3, stage = 6L, quantity = "required_nonacceptance", disposition = "fail")) == 2L,
   "N3 accepted on both backends fails each backend's required non-acceptance despite agreement")
n3_real <- run(case("K02"), overlays = data.frame(overlay = "N3", base_case = "K02"))
ok(identical(verdict(n3_real, "overlay", "N3:K02"), "pass") &&
     nrow(rows(n3_real, stage = 6L, quantity = "required_nonacceptance", disposition = "pass")) == 2L,
   "N3 as fitted produces its condition and both backends decline acceptance")

# ---- an unconverged reference ----------------------------------------------------------
.eqr_reference_fit <- function(reference, row, panel) list(variance = 1, loglik = -10, converged = FALSE)
unconverged <- run(case("K01"), references = data.frame(case = "K01", reference = "lme4::glmer"))
restore()
seven <- rows(unconverged, stage = 7L)
ok(nrow(seven) == 4L && all(seven$disposition == "reference_unavailable") && all(is.na(seven$approximation_error)),
   "an unconverged reference records no approximation error")
.eqr_reference_fit <- function(reference, row, panel) list(variance = NaN, loglik = -10, converged = TRUE)
nonfinite <- run(case("K01"), references = data.frame(case = "K01", reference = "lme4::glmer"))
restore()
ok(all(rows(nonfinite, stage = 7L)$disposition == "reference_unavailable"),
   "a converged reference with a non-finite result records no approximation error")

# ---- stage order ----------------------------------------------------------------------
# A non-finite witness is an R1 event, recorded with its value, and nothing after
# stage 1 runs: not the fitted comparison, not the transform, not the overlay.
.eqr_dense_at_mode <- function(...) { out <- original$dense_at_mode(...); out$factor_reconstruction <- NaN; out }
r1 <- run(case("K02"), transforms = data.frame(transform = "T1", base_case = "K02"),
          overlays = data.frame(overlay = "N3", base_case = "K02"))
restore()
ok(identical(verdict(r1, "case", "K02"), "validity_event"),
   "a non-finite witness is a validity event, not an execution error")
ok(nrow(rows(r1, stage = 1L, quantity = "factor_reconstruction", backend = "dense", disposition = "fail")) == 1L &&
     is.nan(rows(r1, stage = 1L, quantity = "factor_reconstruction", backend = "dense")$measured_difference),
   "the non-finite witness is recorded as NaN with a failing stage 1 row")
ok(!nrow(rows(r1, row_kind = "quantity", stage = 2:7)) &&
     identical(verdict(r1, "transform", "T1:K02"), c("not_run", "not_run")) &&
     identical(verdict(r1, "overlay", "N3:K02"), "not_run") &&
     nrow(rows(r1, quantity = "stage_not_run", disposition = "not_run_after_stage_1")) > 0L,
   "after an R1 event no later stage runs and each is recorded as not run")
.gt_d_sparse_evaluator <- function() {
  inner <- original$evaluator()
  function(...) { out <- inner(...); if (is.list(out) && is.numeric(out$nll)) out$nll <- out$nll + 1e-9; out }
}
s3 <- run(case("K02"), transforms = data.frame(transform = "T1", base_case = "K02"))
restore()
ok(identical(verdict(s3, "case", "K02"), "fail") &&
     identical(s3$summary$stopped_at_stage[s3$summary$id == "K02"], 3L) &&
     !nrow(rows(s3, row_kind = "quantity", stage = 4:7)) &&
     !nrow(rows(s3, row_kind = "case_disposition", stage = 4L, quantity = "disposition")) &&
     identical(verdict(s3, "transform", "T1:K02"), c("not_run", "not_run")),
   "a stage 3 failure stops the fitted comparison and the transforms")

# ---- rule R3 ---------------------------------------------------------------------------
.eqr_reference_change <- function(...) c(marginal_nll = 1)
t3 <- run(case("X14"), transforms = data.frame(transform = "T3", base_case = "X14"))
.eqr_reference_change <- original$reference_change
case_row <- t3$summary[t3$summary$kind == "case" & t3$summary$id == "X14", ]
ok(identical(case_row$verdict, "unsupported") && identical(verdict(t3, "transform", "T3:X14"), "fail") &&
     !case_row$verdict %in% c("pass", "fail"),
   "a failed dense-only T3 keeps its case unsupported and out of the compared count, and stays visible itself")

# ---- the repeated-evaluation transform's detail -------------------------------------
t4_quantities <- c("marginal_nll", "conditional_mode", "log_determinant")
t4 <- run(case("K02"), transforms = data.frame(transform = "T4", base_case = "K02"))
t4_detail <- t4$detail[t4$detail$transform %in% "T4", ]
ok(identical(verdict(t4, "transform", "T4:K02"), c("pass", "pass")) && nrow(t4_detail) == 6L &&
     all(vapply(c("dense", "sparse"), function(b)
       identical(sort(t4_detail$quantity[t4_detail$backend == b]), sort(t4_quantities)), logical(1))),
   "T4 records its three quantities on each backend, six detail rows")
# Every second solve, the repeat, returns an objective shifted by one.
solves <- 0L
.eqr_solve <- function(...) {
  out <- original$solve(...)
  solves <<- solves + 1L
  if (!is.null(out) && solves %% 2L == 0L) out$nll <- out$nll + 1
  out
}
t4_planted <- run(case("K02"), transforms = data.frame(transform = "T4", base_case = "K02"))
.eqr_solve <- original$solve
planted_detail <- t4_planted$detail[t4_planted$detail$transform %in% "T4", ]
ok(identical(verdict(t4_planted, "transform", "T4:K02"), c("fail", "fail")) && nrow(planted_detail) == 6L &&
     all(planted_detail$measured[planted_detail$quantity == "marginal_nll"] > 1e-12),
   "a planted repeat discrepancy fails T4 on both backends, with its detail recorded")

if (fails) { cat("FAILURES: ", fails, "\n", sep = ""); quit(status = 1) }
cat("Equivalence runner regressions verified: required G/Phi comparisons including nested designs, ",
    "overlay conditions and per-backend non-acceptance, unconverged references, R1 and failed-stage ",
    "stopping, unsupported cases under rule R3, and the repeated-evaluation detail.\n", sep = "")
