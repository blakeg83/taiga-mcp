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
| Implementer sends `ready_for_review` | Current task, current committed HEAD, the confirmed `Start` authorization and assignment identity, checklist evidence, and checks | Send one direct review request to the persistent reviewer; set the task to the review-ready mapping or its documented fallback; hold the next task; do not copy the coordinator |
| Implementer sends `implementation_ready` in `story_end_only` | Current task, committed HEAD, the confirmed `Start` authorization and assignment identity, checklist evidence, and checks | Record implementation evidence and advance the next ordered task without task acceptance or a per-task review; request one final story review after the last task directly from the implementer to the reviewer |
| Reviewer sends `changes_requested` | Assigned reviewer, current task, exact pending SHA, finding, and requested correction | Reopen only that task and send the finding directly to the same implementer; require a new revision and review delta |
| Implementer sends correction-ready | Same current task, assigned reviewer, prior reviewed SHA, new committed SHA, and review delta | Send the new revision directly to the same reviewer; keep the coordinator out of the routine correction cycle |
| Coordinator reconciles an exceptional escalation | The exact pending escalation, current task/revision, and coordinator reconciliation decision | Clear the escalation hold; only then may the routine review flow resume |
| Reviewer accepts in `per_task` | Assigned reviewer, exact current task, exact current SHA, complete task criteria, and acceptance evidence | Deliver acceptance directly to the implementer; the implementer applies the version-safe accepted/Done transition, reconciles progress, then advances the next ordered task |
| Implementer starts next task | Prior task has the required accepted evidence in `per_task`, or implementation evidence in `story_end_only` | Mark only the next declared task active in the same implementer chat and story branch; do not add a coordinator assignment or reminder |
| Final task is accepted | Every selected task has exact-revision acceptance | The implementer requests final story review from the reviewer; the reviewer sends exact-HEAD approval to the coordinator; do not merge automatically. After story approval, prepare the PR under the existing `Start` authorization |

## Safety rules

- A ready event, idle status, timeout, elapsed time, or implementation commit
  is not reviewer acceptance.
- Routine `changes_requested`, correction-ready, task-ready, and exact task-acceptance
  events stay worker-to-worker; the coordinator does not relay or
  restate them. The implementer owns the current-version Taiga reconciliation
  and ordered-task advancement after acceptance.
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
- Unknown message delivery, missing destinations, revision conflicts, merge
  approval, product decisions, and scope changes remain coordinator
  reconciliation or user gates. PR creation or update is already covered by
  `Start` and may follow final story approval without another user prompt.
- After an exceptional escalation, the coordinator must reconcile the exact
  pending event before another review, correction, acceptance, or advancement
  event can resume the loop.

The coordinator may observe and reconcile the durable action records, but an
ordinary review handoff or correction is not routed through coordinator action
or a new user approval step.
