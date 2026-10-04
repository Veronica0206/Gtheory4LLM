# Forest display of the coefficients already calculated by gt_reliability().
# Drawing a figure never refits, changes acceptance or invents missing intervals.
plot.gt_reliability <- function(x, coefficient = c("Erho2", "Phi"),
                                interval = TRUE, target = NULL, ...) {
  if (!is.character(coefficient) || !length(coefficient) || anyNA(coefficient) ||
      anyDuplicated(coefficient) || any(!coefficient %in% c("Erho2", "Phi")))
    stop("coefficient must contain Erho2, Phi, or both, without duplicates.", call. = FALSE)
  if (!is.logical(interval) || length(interval) != 1L || is.na(interval))
    stop("interval must be TRUE or FALSE.", call. = FALSE)
  if (!is.null(target) && (!is.numeric(target) || length(target) != 1L ||
      !is.finite(target) || target < 0 || target > 1))
    stop("target must be NULL or one finite number from 0 to 1.", call. = FALSE)
  tab <- as.data.frame(x)
  rows <- do.call(rbind, lapply(coefficient, function(name) {
    data.frame(outcome = tab$outcome, kind = tab$kind, coefficient = name,
      estimate = tab[[name]], lower = tab[[paste0(name, "_lower")]],
      upper = tab[[paste0(name, "_upper")]], stringsAsFactors = FALSE)
  }))
  if (!nrow(rows)) stop("No coefficient rows to plot.", call. = FALSE)
  position <- rev(seq_len(nrow(rows)))
  labels <- paste(ifelse(rows$kind == "composite", "Composite", paste0("Outcome: ", rows$outcome)),
                  rows$coefficient, sep = " | ")
  labels[!is.finite(rows$estimate)] <- paste(labels[!is.finite(rows$estimate)], "(unavailable)")
  usable_interval <- interval & is.finite(rows$estimate) &
    is.finite(rows$lower) & is.finite(rows$upper)
  note <- if (!interval) "Point estimates; intervals hidden" else if (any(usable_interval))
    paste0(format(100 * x$level, digits = 4), "% estimation intervals",
      if (isTRUE(x$uncertainty$restricted_to_interior)) " (conditional)" else "") else
    "Point estimates; intervals unavailable"
  if (identical(x$scale, "latent")) note <- paste(note, "latent responses", sep = "; ")
  if (isTRUE(x$extrapolated)) note <- paste(note, "extrapolated allocation", sep = "; ")
  dots <- list(...)
  if (length(dots) && (is.null(names(dots)) || any(!nzchar(names(dots)))))
    stop("Graphical arguments in ... must be named.", call. = FALSE)
  if (any(names(dots) %in% c("x", "y")))
    stop("x and y are supplied by the coefficient plot.", call. = FALSE)
  defaults <- list(xlim = c(0, 1), ylim = c(.5, nrow(rows) + .5), yaxt = "n",
    xlab = paste("Reliability -", x$scale, "scale"), ylab = "",
    pch = ifelse(rows$kind == "composite", 18, 19),
    col = ifelse(rows$coefficient == "Erho2", "#2166AC", "#B35806"), sub = note)
  settings <- utils::modifyList(defaults, dots)
  previous <- graphics::par("mar")
  on.exit(graphics::par(mar = previous), add = TRUE)
  line_height <- graphics::par("cin")[[2L]] * graphics::par("mex")
  axis_gap <- graphics::par("mgp")[[2L]] * line_height + .15
  label_width <- max(graphics::strwidth(labels, units = "inches")) + axis_gap
  # Leave room for the coefficient axis even on a small device. Arbitrarily
  # long outcome labels must not consume the complete plotting region.
  left <- min(max(previous[2L] * line_height, label_width), graphics::par("fin")[[1L]] * .4)
  available <- max(.15, left - axis_gap)
  for (i in seq_along(labels)) {
    if (graphics::strwidth(labels[i], units = "inches") <= available + 1e-8) next
    label_id <- (i - 1L) %% nrow(tab) + 1L
    text <- if (rows$kind[i] == "composite") "Composite" else rows$outcome[i]
    shortened <- paste0("[", label_id, "] ", text, "... | ", rows$coefficient[i])
    while (nchar(text) > 1L && graphics::strwidth(shortened, units = "inches") > available) {
      text <- substr(text, 1L, nchar(text) - 1L)
      shortened <- paste0("[", label_id, "] ", text, "... | ", rows$coefficient[i])
    }
    labels[i] <- shortened
  }
  graphics::par(mar = c(previous[1L], left / line_height, previous[3:4]))
  do.call(graphics::plot, c(list(rows$estimate, position), settings))
  graphics::axis(2, at = position, labels = labels, las = 1, tick = FALSE)
  if (any(usable_interval)) {
    colors <- rep(settings$col, length.out = nrow(rows))
    graphics::segments(rows$lower[usable_interval], position[usable_interval],
      rows$upper[usable_interval], position[usable_interval], col = colors[usable_interval])
  }
  if (!is.null(target)) graphics::abline(v = target, lty = 2, col = "#555555")
  invisible(x)
}
