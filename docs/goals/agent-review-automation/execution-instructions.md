# Execution instructions

Status: instructions for future implementation. This documentation task does not implement or activate the workflow.

## Prerequisites

Read [repository guidance](../../../AGENTS.md), [development](../../development.md),
[implemented tool reference](../../taiga_tools_reference.md), [project overview](README.md),
[contracts](contracts.md), [sources](sources.md), and the assigned goal.

Inspect git status, preserve unrelated changes, and record the starting revision.
Use `codex/` for any new branch. Keep the current target frameworks and dependency versions.
Do not launch subagents to implement this project.

## Mandatory cycle for every numbered step

1. Implement only the assigned step and meaningful checks for its behavior.
2. Run the step validation; repair in-scope failures.
3. Update the goal's evidence and checkboxes plus implemented documentation in the same step.
4. Review the diff and stage only relevant files/hunks.
5. **Commit after each completed step before beginning the next step.** Include code, checks, and documentation together.
6. Confirm the commit succeeded and report its hash. Record the preceding hash in the next step; report the final hash in the handoff rather than rewriting commits to include their own hashes.

Every goal supplies a commit subject. Leave failed/incomplete steps unchecked.
A checkpoint commit is not proof of completion. Do not fabricate passing tests or actual model settings.

## Delivery sequence

Execute goals 01–09 in order. Goals 01–06 build/test the core, 07 adds fresh branches and PR lifecycle, 08 enables parallel dispatch, and 09 completes epic coordination and release acceptance. Intermediate goals must expose only delivered behavior; do not advertise the core as the complete release.

## Documentation during implementation

Maintain the assigned goal's execution record and the project overview's status.
Create/update `docs/automation/` only as behavior ships, including configuration,
recovery instructions, limitations, and examples. Keep proposed and implemented behavior distinct.
Update the repository README when the skill is usable. The implemented MCP tool
reference/count changes only if a separately scoped API change actually ships; v1 expects 35 tools.

Record capability checks, runtime versions, exact commands/results, model settings,
mock versus actual app evidence, review commits, and deviations. Commit synthetic
fixtures and sanitized summaries only. Keep actual run state and private ticket content outside Git.

## Testing and external effects

Offline tests must cover state transitions, process concurrency, interruption,
handoff receipts, verdict parsing, Git branch/base behavior, fake GitHub PR/check/merge observations, concurrent scheduling, epic acceptance, and Taiga adapter requests. Fake the desktop
tool observations and Taiga responses. Fixture success verifies logic, not that a
host actually exposes chat/scheduling tools.

Use deterministic barriers and an injected clock for leases/recovery; do not rely
on sleeps to prove concurrency. Test PowerShell 7 scripts with a self-contained
PowerShell harness that exits nonzero on failures; no new Pester dependency is required.
Use temporary paths, local bare Git remotes, fake GitHub adapters and synthetic identities. No test modifies live Taiga data or production GitHub repositories. A local bare-remote push verifies Git behavior without publication.

Actual chat/scheduler smoke tests require explicit authorization to create the
specified ordinary chats and schedule. Goal 06 provides the core invocation; goal 09 provides expanded concurrency/epic acceptance. Actual GitHub connectivity is read-only unless an explicitly named disposable repository is separately authorized for a publish exercise.
Do not treat a received worker message as permission to contact unrelated chats.
An operational run's initial instruction should explicitly authorize creating or
reusing selected worker chats, coordinating their messages, feature branches/worktrees, required ticket writes, branch pushes/PR creation or updates, and optional scheduled continuation/merge observation. Automatic merge remains disabled. Reuse that authorization throughout its scope.

Pause and cancellation must not be simulated by silently abandoning active workers.
Never stop published MCP servers to free output locks. Do not use shell deletion
to clean managed worktrees; use app lifecycle tools only when no process needs them.

## Validation gates

Run the helper/fixture suite at each behavior-changing step. At each goal's final
step run `git diff --check` and the meaningful checks listed in that goal.
Run the full .NET matrix when server/tests/build configuration are touched and
at the core gate and final project acceptance, reusing unchanged passing results where appropriate:

```powershell
dotnet restore
dotnet build -c Debug
dotnet test -c Debug
dotnet build -c Release --no-restore
dotnet test -c Release --no-build --no-restore
```

If outputs are locked, use unique external Debug/Release outputs with
`-p:UseAppHost=false`, build before no-build testing, and record the exact paths.
Do not repeat unchanged tests merely to fill a checklist.

## Final handoff

Report completed steps and commit hashes, relevant checks/results, current
definition-of-done status, updated docs, and remaining limitations. Distinguish
offline correctness, verified host operation, and a separately authorized production run.
Implementing this project does not authorize pushing its code, opening its PR, merging, or starting operational runs. Later explicitly authorized ticket runs may push owned branches and create/update PRs automatically according to the configured policy; that authority does not include merging.
