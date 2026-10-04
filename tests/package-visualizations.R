# A real fitted example plus display edge cases. Graphics must not change fits,
# inferred quantities, random state, or the caller's margin settings.
library(Gtheory4LLM)
set.seed(30931)
d <- expand.grid(item = 1:32, rater = 1:6)
d$score <- rnorm(32, sd = 1.2)[d$item] +
  rnorm(6, sd = .8)[d$rater] + rnorm(nrow(d), sd = .7)
fit <- gt_fit(d, "score", gt_design("item", "rater", random = ~ item + rater),
  control = gt_control(gaussian = list(retry_seed = 42)))
stopifnot(isTRUE(fit$numerically_accepted))
reliability <- gt_reliability(fit)
original <- serialize(reliability, NULL)
seed <- .Random.seed
output <- tempfile(fileext = ".pdf")
grDevices::pdf(output, width = 9, height = 5)
margin <- graphics::par("mar")
shown <- withVisible(plot(reliability, target = .8, main = "Observed reliability"))
stopifnot(!shown$visible, identical(shown$value, reliability),
  identical(graphics::par("mar"), margin),
  identical(serialize(reliability, NULL), original), identical(seed, .Random.seed))
plot(reliability, coefficient = "Phi", interval = FALSE,
  col = "purple", pch = 17, xlab = "Absolute coefficient", xlim = c(0, 1))

# Missing estimates remain explicitly labelled; missing intervals are omitted.
missing <- reliability
missing$per_trait$Phi <- NA_real_
missing$per_trait$Phi_lower <- missing$per_trait$Phi_upper <- NA_real_
plot(missing, coefficient = "Phi")
latent <- reliability
latent$scale <- "latent"
latent$uncertainty <- list(available = FALSE, reason = "Discrete uncertainty is unavailable.")
for (name in c("Erho2", "Phi")) {
  latent$per_trait[[paste0(name, "_se")]] <- NA_real_
  latent$per_trait[[paste0(name, "_lower")]] <- NA_real_
  latent$per_trait[[paste0(name, "_upper")]] <- NA_real_
}
plot(latent, target = .75)
grDevices::dev.off()
stopifnot(file.info(output)$size > 1000)
unlink(output)
small <- tempfile(fileext = ".pdf")
grDevices::pdf(small, width = 4, height = 4)
long_name <- reliability
long_name$per_trait$outcome <- paste(rep("long outcome", 8), collapse = " ")
plot(long_name)
grDevices::dev.off()
stopifnot(file.info(small)$size > 1000)
unlink(small)
bad <- function(expr) stopifnot(inherits(tryCatch({force(expr); NULL}, error = identity), "error"))
bad(plot(reliability, target = NA_real_))
bad(plot(reliability, target = c(.5, .8)))
bad(plot(reliability, coefficient = c("Phi", "Phi")))
bad(plot(reliability, interval = NA))
cat("PASS: reliability forest plots preserve results and display absent uncertainty explicitly.\n")
