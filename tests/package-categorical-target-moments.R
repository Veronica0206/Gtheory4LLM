# Run this same contract from source and from the installed package archive.
if (identical(Sys.getenv("GT_TARGET_MOMENT_TEST_SOURCE"), "true")) {
  source("load_functions.R")
  internal <- function(name) get(name, envir = .GlobalEnv, inherits = FALSE)
} else {
  library(Gtheory4LLM)
  internal <- function(name) get(name, envir = asNamespace("Gtheory4LLM"), inherits = FALSE)
}
variance <- internal(".gt_categorical_probability_variance")
moments <- internal(".gt_categorical_item_moments")
expect_error <- function(expr, pattern) {
  error <- tryCatch({ force(expr); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error), fixed = TRUE))
}
relative <- function(value, reference) {
  stopifnot(all(is.finite(value)), all(reference > 0), max(abs(value/reference-1)) < 2e-14)
}
# Independently rounded constants from 100-digit arithmetic. Oracles use the
# unordered-pair identity sum_{i<j} p_i p_j (s_i-s_j)^2, rather than the
# implemented centered-score summation. Trace is 2*sum_{i<j}p_i*p_j.
tiny <- 4.2483542552915889e-18
rarer <- 5.7495222642935599e-19
probabilities <- list(matrix(c(tiny, 1), 1), matrix(c(tiny, 1, tiny), 1),
                      matrix(c(tiny, 1, rarer), 1))
scores <- list(c(0, 1), c(0, 1, 2), c(0, .25, 1))
score_truth <- c(4.2483542552915889e-18, 8.4967085105831777e-18, 5.8893276832223701e-19)
trace_truth <- c(8.4967085105831777e-18, 1.6993417021166355e-17, 9.6466129634418897e-18)
for (i in seq_along(probabilities)) {
  p <- probabilities[[i]]; s <- scores[[i]]
  relative(variance(p, s), score_truth[[i]])
  relative(variance(p), trace_truth[[i]])
  reverse <- rev(seq_len(ncol(p)))
  relative(variance(p[, reverse, drop = FALSE], s[reverse]), score_truth[[i]])
  relative(variance(p[, reverse, drop = FALSE]), trace_truth[[i]])
}

# Deterministic moderate inputs; no RNG, fitting or long simulation is needed.
p <- matrix(c(.2,.3,.5, .1,.6,.3, .4,.2,.4, .7,.2,.1, .2,.7,.1,
              .3,.3,.4, .1,.1,.8, .2,.5,.3, .6,.1,.3, .5,.2,.3), byrow=TRUE, ncol=3)
s <- c(-2, .5, 4)
v <- variance(p, s)
stopifnot(max(abs(v-(drop(p %*% (s^2))-drop(p %*% s)^2))) < 2e-14,
  max(abs(v-variance(p, s+17))) < 2e-13,
  max(abs(9*v-variance(p, 3*s))) < 2e-13,
  max(abs(variance(p)-(1-rowSums(p^2)))) < 1e-15)
permutation <- c(3,1,2)
stopifnot(isTRUE(all.equal(v, variance(p[,permutation],s[permutation]), tolerance=2e-14)),
          isTRUE(all.equal(variance(p), variance(p[,permutation]), tolerance=2e-14)))

# Unequal replication makes a wrong first-appearance grouping observable.
item <- rep(1:3, c(2,3,5)); order <- c(10,9,1,3,2,4,5,6,7,8)
for (score in list(NULL, s)) {
  ordered <- moments(p,item,3,score)
  shuffled <- moments(p[order,],item[order],3,score)
  factored <- moments(p[order,],factor(item[order],levels=1:3),3,score)
  stopifnot(isTRUE(all.equal(ordered,shuffled,tolerance=2e-14)),
            isTRUE(all.equal(ordered,factored,tolerance=2e-14)))
  for (i in 1:3) {
    q <- p[item==i,,drop=FALSE]; n <- nrow(q)
    expected <- if (is.null(score)) colMeans(q) else mean(drop(q%*%score))
    independent_noise <- sum(vapply(seq_len(n), function(row) {
      sum(vapply(2:ncol(q), function(j) {
        previous <- seq_len(j-1L)
        if (is.null(score)) sum(2*q[row,j]*q[row,previous]) else
          sum(q[row,j]*q[row,previous]*(score[[j]]-score[previous])^2)
      }, numeric(1)))
    }, numeric(1)))/n^2
    stopifnot(max(abs(ordered$mean[i,]-expected)) < 1e-14,
      abs(ordered$second[[i]]-(sum(expected^2)+independent_noise)) < 2e-14)
  }
}
fractional <- item; fractional[[1L]] <- 1.5
expect_error(moments(p,fractional,3,s), "integers")
expect_error(moments(p,replace(item,1,NA),3,s), "integers")
expect_error(moments(p,replace(item,1,Inf),3,s), "integers")
expect_error(moments(p,replace(item,1,0),3,s), "1:n_items")
expect_error(moments(p,replace(item,1,4),3,s), "1:n_items")
expect_error(moments(p,item[-1],3,s), "1:n_items")
cat("PASS: categorical target moments retain representable tail variance, label/score invariance, and unequal shuffled allocation; invalid object IDs are refused.\n")
