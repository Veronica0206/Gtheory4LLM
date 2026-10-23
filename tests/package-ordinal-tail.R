# This fixed-point tail contract runs from sources and from an installed archive.
if (identical(Sys.getenv("GT_ORDINAL_TAIL_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
interval <- internal(".gt_d_ordinal_interval")
kernel <- internal(".gt_d_response_kernel")
probabilities <- internal(".gt_d_ordinal_probabilities")
near <- function(actual, expected) {
  stopifnot(all(is.finite(actual)), all(abs(actual - expected) <= 3e-8 * pmax(abs(expected), 1e-300)))
}
# Constants are rounded independently from160-digit exact-input probabilities.
# Hexadecimal endpoint literals avoid cross-language decimal parser ambiguity.
fixture <- data.frame(
  link = c(
    "probit", "probit", "probit",
    "probit", "probit", "probit",
    "probit", "probit", "probit",
    "probit", "probit", "logit",
    "logit", "logit", "logit",
    "logit", "logit", "logit",
    "logit", "logit"
  ),
  lo = c(
    -Inf, -0x1.ep+3, -0x1.ep+3,
    -0x1p+2, 0x1.8p+0, 0x1.7fffffffffp+0,
    0x1.8ffff41943255p+5, -0x1.8p+1, 0x1p+0,
    -0x1p-1, -0x1.0000000002p-1, -Inf,
    0x1.9p+5, 0x1.dfffd0650c953p+3, -0x1.5798ee2308c3bp-27,
    -0x1.5ep+9, -0x1p+1, 0x1p+0,
    -0x1p-1, 0x1.5dcp+9
  ),
  hi = c(
    -0x1.ep+3, Inf, 0x1.ep+3,
    0x1.ffffffffffffcp+1, 0x1.4p+1, 0x1.40000000008p+1,
    0x1.90000be6bcdabp+5, -0x1p+0, 0x1.8p+1,
    0x1p-1, 0x1.0000000002p-1, 0x1.9p+5,
    Inf, 0x1.e0002f9af36adp+3, 0x1.5798ee2308c3ap-27,
    0x1.5e00000000001p+9, -0x1p+0, 0x1p+1,
    0x1p-1, 0x1.5e4p+9
  ),
  loss = c(
    116.13138484571169, 3.6709661993127508e-51, 7.3419323986255017e-51,
    6.3344489886078327e-05, 2.803501047738798, 2.8035010477365909,
    1260.918938318631, 1.8495664205476083, 1.8495664205476083,
    0.95991633369562235, 0.95991633369394991, 1.9287498479639178e-22,
    50, 25.0000006116843, 19.113827924512311,
    1.971935308751842e-304, 1.8988648439482771, 1.8988648439482771,
    1.4068291137472952, 699.95867514538713
  ),
  score = c(
    15.066086827167823, -5.5307095498444164e-50, 0,
    9.5098118493391157e-19, -1.8480833160858641, -1.8480833160853589,
    -49.999999991411862, 1.510049513243984, -1.510049513243984,
    0, 0, 1.9287498479639178e-22,
    -1, -0.99999938819554601, 4.1359030627651384e-25,
    -1.1209153865274948e-317, 0.61185565660788732, -0.61185565660788732,
    0, -1
  ),
  curvature = c(
    0.99566987624244008, 8.2960643247666248e-49, 1.659212864953325e-48,
    0.0010707096275261792, 0.93254461330487226, 0.93254461330467375,
    0.99999999982823728, 0.82654709507587798, 0.82654709507587798,
    0.91941084539918827, 0.91941084539890494, 1.9287498479639178e-22,
    1.9287498479639178e-22, 6.1180426685653213e-07, 0.5,
    1.971935308751842e-304, 0.30160551864498836, 0.30160551864498836,
    0.47000742440318899, 2.2236054558559648e-304
  )
  , stringsAsFactors = FALSE
)
for (link in c("probit", "logit")) {
  z <- fixture[fixture$link == link, ]
  v <- interval(z$lo, z$hi, link, derivatives = TRUE)
  near(-v$log_probability, z$loss)
  near(v$gradient, z$score)
  near(v$curvature, z$curvature)
  stopifnot(identical(interval(z$lo, z$hi, link), v$log_probability))
  # Mixed narrow/wide/end-category groups cross both512 and1024-row joins.
  index <- ((seq_len(1031L) * 7L) %% nrow(z)) + 1L
  repeated <- interval(z$lo[index], z$hi[index], link, derivatives = TRUE)
  for (field in names(v)) near(repeated[[field]], v[[field]][index])
}
# A joint response call joins each outcome's repaired kernel without reordering.
n <- 1031L
eta <- cbind(rep(c(-50, 0, 50), length.out = n), rep(c(15, -15, 0), length.out = n))
parameters <- c(-exp(-10) / 2, -10, -exp(-10) / 2, -10)
blocks <- list(
  list(family = "ordinal", link = "probit", dims = 1L, parameters = 1:2,
       y = rep(1:3, length.out = n)),
  list(family = "ordinal", link = "logit", dims = 2L, parameters = 3:4,
       y = rep(3:1, length.out = n))
)
joint <- kernel(eta, parameters, list(n = n, q = 2L, blocks = blocks))
stopifnot(joint$valid)
loss <- 0
for (j in 1:2) {
  one_block <- blocks[[j]]
  one_block$dims <- 1L
  one <- kernel(eta[, j, drop = FALSE], parameters, list(n = n, q = 1L, blocks = list(one_block)))
  stopifnot(one$valid)
  loss <- loss + one$nll
  near(matrix(joint$gradient, n)[, j], one$gradient)
  near(joint$curvature[[j]]$diagonal, one$curvature[[1]]$diagonal)
  p <- probabilities(eta[, j], c(-exp(-10) / 2, exp(-10) / 2), blocks[[j]]$link)
  stopifnot(max(abs(rowSums(p) - 1)) < 1e-13)
}
near(joint$nll, loss)
# The wider same-tail probit arithmetic remains unchanged.
lo <- 1; hi <- 3
lp <- internal(".gt_d_logdiff")(pnorm(lo, lower.tail = FALSE, log.p = TRUE),
                                pnorm(hi, lower.tail = FALSE, log.p = TRUE))
rl <- exp(dnorm(lo, log = TRUE) - lp); rh <- exp(dnorm(hi, log = TRUE) - lp)
v <- interval(lo, hi, "probit", derivatives = TRUE)
stopifnot(identical(v$log_probability, lp), identical(v$gradient, rh - rl),
          identical(v$curvature, (rh - rl)^2 - ((-hi) * rh - (-lo) * rl)))
cat("PASS: ordinal tail, narrow-boundary, block-join and kernel contracts.\n")
