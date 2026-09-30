# Usage import shape

Usage snapshots are cumulative per exact role/model/effort stream:

```json
{
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

Snapshots are selected explicitly and must not include message text. Duplicate
counter samples are ignored; decreases begin a reset segment; absent counters
remain unknown. Samples after the run end are reported as later activity and
never included in the run's attribution. Request counts require separate
provenance and are not inferred from token samples.
