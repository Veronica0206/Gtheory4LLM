# Post-run rendering amendment (2026-10-03 America/New_York)

The single predeclared campaign completed all 40 fits in 11.704089 seconds.
The initial R summary process returned success and wrote all numerical tables
and the PDF, but its Cairo PNG device issued a missing-X11-library warning and
produced no PNG. This was a rendering failure, not a fit or analysis failure.
The original warning is preserved in `results/logs/summary.log`; the original
execution record remains in `results/execution-initial.json`.

The pre-fit scripts, including that original renderer, are retained verbatim in
`results/frozen-source/` and match `results/study-source-files.csv`. After the
campaign, the renderer's single device-selection expression was changed to use
Quartz on an Aqua-enabled R installation and Cairo otherwise. The runner now
also checks that all required summary files exist, so a future silent graphics
warning cannot be labelled a complete summary. No protocol, panel, seed,
execution order, model, control, acceptance decision, summary formula, or
numerical table changed. No fit was rerun.

Only the summary/rendering script was run again on the existing attempt table;
its final log is `results/logs/render-completed.log`. The resulting PNG was
visually inspected. Current script hashes are retained separately in
`results/postrun-source-files.csv`; the pre-fit freeze is not rewritten.
