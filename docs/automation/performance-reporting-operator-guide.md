# Story performance reporting operator guide

This guide turns the versioned performance contract into a safe operator
runbook. It is the Task #160 documentation artifact for epic #140 and story
#145. The examples are sanitized synthetic fixtures; they are not live Taiga,
GitHub, Codex, provider, token, or release evidence.

The contract and capability boundary remain authoritative in
[`performance-reporting.md`](../../.agents/skills/taiga-story-loop/references/performance-reporting.md).
This guide explains where evidence comes from, where it is stored, how to
recover it, and how to report missing telemetry without changing workflow
authority.

## Evidence states and safe interpretation

Use the state supplied by the source. Never turn an unknown value into zero.

| State | Meaning | Operator action |
| --- | --- | --- |
| `measured` | The required boundaries or counters are source-backed, attributable, and complete for the stated coverage. | Keep the source, calculation, unit, and coverage with the value. |
| `partial` | Some evidence exists, but a boundary, reset segment, semantic rule, task identity, or other required part is missing or ambiguous. | Preserve a covered subtotal only when the report contract supports it (for example, valid elapsed intervals); keep incomplete token/task totals `null` and name the missing coverage. |
| `unavailable` | No authoritative source was available for the metric. | Keep the value `null`, record the source and reason, and continue the workflow. |
| `not_applicable` | The metric has no valid denominator or does not apply to the selected mode. | Do not convert it to zero or failure; retain the applicability explanation. |
| `synthetic_fixture` | A deterministic test or example, not an observation. | Use it to prove contract behavior only. Never present it as a host run. |

For token reporting, account-level limits, message length, file size, agent
count, polling count, and review count are not worker-token measurements. A
partial or unavailable token metric is a valid result. Preserve role, worker,
model, effort, stream, baseline, and coverage provenance separately from the
numeric value.

## Known sources and current capability boundary

| Source | Evidence it can support | Important limitation |
| --- | --- | --- |
| Version-2 event ledger at `events.jsonl` (version-1 remains cold-only) | Authoritative lifecycle identities, UTC transition boundaries, review attempts, explicit usage samples, and provenance. | It records only what the caller supplied; host-counter discovery is a separate incremental metadata collector. |
| Observed-role token usage metadata | Attributable cumulative Codex session counters sampled at story boundaries. | It requires bound session evidence, complete-line coverage, known counter semantics, and reset-free deltas; account limits are never a substitute. |
| Validated setup metadata | Role, worker/session identity, model, reasoning effort, effective time bounds, and profile changes. | Setup provenance is not usage telemetry. Missing setup metadata remains unavailable. |
| Git base-to-reviewed-HEAD comparison | Changed files and line counts for an exact base and full reviewed HEAD. | A missing or invalid base/HEAD makes the comparison metric unavailable; no complexity score is inferred. |
| Current Codex App/tool metadata | Capability and identity/status observations such as supported profiles or a bounded thread listing. | The inspected account-limit schema is shared-account data, not worker attribution; the bounded thread and goal probes did not expose per-worker token counters. |

The dated capability discovery is recorded in the reference linked above. Its
API probes did not expose per-worker counters, while the separate observed
session collector can use authorized local JSONL evidence when role/session
binding, counter semantics, and boundary coverage are explicit. The observed
host metadata and synthetic unavailable/partial examples remain labeled by
their evidence class; do not promote either into live usage telemetry.

## External storage, recovery, and cleanup

The recorder owns one run directory outside the source worktree:

```text
<external-run-root>/<runId>/
  events.jsonl
  events.jsonl.diagnostics.jsonl
  events.jsonl.checkpoint.json
  events.jsonl.bloom
  events.jsonl.index/       # one hashed event-index entry per event identity
  events.jsonl.membership/  # event-membership markers
  events.jsonl.identity/    # committed identity claims with ledger ranges
  events.jsonl.authority/   # bounded authoritative ledger-range claims
  events.jsonl.catalog/     # integrity-checked exact event-ID witnesses
  events.jsonl.integrity/   # authenticated event-ID trie and v2 content-chain digest
```

The lock is transient and is also owned by the run directory. Reports are
immutable external artifacts. A report identity is bound to the run,
project/story, PR identity, and exact reviewed HEAD; a newly reviewed HEAD
gets a new retained report instead of overwriting the previous one.

Recovery rules are deliberately conservative:

