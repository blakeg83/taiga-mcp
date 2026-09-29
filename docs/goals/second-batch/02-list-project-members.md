# Goal 02: list_project_members

Status: planned; not implemented by this document.

## Objective

Let agents identify project members for assignment without confusing membership records with user accounts.

## Scope and prerequisites

One page of project memberships. Return membership_id, project, optional user_id/role_id/role_name/full_name/is_user_active, and is_admin/is_owner when supplied. Defer invitations, membership changes, role administration, email exposure, and directory-wide search.

Prerequisites: [goal 01](01-get-current-user.md).
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `list_project_members(projectId, page=1)`.
- Result: Standard page envelope. Membership records with no user_id may be pending invitations; retain them without inventing an assignable user.
- API operation: GET memberships?project={projectId}&page={page}.
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

- `Api/ProjectApi.cs`
- `Tools/ProjectTools.cs`
- `Models/ProjectMemberDto.cs`
- `tests/TaigaMCP.Tests/ProjectMemberTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify membership identity and pagination

- [ ] Inspect the pinned ordinary/admin membership serializers; map id to membership_id and user to user_id explicitly.
- [ ] Add fixtures for active/inactive users, missing user for an invitation, null role, and admin-only extra email fields.
- [ ] Define no local name filter or automatic all-page read; preserve source page counts even when records are not assignable.
- [ ] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [ ] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify list_project_members contracts`.

## Step 2: Implement project member retrieval

- [ ] Add ProjectApi.ListProjectMembersAsync using positive project/page validation and encoded fixed query keys.
- [ ] Use ReadWithHeadersAsync/TaigaPagination and map allowlisted DTO fields; do not fetch each user's profile.
- [ ] Do not filter pending records out or equate membership existence with permission to assign a future item.
- [ ] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [ ] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_project_members API behavior`.

## Step 3: Expose the members tool

- [ ] Add list_project_members to ProjectTools with explicit descriptions of membership_id versus user_id.
- [ ] Return the page envelope and document pagination and how to choose a returned user_id for assigned_to.
- [ ] Add MCP schema/invocation tests and keep list_projects/resolve_project signatures unchanged.
- [ ] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [ ] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_project_members MCP tool`.

## Step 4: Verify member-driven assignment

- [ ] Read a synthetic member, then use its user_id in an existing assignment; assert the membership ID is never sent as the assignee.
- [ ] Test absent user_id, inactive user, duplicate display names, localized names, empty/later pages, and missing headers.
- [ ] Cover invalid inputs before HTTP, permission denial, malformed required IDs, cancellation, and omission of admin email/invitation text.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_project_members workflows`.

## Acceptance scenarios

- [ ] Membership and user IDs have distinct unambiguous JSON names.
- [ ] Pending/inactive records cannot silently masquerade as active assignees.
- [ ] Pagination represents the requested membership stream and makes no per-member detail requests.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] Agents can select project user IDs for assignment while understanding pending/inactive membership records.
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
| 1 | Not started | — | Specify list_project_members contracts / pending |
| 2 | Not started | — | Implement list_project_members API behavior / pending |
| 3 | Not started | — | Expose list_project_members MCP tool / pending |
| 4 | Not started | — | Verify list_project_members workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
