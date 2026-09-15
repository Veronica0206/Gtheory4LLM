# Fitted smoke study

A frozen contract against which a sparse fitted discrete backend is judged.
Separate from `../discrete-sparse-reference/`, which is a fixed-parameter
reference that runs no outer optimizer.

| File | Role |
| --- | --- |
| `PROTOCOL.md` | the contract: layers, tolerances, cases, dispositions |
| `panels.csv` | authoritative panel rows; loaded, never regenerated |
| `cases.R` | case definitions, shared by the oracle and the later test |
| `freeze-panels.R` | provenance for how `panels.csv` was produced; run once |
| `run-dense-oracle.R` | records the dense baseline and source digests |
| `dense-baseline.csv` | `class` entries are the contract; `provenance` entries are not |
| `source-hashes.csv` | digests of the sources this study depends on |

Read `PROTOCOL.md` before changing anything here.
