# Ordered task execution and truthful Taiga updates

Every implementation-ready revision follows the [clean committed revision
contract](revision-freeze.md). A status or checklist transition never makes a
dirty or moved checkout reviewable.

This reference is the Taiga update contract for the story-loop implementer.
The implementer owns status/checklist writes for the selected story tasks and
the parent-story progress comments. All tasks in one story remain on that
story's branch, worktree, and worker pair. Delivery follows the selected
topology: a new standalone story PR targets `master`, an epic story PR targets
the coordinator-owned shared feature branch, and a legacy standalone resume
targets its preserved feature branch before final feature-to-`master` delivery.
The implementer never creates or mutates the epic or legacy feature branch.

## Resolve mappings once

After the run is authorized and before the first task starts, read the
project-specific metadata:

```text
mcp__taiga__list_user_story_statuses({ projectId, page: 1 })
mcp__taiga__list_task_statuses({ projectId, page: 1 })
```

Follow `next_page` until the metadata is complete. Keep the returned IDs and
names as evidence; IDs are resource- and project-specific. Never use a story
status ID in `update_task`, and never infer a mapping from an English label.
Map logical states to the discovered task metadata:

| Logical state | Required meaning | Normal task status |
| --- | --- | --- |
| `not_started` | no task work has begun | project `New` or equivalent |
| `in_progress` | the current task is being implemented or corrected | project `In progress` or equivalent |
| `awaiting_review` | implementation evidence is complete and the direct handoff was confirmed; independent review is pending | project review-ready status written before dispatch, or the documented in-progress fallback |
| `accepted` | the reviewer accepted the exact implementation revision | project closed/done status |
| `blocked` | work cannot safely continue without a decision or external change | project blocked/needs-info status, when available |

If no task review-ready status exists, record the truthful fallback
`awaiting_review -> in_progress` in the run evidence. Do not use `accepted` as
the fallback: a task remains not-Done until independent review accepts it. If a
blocked status is absent, set `isBlocked=true` and a nonblank `blockedNote` on
the task and report the blocker in the parent story; do not invent a status ID.

## Establish the reviewable endpoint before implementation

Before changing source, the assignment and task description must identify:

- the artifact or behavior the reviewer will inspect;
- the expected check outcome, including whether this is an authoritative
  expected-red checkpoint;
- every criterion intentionally deferred, its later task or final-story owner,
  and the evidence that owner must provide; and
- the advancement gate for the selected review mode.

If any of these are missing or materially ambiguous, ask the narrow
clarification, record the task as blocked/needs information when available, and
do not start dependent work. Do not resolve ambiguity by demanding downstream
implementation early or by inventing an allowed failure.

For an expected-red checkpoint, record each named behavior/test, its exact
permitted failure reason, the complete observed failure set, and relevant
safety checks that passed. The observed set must match the contract one-for-one;
additional failures and alternate reasons are defects. A nonzero command exit
alone is not a valid RED. An unexpected failure, missing regression coverage,
or missing safety evidence leaves the task in-progress and blocks advancement.
The checkpoint can be reviewable when its contracted RED is evidenced, but
final story acceptance still requires exit-0 evidence for every formerly red
regression.

## Start, checklist, and review gates

Before each task, read the authoritative detail and version:

```text
mcp__taiga__get_task({ taskId })
```

Capture the complete Markdown description, including every `[ ]` checklist
item. At task start, update only the status using the current version:

```text
mcp__taiga__update_task({ taskId, version, status: mapping.in_progress })
```

When a checklist item has direct implementation/check evidence, update the full
description while preserving all text and unchecked items. Replace only the
specific evidence-backed checkbox, then send the complete description with the
current version. Never mark a review, acceptance, merge, or unavailable-check
item complete from worker intent. A task status transition is not checklist
evidence, and checked boxes are not reviewer acceptance.

Merge endpoint evidence into the existing task checklist/comment rather than
creating a mandatory receipt schema or duplicating the ticket transcript. Keep
deferred criteria and their owners visible until their later evidence is
recorded.

