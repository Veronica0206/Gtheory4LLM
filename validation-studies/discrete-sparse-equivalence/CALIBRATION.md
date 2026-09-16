# Tolerance calibration plan

Frozen before calibration runs. Calibration runs before any qualification case
runs. The two sets are disjoint on purpose.

## Why calibration is separate

A tolerance chosen from the cases it will later judge is not a tolerance; it is
a restatement of those cases' results. The calibration set below is explicitly
**non-scoring**: no case in it produces a pass, a failure, or an equivalence
verdict, and none of it appears in the qualification record's outcome columns.

## The calibration set

Six cases, disjoint from `EQ_CORE`, spanning the same envelope dimensions so
the calibrated rules are not extrapolated from a narrower regime than they will
judge. Deterministic, no random number generation, non-degeneracy asserted at
construction exactly as in `cases.R`.

    K01  binary  probit  single    diagonal      small        q small
    K02  binary  logit   crossed2  diagonal      medium       q medium
    K03  binary  probit  crossed3  log_cholesky  near_limit   q near 200
    K04  ordinal probit  crossed2  diagonal      medium       interior mass
    K05  ordinal logit   crossed2  diagonal      tail_mass    extreme categories rare
    K06  binary  probit  crossed2  zero_capable  small        exact-zero coordinate

## Quantities and comparison rules

Every rule is quantity-specific. A single blanket tolerance is simultaneously
too loose for a small-magnitude quantity and unachievable for one that grows
with dimension, which is why stage 3 is not scored at a flat `1e-10`.

Stage 3, per quantity, mixed absolute/relative:

    predictor (eta)            normwise, max-abs, relative to max|eta|
    conditional objective      relative
    mode score                 absolute; it is near zero at the mode, so a
                               relative rule is undefined there
    Hessian                    entrywise max-abs, relative to max|H|
    conditional mode           normwise, relative to max|u|, with an absolute
                               floor for coordinates at zero
    log determinant            absolute; it is a sum of q terms and its
                               attainable agreement grows with dimension
    marginal negative log lik  relative, constants included

Stage 4:

    latent G and Phi           its own rule; these are ratios of variance
                               components and their conditioning differs from
                               that of the components themselves

Stage 5:

    equivariance               its own rule; this is a within-backend
                               invariance question under an exact relabelling,
                               so the attainable agreement is not the same
                               quantity as dense/sparse parity

## What calibration produces

A table with one row per quantity and these columns:

    quantity, rule form, observed maximum over the calibration set,
    proposed tolerance, margin (proposed / observed), dimension range observed

The observed maximum is never adopted as the tolerance. Reporting both makes
the margin visible, in the same way the solve-validity bound in #34 was set at
`32 * random_dimension * eps` against a worst healthy observation of
`0.116 * random_dimension * eps`.

## Rules that bind calibration

1. The inherited limits are not recalibrated: `1e-10` fixed-parameter parity
   where that contract already applies, `1e-6` fitted objective, `0.02` fitted
   distance, `32 * random_dimension * eps` solve validity.
2. If calibration appears to require widening any inherited limit, stop and
   investigate. Do not widen it.
3. Calibration observations that violate a backend-neutral validity invariant
   are R1 events. They are excluded from tolerance derivation and reported
   separately; a tolerance must not be set from an arithmetically invalid
   result.
4. The calibration table is committed before qualification begins, in its own
   change against this merged protocol.
