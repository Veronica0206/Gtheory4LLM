# Public LLM annotation modeling resources

These eight RDS files preserve fifteen response codings of three real annotation
panels: hate speech, mental health, and drug reviews. Each panel contains 100
items crossed with four evaluators, three prompts, six temperatures, and three
replicate seeds (21,600 measurement rows). Alternative outcome sets reuse the
same items and annotations.

The original annotation CSVs are publicly deposited at
https://doi.org/10.17605/OSF.IO/K9CAJ . Their MD5 checksums exactly match the
source files used for these modeling resources. Each RDS contains its source
URL/checksum, explicit response families and codings, minimal modeling tables,
and portable provenance. Only item/design identifiers and modeled annotations
are included. Raw texts, original corpus labels, and raw API responses are not
included. Historical preprocessing and stored values are preserved.

The data retain the deposit codebook's CC BY 4.0 license; see the installed
DATA_LICENSE.md. Dataset help topics supply source and annotation-study
citations, category mappings, preprocessing notes, and interpretation limits.

From a source checkout, `Rscript --vanilla scripts/build_package_data.R
--verify-only` verifies resources and manifest without network access or
external files. To rebuild, download the three documented CSVs from OSF to a
separate directory and pass `--source-directory PATH` instead. The builder
requires the documented source checksums and preserves the fixed release
snapshot. It does not simulate or invent empirical observations.

The separate installed LLM workflow and numerical test fixtures use synthetic
data. Loading a full real panel does not mean that its discrete model falls
within the package's dense-backend fitting limits.
