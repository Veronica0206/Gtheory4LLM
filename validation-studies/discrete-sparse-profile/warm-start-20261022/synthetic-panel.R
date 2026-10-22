# The 21,600-row synthetic ordinal-probit panel of harness/run.R, regenerated
# with the same generator lines, and its random-source design. Sourced by
# agreement.R and profile.R. rnorm() after set.seed() is not guaranteed to be
# bit-identical across architectures, so the category counts recorded by the
# harness (low 7598, middle 6719, high 7283 on aarch64 macOS) are asserted.
synthetic_panel <- function() {
  data <- expand.grid(item = seq_len(100L), evaluator = seq_len(4L),
    prompt = seq_len(3L), temperature = seq_len(6L), seed = seq_len(3L))
  source_variance <- c(item = 1, evaluator = .2, prompt = .15,
                       "item:evaluator" = .25, "item:prompt" = .2,
                       "evaluator:prompt" = .1)
  set.seed(2026102101L)
  eta <- numeric(nrow(data))
  for (name in names(source_variance)) {
    variables <- strsplit(name, ":", fixed = TRUE)[[1L]]
    group <- do.call(interaction, c(data[variables], list(drop = TRUE)))
    eta <- eta + rnorm(nlevels(group), sd = sqrt(source_variance[[name]]))[as.integer(group)]
  }
  latent <- eta + rnorm(nrow(data))
  thresholds <- c(-.7, .6)
  data$y <- ordered(c("low", "middle", "high")[1L + (latent > thresholds[1L]) +
                                                        (latent > thresholds[2L])],
                    levels = c("low", "middle", "high"))
  counts <- as.vector(table(data$y))
  if (!identical(counts, c(7598L, 6719L, 7283L)))
    stop("The regenerated panel's category counts differ from the harness record on this platform.")
  design <- gt_design("item", c("evaluator", "prompt", "temperature", "seed"),
                      random = names(source_variance))
  list(data = data, members = design$term_members,
       families = list(list(family = "ordinal", link = "probit", levels = levels(data$y))))
}
