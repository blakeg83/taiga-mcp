# Minimal continuation note

Keep one short note per authorized story-loop run, outside the source
worktrees. It is a pointer to authoritative systems, not a durable workflow
engine. Store only the selected scope, ordered story/task sequence,
branch/worktree lineage, worker chats, PR identity, current stage,
approval/merge state, and recovery reference.

## Template

```text
Run: <run-id>
Scope: <project> story/epic #<ref> | stories: <ordered story refs> | tasks: <ordered task refs>
Repository: <absolute path> | remote: <name> <url>
Base: <remote>/<base-ref> @ <base-sha>
Feature: <branch> | worktree: <absolute path> | head: <sha>
Current: story #<ref> | task/stage: <ref or stage>
Story branch: <branch> | worktree: <absolute path> | base: <sha>
Implementer: <thread-id> @ <host-id> | reviewer: <thread-id> @ <host-id>
Pair: <created/reused> | IDs resolved: <yes/no> | authorization: <scope marker>
Review mode: <per_task/story_end_only> | approved HEAD: <sha or pending>
PR: <url or pending> | base: <feature branch> | head: <sha>
Review: <pending/approved/changes_requested>
Merge: <pending/merged/closed_unmerged/unknown>
Next: <one concrete action>
Recovery: <automation-id or none>
```

Values are updated only after their source system confirms a change. Keep the
previous note recoverable, and never use a note's claim as proof that a Git,
Codex, PR, or Taiga mutation succeeded.

## Resume reconciliation

On restart, process the note in this order:

1. Verify the repository path, remote URL, base mapping, feature branch, and
   recorded HEAD with Git. Fetch only after the run is authorized. A dirty user
   checkout remains untouched.
2. Inspect existing managed worktrees and branches for the recorded feature and
   story identities. If the path, branch, repository, and base match, reuse the
   object. If a create returned an unknown outcome, inspect before retrying.
3. Inspect the recorded implementer/reviewer thread and host IDs, pair outcome,
   and PR URL. Reuse matching chats/PRs; do not create duplicates because the
   note is stale or incomplete. A pending client ID is not a worker ID; resolve
   it through the authoritative thread inventory before messaging.
4. Read Taiga status/comments and the provider's PR state, then refresh the
   note with the authoritative result. Conflicting ownership or lineage is a
   blocker for user input.

Resume returns to the recorded current stage. A failed review uses the same
story checkout. A missing or unconfirmed external result remains pending or
unknown; it is never treated as success by timeout.

## Approved-merge advancement

The next story branch may be created only when all of these are observed:

- the current PR's base is the recorded feature branch;
- the provider reports the PR merged, not merely approved or closed;
- the merge result is reconciled to the repository and the feature branch has
  the updated authoritative HEAD; and
- the continuation note records `Merge: merged` and a new `Next` action.

If the PR is open or changes are requested, continue the current story. If it
is closed without merge, conflicting, or response-lost, keep the current story
waiting and ask for reconciliation or user input. Do not create the next story
branch from a stale local feature checkout, the story head, or the default
branch. Once a merge is confirmed, capture the updated feature HEAD and use
that SHA as the next story's base.
