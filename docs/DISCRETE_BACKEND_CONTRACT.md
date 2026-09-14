# Private discrete backend contract

This contract separates the existing dense implementation into response,
matrix, and conditional-mode operations. It is an internal implementation
boundary, with no exported backend selector, additional dependency, or sparse
solver. Gaussian fitting is unaffected. The existing shared `.gt_d_stop()`
helper remains in `discrete.R` and resolves at call time.

## Data and coordinate order

`.gt_d_prepare()` validates the declared outcomes and produces `prep`: `n`
observations, `q` latent dimensions, and one block per outcome. Each block owns
its observation codes, family/link, latent-dimension indices, and fixed-parameter
indices. Outcome preparation and covariance parameterization remain in
`discrete.R`.

Predictors are `n` by `q` matrices. Gradients use R's column-major order: all
observations for the first latent dimension, followed by all observations for
the next dimension. Group lists and covariance-factor lists use the same source
order. Within a source, random coordinates contain all group levels for the
first latent dimension, followed by the remaining dimensions. Covariance factors
map standardized independent normal random coordinates into outcome coordinates.
No sources or zero columns are removed.

## Response kernel

`.gt_d_response_kernel(eta, parameters, prep)` accepts the prepared response
blocks and current predictors. It returns `valid`, and when valid, `nll`, the
vectorized predictor gradient, and a curvature list. Binary and ordinal blocks
supply their latent-dimension index and per-observation diagonal curvature.
Categorical blocks supply nonreference probabilities and dimension indices,
which encode the full multinomial curvature, including off-diagonal terms.

The kernel neither receives a random-effect design matrix nor allocates its
Hessian. Nonfinite likelihood/gradient and invalid diagonal curvature retain
the existing `list(valid = FALSE)` behavior. Stable probability calculations,
threshold transforms, likelihood summation order, and derivatives are unchanged.

## Dense matrix operations

`.gt_d_dense_backend(groups, factors, n, q)` validates dimensions, observed
group-index ranges, integer level counts, and covariance-factor shapes and finiteness. It constructs a
plain list containing `W`, `n`, and `q`, with class
`gt_discrete_dense_backend`. The object contains no mutable environment, mode
cache, parameter state, acceptance flag, or optimization policy.

`.gt_d_dense_hessian(curvature, W, n)` assembles the existing
`I + W' C W` expression, retaining the original block accumulation and final
symmetrization order. `.gt_d_dense_evaluate()` combines a response-kernel result
with this Hessian. It assumes the validated backend and prepared response use
the same coordinates.

The internal `.gt_d_W()` matrix builder and `.gt_d_response(..., W = NULL)`
adapter remain available to existing internal callers. The response adapter
only delegates to the separated kernel and dense assembly; it does not define a
second likelihood implementation.

## Mode and Laplace result

`.gt_d_dense_mode(parameters, prep, backend, control, details = FALSE)` checks
the backend/response dimensions, matrix structure and finiteness, parameter
length, and inner-solver controls. It starts from an explicit zero vector for
every evaluation. It retains the Newton step, Cholesky solves, 30-step line
search, descent criterion, final-mode recomputation, convergence tolerance, and
log-determinant calculation of the existing implementation.

A successful scalar evaluation returns the Laplace negative log likelihood.
With `details = TRUE`, it returns `valid`, `nll`, `mode`, `eta`,
`conditional_nll`, `inner_iterations`, `inner_converged`, `inner_gradient`, and
`random_dimension`. Numerical failures retain the `1e100` scalar penalty or the
existing diagnostic failure list. A malformed internal input raises an error.

`.gt_d_laplace()` remains the orchestration adapter: it decodes covariance
factors, constructs the backend, calls the mode solver, and inserts `factors`
into the successful detailed result in its original position. Outer optimizers,
restarts, bounds, stationarity probes, numerical acceptance, and public output
assembly remain unchanged in `discrete.R`.

## Verification and limits

The ten canonical cases in `tests/package-characterization.R` must retain
their stored numerical tolerances and exact acceptance/source/boundary decisions;
this refactor does not regenerate their baseline. Independent existing tests
cover observation derivatives, direct integration, external likelihood
comparisons, and acceptance behavior. `tests/package-discrete-backend.R` adds
an independent Kronecker-product matrix reference and finite differences of the
scalar joint conditional objective, including multinomial cross-curvature. It
also checks malformed inputs, retained zero columns, deterministic zero-start
modes, and truncated-solver rejection.

This is a dense implementation boundary for subsequent sparse work. It does not
establish sparse equivalence, automatic differentiation, warm starts, large-panel
feasibility, or broader statistical validity. The observation preparation and
covariance routines can be extracted later without coupling that mechanical
move to a new sparse algorithm.
