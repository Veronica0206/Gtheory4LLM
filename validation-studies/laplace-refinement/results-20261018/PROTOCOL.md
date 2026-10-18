# Defensive-mixture likelihood diagnostic: bounded numerical study

Declared before this study's first numerical execution. This study evaluates
the new importance diagnostic on the existing binary-logit regression fixture;
it is not a new model-recovery study, a test of fitted-parameter bias, or a
general calibration claim for ordinal, nominal, multivariate or crossed models.

The fixture is the one in `tests/package-laplace-check.R`: three items, eight
observations per item, an item random intercept, seed 11, and generating success
probabilities `plogis(c(-1, 0.2, 1.1))`. Fit the binary-logit model once, with
`maxit = 200`, and require numerical acceptance. Keep its fitted parameters fixed
throughout the comparison. Compute the marginal likelihood independently as
the product of three one-dimensional integrals, using base R `integrate()` at
relative tolerances 1e-10 and 1e-12. Their minus-two-log-likelihood values must
agree within 1e-8. No implementation from the package's response or integration
engine enters that reference.

The original Gaussian-only proposal has infinite importance-weight second
moments on this fixture: in standardized random-effect coordinates its three
conditional-mode Hessian diagonal entries exceed two. Record those entries.
The replacement proposal is fixed before evaluation at 90% the Laplace Gaussian
and 10% the standard-normal prior, with the full mixture density used for every
weight. Its unnormalised weights are at most ten because the discrete likelihood
is at most one. This proves finite moments of those weights, not finite-sample
calibration of a log-likelihood interval or good relative precision.

Run 40 independent seeds at each of two draw budgets: 2,000 and 20,000. Seeds
are 71001--71040 at the first budget and 72001--72040 at the second. Do not tune
seeds, budgets or the mixture using these results. Retain all 80 attempts,
including errors and empirical-ESS screen failures. The screen's existing
threshold is ESS at least 200 and at least 10% of draws; it is not an accuracy
certificate and is not the criterion for including a finite result in summaries.

For each budget, report the number attempted, finite results, screen passes,
mean error from the independent reference, empirical SD and RMSE, mean and
root-mean-square reported delta-method MCSE, and the number of nominal
`estimate +/- 1.96 * MCSE` intervals containing the reference. Give a binomial
interval for that last descriptive proportion. Forty repetitions provide only
imprecise calibration evidence. Retain maximum observed unnormalised weights
and realized component counts to audit the sampler.

The runner takes a new output directory and optional isolated R library. It
refuses to overwrite existing results, records session information and hashes
the owned implementation, test, manual, protocol and runner before and after
execution. The installed package path and source Git revision/status are recorded
separately: a development working-tree run does not establish final-archive,
cross-platform or release qualification. No global statistical threshold is
defined from this one fixture's result.
