# Clean committed revision contract

Every review handoff, acceptance, and delivery preflight uses the same immutable
review input. It is a tuple, not only a commit identifier:

```text
Repository: <absolute repository path>
Worktree: <absolute worker worktree path>
Branch: <expected branch name>
Base: <captured base SHA>
Reviewed SHA: <full 40-character SHA copied from `git rev-parse HEAD`>
Diff: <base SHA>..<reviewed SHA> | relevant diff range and changed paths
Source state: clean tracked source
Ignored verification outputs: <none or declared ignored paths>
```

The implementer establishes this input only after source changes are complete
and committed. Before sending a ready or correction handoff, verify the
repository root, expected branch, exact full `HEAD`, and source state in the
expected worktree:

```text
git -C <worktree> rev-parse --show-toplevel
git -C <worktree> branch --show-current
git -C <worktree> rev-parse HEAD
git -C <worktree> diff --quiet HEAD --
git -C <worktree> diff --cached --quiet
git -C <worktree> ls-files --others --exclude-standard
git -C <worktree> diff --name-status <base-sha>..<reviewed-sha>
```

The two diff checks must be quiet, and the non-ignored untracked-file query
must return no paths. This is the clean tracked-source state. Verification may
produce build or test files under declared ignored paths; those files do not
change the review input when the tracked-source checks remain clean. An
unexpected ignored path is still evidence to reconcile, not a reason to hide a
source change.

The reviewer repeats the identity and source-state checks before inspecting and
before accepting. Acceptance and PR delivery are held when the branch,
worktree, `HEAD`, diff range, or clean tracked-source state no longer matches
the pending input. Preserve any change and escalate a revision conflict. Do
not reset, clean, stash, force-push, or silently substitute another revision.

An authorized correction is a new review input. It records the previous
reviewed SHA, the new full SHA, and the new diff/range or changed-path delta;
approval for the previous SHA is stale and the same worker pair must re-review
the new input. A source edit or later-task change is not permitted while a
per-task review is pending.