- Complete JSONL lines are authoritative and are never rewritten to repair a
  tail or sidecar. The authority claim records the first complete ledger range;
  index, membership, and identity entries are repairable projections. A
  committed claim is used only after its stored line/start/end range is read
  directly from the complete ledger and its event ID, binding, and canonical
  payload match.
- New runs use v2 frames: the canonical v1 event is wrapped with an acyclic
  commit anchor binding the previous anchor, orphan suffix digest, canonical
  event digest, content-chain digest, exact frame byte length, record ordinal,
  and trie root. The durable frame is published before derived projections.
  The current committed head is found from a bounded tail read, not from a
  historical checkpoint offset.
- Version-1 raw ledgers are readable but cold-only. They are not implicitly
  migrated or reset; the recorder preserves their legacy append format.
- An interrupted tail, invalid record, foreign binding, duplicate, or
  conflicting event is surfaced through safe diagnostics containing identity,
  line/offset, length, and digest information rather than raw payload text.
- Replaying the same event ID with the same canonical payload is a no-op. A
  changed payload is a conflict; the first complete record remains
  authoritative.
- Missing, stale, truncated, or corrupt checkpoint/index/membership/identity/
  authority/catalog/integrity/Bloom state causes a cold reconstruction from
  the existing ledger when the affected state cannot be repaired from a
  validated complete range. The catalog remains an integrity-checked,
  hash-addressed exact event-ID witness. The checkpoint-anchored integrity
  trie is the exact bounded membership/absence proof: if it knows an event but
  all mutable per-event projections are absent or renamed, the recorder
  cold-rebuilds instead of treating the event as unseen; a missing or corrupt
  trie node also forces cold recovery. A valid absence proof leaves an unseen
  Bloom-positive event eligible for the ordinary incremental append path.
  Pending identity claims are reconciled with complete authority before replay
  decisions. That recovery path is bounded by the existing ledger bytes and
  valid records, then pays its ordinal identity grouping, line/start-offset
  ordering, canonical-payload deduplication, and
  index/membership/identity/authority/catalog/integrity-trie/Bloom rebuild
  costs. Normal append paths do not repeat that full ledger reconstruction.
- A Bloom positive is only a hint. A valid authenticated trie absence proof
  permits the unseen event to append through the ordinary incremental path;
  healthy Bloom collisions must not make recording unavailable. A missing or
  corrupt proof path is recovery evidence, not proof of absence, and causes a
  cold rebuild. A malformed or range-unverifiable committed claim is likewise
  repaired from the ledger or returned as a safe error.
  `ledgerReadBytes` includes successful and partially consumed failed bounded
  range validations, including the identity/index reads on exact replay and the
  extra validation performed during cold recovery.
- The v2 checkpoint and authenticated trie root bind the committed content-chain
  digest and record count. Physical length remains a frame/offset fact rather
  than trie content. A stale/intermediate/alternate root, malformed or
  incomplete suffix, or later complete suffix growth is recovery evidence and
  cannot authorize incremental catch-up; orphan bytes may be bound into the
  next committed frame. Synthetic validator results also report
  `integrityNodeReadCount`, `integrityNodeReadBytes`,
  `integrityNodeWriteCount`, and `integrityNodeWriteBytes`; retain those values
  as implementation-cost evidence rather than treating them as a production
  SLA.
- A measurement or report I/O failure does not invalidate a successfully
  completed implementation, review, or PR-readiness transition. Reconcile
  before considering any retry; never blindly replay an ambiguous write.

### Constructing live UTC boundaries

Production transition events and setup/profile metadata must share one captured
UTC instant and the repository's canonical formatter. From the repository
root, use:

```powershell
. (Join-Path $repoRoot 'scripts/format-story-performance-utc.ps1')
$capturedBoundary = [DateTimeOffset]::UtcNow
$boundaryUtc = Format-StoryPerformanceUtcTimestamp -Timestamp $capturedBoundary
```

Pass `$boundaryUtc` to `occurredAtUtc` and, when a profile begins at that
boundary, to `effectiveFromUtc`. The formatter emits literal `Z` and preserves
the captured instant. A direct `DateTimeOffset.UtcNow.ToString('o')` emits
`+00:00`, which the recorder and report generator reject; existing historical
timestamps are never silently rewritten.

### Bounded historical reporting recovery

When a retained ledger contains a validated, narrowly scoped field-shape defect
that prevents an otherwise attributable report, recover the report through an
explicitly labeled temporary view or in-memory projection. This is a reporting
recovery, not a ledger repair or migration:

