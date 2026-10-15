# Story #194 recovery operations

This guide documents the lightweight quota-recovery extension delivered by
story #194. It is operator guidance and evidence interpretation; it does not
install the skill, start a workflow, induce account exhaustion, or authorize
live Taiga/provider writes.

The portable, skill-local copy is [recovery-operations.md](../../.agents/skills/taiga-story-loop/references/recovery-operations.md).

## Bounded recovery policy

The existing coordinator heartbeat remains the only scheduler. While ordered
work is allowed, keep the confirmed `Recovery` automation identity and its
30-minute schedule `ACTIVE`; do not create a quota service, nested heartbeat,
daemon, per-tick history, or hard-coded five-hour delay. Paused approval,
input/trial, cancellation, PR/merge, and terminal gates retain precedence.

The optional `Quota wait` field is compact planning state, not a second
identity record:

- A known future reset estimate defers an attempt unless fresh authoritative
  evidence says the relevant capacity is available.
- Fresh authoritative exhaustion defers and may replace the reset estimate.
- After an estimate passes, or when no reset is known, missing capacity metadata
  permits one bounded eligibility decision. Passing time is not proof of
  capacity.
- A confirmed rejection remains waiting for a later eligible tick. A confirmed
  delivery changes the outcome to `delivered` and suppresses another quota wake
  for that interruption while ordinary heartbeat observation continues for the
  same running worker. A later observed quota failure may reopen the compact
  state. Unknown delivery requires reconciliation before retry.
- On an eligible tick, reconcile the exact affected worker and send at most one
  scoped continuation to that same worker. A running worker, missing identity,
  stale task/stage/revision/branch/worktree/authorization binding, pending
  action, or uncertain external result blocks dispatch.
- Delivery and substantive progress are separate observations. A later
  stage-appropriate check, implementation, review, reconciliation, or handoff
  is required before calling recovery successful.

The planner stays quiet when unchanged. It does not wake a stopped worker just
because a tick elapsed, poll a new capacity service, retry an unknown send, or
infer a quota duration from reset timestamps. Existing `wait_started` and
`wait_ended` events use the same stable `waitId` and
`waitKind: quota_blocked`; only observed boundaries are recorded.

## Evidence status

The repository fixtures are deterministic and synthetic. The affected checks
passed on the story branch at revision
`f5f0262fef010b75145df56938ec29171dbb41ef`:

```text
git diff --check
validate-continuation-note.ps1
validate-coordinator-lifecycle.ps1
validate-routing.ps1
validate-automatic-review-flow.ps1
validate-performance-reporting.ps1
validate-acceptance-evidence.ps1
validate-scenarios.ps1
```

These checks cover reset/capacity decisions, implementer/reviewer selection,
same-worker identity reconciliation, duplicate suppression, repeated rejection,
unknown delivery, preserved gates, old-note compatibility, telemetry boundary
handling, and a delivery-to-substantive-progress walkthrough. They do not prove
that a real host wakes a quota-blocked coordinator after reset, that reset
metadata means usable capacity, or that an actual provider send succeeded.

The source-backed host finding from task #195 is narrower: the host exposes the
existing heartbeat automation with a recurring schedule and target thread, and
it exposes bounded nonblocking `wait_threads` observation for recorded worker,
host, and cursor identities. Post-reset wake of a quota-blocked coordinator
remains unverified.

## Manual reconciliation fallback

When delivery, worker identity, schedule state, or an external write is
unknown, stop the routine path and reconcile from the authoritative source:

1. Read the current continuation snapshot and preserve its run, pair, task,
   stage, branch, worktree, revision, authorization, gate, and pending-action
   fields.
2. Inspect the same automation ID and provider-confirmed schedule. Do not
   create a replacement automation because a tick or send is missing.
3. Verify the affected worker's exact thread/host and current state. Treat an
   idle/completed status alone as insufficient evidence of interruption or
   non-delivery.
4. Reconcile the current task/review stage and any uncertain external action
   before sending anything. If the worker is already running or delivery is
   unknown, do not send a duplicate continuation.
5. Preserve approval, input/trial, cancellation, PR/merge, and terminal gates.
   If a gate is active, wait for its authorized resolution rather than using
   quota recovery to bypass it.
6. Record real `wait_ended` evidence only after a confirmed recovery boundary.
   Keep incomplete or unknown availability explicit; never fill missing data
   with zero, a guessed duration, or an assumed successful reset.

If the host cannot establish the same worker, same revision, same automation,
and one confirmed scoped delivery, leave the outcome unresolved and report the
limitation. Do not claim unattended recovery.

## Separately authorized actual-host validation

The following is a safe validation plan only. It was not executed for story
#194 and requires separate written authorization from the host/account owner.
Use a disposable story, branch/worktree, continuation note, worker pair, and
heartbeat; do not use live customer data or change plans, models, effort, or
approval gates.

Before starting, capture:

| Evidence | Expected value |
| --- | --- |
| Skill source | Exact installed-skill path and revision/hash used by the host |
| Repository | Absolute repository, story branch/worktree, base and current SHA |
| Workflow | Same run/story/task, implementer/reviewer thread IDs and host IDs |
| Automation | Existing heartbeat ID, target coordinator, provider-confirmed ACTIVE schedule |
| Continuation | Pair identity, affected worker/stage, quota evidence, reset hint, and cursors |
| Telemetry | Stable `waitId`, `waitKind: quota_blocked`, observed `wait_started` timestamp |

Observe, without forcing an unsafe account state, one tick before any supplied
reset estimate, a tick with authoritative exhaustion if the host exposes it,
and one later eligible tick. Expected evidence is: no premature wake; no
capacity polling loop; at most one same-worker scoped continuation; confirmed
delivery or an explicit unknown result; a separate substantive next action;
preserved gates and revision; and no duplicate message, schedule, assignment,
review, or write. Record `wait_ended` only for the observed recovery boundary.

Stop and reconcile on an unknown provider result, changed worker identity,
dirty source, revision drift, approval/input/merge gate, duplicate wake, or any
unbounded retry. Preserve the evidence and limitation report. Cleanup of
disposable data is itself an authorized action; do not delete or reset a live
workflow to make the result look successful.

## Repository versus installed skill

The repository copy is under:

```text
<repository>/.agents/skills/taiga-story-loop/
```

The host executes the separately installed copy under its configured skill
root, for example:

```text
C:\Users\<user>\.codex\skills\taiga-story-loop\
```

The story branch changes the repository copy only. It does not install or
replace the configured copy, and the installed copy must not be assumed to
contain these changes until an explicitly authorized installation/update has
been performed. Compare the exact paths and revisions before any authorized
host trial; preserve both state roots and never copy a continuation note,
registry, or run ledger between them.

All changed helpers and references resolve from the skill package's own
`$skillRoot`. No repository-only quota service or helper framework is required,
so the contract remains portable after a deliberate skill installation/update.
