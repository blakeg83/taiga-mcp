# Goal 07: list_sprints

Status: complete on `codex/list-sprints`.

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

- [x] Verify the milestone viewset's closed filter and default ordering; do not call the filter is_closed or use work-item status IDs.
- [x] Add fixtures for open/closed sprints, ISO date strings, null optional fields, and extra nested stories/point summaries.
- [x] Define omission versus explicit false for nullable closed and separate pagination count from project-wide open/closed summary headers.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify list_sprints contracts`.

## Step 2: Implement lightweight sprint retrieval

- [x] Add SprintApi over TaigaTransport with encoded fixed query keys and input validation.
- [x] Map only agreed summary fields; preserve date-only values without timezone conversion and source ordering.
- [x] Use standard page metadata, register DI, and avoid extra stats/detail requests or client-side filtering after pagination.
- [x] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [x] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_sprints API behavior`.

## Step 3: Expose sprint discovery

- [x] Add SprintTools/list_sprints with nullable closed binding and descriptions explaining that Taiga calls sprints milestones.
- [x] Document selecting the returned id as milestoneId for existing story creation/update or standalone task creation.
- [x] Add MCP tests that distinguish omitted closed, explicit null, false, and true.
- [x] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [x] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_sprints MCP tool`.

## Step 4: Verify discover-and-schedule workflow

- [x] List an open sprint and use its returned id in update_user_story with the story's fetched version.
- [x] Cover empty/later pages, unknown pagination headers, summary-header counts differing from current filter totals, and nested payload omission.
- [x] Test invalid IDs/pages, denied access, malformed identity/dates as appropriate to the mapped contract, and cancellation; no live sprint changes.
- [x] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [x] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_sprints workflows`.

## Acceptance scenarios

- [x] The tool can list all/open/closed sprints with distinct query semantics.
- [x] Returned IDs are directly usable as milestoneId.
- [x] Dates and pagination remain accurate, without nested expansion or fabricated totals.
- [x] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [x] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [x] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [x] Agents can discover existing sprint IDs and schedule work using the already-implemented story/task tools.
- [x] All four ordered steps and acceptance scenarios have passing recorded validation.
- [x] Schema inspection and real MCP calls agree with the documented interface.
- [x] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [x] Current documentation names only delivered functionality and preserves deferred scope.
- [x] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [x] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `882e1ec7136c3e24a920dd288b7ed41917953f6a`. Source evidence is
pinned taiga-back revision `4d11baef9027f5598f6341d6eb4261de2840688e`; official
REST documentation was checked on 2026-09-29. This is source evidence only and
does not claim a live deployment version.

Step 1 contract decisions:

- The request is `GET milestones?project={projectId}&page={page}`, with
  `closed=true` or `closed=false` appended only when the nullable argument is
  explicitly supplied. Project and page are positively validated and all fixed
  query values are URI-encoded.
- The pinned milestone viewset accepts `project`, `project__slug`, and `closed`,
  orders by descending `estimated_start`, and adds
  `Taiga-Info-Total-Opened-Milestones` / `Taiga-Info-Total-Closed-Milestones`.
  Those summary headers are deliberately not page totals; pagination metadata
  comes only from the standard pagination headers.
- The lightweight DTO maps only `id`, `project`, `name`, `slug`,
  `estimated_start`, `estimated_finish`, and `closed`. Required identity/name/
  slug/date/closed values are validated; dates remain date-only ISO strings with
  no timezone conversion. Nested `user_stories`, `total_points`, and
  `closed_points`, plus nullable upstream extras such as `owner`, are ignored.
- Fixtures cover open/closed rows, ISO date strings, nullable ignored extras, and
  nested story/point data. No live Taiga data is used.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Source review and fixtures recorded above. Baseline `dotnet restore`, `dotnet build -c Debug --no-restore`, and `dotnet test -c Debug --no-restore`: passed, 408 tests. | Specify list_sprints contracts / `831aa16` |
| 2 | Complete | `SprintListTests`: 11 passed, including query omission/false/true, mapping, nested-field omission, pagination, malformed data, safe HTTP errors, pre-cancellation, and project/page validation. Debug focused build/test passed. | Implement list_sprints API behavior / `1919b9c` |
| 3 | Complete | Real `tools/list`/`tools/call` integration passed: 30 discovered tools; required/default/null/false/true binding, page envelope, invalid arguments, and sanitized 403 behavior verified. Public reference, README, quickstart, inventory, and batch index updated. | Expose list_sprints MCP tool / `3121e0a` |
| 4 | Complete | Discover-open-sprint → fetched story version → `update_user_story` with returned milestone ID passed. `SprintListTests` and MCP tests cover empty/later pages, unknown metadata, differing summary counts, nested omission, malformed identity/date data, denied access, cancellation, and validation. The workflow forwards the fetched story version rather than a fixture literal. Exact required sequence passed: `dotnet restore`; `dotnet build -c Debug`; `dotnet test -c Debug`; `dotnet build -c Release --no-restore`; `dotnet test -c Release --no-build --no-restore`; `git diff --check`. Both configurations: 422 passed, 0 failed, 0 skipped, 0 warnings/errors. The contaminated-copy test cleanup now retries generated temp-directory deletion up to 20 times for transient Windows handles. | Verify list_sprints workflows / `1ee2cb2` |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