- Hash and size the authoritative `events.jsonl` before the audit, and repeat
  the check after reporting. A changed hash, length, or line count is a hard
  stop.
- Preserve JSON string representations while building and comparing the view.
  In PowerShell, parse with `ConvertFrom-Json -DateKind String` (or an
  equivalent string-preserving parser) so timestamp text such as trailing
  fractional-second zeroes is not silently reserialized. Compare all events in
  order and all fields, allowing only the four explicitly authorized field
  substitutions.
- Validate every proposed record against its run/project/story/task identity,
  event type, phase, request and attempt identities, ordinal, correction link,
  UTC boundary, and revision. Require the matching correction boundaries and
  review start/closure records before normalizing anything.
- Copy only the retained event data into a disposable, clearly named reporting
  view. Change only the explicitly validated fields; preserve every other field
  and event in order. Do not write the view back to the authoritative ledger or
  its sidecars, and do not publish it as a replacement report without labeling
  the source and normalization.
- Run the normal reporter with the declared ordered task set. Record each
  normalized event ID and before/after value, before/after metrics, every
  anomaly, the temporary-view boundary, and the authoritative-ledger hash
  comparison. Keep legitimate warnings such as overlapping intervals; only
  remove the validated defect from the temporary view.
- If identity, correction linkage, timestamps, revision evidence, or the
  before/after hash check is incomplete, stop with precise partial/unavailable
  coverage. Do not infer missing reviews, rewrite immutable history, or build a
  generalized migration from a one-off recovery.

Retain the sanitized report, command output, exact reviewed SHA, and the
review handoff evidence required by the task or story. Remove only a unique,
disposable external run root created by the current smoke or fixture run.
Never remove the repository, an operator-selected shared root, retained
historical reports, or a run whose ownership is unclear.

## Safe command examples

These commands use synthetic event content and a unique temporary root. They
do not require Taiga credentials, do not start a service, and do not write
live provider state. A real report run replaces the synthetic event with the
already-recorded external ledger and keeps the same external-path rules.

```powershell
$repoRoot = (Resolve-Path '.').Path
$externalRunRoot = Join-Path ([IO.Path]::GetTempPath()) ('TaigaMCP-story-performance-' + [guid]::NewGuid().ToString('N'))
$runId = 'synthetic-story-145'
$runDirectory = Join-Path $externalRunRoot $runId
$eventsPath = Join-Path $runDirectory 'events.jsonl'
$reportDirectory = Join-Path $externalRunRoot 'reports'

New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null

$eventJson = @'
{
  "schemaVersion": 1,
  "kind": "story_performance_event",
  "eventId": "synthetic-story-145-start",
  "runId": "synthetic-story-145",
  "projectId": 999,
  "storyId": 998,
  "storyRef": 145,
  "taskRef": null,
  "role": "coordinator",
  "sessionId": "synthetic-session",
  "workerId": "synthetic-worker",
  "transitionId": "synthetic-story-start",
  "scope": "story",
  "phaseId": null,
  "correctionId": null,
  "reviewRequestId": null,
  "reviewAttemptId": null,
  "reviewKind": null,
  "reviewAttemptOrdinal": null,
  "supersedesReviewAttemptId": null,
  "eventType": "story_started",
  "occurredAtUtc": "2026-10-09T10:00:00Z",
  "revision": null,
  "reviewMode": "per_task",
  "provenance": {
    "source": "synthetic_operator_example",
    "observedBy": "operator",
    "coverage": "synthetic",
    "synthetic": true
  },
  "usage": null
}
'@

& pwsh -NoProfile -File (Join-Path $repoRoot '.agents/skills/taiga-story-loop/scripts/write-performance-event.ps1') `
  -ExternalRunRoot $externalRunRoot -RunId $runId -EventJson $eventJson

& pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/get-story-performance.ps1') `
  -EventsPath $eventsPath -ReviewMode per_task `
  -OutputPath (Join-Path $reportDirectory 'synthetic-report.json') `
  -MarkdownPath (Join-Path $reportDirectory 'synthetic-report.md')
