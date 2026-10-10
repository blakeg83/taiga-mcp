# Attributable telemetry capability matrix

This reference records the task #146 capability discovery for story #141. It
is a read-only discovery result, not a provider-specific collector or a claim
that the Codex App exposes worker token counters.

Discovery date: 2026-10-09 (client date)

## Evidence boundary

Every row below names its evidence class. An observed host result is not the
same thing as a tool-schema capability, setup metadata, documentation, or a
synthetic fixture. The report states `measured`, `partial`, `unavailable`, or
`unverified` rather than converting an unknown value to zero.

This discovery used only allowlisted metadata. It did not read or export
prompt bodies, model output, source text, secrets, transcripts, terminal
history, or local session exports. It did not create a worker, send a
measurement-only message, call a provider, or write live Taiga data.

UI/browser evidence: not applicable. This task changes a capability contract
and its deterministic validator, not a rendered interaction.

## Exact read-only probes and results

The following probes were run or inspected in the authorized worker context.
Their results are deliberately narrower than a conversation or transcript
read.

| Probe | Evidence class | Observed result | Meaning and limitation |
| --- | --- | --- | --- |
| Current tool catalog: `mcp__codex_app__create_thread` schema | `tool_schema` | The host advertises `gpt-5.6-luna` with `xhigh` among its supported combinations and `gpt-6.1-sol` with `medium` among its supported combinations. | This establishes profile-selection capability only. It is not token usage, quality, or runtime success evidence. |
| `mcp__codex_app__get_usage_limits` schema | `tool_schema` | A read-only account-limit capability exists, but its contract describes shared account windows and reset timestamps, not worker/thread/session attribution. | Account-level limits must not be used as story or role token totals. No account-wide values were read for this task. |
| `mcp__codex_app__list_threads({ limit: 50 })` | `probe` | The coordinator record was visible with its current title, `idle` status, and `C:\Projects\TaigaMCP` working directory. The assigned implementer and reviewer records were not present in this returned page. | This is point-in-time identity/status metadata only. Absence from one page does not prove that a worker is stopped or unavailable. No follow-up thread read was made. |
| `get_goal({})` for the current worker | `probe` | `{ "goal": null, "remainingTokens": null, "completionBudgetReport": null }` | No active goal-budget counters were available in this worker context. This is not Codex App per-worker usage telemetry. |
| Repository search for performance helpers | `probe` | Existing measurement context is documentation in `docs/automation/measurement-reporting.md` and `.agents/skills/taiga-ticket-loop/references/measurement-contract.md`; no story-loop performance recorder or collector exists at the task base. | The ticket-loop reference is context only and remains unchanged. It does not provide attributable App-worker counters. |

The coordinator identity observed in the thread listing is
`01a123ce-a243-7dd1-9748-e7b747687490`. The implementer identity is the
assigned worker `01a123d1-189d-7661-a6a7-e72cbed9b101`, and the reviewer
identity is `01a123d1-1d12-7a51-916a-9205e4157e1b`. The latter two identities,
their roles, and their exact model/effort profiles come from the setup
assignment, not from token telemetry:

| Role | Assigned identity | Assigned profile | Provenance status |
| --- | --- | --- | --- |
| coordinator | `01a123ce-a243-7dd1-9748-e7b747687490` | not supplied as worker telemetry | `available` as setup identity; model/effort `unverified` |
| implementer | `01a123d1-189d-7661-a6a7-e72cbed9b101` | `gpt-5.6-luna` / `xhigh` | `available` as setup provenance; usage `unavailable` |
| reviewer | `01a123d1-1d12-7a51-916a-9205e4157e1b` | `gpt-6.1-sol` / `medium` | `available` as setup provenance; usage `unavailable` |

## Capability matrix

