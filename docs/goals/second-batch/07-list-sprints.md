# Goal 07: list_sprints

Status: planned; not implemented by this document.

## Objective

Let agents find existing sprints and use their IDs to schedule stories or standalone tasks.

## Scope and prerequisites

One page of project milestones with id/project/name/slug/estimated_start/estimated_finish/closed. Optional closed filter: omitted means all, false means open, true means closed. Defer sprint creation/editing, statistics, date filters, and nested work-item expansion.

Prerequisites: the implemented first-batch baseline; no new function dependency.
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `list_sprints(projectId, page=1, closed=null)`.
- Result: Standard page envelope with lightweight sprint DTOs. Ignore nested user_stories and point aggregates in the upstream payload.
- API operation: GET milestones?project={projectId}&page={page}, with closed=true/false only when explicitly supplied.
- Source evidence: the Sprints, Pagination rows in [pinned sources](sources.md).
  Record revision/version and any verified deviations before implementation.

Illustrative MCP arguments (synthetic IDs):

```json
{
  "projectId": 12,
  "closed": false,
  "page": 1
}
```

## Files and integration points

- `Api/SprintApi.cs`
- `Tools/SprintTools.cs`
- `Models/SprintDto.cs`
- `Hosting/ServiceCollectionExtensions.cs`
- `tests/TaigaMCP.Tests/SprintListTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify milestone filters and dates

- [ ] Verify the milestone viewset's closed filter and default ordering; do not call the filter is_closed or use work-item status IDs.
- [ ] Add fixtures for open/closed sprints, ISO date strings, null optional fields, and extra nested stories/point summaries.
- [ ] Define omission versus explicit false for nullable closed and separate pagination count from project-wide open/closed summary headers.
- [ ] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [ ] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify list_sprints contracts`.

## Step 2: Implement lightweight sprint retrieval

- [ ] Add SprintApi over TaigaTransport with encoded fixed query keys and input validation.
- [ ] Map only agreed summary fields; preserve date-only values without timezone conversion and source ordering.
- [ ] Use standard page metadata, register DI, and avoid extra stats/detail requests or client-side filtering after pagination.
- [ ] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [ ] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_sprints API behavior`.

## Step 3: Expose sprint discovery

- [ ] Add SprintTools/list_sprints with nullable closed binding and descriptions explaining that Taiga calls sprints milestones.
- [ ] Document selecting the returned id as milestoneId for existing story creation/update or standalone task creation.
- [ ] Add MCP tests that distinguish omitted closed, explicit null, false, and true.
- [ ] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [ ] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_sprints MCP tool`.

## Step 4: Verify discover-and-schedule workflow

- [ ] List an open sprint and use its returned id in update_user_story with the story's fetched version.
- [ ] Cover empty/later pages, unknown pagination headers, summary-header counts differing from current filter totals, and nested payload omission.
- [ ] Test invalid IDs/pages, denied access, malformed identity/dates as appropriate to the mapped contract, and cancellation; no live sprint changes.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_sprints workflows`.

## Acceptance scenarios

- [ ] The tool can list all/open/closed sprints with distinct query semantics.
- [ ] Returned IDs are directly usable as milestoneId.
- [ ] Dates and pagination remain accurate, without nested expansion or fabricated totals.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] Agents can discover existing sprint IDs and schedule work using the already-implemented story/task tools.
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
| 1 | Not started | — | Specify list_sprints contracts / pending |
| 2 | Not started | — | Implement list_sprints API behavior / pending |
| 3 | Not started | — | Expose list_sprints MCP tool / pending |
| 4 | Not started | — | Verify list_sprints workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
