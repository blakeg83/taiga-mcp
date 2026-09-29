# Goal 02: list_project_members

Status: complete; all four ordered steps and the documented acceptance scenarios are verified.

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

- [x] Inspect the pinned ordinary/admin membership serializers; map id to membership_id and user to user_id explicitly.
- [x] Add fixtures for active/inactive users, missing user for an invitation, null role, and admin-only extra email fields.
- [x] Define no local name filter or automatic all-page read; preserve source page counts even when records are not assignable.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify list_project_members contracts`.

### Step 1 execution record

- Starting commit: `b69243b7f87980f0d3a180b908bb70a95ceb6550` (`doc cleanup`); branch: `codex/list-project-members`.
- Source evidence: pinned `taiga-back` revision `4d11baef9027f5598f6341d6eb4261de2840688e`. `MembershipViewSet` selects the ordinary serializer for normal project-member reads and the admin serializer for project-admin list reads. `MembershipSerializer` maps `id`, `user_id`, `project_id`, `role_id`, `is_admin`, `role_name`, `full_name`, `is_user_active`, and `is_owner`; `MembershipAdminSerializer` adds `email` and `user_email`. These fields were verified in [the pinned API source](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/api.py#L886-L914) and [serializers](https://raw.githubusercontent.com/taigaio/taiga-back/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/serializers.py#L148-L223). This is source evidence, not a deployed-version claim.
- Contract decisions: the public DTO will expose `membership_id` and `user_id` separately, use `project` for the project ID, and expose only the allowlisted role/name/activity/admin/owner fields. Missing `user_id` records remain in `items` and are not assignable; inactive users remain visible with `is_user_active=false`. Null optional role/name/activity/admin/owner values are omitted by the normal tool serializer. The request has only `projectId` and `page`; it sends one encoded page request, performs no name filter or per-member user lookup, and preserves header-derived `total`, `next_page`, and `has_more` values even when a page contains pending records.
- Fixtures: `ProjectMemberFixtures.MixedPage` covers active and inactive users, a pending record with no user, a null role, a localized name, and admin-only email/invitation fields. Email, user-email, and invitation text are deliberately not part of the planned public DTO.
- Baseline validation: `dotnet test -c Debug` passed on 2026-09-28 with 343 tests passing and 0 failures before feature changes. The new fixture contract test is included in this checkpoint; implementation-focused checks remain for Steps 2–4.
- Planned MCP example: `{"projectId":123,"page":1}` returns a page envelope whose assignable records use `user_id` as the later `assigned_to` value; `membership_id` is never sent as an assignee.

## Step 2: Implement project member retrieval

- [x] Add ProjectApi.ListProjectMembersAsync using positive project/page validation and encoded fixed query keys.
- [x] Use ReadWithHeadersAsync/TaigaPagination and map allowlisted DTO fields; do not fetch each user's profile.
- [x] Do not filter pending records out or equate membership existence with permission to assign a future item.
- [x] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [x] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_project_members API behavior`.

### Step 2 execution record

- Previous checkpoint: `fa4c786` (`Specify list_project_members contracts`).
- Implementation: `ProjectApi.ListProjectMembersAsync` validates positive `projectId` and `page`, sends exactly one `GET memberships?project={projectId}&page={page}`, reads pagination headers through `TaigaPagination`, and maps only the allowlisted membership fields into `ProjectMemberDto`. Required `id` and `project` values must be positive; optional `user`, `role`, strings, and booleans preserve null/missing values. The API never follows a continuation or makes per-member profile requests.
- Source deviation: none identified against the pinned ordinary/admin serializers. Admin-only `email`, `user_email`, and invitation text are intentionally discarded at the DTO boundary. The public MCP function remains planned until Step 3.
- Validation: focused `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug --no-restore --filter FullyQualifiedName~ProjectMemberTests` passed 6 tests. The focused suite covers query/page headers, active/inactive/pending/null-role mapping, allowlist serialization, invalid input before HTTP, malformed required identity data, and sanitized permission errors. Debug implementation build/test was run through the focused test command; full Debug build/test and cancellation coverage remain in later steps.

## Step 3: Expose the members tool

- [x] Add list_project_members to ProjectTools with explicit descriptions of membership_id versus user_id.
- [x] Return the page envelope and document pagination and how to choose a returned user_id for assigned_to.
- [x] Add MCP schema/invocation tests and keep list_projects/resolve_project signatures unchanged.
- [x] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [x] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_project_members MCP tool`.

### Step 3 execution record

- Previous checkpoint: `1c55973` (`Implement list_project_members API behavior`).
- Public surface: `ProjectTools.ListProjectMembers` exposes `list_project_members(projectId, page=1)` with a required positive `projectId`, optional positive `page`, a standard page envelope, and no public cancellation argument. Its description explicitly distinguishes `membership_id` from the assignable `user_id`, retains pending/inactive records, and excludes email/invitation text.
- Documentation: `README.md`, `docs/taiga_tools_reference.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, `docs/development.md`, and this batch index now describe the delivered 25-tool surface, response shape, pagination, assignment workflow, and deferred boundaries.
- Validation: real `ProductionServer_ListsAllTools_InvokesReadTool_AndReportsUpstreamFailure` passed. `tools/list` found `list_project_members` with properties exactly `projectId,page`, required exactly `projectId`, and no `cancellationToken`; `tools/call` with the default page returned mapped active/inactive/pending records, pagination metadata, and no admin email fields. `projectId=0` returned a safe MCP error without an HTTP request. Existing `list_projects` behavior and schema assertions remained unchanged.

