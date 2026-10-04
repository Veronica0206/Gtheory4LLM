# Independent generator. Run only through run.py, before any fit.
args <- commandArgs(trailingOnly = TRUE)
out <- args[[1L]]
lib <- args[[2L]]
study <- args[[3L]]
config <- read.csv(file.path(study, "config.csv"), stringsAsFactors = FALSE)
stopifnot(nrow(config) == 4L, !anyDuplicated(config$scenario), all(config$replicates == 10L))
RNGkind("Mersenne-Twister", "Inversion", "Rejection")
plan <- do.call(rbind, lapply(seq_len(10L), function(i) {
  x <- config
  x$replicate <- i
  x$seed <- x$seed_base + i
  x
}))
plan$attempt <- seq_len(nrow(plan))
plan$variance_true <- plan$variance
plan$reliability_true <- plan$variance / (plan$variance + 1 / plan$repetitions)
plan$intercept_true <- ifelse(plan$family == "binary", sqrt(1 + plan$variance) * qnorm(plan$event_probability), 0)
plan$cut_1_true <- sqrt(1 + plan$variance) * qnorm(plan$cumulative_1)
plan$cut_2_true <- sqrt(1 + plan$variance) * qnorm(plan$cumulative_2)
stopifnot(!anyDuplicated(plan$seed), nrow(plan) == 40L)
dir.create(file.path(out, "panels"), showWarnings = FALSE)
for (k in seq_len(nrow(plan))) {
  s <- plan[k, ]
  set.seed(s$seed)
  d <- expand.grid(occasion = seq_len(s$repetitions), item = seq_len(s$n_items))
  u <- sqrt(s$variance) * qnorm(runif(s$n_items))
  latent <- u[d$item] + qnorm(runif(nrow(d)))
  d$y <- if (s$family == "binary") as.character(as.integer(s$intercept_true + latent > 0)) else
    c("low", "middle", "high")[1L + (latent > s$cut_1_true) + (latent > s$cut_2_true)]
  write.csv(d, file.path(out, "panels", sprintf("%02d.csv", k)), row.names = FALSE)
}
write.csv(plan, file.path(out, "plan.csv"), row.names = FALSE, na = "NA")
.libPaths(c(normalizePath(lib), .libPaths()))
library(Gtheory4LLM, lib.loc = lib)
stopifnot(as.character(packageVersion("Gtheory4LLM")) == "0.3.0.9000")
writeLines(c(paste("Package:", as.character(packageVersion("Gtheory4LLM"))),
             paste("Installed library:", normalizePath(lib)),
             paste("RNG:", paste(RNGkind(), collapse = ";")),
             paste("BLAS:", extSoftVersion()[["BLAS"]]),
             paste("LAPACK:", La_library()),
             paste("Matrix:", as.character(packageVersion("Matrix"))),
             paste("OpenMx:", as.character(packageVersion("OpenMx"))),
             capture.output(sessionInfo())), file.path(out, "environment.txt"))
