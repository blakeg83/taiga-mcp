# Issue #89: direct routine milestone routing

The repository-local `taiga-story-loop` no longer wakes or copies routine
milestones to the coordinator. The persistent pair now uses this route:

| Milestone | Route |
| --- | --- |
| Initial task-ready | implementer → reviewer |
| Findings | reviewer → implementer |
| Correction-ready | implementer → same reviewer |
| Per-task acceptance | reviewer → implementer |
| Final story approval | reviewer → coordinator |
| Blockers, disagreements, missing identities, unknown delivery, revision conflicts | worker → coordinator |

After exact task acceptance, the implementer rereads the current Taiga
version, applies the accepted checklist/status/progress reconciliation, and
advances only the next declared task when the selected review mode permits it.
The coordinator does not acknowledge, assign, or remind the pair for these
ordinary milestones. `story_end_only` still advances from implementation
evidence without per-task reviews and still requires final whole-story approval.

The coordinator remains the owner of the compact continuation snapshot. Git
commits, Taiga task/story evidence, confirmed worker messages, and compact
worker status remain authoritative; the snapshot is not an acceptance receipt
or a replacement state registry. Healthy `awaiting_review` waits remain quiet,
while final approval and actionable exceptions still trigger reconciliation.

## Offline validation

The focused fixtures are:

```powershell
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-routing.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-automatic-review-flow.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-continuation-note.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-scenarios.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-merge-approval.ps1
pwsh -NoProfile -File tests/automation/Test-Automation.ps1 -Only 'keep routine story corrections within the persistent worker pair'
pwsh -NoProfile -File tests/automation/Test-Automation.ps1 -Only 'automate review dispatch and ordered task advancement'
pwsh -NoProfile -File tests/automation/Test-Automation.ps1 -Only 'reconcile stale story-loop snapshots without replaying milestones'
git diff --check
```

The fixtures use synthetic state and exercise two ordered tasks, correction
rounds, both review modes, duplicate/stale outcomes, and coordinator recovery
from a snapshot that still points at task #77 after the pair has independently
accepted it and advanced to task #78. The recovery fixture asserts that
reconciliation derives the current task, revision, and evidence from the
authoritative acceptance, confirmed Taiga write, ordered advancement, and
worker cursors. It updates only the compact pointer: it does not duplicate
worker messages, Taiga writes, or task advancement, including on a repeated
resume. Missing or conflicting acceptance/write/worker evidence holds the
stale snapshot without rewriting it or replaying external actions.
The remaining fixtures cover exact-HEAD approval and an unanswered merge gate.
They do not launch workers, mutate live Taiga/GitHub data, or measure live
token/cost savings.
