# Goal 08: update_epic

Status: complete; all four steps completed.

## Objective

Complete routine epic management: edit content, change ownership, update appearance/tags, and close or reopen through a chosen status.

## Scope and prerequisites

Update subject, description, status, assigned_to, color, tags, and optional comment. clearFields accepts only assigned_to. Defer requirement flags, blocking/dates, ordering, project moves, custom fields, and changes to linked stories.

Prerequisites: [goal 02](02-list-project-members.md), [goal 06](06-list-epic-statuses.md).
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `update_epic(epicId, version, subject?, description?, status?, assigned_to?, color?, tags?, comment?, clearFields?)`.
- Result: The existing EpicDetailDto shape populated from the authoritative PATCH response, including returned version.
- API operation: PATCH epics/{epicId}; send only version and requested changes.
- Source evidence: the Epics and relationships, Versions rows in [pinned sources](sources.md).
  Record revision/version and any verified deviations before implementation.

Illustrative MCP arguments (synthetic IDs):

```json
{
  "epicId": 301,
  "version": 4,
  "status": 7,
  "comment": "Delivery complete."
}
```

## Files and integration points

- `Api/EpicApi.cs`
- `Tools/EpicTools.cs`
- `Models/EpicUpdateDto.cs`
- `tests/TaigaMCP.Tests/EpicUpdateTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify epic presence-aware edits

- [x] Compare existing issue/story/task update payload construction and reuse its omission/clearing conventions.
- [x] Add fixtures for status-only edits, unassignment, empty description/tags, color changes, and comment-only calls.
- [x] Require positive IDs, nonnegative version, a real change/nonblank comment, nonblank supplied subject, and no set/clear collision; let Taiga validate color formats.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify update_epic contracts`.

## Step 2: Implement versioned epic PATCH

- [x] Construct a minimal presence-aware payload with exact supplied version and assigned_to:null only when explicitly cleared.
- [x] Reuse MapEpicDetail; report post-write parse/mapping failure as potentially applied and preserve bounded safe version/status errors.
- [x] Do not refresh entity versions or touch project settings, linked stories, or relationship order; retain only existing received-401 auth replay.
- [x] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [x] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement update_epic API behavior`.

## Step 3: Expose epic editing

- [x] Add update_epic with required epicId/version and descriptions matching current updates; cancellation remains injected.
- [x] Document get_epic -> list_epic_statuses -> update_epic and member-driven assignment/unassignment.
- [x] Keep create_epic and comment-only AddCommentAsync behavior compatible and add actual MCP binding tests.
- [x] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [x] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose update_epic MCP tool`.

## Step 4: Verify close/reopen and edits