| Capability or datum | Source and exact field semantics | State | Coverage and safe use |
| --- | --- | --- | --- |
| Role, worker identity, story/project identity, branch and review assignment | Setup assignment and story/task records; identifiers are metadata, not usage counters. | `available` | Use for report provenance when the assignment is still authoritative. Do not infer token totals from an identity. |
| Assigned model and reasoning effort | Setup assignment; the host `create_thread` schema independently advertises the selected combinations. | `available` for provenance | Report the exact assigned profile and any later profile change as metadata. This does not prove that a worker completed a turn with that profile. |
| Coordinator point-in-time status and working directory | `list_threads` result fields `status` and `cwd`. | `partial` | A status snapshot can support recovery or routing evidence. It cannot measure elapsed work, activity, or usage and must not be extrapolated between snapshots. |
| Implementer/reviewer point-in-time status | The assigned worker/reviewer records were not returned by the authorized `list_threads` page. | `unavailable` for this probe | Do not infer idle, active, completed, or failed from absence. Preserve the assignment identity and leave runtime status unknown. |
| Per-worker input, cached-input, output, or reasoning counters | No current host schema or probe exposed counters bound to these worker identities. | `unavailable` | Token fields remain unknown, not zero. The later recorder/report must preserve `usage.state = unavailable` and its source/coverage reason. |
| Account usage-limit windows | `get_usage_limits` schema exposes shared account usage percentages and reset times. | `unavailable` for story attribution | Account limits may describe the account, but cannot be assigned to this story, worker, role, or review. Do not use them as token totals or cost. |
| Local CLI/session exports for App workers | No export was selected or read. The epic explicitly warns that CLI records must not be assumed to cover App worker chats. | `unverified` | A future authorized export would need an explicit worker/session binding, stream identity, counter semantics, and boundary coverage before use. |
| Exact transition timestamps | The story/epic contract names UTC transition boundaries, but this discovery run did not execute a recorder or workflow transition. | `unverified` | Later workflow work must record actual UTC boundaries at the transition. Retrospective estimates and elapsed-time subtraction are not valid substitutes. |
| Synthetic validation of the unavailable and partial paths | `validate-performance-reporting.ps1` reads the checked-in contract and exercises labeled in-memory fixtures only. | `available` as deterministic validation | This proves contract shape and honest fallback behavior. It is not a host observation, browser run, live provider result, or token measurement. |

## Sanitized examples

The first example is a sanitized host observation. It contains identity/status
metadata only and intentionally has no usage field. The other examples are
synthetic fixtures; their counter values are test data and must never be
reported as observed usage.

### Observed host metadata (sanitized)

```json
{
  "exampleId": "observed-coordinator-thread-metadata",
  "evidenceClass": "observed_host_metadata",
  "source": "mcp__codex_app__list_threads",
  "role": "coordinator",
  "threadId": "01a123ce-a243-7dd1-9748-e7b747687490",
  "status": "idle",
  "workingDirectory": "C:\\Projects\\TaigaMCP",
  "usage": null,
  "interpretation": "identity and point-in-time status only"
}
```

### Synthetic unavailable-token observation

```json
{
  "exampleId": "synthetic-unavailable-worker-usage",
  "evidenceClass": "synthetic_fixture",
  "source": "no attributable per-worker counter exposed by the current host schema",
  "role": "implementer",
  "model": "gpt-5.6-luna",
  "effort": "xhigh",
  "streamId": null,
  "state": "unavailable",
  "counters": null,
  "coverage": "none",
  "reason": "worker/session token counters are not exposed for this identity",
  "fallback": "retain unknown usage and continue with later authoritative UTC transition evidence"
}
```

### Synthetic partial counter observation

```json
{
  "exampleId": "synthetic-partial-worker-usage",
  "evidenceClass": "synthetic_fixture",
  "source": "fixture-only cumulative stream",
  "role": "reviewer",
  "model": "gpt-6.1-sol",
  "effort": "medium",
  "streamId": "synthetic-reviewer-stream",
  "state": "partial",
  "baseline": "exact story-start boundary sample",
  "counters": {
    "inputTokens": 120,
    "cachedInputTokens": 40,
    "outputTokens": 30,
    "reasoningTokens": 8
  },
  "coverage": "one attributable interval; not a story total",
  "resetHandling": "a counter decrease starts a reset segment and leaves the affected interval unknown"
}
```

