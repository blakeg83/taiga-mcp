# Task and story acceptance

Review mode is part of the confirmed setup. `per_task` is the default: the
implementer ends its turn after each task-ready or correction-ready handoff
and resumes on an authorized reviewer message until the reviewer accepts
that exact revision. `story_end_only` is an explicit alternative shown in the
setup summary; the implementer may complete the ordered task commits before a
single final review, but findings still route to the same pair and no approval
is implied by implementation evidence.

The task-acceptance route is reviewer-to-implementer. The implementer owns the
version-safe Taiga reconciliation and ordered-task advancement permitted by
the selected review mode; the coordinator is not copied on this routine
milestone.

## Task acceptance

The reviewer first checks the task's declared reviewable endpoint: artifact,
expected outcome, deferred criteria and owner, and advancement gate. The task
may be accepted at an expected-red checkpoint only when the contract names the
permitted behavior/tests, the observed failure reason matches that checkpoint,
and the relevant safety checks pass. A nonzero command exit alone, an
unexpected failure, or missing regression/safety coverage is a finding and
cannot release the next task.

After inspecting the exact revision and all task criteria, the reviewer sends
the acceptance directly to the implementer:

```text
Task #<ref> accepted
Reviewed: <exact commit SHA>
Criteria: <criterion/result summary>
Checks: `<command>` — exit <code>; <concise result>
Next: implementer, reconcile the current Taiga version and advance to the next ordered task.
```

The implementer then rereads the task, merges only evidence-backed checklist
changes, writes the accepted status using the current Taiga version, records
the parent-story progress evidence, and begins the next task only when the
selected review mode allows it. No coordinator acknowledgement, next-task
assignment, or reminder is an additional gate. A task acceptance is bound to
the named SHA; a later source change
supersedes it and requires a new ready handoff and review. A reviewer never
accepts a SHA it did not inspect.

Before applying acceptance, follow the identity, current pending revision, and
already-handled outcome checks in [message-driven resume](worker-handoffs.md#message-driven-resume).
A duplicate acceptance is a no-op; acceptance for an old task/revision cannot
release the current gate. Reconcile an unknown Taiga write before another
attempt. Idle chat status and elapsed time are not acceptance evidence.

The scoped workflow may deliver this handoff automatically after a durable
current acceptance event in `per_task` mode. The implementer must verify
reviewer identity, task identity, exact SHA, the immutable `Start`
authorization and assignment identity, criteria, and current Taiga version
before writing, then release only the next ordered task. In
`story_end_only` mode, implementation-ready evidence advances task order
without task acceptance or per-task review; the final story review accepts the
retained task revisions. A stale, duplicate, changed-scope, or uncertain event
stops at reconciliation.

## Final story acceptance

After the last task's required reviews, the reviewer checks the complete story
against its definition of done, ordered-task evidence, cross-task behavior, and
the current branch HEAD. The reviewer sends the coordinator:

Final story acceptance must also prove every deferred criterion through its
named later task or story-review owner and must verify that required regressions
that were intentionally red at an earlier checkpoint are now green. An
unresolved expected RED, unexpected failure, missing regression coverage, or
deferred criterion without evidence is a rejection/blocker, not a partial
approval.

```text
Story #<ref> approved
Reviewed HEAD: <exact commit SHA>
Tasks: <ordered task refs and acceptance state>
Definition of done: <criterion/result summary>
Checks: `<command>` — exit <code>; <concise result>
Next: coordinator, use this HEAD for the story PR/review decision.
```

Only the coordinator may treat this message as final story approval or prepare
the story PR. A task acceptance alone cannot create the PR. Before using the
approval, the coordinator verifies that the story branch still points at the
reviewed HEAD and that the requirements and scope are unchanged. Any source
commit, branch movement, material task change, or new review finding makes the
approval stale; the affected work returns through the same implementer/reviewer
pair. A comment, timeout, or unchanged Taiga status cannot substitute for the
reviewer's exact HEAD approval.

The coordinator follows [reviewed story PR delivery](pr-delivery.md) after this
approval. For a new standalone story, the resulting delivery PR targets
`master` directly. For an epic, it targets the shared integration feature
branch. An active legacy standalone run targets its preserved feature branch
as the compatibility exception. In every case it is a delivery artifact, not
a merge: its topology, base, head, checks, review profile, and exact URL are
recorded before asking for the separate merge decision.

The merge decision follows [the Yes/No story merge gate](merge-approval.md).
Only an explicit Yes for the exact displayed PR authorizes an attempt. No,
silence, stale approval, failed merge, or unknown provider result leaves the
story waiting and cannot release the next ordered story. A verified merge in a
legacy standalone run proceeds only to its preserved final feature-to-`master`
delivery; it never dispatches another story.

When the scope is an epic, all story merges are followed by the [final
integrated epic review](final-epic-review.md) at `gpt-6.1-sol`/`high` before
final feature-to-master PR delivery. An active legacy standalone run skips the
epic review but requires a separate final legacy review of the refreshed
preserved feature HEAD before the final feature-to-master PR. A new standalone
story uses its final story acceptance as the exact-HEAD review for the
direct-to-master story PR; the epic review and a second feature-to-master PR
are not added.

Final delivery follows [final feature-to-master delivery](final-delivery.md).
Opening that PR hands the user a release candidate and never claims epic or
master completion. Final master merge remains a separate user decision.

## Mode selection

The setup summary must display `Review mode: per_task (default)` and
`story_end_only (optional)`. The user's selected mode is recorded with the
authorization and passed to both prompts. It cannot be changed by a worker
message. If the user changes mode or scope, regenerate setup and obtain a new
confirmation.
