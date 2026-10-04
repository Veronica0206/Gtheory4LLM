# Installed-package checks for flat exports and supplied-grid target screening.
library(Gtheory4LLM)

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
near <- function(a, b, label)
  expect(isTRUE(all.equal(unname(a), unname(b), check.attributes = FALSE)), label)
expect_error <- function(expr, pattern, label) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  expect(inherits(error, "error") && grepl(pattern, conditionMessage(error)), label)
}

# Both facet names collide with result fields; an actual outcome is named
# 'composite', so only the kind/outcome pair identifies a coefficient series.
set.seed(123)
panel <- expand.grid(item = 1:20, outcome = 1:4, Phi = 1:3)
panel$composite <- rnorm(20)[panel$item] + rnorm(4, sd = .5)[panel$outcome] +
  rnorm(3, sd = .4)[panel$Phi] + rnorm(nrow(panel), sd = .7)
panel[["quality score"]] <- rnorm(20)[panel$item] + rnorm(4, sd = .4)[panel$outcome] +
  rnorm(3, sd = .6)[panel$Phi] + rnorm(nrow(panel), sd = .8)
design <- gt_design("item", c("outcome", "Phi"), random = ~ item + outcome + Phi)
fit <- gt_fit(panel, c("composite", "quality score"), design,
              covariance = "diagonal", residual = "diagonal")
expect(isTRUE(fit$numerically_accepted), "the reporting fixture is an accepted fit")
score <- gt_score(c(composite = .4, "quality score" = .6))
reliability <- gt_reliability(fit, score = score)
table <- as.data.frame(reliability)
expect(identical(class(table), "data.frame") && nrow(table) == 3L,
       "reliability exports one ordinary data-frame row per outcome and composite")
expect(identical(table$kind, c("outcome", "outcome", "composite")),
       "a real outcome named composite remains distinct from the weighted composite")
expect(!anyDuplicated(names(table)) && all(vapply(table, is.atomic, logical(1))),
       "exports contain unique column names and no list columns")
expect(identical(attr(table, "allocation_columns"),
                 c(allocation_outcome = "outcome", allocation_Phi = "Phi")),
       "allocation columns retain an exact facet-name mapping")
expect(all(table$allocation_outcome == 4L) && all(table$allocation_Phi == 3L),
       "facets cannot overwrite the outcome or Phi coefficient columns")
near(table$Phi[table$kind == "outcome"], reliability$per_trait$Phi,
     "flat exports preserve the original coefficient values")
expect(all(table$scale == "observed") && all(table$measurements_per_object == 12L) &&
         !any(table$extrapolated), "the reliability table carries scale and allocation context")
expect(all(table$uncertainty_available == reliability$uncertainty$available) &&
         all(table$interval_level == .95), "the uncertainty record and confidence level are retained")
expect(identical(table$Phi_interval_available,
                 is.finite(table$Phi_lower) & is.finite(table$Phi_upper)),
       "per-coefficient interval availability describes the actual row bounds")
expect(all(is.na(table$composite_weights[table$kind == "outcome"])) &&
         grepl('"quality score" = ', table$composite_weights[table$kind == "composite"], fixed = TRUE) &&
         identical(attr(table, "score"), score),
       "composite rows carry readable weights and preserve their exact structured score")
named <- as.data.frame(reliability, row.names = c("a", "b", "c"), optional = TRUE)
expect(identical(rownames(named), c("a", "b", "c")), "explicit row names are honored")

# CSV needs no package-specific decoder; attributes carry extra R context.
csv <- tempfile(fileext = ".csv")
utils::write.csv(table, csv, row.names = FALSE)
roundtrip <- utils::read.csv(csv, check.names = FALSE)
unlink(csv)
expect(identical(names(roundtrip), names(table)), "CSV preserves export column names")
near(roundtrip$Phi, table$Phi, "CSV preserves numerical coefficient values")

# Exact-name preservation also covers facets that make.names would collapse.
label_fixture <- reliability
names(label_fixture$design) <- c("a b", "a.b")
label_table <- as.data.frame(label_fixture)
expect(all(c("allocation_a b", "allocation_a.b") %in% names(label_table)) &&
         identical(unname(attr(label_table, "allocation_columns")), c("a b", "a.b")),
       "nonsyntactic allocation names are preserved without name-repair collisions")

