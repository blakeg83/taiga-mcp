# Recovery operations reference

This reference is portable with the `taiga-story-loop` skill. It describes
bounded quota-recovery operations and evidence handling; it does not install a
skill, start a workflow, induce account exhaustion, or authorize live writes.

## Bounded policy

Use the existing coordinator heartbeat as the only scheduler. Keep the same
confirmed recovery automation identity and its `ACTIVE` 30-minute schedule.
Do not create a nested scheduler, daemon, capacity poller, per-tick history, or
hard-coded quota delay. Approval, input/trial, cancellation, PR/merge, and
terminal gates always have precedence.

For the optional `Quota wait` state:

- A future reset estimate defers an attempt unless fresh authoritative evidence
  says the relevant capacity is available.
- Fresh authoritative exhaustion defers and may update the reset estimate.
- An elapsed or unknown reset permits one bounded eligibility decision; time
  passing is not proof of capacity.
- A confirmed rejection waits for a later eligible tick. Confirmed delivery
  closes the dispatch interruption and suppresses another quota wake while ordinary
  heartbeat observation continues for the same running worker. A later observed
  quota failure may reopen the compact state. Unknown delivery is persisted and
  requires reconciliation before retry.
- An eligible tick may send at most one scoped continuation to the same
  affected worker. Match the saved worker thread and host, task, stage,
  revision, branch, worktree, authorization, pending action, and external
  outcome before dispatch.
- That continuation targets the existing worker with its assigned settings:
  omit both the `model` and `thinking` arguments from the message. Recovery
  does not select a replacement profile; creation-time profile selection and
  separately authorized user configuration remain distinct.
- Delivery and substantive progress are different observations. A stage-
  appropriate source edit, scoped check, review, reconciliation, or handoff
  must be observed before recovery is called successful.

Unchanged ticks stay quiet. Never retry an unknown send, wake stopped peers, or
infer usable capacity from a timestamp. Use the same stable `waitId` and
`waitKind: quota_blocked` for observed `wait_started` and `wait_ended` bounds.
At the first explicit `usage_limit_exceeded`, record the failure timestamp
through `New-StoryPerformanceInterruptionEvent` and the transition recorder,
as described in [telemetry invocation](telemetry-invocation.md#explicit-interruption-observations).
Failed recovery attempts reuse that episode without duplicate wait boundaries.
Dispatch confirmation alone cannot close a telemetry quota wait. Record manual
authorization waits separately as `manual_resume`; if capacity during that gap
is unknown, retain the open quota boundary and partial duration coverage.

## Manual reconciliation fallback

When delivery, identity, schedule state, or an external action is unknown:

1. Read the current continuation snapshot. Preserve its run, pair, task, stage,
   branch, worktree, revision, authorization, gate, and pending-action fields.
2. Inspect the same automation ID and provider-confirmed schedule. Do not make
   a replacement automation because a tick or send is missing.
3. Verify the affected worker's exact thread and host and current state. An
   idle or completed status alone does not prove interruption or non-delivery.
4. Reconcile the current task/review stage and uncertain external action before
   sending anything. If the worker is running or delivery is unknown, do not
   send a duplicate continuation.
5. Preserve all approval, input/trial, cancellation, PR/merge, and terminal
   gates. Wait for an authorized resolution instead of bypassing a gate.
6. Record `wait_ended` only after a confirmed recovery boundary. Keep unknown
   availability explicit; do not fill missing data with zero or a guessed
   duration.

If the same worker, revision, automation, and one confirmed scoped delivery
cannot be established, leave the outcome unresolved and report the limitation.
Do not claim unattended recovery.

## Separately authorized host validation

This is a validation plan only. It was not executed by this skill change and
requires separate written authorization from the host/account owner. Use a
disposable story, branch/worktree, continuation note, worker pair, and
heartbeat. Do not use live customer data or change models, effort, plans, or
approval gates.

Before starting, capture the exact installed skill path and revision, repository
and SHA, run/story/task, implementer and reviewer thread/host pair, existing
heartbeat ID and provider-confirmed `ACTIVE` schedule, continuation pair and
quota fields, and stable `waitId`/`waitKind` with the observed start time.

Observe without forcing an unsafe account state: one tick before any supplied
reset estimate, an authoritative exhaustion result if exposed, and one later
eligible tick. Expected evidence is no premature wake, no capacity-polling
loop, at most one same-worker continuation, confirmed or explicitly unknown
delivery, a separate substantive next action, preserved gates and revision, and
no duplicate message, assignment, schedule, review, or write. Record
`wait_ended` only for the observed recovery boundary.

Stop and reconcile on an unknown provider result, changed worker identity,
dirty source, revision drift, approval/input/merge gate, duplicate wake, or any
unbounded retry. Preserve the evidence and limitation report. Cleanup of
disposable data is separately authorized; do not reset a live workflow to make
the result look successful.

All references in this section resolve within the skill package from
`$skillRoot`; they do not depend on repository-only documents or services.