```

For a complete source-backed report, use the real ledger, the declared ordered
task references, the exact base and reviewed HEAD, and validated setup
metadata. Keep the report paths outside the repository:

```powershell
& pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/get-story-performance.ps1') `
  -EventsPath $eventsPath -ReviewMode per_task -TaskRefs @(158, 159, 160) `
  -BaseRevision '<full-base-sha>' -ReviewedHead '<full-reviewed-head-sha>' `
  -RepositoryPath $repoRoot -MetadataPath '<external-setup-metadata.json>' `
  -OutputPath (Join-Path $reportDirectory 'story-report.json') `
  -MarkdownPath (Join-Path $reportDirectory 'story-report.md')
```

When the observed-role evidence file names local Codex session JSONL sources,
update the collector cursor and report its metadata alongside the story report:

```powershell
& pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/collect-role-token-usage.ps1') `
  -ObservedEvidencePath '<external-observed-role-token-usage.json>' `
  -EventsPath $eventsPath `
  -StatePath '<external-role-usage-cursor.json>' `
  -OutputPath '<external-role-usage.json>' `
  -Scope '<story-or-run-scope>'

& pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/get-story-performance.ps1') `
  -EventsPath $eventsPath -UsageMetadataPath '<external-role-usage.json>' `
  -OutputPath (Join-Path $reportDirectory 'story-report.json')
```

The collector reads only new complete lines after the saved byte cursor on
subsequent runs. It verifies each real local source with its
`session_meta.payload.id`, reads cumulative counters from `event_msg` records
whose `payload.type` is `token_count` and whose counter is
`payload.info.total_token_usage`, detects file or counter resets, subtracts
boundary snapshots once per disjoint session, and
marks nearest-line or incomplete boundaries as partial. It never sums
cumulative notifications, uses account-limit windows, or exports prompt text.

Run the deterministic checks from the repository root:

```powershell
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-performance-reporting.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-performance-overhead.ps1
git diff --check
```

After retaining the report and evidence, clean only the unique fixture root:

```powershell
Remove-Item -LiteralPath $externalRunRoot -Recurse -Force
```

The validators create and remove their own unique disposable roots. Do not
reuse a shared root, and do not stop a running server to release an output
lock.

## Sanitized sample reports

The following compact objects show the reporting rule, not a complete ledger.
Every numeric value, identity, timestamp, and SHA is synthetic. Real reports
retain the full metric set and the exact source/coverage/calculation fields.

### Complete source-backed coverage

```json
{
  "schemaVersion": 1,
  "kind": "story_performance_report",
  "reportId": "synthetic-run-complete-pr-head-0123456789abcdef0123456789abcdef01234567",
  "runId": "synthetic-run-complete",
  "projectId": 999,
  "storyId": 998,
  "storyRef": 145,
  "reviewMode": "per_task",
  "pullRequest": {
    "provider": "github",
    "owner": "example",
    "repository": "synthetic-repository",
    "number": 321,
    "reviewedHead": "0123456789abcdef0123456789abcdef01234567"
  },
  "metrics": {
    "timeToPr": { "state": "measured", "value": 900000, "unit": "milliseconds", "source": "story_started -> pr_ready", "coverage": "both boundaries present" },
    "implementationElapsed": { "state": "measured", "value": 420000, "unit": "milliseconds", "source": "implementation phase boundaries", "coverage": "all paired intervals valid" },
    "reviewElapsed": { "state": "measured", "value": 180000, "unit": "milliseconds", "source": "review attempt boundaries", "coverage": "all attempts closed" },
    "implementationTokens": { "state": "measured", "value": 530, "unit": "tokens", "source": "source-backed worker stream", "coverage": "exact baseline and end sample" },
    "reviewTokens": { "state": "measured", "value": 210, "unit": "tokens", "source": "source-backed reviewer stream", "coverage": "exact baseline and end sample" },
    "totalTokens": { "state": "measured", "value": 740, "unit": "tokens", "source": "attributable role totals", "coverage": "all included roles measured" },
    "tasksCompleted": { "state": "measured", "value": 3, "unit": "tasks", "source": "declared ordered task identities", "coverage": "3 of 3 accepted" },
    "firstPassAcceptanceRate": { "state": "measured", "value": 0.666667, "unit": "ratio", "source": "review attempt identities", "coverage": "2 of 3 accepted first attempt" }
  },
  "provenance": {
    "eventSchemaVersion": 1,
    "sourceCoverage": "source-backed synthetic fixture",
    "limitations": []
  }
}
```

### Partial coverage

