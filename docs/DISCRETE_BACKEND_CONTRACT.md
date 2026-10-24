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
They also retain the maximum category and its complementary probability.
Both backends use that complement for the maximum category's diagonal
curvature, avoiding subtraction from a probability rounded to one. Older
curvature records without the complementary fields retain the original path.

The kernel neither receives a random-effect design matrix nor allocates its
Hessian. Nonfinite likelihood/gradient and invalid diagonal curvature retain
the existing `list(valid = FALSE)` behavior. Threshold transforms and the
first-order Laplace criterion are unchanged. Ordinal log probabilities and
derivatives use complementary tails and factored differences. For a finite
probit interval with half-width at most 0.5 and absolute midpoint times
half-width at most 1, a paired 16-node Gauss-Legendre rule evaluates the
bounded normal-density integral and its centered moments. Scratch matrices
use at most 512 rows per block. This is a stable evaluation of the response
probability, not a higher-order integration over the model's random effects.
Nominal loss and score calculations retain the small complement of the
maximum category through `log1p()` and direct complementary sums. These
repairs do not relax the final acceptance requirements.

## Response third derivatives

For the analytic gradient of the Laplace objective the engine needs, per
observation, the third derivative of the loss in its linear predictor and, for
ordinal blocks, the partials of loss, score and curvature in the block's stored
threshold coordinates. `.gt_d_ordinal_interval(lo, hi, link, third = TRUE)`
returns them beside the existing log probability, score and curvature, computed
inside the same regime branch that produced the curvature: the closed logistic
forms, with the paired `sinh`/`cosh` form on crossing intervals so that a
near-symmetric interval's small value is not a difference; the closed probit
forms, with a crossing interval's two endpoint terms taken through the score
and `4 a c r_L`; the 16-node rule's third moment on narrow probit intervals;
and, on same-side probit intervals and one-sided tails, a tilted-exponential
quadrature of the first three moments in `u = s (z - L) >= 0`, `s = max(1, L)`,
on fixed panels of `u` up to 64, because the closed form of the third cumulant
cancels three leading orders in a far tail. The existing outputs are byte for
byte what they were without the request; the tail tests and the
characterization baseline hold that. In the engine's convention the endpoints
are already shifted by the linear predictor, so a partial in `lo` or `hi` is
the partial in that cut; an infinite endpoint has none.

The paired logistic third derivative divides by `cosh(half)^3` algebraically
before multiplication. With `r = cosh(center)/cosh(half)` and
`s = sinh(center)/cosh(half)`, it evaluates
`s * (2/cosh(half)^2 + r - 1)/(1 + r)^3`. On the existing crossing branch,
`abs(center) < half < 300`, so the ratios and remaining products are bounded.
This avoids overflow on wide intervals admitted through an explicit threshold
gap override; the default maximum gap and the branch selection are unchanged.

`.gt_d_response_third(eta, parameters, prep, response)` applies this to a
kernel result. Binary blocks are the one-cut interval at zero, `(-eta, Inf)`
for an event and `(-Inf, -eta)` otherwise; the closed Mills-ratio form
`r [1 - (r + m)(2r + m)]` is exact in algebra but loses its bracket, of order
`2 / m^4`, to the rounding of `log Phi(m)` in a far tail. Ordinal blocks map the
endpoint partials to stored coordinates: the first stored cut shifts every
finite cut, which is the opposite of shifting `eta`, so its derivatives are
minus the location derivatives; a log gap scales the shift of every cut from
its own onwards by `exp(gap)`, so categories above it receive the common shift,
its own category the upper-endpoint partial, categories below nothing. Nominal
blocks carry no scalar third derivative; their contraction uses the
probabilities the kernel already returns. A row whose curvature the kernel
tolerated below zero, which the Hessian assembly replaces by zero, has no
derivative of the assembled matrix, so the block is refused with
`clipped_curvature` rather than differentiated as if unclipped; an invalid
kernel result refuses with `invalid_response`, a nonfinite value with
`nonfinite_third_derivative`. No fit calls either function yet.

`tests/package-response-third.R` holds the campaign's 108 fixed intervals with
their 160-digit references for all ten quantities, finite differences of the
kernel's own score and curvature in the predictor and in each stored threshold
coordinate, the binary one-cut identity with 60-digit far-tail references, the
refusals, and the identity of the existing outputs. Twenty additional exact-double
logistic intervals have independent 180-digit references: the finite-zero and
nonfinite overflow witnesses, their mirrors, wide symmetric and near-symmetric
intervals, and adjacent points across the paired-branch transitions. Wide-gap
first-threshold curvature partials also agree with the response kernel's finite
differences at three step sizes under the existing tolerances.

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
evaluations, values and path unchanged. At a parameter scale other than one (a
coarse attempt rerun after a collapsed first step, below, or
`optimizer_scaling = "start"`) the explicit rule deliberately keeps its
physical steps in the original coordinates, whereas `optim()`'s own rule would
difference in the scaled coordinates with `ndeps` applied there; the two
differ by their truncation errors, so the scaled attempt's path is that of the
explicit gradient, not a reproduction of the implicit one. The optimizer's
function evaluations carry the role `warm`: they
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
in its `first_step_rescue` entry, including the complete `collapsed_attempt`.
Only an available finite optimizer result without an error is eligible; an
exception or unusable result remains a failed attempt and cannot be replaced
by a successful rescaled run. An attempt that moved is never rerun, so no
path that did not collapse changes. Scaling every attempt was rejected: it
changes every path, and on a frozen smoke case it left a tight attempt starting
within 1e-8 of the optimum with no representable decrease, so its line search
ended abnormally. Under the default `optimizer_scaling = "none"`, tight
attempts and `nlminb` attempts are not scaled.

