# Gtheory4LLM 0.0.6

- Prepares the package for its first public distribution under GPL-3.
- Bundles eight outcome sets and fifteen codings of three real, publicly
  archived LLM annotation panels. Preserves public-source checksums, CC BY 4.0
  data attribution, response mappings, and the three dataset reference chapters.
  Rebuilding modeling resources accepts explicitly supplied public-source CSVs;
  verification requires no external files or network access.
- Adds `gt_preflight()` to report resolved sources, covariance and random-effect
  dimensions, replication/completeness, resource limits, and supported scales.
- Adds an installed synthetic LLM tutorial completing fitting, diagnostics,
  G/Phi calculation, and an 18-allocation decision study.
- Makes installed example loading independent of ambient workspace variables;
  intentional directory overrides support RDS resources and source CSV files.
- Adds a concise classed fit summary and shared diagnostic fields for selected
  attempts, rejection reasons, natural covariance boundaries, and artificial
  parameter bounds. Existing estimates and numerical acceptance rules are
  unchanged.
- Preserves explicit starting values, fixed optimizer selection across fitting
  attempts, reproducible retry controls, and failed-fit safeguards.
- Requires R 4.5 or later because the supported OpenMx dependency uses an R 4.5 API.
- Adds minimum-R and Windows/macOS compatibility workflows beside the locked
  Linux numerical checks, plus one source-and-artifact release-check entrypoint.

Supported scope remains exact balanced Gaussian likelihood and small-model
first-order Laplace discrete likelihood. Discrete latent random effects remain
Gaussian. Binary/ordinal reliability requires an explicit latent scale;
unordered categorical scalar reliability, observed-score discrete reliability,
joint Gaussian-discrete fitting, bootstrap/jackknife, and general uncertainty
intervals are not implemented. Numerical tests do not establish parameter
recovery, approximation adequacy, or application-wide statistical validity.
