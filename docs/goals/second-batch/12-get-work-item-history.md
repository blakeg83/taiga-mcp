# Goal 12: get_work_item_history

Status: complete; implementation is complete on branch
`codex/get-work-item-history`.

## Objective

Expose who changed a work item, when, and what changed, alongside safe visible comment context.

## Scope and prerequisites

One page of combined field-change/comment history for the four kinds. Return id/type/created_at/user and available diff/values_diff/comment/edit/delete metadata/is_snapshot. Defer historical object restoration, snapshots, raw values maps, comment revisions, event filtering, and automatic summaries.

Prerequisites: [goal 11](11-list-work-item-comments.md), [goal 08](08-update-epic.md), [goal 10](10-unlink-user-story-from-epic.md).
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `get_work_item_history(kind, id, page=1)`.
- Result: Standard page envelope of visible history entries. Keep upstream event type and structured changes; provide comment_deleted=true for a retained activity entry with a deleted comment, with its comment body suppressed.
- API operation: GET history/{issue|userstory|task|epic}/{id}?page={page}; omit type=comment to include field changes.
- Source evidence: the History, Pagination, Versions rows in [pinned sources](sources.md).
  Record revision/version and any verified deviations before implementation.

Illustrative MCP arguments (synthetic IDs):

```json
{
  "kind": "epic",
  "id": 301,
  "page": 1
}
```

## Files and integration points

- `Api/WorkItemHistoryApi.cs`
- `Tools/WorkItemHistoryTools.cs`
- `Models/WorkItemHistoryEntryDto.cs`
- `tests/TaigaMCP.Tests/WorkItemHistoryTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify audit mapping and visibility

- [x] Reuse goal 11 routes/pagination/actor handling and verify diff/values_diff/type shapes against the pinned history model/serializer.
- [x] Add fixtures for pure changes, comment-only events, mixed changes/comments, deleted comments with retained field changes, hidden events, and unknown change fields.
- [x] Define bounded output fields: do not return snapshot, raw values, comment_html, or comment_versions. Suppress deleted comment text in every returned structure as required by contracts.md.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify get_work_item_history contracts`.

## Step 2: Implement history-page mapping

- [x] Add a full-history API method sharing the existing page reader but omitting the comment-only query filter.
- [x] Map core entry/actor fields and clone retained JSON changes before disposing documents; retain source ordering and type values.
- [x] Omit hidden entries; remove deleted comment content from comment/diff/values_diff while retaining separable non-comment changes and deletion metadata.
- [x] If an unknown structure prevents safe separation of deleted text, drop the unverified nested carrier or omit the entry for an unsafe root; do not serialize raw responses wholesale.
- [x] Validate this step: focused `WorkItemHistoryTests` passed 11/11; Debug build passed with zero warnings; cancellation and ownership are covered.
- [x] Update documentation during this step: the API sends `history/{route}/{id}?page=N`, supports array and verified body-page responses, and redacts deleted comment fields/text. The public function remains planned until exposed.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement get_work_item_history API behavior`.

## Step 3: Expose audit history

- [x] Add get_work_item_history with explicit one-page and upstream-count semantics; distinguish it from comment-only listing.
- [x] Document resolve_work_item -> detail -> update -> history using the returned internal ID and a separate example for reading a later history page.
- [x] Add MCP schema/call coverage, safe error behavior, and update the completed batch's expected tool count to 35 now that all 12 actually ship.
- [x] Validate this step: real MCP tools/list and tools/call checks passed, including required/default/null arguments, the unfiltered page request, and safe invalid-ID errors.
- [x] Update documentation during this step: published the callable signature, response/default/error examples, 35-tool counts, inventory delivery, and a quickstart workflow.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose get_work_item_history MCP tool`.

## Step 4: Verify audit trails and complete the batch

