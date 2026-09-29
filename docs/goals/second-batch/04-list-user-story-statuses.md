# Goal 04: list_user_story_statuses

Status: planned; not implemented by this document.

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

- [ ] Verify the pinned story status serializer and project filter; include closed/archived choices with no automatic exclusions.
- [ ] Add localized/custom-name fixtures and independent closed/archive flags, null WIP, and zero order/WIP values.
- [ ] Define a page-envelope public contract despite older issue metadata tools returning arrays; preserve those old shapes.
- [ ] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [ ] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify list_user_story_statuses contracts`.

## Step 2: Implement project status reads

- [ ] Add a one-page API method using transport/header parsing and positive-ID/page validation.
- [ ] Map status fields accurately and preserve source order; do not hardcode status names or infer flags from them.
- [ ] Do not reuse a partial page as the full internal status map or modify existing list_user_stories filtering.
- [ ] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [ ] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_user_story_statuses API behavior`.

## Step 3: Expose status discovery

- [ ] Add the public method to UserStoryTools with descriptions of resource-specific IDs, flags, and page behavior.
- [ ] Document selecting a returned status id for create/update_user_story and checking later pages when necessary.
- [ ] Add actual MCP invocation tests and update discovery documentation.
- [ ] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [ ] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_user_story_statuses MCP tool`.

## Step 4: Verify discovery-to-transition flow

- [ ] Fetch a custom-named closed status and pass its ID to update_user_story using get_user_story's version.
- [ ] Test independent flags, WIP zero/null, missing optional color, empty/later pages, unknown metadata, and wrong-project data handling.
- [ ] Cover denied access, malformed required IDs, cancellation, and unchanged existing story filter semantics.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_user_story_statuses workflows`.

## Acceptance scenarios

- [ ] Closed and archived choices are visible and semantics do not depend on English names.
- [ ] Returned IDs work with existing story update/create parameters.
- [ ] New metadata discovery leaves legacy issue-status arrays and story list behavior unchanged.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] An agent can discover valid story statuses before creating or transitioning a story.
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
| 1 | Not started | — | Specify list_user_story_statuses contracts / pending |
| 2 | Not started | — | Implement list_user_story_statuses API behavior / pending |
| 3 | Not started | — | Expose list_user_story_statuses MCP tool / pending |
| 4 | Not started | — | Verify list_user_story_statuses workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
