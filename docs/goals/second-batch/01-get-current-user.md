# Goal 01: get_current_user

Status: in progress; contract evidence and fixtures are recorded, API/tool work remains.

## Objective

Let an agent identify the authenticated account and use its numeric user ID in existing assignment and member filters.

## Scope and prerequisites

Identity read only. Return id plus optional username, full_name, and is_active. Defer profile editing, user search, email, roles, notification settings, and account administration.

Prerequisites: the implemented first-batch baseline; no new function dependency.
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `get_current_user()`.
- Result: One identity object: { id, username?, full_name?, is_active? }. No user-supplied credentials or user ID.
- API operation: GET users/me.
- Source evidence: the Current user rows in [pinned sources](sources.md).
  Record revision/version and any verified deviations before implementation.

Illustrative MCP arguments (synthetic IDs):

```json
{}
```

## Files and integration points

- `Api/UserApi.cs`
- `Tools/UserTools.cs`
- `Models/UserIdentityDto.cs`
- `Hosting/ServiceCollectionExtensions.cs`
- `tests/TaigaMCP.Tests/UserIdentityTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify identity mapping

- [x] Read current AuthClient/transport tests and the pinned users/me serializer; record required/optional fields.
- [x] Add synthetic minimal/populated/malformed identity fixtures, including an admin response with fields that must not be forwarded.
- [x] Define id as a required positive integer; do not expose tokens, email, or arbitrary upstream properties.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify get_current_user contracts`.

### Step 1 evidence

- Starting commit: `257149f6f5758af3e2d44f11c2ebfc446f2c99e4` (`master`); the worktree already contained unrelated edits that remain uncommitted by this goal.
- Baseline validation: `dotnet restore TaigaMCP.sln` passed; `dotnet test TaigaMCP.sln -c Debug -p:OutputPath=C:\Temp\TaigaMCP-goal01-baseline-debug\ -p:UseAppHost=false` passed 332 tests with 0 failures.
- Pinned source revision: `4d11baef9027f5598f6341d6eb4261de2840688e`. `UsersViewSet.me` returns `UserAdminSerializer(request.user)`, whose base serializer exposes `id`, `username`, `full_name`, and `is_active`; the admin serializer additionally exposes private/profile fields such as `email`, `uuid`, and account metadata. This is source evidence, not a deployed-version claim.
- Transport review: `AuthClient` retains bearer state in memory, attaches it per request, and permits replay only after a received 401; `TaigaTransport` owns responses and returned JSON documents are caller-owned. The new read will reuse those paths and pass cancellation through.
- Mapping decision: require a JSON object with a positive integer `id`; preserve optional string `username` and `full_name`, and optional boolean `is_active` including `false`. Missing or malformed required identity data is a safe failure. Unknown/private properties, including tokens, email, roles, and UUIDs, are omitted.
- Fixtures: `UserIdentityFixtures` covers minimal, populated, private-field, missing-id, nonpositive-id, wrong-type, and malformed responses. No future-behavior tests were added in this contract-only step.

## Step 2: Implement the identity API

- [ ] Add a concrete UserApi using TaigaTransport; own/dispose the request and returned document and pass cancellation.
- [ ] Map the allowlisted identity fields, preserving false is_active and absent optional values.
- [ ] Register UserApi through DI without modifying AuthClient login payloads, singleton state, or token claims.
- [ ] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [ ] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement get_current_user API behavior`.

## Step 3: Expose identity through MCP

- [ ] Add UserTools with the explicit tool name and descriptions; the public schema has no arguments and no cancellationToken.
- [ ] Use ToolErrors and ToolResponseJson; document using the returned id as assigned_to or assignedTo and its string form as list_projects.member.
- [ ] Update discovery expectations by one tool and add real MCP call assertions.
- [ ] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [ ] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose get_current_user MCP tool`.

## Step 4: Verify identity-to-assignment workflow

- [ ] Read users/me and pass the returned ID to an existing issue/story/task assignment in fake HTTP; never hardcode a production user.
- [ ] Cover missing/nonpositive id, optional fields, 401 bounded auth replay, 403, invalid JSON, and cancellation.
- [ ] Verify extra upstream private fields never appear in the result or logs and all 23 baseline tools retain their contracts.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify get_current_user workflows`.

## Acceptance scenarios

- [ ] No public arguments are required and the result contains a usable numeric user ID.
- [ ] Identity can drive an existing assignment/filter without parsing login responses.
- [ ] Unknown/private upstream properties are omitted; malformed required identity fails safely.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] An agent can resolve 'me' to the authenticated user ID through a tested read-only MCP tool.
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
| 1 | Complete | Baseline restore/test passed (332 tests); pinned users/me serializer reviewed; identity mapping and synthetic fixtures recorded above. | Specify get_current_user contracts / pending |
| 2 | Not started | — | Implement get_current_user API behavior / pending |
| 3 | Not started | — | Expose get_current_user MCP tool / pending |
| 4 | Not started | — | Verify get_current_user workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
