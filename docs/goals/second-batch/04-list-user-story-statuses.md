# Goal 04: list_user_story_statuses

Status: complete.

## Objective

Expose the project's complete selectable story workflow options, including closed/archived columns.

## Scope and prerequisites

One status page with id/project/name/slug/order/color/is_closed/is_archived/wip_limit when supplied. Defer workflow changes, automatic name matching, and status caching redesign.

Prerequisites: the implemented first-batch baseline; no new function dependency.
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `list_user_story_statuses(projectId, page=1)`.
- Result: Standard page envelope of status DTOs; closed/archive booleans and zero WIP values retain their actual values.
- API operation: GET userstory-statuses?project={projectId}&page={page}.
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

- `Api/UserStoryApi.cs`
- `Tools/UserStoryTools.cs`
- `Models/UserStoryStatusDto.cs`
- `tests/TaigaMCP.Tests/UserStoryStatusTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify status metadata

- [x] Verify the pinned story status serializer and project filter; include closed/archived choices with no automatic exclusions.
- [x] Add localized/custom-name fixtures and independent closed/archive flags, null WIP, and zero order/WIP values.
- [x] Define a page-envelope public contract despite older issue metadata tools returning arrays; preserve those old shapes.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify list_user_story_statuses contracts`.

## Step 2: Implement project status reads

- [x] Add a one-page API method using transport/header parsing and positive-ID/page validation.
- [x] Map status fields accurately and preserve source order; do not hardcode status names or infer flags from them.
- [x] Do not reuse a partial page as the full internal status map or modify existing list_user_stories filtering.
- [x] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [x] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_user_story_statuses API behavior`.

## Step 3: Expose status discovery

- [x] Add the public method to UserStoryTools with descriptions of resource-specific IDs, flags, and page behavior.
- [x] Document selecting a returned status id for create/update_user_story and checking later pages when necessary.
- [x] Add actual MCP invocation tests and update discovery documentation.
- [x] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [x] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_user_story_statuses MCP tool`.

## Step 4: Verify discovery-to-transition flow

- [x] Fetch a custom-named closed status and pass its ID to update_user_story using get_user_story's version.
- [x] Test independent flags, WIP zero/null, missing optional color, empty/later pages, unknown metadata, and wrong-project data handling.
- [x] Cover denied access, malformed required IDs, cancellation, and unchanged existing story filter semantics.
- [x] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [x] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_user_story_statuses workflows`.

## Acceptance scenarios

- [x] Closed and archived choices are visible and semantics do not depend on English names.
- [x] Returned IDs work with existing story update/create parameters.
- [x] New metadata discovery leaves legacy issue-status arrays and story list behavior unchanged.
- [x] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [x] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [x] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [x] An agent can discover valid story statuses before creating or transitioning a story.
- [x] All four ordered steps and acceptance scenarios have passing recorded validation.
- [x] Schema inspection and real MCP calls agree with the documented interface.
- [x] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [x] Current documentation names only delivered functionality and preserves deferred scope.
- [x] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [x] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `abefa995f7a05bb918d741f0a222c20592d53077` (`master`). Source
evidence is pinned taiga-back revision `4d11baef9027f5598f6341d6eb4261de2840688e`;
no live deployment or Taiga data was queried. The verified serializer exposes
`id`, `name`, `slug`, `order`, `is_closed`, `is_archived`, `color`, `wip_limit`,
and `project`; the project viewset allowlists `project` and applies project-view
permissions. The implementation therefore preserves localized/custom names,
independent boolean flags, zero `order`/`wip_limit`, nullable optional metadata,
and server order without name-based filtering.

The public contract is a page envelope:

```json
{
  "items":[{"id":10,"project":123,"name":"Terminado","slug":"terminado","order":0,"color":"#cc0000","is_closed":true,"is_archived":false,"wip_limit":0}],
  "page":1,
  "total":null,
  "next_page":null,
  "has_more":null
}
```

The endpoint sends exactly one request per call to
`userstory-statuses?project={projectId}&page={page}`. It includes all returned
statuses, including closed and archived choices. Null DTO properties are omitted
by the public serializer; page metadata remains explicit JSON null when unknown.
The legacy issue-status array and story-list behavior remain unchanged.

Step 2 implementation uses `UserStoryApi` with the existing `TaigaTransport`.
The API exposes a bare-list convenience method for domain callers and an
internal page result for the eventual tool. Each call validates positive
`projectId`/`page`, sends the configured project and page values, parses one JSON
array, preserves source order, and uses `TaigaPagination` for count/continuation
headers. A status must contain a positive numeric `id`; all other contract
fields are presence-aware and type-checked, with `project` requiring a positive
value when present. No status cache or story-list filter was changed.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline `dotnet restore`, `dotnet build -c Debug`, and `dotnet test -c Debug` passed (381 tests, 0 warnings/errors). Added `UserStoryStatusDto` contract fixtures/tests for localized names, independent flags, null color/WIP, and zero order/WIP. Verified pinned source revision and project filter above. | Specify list_user_story_statuses contracts / `471e6f1` |
| 2 | Complete | Focused `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug --filter FullyQualifiedName~UserStoryStatusTests` passed (6 tests); Debug build/test passed (387 tests, 0 warnings/errors). API tests cover exact project/page query, field mapping/order, pagination, validation, malformed required IDs, and unknown metadata. | Implement list_user_story_statuses API behavior / `bafbfe2` |
| 3 | Complete | Focused `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug --filter FullyQualifiedName~McpIntegrationTests` passed (11 tests); the complete Debug test rerun passed (387 tests, 0 warnings/errors). A transient first-run cleanup lock in the existing contamination test was cleared by rerunning its isolated test. Real STDIO `tools/list` and `tools/call` checks cover required/default/null argument binding, omitted-page defaults, page 2 requests, returned closed/archived metadata, and safe invalid-ID errors. Updated the reference, README, quickstart, inventory, and batch index to 27 tools. | Expose list_user_story_statuses MCP tool / `8bb12ba` |
| 4 | Complete | Focused status/discovery/story-list coverage passed (29 tests). The fake STDIO update flow fetched `Terminado`, used its returned status ID with a fresh `get_user_story` version, and verified the forwarded PATCH. API/tool tests covered independent flags, zero/null WIP, omitted color, empty/later pages, unknown headers, wrong-project data, forbidden responses, malformed IDs, cancellation, and unchanged story-list filters. Final commands all passed: `dotnet restore`; `dotnet build -c Debug` (0 warnings/errors); `dotnet test -c Debug` (390 passed); `dotnet build -c Release --no-restore` (0 warnings/errors); `dotnet test -c Release --no-build --no-restore` (390 passed); `git diff --check`. Outputs: `bin/Debug/net8.0`, `tests/TaigaMCP.Tests/bin/Debug/net8.0`, `bin/Release/net8.0`, and `tests/TaigaMCP.Tests/bin/Release/net8.0`. | Verify list_user_story_statuses workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