- [x] Use the stateful fake server to record comments for issue, user story, task, and epic updates; assert actor/time/type context in full-history reads, with field-change context covered by the API fixture.
- [x] Test hidden/deleted-content suppression including nested structures, escaped text, null/unknown fields, opaque IDs, empty filtered pages with continuation, permissions, and cancellation.
- [x] Run the existing batch scenarios using returned user/status/sprint/reference IDs, epic update/list/unlink, and comment submission/reads; the full suite uses fake HTTP only and performs no live writes.
- [x] Audit all 35 public names and preserve the baseline contracts; reconcile completed-goal counts, inventory subsets, current documentation, and links.
- [x] Validate this step: `dotnet restore`, `dotnet build -c Debug`, `dotnet test -c Debug`, `dotnet build -c Release --no-restore`, `dotnet test -c Release --no-build --no-restore`, and `git diff --check` all passed. Debug/Release builds had 0 warnings and 0 errors; both test runs passed 525/525.
- [x] Update documentation during this step: reconciled the reference, README, quickstart, inventory, development guide, and batch index with the delivered 35-tool scope and verified examples.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify get_work_item_history workflows`.

## Acceptance scenarios

- [x] All four kinds provide a paged audit trail with actor/time and structured changes.
- [x] Visible mixed activity survives where it can be separated safely from deleted comments.
- [x] No hidden or deleted comment text leaks through snapshots, revisions, or diff fields.
- [x] Shared comment reads and existing update/submission tools remain compatible.
- [x] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [x] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [x] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [x] Agents can inspect meaningful, visibility-aware audit history and the second batch's workflows compose end to end.
- [x] All four ordered steps and acceptance scenarios have passing recorded validation.
- [x] Schema inspection and real MCP calls agree with the documented interface.
- [x] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [x] Current documentation names only delivered functionality and preserves deferred scope.
- [x] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [x] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `7bab2b8d939618c65cdb65a8a2864ae956f93f86` (`7bab2b8`,
origin/master). Baseline `dotnet test -c Debug` passed with 511 tests and no
failures. Source evidence was rechecked on 2026-09-29 against pinned taiga-back
revision `4d11baef9027f5598f6341d6eb4261de2840688e`: the history serializer
exposes `id`, numeric `type`, `diff`, `values_diff`, `comment`, edit/delete
metadata, `is_hidden`, `is_snapshot`, and safe actor data; the history viewset
supports `issue`, `userstory`, `task`, and `epic`, applies newest-first ordering,
and returns an array with pagination headers when `page` is supplied. This is
pinned source evidence, not a deployed-version claim.

Step 1 contract decisions: the new reader will send `page` explicitly without
`type=comment`; map numeric `type` and clone structured `diff`/`values_diff`
values before document disposal; omit hidden entries and never expose `snapshot`,
`values`, `comment_html`, or `comment_versions`. Deleted comments set
`comment_deleted=true`, suppress the top-level body, and remove comment-labelled
or matching deleted text from structured changes while retaining separable
known scalar/non-comment fields. Unknown nested carriers and unverified text
shapes are dropped; an unsafe unstructured deleted root is omitted.
`WorkItemHistoryFixtures.FullHistoryPage` covers field-only, comment-only,
mixed/deleted, hidden, and unknown nested changes.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline `dotnet test -c Debug`: 511 passed. Pinned history serializer/viewset/choice sources rechecked; synthetic full-history fixture added with field, comment, mixed/deleted, hidden, and unknown nested changes. | Specify get_work_item_history contracts / `47726eb` |
| 2 | Complete | `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug --no-restore --filter FullyQualifiedName~WorkItemHistoryTests`: 11 passed. Debug compilation passed with zero warnings. API request is `GET history/{route}/{id}?page=N`; response mapping clones structured JSON and redacts deleted comment content. | Implement get_work_item_history API behavior / `9909a5f` |
| 3 | Complete | `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug --no-restore --filter FullyQualifiedName~McpIntegrationTests`: 12 passed. Real STDIO discovery/calls verify the 35-name set, schema (`kind,id,page` with `kind,id` required), unfiltered page request, and safe invalid-ID result. Reference, README, quickstart, inventory, development, and batch status were reconciled. | Expose get_work_item_history MCP tool / `36ebf27` |
| 4 | Complete | `dotnet restore`; Debug build/test passed with 0 warnings/errors and 525/525 tests; Release build/test passed with 0 warnings/errors and 525/525 tests; `git diff --check` passed. Focused history tests cover 14 cases and full MCP integration covers all four kinds with fake HTTP only. Follow-up redaction regression covers unknown nested carriers, HTML-decorated text, and escaped text. | Verify get_work_item_history workflows / `393187e` |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