An explicit `optimizer_scaling = "start"` request uses L-BFGS-B with
`parscale = pmax(1, abs(attempt_start)) / sqrt(rows)` for every coarse and
tight attempt. This fixed metric balances relative coordinate sizes and
the row-summed objective; it is recomputed only when a new attempt begins.
It is retained in each attempt's `optimizer_control$parscale`. Original-coordinate
finite-difference steps remain unchanged because the gradient is supplied
explicitly. The objective, tolerances, independent cold stationarity checks,
bound-contact rules and all-candidate stability requirements are unchanged.
The collapsed-first-step rescue is disabled under this explicit policy: a
failed attempt remains failed rather than silently switching metrics. The
policy is refused with `nlminb`. It is an opt-in search control, not evidence
that a model is identified or a fit is accepted; defaults remain unchanged.

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

## Sparse working-memory estimate

The sparse engine's guard against `max_sparse_bytes` is evaluated before any
random design is built, in two stages that allocate nothing the fit would not.
The complete-fill bound of `.gt_d_sparse_bytes()`, which assumes fully populated
source factors and a dense conditional Hessian and factor, is kept whenever it
already fits the budget. Otherwise `.gt_d_sparse_pattern_entries()` counts the
structural nonzeros of the conditional Hessian exactly: two coordinates are
coupled only when their groups share an observation, so the pattern holds one
`q`-by-`q` block per level of every source and one per observed pair of levels
of two distinct sources, in both triangles; the observed pairs are counted from
the group indices. If that count alone exceeds the budget the request is
refused with method `pattern_exceeds_budget` and no pattern is built. If it
does not, `.gt_d_sparse_resources()` builds the structural pattern through
`.gt_d_sparse_W()` with every factor entry set to one, so that every latent
dimension of an observation is coupled and the pattern contains the pattern of
any conditional Hessian the fit can assemble, factorizes `I + W'W` once through
`.gt_d_sparse_factor()`, and charges twelve bytes per counted Hessian and factor
entry alongside the design and predictor arrays. The counted Hessian entries
equal the exact count. The counted factor entries are a planning estimate, not
a bound: the fit computes its own fill-reducing ordering on the fitted matrix,
whose pattern is a subset of the structural one, and a different ordering can
fill slightly more or less than the structural factor did; the planning
multiplier is the allowance for that difference and for what the estimate
omits (caller data, optimizer state, the repeated allocation of the
finite-difference checks). The method and the counts are reported by preflight
and recorded in the fit's resource estimate. A feasible factorization
establishes neither numerical acceptance nor approximation accuracy at that
size.

## Compiled selected inverse

`src/gt_selected_inverse.c` computes selected entries of the inverse of a
sparse conditional Hessian from its Cholesky factor, for the analytic gradient
of the first-order Laplace objective: the gradient needs `tr(H^{-1} H_j)` for
every parameter derivative `H_j` and, per observation, the block
`W_i H^{-1} W_i'`, and the dense inverse is never formed. The routines are
reached through registered `.Call` entry points only (`useDynLib(...,
.registration = TRUE)` with dynamic symbol lookup disabled) and wrapped by
`R/selected_inverse.R`; no fit uses them yet.

Input is the permuted lower factor `L` with `H[perm, perm] = L L'`, exactly as
`.gt_d_sparse_factor()` returns it, in compressed sparse column storage with
each column's diagonal entry first and strictly increasing row indices. The
compiled code validates every argument again: types, lengths against the
declared caps in a wide integer type before any narrowing, pointer
monotonicity, the position and positivity of each diagonal, finiteness.
`.gt_selected_inverse()` returns the inverse's entries on the factor's own
pattern, the permutation and its inverse, and the platform's arithmetic widths.
`.gt_selected_entries()`, `.gt_selected_trace()` and
`.gt_selected_contractions()` take and return original coordinates; the
permuted positions never leave the wrapper.

The recurrence visits columns from the last to the first and accumulates in
long double in ascending neighbour order, so results agree across platforms to
the precision the narrower long double leaves, not bit for bit; the recorded
`long_double_mantissa` says which. An entry outside the factor's pattern is a
refusal, never a zero: a derivative of `H` can be nonzero where `H`'s current
entry is zero, and the structural envelope the gradient will factorize must
cover every entry it reads. Nonpositive or nonfinite pivots, nonfinite results
and every declared cap (dimension, fill, recurrence products, query count,
observations, local width, latent dimensions, contraction work) refuse by name;
`.gt_selected_caps()` reports the caps. They bound allocation and work before
anything is allocated and are not estimates of what a machine can afford.