```json
{
  "schemaVersion": 1,
  "kind": "story_performance_report",
  "reportId": null,
  "runId": "synthetic-run-partial",
  "projectId": 999,
  "storyId": 998,
  "storyRef": 145,
  "reviewMode": "per_task",
  "pullRequest": null,
  "metrics": {
    "timeToPr": { "state": "partial", "value": null, "unit": "milliseconds", "source": "story_started -> pr_ready", "coverage": "start present; readiness boundary ambiguous", "missingData": "two candidate pr_ready observations" },
    "implementationElapsed": { "state": "partial", "value": 420000, "unit": "milliseconds", "source": "implementation phase boundaries", "coverage": "1 of 2 intervals has valid paired boundaries", "missingData": "one implementation interval is missing its closing boundary" },
    "implementationTokens": { "state": "partial", "value": null, "unit": "tokens", "source": "one attributable worker stream", "coverage": "1 of 2 intervals has complete deltas", "missingData": "counter reset removed one interval" },
    "reviewTokens": { "state": "unavailable", "value": null, "unit": "tokens", "source": "reviewer stream", "coverage": "no complete source-backed delta", "missingData": "end sample was not available" },
    "totalTokens": { "state": "partial", "value": null, "unit": "tokens", "source": "role totals", "coverage": "not all included roles are measured", "missingData": "partial or unavailable role usage remains unknown" },
    "tasksCompleted": { "state": "partial", "value": null, "unit": "tasks", "source": "declared ordered task identities", "coverage": "2 of 3 acceptance identities observed", "missingData": "one task acceptance is not authoritative" }
  },
  "provenance": {
    "eventSchemaVersion": 1,
    "sourceCoverage": "mixed source-backed and synthetic evidence",
    "limitations": ["Unknown values remain null; no estimate was substituted."]
  }
}
```

### Unavailable telemetry

```json
{
  "schemaVersion": 1,
  "kind": "story_performance_report",
  "reportId": null,
  "runId": "synthetic-run-unavailable",
  "projectId": 999,
  "storyId": 998,
  "storyRef": 145,
  "reviewMode": "story_end_only",
  "pullRequest": null,
  "metrics": {
    "timeToPr": { "state": "unavailable", "value": null, "unit": "milliseconds", "source": "story_started -> pr_ready", "coverage": "no paired story boundaries", "missingData": "confirmed PR readiness was not observed" },
    "implementationTokens": { "state": "unavailable", "value": null, "unit": "tokens", "source": "no attributable worker stream", "coverage": "none", "missingData": "worker/session counters are not exposed" },
    "reviewTokens": { "state": "unavailable", "value": null, "unit": "tokens", "source": "no attributable reviewer stream", "coverage": "none", "missingData": "reviewer/session counters are not exposed" },
    "totalTokens": { "state": "unavailable", "value": null, "unit": "tokens", "source": "role totals", "coverage": "no measured role totals", "missingData": "unavailable roles are not treated as zero" },
    "firstPassAcceptanceRate": { "state": "not_applicable", "value": null, "unit": "ratio", "source": "review attempt identities", "coverage": "story_end_only has no per-task denominator", "missingData": "not applicable" }
  },
  "provenance": {
    "eventSchemaVersion": 1,
    "sourceCoverage": "synthetic fixture",
    "limitations": ["Retain unknown usage and continue with authoritative UTC transition evidence."]
  }
}
```

## Diagnostics and operator decisions

| Observation | Meaning | Decision |
| --- | --- | --- |
| Same event ID and canonical payload replayed | Idempotent re-observation | Continue; do not increment counts or write a second event. |
| Same event ID with changed payload | Immutable identity conflict | Preserve the first record, retain the diagnostic, reconcile the source; do not overwrite or blindly replay. |
| Missing/reversed/ambiguous boundary | The affected interval cannot be calculated safely | Mark that metric partial or unavailable; do not subtract other phases to estimate it. |
| Missing, stale, or corrupt sidecar | Derived recovery state may not describe the complete ledger | The recorder first validates authority/index/identity claims by bounded direct ledger range; it repairs mutable sidecars from that record, reconciles pending claims, cold-rebuilds when required, or returns a safe error. An exact sidecar miss for an unseen Bloom-positive ID remains an ordinary append. |
| Foreign run/story binding | The ledger belongs to another scope | Stop that append, choose the correct run root, and keep the existing ledger untouched. |
| Report artifact already exists for the same identity | Immutable artifact collision | Compare/reconcile the exact identity; never overwrite a retained report. |
| Recorder or renderer I/O failure | Measurement path failed, workflow authority did not | Preserve the transition outcome, surface the limitation, and retry only after reconciliation. |

