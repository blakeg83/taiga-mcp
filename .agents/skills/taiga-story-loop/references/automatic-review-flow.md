# Automatic review and ordered-task flow

Every event carries the [clean committed revision
contract](revision-freeze.md). A ready or correction event is valid only when
the expected repository/worktree and branch, full current SHA, relevant diff
range, and clean tracked-source state are verified. Ignored verification
outputs may be declared; source changes or unexpected HEAD movement require
revision-conflict reconciliation.

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
| Implementer sends `ready_for_review` | Current task, current committed full HEAD, expected repository/worktree and branch, base/diff/path record, clean tracked-source state, the confirmed `Start` authorization and assignment identity, checklist evidence, checks, confirmed implementation-complete Taiga/progress writes, and confirmed delivery to the required reviewer (a successful direct-delivery result for that assigned reviewer) | Confirm the task's review-ready mapping or documented fallback before freezing the packet; Send one direct review request to the persistent reviewer exactly once; only after successful delivery record the worker-local `awaiting_review` state, hold the next task, issue the concise final response and end the implementer turn; failed/unknown delivery remains an exception and is not blindly retried. The provider write is not dispatch confirmation. |
| Implementer sends `implementation_ready` in `story_end_only` | Current task, committed HEAD, the confirmed `Start` authorization and assignment identity, checklist evidence, and checks | Record implementation evidence and advance the next ordered task without task acceptance or a per-task review; request one final story review after the last task directly from the implementer to the reviewer |
| Reviewer sends `changes_requested` | Assigned reviewer, current task, exact pending SHA, finding, and requested correction | Reopen only that task and send the finding directly to the same implementer; require a new revision and review delta |
| Implementer sends correction-ready | Same current task, assigned reviewer, previous full reviewed SHA, new committed full SHA, expected branch/worktree, clean tracked-source state, base/diff/path review delta, confirmed implementation-complete Taiga/progress writes, and confirmed delivery to that reviewer (a successful direct-delivery result for that reviewer) | Confirm the corrected task's review-ready mapping or documented fallback before freezing the packet and sending exactly one new revision to the same reviewer; only after successful delivery record the worker-local `awaiting_review` state and supersede prior approval, issue the concise final response and end the implementer turn; keep the coordinator out of the routine correction cycle; failed/unknown delivery remains an exception. The provider write is not dispatch confirmation. |
| Coordinator reconciles an exceptional escalation | The exact pending escalation, current task/revision, and coordinator reconciliation decision | Clear the escalation hold; only then may the routine review flow resume |
| Reviewer accepts in `per_task` | Assigned reviewer, exact current task, exact current SHA, complete task criteria, and acceptance evidence | Deliver acceptance directly to the implementer; the implementer applies the version-safe accepted/Done transition, reconciles progress, then advances the next ordered task |
| Implementer starts next task | Prior task has the required accepted evidence in `per_task`, or implementation evidence in `story_end_only` | Mark only the next declared task active in the same implementer chat and story branch; do not add a coordinator assignment or reminder |
| Final task reaches the selected review-mode endpoint | `per_task`: every selected task has exact-revision acceptance; `story_end_only`: every selected task has implementation-ready evidence | Request exactly one final whole-story review from the reviewer at the exact current HEAD; do not treat the last task acceptance or implementation milestone as story approval |
| Reviewer accepts the final story review | Assigned reviewer, final-review request identity, exact current repository/worktree/branch/HEAD/scope, definition-of-done evidence, ordered task coverage, cross-task evidence, deferred-criterion evidence, independent checks, inspected worker evidence, and limitations | Send one exact-HEAD story approval to the coordinator; only the coordinator may open the topology-specific PR; do not merge automatically |

### Ready-turn transaction

For initial, correction-ready, and final-story review events, the dispatch
boundary is ordered and terminal:

1. Complete and confirm the required task/story Taiga/progress writes,
   including the provider review-ready mapping or documented fallback, then
   freeze the relevant revision packet before dispatch. The provider mapping is
   not handoff confirmation.