The partial example demonstrates required provenance fields and reset
semantics; it does not establish that the current host exposes those fields.
Cached-input and reasoning subtotals remain source-defined and are not added
twice. A missing baseline, counter reset, post-run sample, or ambiguous stream
changes coverage to partial or unavailable instead of creating an estimate.

## Executable fallback

When attributable worker usage is unavailable, the supported fallback is:

1. Preserve the role/model/effort assignment as provenance only.
2. Emit an explicit `unavailable` usage state with `counters: null` and a
   source/coverage reason.
3. Do not emit zero, infer usage from message length or file size, or convert
   account limits into story tokens, subscription consumption, or cost.
4. Continue the workflow and later record only authoritative UTC transition
   boundaries when the recorder exists. Measurement failure must not alter
   authorization, review, advancement, PR, or merge behavior.
5. Run the deterministic validator from the repository root:

   `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-performance-reporting.ps1`

The validator exercises synthetic unavailable and partial examples and checks
that the observed host example is not mislabeled as usage telemetry. It makes
no network calls and writes no state.

## Acceptance evidence plan

- UI/browser evidence: not applicable; this is a documentation and validator
  change.
- Capability sources/probes: current Codex App tool schemas, the bounded
  `list_threads` probe, the current-worker `get_goal` probe, the setup
  assignment, and repository search results listed above.
- Production path: no runtime production path is changed in this task. The
  validator reaches the contract by reading the checked-in reference and
  validates its sanitized examples and fallback semantics.
- Preserved inputs: exact role identities, assigned profiles, probe names,
  state names, explicit null/unknown values, and no prompt/transcript data.
- Metrics: no performance number is claimed. The validator counts contract
  examples and checks state/provenance fields; those counts are synthetic
  assertions, not host measurements.
- Scenario matrix: observed coordinator metadata is an automated contract
  assertion; per-worker usage is an honest unavailable case; synthetic partial
  counters are an automated fixture only.
- Smoke: from the repository root, run the validator with PowerShell 7 and a
  disposable external working directory if one is needed by the caller. It
  reads tracked files only, has no service start, live data, or cleanup.
- Limitations: no per-worker App token counters, no attributable account
  limits, no worker status from the bounded listing, and no live transition
  timestamps were available in this discovery context. Recorder, aggregation,
  workflow hooks, review counting, and integrated overhead evidence are owned
  by later tasks/stories.

## Deferred ownership and boundaries

- Task #147 (the versioned contract section above) defines event identity,
  persistence, timestamp coverage, metric semantics, and versioned event/report
  schemas.
- Task #148 defines review-attempt counting and bounded-overhead acceptance
  cases.
- Story #142 owns safe event recording; story #143 owns deterministic
  aggregation/reporting; story #144 owns workflow hooks; story #145 owns
  integrated regression and overhead evidence.

This task therefore records what can be attributed and how unavailable data is
represented, without inventing a collector or changing workflow authority.

## Versioned event and report contract (task #147)

This section defines the version-1 contract that later recorder, aggregation,
and workflow-hook work must consume. It is a contract only: this story does
not implement the recorder, aggregation, or hooks.

### Canonical event envelope

Every persisted event is one JSON object with `schemaVersion: 1` and
`kind: "story_performance_event"`. Required identity and provenance fields
are:

| Field | Required value/shape | Semantics |
| --- | --- | --- |
| `schemaVersion` | positive integer; currently `1` | Contract version, independent of the run or report revision. |
| `eventId` | nonblank stable identifier | Ledger identity. The canonical event payload excludes no field except an implementation-only digest used to compare payloads. |
| `runId` | nonblank run identity | Binds an event to one authorized story run; never infer it from a branch or chat title. |
| `projectId` | positive internal project ID | Taiga project identity. |
| `storyId` / `storyRef` | positive internal ID and displayed ref | Both are retained so provider identity and human-facing identity cannot be confused. |
| `taskRef` | positive displayed ref or `null` | Required for task events; `null` for story-level events. A null task is not task zero. |
| `role` | `coordinator`, `implementer`, or `reviewer` | Actor responsible for the observed transition, not a guess from message text. |
| `sessionId` / `workerId` | nonblank when the source supplies them; otherwise `null` | Session and worker/chat provenance. Missing values reduce coverage; they are never synthesized from a prompt or transcript. |
| `transitionId` | nonblank stable logical transition ID | Names the logical lifecycle transition and remains stable across re-observation. |
| `reviewRequestId` / `reviewAttemptId` | nullable outside review events | A request identifies the handoff; an attempt identifies one actual review. They are separate from `revision` and from `eventId`. |
| `eventType` | one event vocabulary value below | No free-form event type is accepted by the contract. |
| `occurredAtUtc` | UTC ISO 8601 timestamp ending in `Z` | Generated at the actual transition. It is not an LLM estimate or a local-time conversion. |
| `revision` | full Git SHA or `null` before a revision exists | Exact reviewed/changed revision. A shortened SHA is invalid. |
| `reviewMode` | `per_task` or `story_end_only` | Captures the selected mode without changing workflow authority. |
| `provenance` | object with source, observer and coverage | Explains where the observation came from and whether it is direct, partial, synthetic, or unavailable. |
| `usage` | object or `null` | Optional source-backed usage sample. Null means not supplied, not zero. |

`eventId` is the ledger's idempotency key. Replaying the same ID with a
canonical payload that is byte-for-byte equivalent after JSON object-key
normalization is a no-op and must not create a second event or counter delta.
Replaying the same ID with any different payload is a conflict: preserve the
first complete record, surface the conflict with both identities, and do not
silently merge fields. A reobserved handoff is not a new review attempt.

### Event vocabulary and pairing

These are the original epic lifecycle events. `wait_started` and `wait_ended`
are the only additional boundaries allowed by this contract, and they are
recorded only when an existing workflow transition begins or ends an explicit
wait that the report is required to measure. There is no generic polling event
and no measurement-only worker message. Existing lifecycle end events serve as
phase ends; a generic `phase_ended` event is unnecessary and prohibited.

| Event type | Required identity | Closes or pairs with | Missing-data rule |
| --- | --- | --- | --- |
| `story_started` | story identity; coordinator role | `pr_ready` | Missing start makes time-to-PR unknown. |
| `implementation_started` | `taskRef`; implementer role | `task_ready_for_review` or `correction_ready` for the same task/revision interval | Missing end leaves that implementation interval uncovered. |
| `task_ready_for_review` | `taskRef`, `revision`; implementer role | next `review_started` for the same request | It is an implementation boundary, not proof that delivery or review occurred. |
| `review_started` | task/final scope, `reviewRequestId`, `reviewAttemptId`, `revision`; reviewer role | `review_findings` or `review_accepted` with the same attempt identity | Missing end leaves review duration unknown. |
| `review_findings` | same review request/attempt and revision | `correction_started` for that task | Findings close the current review phase; they do not count as acceptance. |
| `review_accepted` | same review request/attempt and revision | acceptance of that task revision | Acceptance is evidence, not a provider write receipt or merge. |
| `correction_started` | `taskRef`, corrected-attempt identity; implementer role | `correction_ready` | Missing end leaves the correction interval uncovered. |
| `correction_ready` | `taskRef`, new full `revision`; implementer role | a new `review_started` request | The new revision supersedes the prior review input; it does not mutate history. |
| `final_review_started` | final `reviewRequestId`, `reviewAttemptId`, exact HEAD; reviewer role | `final_review_accepted` | Missing end leaves final review duration unknown. |
| `final_review_accepted` | same final request/attempt and exact HEAD | final-story approval | Does not authorize PR creation or merge by itself. |
| `pr_ready` | PR identity and exact reviewed HEAD; coordinator role | report identity | Missing PR readiness prevents a confirmed PR report. Unknown provider delivery is not readiness. |
| `wait_started` | stable `waitId`, wait kind, affected scope | `wait_ended` with the same `waitId` | An open wait is reported as uncovered/unknown; it is never inferred from elapsed wall time. |
| `wait_ended` | same `waitId` and scope | closes the explicit wait interval | An end without a start is an anomaly and contributes no duration. |