Diagnostics must not expose prompt bodies, transcripts, source text, secrets,
or raw malformed payloads. Safe diagnostics are sufficient for repair and
review: type, identity, line/start offset, byte length, and digest.

## Epic acceptance mapping and deferred ownership

Epic #140's original acceptance criteria map to deterministic evidence as
follows. A passing fixture proves the behavior contract; it does not claim a
live host trial or provider publication.

| Epic criterion | Evidence and owner | Status boundary |
| --- | --- | --- |
| Story start initializes lightweight measurement without changing authorization | `validate-performance-start.ps1`, `validate-performance-reporting.ps1`, and the story #144 hook evidence | Synthetic/local contract; authorization remains owned by the existing workflow. |
| Normal implementation and review transitions record events | `validate-performance-event.ps1` plus `event-envelope-v1`, `phase-coverage`, and `event-vocabulary-complete` | Recorder/hook evidence, not a live story run. |
| Confirmed story PR produces one readable report | `scripts/get-story-performance.ps1` and the report identity fixture; final PR readiness remains an integrated story #145 check | Exact PR/HEAD publication is a separate authorized gate. |
| Time to PR uses authoritative timestamps | `phase-coverage`, `metric-semantics`, and `timeToPr` report examples | UTC boundaries only; no retrospective estimate. |
| Implementation and review elapsed times are separate | `phase-coverage` and report metric semantics | Overlapping elapsed phase time is not CPU time or subtraction-derived coordination time. |
| Review counts use actual attempts and exclude duplicates | `synthetic-review-counts-per-task`, `synthetic-review-counts-story-end-only`, and `synthetic-final-rereviews-same-head` | Review identity is distinct from message delivery and SHA alone. |
| Token totals are accurate when available and qualified otherwise | `usage-boundary-reset`, `usage-subtotals`, `privacy-unavailable`, and the complete/partial/unavailable samples above | Current host has no attributable per-worker counter claim; unknown remains null. |
| Model, effort, mode, and story identifiers are included | setup metadata contract, `event-envelope-v1`, `report-identity`, and `modelsAndReasoning` semantics | Setup provenance is not token telemetry. |
| Both `per_task` and `story_end_only` are supported | `synthetic-review-counts-per-task` and `synthetic-review-counts-story-end-only` | Zero per-task reviews in `story_end_only` is valid. |
| Interrupted/recovered workflows do not double-count | `replay-same-id`, `replay-conflict`, `external-ledger-pointer`, recorder restart/isolation, interrupted-tail, and historical-report fixtures | Complete prior records survive; ambiguous writes are reconciled. |
| Reporting adds no agents, polling, or measurement-only messages | `synthetic-overhead-baseline-candidate` and `validate-performance-overhead.ps1` | Cold recovery costs are disclosed separately from recurring overhead. |
| Reporting failures do not block workflow, review, PR, or merge approval | recorder I/O-failure fixtures, `privacy-unavailable`, and story #144 failure-isolation evidence | Measurement is diagnostic; workflow authority remains unchanged. |
| Existing `taiga-ticket-loop` behavior remains unchanged | repository boundary in `docs/automation/README.md`, `validate-automatic-review-flow.ps1`, `validate-routing.ps1`, and `validate-final-delivery.ps1` | No ticket-loop implementation or provider behavior is claimed here. |
| Existing story-loop validators remain green | all affected `validate-*.ps1` scripts, with focused reporting and overhead checks called out below | Exact command output belongs to the current task review handoff. |
| Synthetic normal/correction/duplicate/interrupted/unavailable/PR-reuse cases pass | `event-envelope-v1`, correction and replay fixtures, privacy/unavailable fallback, report identity, recorder lifecycle, and overhead fixtures | Synthetic evidence stays synthetic; live trial and release remain separate. |

Deferred ownership is now explicit rather than open-ended:

- Task #141 owns the capability and version-1 contract reference.
- Story #142 owns safe append, idempotency, interruption recovery, and
  diagnostic sidecars.
- Story #143 owns deterministic aggregation, immutable report identity, and
  JSON/Markdown rendering.
- Story #144 owns lifecycle hooks and failure isolation at existing workflow
  boundaries.