At implementation completion, commit all source changes before sending a
handoff. Copy the full SHA from `git rev-parse HEAD`, verify the expected
repository/worktree and branch, record the `<base SHA>..<reviewed SHA>` diff and
relevant paths, and verify clean tracked source. Declared ignored verification
outputs may remain, but non-ignored source changes block readiness.

At implementation completion, before dispatch, update and confirm the current
version to the project-specific review-ready mapping (or the documented
in-progress fallback). The worker must not write `mapping.accepted`. This
provider status write, together with the story progress write, belongs in the
frozen revision packet and is not proof that the reviewer received the
handoff. After one successful direct delivery to the assigned reviewer, record
the worker-local `awaiting_review` state; do not perform a new provider status
write at that endpoint. In `per_task` mode, only an independent reviewer
acceptance for the same revision allows the current task to become
`mapping.accepted`/Done or releases the next ordered task. In
`story_end_only` mode, implementation evidence may release the next ordered
task after the current task's status, checklist, comment, and commit evidence
are recorded, but the current task cannot become `mapping.accepted`/Done until
an independent reviewer accepts that exact revision. After a substantive
review rejection,
re-read the task, reopen only that task to `mapping.in_progress`, preserve the
other tasks and human edits, and add new revision-bound evidence before
returning it to review.

