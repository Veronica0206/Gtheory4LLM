# Binary-logit parameter recovery: bounded pilot

This pilot is separate from the fixed-parameter integration comparisons. It
examines the whole estimation procedure with independently generated data.
Ten replicates per setting are too few to establish an operating range or
separate finite-sample bias from Laplace approximation bias.

Before running, `config.csv` fixes four settings: 12 items, 3 or 12 exchangeable
repetitions, random-intercept variance 0.1 or 2, and intercept -0.5. For each
replicate, draw independent item effects `u ~ N(0, variance)` and conditionally
independent responses `y ~ Bernoulli(plogis(intercept + u))`. Data seed is
`seed_base + replicate`, using Mersenne-Twister/Inversion/Rejection. There is
no shared repetition effect in this generating model. The corresponding
item-only random-intercept specification is intentional, not a repair of a
real annotation design.

The population latent target for a mean of `m` repetitions is
`G = Phi = variance / (variance + pi^2 / (3*m))`. This is not majority-vote
reliability or observed response agreement. Fit binary logit with diagonal
covariance, the default variance parameterization and acceptance checks, and
L-BFGS-B with at most 150 outer iterations. Starting values are automatic;
generating effects and variances are never supplied to fitting. No intervals
are available for this engine.

Attempt one replicate of each scenario in turn before advancing to the next
replicate. The budget is 180 cumulative fit seconds, checked between fits;
an in-progress fit may finish. Preserve all 40 planned rows, including errors,
numerical rejections and any unstarted rows. Checkpoint after each attempt.
Neither failed fits nor zero-variance estimates are rerun or removed.

Summary bias, RMSE and empirical SD use only accepted finite estimates, and
always report that denominator alongside planned, attempted, rejected, errored,
and boundary counts. Mean-estimate Monte Carlo SE is empirical SD / sqrt(n).
These summaries are conditional on numerical acceptance. Rejected-fit
estimates remain inspectable in the raw table but support no coefficient.
No test of acceptable bias, no interval coverage claim and no general
approximation-accuracy claim is made from this small pilot.

Run from the repository root with
`Rscript validation-studies/discrete-recovery/run.R /tmp/discrete-recovery-rerun`.
The output directory must be empty. The default is `results/` in this campaign.
Source fingerprints, Git base commit, RNG, R version and platform accompany
the results. Generated panels can be reproduced from the stored seeds; no
original text, real annotations or fitted-model objects are written.
