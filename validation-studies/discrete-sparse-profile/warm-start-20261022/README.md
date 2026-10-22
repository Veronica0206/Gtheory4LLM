# Warm starts within an optimizer attempt: measurements, 2026-10-22

Measured before and after the change on the sources of `main` at 2c44c6c, on an
Apple M4 Max with R 4.5.3, Matrix 1.7.4 and R's reference BLAS, single-threaded,
while two unrelated R fits were running on the same machine (load average 4 to
5). The seconds are therefore indicative; the step counts, evaluation counts,
objectives and agreements are exact. Nothing here is a timing qualification.

## Evaluations by stage (before, the accepted 21,600-row L-BFGS-B fit)

Eight parameters, 819 random effects, 3,163 evaluations in 292 s, about 0.09 s
each. `optim()`'s numerical gradient uses central differences, 2p evaluations,
so every L-BFGS-B iteration costs 1 + 2p = 17 evaluations and 16 of them are
gradient probes (24 of 25 with the native panel's 12 parameters). The four
attempts took 67, 37, 60 and 22 iterations; the one tight re-evaluation of the
primary fit is the 3,163rd evaluation. The stationarity probes (2p coarse and
2p refined) and the final check are outside that count.

## One evaluation, cold from zero modes versus warm from a neighbour's mode

The neighbour is the mode found at the same parameters with the first
covariance coordinate moved by 1e-3, which is what a finite-difference probe
supplies.

| Panel | Random effects | Cold | Warm | Objective difference | Max mode difference |
|---|---:|---|---|---|---|
| Synthetic ordinal probit, 21,600 rows, 6 sources | 819 | 0.091 s, 8 Newton steps | 0.034 s, 3 steps | 4.8e-10 | 2.0e-10 |
| Native hate-speech ordinal probit, 21,600 rows, 10 sources, starting values | 9,507 | 0.52 to 0.64 s, 7 steps | 0.21 s, 3 steps | 1.5e-7 (coarse), 3.6e-12 (validation tolerance) | 4.1e-9 (coarse), 4.1e-14 (validation) |

Components of one Newton step at the mode (medians of three):

| Component | Synthetic (819) | Native (9,507) |
|---|---:|---:|
| response kernel | 2 to 3 ms | 3 ms |
| Hessian assembly (`crossprod` and symmetrize) | 3 to 4 ms | 26 ms |
| Cholesky, fresh symbolic analysis and factor | under 1 ms | under 1 ms |
| Cholesky through `Matrix::update()` on a cached analysis | 1 ms | 14 ms |
| the three fill counts in `.gt_d_sparse_factor()` | about 1 ms | 2 ms |
| solve through the factor | under 1 ms | 1 ms |
| one line-search trial (`W %*% u` and kernel) | 3 ms | 2 ms |

Fill: synthetic H has 15,843 stored entries and its factor 15,039; native H has
433,539 and its factor 328,278 (1.5 times the triangle).

## Candidates measured and not adopted

- A fixed-pattern Hessian assembly (precomputed slot map, `rowsum`
  accumulation, entries identical to 2e-16): 6.0 ms per evaluation against 3.0
  ms for the current assembly on the synthetic panel, 48 ms against 26 ms on
  the native panel. Slower on both; not adopted.
- A cached Cholesky symbolic analysis with `Matrix::update()`: the fresh
  factorization is already below a millisecond on both panels, and the update
  path measured slower. Not adopted. A cache would also need a guard for the
  pattern change that a source at an exact zero produces.

## Adopted: warm starts within an attempt, and fill counts off the hot path

Policy (R/discrete_sparse_mode.R, R/discrete.R; contract in
docs/DISCRETE_BACKEND_CONTRACT.md): within an optimizer attempt each
conditional solve starts from the attempt's centre mode; both probes of a
coordinate share the centre; every attempt starts cold; the final checks, the
stationarity probes and the information step stay cold; a warm solve that
stops short falls back to the cold solve. `.gt_d_sparse_factor()` computes
fill counts only when asked.

Warm-versus-cold objective agreement, 18 parameter vectors:

| Vectors | Coarse tolerance (1e-7) | Validation tolerance (1e-9) |
|---|---|---|
| 12 frozen calibration points (K01 to K06, displaced positive and negative) | at most 3.0e-9 | at most 1.9e-10 |
| 5 synthetic 21,600-row points (four attempt endpoints and the optimum) | at most 3.0e-9 | at most 1.1e-11 |
| native 21,600-row starting values | 1.5e-7 | 3.6e-12 |

The coarse figures are what the coarse inner tolerance leaves unresolved: the
objective's log-determinant term is sensitive to the mode at the 1e-7 gradient
level, and more so with 9,507 random effects. Every acceptance check runs at
the validation tolerance.

## The synthetic 21,600-row fits, before and after (`synthetic-21600-*-summary.json`)

| | L-BFGS-B before | L-BFGS-B after | nlminb before | nlminb after |
|---|---|---|---|---|
| Disposition | accepted | accepted | rejected | rejected |
| Elapsed | 291.8 s | 106.4 s | 128.2 s | 34.4 s |
| Evaluations (warm, fallbacks) | 3,163 | 2,942 (2,937, 0) | 1,400 | 989 (984, 0) |
| Tight objective | 17270.732031 | 17270.732032 | 17270.732060 (code 1) | 17270.732034 (code 1) |
| Max parameter difference at the primary tight point | | 1.7e-4 | | 7.7e-4 |
| Latent Erho2 | 0.870823 | 0.870800 | unavailable | unavailable |
| Acceptance failures | none | none | restart rule | restart rule, and the tightened alternative now also stops with code 1 (`optimizer_incomplete`) |

Both dispositions are reproduced; the optimizer paths differ because the
objective seen by the finite-difference gradient differs at the 1e-9 level,
and nlminb's termination codes are sensitive to that. The warm-start retry
and the cold fallback never fired.

## Not measured here

A full native-panel fit with the change, and the native clmm comparison, wait
for the machine to be free of the running native fits; the 2,400-row clmm
agreement to 1e-8 is on record in the scale study. The paper's categorical
numbers come from the dense engine, which is untouched by this change, as is
the Gaussian engine.
