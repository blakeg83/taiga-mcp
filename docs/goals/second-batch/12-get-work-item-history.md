# Goal 12: get_work_item_history

Status: planned; not implemented by this document.

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

- [ ] Reuse goal 11 routes/pagination/actor handling and verify diff/values_diff/type shapes against the pinned history model/serializer.
- [ ] Add fixtures for pure changes, comment-only events, mixed changes/comments, deleted comments with retained field changes, hidden events, and unknown change fields.
- [ ] Define bounded output fields: do not return snapshot, raw values, comment_html, or comment_versions. Suppress deleted comment text in every returned structure as required by contracts.md.
- [ ] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [ ] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify get_work_item_history contracts`.

## Step 2: Implement history-page mapping

- [ ] Add a full-history API method sharing the existing page reader but omitting the comment-only query filter.
- [ ] Map core entry/actor fields and clone retained JSON changes before disposing documents; retain source ordering and type values.
- [ ] Omit hidden entries; remove deleted comment content from comment/diff/values_diff while retaining separable non-comment changes and deletion metadata.
- [ ] If an unknown structure prevents safe separation of deleted text, omit that entry and document/test the behavior; do not serialize raw responses wholesale.
- [ ] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [ ] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement get_work_item_history API behavior`.

## Step 3: Expose audit history

- [ ] Add get_work_item_history with explicit one-page and upstream-count semantics; distinguish it from comment-only listing.
- [ ] Document resolve_work_item -> detail -> update -> history using the returned internal ID and a separate example for reading a later history page.
- [ ] Add MCP schema/call coverage, safe error behavior, and update the completed batch's expected tool count to 35 only when all 12 actually ship.
- [ ] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [ ] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose get_work_item_history MCP tool`.

## Step 4: Verify audit trails and complete the batch

- [ ] Use stateful fake issue/story/task/epic updates and comments, then assert actor/time/changed-field context in returned history.
- [ ] Test hidden/deleted-content suppression including nested structures, escaped text, null/unknown fields, opaque IDs, empty filtered pages with continuation, permissions, and cancellation.
- [ ] Run batch scenarios using returned user/status/sprint/reference IDs, epic update/list/unlink, and comment submission/reads; ensure no live calls.
- [ ] Audit all 35 public names and preserve the 23 baseline contracts; reconcile only completed goals, current counts, inventory subsets, and documentation links.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify get_work_item_history workflows`.

## Acceptance scenarios

- [ ] All four kinds provide a paged audit trail with actor/time and structured changes.
- [ ] Visible mixed activity survives where it can be separated safely from deleted comments.
- [ ] No hidden or deleted comment text leaks through snapshots, revisions, or diff fields.
- [ ] Shared comment reads and existing update/submission tools remain compatible.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] Agents can inspect meaningful, visibility-aware audit history and the second batch's workflows compose end to end.
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
| 1 | Not started | — | Specify get_work_item_history contracts / pending |
| 2 | Not started | — | Implement get_work_item_history API behavior / pending |
| 3 | Not started | — | Expose get_work_item_history MCP tool / pending |
| 4 | Not started | — | Verify get_work_item_history workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
