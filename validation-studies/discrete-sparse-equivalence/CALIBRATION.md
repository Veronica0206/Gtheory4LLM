# Tolerance calibration plan

Frozen before calibration runs. Calibration runs before any qualification case
runs. The two sets are disjoint on purpose.

## Why calibration is separate

A tolerance chosen from the cases it will later judge is not a tolerance; it is
a restatement of those cases' results. The calibration set below is explicitly
**non-scoring**: no case in it produces a pass, a failure, or an equivalence
verdict, and none of it appears in the qualification record's outcome columns.

## The calibration set

Six cases, machine-defined in `cases.R` as `EQ_CALIBRATION`, spanning the same
envelope dimensions so the calibrated rules are not extrapolated from a
narrower regime than they will judge. Deterministic, no random number
generation, non-degeneracy asserted at construction exactly as for the scored
cases.

**Disjoint in data, not only in name.** The calibration geometries
(`EQ_CALIBRATION_GEOMETRY`) differ from the scored ones, so the calibration
panels are different matrices with different digests. A tolerance derived from
the very panels it will later judge is not a tolerance; it is a restatement of
those panels' results.

    case  family   link    structure  covariance    geometry    observations  random dim
    K01   binary   probit  single     diagonal      cal_small    126            14
    K02   binary   logit   crossed2   diagonal      cal_medium   240            34
    K03   binary   probit  crossed3   log_cholesky  cal_limit   1086           188
    K04   ordinal  probit  crossed2   diagonal      cal_medium   240            34
    K05   ordinal  logit   crossed2   diagonal      cal_tail     240            34
    K06   binary   probit  crossed2   zero_capable  cal_small    126            17

K03 reaches random dimension 188, ABOVE the largest scored case (C08 at 187).
The log-determinant rule is explicitly dimension-dependent, so a calibration
that topped out below the scored maximum would extrapolate that rule past the
regime it was measured in.

Their panel digests, observation counts, random dimensions and kernel ranks are
frozen in `fixture-digests.csv` under `set = calibration` and pinned by the
study's test, exactly as the scored fixtures are. The calibration inputs are at
least as frozen as the cases they will be used to judge, because those
observations are what determine the tolerances.

Calibration evaluates at the same three frozen fixed-parameter points as the
scored cases (`EQ_FIXED_POINT_LABELS` and `.eq_fixed_points`) and under the
same frozen controls (`EQ_CONTROL`), which are the current production numerical
policy rather than a more generous budget. K06 places the same named source at
an exact zero as C06 does (`EQ_ZERO_SOURCES`), so the zero coordinate is
calibrated in the regime it will be judged in.

## Quantities and comparison rules

**The formulas are already frozen.** `EQ_METRIC` and `.eq_difference()` in
`cases.R` fix the exact comparison per quantity, including the symmetric
denominator and the absolute floor. Calibration establishes only the tolerance
VALUES to attach to them. A calibration that could also choose the formula
would be choosing the ruler after seeing what it measures.

The same applies to where the comparison happens: `EQ_STAGE3_LATENT_POINT` is
zero, and the stage 1 validity witnesses in `EQ_VALIDITY` carry their own frozen
formulas and bounds, so R1 classification is not a calibration output either.

Every rule is quantity-specific. A single blanket tolerance is simultaneously
too loose for a small-magnitude quantity and unachievable for one that grows
with dimension, which is why stage 3 is not scored at a flat `1e-10`.

Stage 3, per quantity, mixed absolute/relative. The conditional objective and
the marginal negative log likelihood are NOT listed here: they are already
covered by the inherited `1e-10` parity contract from #3 and #30, and the split
is frozen as data in `cases.R` (`EQ_INHERITED_PARITY`,
`EQ_CALIBRATED_QUANTITIES`). Calibration establishes only the quantities that
contract does not cover.

    predictor (eta)            normwise, max-abs, relative to max|eta|
    mode score                 absolute; it is near zero at the mode, so a
                               relative rule is undefined there
    Hessian                    entrywise max-abs, relative to max|H|
    conditional mode           normwise, relative to max|u|, with an absolute
                               floor for coordinates at zero
    log determinant            absolute; it is a sum whose attainable agreement
                               grows with dimension

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
