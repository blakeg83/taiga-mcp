# Goal 10: unlink_user_story_from_epic

Status: planned; Steps 1–2 are complete; public exposure and final verification
remain planned until later checkpoints.

## Objective

Remove a mistaken epic/story association while preserving both work items and their other relationships.

## Scope and prerequisites

Delete one nested relationship. Add the minimal transport no-content support required for HTTP 204. Defer deleting work items, bulk unlinking, reordering, implicit relinking, or catch-all idempotent success.

Prerequisites: [goal 09](09-list-epic-user-stories.md).
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `unlink_user_story_from_epic(epicId, userStoryId)`.
- Result: { epic_id, user_story_id, removed: true } only after a confirmed successful no-content response. A 404 remains an error, including a repeated unlink of an absent link.
- API operation: DELETE epics/{epicId}/related_userstories/{userStoryId}; expected response HTTP 204 without JSON.
- Source evidence: the Epics and relationships rows in [pinned sources](sources.md).
  Record revision/version and any verified deviations before implementation.

Illustrative MCP arguments (synthetic IDs):

```json
{
  "epicId": 301,
  "userStoryId": 102
}
```

## Files and integration points

- `Api/TaigaTransport.cs`
- `Api/EpicApi.cs`
- `Tools/EpicTools.cs`
- `Models/EpicUserStoryUnlinkDto.cs`
- `tests/TaigaMCP.Tests/TransportTests.cs`
- `tests/TaigaMCP.Tests/EpicStoryUnlinkTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify DELETE success and ownership

- [x] Verify nested deletion semantics and expected 204 status from the pinned viewset/base CRUD path before coding.
- [x] Add fixtures for 204 empty content, 403/404, 401 then 204, unexpected responses, cancellation, and transport failure.
- [x] Define no version parameter for this relationship operation; do not infer an absent/access-denied parent from a 404.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify unlink_user_story_from_epic contracts`.

## Step 2: Add no-content transport and unlink API

- [x] Add a narrowly named TaigaTransport no-content send method using operation-scoped factory clients, AuthClient, safe status checks, and response disposal.
- [x] Handle expected empty success without JSON parsing; keep existing ReadAsync behavior strict for JSON endpoints. Reuse shared send/error rules without weakening status validation.
- [x] Extend EpicApi to validate IDs and issue DELETE only to the nested path; return a removal receipt after confirmed success.
- [x] Preserve existing one-replay-only behavior for a received 401; ambiguous deletion/response failures remain potentially applied and are not replayed.
- [x] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [x] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement unlink_user_story_from_epic API behavior`.

## Step 3: Expose relationship removal

- [ ] Add the tool to EpicTools with descriptions distinguishing unlinking from story/epic deletion and explaining repeated-call 404 behavior.
- [ ] Document list_epic_user_stories -> select user_story_id -> unlink -> list again.
- [ ] Add protocol tests for the receipt, safe failures, and cancellation invisibility in the schema.
- [ ] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [ ] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose unlink_user_story_from_epic MCP tool`.

## Step 4: Verify preservation and empty responses

- [ ] Use a stateful fake with a story linked to two epics; unlink one and prove the story, epic, and other link still exist.
- [ ] Assert correct DELETE path and no DELETE requests to stories/epics, no PATCHes, and no unwanted preflight all-page reads.
- [ ] Verify response disposal on 204/errors/cancellation, exact 401 replay limits, no JSON parse on 204, and no false success for 404 or transport ambiguity.
- [ ] Run transport regression tests to ensure malformed/empty responses to existing JSON reads still fail.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify unlink_user_story_from_epic workflows`.

## Acceptance scenarios

- [ ] HTTP 204 produces a valid MCP JSON removal receipt without attempting to parse an empty body.
- [ ] Only the selected relationship is removed.
- [ ] 403/404 and ambiguous failures are surfaced, while only received-401 auth replay is allowed.
- [ ] Existing transport disposal, bounded error, cancellation, and JSON-read contracts remain intact.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] Agents can correct epic membership without deleting work items or misreporting unsuccessful removals.
- [ ] All four ordered steps and acceptance scenarios have passing recorded validation.
- [ ] Schema inspection and real MCP calls agree with the documented interface.
- [ ] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [ ] Current documentation names only delivered functionality and preserves deferred scope.
- [ ] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [ ] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `c51bfd1adda74b52a44dd42135a25c4800f255fc` on
`codex/unlink-user-story-from-epic`. Baseline focused validation:
`dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug` passed with
471 tests, 0 failures, 0 skipped. Source/deployment evidence: the pinned
Taiga backend revision `4d11baef9027f5598f6341d6eb4261de2840688e` was checked
read-only; this is not a live deployment claim.

Step 1 contract decisions and source evidence:

- `EpicRelatedUserStoryViewSet` declares `lookup_field = "user_story"` and is
  nested under the epic, so the operation is `DELETE
  epics/{epicId}/related_userstories/{userStoryId}`.
- The viewset inherits `ModelCrudViewSet`; its pinned destroy mixin resolves the
  nested object, checks permissions, deletes only that relationship, and returns
  `response.NoContent()` (HTTP 204 with no JSON body).
- Missing or inaccessible relationships remain server errors (404/403); a 404
  is not interpreted as an already-successful unlink. The operation has no
  version argument and performs no parent/story preflight lookup.
- Step 1 fixtures cover empty 204 success, safe 403/404/401 detail objects, an
  unexpected successful body, and the planned cancellation/transport-failure
  cases without introducing future-behavior stubs.

Step 2 implementation and validation:

- `TaigaTransport.SendNoContentAsync` obtains and disposes one named factory
  client per operation, delegates authentication/status/error handling to the
  existing path, accepts only HTTP 204, and never parses the response body.
  Existing JSON reads remain unchanged and strict.
- `EpicApi.UnlinkUserStoryFromEpicAsync` validates both positive IDs, sends
  exactly `DELETE epics/{epicId}/related_userstories/{userStoryId}`, and returns
  the receipt only after the transport confirms 204. It performs no relationship
  lookup, parent/story read, PATCH, or retry after an ambiguous failure.
- Focused validation:
  `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug --no-restore
  --filter "FullyQualifiedName~TransportTests|FullyQualifiedName~EpicStoryUnlink"`
  passed 36 tests with 0 failures, 0 skipped, and no warnings. Coverage includes
  204 body non-parsing/disposal, 403/404 safe errors, unexpected success status,
  one 401 replay, cancellation, transport failure, ID validation, and exact
  nested request ownership. The Debug build completed as part of that command.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline: 471 focused tests passed. Pinned source revision and nested DELETE/204 semantics recorded above; fixture-only tests pass. | Specify unlink_user_story_from_epic contracts / `27f1657` |
| 2 | Complete | Focused transport/API tests: 36 passed; no warnings. 204 no-content ownership, status/error handling, cancellation, one-401 replay, exact DELETE path, receipt, and ambiguous-failure behavior recorded above. | Implement unlink_user_story_from_epic API behavior / pending |
| 3 | Not started | — | Expose unlink_user_story_from_epic MCP tool / pending |
| 4 | Not started | — | Verify unlink_user_story_from_epic workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
