# Warm starts within an optimizer attempt: measurements, 2026-10-22

Every number below comes from a file in this directory, produced by a script
in this directory or by the retained harness. Runs were made on an Apple M4 Max
with R 4.5.3, Matrix 1.7.4 and R's reference BLAS, single-threaded, while other
R work ran on the same machine (load average about 2.5 to 5), so seconds are
indicative and vary between runs; step counts, evaluation counts, objectives
and agreements are exact.

| File | Content | Produced by |
|---|---|---|
| `harness/run.py`, `harness/run.R` | the 21,600-row synthetic fit harness, byte-identical to the one whose SHA-256 the `*-started.json` records declare | retained unchanged |
| `before-synthetic-21600-{lbfgsb,nlminb}-summary.json` | the fits on the sources of `main` at 2c44c6c, before warm starts | the harness |
| `synthetic-21600-{lbfgsb,nlminb}-{summary,started}.json` | the fits with warm starts and explicit roles; `started.json` hashes every source file loaded | the harness |
| `synthetic-panel.R` | the harness's generator, regenerating the same panel and asserting its category counts | |
| `agreement.R`, `agreement.csv` | warm against cold objective agreement at 18 parameter vectors and two tolerances (36 rows) | `agreement.R` |
| `profile.R`, `profile-synthetic.txt`, `profile-native.txt` | one cold and one warm evaluation, the components of a Newton step, and the fixed-pattern assembly prototype | `profile.R synthetic`, `profile.R native` |

The harness writes a lock beside its own directory; copy `harness/` outside the
checkout to run it, with `--source` pointing at the checkout.

## Where the time goes (before)

Eight parameters, 819 random effects, 3,163 evaluations in 292 s, about 0.09 s
each (`before-synthetic-21600-lbfgsb-summary.json`). `optim()`'s numerical
gradient uses central differences, 2p evaluations, so every L-BFGS-B iteration
costs 1 + 2p = 17 evaluations and 16 of them are gradient probes (24 of 25 with
the native panel's 12 parameters).

## One evaluation, cold against warm (`profile-*.txt`)

The warm start is the mode at the same parameters with the first covariance
coordinate moved by 1e-3, which is what a gradient probe supplies.

| Panel | Random effects | Cold | Warm | Objective difference | Max mode difference |
|---|---:|---|---|---|---|
| Synthetic ordinal probit, 6 sources, at its optimum | 819 | 0.17 s, 8 Newton steps | 0.03 s, 3 steps | 4.8e-10 | 2.0e-10 |
| Native hate-speech ordinal probit, 10 sources, starting values | 9,507 | 0.66 s, 7 steps | 0.18 s, 3 steps | 1.5e-7 | 4.1e-9 |

Per Newton step, Hessian assembly is the largest component (4 ms synthetic, 30
ms native), the fresh Cholesky is under a millisecond on both, and the fill
counts cost 1 to 3 ms.

## Candidates measured and not adopted

- A fixed-pattern Hessian assembly (precomputed slot map, `rowsum`
  accumulation, entries identical to 2e-16): 6 ms against 4 ms per evaluation
  on the synthetic panel, 48 ms against 30 ms on the native panel.
- A cached Cholesky symbolic analysis through `Matrix::update()`: the fresh
  factorization is already under a millisecond on both panels; the update path
  measured slower on the native panel.

## Adopted

Warm starts within an L-BFGS-B attempt, with roles named by the fit (see
`docs/DISCRETE_BACKEND_CONTRACT.md`): the fit supplies `optim()`'s own
finite-difference gradient, written out so the path is unchanged, and every
probe of one gradient starts from the mode at the point it differentiates.
Every attempt starts cold; final checks, stationarity probes, information and
every `nlminb` evaluation stay cold; a warm solve that stops short falls back to
the cold solve, which keeps the older retry from the last valid mode. Fill
counts are computed only when asked.

## Agreement, warm against cold (`agreement.csv`)

Each vector is evaluated as a probe seeded from a centre's mode, and cold by a
fresh evaluator.

| Vectors | Coarse tolerance (1e-7) | Validation tolerance (1e-9) |
|---|---|---|
| 12 frozen calibration points (K01 to K06, displaced positive and negative), centre at each case's start | at most 4.4e-9 | at most 1.9e-10 |
| 5 synthetic 21,600-row points (the four attempt endpoints and the optimum of the before fit), centre at the automatic start | at most 5.5e-10 | at most 3.6e-12 |
| native 21,600-row starting values, centre at a neighbour | 1.5e-7 | 3.6e-12 |

The coarse figures are what the coarse inner tolerance leaves unresolved; the
log-determinant term is sensitive to the mode at that level, more so with
9,507 random effects. Every acceptance check runs at the validation tolerance.

## The synthetic 21,600-row fits, before and after

| | L-BFGS-B before | L-BFGS-B after | nlminb before | nlminb after |
|---|---|---|---|---|
| Disposition | accepted | accepted | rejected | rejected |
| Elapsed | 291.8 s | 126.0 s (106.4 s in an earlier run of the same path) | 128.2 s | 147.6 s |
| Evaluations (warm-started, fallbacks, rescues) | 3,163 | 2,942 (2,937, 0, 0) | 1,400 | 1,400 (0, 0, 0) |
| Tight objective | 17270.732031 | 17270.732032 | 17270.732060 (code 1) | identical to before |
| Latent Erho2 | 0.870823 | 0.870800 | unavailable | unavailable |
| Acceptance failures | none | none | restart rule | identical to before |

The L-BFGS-B path differs from the before path because the gradient sees the
objective at the 1e-9 level; its disposition and optimum are reproduced. Every
`nlminb` attempt is bit-identical to the before run: `nlminb` forms its finite
differences internally, so it solves cold throughout, and its elapsed times
differ only by machine load.

## Not measured here

A full native-panel fit with warm starts, and a native clmm comparison, wait
for a machine free of other fits; the 2,400-row clmm agreement to 1e-8 is on
record in the scale study. The dense engine and the Gaussian engines are
untouched, so the paper's categorical and Gaussian numbers do not change.