Pairing is by scope, stable identity, and chronological UTC boundaries, never
by array position or nearest timestamp. A missing boundary, reversed boundary,
or ambiguous identity creates an anomaly and reduces that metric's coverage.
Worker phase intervals may overlap coordinator or reviewer intervals. Sum the
valid intervals for their own phase metric, preserve overlap diagnostics, and
never subtract one phase from total wall time to invent coordination or wait
time. Uncovered gaps remain explicit.

### Persistence and recovery pointer

The event ledger is append-only JSONL outside the source worktree, under a
coordinator-selected external run root:

`<external-run-root>/<runId>/events.jsonl`

The path is run configuration, not an event payload field. One complete JSON
object and newline is the append unit. A writer must serialize concurrent
appends and flush the complete line before reporting success. An interrupted
tail may be quarantined or reported as incomplete, but earlier complete lines
remain authoritative and are never rewritten. Duplicate IDs are no-ops;
conflicting IDs remain visible as conflicts.

Reports are immutable siblings of the ledger and are keyed by a canonical
report identity:

`runId + projectId + storyId + PR provider/owner/repository/number + exact reviewed HEAD`

Identical PR identity and exact HEAD is idempotent and reuses the same report
identity. A newly approved HEAD creates a new retained report; it must not
overwrite the old report. An unknown PR result creates no confirmed PR report,
but never invalidates already recorded measurements.

The continuation note carries only a compact recovery pointer, for example:

```text
Performance pointer: schema=1 | run=<run-id> | project=<project-id> | story=<story-id>/<story-ref> | ledger=<external-ledger-path> | lastEvent=<event-id> | lastObservedUtc=<utc>
```

The pointer is not a historical registry and contains no prompt text,
transcript, source, token payload, or copied event list. Recovery rereads the
external ledger and verifies the last event identity before continuing.

### Usage and interval semantics

An optional `usage` sample is cumulative within one explicit `streamId`, role,
session, and source. Its counters are source-defined nonnegative integers:
`inputTokens`, `cachedInputTokens`, `outputTokens`, and `reasoningTokens`.
Each sample also records `sampledAtUtc`, `baselineAtUtc` when known,
`source`, `counterSemantics`, and `coverage`.

For a counter `c`, a report may calculate a delta only when the same stream has
an exact start-boundary baseline and an end sample, both are attributable to
the run, and the counter does not decrease between them:

`delta(c) = c(end) - c(exact baseline)`

An interval crossing a counter decrease starts a named reset segment and is
unknown; it is not clamped to zero. A missing baseline, absent counter,
ambiguous stream, or sample after the run end reduces coverage or makes the
affected value unavailable. Later samples are retained as later activity but
are not attributed to the run.

Cached-input and reasoning counters remain separate raw fields. They are not
added to input or output a second time. If the source does not state whether
reasoning is included in output, that component is partial/unavailable rather
than estimated. Unknown is never zero, and raw tokens are never converted to
subscription allowance or monetary cost.

### Report metrics

