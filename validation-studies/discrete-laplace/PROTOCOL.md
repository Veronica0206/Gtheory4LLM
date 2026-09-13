# Fixed-parameter discrete likelihood comparison

This bounded study compares the package's first-order Laplace marginal negative
log likelihood (NLL) with an independently calculated numerical integral. It is
an approximation study at known parameter values, **not** a parameter recovery,
interval coverage, or fitted-model acceptance study. Numerical optimization
success and approximation accuracy are different quantities.

## Predeclared design

- One random item intercept, six independent items, 3 or 12 observations per
  item. The observed responses are individual trials: neither likelihood includes
  a binomial or multinomial count coefficient.
- Binary logit and probit; three-level ordinal logit and probit; three-category
  nominal softmax. Outcomes within each item are conditionally independent.
- Random-intercept variance: 0, 0.1, or 2. For nominal outcomes there are two
  reference-category contrasts, each with that variance and correlation 0.3.
- Balanced parameters: binary intercept 0; ordinal cutpoints (-0.6, 0.6);
  nominal contrast intercepts (0, 0).
- Rare-response parameters: binary intercept -2.2; ordinal cutpoints (1.2, 1.8);
  nominal contrast intercepts (-1.5, -2.3).
- Full factorial: 60 scenarios, three independently generated panels each;
  180 attempted comparisons. These three panels are examples of sampling
  variability, not an adequately powered Monte Carlo campaign. Scenario order
  and seeds are materialized in `scenarios.csv` before calculation. Replicate
  seed is 30100 + 100 * scenario number + replicate number, with R's declared
  Mersenne-Twister/Inversion/Rejection RNG settings.
- A 240-second elapsed budget is checked before each panel. An in-progress
  reference calculation is allowed to finish. Panels not started within the
  budget are retained as `budget_not_started`; no panel is silently dropped.

## Independent reference and precision checks

Binary and ordinal references use base R adaptive integration, separately for
each item's one-dimensional Gaussian random effect. The probability functions
use base R distribution functions; they do not call package response, gradient,
Hessian, mode, or covariance-factor routines. Two integrations use relative
tolerances 1e-8 and 1e-11 (absolute tolerances 1e-12 and 1e-15). Their aggregate
NLLs must differ by at most 1e-7, every integral must be finite and positive, and
every integration status must be `OK`. Reported integration error estimates are
retained; they are numerical estimates, not rigorous error bounds.

Nominal references integrate the two independent standard normal coordinates
after an independently constructed Cholesky transformation. Tensor
Gauss-Hermite nodes and weights come from the symmetric tridiagonal standard
normal Jacobi matrix, with no additional package dependency. Orders 41, 81,
161, and, if required, 321 and 481 are tried. Agreement of the latest two
aggregate NLLs within 1e-7 defines a precision-converged reference. The initial
41-versus-81 comparison is always followed by order 161 to reduce premature
agreement. This refinement is evidence of numerical stability, not a formal
error bound. Zero variance instead uses the exact conditional likelihood.

The package is evaluated with fixed generating covariance, known
intercepts/cutpoints, `inner_tol = 1e-9`, and `inner_maxit = 100`. This bypasses
outer optimization and does not establish acceptance of a fitted model. The
package's ordinary data-preparation checks still apply: panels with an
unobserved declared category are retained as engine preparation failures; their
reference likelihood is still evaluated.

## Recorded outcomes and interpretation

`results.csv` retains every planned panel, seed, elapsed time, observed category
counts, package conditional-mode status and gradient, both numerical reference
values, reference refinement details/status, errors/warnings, signed and
absolute NLL discrepancy, and discrepancy per observation. `generated-data.csv`
contains only synthetic observations, so exact panels can be inspected without
regeneration. `summary.csv` gives denominators and descriptive discrepancy
summaries by scenario. There is no pass/fail threshold for approximation
adequacy: an appropriate tolerance depends on the inferential use, which this
study does not establish. Large errors and unavailable comparisons are retained.

Use `Rscript validation-studies/discrete-laplace/run.R` from the repository root.
The optional first argument changes the output directory, enabling replay
without overwriting the checked-in evidence. `metadata.txt` and
`source-hashes.csv` record source commit, working-tree state, code hashes, R
version, platform, RNG, settings, and runtime without private filesystem paths.

The study does not cover crossed random effects, multivariate mixed outcomes,
heterogeneous covariance components, missing data, estimated parameter bias,
coefficient accuracy, or uncertainty intervals. Its results therefore cannot
establish a general operating envelope for the discrete backend.
