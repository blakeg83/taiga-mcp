# Issue #93: acceptance reconciliation and ordered advancement

The repo-local `taiga-story-loop` now treats reviewer acceptance as durable
evidence delivered to the implementer, not as a Taiga write result. The
implementer owns a `task + exact reviewed SHA` acceptance journal and completes
the task status/checklist write and parent-story progress comment as separate,
current-version operations before advancing.

The automatic-flow fixture uses a synthetic Taiga provider with controlled
barriers. It covers normal acceptance, duplicate acceptance with a different
message ID, stale task/SHA binding, human edits between read and write,
applied-but-response-lost task writes, an interrupted task/comment sequence,
final-task handoff, and final-review acceptance in `story_end_only`. Recovery
reads authoritative task/story state and reuses marker evidence; it does not
blindly retry a confirmed write, add duplicate comments, close another task,
or advance twice. Final task and story acceptance leave merge/release as
separate gates.

## Offline validation

```powershell
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-task-execution.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-automatic-review-flow.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-routing.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-scenarios.ps1
git diff --check
```

These fixtures use synthetic/disposable state only. They do not write live
Taiga data, worker chats, branches, pull requests, or release state.
