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

Run as:

    Rscript profile-medium.R dense  timing
    Rscript profile-medium.R sparse timing
    Rscript profile-medium.R dense  work
    Rscript profile-medium.R sparse work

Peak RSS is a property of the process, so the two passes never share one, and no
backend is measured in a process that also ran the other.
