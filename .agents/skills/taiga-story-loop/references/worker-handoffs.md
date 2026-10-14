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

## Recording the handoff boundary

Each handoff has one performance observation at the boundary that already
exists in this protocol. In both modes, the implementer records
`implementation_started` at the first concrete task-scoped edit/check and
`task_ready_for_review` after the clean committed revision packet is frozen at
the implementation-ready milestone. In `per_task`, that frozen event precedes
the direct reviewer handoff; in `story_end_only`, it closes implementation but
does not dispatch a task review. The reviewer records
`review_started` when it begins the exact request/attempt and records
`review_findings` or `review_accepted` when that current attempt closes. A
current finding starts an implementer-owned `correction_started` phase; the
corrected frozen packet records `correction_ready` before the direct re-review.
The reviewer owns `final_review_started` and its finding/acceptance boundary.
The coordinator owns `story_started`, explicit `wait_started`/
`wait_ended`, and the confirmed `pr_ready` boundary; PR readiness remains the
task #157 endpoint.

Use `scripts/record-story-performance-transition.ps1` at each existing
boundary. It invokes the actual recorder
`.agents/skills/taiga-story-loop/scripts/write-performance-event.ps1` and performs
lightweight, nonblocking boundary/linkage diagnostics. Supply the authorized
ordered `TaskRefs` so advancement/final-review checks can identify missing
implementation ends and mode-specific acceptance evidence. Record the returned
limitations in the existing evidence/continuation surface and continue an
otherwise valid transition; do not add telemetry-only worker turns. Use the
setup `runId`, project/story identity, selected mode, actual UTC boundary, and
the stable identity fields required by
[performance-reporting](performance-reporting.md). A review request ID is not
a review attempt ID: a retry increments `reviewAttemptOrdinal`, while an exact
replay of an event, handoff, or stale revision is a no-op/reconciliation case.
`phaseId` binds implementation/review/correction pairs, `correctionId` binds a
correction pair, `reviewRequestId`/`reviewAttemptId` distinguish the request
from one actual attempt, and `waitId` binds an explicit wait pair. Maintain known
model/effort and profile changes in the validated setup metadata; attach an
attributable usage snapshot when available and preserve
`unavailable`/null when it is not. Do not estimate usage or emit a routine
telemetry-only summary/message. Recording failures leave the handoff and its
ownership gates unchanged and disclose the affected measurement coverage.
For each reviewer-owned review event, explicitly emit
`supersedesReviewAttemptId: null`; only `correction_started` and
`correction_ready` retain the non-null finding identity. Correction events
must emit null `reviewRequestId`, `reviewAttemptId`, `reviewKind`, and
`reviewAttemptOrdinal`; correction linkage uses `phaseId`, `correctionId`,
and `supersedesReviewAttemptId`.

For an observed quota interruption/resumption, the coordinator uses existing
`wait_started`/`wait_ended` boundaries with stable `waitId` and
`waitKind: quota_blocked`. Record real observation timestamps. A quota window
is not a blocked-duration measurement; incomplete boundaries remain partial.

`per_task` records the task review/correction events above. `story_end_only`
does not create task-scoped review or correction events, but it still records
implementation boundaries and final-story start, finding, correction, and
re-review boundaries when they actually occur. The selected mode is setup
data, not an inference from whichever events happen to be present.

### Canonical UTC construction

When a workflow transition constructs an event boundary and setup/profile
metadata, capture one `DateTimeOffset` and format that captured instant through
the repository helper before building either payload:

```powershell
. (Join-Path $repoRoot 'scripts/format-story-performance-utc.ps1')
$capturedBoundary = [DateTimeOffset]::UtcNow
$boundaryUtc = Format-StoryPerformanceUtcTimestamp -Timestamp $capturedBoundary

# Use the same $boundaryUtc for occurredAtUtc and effectiveFromUtc as needed.
```

The helper emits the canonical literal-`Z` form while preserving the captured
instant. Do not use `DateTimeOffset.ToString('o')` directly (`+00:00` is
rejected by the recorder), and do not rewrite already captured historical input;
an invalid supplied timestamp must remain a bounded validation diagnostic.

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
coordinator for reconciliation. The same delivery endpoint applies to
correction-ready handoffs and to the separate final-story review; final-story
dispatch preserves the already-confirmed per-task accepted closures or
story_end_only implementation-ready endpoint, carries the exact current
HEAD/scope packet and one deduplication identity, and does not rewrite provider
status merely to request review.

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

## Acceptance-to-next-task resume

After the assigned reviewer sends an exact current-task acceptance, the same
implementer chat owns the ordered continuation. It first matches the reviewer,
task, reviewed SHA, authorization, branch/worktree/HEAD, clean source state,
and already-handled outcome. A stale, duplicate, wrong-task, or conflicting
message cannot write Taiga or release a newer gate.

The durable sequence is:

1. Read the current task/version and merge only evidence-backed checklist items.
2. Write and confirm the accepted task status/checklist with that version.
3. Read the parent story and write/confirm the marker-bearing acceptance
   comment with its current version. Response-lost, interrupted, or
   version-conflicted writes hold the pointer and resume the same journal;
   confirmed operations are not blindly repeated.
4. If another declared task remains and the selected review mode allows it,
   read its complete detail/version, set only that task `In progress`, and
   confirm the returned version.
5. Begin concrete work on that next task in the same resumed turn. Observable
   evidence is a task-scoped source/documentation edit or the first
   task-scoped check with actual output; a status write, plan, or intention is
   insufficient. Then add one current-version parent-story marker:

   `Task #<ref> started | status: In progress | state: implementation_started | evidence: <path-or-command>`

The start marker is idempotent progress evidence and does not mean the task is
accepted or review-ready. If the accepted task is final, activate no next task;
freeze the exact current HEAD and request exactly one separate final-story
review. In `story_end_only`, implementation-ready evidence follows the same
next-task start sequence without task acceptance or per-task review dispatch.

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
