# Offline automation fixtures

Run the self-contained PowerShell 7 harness from the repository root:

```powershell
pwsh -NoProfile -File tests/automation/Test-Automation.ps1
```

The harness uses synthetic state, a local bare Git remote, and no desktop,
Taiga, or production GitHub calls. It covers atomic state recovery, canonical
hashing and JSON shape preservation, mandatory CAS/fencing and
ownership/capacity rules, canonical ticket aliases, v1 registry migration,
uncertain actions, cursor consumption, quiescent pause/cancel reconciliation,
session-control fencing, review correction receipts with failed evidence,
shared versioned review receipt validation, legacy disposition normalization,
exact packet criterion ordering/text, stale review binding, and field-level
format errors, bounded local/author repair routing, separate repair and code
correction counters, contradictory evidence escalation, documentation-delta
assessment, justified check reuse,
dependency cycles, epic evidence, fresh-base branch creation, refresh approval
binding, immutable hash-bound assignment packets and full-context artifacts,
exact-profile/browser/authority preflight, null-hasMore pagination with
authoritative totals, duplicate/contradictory page rejection, coordinator-only
role traces, stable worker identities through corrections, and a verified local
push. Evidence cases also cover immutable record/log hashes, trusted packet and
action metadata, raw exit preservation, expected-red and intentional-shutdown
classification, structured counts, and reported-only provenance. Run one case
while developing with `pwsh -NoProfile -File tests/automation/Test-Automation.ps1 -Only evidence` or `-Only repair`.
A nonzero exit code means a fixture failed.

Story fixtures additionally cover complete child-task scope capture, bounded
progress relay, review-gated version-bound task journals, selective scope
reconciliation, and restart-safe parent lifecycle acceptance. The fixture
`fixtures/child-task-story-lifecycle.json` is synthetic and never contacts
Taiga or GitHub.
