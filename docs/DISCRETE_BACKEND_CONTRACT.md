# Private discrete backend contract

This contract separates the existing dense implementation into response,
matrix, and conditional-mode operations. It is an internal implementation
boundary. The development version exposes backend selection through
`gt_control(discrete = list(engine = "dense"))` or `engine = "sparse"`.
The internal sparse files,
`R/discrete_sparse.R` and `R/discrete_sparse_mode.R`, build on it through the
`Matrix` import and are checked against the frozen studies under
`validation-studies/`. Additional nominal, joint and call support has small-case
tests; those do not replace larger-scale qualification. Gaussian fitting
is unaffected. The existing shared `.gt_d_stop()` helper remains in
`discrete.R` and resolves at call time.

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
existing diagnostic failure list; a non-converged solve's list records
`inner_iterations`, `inner_line_search_failed` and `inner_factor_unavailable`.
A malformed internal input raises an error.

The sparse solver additionally handles rounded function values at a full
Newton step. Its predicted decrease must be positive and the maximum absolute
score must strictly decrease. The small plateau branch requires both the
predicted decrease and absolute objective difference to be no larger than
`32 * eps * max(1, abs(objective))`. Outside that branch, both quantities must
be within `sqrt(eps) * max(1, abs(objective))`; the step also needs the
approximate-Wolfe directional inequalities with delta `1e-4` and sigma `0.9`,
and a candidate score that already meets the unchanged final mode tolerance.
This limited safeguard follows the
derivative comparison in [Hager and Zhang (2005), section 4](https://doi.org/10.1137/030601880);
it does not implement their complete line search or inherit its convergence
claims. The function-value window is a conservative heuristic safeguard, not a
proven evaluation-error bound. Every successful mode still satisfies the
original final score tolerance and both validity checks below. The dense
search is unchanged; identical final requirements do not imply identical
search trajectories.

When a cold sparse solve, from zero modes, ends as a classified convergence
failure (not converged within the iteration budget or the line search, with an
available factor and no validity reason), the sparse evaluator retries that
evaluation once from the last valid conditional mode it produced for the same
fit. The cold solve always runs first and is unchanged, so every evaluation the
cold solve completes is identical with or without the retry. The retry applies
the same tolerances, iteration budget, line search, solve-validity and
factor-validity rules. The two validity invariants below are never rescued: a
cold solve that failed one is not retried, and a retry that fails one is itself
the recorded outcome, marked `inner_warm_started`, with its specimen and its
cold attempt's measurements. A retry that merely does not converge leaves the
cold failure as the recorded outcome. Invalid responses and unavailable
factors are not retried. A rescued evaluation is a valid evaluation marked
`inner_warm_started`, with its cold attempt's measurements retained, and the
fit's evaluation record counts such rescues separately from invalid
evaluations. The first evaluation of a fit, and any evaluation made before a
valid mode exists, has no retry. The dense evaluator has no retry.

Both mode solvers enforce the same two validity invariants (issues #14 and
#46). The Newton step is checked against its own system by the shared
backward-error rule `.gt_d_solve_check()`, at the bound
`32 * random_dimension * eps`, immediately after the solve; the sparse solver
applies it to its sparse Hessian without densifying it. The final factor is
probed with the same two fixed vectors before its log determinant enters the
objective; the sparse probe goes through the factor object's permutation-aware
solve in `.gt_d_sparse_final_factor_check()`. A violated invariant returns the
failure list with reason `dense_newton_solve_invalid`,
`dense_final_factor_invalid`, `sparse_newton_solve_invalid` or
`sparse_final_factor_invalid` and, in detailed form, the failed operation as a
`specimen` element. There is no fallback, regularization or looser tolerance.

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

This section describes the dense implementation boundary. The sparse routes,
the rounded-plateau search safeguard and the warm-start retry are specified
above and covered by the tests named there for the cases they list. Nothing in
this document establishes automatic differentiation, large-panel feasibility,
or broader statistical validity; full native-panel qualification and
approximation accuracy remain separate gates.
