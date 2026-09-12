# Real annotation data: attribution and license

The eight RDS resources in `extdata/` are alternative modeling views of three
LLM annotation panels authored by Jin Liu and publicly archived as:

Liu, J. (2026). *LLM Annotation Reliability: A Generalizability Theory Analysis
of Hate Speech, Mental Health, and Drug Review Tasks*. Open Science Framework.
https://doi.org/10.17605/OSF.IO/K9CAJ

The deposit's [data codebook](https://osf.io/download/69e52a44fa0947a9f3fd89c0/)
expressly releases its derived artifacts under **Creative Commons Attribution
4.0 International (CC BY 4.0)**. That data-specific license is retained here.
[License summary](https://creativecommons.org/licenses/by/4.0/) and
[legal terms](https://creativecommons.org/licenses/by/4.0/legalcode.en).
Retain attribution, the license link, and an indication of modifications when
sharing or adapting these data. No warranty or endorsement is implied.

Package modifications consist of selecting modeling columns, representing
design identifiers as factors, assigning explicit response families and category
levels, and providing the documented historical scores and grouped binary flags.
Stored annotation values and preprocessing are preserved. Source-file MD5
checksums match the publicly archived files; resource checksums and source URLs
are recorded in `extdata/manifest.csv` and resource provenance.

Original text sources are HateXplain (Mathew et al., 2021), Sentiment Analysis
for Mental Health (Sarkar), and the Drugs.com review corpus described by
Gräßer et al. (2018). The package does not redistribute source texts, original
human/reference labels, or raw API responses. The data license here covers the
archived derived annotation artifacts, and does not relicense those corpora.
The dataset help topics and `DATASET_REFERENCES.bib` supply the source citations
and corresponding task-specific annotation-study references.

Package code, synthetic tutorial data, and synthetic test fixtures are GPL-3;
see the repository LICENSE. The public OSF project's general license metadata
also lists GPL-3; the explicit data-specific CC BY 4.0 statement above governs
our attribution of the bundled annotation tables.
