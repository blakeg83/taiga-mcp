# Goal 05: list_task_statuses

Status: delivered; implemented by this document.

## Objective

Let agents discover task workflow IDs before changing task progress.

## Scope and prerequisites

One page of task statuses with id/project/name/slug/order/color/is_closed. Do not expose story-only is_archived/wip_limit, status mutation, or cross-project aggregation.

Prerequisites: [goal 04](04-list-user-story-statuses.md).
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `list_task_statuses(projectId, page=1)`.
- Result: Standard page envelope with actual task status IDs/closure flags in server order.
- API operation: GET task-statuses?project={projectId}&page={page}.
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

- `Api/TaskApi.cs`
- `Tools/TaskTools.cs`
- `Models/TaskStatusDto.cs`
- `tests/TaigaMCP.Tests/TaskStatusTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify task-specific metadata

- [x] Compare the task serializer with the goal 04 story serializer; record that task statuses lack story archive/WIP fields.
- [x] Prepare localized names, open status named Done, and closed status with a non-English name.
- [x] Reuse only shared pagination/validation fixtures, not a DTO that invents unsupported fields.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify list_task_statuses contracts`.

## Step 2: Implement task status retrieval

- [x] Extend TaskApi with a project-scoped one-page GET through TaigaTransport.
- [x] Map positive identity/project and available label/order/color/closure fields; preserve false/zero.
- [x] Keep task list/detail/update behavior and existing status extra-info mapping unchanged.
- [x] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [x] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_task_statuses API behavior`.

## Step 3: Expose task status lookup

- [x] Add list_task_statuses to TaskTools with required projectId, optional page, and internal-ID descriptions.
- [x] Document get_task -> choose a returned task status -> update_task; never use a story status ID in the example.
- [x] Add MCP discovery/schema/argument binding tests.
- [x] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [x] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_task_statuses MCP tool`.

## Step 4: Verify task workflow selection

- [x] Use a returned status ID in a fake-HTTP update_task call and confirm the exact PATCH key/version.
- [x] Test custom flags/names, no unsupported archive fields, empty/later pages, invalid project/page, 403, and cancellation.
- [x] Retain blocking/unblocking and explicit assignee-clearing regression coverage.
- [x] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [x] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_task_statuses workflows`.

## Acceptance scenarios

- [x] Task-specific status IDs and actual closure flags are available without guessing names.
- [x] Unsupported story metadata does not appear.
- [x] Status lookup composes with current task updates and preserves existing interfaces.
- [x] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [x] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [x] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [x] Agents can choose valid task workflow statuses through a paged read tool.
- [x] All four ordered steps and acceptance scenarios have passing recorded validation.
- [x] Schema inspection and real MCP calls agree with the documented interface.
- [x] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [x] Current documentation names only delivered functionality and preserves deferred scope.
- [x] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [x] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `3705c2c` (`master`). Source evidence is pinned taiga-back
revision `4d11baef9027f5598f6341d6eb4261de2840688e`; no live deployment version
was checked or claimed.

Step 1 contract decisions: task statuses use the project-scoped
`task-statuses?project={projectId}&page={page}` route and expose only `id`,
`project`, `name`, `slug`, `order`, `color`, and `is_closed`. They do not reuse
the story-status DTO because `is_archived` and `wip_limit` are story-only fields.
Fixtures cover an open status named `Done`, a closed status with the localized
name `Terminé`, zero order, false closure, null color, and the absence of
story-only metadata. These are source-backed contract fixtures, not live data.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline focused story-status check: `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug --no-restore --filter FullyQualifiedName~UserStoryStatusTests` — 9 passed. Added task-specific DTO/fixture serialization checks; source revision and field deviations recorded above. | Specify list_task_statuses contracts / `61b2131` |
| 2 | Complete | `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug --no-restore --filter FullyQualifiedName~TaskStatusTests` passed 8 tests; `dotnet build -c Debug --no-restore` passed with 0 warnings/errors; `git diff --check` passed. API tests cover route/query, mapping, trusted pagination, invalid IDs/page, malformed required data, project mismatch, empty-page metadata, and pre-cancellation. Public tool remained planned at this checkpoint. Previous commit: `61b2131`. | Implement list_task_statuses API behavior / `8163734` |
| 3 | Complete | Production MCP integration verifies 28-tool discovery, exact `projectId/page` schema and required arguments, omitted/default/null binding boundaries, successful page calls with task-only fields, and safe invalid-input errors. Public docs/reference/README/quickstart/inventory updated to 28 delivered tools. Previous commit: `8163734`. | Expose list_task_statuses MCP tool / `b0fe7ed` |
| 4 | Complete | Returned task IDs drive task filtering and a versioned `update_task` PATCH; the body contains the returned `status` and exact caller version `2`. Task fixtures/tests cover localized/custom names, open/closed flags, empty/later pages, unsupported story fields, invalid IDs/page, project mismatch, 403, malformed data, cancellation, and existing blocking/assignee-clear behavior. Required validation: `dotnet restore` passed; `dotnet build -c Debug` passed with 0 warnings/errors; `dotnet test -c Debug` passed 399/399; `dotnet build -c Release --no-restore` passed with 0 warnings/errors; `dotnet test -c Release --no-build --no-restore` passed 399/399 on rerun after one transient temporary-copy cleanup lock; `git diff --check` passed. Debug outputs: `bin/Debug/net8.0/` and `tests/TaigaMCP.Tests/bin/Debug/net8.0/`; Release outputs: `bin/Release/net8.0/` and `tests/TaigaMCP.Tests/bin/Release/net8.0/`. Previous commit: `b0fe7ed`. | Verify list_task_statuses workflows / pending (this commit) |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
