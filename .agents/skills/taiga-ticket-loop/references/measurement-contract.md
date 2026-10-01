# Measurement contract

`workflow-measure.ps1` records event timestamps supplied by the caller. Phase
wall time, coordinator observation latency, and worker-reported execution time
are separate fields; an absent worker duration remains unknown. The helper
keeps a bounded recent registry and an append-only local audit stream. Stall
alerts are advisory and never cancel a worker or change its model.

Usage import consumes explicitly selected cumulative snapshots. Exact duplicate
samples from the same stream/timestamp are ignored, and each sample carries a
stream identity so separate workers or counter resets cannot be conflated.
Counter decreases start a named reset segment. An exact start-boundary sample
is used as the zero point; intervals that straddle the boundary without one
remain unknown. Snapshots after the run boundary are flagged without emitting
post-run deltas. Usage totals are not request counts.

Reports always show role, exact model/effort, and raw usage. Actual monetary or
subscription consumption is shown only when attributable input exists. API
estimates require dated model-specific rates, cache semantics, reasoning
semantics, and their source; incomplete rates remain unavailable. They never
stand in for ChatGPT allowance. Comparisons require explicit quality,
accepted-defect, scope, repository-requirement, profile, and wall-time fields;
missing bindings are not comparable. Raw-token reduction is informative,
never a release gate or an automatic model-selection rule.

Timing summaries read the append-only audit stream when the bounded registry
has evicted older events. Dispatch, worker, and receipt timings are correlated
by action/worker identity when supplied; ambiguous global matches are reported
as unknown. Repeated bounded waits do not reset the last-progress timestamp and
do not constitute engineering progress or a cancellation signal. A
phase/action with no actual progress beyond its threshold produces an advisory
stall alert.
