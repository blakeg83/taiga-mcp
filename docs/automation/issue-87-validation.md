# Issue #87: automatic review dispatch and ordered-task advancement

The repo-local `taiga-story-loop` now documents and validates the scoped
event-driven review loop. After the confirmed `Start`, a durable
`ready_for_review` event dispatches one review request to the persistent
reviewer. A current `changes_requested` finding reopens only the affected task
and routes a correction to the same pair. In `per_task` mode, exact current
reviewer acceptance performs the version-safe acceptance transition and starts
only the next declared task. In `story_end_only` mode, implementation-ready
milestones advance task order without per-task acceptance or review; final story
review owns acceptance.

Duplicate and stale events, wrong task/reviewer or revision bindings, idle
status, scope changes, and uncertain/version-conflicted writes remain
reconciliation cases. The flow never widens scope, infers acceptance, creates
a replacement worker pair, creates a PR, or merges automatically.

## Offline validation

The focused behavioral fixture is:

```powershell
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-automatic-review-flow.ps1
```

The static story-loop contract check is:

```powershell
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-scenarios.ps1
```

The repository automation harness passed 42 fixtures, including the new
automatic review-flow case. The .NET build passed with a unique external
output directory, and the .NET test suite passed 642 tests. The ordinary build
output was locked by already-running TaigaMCP processes; those processes were
left untouched as required by the repository guidance.

These checks use synthetic state and do not mutate live Taiga data, worker
chats, branches, pull requests, or production resources.
