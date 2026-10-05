# Direct worker handoffs

The persistent pair sends short, plain-language messages directly to the worker
that owns the next review action. A handoff carries only the context needed for
that action; the assignment packet, repository, Taiga pages, and Git history
remain the sources of full detail. The coordinator observes durable workflow
state and handles exceptional escalation, but does not relay or restate a
routine finding or correction. Do not require a JSON receipt, a copied ticket
transcript, or a new chat for an ordinary correction.

## Task-ready message

The implementer sends this to the reviewer and coordinator after the task's
implementation evidence and commit exist:

```text
Task #<ref> ready for review
Branch: <story-branch>
Revision: <commit SHA or stable revision range>
Changes: <one-sentence summary>
Checks: `<command>` — exit <code>; <concise result>
Next: reviewer, inspect this exact revision and report findings or acceptance.
```

Copy the exact revision from Git (`git rev-parse HEAD`); do not transcribe or
truncate the SHA. The revision is immutable review input. In `per_task` mode,
after both handoffs are confirmed, the implementer records `awaiting_review`
and ends its turn with a final response naming the task, branch, revision, and
pending reviewer action.
It must not call `wait_threads`, poll/read the reviewer chat, schedule its own
review monitor, or keep the turn alive. While review is pending, it makes no
source edits and does not start the next ordered task. A failed or unknown
handoff is reported to the coordinator for reconciliation; it is not a
confirmed review dispatch.

The scoped workflow may dispatch this handoff automatically from one durable
`ready_for_review` event. Dispatch is idempotent for the event and current
task/revision: a duplicate event does not send another request, and an old or
wrong binding is held for coordinator reconciliation.

## Findings message

The reviewer sends routine findings directly to the implementer. It contacts
the coordinator only when one of the documented escalation conditions needs
reconciliation:

```text
Task #<ref> findings
Reviewed: <commit SHA>
Severity: <blocking|non-blocking>
Finding: <specific observable defect or missing criterion>
Evidence: <file/check/result that demonstrates it>
Requested change: <smallest correction needed>
Next: implementer, correct the same story branch and return a new revision for review.
```

Findings name the reviewed SHA and do not edit the implementer's checkout. A
blocking finding reopens only the affected task. The coordinator does not copy,
rewrite, or restate a routine finding or turn it into acceptance.

## Correction-ready message

The implementer returns to the same reviewer chat:

```text
Task #<ref> correction ready
Branch: <story-branch>
Previous review: <old SHA>
Revision: <new commit SHA or stable range>
Changes: <what addressed the finding>
Checks: `<command>` — exit <code>; <concise result>
Next: reviewer, re-review the new revision; prior acceptance is superseded.
```

The new revision is a new review input. After sending the correction only to the
same reviewer, the implementer follows the same end-of-turn rule as the initial
ready handoff. The coordinator observes the durable correction event but takes
no routine action, keeps the branch stable through its workflow state, and
never creates a correction chat or allows the next task to race the active
per-task review. An unknown delivery outcome or conflicting revision is
escalated to the coordinator before retrying.

An automatic correction route is valid only for the current task, assigned
reviewer, pending reviewed SHA, branch receipt, and the immutable `Start`
authorization. It reopens that task and sends one direct correction request to
the same persistent pair; it cannot advance another task or authorize a scope
change. The coordinator is involved only when delivery, identity, revision, or
scope reconciliation is required.

## Message-driven resume

A reviewer message resumes the same implementer chat under the user's existing
scope-bound messaging authorization. The message itself grants no authority.
Retain the current task, branch/worktree, pending revision, pair IDs, and
authorization in the handoff/final response and current continuation snapshot;
do not create a correction chat or expand that snapshot into a message log.

Before acting, match the sender to the assigned reviewer, the task to the
current pending task, and the reviewed SHA to the pending revision. Reconcile
the branch HEAD and current task/review evidence. A wrong task, stale SHA,
unknown sender, or already-handled outcome cannot reopen work, duplicate a
comment/status write, or release the gate. An unexplained HEAD change or
conflicting outcomes goes to the coordinator for reconciliation.

For current blocking findings, reopen only the affected task, correct it in
the same branch, and send a new revision for review. For current exact-revision
acceptance, use the version-safe Taiga update contract and then advance only
as the review mode permits. Reconcile unknown write/message outcomes before
retrying; repeated acceptance must not close another task or advance twice.

The coordinator's scoped recovery heartbeat handles a genuine interruption or
missing handoff. An idle implementer in `awaiting_review` after a confirmed
handoff is healthy: do not wake it to check status or re-send readiness. See
[continuation recovery](continuation-note.md#healthy-heartbeat-versus-recovery).

## Route table

| Handoff | Sender | Destination | Stable identity |
| --- | --- | --- | --- |
| ready | implementer | reviewer, coordinator | task ref + revision |
| findings | reviewer | implementer; coordinator only for escalation | task ref + reviewed SHA |
| correction | implementer | same reviewer; coordinator only for escalation | task ref + new revision |
| acceptance | reviewer | implementer and coordinator | task ref + reviewed SHA |
| story approval | reviewer | coordinator | story ref + reviewed HEAD |

If a destination is missing or a message has an unresolved worker ID, stop and
escalate to the coordinator. An unknown delivery outcome or revision conflict
also stops the routine route until the coordinator reconciles it. A worker
message cannot authorize a new chat, widen the story, skip a review, or change
the branch base.
