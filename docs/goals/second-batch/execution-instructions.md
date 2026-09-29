# Execution instructions for the second batch

Status: planning instructions for later implementation. Creating these documents
does not authorize implementing every goal, launching agents, publishing, or live writes.

## Start here

Read [AGENTS.md](../../../AGENTS.md), [development](../../development.md),
[the current tool reference](../../taiga_tools_reference.md),
[batch contracts](contracts.md), [source evidence](sources.md), and the assigned
goal. The implemented baseline is 23 public tools on net8.0, SDK 10.0.401
(latestPatch), and the existing package versions.

Inspect git status and recent history; preserve unrelated changes. Record the
starting commit, assigned scope, baseline checks, and prerequisites in the
goal's execution record. Reuse the existing tests, TaigaTransport, ToolErrors,
ToolResponseJson, cancellation paths, and protocol fixtures. Do not repeat the
first-batch foundation or restore removed goal files/facades. If making a branch,
use the codex/ prefix. No worktree or branch rearrangement is needed merely to
write or execute a goal.

## Mandatory ordered step cycle

For each numbered step:

1. Implement the listed changes and appropriate focused tests.
2. Run the step's checks; fix regressions within scope. Keep contract/fixture-only
   steps runnable without checking in failing future-behavior tests or fake success stubs.
3. Update documentation during the same step: goal checkboxes/evidence, tool
   reference, README/quickstart for public changes, and inventory/batch status.
   Mark incomplete behavior as planned and do not erase deferred scope.
4. Review the diff and stage only this step's files/hunks.
5. **Commit after every completed step, before starting the next.** Include code,
   tests, and documentation in the same focused commit with an imperative subject.
   Suggested subjects are supplied in each goal.
6. Confirm the commit succeeded; report its hash. Record the previous step's hash
   in the next step's execution record and the final hash in the handoff. Do not
   rewrite commits just to embed their own hashes.

The commit checkbox can be included in its own commit; if committing fails,
uncheck it and record why. A partial checkpoint does not satisfy a completed step.
If blocked, leave affected boxes unchecked and record the missing prerequisite,
failed check, or source discrepancy. Never manufacture successful validation.

## Scope, sources, and contracts

Only execute the assigned goal and explicitly authorized prerequisites.
Dependencies in the index establish reusable code/acceptance flows, not permission
to start unrelated goals or parallel agents. Keep the default execution order.

Use pinned sources in sources.md as the starting evidence. If deployed-version
information is available, compare read-only documentation/configuration.
Record any actual version; do not claim the pinned upstream revision is deployed.
Resolve source discrepancies with fixtures and update contracts before dependent
work. Routine implementation choices within these bounds do not need permission.

Keep tools thin, with descriptions, concrete API injection, JSON-string results,
and cancellation that never appears as a public argument. New DTOs use explicit
snake_case JSON names and init accessors. Extend existing domain APIs for their
resource; proposed new APIs/files may be consolidated when equivalent code exists.
Keep ordinary response null omission separate from page metadata and PATCH nulls.

## Documentation to maintain every step

- Assigned goal: checkboxes, implementation decisions, tests/results, source
  revision, changed documentation, previous commit references, blockers.
- docs/taiga_tools_reference.md: only callable implemented contracts, defaults,
  request/response examples, errors, and remaining limits.
- README.md and docs/taiga_mcp_quickstart.md: implemented capabilities and
  practical examples; no fictional user/status IDs described as universal.
- docs/taiga_command_inventory.md and this batch's README: update only delivered
  functionality; update the tool count when a public tool is exposed.
- docs/development.md and AGENTS.md only when conventions actually change.

Use placeholders or synthetic data. Do not record credentials, tokens, real
private payloads, or raw upstream error bodies.

## Verification requirements

Use fake HttpMessageHandler/FakeTaigaHttpServer, synthetic credentials, and real
MCP sessions via the existing StrictMcpProcess fixture. Assert wire requests,
mapped responses, safe errors, argument binding, discovery, cancellation, and
unchanged existing interfaces. Use controlled barriers/TimeProvider for timing
behavior. Never modify live Taiga data for tests.

At each goal's final step run the repository's required checks:

```powershell
dotnet restore
dotnet build -c Debug
dotnet test -c Debug
dotnet build -c Release --no-restore
dotnet test -c Release --no-build --no-restore
git diff --check
```

Windows is required by the current contamination test. SDK 10 requires a separate
.NET 8 runtime for these targets; do not upgrade packages/targets to sidestep it.
If output files are locked, do not stop servers. Use a unique external OutputPath
and UseAppHost=false on the affected build/test commands. Use distinct Debug and
Release output directories, build each before its --no-build tests, and record
the exact paths/commands so tests exercise the new assembly.

Only a received 401 permits the existing one-time authentication replay.
Never retry ambiguous writes or fetch a fresh entity version and replay an edit.
Keep error bodies bounded and sanitized. A local implementation commit does not
authorize push, PR, merge, release, or live project modification.

Final handoff: completed steps and hashes, exposed tool(s), exact validation
results, definition-of-done outcome, docs updated, and remaining limitations.
