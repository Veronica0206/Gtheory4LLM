# Binary and ordinal usability/recovery pilot — predeclared protocol

This is a bounded development-source pilot, not a qualification campaign.
The protocol, configuration, implementation hashes, all 40 seeds, execution
order and generated panels are frozen before the first fit. No settings,
starts, tolerances, seeds or acceptance rules are changed after outcomes are
seen. Existing 0.2.0 release artifacts are not used or changed.

## Design and independent generator

Ten independently seeded panels per row of `config.csv` give 40 planned fits:

| Setting | Items | Repetitions per item | Population response probabilities | Latent reliability of the mean |
|---|---:|---:|---|---:|
| Binary balanced | 24 | 8 | 0.5 / 0.5 | 0.80 |
| Binary rare | 12 | 6 | 0.9 / 0.1 | 0.75 |
| Ordinal balanced | 24 | 8 | 0.3 / 0.4 / 0.3 | 0.80 |
| Ordinal rare | 12 | 6 | 0.1 / 0.85 / 0.05 | 0.75 |

Draw item effects `u_i ~ N(0, 0.5)` and independent observation errors
`e_ij ~ N(0, 1)`. Draws use only base R: Mersenne-Twister uniforms transformed
by `qnorm`, with RNG kinds Mersenne-Twister/Inversion/Rejection. Seed is the
configuration's `seed_base + replicate`; no stream is reused. Save all panels
as authoritative CSV files because a seed alone is not a cross-platform byte
identity. The generator calls no package fitting, response or simulation code.

For binary data, `y_ij = 1[alpha + u_i + e_ij > 0]`, with
`alpha = sqrt(1.5) * qnorm(p)`. For ordinal data, cut `u_i + e_ij` at
`sqrt(1.5) * qnorm(cumulative probabilities)` into low/middle/high. Thus the
marginal probabilities in the table follow directly from a `N(0, 1.5)` latent
response; they are not asserted to equal each finite panel's proportions.
No common occasion effect exists. A labelled `occasion` column merely indexes
exchangeable independent repetitions.

The population estimands are item variance `0.5` and latent mean-score
`G = Phi = 0.5 / (0.5 + 1/m)`, for `m` repetitions. These are not reliability
of observed category averages, majority voting, accuracy, or observed
agreement. Setting differences confound group count, replication and response
rarity deliberately: they are two usability settings, not a factorial estimate
of any one effect. The pilot cannot separate finite-sample from Laplace bias.

## Fitting and finite execution budget

Use the freshly installed development package **0.3.0.9000**, recording its
actual installed path, runtime file hashes, R/dependency environment, associated
source archive SHA-256 and archive source-file hashes. The archive identifies
the executed source snapshot; the current Git base and checkout hashes are
additional context, not a claim that an uncommitted checkout equals its base.
The runner requires explicit archive and library paths, refuses a nonempty
output directory, and writes the pre-fit freeze manifest before fitting.

Use only the public dense API: `gt_design("item", "occasion", random = ~item,
full_cell = FALSE)`, `gt_family(family, "probit", levels = ...)`, diagonal
covariance, ML_Laplace, automatic starts, and `gt_control(discrete =
list(maxit = 150L, optimizer = "L-BFGS-B"))`. Other numerical controls and
acceptance criteria remain package defaults. Generating item effects and
parameters are never supplied to the fitter. Missing declared categories,
errors, warnings, numerical rejections, boundary estimates and timeouts are
retained, never replaced or rerun.

Interleave the four scenarios within replicate 1, then replicate 2, and so on.
The whole runner has a **450-second wall-clock budget**, including preparation
and summaries, with **10 seconds per fit subprocess**, including R startup and
result writing. Reserve 15 seconds for final summaries. A subprocess is killed
at its timeout; all planned rows remain in `attempts.csv`, including
`budget_not_started`. Checkpoint after every attempt. Preparation, fits and
summary each have external subprocess deadlines. This is an execution budget,
not an accuracy criterion. No campaign restart is used to recover timed-out
attempts. Setup and reading/rendering the produced figure are outside fit
execution; no additional fits are performed there.

## Analysis fixed before execution

Report planned, attempted, accepted, rejected, errored, timed out and unstarted
counts first, by setting. Acceptance is accepted/attempted, where errors and
timeouts count as nonacceptance. Give Wilson 95% Monte Carlo intervals with
that denominator; these describe simulated acceptance, not parameter coverage.
Also retain category counts, elapsed time, optimizer completion, approximation
status, acceptance failures and warnings/errors for every attempt.

Only accepted finite estimates contribute to bias and RMSE; print the separate
usable denominator for each estimand. Bias MCSE is `sd(error)/sqrt(n)` and RMSE
MCSE uses the delta approximation `sd(error^2)/(2*RMSE*sqrt(n))`, requiring at
least two accepted finite estimates. If RMSE is zero and n>=2, its MCSE is zero.
For n=0 or 1, unavailable uncertainty stays NA. All summaries are conditional
on numerical acceptance and can be affected by that selection. Rejected
variance estimates remain in the attempt table/plot as diagnostics, not in
recovery summaries. The latent coefficient is requested only after acceptance.
A coefficient extraction failure remains visible and reduces its usable n.

Figures show acceptance with Wilson intervals and every available variance/
accepted latent-reliability estimate against the generating truth. Jitter is
deterministic by replicate. No bias threshold, hypothesis test, interval
coverage, sparse-backend qualification, multivariate claim, CRAN check or
production-readiness conclusion is attached to this 10-replicate-per-setting
pilot. Monte Carlo precision is deliberately poor and is reported explicitly.
