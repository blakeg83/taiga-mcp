# Goal 01: get_current_user

Status: complete; `get_current_user` is implemented, exposed, documented, and fully verified.

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

- [x] Add a concrete UserApi using TaigaTransport; own/dispose the request and returned document and pass cancellation.
- [x] Map the allowlisted identity fields, preserving false is_active and absent optional values.
- [x] Register UserApi through DI without modifying AuthClient login payloads, singleton state, or token claims.
- [x] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [x] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement get_current_user API behavior`.

### Step 2 evidence

- Previous checkpoint: `49cdee8` (`Specify get_current_user contracts`).
- `UserApi.GetCurrentUserAsync` sends exactly `GET users/me`, delegates authentication, status handling, JSON parsing, cancellation, and response disposal to `TaigaTransport`, and disposes its returned `JsonDocument` after mapping.
- Optional fields with the wrong JSON kind are treated as absent; `false` is preserved for `is_active`. Required `id` must be an integer greater than zero. No upstream private fields are modeled or forwarded.
- Focused validation: `dotnet build TaigaMCP.sln -c Debug --no-restore -p:OutputPath=C:\Temp\TaigaMCP-goal01-step2b-debug\ -p:UseAppHost=false` passed with 0 warnings/errors; `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug --no-build --no-restore --filter FullyQualifiedName~UserIdentityTests -p:OutputPath=C:\Temp\TaigaMCP-goal01-step2b-debug\ -p:UseAppHost=false` passed all 9 identity tests. An earlier full custom-output run reached 341 tests with 338 passing; the two identity failures were fixed, while the existing `ProductionServer_RejectsStartupStdoutContaminationInTemporaryCopy` test hit a temporary-copy cleanup lock. The focused rerun was clean.

## Step 3: Expose identity through MCP

- [x] Add UserTools with the explicit tool name and descriptions; the public schema has no arguments and no cancellationToken.
- [x] Use ToolErrors and ToolResponseJson; document using the returned id as assigned_to or assignedTo and its string form as list_projects.member.
- [x] Update discovery expectations by one tool and add real MCP call assertions.
- [x] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [x] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose get_current_user MCP tool`.

### Step 3 evidence

- Previous checkpoint: `8953859` (`Implement get_current_user API behavior`).
- Added `UserTools.GetCurrentUser`; the MCP name is `get_current_user`, the callable has no user arguments, and the injected cancellation token is not part of the generated schema.
- Public success JSON is an identity object such as `{"id":42,"username":"integration-user","full_name":"Integration User","is_active":true}`. Null optional fields are omitted by `ToolResponseJson`; upstream email, roles, tokens, and other private fields are never represented.
- Real stdio integration validation uses `FakeTaigaHttpServer` for `GET /api/v1/users/me`, checks discovery and the call result, and confirms private-field suppression. The configurable fake route also supports public-boundary assertions for omitted optional fields, preserved `is_active:false`, safe 403/invalid-JSON/malformed-identity errors, and private/error sentinel suppression from results and stderr. `dotnet build TaigaMCP.sln -c Debug --no-restore -p:OutputPath=C:\Temp\TaigaMCP-goal01-step3b-debug\ -p:UseAppHost=false` passed with 0 warnings/errors; the matching filtered MCP integration test passed 1 test.

## Step 4: Verify identity-to-assignment workflow

- [x] Read users/me and pass the returned ID to an existing issue/story/task assignment in fake HTTP; never hardcode a production user.
- [x] Cover missing/nonpositive id, optional fields, 401 bounded auth replay, 403, invalid JSON, and cancellation.
- [x] Verify extra upstream private fields never appear in the result or logs and all 23 first-batch baseline tools retain their contracts.
- [x] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [x] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify get_current_user workflows`.

### Step 4 evidence

- Previous checkpoint: `da569ff` (`Expose get_current_user MCP tool`).
- The real MCP workflow reads `get_current_user`, stores its returned `id`, and uses that value in an existing assigned story create request. The fake server returns synthetic ID 42 only; no production identity or live Taiga data is used.
- `UserIdentityTests` covers minimal/populated optional fields, private-field omission, missing/nonpositive/wrong-type/malformed IDs, safe 403 handling, pre-cancellation, response disposal, and one received-401 replay with refreshed bearer authorization. The MCP integration tests confirm the 24-tool discovery contract, no public cancellation token, the users/me call, minimal optional omission, `is_active:false` preservation, safe 403/invalid-JSON/malformed-identity errors, private/error sentinel suppression from results and stderr, and the assignment workflow.
- Required validation: `dotnet restore` passed. `dotnet build TaigaMCP.sln -c Debug --no-restore -p:OutputPath=C:\Temp\TaigaMCP-goal01-final-debug7\ -p:UseAppHost=false` passed with 0 warnings/errors and the matching standard `dotnet test TaigaMCP.sln -c Debug --no-build --no-restore -p:OutputPath=C:\Temp\TaigaMCP-goal01-final-debug7\ -p:UseAppHost=false` passed 342/342. `dotnet build TaigaMCP.sln -c Release --no-restore -p:OutputPath=C:\Temp\TaigaMCP-goal01-final-release6\ -p:UseAppHost=false` passed with 0 warnings/errors and the matching standard `dotnet test TaigaMCP.sln -c Release --no-build --no-restore -p:OutputPath=C:\Temp\TaigaMCP-goal01-final-release6\ -p:UseAppHost=false` passed 342/342. The follow-up public-boundary validation command filtered to `UserIdentityTests` and the three relevant MCP integration tests passed 13/13 in `C:\Temp\TaigaMCP-review-current-user-boundary\`. `git diff --check` passed after this documentation update. The Windows contamination test initially hit a temporary-copy lock in several parallel full runs, then passed independently and in the clean full-suite retries; no test was skipped. No live server, credentials, generated artifacts, or unrelated files were changed by this goal.

## Acceptance scenarios

- [x] No public arguments are required and the result contains a usable numeric user ID.
- [x] Identity can drive an existing assignment/filter without parsing login responses.
- [x] Unknown/private upstream properties are omitted; malformed required identity fails safely.
- [x] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [x] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [x] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [x] An agent can resolve 'me' to the authenticated user ID through a tested read-only MCP tool.
- [x] All four ordered steps and acceptance scenarios have passing recorded validation.
- [x] Schema inspection and real MCP calls agree with the documented interface.
- [x] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [x] Current documentation names only delivered functionality and preserves deferred scope.
- [x] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [x] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `257149f6f5758af3e2d44f11c2ebfc446f2c99e4`. Source/deployment evidence: pinned source only; do not claim a live
deployment version from upstream source alone.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline restore/test passed (332 tests); pinned users/me serializer reviewed; identity mapping and synthetic fixtures recorded above. | Specify get_current_user contracts / `49cdee8` |
| 2 | Complete | UserApi mapping, cancellation, safe errors, request path, response disposal, DI registration, focused tests, and Debug build passed; public tool remains planned. | Implement get_current_user API behavior / `8953859` |
| 3 | Complete | Public schema/call assertions and fake-HTTP users/me route added; documentation publishes the 24-tool callable contract. Exact integration command/result recorded above. | Expose get_current_user MCP tool / `da569ff` |
| 4 | Complete | Full Debug/Release restore-build-test sequence, assignment workflow, auth replay, safe-error/cancellation/private-field tests, and documentation reconciliation passed; final evidence is recorded above. | Verify get_current_user workflows / this checkpoint |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
