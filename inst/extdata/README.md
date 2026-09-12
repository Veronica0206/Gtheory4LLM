# Synthetic examples for Gtheory4LLM

**Every observation in this directory is synthetic.** The files contain no
source-study records, real LLM outputs, real text, human ratings, clinical
measurements, private analysis results, or information about actual model
performance.

Each of eight outcome sets has a complete 576-row panel: 24 hypothetical items
× 3 generic evaluators × 2 generic prompts × 2 temperature-setting identifiers
× 2 seed identifiers. These are 24 repeated measurements per hypothetical item.
The temperature and seed identifiers do not record actual sampling temperatures
or executed random-number seeds.

| Outcome set | Native representation | Numeric-score compatibility |
| --- | --- | --- |
| `hate_speech` | Ordered NORMAL/OFFENSIVE/HATE, coded 1/2/3 | 1–3 Gaussian working score |
| `mental_health_7L` | Seven-code Gaussian working score | Same score |
| `mental_health_3L` | Three-code Gaussian working score | Same score |
| `mental_health_6flag` | Six binary flags | Same 0/1 values, Gaussian family |
| `mental_health_3group` | Three binary OR groups | Same 0/1 values, Gaussian family |
| `drug_review` | Ordered holistic sentiment, five categories | 1–5 Gaussian working score |
| `drug_review_4aspect` | Four ordered three-category aspects | 1–3 Gaussian working scores |
| `mental_health_nominal` | Seven unordered categories | Unavailable |

Load these resources through `gt_example()`. The legacy argument
`coding = "manuscript"` requests numeric-score compatibility; it does not load
or reproduce any manuscript data or findings. Category mappings are documented
in the installed help topics. The Mental-Health 7L/3L codes are not validated
clinical severity scales, and the flags are not diagnoses.

The public generator is `scripts/build_package_data.R`, authored by Jin Liu
and distributed under GPL-3. It uses only deterministic bounded integer
arithmetic and the package's explicit observation-family constructors. It does
not call a random-number generator, fit a model, access an API, read a source
study, or depend on floating-point distribution functions. The patterns are
toy software examples rather than draws from an estimated scientific model or
a parameter-recovery simulation.

From the repository root:

```sh
Rscript --vanilla scripts/build_package_data.R
Rscript --vanilla scripts/build_package_data.R --verify-only
```

`--verify-only` constructs expected objects in memory and compares them to the
existing RDS files and `manifest.csv`. It never writes or modifies resources.
The manifest records resource checksums and the generator identity; it contains
no hashes or paths from private source data.

The three task-specific annotation papers and three original-corpus references
are retained in `DATASET_REFERENCES.bib` and the installed dataset help topics as
**background motivating these task types**. None supplied any observations for
these examples. The overview is `help("gtheory_datasets", package = "Gtheory4LLM")`.

Loading a panel does not guarantee a supported fit. Use `gt_preflight()` with
the intended source structure and family; the discrete engine has explicit
size limits, and scalar reliability has family- and scale-specific restrictions.