conditional <- reliability
conditional$uncertainty$restricted_to_interior <- TRUE
conditional$uncertainty$fixed_components <- "Phi"
conditional$uncertainty$fixed_component_kinds <- c(Phi = "singular_nonzero")
conditional_table <- as.data.frame(conditional)
expect(all(conditional_table$uncertainty_conditional) &&
         all(grepl("singular but nonzero", conditional_table$uncertainty_conditioning)),
       "flat reports distinguish conditioning at nonzero covariance from fixing at zero")
fixed_table <- as.data.frame(gt_reliability(fit, fixed = "Phi"))
expect(identical(attr(fixed_table, "fixed_facets"), "Phi"), "fixed-facet context survives export")
expect(all(fixed_table$fixed_facets == '"Phi"'), "fixed-facet declarations survive CSV as quoted labels")

grid <- data.frame(outcome = c(2L, 3L, 6L, 3L), Phi = c(3L, 2L, 3L, 2L))
study <- gt_dstudy(fit, grid, score = score)
shuffled <- study
shuffled$results <- study$results[rev(seq_len(nrow(study$results))), , drop = FALSE]
flat <- as.data.frame(shuffled)
expect(identical(flat$design_id, shuffled$results$design_id), "export preserves result-row order")
for (i in seq_len(nrow(grid))) {
  rows <- flat$design_id == i
  expect(sum(rows) == 3L, "each allocation joins to all outcomes and the composite")
  expect(all(flat$allocation_outcome[rows] == grid$outcome[i]) &&
           all(flat$allocation_Phi[rows] == grid$Phi[i]),
         "reordered coefficient rows join to the exact recorded design ID")
  expect(all(flat$measurements_per_object[rows] == study$measurements_per_object[i]) &&
           all(flat$extrapolated[rows] == study$extrapolated[i]),
         "measurement counts and extrapolation flags use the same design-ID join")
}
bad_id <- study
bad_id$results$design_id[1L] <- nrow(grid) + 1L
expect_error(as.data.frame(bad_id), "design_id", "an unmatched design ID is refused")

expect_error(gt_dstudy_target(study, .8), "Specify outcome explicitly",
             "a multivariate target never chooses an outcome silently")
screen <- gt_dstudy_target(shuffled, 0, outcome = "composite")
expect(nrow(screen) == nrow(grid) && all(screen$kind == "outcome"),
       "screening keeps every supplied candidate for the selected real outcome")
expect(all(screen$meets_target) && sum(screen$fewest_measurements) == 3L &&
         all(screen$fewest_measurements == (screen$measurements_per_object == 6L)),
       "all minimum-measurement ties survive, including duplicate supplied candidates")
expect(identical(attr(screen, "target_context")$scope, "supplied_candidates_only") &&
         identical(attr(screen, "allocation_columns"), attr(flat, "allocation_columns")),
       "the target screen retains its scope and allocation mapping")
composite_screen <- gt_dstudy_target(study, 0, kind = "composite", coefficient = "Phi")
expect(all(composite_screen$kind == "composite") &&
         all(composite_screen$coefficient == "Phi"), "composite screening is explicitly selected")
none <- gt_dstudy_target(study, 1, outcome = "quality score")
expect(!any(none$meets_target) && !any(none$fewest_measurements),
       "a target met by no candidate keeps all rows with FALSE flags")
unknown <- study
unknown_row <- which(unknown$results$kind == "outcome" &
                       unknown$results$outcome == "composite")[1L]
unknown$results$Erho2[unknown_row] <- NA_real_
unknown_screen <- gt_dstudy_target(unknown, 0, outcome = "composite")
expect(is.na(unknown_screen$meets_target[1L]) && is.na(unknown_screen$fewest_measurements[1L]),
       "an unavailable coefficient remains unknown in both screening flags")
expect(!unknown_screen$Erho2_interval_available[1L],
       "an unavailable point cannot advertise an available coefficient interval")
large_grid <- data.frame(outcome = c(1e9, 1e9 - 1, 1e200),
                         Phi = c(1e9, 1e9 + 1, 1e200))
large <- gt_dstudy_target(gt_dstudy(fit, large_grid), 0, outcome = "composite")
expect(all(large$meets_target) && !any(large$measurement_count_exact) &&
         all(is.na(large$fewest_measurements)),
       "rounded or overflowing large products cannot create false minimum-count ties")
mixed <- gt_dstudy_target(gt_dstudy(fit, rbind(large_grid, grid[1L, ])),
                          0, outcome = "composite")
expect(identical(mixed$fewest_measurements, c(FALSE, FALSE, FALSE, TRUE)) &&
         identical(mixed$measurement_count_exact, c(FALSE, FALSE, FALSE, TRUE)),
       "an exactly represented smaller eligible allocation beats every inexact large total")