`tests/package-selected-inverse.R` checks every selected entry, both-triangle
queries, traces against the matrix and against derivative matrices with
structural-zero entries, and the contractions against dense inverses on eight
reference matrices under two coordinate orders with and without a
fill-reducing permutation; the engine's own sparse Hessian geometry through
`.gt_selected_local_index()` and `.gt_selected_local_design()`; thirty refusals;
the cap boundaries; and collector safety under `gctorture()`.

## Structural envelope and the analytic gradient at a fixed point

The analytic gradient of the Laplace objective reads entries of `H^{-1}`
wherever a derivative of the conditional Hessian can be nonzero, and a
derivative can be nonzero where `H`'s current entry is zero. The structural
envelope (`R/discrete_sparse_envelope.R`) is the pattern of `I + W'W` with every
factor entry set to one, built once per design by `.gt_d_sparse_envelope()`
from the sparse context: it couples every latent dimension of an observation
and every source's coordinates for that observation to every other's, it is
the pattern the working-memory estimate factorizes, and it contains the pattern
of every numeric Hessian the design can produce. At an evaluation
`.gt_d_sparse_envelope_factor()` overlays the numeric `H` on it, explicit zeros
kept, factorizes the overlay and checks it before it is used: `H`'s own pattern
inside the envelope, the probe solves under the shared backward-error rule,
and the log determinant within `1e-8 * max(1, |log det|)` of the production
factor's. A failed check refuses by name (`envelope_mismatch`,
`envelope_not_positive_definite`, `envelope_factor_invalid`). The production
mode, value and factor are never replaced.

`.gt_d_gradient()` (`R/discrete_gradient.R`) assembles the gradient in stored
coordinates at a valid detailed evaluation: for coordinate `theta_j`,

    L_j = f_{theta_j} + tr(H^{-1} H_{theta_j}) / 2 - a' f_{u theta_j},
    a = H^{-1} z,  z_k = tr(H^{-1} H_{u_k}) / 2,

the last term being the log determinant's dependence on the mode. Per
observation only the block `Q_i = W_i H^{-1} W_i'` is needed, from the compiled
selected inverse on the envelope factor and the local contractions of
`R/selected_inverse.R`; with `v_i` the half-contraction of `Q_i` with the
curvature's derivative in the predictor (`.gt_d_response_third()` for binary
and ordinal rows, `C_i (diag Q_i - 2 Q_i p_i) / 2` for nominal rows), `z = W'v`,
`t = W a` and `r_i = g_i + v_i - C_i t_i`: an intercept of dimension `d` is
`sum_i r_i[d]`; an ordinal threshold coordinate is
`sum_i { loss_theta - t_i[d] score_theta + Q_i[d, d] curvature_theta / 2 }`;
a natural Cholesky entry `L_s[a, b]` with the observation's coordinate `k` is
`sum_i { r_i[a] u[k] - g_i[a] a[k] + (C_i W_i S_i)[a, k] }`. Log-Cholesky
diagonals, direct variances and exchangeable variances follow by the chain
rule; at an exact zero the square-root maps are one-sided and the evaluation
is refused (`unsupported_coordinate_at_zero`). The adjoint solve goes through
the production factor and its backward-error check (`adjoint_solve_invalid`).
Every refusal names its reason; a zero gradient never stands in for a failure.
`.gt_d_laplace_problem()` is the fit's prologue for fixed-point tools and
tests, without the fit's resource guards. No fit calls any of this yet; the
objective, the conditional mode and the acceptance rules are unchanged.

`tests/package-sparse-envelope.R` checks the envelope against the preflight's
counts, the overlay at nonzero, zero-off-diagonal and zero-pivot points, the
coverage of every local block, and the refusals. `tests/package-discrete-gradient.R`
checks the gradient against central finite differences of the objective, cold
at a tight inner tolerance, on thirteen fixtures across families, links,
joint outcomes and every covariance parameterization, with three-point
forward differences at natural boundaries, negative controls that drop the
implicit-mode and log-determinant terms, convergence as the inner tolerance
tightens, and the refusals.

## Declared numerical domains

`parameter_bounds` optionally supplies partial named `lower` and `upper`
overrides after observation and covariance coordinates are resolved. The
shared resolver is used by fitting, preflight and retained Laplace checks.
Defaults are unchanged. Natural variance and ordinary Cholesky diagonal lower
bounds stay zero; finite ordered domains must retain distinguishable positive
ordinal gaps and finite covariance factors and summed variances. There is no
automatic expansion, start projection, altered likelihood or looser acceptance.
The requested, default and effective domains are retained in
`diagnostics$parameter_domain`. The existing `parameter_bounds` diagnostic
continues to list artificial contacts, and any such contact prevents acceptance.
A changed domain is a declared new numerical protocol, not evidence that a
previously refused model is identified or its approximation adequate.

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
