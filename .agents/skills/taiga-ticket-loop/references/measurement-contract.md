# Measurement contract

`workflow-measure.ps1` records event timestamps supplied by the caller. Phase
wall time, coordinator observation latency, and worker-reported execution time
are separate fields; an absent worker duration remains unknown. The helper
keeps a bounded recent registry and an append-only local audit stream. Stall
alerts are advisory and never cancel a worker or change its model.

Usage import consumes explicitly selected cumulative snapshots. Exact duplicate
samples are ignored, counter decreases start a named reset segment, missing
counters remain unknown, and snapshots after the run boundary are flagged.
Usage totals are not request counts.

Reports always show role, exact model/effort, and raw usage. Actual monetary or
subscription consumption is shown only when attributable input exists. API
estimates require dated model-specific rates and their source; they never stand
in for ChatGPT allowance. Comparisons require equivalent scope, repository
requirements, and profiles. Raw-token reduction is informative, never a release
gate or an automatic model-selection rule.