- Story #145 owns integrated regression, recovery, overhead, operator/sample
  evidence, and the final exact-HEAD review.

Task #159's accepted exact revision is evidence for its own task boundary; it
does not close story #145 or authorize a PR/merge. Task #160's commit and
review handoff likewise remain task-scoped until the mandatory final
whole-story review at the integrated story HEAD.

## Final exact-HEAD review handoff

Before final story review, record all of the following against one clean,
committed HEAD:

1. Full HEAD SHA, captured base SHA, branch, changed paths, and `git diff
   --check` result.
2. Exact validator commands, exit codes, and concise output for the focused
   reporting/overhead checks and any affected existing validators.
3. The external report paths or sanitized retained samples, with the source,
   coverage, and limitations for every unavailable metric.
4. Confirmation that no live trial, provider write, PR merge, release, or
   unsupported host-token claim was made by this task.
5. The deferred-owner mapping above and the distinction between task-ready,
   reviewer-accepted, story-approved, PR-approved, and merged states.

The final whole-story reviewer decides whether the integrated evidence is
acceptable. This guide does not pre-approve that review or authorize
feature-to-master delivery.

## Mandatory production finalization (issue #214)

At the authorized story start and existing implementation/review/correction/wait
transitions, invoke `scripts/record-story-performance-transition.ps1` with the
existing recorder arguments (`ExternalRunRoot`, `RunId`, and `EventJson` or
`EventPath`) plus authorized `TaskRefs`. At initialization, also pass known
`MetadataPath` and `ObservedEvidencePath`. The wrapper records once through the
existing recorder and returns immediate missing-boundary/linkage/setup/session
diagnostics. Recording and diagnostic failures are limitations; they are not
workflow authorization or advancement gates. Actual observed UTC timestamps
are required. No historical boundary may be manufactured.

The wrapper's bounded `diagnostics` distinguish actionable event rejection from
recorder availability or execution failure. A value such as
`recorder_validation_rejected: occurredAtUtc must be an ISO 8601 UTC timestamp
ending in Z` identifies the field to correct before retrying the same
authorized transition. `recorder_unavailable: ...` and
`recorder_execution_failed: ...` require preserving the valid workflow outcome,
surfacing limited telemetry, and reconciling the recorder path before retrying.
These messages omit raw event JSON, payload values, secrets, prompts, and
transcripts; do not append a replacement event to repair rejected input.

After a confirmed exact-HEAD PR create/reuse, invoke the production finalizer:

```powershell
& ./scripts/finalize-story-performance.ps1 `
  -DeliveryPath '<external confirmed delivery receipt.json>' `
  -ExternalRunRoot '<existing external run root>' -RunId '<existing run id>' `
  -ArtifactRoot '<external immutable artifacts directory>' `
  -RepositoryPath '<story checkout>' -BaseRevision '<captured full base SHA>' `
  -ReviewMode story_end_only -TaskRefs 155,156 `
  -MetadataPath '<validated setup metadata.json>' `
  -ObservedEvidencePath '<observed role source bindings.json>' `
  -TaskOutcomePath '<authoritative task outcomes.json>'
```

For array parameters, invoke from PowerShell with `& ./scripts/finalize-story-performance.ps1`
and a typed `int[]`, or use a parameter hashtable rather than passing a
comma-delimited string through a native shell. Optional metadata/evidence paths
are omitted only when unavailable. In-process callers may pass `-Delivery`
instead of `-DeliveryPath`. The receipt uses the existing PR-delivery preflight
fields: `providerConfirmed`, `state` (`created`/`reused`), `pr` (URL, number,
repository, headBranch, base, head, state, isClosed), repository, storyBranch,
prBase, reviewedHead, and `receipt` with the documented topology/clean-state,
base/diff, branch/approved/checks/final-review exact-HEAD evidence. The production
entry point validates this same receipt; a confirmed flag alone is insufficient.
A telemetry command never confirms provider operations itself.

The finalizer checks the run's selected `observed-role-token-usage.json` sibling
when an explicit evidence path is absent. It invokes the existing collector
when bindings exist, including the collector's existing selected-source handling.
It records missing inputs, invalid/unavailable sources, partial coverage, and
execution failures before immutable publication. No unrelated session search,
quota polling, additional ledger, or telemetry-only agent turn is introduced.
Valid collector output reaches `-UsageMetadataPath` automatically, and valid
setup profiles reach `-MetadataPath`. Each revision uses a temporary collector
cursor/reporting view; those files are removed after publication. The original
ledger remains unchanged except for the normally confirmed `pr_ready` append.

