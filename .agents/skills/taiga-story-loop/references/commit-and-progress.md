# Per-task commits and parent-story progress comments

Each ordered task is implemented on the story branch and produces one
reconciled progress record. A task record is not a new branch, chat, or pull
request. The story owns those integration objects.

## Commit boundary

After the task checklist has direct evidence and the required checks have
finished, inspect the worktree and commit the task's complete change:

```text
git status --short
git diff --check
git add <task-scoped paths>
git commit -m "<short imperative task subject>"
git rev-parse HEAD
```

The implementation worker must report the exact commit SHA and changed paths.
Do not add `bin/`, `obj/`, `.vs/`, credentials, temporary files, or unrelated
user changes. If the task made no file change, run the relevant read-only check
and report `no-change-verified`; do not invent an empty commit. A failed check
or unresolved blocker is not task completion and must not receive a
`ready-for-review` completion record.

The commit is the revision named by the task's review handoff. A later task
must not alter an earlier task's commit; later changes belong to a later task
commit. If a review correction changes an earlier task, reopen only that task,
make a new commit, and link the new SHA to the correction evidence.

## Completion comment

After the commit is confirmed, read the parent story's current version and
visible comments. Add one concise Markdown comment with a stable idempotency marker:

```text
Task #<ref> complete | commit: <sha-or-no-change-verified> | state: ready_for_review

Summary: <what changed and why>
Checklist: [x] <criterion> — <evidence>; [ ] <criterion> — <truthful reason>
Checks: `<command>` — exit <code>; <evidence or unavailable reason>
Review: pending independent review; acceptance/Done not claimed
Next: <next ordered task or specific review action>
```

Write it through the story comment operation with the current story version:

```text
mcp__taiga__get_user_story({ userStoryId })
mcp__taiga__add_work_item_comment({
  kind: "user_story", id: userStoryId, version, text: completionComment
})
```

The comment names the task ref, summary, checklist outcome, checks and actual
exit codes, commit/no-change result, review state, and next action. It is
progress evidence, not proof of review acceptance, PR approval, merge, or
Taiga Done.

## Blocker comments and resume idempotency

For a blocker, immediately comment on the parent story using a distinct marker:

```text
Task #<ref> blocked | status: <status> | version: <version>

Obstacle: <specific blocker>
Attempted: <work and checks>
Evidence: <failed command/response/history reference>
Decision needed: <exact help or external change>
Dependent tasks: not started
```

Notify the coordinator in the same handoff and stop dependent tasks. Do not
emit empty periodic comments. On resume, list the parent-story comments before
writing: if the exact task/ref, commit SHA, and completion marker already
exist, reconcile the task status/version and reuse that evidence instead of
adding a duplicate. A changed revision, new checklist evidence, or substantive
review correction requires a new commit and a new comment that points to the
new SHA; it must not overwrite the old record.

An opaque comment-write error is uncertain. Re-read the story and comment pages
before retrying. If the marker is present, treat the comment as submitted; if
it is absent, retry only with the newly authoritative story version. Preserve
all human comments and report an unresolved result when the pages are
incomplete.