Every report metric includes `state`, `value` (or `null`), `unit`, `source`,
`calculation`, `coverage`, and `missingData`. `state` is `measured`,
`partial`, `unavailable`, or `not_applicable`; a numeric value with partial
coverage is not a complete total.

| Metric | Unit | Calculation | Source | Missing-data semantics |
| --- | --- | --- | --- | --- |
| `timeToPr` | milliseconds | Direct UTC difference `pr_ready - story_started` | paired story boundaries | Null/unavailable when either boundary is missing, reversed, or PR delivery is unknown. |
| `implementationElapsed` | milliseconds | Sum valid implementation and correction intervals by task | paired `implementation_started`/`task_ready_for_review` or `correction_*` events | Partial when any required interval is uncovered; never derive by subtracting other phases. |
| `reviewElapsed` | milliseconds | Sum valid task/final review intervals by distinct review attempt | paired `review_started` and finding/acceptance events | Partial/unavailable for open or ambiguous attempts. |
| `coordinationElapsed` | milliseconds | Sum explicit coordinator intervals only | coordinator lifecycle/wait boundaries | Unavailable when no attributable coordinator interval exists. |
| `waitingElapsed` | milliseconds | Sum explicit `wait_started`/`wait_ended` intervals | wait boundary events | Unknown for open, orphaned, or inferred waits; no polling-based estimate. |
| `implementationTokens`, `reviewTokens`, `coordinationTokens` | tokens | Sum valid cumulative deltas by role and stream | source-backed usage samples | Null when unavailable; partial when only some streams/intervals are covered. |
| `totalTokens` | tokens | Sum attributable role totals only when their states/semantics permit | role usage metrics | Partial remains partial; never treat unavailable roles as zero. |
| `tasksCompleted` | tasks | Count accepted task identities in the declared ordered task set | accepted lifecycle events and story task metadata | Unknown when the ordered set or acceptance evidence is incomplete. |
| `initialTaskReviews`, `correctionReReviews`, `finalStoryReviews`, `finalStoryReReviews` | review attempts | Count distinct request/attempt identities by event scope | actual review handoff/acceptance events | Zero per-task reviews in `story_end_only` is valid; incomplete identity coverage is partial. Detailed cases are locked by #148. |
| `firstPassAcceptanceRate` | ratio and coverage counts | accepted-on-first-attempt tasks / tasks with an initial review | review request/acceptance identities | Zero denominator is `not_applicable`; report numerator, denominator, and coverage. |
| `reviewMode` | enum | Assigned mode copied unchanged | setup authorization | Unavailable if setup mode is absent; never infer from observed event order. |
| `modelsAndReasoning` | metadata records | Exact role/profile records, including changes | setup/host provenance | Unverified profile remains explicitly unverified; it is not a token estimate. |
| `changedFiles`, `linesAdded`, `linesDeleted` | counts | Exact base-to-reviewed-HEAD Git diff | revision freeze and Git | Null when base/HEAD or diff is unavailable; no complexity score is inferred. |

### Concrete version-1 examples

The following objects are synthetic examples. Their IDs, SHA, timestamps, PR
number, and token values are fixtures, not observations from this run.

```json
{
  "exampleId": "synthetic-run-141/story-started",
  "schemaVersion": 1,
  "kind": "story_performance_event",
  "eventId": "synthetic-run-141/story-started",
  "runId": "synthetic-run-141",
  "projectId": 12,
  "storyId": 725,
  "storyRef": 141,
  "taskRef": null,
  "role": "coordinator",
  "sessionId": "synthetic-coordinator-session",
  "workerId": "synthetic-coordinator-thread",
  "transitionId": "story-started",
  "reviewRequestId": null,
  "reviewAttemptId": null,
  "eventType": "story_started",
  "occurredAtUtc": "2026-10-09T10:00:00Z",
  "revision": null,
  "reviewMode": "per_task",
  "provenance": {
    "source": "workflow_transition",
    "observedBy": "coordinator",
    "coverage": "direct",
    "synthetic": true
  },
  "usage": null
}
```

