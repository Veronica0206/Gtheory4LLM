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

Preflight's bounded audit and no-variation examples retain sampled design
labels and counts (panel examples also retain input row numbers), excluding
individual outcome values and unrelated columns. Outcome profiles retain
aggregate category counts and the declared category labels. These identifiers may
still identify participants or evaluators. `max_examples = 0` omits the audit
examples; it does not remove category labels, aggregate summaries or values
supplied literally in the recorded call's other arguments. The call's `data`
argument is kept only when it is a plain object name: a data frame passed
through `do.call()`, or an inline expression, is recorded as a marker.

Data you pass to `gt_fit()` stays in the R session and in the returned object.
Nothing is uploaded or cached outside the session, and nothing is written to
disk unless you set the environment variable `GTHEORY_DISCRETE_SPECIMEN_DIR`.
With that set, a discrete fit writes a specimen file for each refused start, for
at most eight evaluations its optimizer could not use and at most eight further
solve- or factor-validity events, and for each failed final check, holding the failed
operation's matrix, right-hand side, step and factor, the model parameters, the
evaluation's measurements and the numerical environment. A specimen holds no
observations, but its matrix is a function of them, so treat that directory as
you would a saved fit; `scripts/replay_specimen.R` reads one back. A fitted
object retains the modelled data by default, in `$data`, in the recorded call
when the data were passed by value, and, for Gaussian fits, as summary
metadata inside the retained OpenMx model, so treat a saved `.rds` of a fit
as containing whatever you fitted.
`gt_control(retain = list(data = FALSE))` drops every copy of the observations
when that matters; the installed tests verify this by searching the bytes of a
serialized fit for a sentinel observation. Facet level labels are design
metadata, not observations, and stay in the retained model's prepared
statistics; drop the model as well, or relabel facets before fitting, if the
labels themselves identify people.


## Portable report exports

`gt_report()` selects aggregate model and reporting fields rather than saving
its input objects. It excludes observations, calls, model objects, row examples,
facet-level identifiers and category labels. `gt_export_report()` writes the
result as a standalone HTML file only when requested, protecting an existing
file unless replacement is explicit. Text is escaped, and the export uses no
external resources or scripts. Variable, outcome and source names and aggregate
results remain visible; review these before sharing. This is not anonymization.
Creating a report does not change retention of the original fit or preflight.
