# Usage import shape

Usage snapshots are cumulative per explicit `streamId` and exact role/model/effort
stream. The importer keeps schemaVersion 1 output for compatibility, but the
input contract now requires `streamId` for multi-stream exports. A legacy export
may omit it only when every snapshot has the same role/model/effort; it is then
assigned the explicit adapter ID `legacy-single-stream`. Mixed explicit and
missing IDs, or multiple legacy identities, are rejected as ambiguous.

```json
{
  "streamId": "implementer-1",
  "role": "implementer",
  "model": "gpt-5.6-luna",
  "effort": "xhigh",
  "atUtc": "2026-09-30T00:10:00Z",
  "counters": {
    "inputTokens": 150,
    "cachedInputTokens": 60,
    "outputTokens": 30,
    "reasoningTokens": 8
  }
}
```

Snapshots are selected explicitly and must not include message text. Exact
duplicates (same stream, timestamp, and counters) are ignored; equal counters
at different timestamps are retained. An exact start-boundary sample is the
baseline and contributes no pre-run increment. Without an exact boundary,
intervals that straddle the start are marked unknown rather than attributed in
full. Decreases begin a reset segment; absent counters remain unknown. Samples
after the run end are reported as later activity and never included in the
run's attribution. Request counts require separate provenance and are not
inferred from token samples.