In `per_task` mode, both initial and correction-ready handoffs end the
implementer turn in `awaiting_review`; waiting means an idle chat, with no
reviewer polling or source edits. Resume on an authorized reviewer message
using the identity, exact-revision, and deduplication checks in
[message-driven resume](worker-handoffs.md#message-driven-resume). A timeout or
idle worker cannot release the review gate. Coordinator recovery handles
interrupted or missing handoffs, not routine review waits. The final response
after a confirmed handoff is the last implementer action; failed or unknown
delivery remains an escalation and never enters `awaiting_review`.

### Lifecycle recording at task boundaries

Record `implementation_started` when the resumed task reaches its first
concrete task-scoped edit or check, not when a status-only write is made. In
both modes, record `task_ready_for_review` after the exact clean commit at the
implementation-ready milestone. In `per_task`, then let the reviewer own the
matching `review_started` and `review_findings`/`review_accepted` observations;
in `story_end_only`, the implementation boundary does not dispatch a task
review. A current task finding starts `correction_started`; the corrected
commit records `correction_ready` before direct re-review. The reviewer owns
final-story start, finding, and re-review events in both modes. The implementer owns `correction_started` and `correction_ready`, including final-story
corrections, in both modes.
The coordinator owns explicit wait boundaries and the story/PR boundaries;
`pr_ready` remains deferred to task #157.

Use the actual `.agents/skills/taiga-story-loop/scripts/write-performance-event.ps1`
recorder helper and stable `phaseId`, `correctionId`,
`reviewRequestId`, `reviewAttemptId`, ordinal, revision, and `waitId` identities
from [worker-handoffs](worker-handoffs.md#recording-the-handoff-boundary). Duplicate
or stale messages do not create attempts or advance the ordered pointer. In
`story_end_only`, preserve the existing implementation-ready advancement gate,
omit task-scoped review/correction events, and record final-story start,
finding, correction, and re-review boundaries that actually occur. Copy known
model/effort and attributable usage snapshots
when available; absent counters stay unavailable/null. Recording is fail-open
and never adds a polling loop or telemetry-only worker message.

The ordinary handoff can be automated after the scope-bound `Start`: consume a
durable `ready_for_review` event once, send the review request directly to the
persistent reviewer, send one current finding directly back to the same
implementer, and send each correction-ready revision directly to that reviewer.
An exact acceptance is delivered directly from the reviewer to the implementer.
The implementer performs the current-version Taiga reconciliation and starts
only the next declared task when the selected review-mode gate is satisfied;
there is no coordinator acknowledgement, next-task assignment, or reminder
in this ordinary path. Duplicate or stale events, changed authorization/scope,
unknown delivery, revision conflicts, and idle observations remain pending for
reconciliation. The automatic path never starts an undeclared task, changes
scope, or merges. After final story approval, the coordinator may perform the
Start-authorized story PR delivery without another PR-creation gate.

Treat reviewer acceptance as durable evidence for the implementer, not as a
provider write receipt. The implementer owns one acceptance journal keyed by
`task ref + exact reviewed SHA` and completes it in this order:

1. re-read the authoritative task and current version;
2. merge only the named evidence-backed checklist items, preserving unrelated
   human text and applying the discovered task status mapping;
3. write the accepted status/checklist with that version;
4. re-read after a conflict or unknown result and classify the write as
   applied, already applied, human-changed, or unresolved;
5. read the parent story and add one marker-bearing progress comment using its
   current version; and
6. advance only after both the task transition and comment are authoritative.

For a non-final task, advancement then has a second observable boundary: read
the next declared task/version, set only that task to `mapping.in_progress`,
confirm the returned version, and begin concrete task-scoped work in the same
resumed turn. The first source/documentation edit or first task-scoped check
with actual output is implementation-start evidence; a status-only write,
plan, or intention is not. Record the evidence with one current-version
parent-story marker:

`Task #<ref> started | status: In progress | state: implementation_started | evidence: <path-or-command>`

If the accepted task is final, do not activate another task. Freeze the exact
current HEAD and use the separate final-story review endpoint. In
`story_end_only`, apply the same concrete-start rule after implementation-ready
evidence, status, parent-story comment, and commit evidence, without claiming
task acceptance or dispatching a per-task review.

The journal remains pending when the task write applies but its response is
lost, when the comment sequence is interrupted, or when a human edit creates a
version conflict. Recovery resumes the same journal, confirms existing marker
evidence, and writes only the missing operation. It never blindly retries an
ambiguous write, consumes acceptance early, closes another task, or advances
twice. A human status remains unchanged until an explicit preserve-or-replace
decision is recorded.

## Version-safe writes and reconciliation

Every update is a read/compare/write operation:

1. Read the current task detail and version immediately before preparing the
   write.
2. Preserve fields not owned by this run, including a human status, assignee,
   tags, description text, blocker note, and unrelated checklist items.
3. Send the smallest valid `update_task` containing the intended status,
   checklist description, blocker fields, or comment and the captured version.
4. Record the returned authoritative task and version.

If the response is lost or a version conflict occurs, do not retry the same
write. Re-read `get_task` and, when history is needed, use
`get_work_item_history({ kind: "task", id: taskId, page: 1 })`. Classify the
outcome as applied, unchanged, human-changed, or unresolved. A matching
authoritative status/version may confirm an applied write; a different human
status or changed description must be preserved and surfaced. Stop for a
decision when the intended checklist merge cannot be made without overwriting
the human edit. A human status is never replaced automatically: record an
explicit decision to preserve the human status and stop, or to replace it with
the exact intended transition. Include the prior human status/version and the
decision in the reconciliation evidence; without that decision, leave the
human status unchanged and unresolved.

The same rule applies to the parent-story comment. Read the current story
version before writing:

```text
mcp__taiga__get_user_story({ userStoryId })
mcp__taiga__add_work_item_comment({
  kind: "user_story", id: userStoryId, version, text: progressComment
})
```

An opaque error is not proof that a comment failed or succeeded; reconcile by
reading the story comments/history before another attempt.

## Blockers and truthful evidence

For a failed prerequisite, ambiguous order, unavailable required capability,
or unresolved check failure, keep dependent tasks untouched. If the project
provides a blocker status, write it with `isBlocked=true` and a concise
`blockedNote`; otherwise retain the task's current truthful status and use the
blocking fields. Then add a parent-story comment containing:

- task ref and current status/version;
- the obstacle and the attempted work;
- the exact check or authoritative response that demonstrates it;
- the decision/help or external change required; and
- the fact that dependent tasks were not started.

Clear a blocker only after rereading the current task and documenting the new
evidence. Never turn a failed check, missing receipt, timeout, response-lost
write, or unaccepted review into a completed checklist item.

At final story review, verify every deferred criterion against its named owner
and evidence, and verify that every required expected-red regression is green.
An unresolved RED or an ownerless/unsupported deferred criterion keeps the
story unapproved even when all implementation tasks have commits.