2. Send exactly one direct message to the assigned persistent reviewer and
   require a successful delivery result for that exact identity/revision.
3. Only then enter worker-local `awaiting_review` and issue the concise final
   response. Do not perform a new provider status write at this endpoint. The
   response is the last implementer action in that turn.
4. On failed or unknown delivery, keep the event in coordinator reconciliation;
   do not present a healthy review wait, release ordered work, or blindly
   redispatch. A healthy idle review wait is distinct from this exception.

The shorthand “only after successful delivery set the task to the review-ready
mapping” must not be read as a post-dispatch provider write. The mapping is
confirmed before dispatch; only the worker-local `awaiting_review` state waits
for successful delivery.

### Acceptance reconciliation transaction

The reviewer message is not a Taiga write result. In `per_task`, the
implementer resumes the same chat and owns a durable acceptance journal keyed
by the current task and exact reviewed SHA. It reads the task detail/version,
merges only checklist items named by the acceptance evidence, preserves
unrelated human edits, and applies the project-specific task status mapping.
It then confirms the status/checklist write and a marker-bearing parent-story
progress comment separately. Advancement is legal only after both are
authoritatively observed.

An unknown or version-conflicted task/status/comment operation holds the
acceptance and ordered pointer. The implementer rereads the task/story and
history before another write; a response-lost write may be confirmed as
already applied, while a human change remains unresolved until an explicit
decision. Recovery resumes the same journal and performs only the missing
operation. Duplicate acceptance messages, duplicate event IDs, and repeated
recovery of a confirmed marker are no-ops.

For the final task, confirmed closure requests exactly one final whole-story
review and does not merge or release the story. In `story_end_only`,
implementation-ready milestones may advance task order but leave provider
tasks unaccepted; final story acceptance reconciles those task closures and
progress evidence, then leaves merge/release as separate gates. A final finding
routes to the same implementer/reviewer pair, and the corrected HEAD receives
a fresh final-review request; no approval survives a changed revision, scope,
requirement, or new finding.

## Safety rules

- A ready event, idle status, timeout, elapsed time, or implementation commit
  is not reviewer acceptance.
- After a confirmed initial or correction-ready delivery, the implementer turn
  ends immediately. The same terminal rule applies to final-story delivery.
  The implementer does not call
  `wait_threads`, read or poll the reviewer chat, run a review monitor, send a
  keep-alive or unchanged acknowledgement, make source changes, or start the
  next task while the review is pending. Only a current authorized reviewer
  message or evidenced recovery may resume the same implementer chat.
- A failed or unknown handoff delivery is an exceptional coordinator
  reconciliation, not `awaiting_review` and not permission to re-dispatch.
- A healthy idle `awaiting_review` worker is not woken by recovery. Recovery
  observes the authoritative task/revision and delivery evidence only when a
  missing handoff, failed delivery, or genuine interruption is evidenced.
- Routine `changes_requested`, correction-ready, task-ready, and exact task-acceptance
  events stay worker-to-worker; the coordinator does not relay or
  restate them. The implementer owns the current-version Taiga reconciliation
  and ordered-task advancement after acceptance.
- `story_end_only` never turns implementation evidence into task acceptance and
  never dispatches a per-task review; only the selected final story review can
  accept those task revisions.
- A stale SHA, wrong task, wrong reviewer, changed branch/worktree, dirty
  tracked-source state, changed branch HEAD, duplicate
  message, or already-consumed action is ignored or routed to reconciliation;
  it cannot write Taiga or advance the task pointer.
- An uncertain or version-conflicted Taiga write is reconciled through the
  existing task-write contract before another write is prepared.
- A source or HEAD change discovered during review holds acceptance and
  advancement. Preserve the change and escalate the revision conflict; never
  reset, clean, stash, force-push, or silently review another revision.
- A changed task list, scope, acceptance criterion, or substantive requirement
  stops the loop for user input and creates no replacement task or branch.
- A final story approval is not a task acceptance. It must report independent
  verification separately from inspected worker evidence, and it must name
  cross-task behavior, deferred criteria and owners/evidence, checks, and
  limitations.
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
