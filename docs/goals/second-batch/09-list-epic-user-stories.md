# Goal 09: list_epic_user_stories

Status: implementation in progress; the relationship contract is specified and
the public tool remains planned until Step 3.

## Objective

Expose the existing stories linked to an epic so agents can inspect or correct its membership.

## Scope and prerequisites

One page of relationship identities and order. Return epic_id, user_story_id, order. Defer implicit story-detail enrichment, cross-project summary aggregation, reordering, and computed progress.

Prerequisites: the implemented first-batch baseline; no new function dependency.
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `list_epic_user_stories(epicId, page=1)`.
- Result: Standard page envelope of relationship DTOs. This is an index of linked story IDs, not full story details or a list of newly created stories; use get_user_story on a selected ID.
- API operation: GET epics/{epicId}/related_userstories?page={page}.
- Source evidence: the Epics and relationships, Pagination rows in [pinned sources](sources.md).
  Record revision/version and any verified deviations before implementation.

Illustrative MCP arguments (synthetic IDs):

```json
{
  "epicId": 301,
  "page": 1
}
```

## Files and integration points

- `Api/EpicApi.cs`
- `Tools/EpicTools.cs`
- `Models/EpicUserStoryRelationshipDto.cs`
- `tests/TaigaMCP.Tests/EpicStoryListTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify relationship listing

- [x] Verify the nested serializer returns epic/user_story/order, with lookup by story ID and no independent public relationship ID.
- [x] Keep the existing link receipt's created flag out of the new list DTO; listing must not imply creation.
- [x] Add empty/single/multiple/cross-project relationship fixtures and page metadata; define epic identity consistency checks.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify list_epic_user_stories contracts`.

## Step 2: Implement one-page relationship reads

- [x] Extend EpicApi using TaigaTransport/TaigaPagination, validated epicId/page, and cloned/scalar response mapping.
- [x] Map epic and user_story to explicit *_id output names and require each epic_id to match the requested epic.
- [x] Preserve server order and the long order value; avoid one detail request per story or assumptions that all linked stories share a project.
- [x] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [x] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_epic_user_stories API behavior`.

## Step 3: Expose the linked-story index

- [ ] Add list_epic_user_stories with descriptions stating its lightweight result and one-page scope.
- [ ] Document list_epics/get_epic -> relationship list -> get_user_story for selected full details.
- [ ] Add MCP discovery/invocation tests and preserve existing link/get_epic shapes and no-expansion defaults.
- [ ] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [ ] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_epic_user_stories MCP tool`.

## Step 4: Verify group inspection

- [ ] Link existing stories in a stateful fake, list the relationship page, and fetch one returned story ID with get_user_story.
- [ ] Test zero/multiple links, later pages, large/zero order values, malformed IDs, mismatched epic, permissions, and cancellation.
- [ ] Assert the list makes no writes or per-item detail requests and missing pagination is not reported as a complete epic backlog.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_epic_user_stories workflows`.

## Acceptance scenarios

- [ ] Agents can obtain linked story IDs/order without creating or modifying relationships.
- [ ] Cross-project membership is represented without a fabricated same-project constraint.
- [ ] The page result does not claim full story details, creation state, or calculated epic progress.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] An agent can enumerate an epic's linked story identities page by page and inspect selected stories.
- [ ] All four ordered steps and acceptance scenarios have passing recorded validation.
- [ ] Schema inspection and real MCP calls agree with the documented interface.
- [ ] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [ ] Current documentation names only delivered functionality and preserves deferred scope.
- [ ] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [ ] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `1da9990` (`origin/master`). Source evidence is pinned
taiga-back revision `4d11baef9027f5598f6341d6eb4261de2840688e`; no live
deployment version was inspected or claimed. The pinned relationship serializer
defines `epic` from `epic_id`, `user_story` from `user_story_id`, and `order`;
the nested viewset uses `user_story` as its lookup field. This confirms that the
new list DTO must not expose the existing link receipt's `created` flag or a
relationship ID. No source-shape deviation was found. The current reference's
older link-source citation describes the same fields, but this goal uses the
batch's current pinned revision.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline `dotnet restore`, `dotnet build -c Debug --no-restore`, and `dotnet test -c Debug --no-restore` passed; 452 existing tests passed. Added source-backed empty, single, multiple, zero/large-order, cross-project-identity, and pagination fixtures plus the creation-free DTO contract. | Specify list_epic_user_stories contracts / pending |
| 2 | Complete | `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug --no-restore --filter FullyQualifiedName~EpicStoryList` passed 17 focused tests; a serial Debug build passed with 0 warnings/errors. API tests cover exact `?page=2`, empty/unknown metadata, scalar ownership, long/zero order, cross-project IDs without detail reads, malformed/mismatched responses, 403 sanitization, invalid inputs, and pre-cancellation. | Implement list_epic_user_stories API behavior / pending |
| 3 | Not started | — | Expose list_epic_user_stories MCP tool / pending |
| 4 | Not started | — | Verify list_epic_user_stories workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
