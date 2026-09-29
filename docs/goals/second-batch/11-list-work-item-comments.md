# Goal 11: list_work_item_comments

Status: implementation in progress; public tool remains planned until Step 3.

## Objective

Let agents read prior discussion on issues, stories, tasks, and epics before making changes or adding comments.

## Scope and prerequisites

Read one page of visible nonblank comments for the four WorkItemKind values. Return opaque history-entry id, comment, created_at, safe actor identity, and available edit_comment_date. Defer comment revisions/edit/delete/restore and hidden-content access.

Prerequisites: [goal 03](03-resolve-work-item.md).
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `list_work_item_comments(kind, id, page=1)`.
- Result: Standard page envelope; metadata describes the upstream type=comment history stream before local visibility filtering, so an empty items array can still have next_page.
- API operation: GET history/{issue|userstory|task|epic}/{id}?type=comment&page={page}; explicit page selects the history pagination path.
- Source evidence: the History, Pagination rows in [pinned sources](sources.md).
  Record revision/version and any verified deviations before implementation.

Illustrative MCP arguments (synthetic IDs):

```json
{
  "kind": "user_story",
  "id": 102,
  "page": 1
}
```

## Files and integration points

- `Api/WorkItemHistoryApi.cs`
- `Tools/WorkItemHistoryTools.cs`
- `Models/WorkItemCommentEntryDto.cs`
- `Hosting/ServiceCollectionExtensions.cs`
- `tests/TaigaMCP.Tests/WorkItemHistoryFixtures.cs`
- `tests/TaigaMCP.Tests/WorkItemCommentReadTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify history-backed comment reads

- [x] Verify per-kind history routes and actual paginated serialization using pinned sources; distinguish userstory route token from user_story enum value.
- [x] Add fixtures for visible/blank/hidden/deleted comments, edited comments, actor pk/name/username, and string UUID-like entry IDs.
- [x] Specify one-page header/body metadata parsing and visibility rules from contracts.md; preserve raw Markdown and omit HTML/old revisions.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify list_work_item_comments contracts`.

## Step 2: Implement shared history read infrastructure

- [ ] Add WorkItemHistoryApi using a closed kind-route map, positive ID/page validation, TaigaTransport, and end-to-end cancellation.
- [ ] Request type=comment and page explicitly; map only visible nonblank comments with neither deletion marker set.
- [ ] Reuse TaigaPagination for headers; handle only verified body pagination forms with isolated tests, and never auto-fetch later pages to fill a filtered page.
- [ ] Map actor pk to user.id when present, preserve missing/deleted actor information without inventing IDs, and register the API in DI.
- [ ] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [ ] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_work_item_comments API behavior`.

## Step 3: Expose comment reading

- [ ] Add WorkItemHistoryTools/list_work_item_comments and document opaque entry IDs versus numeric item IDs.
- [ ] Document add_work_item_comment -> list_work_item_comments and the possibility of a filtered empty page with continuation.
- [ ] Preserve existing get_issue response/comment behavior; do not silently replace its internal comment reader in this goal.
- [ ] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [ ] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_work_item_comments MCP tool`.

## Step 4: Verify conversations across all kinds

- [ ] Invoke the tool through MCP for all four kinds; submit a comment with the existing tool and read it back from a stateful fake.
- [ ] Test hidden/deleted/blank filtering, retained whitespace/Markdown/Unicode, edited date, inactive/missing actor, and string entry IDs.
- [ ] Cover empty filtered pages with next_page, last-page evidence, unknown/malformed pagination, 403/404, invalid kind, and cancellation.
- [ ] Assert no write, history revision fetch, full-page scan, or hidden/deleted body leakage occurs.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_work_item_comments workflows`.

## Acceptance scenarios

- [ ] All four kinds have paged visible-comment reads with correct routes.
- [ ] Opaque comment/history IDs and author/date context are preserved.
- [ ] Hidden/deleted/blank comments are omitted without corrupting pagination claims.
- [ ] Existing get_issue and comment-submission contracts are unchanged.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] Agents can read the current visible conversation on any supported work-item kind before acting.
- [ ] All four ordered steps and acceptance scenarios have passing recorded validation.
- [ ] Schema inspection and real MCP calls agree with the documented interface.
- [ ] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [ ] Current documentation names only delivered functionality and preserves deferred scope.
- [ ] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [ ] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `3129d8e` (`master`). Source/deployment evidence: pinned Taiga
backend revision `4d11baef9027f5598f6341d6eb4261de2840688e`; this is source
evidence only and is not a live deployment claim.

Step 1 contract decisions: history reads use `history/{kind-route}/{id}` with
`type=comment` and an explicit `page` query. The enum value `user_story` maps to
the upstream route token `userstory`; the other route tokens are `issue`,
`task`, and `epic`. The pinned `HistoryViewSet` excludes empty comments for this
filter, orders newest first, and returns a paginated `results` body whenever a
page is requested. Response headers remain authoritative when present; a
verified body `{count,next,results}` shape is the fallback when headers are
absent. Unknown or conflicting metadata remains null. Local filtering removes
hidden entries, blank/whitespace comments, and comments with either deletion
marker; envelope metadata still describes the upstream page, so visible `items`
may be empty while `next_page` remains set. Returned text is the raw comment;
`comment_html`, revisions, diffs, snapshots, and values are not exposed.
Actor `user.pk` maps to `user.id` when it is a positive integer. Missing or
deleted actors retain safe name/username/activity fields without inventing an
ID. History entry IDs are opaque strings, including UUID-like values.

Step 1 validation: baseline `dotnet test -c Debug` is recorded below. The new
fixture JSON is synthetic and does not contact Taiga; it covers visible,
whitespace, hidden, deleted, edited, missing-actor, Unicode/Markdown, and
UUID-like entry cases. No public behavior is exposed in this checkpoint.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Pinned source review; synthetic history fixtures; `dotnet test -c Debug` passed on 2026-09-29. | Specify list_work_item_comments contracts / pending |
| 2 | Not started | — | Implement list_work_item_comments API behavior / pending |
| 3 | Not started | — | Expose list_work_item_comments MCP tool / pending |
| 4 | Not started | — | Verify list_work_item_comments workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
