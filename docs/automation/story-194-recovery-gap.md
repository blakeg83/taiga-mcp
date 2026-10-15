# Story #194 task #195: recovery gap and host capability report

This report is the evidence endpoint for Taiga MCP story #194 task #195. It
records the current repository gap and the supported host contracts without
starting a workflow, forcing quota exhaustion, installing a skill, or mutating
live Taiga data.

## Frozen investigation context

| Field | Value |
| --- | --- |
| Repository | `C:\Projects\taiga-mcp` |
| Worktree | `C:\Users\Chez Blerin\.codex\worktrees\story-194-quota-recovery\taiga-mcp` |
| Branch | `codex/story-194-quota-recovery` |
| Story base | `5da765764b26b916d684458d31bc9f161fcde2e4` |
| Story | Taiga MCP #194 / internal id `737` |
| Task | #195 / internal id `927` |
| Investigation date | 2026-10-15 |

The base is the reviewed `master`/PR #97 baseline named by the story. The
task's implementation revision is supplied by its committed diff and final
revision packet, not by this report alone.

## Evidence classification

### Reported evidence

The live story consolidates issue #227 and reports two JobSearch story #16
incidents: an implementer `usage_limit_exceeded` event at 02:22 UTC followed
by a paused heartbeat and manual continuation, and a reviewer event at 11:33
UTC followed by failed scheduled attempts and manual continuation. The story
also reports `rate_limits.primary` fields named `used_percent`,
`window_minutes`, and `resets_at`.

These observations establish the user-visible recovery gap, but do not by
themselves establish the exact root cause, usable capacity at a reset, or
whether the scheduler attempted to wake a quota-blocked coordinator.

### Source-verified evidence

- The repository contains one compact continuation writer,
  `.agents/skills/taiga-story-loop/scripts/write-continuation-note.ps1`, and
  one validator,
  `.agents/skills/taiga-story-loop/scripts/validate-continuation-note.ps1`.
  The writer uses an allowlisted, single-line snapshot with atomic replacement,
  a `.previous` backup, no-op handling, field/byte bounds, and no history
  append path.
- `references/continuation-note.md` stores the existing run, worker, branch,
  revision, gate, pending-action, cursor, automation identity, and confirmed
  schedule state. Its healthy heartbeat planner reads the snapshot first,
  requires `ACTIVE`, targets only actively running workers, uses at most one
  `wait_threads(timeoutMs: 0)` snapshot, excludes a confirmed
  `awaiting_review` implementer, and stays quiet when unchanged.
- `references/routing-and-escalation.md` and
  `references/automatic-review-flow.md` preserve direct worker-pair routing,
  exact-revision checks, unknown-delivery reconciliation, and coordinator
  escalation. They contain no quota-specific wait, reset, or same-worker
  continuation decision.
- The existing performance event constructor and recorder accept
  `wait_started`/`wait_ended` with a stable `waitId` and nonblank `waitKind`.
  `story-performance-metrics.ps1` already recognizes `waitKind =
  quota_blocked`; this is reusable telemetry, not proof that a quota wait was
  observed or resumed.
- The current provider-backed heartbeat state is one automation with id
  `story-194-recovery`, kind `heartbeat`, status `ACTIVE`, target coordinator
  thread `01a14094-bdb0-7720-949d-75118971f8e6`, and
  `FREQ=MINUTELY;INTERVAL=30`. Its prompt reads the continuation snapshot and
  performs the existing bounded healthy-worker wait; it has no quota-wait
  branch or worker-resume operation.
- The local host has 69 parsed `rate_limits` records in the 2026-10-15
  session JSONL set. The records expose `primary.used_percent`,
  `primary.window_minutes`, and `primary.resets_at`; none has a non-null
  `rate_limit_reached_type`. Textual `usage_limit_exceeded` matches are not
  treated as independent incident proof because the matching session lines
  include copied ticket/tool content as well as source records.

### Synthetic or contract-only evidence

The existing offline validators exercise the current continuation replacement,
healthy heartbeat budget, direct routing, lifecycle termination, and duplicate
guards with synthetic state. They do not execute a real worker chat, heartbeat
tick, scheduler wake, provider write, or quota reset.

## Current gap

The current continuation snapshot can preserve the affected worker indirectly
through the normal pair fields, but it has no compact field for all of the
following facts together:

- an evidenced recoverable quota interruption and affected stage;
- the failure/evidence reference and optional estimated reset;
- whether the last continuation outcome is waiting, confirmed-delivered, or
  unknown; and
- a re-opened wait after a confirmed quota rejection.

The general blocker/reconciliation route can preserve a user-action blocker,
but ordinary inactivity and a recoverable quota wait are not the same state.
The healthy heartbeat contract also has no bounded decision for a known future
reset, a passed estimate with missing capacity metadata, fresh continued
exhaustion, or an unknown continuation delivery. Consequently, adding quota
behavior only to the prompt would lose state across coordinator interruption
and could resend a continuation without identity/action reconciliation.