## Step 4: Verify member-driven assignment

- [x] Read a synthetic member, then use its user_id in an existing assignment; assert the membership ID is never sent as the assignee.
- [x] Test absent user_id, inactive user, duplicate display names, localized names, empty/later pages, and missing headers.
- [x] Cover invalid inputs before HTTP, permission denial, malformed required IDs, cancellation, and omission of admin email/invitation text.
- [x] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [x] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_project_members workflows`.

### Step 4 execution record

- Previous checkpoint: `6992dad` (`Expose list_project_members MCP tool`).
- Workflow evidence: the real STDIO integration call read membership `membership_id=501` with `user_id=42`, passed `42` to `create_user_story(assigned_to=42)`, and asserted the outgoing request contained `assigned_to:42` rather than `assigned_to:501`. No membership detail or user-profile request was made beyond the one membership page.
- Edge/error evidence: focused ProjectMemberTests now pass 8 tests covering active/inactive/pending rows, duplicate display names, localized names, null role, absent `user_id`, empty later pages, missing headers, pagination, invalid IDs before HTTP, malformed required IDs, cancellation before HTTP, sanitized permission errors, and omission of email/user-email/invitation fields. The real MCP integration also verifies safe public permission errors and invalid `projectId` handling. Existing authentication/transport tests cover the shared one-401 replay rule, request disposal, cancellation, null omission, and safe errors; the membership read adds no write or version retry behavior.
- Final validation: `dotnet restore` passed; `dotnet build -c Debug` passed with 0 warnings and 0 errors; the first full `dotnet test -c Debug` attempt had one transient cleanup `UnauthorizedAccessException` in the pre-existing temporary-copy contamination test after 350 passing tests, and the immediate retry passed all 351 tests; `dotnet build -c Release --no-restore` passed with 0 warnings and 0 errors; `dotnet test -c Release --no-build --no-restore` passed all 351 tests; `git diff --check` passed. The validated assemblies were `bin/Debug/net8.0/TaigaMCP.dll` and `bin/Release/net8.0/TaigaMCP.dll`; no generated output was staged.
- Documentation reconciliation: the public reference, README, quickstart, command inventory, development guide, second-batch index, and this goal now name only the delivered `list_project_members` scope. The endpoint/source evidence remains pinned to `taiga-back` revision `4d11baef9027f5598f6341d6eb4261de2840688e`; no live deployment version or live Taiga data was used.

## Acceptance scenarios

- [x] Membership and user IDs have distinct unambiguous JSON names.
- [x] Pending/inactive records cannot silently masquerade as active assignees.
- [x] Pagination represents the requested membership stream and makes no per-member detail requests.
- [x] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [x] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [x] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [x] Agents can select project user IDs for assignment while understanding pending/inactive membership records.
- [x] All four ordered steps and acceptance scenarios have passing recorded validation.
- [x] Schema inspection and real MCP calls agree with the documented interface.
- [x] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [x] Current documentation names only delivered functionality and preserves deferred scope.
- [x] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [x] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `b69243b7f87980f0d3a180b908bb70a95ceb6550`. Source/deployment evidence:
pinned source only; no live deployment version was inspected or claimed.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Pinned serializer/API evidence recorded; mixed membership fixture and contract test added; `dotnet test -c Debug` baseline passed 343 tests before changes. | Specify list_project_members contracts / `fa4c786` |
| 2 | Complete | `ProjectApi`/`ProjectMemberDto` implemented; focused ProjectMemberTests passed 6 tests with request, mapping, pagination, validation, malformed-data, and safe-error coverage. Public tool remained planned pending Step 3. | Implement list_project_members API behavior / `1c55973` |
| 3 | Complete | Public tool exposed; real STDIO tools/list and tools/call integration passed with schema/default/error/allowlist checks; full Debug test suite passed 349 tests; public docs and 25-tool counts reconciled. | Expose list_project_members MCP tool / `6992dad` |
| 4 | Complete | Member-driven assignment, edge/error flows, complete Debug/Release validation, and diff hygiene passed; see the Step 4 execution record above. | Verify list_project_members workflows / pending (this checkpoint) |

All required steps are complete. The only observed validation retry was the
transient pre-existing test cleanup failure recorded above; the immediate Debug
retry passed. No blockers remain, and the final checkpoint commit hash is reported
in the handoff rather than embedded by rewriting this commit.
