# Goal 08: update_epic

Status: in progress; Step 1 completed.

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
- [ ] Require positive IDs, nonnegative version, a real change/nonblank comment, nonblank supplied subject, and no set/clear collision; let Taiga validate color formats.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify update_epic contracts`.

## Step 2: Implement versioned epic PATCH

- [ ] Construct a minimal presence-aware payload with exact supplied version and assigned_to:null only when explicitly cleared.
- [ ] Reuse MapEpicDetail; report post-write parse/mapping failure as potentially applied and preserve bounded safe version/status errors.
- [ ] Do not refresh entity versions or touch project settings, linked stories, or relationship order; retain only existing received-401 auth replay.
- [ ] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [ ] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement update_epic API behavior`.

## Step 3: Expose epic editing

- [ ] Add update_epic with required epicId/version and descriptions matching current updates; cancellation remains injected.
- [ ] Document get_epic -> list_epic_statuses -> update_epic and member-driven assignment/unassignment.
- [ ] Keep create_epic and comment-only AddCommentAsync behavior compatible and add actual MCP binding tests.
- [ ] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [ ] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose update_epic MCP tool`.

## Step 4: Verify close/reopen and edits

- [ ] Fetch a version and status IDs through existing/new readers; close and reopen a fake epic using its returned versions.
- [ ] Test omission versus clear, comment-only update, empty tags/description, unknown clear names, status validation, and wrong-project IDs rejected by Taiga.
- [ ] Cover 400 version rejection, 409, accepted nonoverlapping stale edits, 403/404, cancellation, and ambiguous transport failure with no automatic edit retry.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify update_epic workflows`.

## Acceptance scenarios

- [ ] An epic can be edited, assigned/unassigned, and transitioned using discovered status IDs.
- [ ] Only selected properties and the exact supplied version are sent.
- [ ] Returned identity/version reflect the server, and linked stories remain untouched.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] Agents can maintain and close/reopen epics through the same reliable versioned workflow as stories and tasks.
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
| 1 | Complete | Starting commit `4b4d896`; baseline `dotnet test -c Debug`: 422 passed. Focused contract fixtures cover status-only, explicit assignee clearing, empty description/tags, color, and comment-only payloads. The pinned Taiga backend revision `4d11baef9027f5598f6341d6eb4261de2840688e` confirms the epic writable fields and OCC version requirement; no source deviation was found. | Specify update_epic contracts / pending |
| 2 | Not started | — | Implement update_epic API behavior / pending |
| 3 | Not started | — | Expose update_epic MCP tool / pending |
| 4 | Not started | — | Verify update_epic workflows / pending |

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

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
