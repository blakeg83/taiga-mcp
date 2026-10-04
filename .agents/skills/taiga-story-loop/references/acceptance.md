# Task and story acceptance

Review mode is part of the confirmed setup. `per_task` is the default: the
implementer pauses after each task-ready handoff until the reviewer accepts
that exact revision. `story_end_only` is an explicit alternative shown in the
setup summary; the implementer may complete the ordered task commits before a
single final review, but findings still route to the same pair and no approval
is implied by implementation evidence.

## Task acceptance

After inspecting the exact revision and all task criteria, the reviewer sends
the acceptance directly to the implementer and the coordinator:

```text
Task #<ref> accepted
Reviewed: <exact commit SHA>
Criteria: <criterion/result summary>
Checks: `<command>` — exit <code>; <concise result>
Next: implementer, update the task in Taiga and advance to the next ordered task.
```

The implementer may then update the task's checklist/status using the current
Taiga version and begin the next task only when the selected review mode allows
it. A task acceptance is bound to the named SHA; a later source change
supersedes it and requires a new ready handoff and review. A reviewer never
accepts a SHA it did not inspect.

## Final story acceptance

After the last task's required reviews, the reviewer checks the complete story
against its definition of done, ordered-task evidence, cross-task behavior, and
the current branch HEAD. The reviewer sends the coordinator:

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
approval. The resulting PR is a delivery artifact targeting the integration
feature branch, not a merge. Its base, head, checks, review profile, and exact
URL are recorded before asking for the separate merge decision.

The merge decision follows [the Yes/No story merge gate](merge-approval.md).
Only an explicit Yes for the exact displayed PR authorizes an attempt. No,
silence, stale approval, failed merge, or unknown provider result leaves the
story waiting and cannot release the next ordered story.

When the scope is an epic, all story merges are followed by the [final
integrated epic review](final-epic-review.md) at `gpt-6.1-sol`/`high` before
final PR delivery. A single-story scope uses final story acceptance instead;
the epic review is not added as an unnecessary gate.

## Mode selection

The setup summary must display `Review mode: per_task (default)` and
`story_end_only (optional)`. The user's selected mode is recorded with the
authorization and passed to both prompts. It cannot be changed by a worker
message. If the user changes mode or scope, regenerate setup and obtain a new
confirmation.
