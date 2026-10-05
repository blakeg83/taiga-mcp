# Automatic review and ordered-task flow

The confirmed story scope authorizes routine review handoffs for the selected
story. After `Start`, the worker pair must drive the ordinary task loop without
waiting for the user or coordinator to request each review, re-review, or next
task. This is an automation trigger, not a new permission to widen scope,
change requirements, or merge a branch. `Start` already authorizes the
scope-bound PR creation or update listed in setup; the review loop must not add
another PR-creation confirmation.

## State carried by the run

The continuation snapshot and authoritative worker/Taiga records together bind:

- the ordered selected task IDs and the declared review mode;
- one implementer, one reviewer, one story branch, and one worktree;
- the current task and its pending implementation revision;
- the reviewer identity and action associated with that revision; and
- the immutable `Start` authorization record, resolved task scope, branch
  receipt, and current branch HEAD.

The continuation note is a compact pointer, not proof of acceptance. Confirmed
worker messages, Git state, Taiga versions, and review evidence remain
authoritative.

## Event transitions

| Event | Required proof | Automatic result |
| --- | --- | --- |
| Implementer sends `ready_for_review` | Current task, current committed HEAD, the confirmed `Start` authorization and assignment identity, checklist evidence, and checks | Send one review request to the persistent reviewer; set the task to the review-ready mapping or its documented fallback; hold the next task |
| Implementer sends `implementation_ready` in `story_end_only` | Current task, committed HEAD, the confirmed `Start` authorization and assignment identity, checklist evidence, and checks | Record implementation evidence and advance the next ordered task without task acceptance or a per-task review; request one final story review after the last task |
| Reviewer sends `changes_requested` | Assigned reviewer, current task, exact pending SHA, finding, and requested correction | Reopen only that task and send the correction to the same implementer; require a new revision and review delta |
| Reviewer accepts in `per_task` | Assigned reviewer, exact current task, exact current SHA, complete task criteria, and acceptance evidence | Apply the version-safe accepted/Done transition, then advance the next ordered task |
| Implementer starts next task | Prior task has the required accepted evidence in `per_task`, or implementation evidence in `story_end_only` | Send the next task assignment through the same implementer chat and story branch |
| Final task is accepted | Every selected task has exact-revision acceptance | Request final story review; do not merge automatically. After story approval, prepare the PR under the existing `Start` authorization |

## Safety rules

- A ready event, idle status, timeout, elapsed time, or implementation commit
  is not reviewer acceptance.
- `story_end_only` never turns implementation evidence into task acceptance and
  never dispatches a per-task review; only the selected final story review can
  accept those task revisions.
- A stale SHA, wrong task, wrong reviewer, changed branch HEAD, duplicate
  message, or already-consumed action is ignored or routed to reconciliation;
  it cannot write Taiga or advance the task pointer.
- An uncertain or version-conflicted Taiga write is reconciled through the
  existing task-write contract before another write is prepared.
- A changed task list, scope, acceptance criterion, or substantive requirement
  stops the loop for user input and creates no replacement task or branch.
- Merge approval, product decisions, and scope changes remain separate user
  gates. PR creation or update is already covered by `Start` and may follow
  final story approval without another user prompt.

The coordinator may observe and reconcile the durable action records, but an
ordinary review handoff is not routed through a new user approval step.