- [x] Fetch a version and status IDs through existing/new readers; close and reopen a fake epic using its returned versions.
- [x] Test omission versus clear, comment-only update, empty tags/description, unknown clear names, status validation, and wrong-project IDs rejected by Taiga.
- [x] Cover 400 version rejection, 409, accepted nonoverlapping stale edits, 403/404, cancellation, and ambiguous transport failure with no automatic edit retry.
- [x] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [x] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify update_epic workflows`.

## Acceptance scenarios

- [x] An epic can be edited, assigned/unassigned, and transitioned using discovered status IDs.
- [x] Only selected properties and the exact supplied version are sent.
- [x] Returned identity/version reflect the server, and linked stories remain untouched.
- [x] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [x] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [x] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [x] Agents can maintain and close/reopen epics through the same reliable versioned workflow as stories and tasks.
- [x] All four ordered steps and acceptance scenarios have passing recorded validation.
- [x] Schema inspection and real MCP calls agree with the documented interface.
- [x] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [x] Current documentation names only delivered functionality and preserves deferred scope.
- [x] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [x] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `4b4d896`. Source evidence is the pinned taiga-back revision
`4d11baef9027f5598f6341d6eb4261de2840688e`, checked 2026-09-29; no live
deployment version was read or claimed.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Starting commit `4b4d896`; baseline `dotnet test -c Debug`: 422 passed. Focused contract fixtures cover status-only, explicit assignee clearing, empty description/tags, color, and comment-only payloads. The pinned Taiga backend revision `4d11baef9027f5598f6341d6eb4261de2840688e` confirms the epic writable fields and OCC version requirement; no source deviation was found. | Specify update_epic contracts / `1d9ee50` |
| 2 | Complete | Previous step `1d9ee50`. `UpdateEpicAsync` sends only selected fields plus the exact caller version, supports explicit assignee clearing, maps the authoritative PATCH response, preserves safe 400/409/403/404 errors, and never performs a read/retry after an ambiguous write. Focused `FullyQualifiedName~EpicUpdate` tests: 26 passed; `dotnet build -c Debug --no-restore`: 0 warnings/errors. | Implement update_epic API behavior / `e7ea1d6` |
| 3 | Complete | Previous step `e7ea1d6`. The `update_epic` tool is discoverable with required `epicId`/`version`, no public cancellation argument, and descriptions for every optional field. Real MCP integration covered omitted optionals with comment-only editing, explicit null optionals, empty tags, missing required version, authoritative detail response, safe 403 error handling, and preserved existing create/comment flows. The updated reference, README, quickstart, inventory, batch index, and development count document 31 tools and the delivered scope. | Expose update_epic MCP tool / `edad560` |
| 4 | Complete | Previous step `edad560`. Focused epic workflow tests: 29 passed, including status discovery plus close/reopen with returned versions, successful subject/assignment/unassignment, explicit clearing/omission, comment-only edits, empty fields, malformed transport and mapped success, safe HTTP statuses, stale-version acceptance, cancellation, and ambiguous write handling. Full required validation passed: `dotnet restore`; `dotnet build -c Debug` (0 warnings/errors); `dotnet test -c Debug` (452 passed); `dotnet build -c Release --no-restore` (0 warnings/errors); `dotnet test -c Release --no-build --no-restore` (452 passed); `git diff --check` clean apart from the expected CRLF conversion warning. Outputs were the standard `bin/Debug/net8.0` and `bin/Release/net8.0` directories; no generated files were staged. | Verify update_epic workflows / `bf3f98d` + follow-up |

### Step 1 contract decisions

Existing issue, story, and task updates use a dictionary payload so omitted
nullable arguments are distinguishable from explicit empty values and explicit
clears. `EpicUpdateDto` follows that convention: `description=""` and
`tags=[]` remain present, `assigned_to:null` is emitted only for the supported
`clearFields=["assigned_to"]` case, and `version` is always present exactly as
supplied. Status-only, color-only, and comment-only edits contain no unrelated
fields. Subject, ID, version, change/comment, and clear collision validation
will be enforced by the domain API in Step 2; color format validation remains
Taiga-owned.

Pinned source evidence checked 2026-09-29: the epic serializer exposes the
detail fields and the epic validator accepts model-backed updates; the model
defines `subject`, `description`, `status`, `assigned_to`, `color`, and tags,
while `OCCResourceMixin` requires a nonnegative caller version and returns the
authoritative incremented version. `epics_order`, requirement flags, blocking,
dates, custom fields, and relationships remain out of scope.

### Follow-up review hardening

The completion review found no production defect. Additional coverage now
exercises member-driven `user_id` assignment, successful subject/content edits,
explicit assignee clearing with omitted returned `assigned_to`, and a valid JSON
response that fails detail mapping after PATCH. The quickstart, reference,
inventory, and development guide now consistently describe assignment through
`list_project_members` and the delivered 31-tool state.

### Step 2 implementation evidence

`EpicApi.UpdateEpicAsync` now issues one `PATCH epics/{epicId}` with a minimal
presence-aware JSON body. It validates positive IDs, nonnegative versions,
nonblank supplied subjects, positive optional IDs, supported clear names, and
set/clear collisions before HTTP. Empty descriptions and tag arrays are valid
explicit values; blank comments do not satisfy a comment-only update. The
returned document is mapped through the existing `MapEpicDetail`, so the
server's identity and version are authoritative. Transport/status failures
remain bounded safe `TaigaRequestException` values; successful-response mapping
failures explicitly warn that the write may already have applied. No automatic
version refresh, read-modify-write, relationship change, or project mutation is
performed. The public MCP tool and public documentation remain planned until
Step 3.

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
