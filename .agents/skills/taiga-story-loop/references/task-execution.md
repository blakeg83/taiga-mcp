# Ordered task execution and truthful Taiga updates

This reference is the Taiga update contract for the story-loop implementer.
The implementer owns status/checklist writes for the selected story tasks and
the parent-story progress comments. All tasks in one story remain on that
story's branch, worktree, and worker pair. Delivery follows the selected
topology: a standalone story PR targets `master`, while an epic story PR
targets the coordinator-owned shared feature branch. The implementer never
creates or mutates the epic feature branch.

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
| `awaiting_review` | implementation evidence is complete; independent review is pending | project review-ready status |
| `accepted` | the reviewer accepted the exact implementation revision | project closed/done status |
| `blocked` | work cannot safely continue without a decision or external change | project blocked/needs-info status, when available |

If no task review-ready status exists, record the truthful fallback
`awaiting_review -> in_progress` in the run evidence. Do not use `accepted` as
the fallback: a task remains not-Done until independent review accepts it. If a
blocked status is absent, set `isBlocked=true` and a nonblank `blockedNote` on
the task and report the blocker in the parent story; do not invent a status ID.

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

At implementation completion, update the current version to
`mapping.awaiting_review` (or the documented in-progress fallback). The worker
must not write `mapping.accepted`. In `per_task` mode, only an independent
reviewer acceptance for the same revision allows the current task to become
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
interrupted or missing handoffs, not routine review waits.

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