for (bad in list(NULL, NA_real_, Inf, -.1, 1.1, c(.7, .8), "0.8"))
  expect_error(gt_dstudy_target(study, bad, outcome = "composite"), "target must",
               "invalid targets explain the accepted range")
expect_error(gt_dstudy_target(study, .8, outcome = "missing"), "No results match",
             "unknown outcomes are refused")
expect_error(gt_dstudy_target(study, .8, outcome = "composite", kind = NULL), "kind must",
             "target screening requires one result kind")
expect_error(gt_dstudy_target(study, .8, outcome = "composite", coefficient = "lower"),
             "coefficient must", "target screening does not silently screen interval bounds")

# A small accepted discrete fit supplies latent point projections, never CIs.
binary_panel <- expand.grid(item = 1:8, rater = 1:3)
binary_panel$b <- rep(c(0L, 1L, 1L), 8L)
binary_design <- gt_design("item", "rater", random = ~ item + rater, full_cell = FALSE)
binary <- gt_fit(binary_panel, "b", binary_design, gt_family("binary"),
  control = gt_control(discrete = list(fixed_covariance =
    list(item = matrix(0), rater = matrix(0)))))
latent <- gt_dstudy(binary, data.frame(rater = c(2L, 4L)), scale = "latent")
latent_table <- as.data.frame(latent)
expect(all(latent_table$scale == "latent") && !any(latent_table$uncertainty_available) &&
         all(is.na(latent_table$Erho2_lower)) &&
         !any(latent_table$Erho2_interval_available) &&
         all(grepl("point estimates only", latent_table$uncertainty_reason)),
       "latent exports keep missing intervals and an explicit reason")
expect(nrow(gt_dstudy_target(latent, .8)) == 2L,
       "a single-outcome study infers its unambiguous outcome")

# Inspect actual graphics calls while still rendering a PDF. This verifies
# limits, series selection, target placement, and caller overrides.
plot_file <- tempfile(fileext = ".pdf")
capture <- new.env(parent = emptyenv())
trace("plot.default", where = asNamespace("graphics"), print = FALSE,
      tracer = substitute({
        assign("plot", list(x = x, y = y, ylim = ylim,
                            pch = list(...)$pch, col = list(...)$col,
                            type = type, xlab = xlab), envir = STORE)
      }, list(STORE = capture)))
trace("abline", where = asNamespace("graphics"), print = FALSE,
      tracer = substitute(assign("target", h, envir = STORE), list(STORE = capture)))
trace("segments", where = asNamespace("graphics"), print = FALSE,
      tracer = substitute(assign("segments", length(x0), envir = STORE), list(STORE = capture)))
tryCatch({
  grDevices::pdf(plot_file)
  returned <- plot(shuffled, coefficient = "Phi", target = 1,
                   outcome = "composite", kind = "outcome")
  expect(identical(returned, shuffled), "plot returns the complete original study invisibly")
  expect(length(capture$plot$y) == nrow(grid) && capture$plot$type == "p",
         "filtered plots show only selected-series points, without connecting allocations")
  expect(max(capture$plot$ylim) >= 1 && identical(capture$target, 1),
         "automatic limits include the target and the target line is drawn")
  expect(length(unique(capture$plot$pch)) == 2L,
         "default symbols distinguish allocations beyond fitted counts")
  capture$segments <- 0L
  plot(unknown, outcome = "composite", kind = "outcome")
  expect(capture$segments == sum(unknown_screen$Erho2_interval_available),
         "interval segments are drawn only for available point-and-bound rows")
  plot(study, target = .8, col = "red", pch = 3L, ylim = c(0, 1), xlab = "Calls")
  expect(identical(capture$plot$col, "red") && identical(capture$plot$pch, 3L) &&
           identical(capture$plot$ylim, c(0, 1)) && identical(capture$plot$xlab, "Calls"),
         "graphical overrides remain authoritative")
  expect_error(plot(study, outcome = "composite"), "specify kind explicitly",
               "a plot cannot confuse an outcome with a same-named composite")
  plot(latent, target = .8)
}, finally = {
  grDevices::dev.off()
  untrace("plot.default", where = asNamespace("graphics"))
  untrace("abline", where = asNamespace("graphics"))
  untrace("segments", where = asNamespace("graphics"))
})
expect(file.info(plot_file)$size > 1000, "the graphics checks render a nonempty PDF")
unlink(plot_file)
cat("PASS: flat coefficient reports, exact allocation joins, target screening, and plots.\n")
