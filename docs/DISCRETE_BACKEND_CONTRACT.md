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
`discrete.R`. Three source-covariance structures are supported: unstructured
(Cholesky coordinates with a nonnegative diagonal by default, so a singular
source matrix is reached exactly; log-Cholesky on request), diagonal (variance,
Cholesky or log-Cholesky coordinates),
and, for fits with a nominal outcome, exchangeable: each source contributes
`sigma^2 (I + 11')` on a nominal outcome's contrasts and one variance on each
binary or ordinal dimension, block-diagonal across outcomes, in variance
coordinates. Its stationarity check and observed-information map use one
feasible direction per block, the block's shape.

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

Within an L-BFGS-B attempt the sparse evaluator also starts conditional
solves warm, and the fit names each evaluation's role rather than leaving the
evaluator to infer it. The fit supplies the finite-difference gradient itself
(`.gt_d_numerical_gradient()`), written out from `optim()`'s own rule: central
differences with the same steps, each side clipped to its bound with the step
it used. At unit parameter scale, supplying it leaves the optimizer's
evaluations, values and path unchanged; a coarse attempt rerun after a
collapsed first step (below) runs at a parameter scale, where the explicit
rule, differencing in the original coordinates, agrees with `optim()`'s scaled
one to rounding. The optimizer's function evaluations carry the role `warm`: they
start from the attempt's centre mode and become the new centre, whatever
coordinates moved. The gradient's probes carry the role `warm_probe`: they
start from the centre mode and never replace it, and because L-BFGS-B
evaluates the function at a point immediately before that point's gradient,
every probe of one gradient starts from the mode at the point it
differentiates. The conditional objective is strictly concave in the random
effects for every supported family, so the mode is unique and a start changes
only the path to it. The fit resets the evaluator before every attempt, so
each attempt's first solve is cold and no attempt is seeded by another.

Evaluations without a role solve cold from zero modes: the final checks, the
stationarity probes, the information step, and every evaluation of an
optimizer whose finite differences are internal to it (`nlminb` and injected
optimizers), where no role can be named. The classified-failure retry from the
last valid mode, which predates warm starts, still applies to those cold
solves.

L-BFGS-B begins from an identity Hessian, and every discrete coordinate has
two finite bounds, so its first trial point is the start minus the raw
gradient, which is a sum over rows. On the 21,600-row drug-review panel that
put an ordinal fit's item variance near 4,000; every conditional solve there
failed and the attempt stopped at its start after three evaluations. A coarse
attempt (the primary or an alternative start) that ends where it began, within
1e-8 relative, after an invalid evaluation has collapsed this way. It is run
again from the same start at a uniform parameter scale of `1/sqrt(rows)`
(`optim()`'s `parscale`), which makes the first step the per-row gradient.
Later steps take their scale from the curvature the optimizer observes, and the
objective is not rescaled, so the relative-reduction rule (`factr`) is
unchanged. The rerun keeps the attempt's label; the collapsed run is recorded
in its `first_step_rescue` entry. An attempt that moved is never rerun, so no
path that did not collapse changes. Scaling every attempt was rejected: it
changes every path, and on a frozen smoke case it left a tight attempt starting
within 1e-8 of the optimum with no representable decrease, so its line search
ended abnormally. Tight attempts and `nlminb` attempts are not scaled.

A warm solve that stops short of the mode without a validity event is not the
recorded outcome: the cold solve from zero modes runs in its place, with the
warm attempt's measurements retained as `inner_warm_attempt`. A cold solve,
whether the first solve or that fallback, that ends as a classified
convergence failure is then retried once from the last valid mode, unless that
mode is the seed the warm solve already tried. Given the same last valid mode,
an evaluation therefore tries everything the cold path with its retry would
have tried. Under a restrictive iteration budget this matters: a warm solve
from a distant centre and the cold solve can both stop short where the retry
from the nearer last valid mode completes. A probe completed by that retry is
seeded from the last valid mode rather than the centre and is recorded as
rescued. The validity invariants are never rescued in either direction. The
fit's evaluation record counts `warm_started` evaluations and `cold_fallbacks`,
the latter whether or not the evaluation was finally usable, and failure and
rescue records keep the warm attempt.

Warm and cold objectives agree to the precision the inner tolerance leaves
unresolved: within 4.4e-9 at the coarse tolerance and 1.9e-10 at the validation
tolerance on the frozen calibration points and the 21,600-row synthetic panel,
and 1.5e-7 (coarse) against 3.6e-12 (validation) at the native 21,600-row
panel's starting values, whose 9,507 random effects make the log-determinant
term correspondingly more sensitive; every acceptance check runs at the
validation tolerance. The ledger is
`validation-studies/discrete-sparse-profile/warm-start-20261022/agreement.csv`.
The mode solver does not compute the factor's fill counts on its Newton steps;
`.gt_d_sparse_factor()` computes them only when asked.

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
