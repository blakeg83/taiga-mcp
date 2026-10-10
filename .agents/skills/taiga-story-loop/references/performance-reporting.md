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

- Task #147 defines event identity, persistence, timestamp coverage, metric
  semantics, and versioned event/report schemas.
- Task #148 defines review-attempt counting and bounded-overhead acceptance
  cases.
- Story #142 owns safe event recording; story #143 owns deterministic
  aggregation/reporting; story #144 owns workflow hooks; story #145 owns
  integrated regression and overhead evidence.

This task therefore records what can be attributed and how unavailable data is
represented, without inventing a collector or changing workflow authority.
