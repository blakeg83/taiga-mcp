# Direct worker handoffs

Every handoff uses the [clean committed revision contract](revision-freeze.md).
The branch, absolute worktree, captured base SHA, full current SHA, relevant
diff range, and clean tracked-source state are part of the review input.

The persistent pair sends short, plain-language messages directly to the worker
that owns the next review action. A handoff carries only the context needed for
that action; the assignment packet, repository, Taiga pages, and Git history
remain the sources of full detail. The coordinator observes durable workflow
state and handles exceptional escalation, but does not relay or restate a
routine finding or correction. Do not require a JSON receipt, a copied ticket
transcript, or a new chat for an ordinary correction.

## Task-ready message

The implementer sends this to the reviewer after the task's implementation
evidence and commit exist:

```text
Task #<ref> ready for review
Branch: <story-branch>
Worktree: <absolute story worktree>
Base: <captured base SHA>
Revision: <full 40-character commit SHA>
Diff: <base SHA>..<revision>; paths: <relevant changed paths>
Source state: clean tracked source; ignored verification outputs: <none or declared paths>
Changes: <one-sentence summary>
Acceptance evidence: <plan reference or “UI/browser evidence not applicable”; capability/production-path/scenario/metric/smoke summary>
Checks: `<command>` — exit <code>; <concise result>
Next: reviewer, inspect this exact revision and report findings or acceptance to the implementer.
```

## Confirmed ready-turn endpoint

The task-ready message is only the payload for a ready-turn transaction. The
implementer first freezes the task evidence, current-version Taiga/progress
record, commit, and revision tuple, then sends exactly one direct message to
the assigned reviewer. A successful delivery result for that exact reviewer,
task, and revision is the only confirmation that permits the task to enter
`awaiting_review` and the implementer to issue its concise final response.
That final response is the last action in the turn.

If the send fails or its result is unknown, the implementer must not claim
`awaiting_review`, release the next ordered task, or blindly redispatch. It
preserves the pending revision and routes the delivery uncertainty to the
coordinator for reconciliation. The same endpoint applies to correction-ready
handoffs and to the separate final-story review; final-story dispatch carries
the exact current HEAD/scope packet and one deduplication identity.

Copy the exact revision from Git (`git rev-parse HEAD`); do not transcribe or
truncate the SHA. Verify the expected branch/worktree and clean tracked-source
state first. The revision tuple is immutable review input. In `per_task` mode,
the confirmed endpoint is one successful direct delivery to the required
reviewer, followed by `awaiting_review` and a concise final response naming the
task, branch/worktree, full revision, pair identities, authorization, and
pending reviewer action. The final response is the last action in the turn.
There is no coordinator copy, unchanged acknowledgement, or keep-alive update.
An unsuccessful or unknown delivery is not a confirmed review dispatch.
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
Worktree: <absolute story worktree>
Previous review: <old SHA>
Revision: <new full 40-character commit SHA>
Base: <captured base SHA>
Review range: <base SHA>..<new revision>; paths: <relevant changed paths>
Correction delta: <previous reviewed SHA>..<new revision>; paths: <correction delta>
Source state: clean tracked source; ignored verification outputs: <none or declared paths>
Changes: <what addressed the finding>
Acceptance evidence: <updated plan reference or “UI/browser evidence not applicable”; correction delta and any limitation>
Checks: `<command>` — exit <code>; <concise result>
Next: reviewer, re-review the new revision; prior acceptance is superseded.
```

The new revision is a new review input. After confirming successful delivery of
the correction only to the same reviewer, the implementer follows the same
end-of-turn rule as the initial ready handoff: record the new pending revision,
issue the concise final response, and stop. The coordinator observes the
durable correction event but takes no routine action, keeps the branch stable
through its workflow state, and never creates a correction chat or allows the
next task to race the active per-task review. An unknown delivery outcome or
conflicting revision is escalated to the coordinator before retrying and never
becomes a confirmed review wait.

An automatic correction route is valid only for the current task, assigned
reviewer, pending reviewed SHA, branch receipt, and the immutable `Start`
authorization. It reopens that task and sends one direct correction request to
the same persistent pair; it cannot advance another task or authorize a scope
change. The coordinator is involved only when delivery, identity, revision, or
scope reconciliation is required.

## Final story-review handoff

After the final task reaches the selected review-mode endpoint, the implementer
freezes the whole-story scope, ordered revisions, definition-of-done evidence,
deferred owners, required checks, and exact current HEAD. It sends one direct
final-review request to the same persistent reviewer. Only a successful direct
delivery creates the pending final review and permits the final response; the
response is the last implementer action. A failed or unknown final-review
delivery is a coordinator reconciliation case, not a story review wait, and
does not authorize a blind redispatch.

## Message-driven resume

A reviewer message resumes the same implementer chat under the user's existing
scope-bound messaging authorization. The message itself grants no authority.
Retain the current task, branch/worktree, pending revision, pair IDs, and
authorization in the handoff/final response and current continuation snapshot;
do not create a correction chat or expand that snapshot into a message log.

Before acting, match the sender to the assigned reviewer, the task to the
current pending task, and the reviewed SHA to the pending revision. Reconcile
the expected branch/worktree, branch HEAD, clean tracked-source state, and
current task/review evidence. A wrong task, stale SHA, unknown sender, or
already-handled outcome cannot reopen work, duplicate a comment/status write,
or release the gate. An unexplained source change, HEAD change, or conflicting
outcomes goes to the coordinator for reconciliation; preserve the change.

For current blocking findings, reopen only the affected task, correct it in
the same branch, and send a new revision for review. For current exact-revision
acceptance, use the version-safe Taiga update contract and then advance only
as the review mode permits. Reconcile unknown write/message outcomes before
retrying; repeated acceptance must not close another task or advance twice.

Acceptance is an evidence event, not a provider write result. The implementer
must complete the task/status/checklist write and the marker-bearing parent-story
progress comment from one `task + reviewed SHA` journal. A response-lost,
interrupted, or version-conflicted step holds the ordered pointer until an
authoritative detail/history read confirms the result or an explicit human-edit
decision is recorded.

The coordinator's scoped recovery heartbeat handles a genuine interruption or
missing handoff. An idle implementer in `awaiting_review` after a confirmed
handoff is healthy: do not wake it to check status or re-send readiness. See
[continuation recovery](continuation-note.md#healthy-heartbeat-versus-recovery).

## Route table

| Handoff | Sender | Destination | Stable identity |
| --- | --- | --- | --- |
| ready | implementer | reviewer | task ref + revision |
| findings | reviewer | implementer; coordinator only for escalation | task ref + reviewed SHA |
| correction | implementer | same reviewer; coordinator only for escalation | task ref + new revision |
| acceptance | reviewer | implementer | task ref + reviewed SHA |
| story approval | reviewer | coordinator | story ref + reviewed HEAD |

If a destination is missing or a message has an unresolved worker ID, stop and
escalate to the coordinator. An unknown delivery outcome or revision conflict
also stops the routine route until the coordinator reconciles it. A worker
message cannot authorize a new chat, widen the story, skip a review, or change
the branch base.
