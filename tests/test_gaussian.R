# Run from the project root: Rscript tests/test_gaussian.R
source("R/design.R")
source("R/gaussian_retry.R")
source("R/gaussian_engine.R")
source("R/gaussian.R")
if (!requireNamespace("OpenMx", quietly = TRUE)) stop("OpenMx is required.")
near <- function(a, b, tolerance = 1e-5, label = "comparison") {
  if (!isTRUE(all.equal(unname(a), unname(b), tolerance = tolerance, check.attributes = FALSE)))
    stop(label, " failed: maximum absolute difference ", max(abs(a-b)))
}
expect_error <- function(expr, pattern) {
  e <- tryCatch({ force(expr); NULL }, error = identity)
  if (is.null(e) || !grepl(pattern, conditionMessage(e), fixed = TRUE))
    stop("Expected error containing: ", pattern)
}
# Full data covariance likelihood independent of the factorial-stratum code.
raw_deviance <- function(data, outcomes, components, reml) {
  N <- nrow(data); D <- length(outcomes); V <- matrix(0, N*D, N*D)
  for (g in names(components)) {
    if (g == "Residual") K <- diag(N) else {
      members <- strsplit(g, ":", fixed = TRUE)[[1L]]
      K <- Reduce(`*`, lapply(data[members], function(x) outer(x, x, `==`)))
    }
    V <- V + kronecker(K, components[[g]])
  }
  L <- chol(V); inverse <- chol2inv(L)
  X <- kronecker(matrix(1,N,1), diag(D))
  information <- crossprod(X, inverse %*% X)
  y <- as.vector(t(as.matrix(data[outcomes])))
  beta <- solve(information, crossprod(X, inverse %*% y))
  error <- y-X %*% beta
  value <- (N*D-if (reml) D else 0)*log(2*pi)+2*sum(log(diag(L)))+
    drop(crossprod(error, inverse %*% error))
  if (reml) value <- value+2*sum(log(diag(chol(information))))
  value
}
set.seed(781L)
d <- expand.grid(subject=1:12, rater=letters[1:3], occasion=1:2,
                 KEEP.OUT.ATTRS=FALSE, stringsAsFactors=FALSE)
Z <- matrix(rnorm(nrow(d)*2),nrow(d),2)
item_effect <- matrix(rnorm(24),12,2) %*% chol(matrix(c(2,.6,.6,1.4),2))
rater_effect <- matrix(rnorm(6),3,2); time_effect <- matrix(rnorm(4),2,2)
Y <- Z %*% chol(matrix(c(1,.3,.3,1.3),2))+item_effect[d$subject,]+
  rater_effect[match(d$rater,letters),]+time_effect[d$occasion,]
d$score_one <- Y[,1]; d$score_two <- Y[,2]
outcomes <- c("score_one","score_two")
design <- gt_design("subject",c("rater","occasion"),random=c("subject","rater","occasion"))
engine <- .gt_gaussian_engine(c(design$object,design$facets))
prepared <- engine$prepare(d,outcomes)
components <- list(subject=matrix(c(2,.6,.6,1.4),2),rater=matrix(c(.8,.1,.1,.5),2),
                   occasion=diag(c(.2,.3)),Residual=matrix(c(1,.3,.3,1.3),2))
for (reml in c(FALSE,TRUE))
  near(engine$deviance(prepared,components,reml),raw_deviance(d,outcomes,components,reml),
       1e-10,paste("Independent N=2 likelihood",reml))
cat("PASS: arbitrary-name N=2 ML and REML match independent full covariance likelihood.\n")
control <- list(extra_tries=2L,check_hessian=FALSE,retry_seed=439L,
                tolerance=1e-10,max_iterations=1500L)
rng_before <- .Random.seed
joint <- .gt_fit_gaussian(d,outcomes,design,covariance="diagonal",residual="diagonal",control=control)
stopifnot(identical(.Random.seed,rng_before),joint$converged,
          joint$diagnostics$independent_likelihood_matches,
          identical(names(joint$covariance_components),c(design$terms,"Residual")),
          identical(joint$estimator,"REML"),joint$design$validated_data)
separate <- lapply(outcomes,function(y) .gt_fit_gaussian(d,y,design,control=control))
stopifnot(all(vapply(separate,function(x) x$converged,logical(1))))
near(joint$minus2loglik,sum(vapply(separate,`[[`,numeric(1),"minus2loglik")),1e-7,
     "Joint diagonal versus separate REML likelihood")
for (j in seq_along(outcomes))
  near(vapply(joint$covariance_components,function(M) M[j,j],numeric(1)),
       vapply(separate[[j]]$covariance_components,function(M) M[1,1],numeric(1)),
       1e-4,"Joint diagonal versus separate variance components")
cat("PASS: generic univariate and multivariate diagonal fits agree; caller RNG restored.\n")
unstructured <- .gt_fit_gaussian(d,outcomes,design,control=control)
stopifnot(unstructured$converged,unstructured$diagnostics$independent_likelihood_matches)
near(unstructured$minus2loglik,raw_deviance(d,outcomes,unstructured$covariance_components,TRUE),
     1e-9,"Unstructured joint fit independent likelihood")
stopifnot(any(abs(vapply(unstructured$covariance_components,function(M) M[1,2],numeric(1)))>.01))
cat("PASS: unstructured source covariance fit converges and matches independent likelihood.\n")
full <- gt_design("subject",c("rater","occasion"))
full_fit <- .gt_fit_gaussian(d,"score_one",full,control=control)
stopifnot(full_fit$converged,length(full_fit$covariance_components)==7L,
          "subject:rater:occasion" %in% full_fit$design$aliased_terms)
near(full_fit$minus2loglik,raw_deviance(d,"score_one",full_fit$covariance_components,TRUE),
     1e-9,"Full interaction independent likelihood")
cat("PASS: complete interactions retain the full-cell residual alias.\n")
expect_error(.gt_fit_gaussian(d[-1,],outcomes,design),"complete balanced factorial")
expect_error(.gt_fit_gaussian(rbind(d[-1,],d[2,]),outcomes,design),"replication does not match")
expect_error(.gt_fit_gaussian(d,outcomes,design,control=list(unknown=1)),"Unsupported Gaussian control")
replicated <- gt_design("subject",c("rater","occasion"),replicates=2L)
expect_error(.gt_fit_gaussian(d,outcomes,replicated),"replication does not match")
expect_error(.gt_fit_gaussian(rbind(d,d),outcomes,replicated),"within-cell replication")
expect_error(.gt_fit_gaussian(transform(d,score_one=NA_real_),outcomes,design),"missing or non-finite")
cat("PASS: unsupported inputs and control settings are rejected explicitly.\n")
cat("All Gaussian backend tests passed.\n")
