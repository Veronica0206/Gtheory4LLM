# Engineering profile

Measurement, not qualification. Nothing here is a threshold, an acceptance rule,
or a claim about correctness.

The qualified prototype evidence lives in two frozen studies and is not restated
here:

| Study | Claim |
| --- | --- |
| `../discrete-sparse-reference/` | fixed-parameter algebra, frozen before any sparse implementation |
| `../discrete-sparse-fitted-smoke/` | fitted dense-sparse agreement, frozen before any sparse fitted evaluator |

| File | Role |
| --- | --- |
| `profile-medium.R` | one backend per process; `timing` and `work` modes |
| `results.md` | recorded measurements and the scale-risk specimen |

| `profile-medium.sh` | wrapper that adds external peak RSS |

Reproduce everything, including the headline memory figures, with:

    sh validation-studies/discrete-sparse-profile/profile-medium.sh

Run the R script directly only for the figures that do not need external
measurement:

    Rscript profile-medium.R dense  timing
    Rscript profile-medium.R sparse timing
    Rscript profile-medium.R dense  work
    Rscript profile-medium.R sparse work

Peak RSS cannot be measured from inside the process being measured, so it comes
from an external timing utility whose reported unit differs by platform: bytes
on macOS, kilobytes on Linux. The wrapper prints the raw line and the conversion
so neither has to be taken on trust. Peak RSS is also a property of the process,
so the two passes never share one and no backend is measured in a process that
also ran the other.
