# Goal 05: list_task_statuses

Status: planned; not implemented by this document.

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

- [ ] Compare the task serializer with the goal 04 story serializer; record that task statuses lack story archive/WIP fields.
- [ ] Prepare localized names, open status named Done, and closed status with a non-English name.
- [ ] Reuse only shared pagination/validation fixtures, not a DTO that invents unsupported fields.
- [ ] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [ ] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify list_task_statuses contracts`.

## Step 2: Implement task status retrieval

- [ ] Extend TaskApi with a project-scoped one-page GET through TaigaTransport.
- [ ] Map positive identity/project and available label/order/color/closure fields; preserve false/zero.
- [ ] Keep task list/detail/update behavior and existing status extra-info mapping unchanged.
- [ ] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [ ] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_task_statuses API behavior`.

## Step 3: Expose task status lookup

- [ ] Add list_task_statuses to TaskTools with required projectId, optional page, and internal-ID descriptions.
- [ ] Document get_task -> choose a returned task status -> update_task; never use a story status ID in the example.
- [ ] Add MCP discovery/schema/argument binding tests.
- [ ] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [ ] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_task_statuses MCP tool`.

## Step 4: Verify task workflow selection

- [ ] Use a returned status ID in a fake-HTTP update_task call and confirm the exact PATCH key/version.
- [ ] Test custom flags/names, no unsupported archive fields, empty/later pages, invalid project/page, 403, and cancellation.
- [ ] Retain blocking/unblocking and explicit assignee-clearing regression coverage.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_task_statuses workflows`.

## Acceptance scenarios

- [ ] Task-specific status IDs and actual closure flags are available without guessing names.
- [ ] Unsupported story metadata does not appear.
- [ ] Status lookup composes with current task updates and preserves existing interfaces.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] Agents can choose valid task workflow statuses through a paged read tool.
- [ ] All four ordered steps and acceptance scenarios have passing recorded validation.
- [ ] Schema inspection and real MCP calls agree with the documented interface.
- [ ] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [ ] Current documentation names only delivered functionality and preserves deferred scope.
- [ ] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [ ] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: pending. Source/deployment evidence: pending; do not claim a live
deployment version from upstream source alone.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Not started | — | Specify list_task_statuses contracts / pending |
| 2 | Not started | — | Implement list_task_statuses API behavior / pending |
| 3 | Not started | — | Expose list_task_statuses MCP tool / pending |
| 4 | Not started | — | Verify list_task_statuses workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
