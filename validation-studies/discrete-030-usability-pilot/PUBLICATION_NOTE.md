# Public evidence inventory

The public checkout includes the independent generator, frozen protocol and
scripts, all 40 generated panels, per-attempt CSV records, aggregate summaries,
source fingerprints and the PNG figure. Every panel matches the pre-fit digest
record, and frozen script bytes remain unchanged.

Local numerical-detail RDS files, execution logs and the generated PDF are
retained locally and excluded from Git. References to these files in the
historical rendering amendment describe those local records. They are not
additional publicly downloadable files. The checked-in CSV tables retain all
attempts, including errors and rejections; no failed attempt was removed or rerun
for publication. The reproducible runner creates these local outputs on a new
execution, whose software environment and results must be recorded separately.

Before the first public commit, `results/environment.txt` had only its installed
library location replaced with `<isolated-validation-library>`. Package and R
versions, RNG settings, BLAS/LAPACK information and session information were
preserved. The original is retained locally with SHA-256:

`d4488ffc227a5cf8af766743c1680277de3d1c221c65eedcb0a7b717ee42f362`

The frozen source, pre-fit hash manifest, numerical CSV records and historical
rendering amendment were not rewritten. This note records the publication
selection and path redaction separately from the original study execution.
