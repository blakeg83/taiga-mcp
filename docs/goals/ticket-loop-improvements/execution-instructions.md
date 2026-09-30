# Execution instructions

Status: implemented offline. Reading or validating these documents does not
activate the ticket loop or authorize an operational run.

## Preparation and boundaries

Read [repository guidance](../../../AGENTS.md), [development](../../development.md),
[tool reference](../../taiga_tools_reference.md), the [batch overview](README.md),
the [operator guide](../../automation/README.md), and the assigned goal.
Inspect the current implementation; helper filenames below are existing touch
points or suggested small additions, not a mandate to build a new framework.
Record the starting Git revision and preserve unrelated work.

Use no subagents. Do not launch new coding chats to implement these goals.
Read the relevant skill-authoring instructions when editing the actual skill.
Planning documents alone do not change runtime contracts.

## Required cycle for every numbered step

1. Implement the scoped behavior and meaningful regression coverage.
2. Run the step's checks and resolve related failures.
3. Update implemented operator/reference documentation and this goal's
   checkboxes, results, limitations, and execution record.
4. Review and stage only the relevant changes.
5. Commit code, checks, and documentation together before the next step.
6. Report the hash; record it in the next checkpoint or final handoff rather
   than attempting to put a commit's own hash inside that commit.

Do not batch multiple numbered steps into one retrospective commit. Leave
incomplete gates unchecked. Do not backfill evidence or call an unrun check
passed. This batch's cycle applies even where historical goals recorded
several steps in one commit.

Historical deviation: this batch's earlier implementation commits did not
fully follow the ordered documentation-and-commit cycle. The goal execution
records preserve the actual checkpoint hashes, and the overview explicitly
labels this deviation; subsequent correction work follows the same offline
scope without claiming retroactive cycle compliance.

## Validation and data

Use the existing self-contained PowerShell harness and synthetic fixtures:

```powershell
pwsh -NoProfile -File tests/automation/Test-Automation.ps1
git diff --check
```

Run focused meaningful checks for each step and the full helper harness at each
goal's final checkpoint. Use injected clocks and controlled synchronization,
not sleeps as evidence. Do not add test dependencies merely for this batch.

Follow AGENTS.md's full Debug/Release .NET matrix when server, test, or build
configuration changes, and at final batch acceptance. Reuse unchanged passing
results where appropriate. Do not stop running servers to release locks; use
the documented unique external outputs if required.

Fixtures may use disposable local bare Git remotes and fake desktop, Taiga, and
GitHub observations. No tests alter live Taiga, real Cozi data, production GitHub,
or retained databases. Never copy the user's real run logs into tracked tests.

## Compatibility and operational authorization

Keep supported input shapes unless a versioned migration is explicitly
implemented and tested. Preserve active/paused run ownership, review history,
pending actions, fencing, and external state roots. Do not migrate an actual
registry merely to test the migration.

The coordinator still uses documented native chat/schedule tools; PowerShell
performs local logic and returns compact action descriptions. Do not introduce
private desktop APIs, a hidden polling daemon, or an SDK runner.

Implementation authorizes local edits, tests, and step commits. It does not
authorize starting the audited ticket again, changing installed skill copies,
creating operational chats/schedules, pushing, opening PRs, or writing live
Taiga. Reuse any later explicit operational authorization within its scope.
For a missing required operational authorization, finish the offline work and
report the actual-host gate as unverified; do not represent it as a failed
offline implementation.

## Final handoff

Report completed steps and commits, changed behavior, relevant checks, updated
documentation, compatibility/migration details, and remaining gates. Keep the
overview's status current. State separately whether offline acceptance,
installation on a named machine, actual chat behavior, and publication were
verified. Do not treat lower token count as proof of lower cost or better work.
