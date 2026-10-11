# Issue #90: end-of-turn review handoffs

The repo-local `taiga-story-loop` now defines one ready/correction-ready
endpoint: confirm direct delivery to the required reviewer, record the current
task and full pending revision in `awaiting_review`, send one concise final
response, and end the implementer turn. The implementer does not poll or read
the reviewer chat, run a review monitor, send keep-alive or unchanged
acknowledgements, or edit source while review is pending.

Reviewer findings and exact-revision acceptance resume the same implementer
chat only after sender, task, revision, branch, and prior-outcome checks. Stale
or duplicate messages are no-ops. Failed or unknown delivery is an exceptional
coordinator reconciliation and never a confirmed review wait. Healthy idle
`awaiting_review` recovery does not wake the worker.

## Offline validation

The focused checks are:

```powershell
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-task-execution.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-routing.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-automatic-review-flow.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-continuation-note.ps1
pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-scenarios.ps1
git diff --check
```

The automatic review-flow fixture derives initial and correction-ready turn
termination from the action trace, validates the terminal handoff suffix after
authorized preceding work, rejects source edits and coordinator copies after
the final response until a validated reviewer resume, distinguishes healthy
recovery from unresolved delivery escalation, and covers
duplicate/stale outcomes, failed delivery, and explicit rejection of
implementer `wait_threads`, reviewer reads, monitors, keep-alives, and
unchanged acknowledgements. It also carries task #65 through acceptance,
Taiga reconciliation, and advancement before dispatching task #66, proving
that the next ordered task can end the same implementer turn with a valid
terminal handoff. The other fixtures cover ordered-task evidence, direct
routing, snapshot recovery, and static contract consistency.

Observed results for this implementation:

```text
validate-task-execution.ps1       passed
validate-routing.ps1              passed
validate-automatic-review-flow.ps1 passed
validate-continuation-note.ps1    passed
validate-scenarios.ps1             passed
Test-Automation.ps1                Passed 44 automation fixtures.
git diff --check                   passed
```

No live worker trial was separately authorized or run for this issue. Offline
fixtures therefore provide implementation evidence only; live chat turn
termination and message-driven resume remain pending separate authorization.

The story #208 follow-up adds the coordinator-side terminal action trace and
persisted continuation checks for both story review modes and the integrated
epic pair; see [story #208 validation](story-208-validation.md) for the
combined command matrix and evidence limits.