`provenance.collectionAttempt` distinguishes `measured`, `partial`,
`source_unavailable`, `failed`, and `skipped`, with `discoveryAttempted`,
`collectorInvoked`, and a reason. This is collection-attempt evidence, separate
from metric states. Direct aggregation without finalization reports `skipped`.
An existing exact-HEAD report is checksum-verified and returned without
recollection/overwrite; historical reports lacking attempt evidence remain
preserved and explicitly disclose that absence.

Timing values have separate semantics:

- `timeToPr`: story start to confirmed PR readiness wall-clock elapsed.
- `implementationElapsed`/`reviewElapsed`: summed paired phase durations,
  including overlap and inactivity.
- `implementationWallClock`: union of paired implementation/correction windows
  inside the story span, counting overlaps once; still includes inactivity.
- `quotaBlockedElapsed`: union of confirmed `quota_blocked` wait pairs inside
  the story span. Missing pairs or no observed quota evidence remain unknown.
- `quotaAdjustedElapsed`: wall-clock elapsed minus confirmed quota overlap;
  other idle time remains included.
- `activeExecutionElapsed`: unavailable without independent activity evidence.

If `story_started` is absent but the ledger contains exactly one coherent
story-scoped `pr_ready` event for the confirmed provider PR and reviewed HEAD,
finalization anchors story identity to that existing readiness event. It does
not infer or append a replacement start event. JSON, Markdown, and manifest
artifacts may still publish with implementation/review measurements preserved;
`timeToPr` is `unavailable` and the report names the missing start boundary.
Ambiguous, conflicting, or missing readiness evidence keeps the report
unavailable while confirmed PR delivery remains valid.

Quota events use existing `wait_started`/`wait_ended` and a stable `waitId`;
the quota window length is never a blocked-duration estimate. Correction events
use `phaseId`, `correctionId`, `supersedesReviewAttemptId` and null review
request/attempt/kind/ordinal fields. Recorder and aggregator now agree.

Task completion preserves `acceptedTaskRefs` and separately reports
`implementationReadyTaskRefs`. In `story_end_only`, missing per-task reviews do
not prove tasks incomplete; authoritative individual acceptance/Done evidence
is needed. Final-story approval is never substituted. Optional task outcomes
use this envelope, tied to the exact reviewed HEAD:

```json
{
  "schemaVersion": 1,
  "kind": "story_performance_task_outcomes",
  "runId": "existing-run",
  "projectId": 12,
  "storyId": 728,
  "reviewedHead": "<full reviewed SHA>",
  "tasks": [
    {
      "taskRef": 155,
      "accepted": false,
      "isDone": true,
      "source": "taiga_task_status",
      "observedAtUtc": "2026-10-13T18:00:00Z",
      "evidenceReference": "<authoritative task status record and project Done mapping>"
    }
  ]
}
```

`source` is `taiga_task_status` or `task_acceptance`; capture explicit booleans
from actual task records/acceptance, never derive them from whole-story approval.
Duplicate, undeclared, or differently scoped outcome evidence is diagnosed and
not counted. Current task outcomes supersede earlier task acceptance; when all
outcomes are known, a known non-Done task contributes zero rather than unknown.

Normal PR delivery must include the finalizer's publication status, concise
coverage and limitations, PR and reviewed HEAD, and accessible JSON/Markdown
references. Only use `-ArtifactsAccessibleToUser` for paths actually reachable
on the user's host. Otherwise establish accessible references through the
existing delivery surface and report the access limitation. Publication and
measurement completeness are separate; confirmed PR delivery remains valid if
finalization fails. At epic completion, use `get-epic-performance-index.ps1`
with the ordered child story refs and a JSON array of selected delivered-HEAD
finalizer receipts. Include its Markdown index in the normal final epic response,
including missing/limited reports. This formatter adds no aggregate analytics.

Run the focused production regression suite:

```powershell
pwsh -NoProfile -File scripts/validate-story-performance-finalization.ps1
```

It executes the existing PR-delivery cases and production transition/finalizer/
index entry points using synthetic credentials-free data and temporary artifacts.
It covers complete/partial/failed/skipped collection, unavailable session binding,
correction parity, missing boundaries, task outcomes, quota/overlap semantics,
normal response references, immutable reuse, and missing rows in epic delivery.
