# Goal 06: list_epic_statuses

Status: in progress; MCP exposure complete, final verification in progress.

## Objective

Provide valid epic workflow IDs for creation and the planned epic update command.

## Scope and prerequisites

One page of epic statuses with id/project/name/slug/order/color/is_closed. Defer workflow administration, name-to-ID shortcuts, and status caching.

Prerequisites: [goal 04](04-list-user-story-statuses.md).
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `list_epic_statuses(projectId, page=1)`.
- Result: Standard page envelope; include open and closed choices and preserve server order.
- API operation: GET epic-statuses?project={projectId}&page={page}.
- Source evidence: the Memberships and statuses rows in [pinned sources](sources.md).
  Record revision/version and any verified deviations before implementation.

Illustrative MCP arguments (synthetic IDs):

```json
{
  "projectId": 12,
  "page": 1
}
```

## Files and integration points

- `Api/EpicApi.cs`
- `Tools/EpicTools.cs`
- `Models/EpicStatusDto.cs`
- `tests/TaigaMCP.Tests/EpicStatusTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify epic workflow lookup

- [x] Verify the epic serializer and project filtering; omit unsupported archival/WIP fields.
- [x] Add fixtures for custom open/closed names and missing optional color/order fields where supported.
- [x] Define validation/mapping behavior consistently with the other new status readers.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify list_epic_statuses contracts`.

## Step 2: Implement epic status reads

- [x] Extend EpicApi with authenticated one-page retrieval using TaigaTransport and existing page parsing.
- [x] Validate identity/project, preserve numeric IDs and closure booleans, and do not filter out closed statuses.
- [x] Avoid changing list_epics filters or introducing status caches that treat one page as a complete map.
- [x] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [x] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_epic_statuses API behavior`.

## Step 3: Expose the lookup

- [x] Add list_epic_statuses to EpicTools with clear epic-specific IDs and pagination descriptions.
- [x] Document choosing a status for existing create_epic and future update_epic; label the latter planned until goal 08 ships.
- [x] Add MCP schema/discovery/call coverage.
- [x] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [x] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_epic_statuses MCP tool`.

## Step 4: Verify epic status selection

- [ ] Fetch a synthetic status and pass its ID to create_epic; goal 08 adds the closing/reopening workflow.
- [ ] Cover flags independent of names, empty/later pages, malformed identity, disabled/inaccessible project errors, and cancellation.
- [ ] Check all existing epic detail/create/link/list response contracts remain unchanged.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_epic_statuses workflows`.

## Acceptance scenarios

- [ ] All project epic status choices can be paged, including closing statuses.
- [ ] The result uses actual IDs/flags and composes with epic creation.
- [ ] No unrelated epic or project state changes occur.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] Agents can discover project epic status options before creating or editing epics.
- [ ] All four ordered steps and acceptance scenarios have passing recorded validation.
- [ ] Schema inspection and real MCP calls agree with the documented interface.
- [ ] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [ ] Current documentation names only delivered functionality and preserves deferred scope.
- [ ] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [ ] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `25432f4` (`Merge pull request #49 from blakeg83/codex/list-task-statuses`).
Source/deployment evidence: verified against pinned taiga-back revision
`4d11baef9027f5598f6341d6eb4261de2840688e`; this is source evidence, not a live
deployment claim.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline `dotnet test -c Debug`: 399 passed. Added contract fixtures/tests for localized open/closed names, zero order, missing order/color, and null omission. Verified `EpicStatusSerializer` fields and project filter against pinned revision `4d11baef9027f5598f6341d6eb4261de2840688e`; no deviation. | Specify list_epic_statuses contracts / `551f15b` |
| 2 | Complete | `EpicApi` now requests one authenticated `GET epic-statuses?project={projectId}&page={page}` and returns the standard page metadata. It maps `id/project/name/slug/order/color/is_closed`, preserves open and closed server order, rejects nonpositive inputs, malformed IDs, and mismatched projects, and does not use a cache or alter `list_epics`. Focused `EpicStatusTests`: 9 passed; full `dotnet test -c Debug`: 408 passed; `git diff --check`: passed. | Implement list_epic_statuses API behavior / `0fcaf25` |
| 3 | Complete | Added `list_epic_statuses` with `projectId` required and `page=1` default; no cancellation argument is exposed. Real MCP discovery/schema and calls cover default/page 2, missing/null argument failures, page metadata, closed choices, omission of story-only fields, and composing a returned ID with `create_epic`. Focused status tests: 9 passed; focused real MCP checks: 2 passed; full `dotnet test -c Debug`: 408 passed; `git diff --check`: passed. Updated README, tool reference, quickstart, command inventory, and batch index to 29 tools. | Expose list_epic_statuses MCP tool / pending |
| 4 | Not started | — | Verify list_epic_statuses workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
