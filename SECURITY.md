# Security policy

This is a statistical modelling package. It runs locally, opens no network
connections, starts no server, and reads only the data you pass it and the
files it ships. The realistic risks are therefore narrow, and so is this policy.

## Supported version

Only the current release receives fixes. See `NEWS.md` for what that is and
`artifacts/manifest.json` for whether it is prepared or published.

## Reporting

Report suspected security problems privately to Jin Liu at
<Veronica.Liu0206@gmail.com> with `Gtheory4LLM security` in the subject. Please
do not open a public issue first.

Include the package and R versions, your platform, and a minimal synthetic
reproduction. **Do not include private annotations, participant text,
credentials, or API logs**; a synthetic example that reproduces the behaviour is
always sufficient and always preferable. Expect an acknowledgement within 14
days. A confirmed problem is fixed in a new version with an entry in `NEWS.md`;
the reporter is credited unless they ask otherwise.

## In scope

- Code execution or file writing triggered by loading a bundled resource,
  fitting a model, or running a documented example.
- A bundled data file or release artifact whose content does not match
  `inst/extdata/manifest.csv` or `artifacts/manifest.json`.
- A release-verification or public-content check that can be made to pass on
  material it should reject.
- Private content reaching the public tree or its reachable history.

## Out of scope

- A numerical result you believe is statistically wrong. That is a correctness
  issue: open a GitHub issue with a reproduction, and see
  [docs/LIMITATIONS.md](docs/LIMITATIONS.md) first for what is known not to be
  established.
- A model that fails to converge, is rejected by numerical acceptance, or
  exhausts memory within the documented dense limits. These are the guards
  working; see [docs/LIMITATIONS.md](docs/LIMITATIONS.md).
- Vulnerabilities in R itself, in OpenMx, or in other dependencies. Report those
  to their maintainers; tell us if this package's pinned version must change.
- Anything requiring an attacker who can already write to your filesystem or
  your R library.

## What this package does with data

Data you pass to `gt_fit()` stays in the R session and in the returned object.
Nothing is uploaded, cached outside the session, or written to disk. A fitted
object retains the modelled data by default, so treat a saved `.rds` of a fit
as containing whatever you fitted; `gt_control(gaussian = list(keep_data =
FALSE))` drops it when that matters.