```json
{
  "exampleId": "synthetic-run-141/project-12-story-725-pr-321-head-0123456789abcdef0123456789abcdef01234567",
  "schemaVersion": 1,
  "kind": "story_performance_report",
  "reportId": "synthetic-run-141/project-12-story-725-pr-321-head-0123456789abcdef0123456789abcdef01234567",
  "runId": "synthetic-run-141",
  "projectId": 12,
  "storyId": 725,
  "storyRef": 141,
  "reviewMode": "per_task",
  "pullRequest": {
    "provider": "github",
    "owner": "blakeg83",
    "repository": "taiga-mcp",
    "number": 321,
    "reviewedHead": "0123456789abcdef0123456789abcdef01234567"
  },
  "metrics": {
    "timeToPr": {
      "state": "measured",
      "value": 900000,
      "unit": "milliseconds",
      "source": "story_started -> pr_ready",
      "calculation": "direct UTC difference",
      "coverage": "both boundaries present",
      "missingData": null
    },
    "implementationTokens": {
      "state": "unavailable",
      "value": null,
      "unit": "tokens",
      "source": "no attributable worker stream",
      "calculation": "not calculated",
      "coverage": "none",
      "missingData": "worker stream was not exposed"
    },
    "firstPassAcceptanceRate": {
      "state": "not_applicable",
      "value": null,
      "unit": "ratio",
      "source": "review attempt identities",
      "calculation": "accepted-on-first-attempt / tasks-with-initial-review",
      "coverage": "zero denominator in this fixture",
      "missingData": "not applicable"
    }
  },
  "provenance": {
    "eventSchemaVersion": 1,
    "sourceCoverage": "synthetic fixture",
    "generatedAtUtc": "2026-10-09T10:15:00Z"
  }
}
```

### Requirement-to-fixture matrix

The focused validator names each fixture so a later recorder or aggregator can
replace the in-memory control without changing the contract vocabulary.

| Requirement | Fixture ID | Deterministic assertion |
| --- | --- | --- |
| Versioned envelope and required identity | `event-envelope-v1` | Valid event has schema/kind, run/project/story, role/session, transition, UTC, revision, provenance, and optional usage fields. |
| Same-ID replay | `replay-same-id` | Same ID and same canonical payload is a no-op and preserves one record. |
| Same-ID conflict | `replay-conflict` | Same ID with a changed field is surfaced as a conflict and cannot overwrite the first record. |
| Original event vocabulary | `event-vocabulary-complete` | All eleven epic events are present; only explicit `wait_started`/`wait_ended` are accepted as additional boundaries. |
| Phase pairing and overlap | `phase-coverage` | Valid pairs calculate elapsed milliseconds; missing/reversed boundaries remain unknown and overlapping intervals are not subtracted. |
| External ledger and recovery pointer | `external-ledger-pointer` | The ledger is outside the worktree and the pointer contains only compact run/story/last-event metadata. |
| Cumulative usage baseline | `usage-boundary-reset` | Exact-boundary deltas work; missing baseline, decreases, absent counters, and post-run samples reduce coverage or remain unknown. |
| Counter subtotal semantics | `usage-subtotals` | Cached-input and reasoning subtotals remain separate and are never double-counted. |
| Report identity | `report-identity` | Same run/story/PR/exact HEAD reuses identity; a new exact HEAD creates a new identity. |
| Metric completeness | `metric-semantics` | Each epic metric declares unit, calculation, source, coverage, and missing-data semantics. |
| Privacy and unavailable fallback | `privacy-unavailable` | No prompt/transcript/source/secret data is accepted; unavailable usage remains null with an explicit reason. |

The matrix is synthetic executable evidence, not a claim that a recorder or
host telemetry source is already available. Task #148 owns the detailed
review-attempt and bounded-overhead acceptance cases that build on these
identities and metrics.
