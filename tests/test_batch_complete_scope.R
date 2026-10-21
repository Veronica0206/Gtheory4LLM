source("load_functions.R")
expect <- function(x, text) if (!isTRUE(x)) stop(text)
data <- expand.grid(item = seq_len(8L), rater = seq_len(3L))
data$y <- rep(c(0L, 1L), length.out = nrow(data))
design <- gt_design("item", "rater", random = c("item", "rater"), batch = gt_batch(size = 2L))
expect(.gt_batch_model(data, design)$modelled, "Complete inferred fixed calls are modelled")
for (changed in list(data[-1L, ], rbind(data, data[1L, ]),
                     rbind(data[-1L, ], data[2L, ]))) {
  found <- .gt_batch_model(changed, design)
  expect(!found$modelled && grepl("complete balanced", found$reason, fixed = TRUE),
         "Incomplete and duplicate inferred layouts do not claim a Call source")
  preflight <- gt_preflight(changed, "y", design, gt_family("binary"))
  expect(!"Call" %in% preflight$sources$source,
         "Preflight does not count an unsupported fixed-call source")
}
# Missing whole conditions cannot be hidden by supplying valid recorded call
# identifiers in the remaining cells. The Cartesian condition scope matters.
data$occasion <- rep(seq_len(2L), each = nrow(data) / 2L)
data$call_id <- interaction((data$item - 1L) %/% 2L, data$rater, data$occasion, drop = TRUE)
recorded <- gt_design("item", c("rater", "occasion"), random = c("item", "rater"),
                      batch = gt_batch(size = 2L, id = "call_id"))
expect(!.gt_batch_model(data, recorded)$modelled,
       "Recorded calls also require the declared complete condition panel")
cat("PASS: fixed call model and preflight share the complete, one-row-per-cell scope.\n")