## Smallest adequate implementation touchpoints

The ordered tasks should extend the existing path in this order:

1. **Task #196 — continuation.** Add one optional, single-line quota-wait
   snapshot field to the existing writer allowlist and validator. Keep the
   normal run/pair/task/branch/revision/authority/gate/cursor fields as the
   source of identity. Preserve old notes when the field is absent, atomic
   replacement, no-growth/no-op behavior, size limits, unknown actions, and
   user gates. Do not add a registry, per-tick history, or duplicate identity
   fields.
2. **Task #197 — heartbeat planning.** Extend the existing heartbeat decision
   path and synthetic planning helpers to retain the same `ACTIVE` automation
   during a quota wait. A known future reset or fresh authoritative exhaustion
   defers; a missing reset/capacity signal permits one later bounded attempt;
   elapsed time never proves capacity. The planner must retain the wait after a
   confirmed rejection and require reconciliation before retrying an unknown
   delivery. Approval, cancellation, input, trial, PR, merge, and terminal
   gates keep precedence.
3. **Task #198 — same-worker continuation.** Reconcile the recorded worker,
   host, stage, revision, pending action, and uncertain delivery before sending
   at most one scoped continuation to the same worker. A healthy
   `awaiting_review` implementer is not woken when the reviewer is affected;
   already-running/resumed workers receive no wake. Delivery must remain
   distinct from substantive progress. Reuse the existing
   `wait_started`/`wait_ended` telemetry with `waitKind = quota_blocked` and
   observed boundaries only.
4. **Task #199 — deterministic coverage.** Extend the existing continuation,
   routing, lifecycle, and performance fixtures with controlled synthetic
   quota evidence and barriers. Use no sleeps, live exhaustion, live Taiga
   writes, or parallel test-only workflow engine. Include negative controls for
   duplicate wakes, unknown delivery, missing identity, and gate bypass.
5. **Task #200 — operator documentation.** Publish the bounded policy,
   evidence limitations, manual reconciliation fallback, synthetic results,
   and a separately authorized host-validation procedure. Keep repository and
   installed-skill portability explicit.

## Host capability finding

The current native host contract supports a persistent heartbeat automation:
`automation_update` exposes heartbeat create/update/view operations with a
recurring schedule and target thread, while `wait_threads` exposes a bounded
nonblocking snapshot for recorded worker/host/cursor identities. The current
automation file confirms the story's existing 30-minute heartbeat is active
and targets the coordinator.

That is capability evidence for scheduling and bounded thread observation. It
does **not** prove that a heartbeat tick can wake a coordinator whose model
execution is quota-blocked, that a reset estimate corresponds to usable
capacity, or that a scheduler tick survives coordinator interruption. The
provider's post-reset wake semantics are therefore **unverified** in this
task. No actual-host trial was authorized or performed.

## Safe separately authorized validation procedure

This procedure is documentation only and must not be run under story #194's
current authorization:

1. Authorize a disposable story scope, a fresh continuation snapshot, one
   existing implementer/reviewer pair, and one heartbeat. Record the exact
   automation id, coordinator/worker host ids, branch/worktree, task, and
   revision before the run.
2. Induce or use a provider-controlled recoverable quota interruption only if
   the host owner supplies a safe, reversible method. Record the worker/stage,
   failure evidence, reset metadata, and `wait_started` event; do not change
   models, effort, account plans, or approval gates.
3. Leave the same heartbeat `ACTIVE`. Observe one eligible tick before reset,
   one tick after reset with authoritative exhaustion, and one eligible tick
   with usable capacity if the host exposes that evidence. Expected results are
   no premature wake, no continuous polling, and at most one same-worker
   continuation after reconciliation.
4. Verify confirmed rejection, confirmed delivery, unknown delivery, and
   substantive progress separately. Confirm no duplicate messages, schedules,
   assignments, writes, or gate transitions, then record `wait_ended` only for
   the observed recovery boundary.
5. Stop on an unknown provider result, unexpected worker, dirty source,
   changed revision, approval/input/merge gate, or any unbounded retry. Pause
   the same heartbeat, remove disposable data, and preserve the evidence and
   limitation report without claiming unattended recovery if the host cannot
   establish it.

## Acceptance-evidence plan

- UI/browser evidence: not applicable; this is a service/contract/host
  capability investigation.
- Capability sources: repository contracts and validators (documentation),
  native automation/thread tool schemas (tool schema), current automation
  state file (provider-backed local state), and read-only session JSONL parsing
  (source probe).
- Production path/control: the existing continuation writer, heartbeat
  planner, worker routing, and performance event constructor/recorder named
  above; future fixtures must fail when they bypass those paths.
- Metrics: no performance claim is made. Quota duration remains unavailable
  unless paired observed wait boundaries exist; reset timestamps are hints, not
  duration measurements.
- Scenario status: current offline validators are synthetic assertions;
  post-reset scheduler wake and coordinator-interruption behavior are
  unavailable/unverified until separately authorized host validation.
