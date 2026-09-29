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

- [x] Add WorkItemHistoryApi using a closed kind-route map, positive ID/page validation, TaigaTransport, and end-to-end cancellation.
- [x] Request type=comment and page explicitly; map only visible nonblank comments with neither deletion marker set.
- [x] Reuse TaigaPagination for headers; handle only verified body pagination forms with isolated tests, and never auto-fetch later pages to fill a filtered page.
- [x] Map actor pk to user.id when present, preserve missing/deleted actor information without inventing IDs, and register the API in DI.
- [x] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [x] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement list_work_item_comments API behavior`.

## Step 3: Expose comment reading

- [x] Add WorkItemHistoryTools/list_work_item_comments and document opaque entry IDs versus numeric item IDs.
- [x] Document add_work_item_comment -> list_work_item_comments and the possibility of a filtered empty page with continuation.
- [x] Preserve existing get_issue response/comment behavior; do not silently replace its internal comment reader in this goal.
- [x] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [x] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose list_work_item_comments MCP tool`.

## Step 4: Verify conversations across all kinds

- [x] Invoke the tool through MCP for all four kinds; submit a comment with the existing tool and read it back from a stateful fake.
- [x] Test hidden/deleted/blank filtering, retained whitespace/Markdown/Unicode, edited date, inactive/missing actor, and string entry IDs.
- [x] Cover empty filtered pages with next_page, last-page evidence, unknown/malformed pagination, 403/404, invalid kind, and cancellation.
- [x] Assert no write, history revision fetch, full-page scan, or hidden/deleted body leakage occurs.
- [x] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [x] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify list_work_item_comments workflows`.

## Acceptance scenarios

- [x] All four kinds have paged visible-comment reads with correct routes.
- [x] Opaque comment/history IDs and author/date context are preserved.
- [x] Hidden/deleted/blank comments are omitted without corrupting pagination claims.
- [x] Existing get_issue and comment-submission contracts are unchanged.
- [x] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [x] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [x] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [x] Agents can read the current visible conversation on any supported work-item kind before acting.
- [x] All four ordered steps and acceptance scenarios have passing recorded validation.
- [x] Schema inspection and real MCP calls agree with the documented interface.
- [x] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [x] Current documentation names only delivered functionality and preserves deferred scope.
- [x] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [x] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `3129d8e` (`master`). Source/deployment evidence: pinned Taiga
backend revision `4d11baef9027f5598f6341d6eb4261de2840688e`; this is source
evidence only and is not a live deployment claim.

Step 1 contract decisions: history reads use `history/{kind-route}/{id}` with
`type=comment` and an explicit `page` query. The enum value `user_story` maps to
the upstream route token `userstory`; the other route tokens are `issue`,
`task`, and `epic`. The pinned `HistoryViewSet` excludes empty comments for this
filter, orders newest first, and returns an array body with pagination headers
when a page is requested. The client also has a narrowly validated
`{count,next,results}` compatibility fallback from the shared batch contract;
that object-body form is not claimed as pinned-backend behavior. Response
headers remain authoritative when meaningful; unknown or conflicting metadata
remains null. Local filtering removes
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

Step 2 implementation decisions: `WorkItemHistoryApi` owns the shared comment
read and exposes an internal page result for tools. It accepts Taiga's array
response with pinned pagination headers and the exact compatible
`{count,next,results}` body fallback. Header metadata is used when it is the
only source; a body field is used when the matching header is absent or only
`x-paginated: true` is present without a next URL, and malformed or conflicting
metadata remains null. A valid body `next: null` is explicit last-page evidence
(`has_more=false`). Comment
mapping filters hidden entries, whitespace-only/non-string comments, and either
deletion marker before validating visible entry identity/timestamp. It preserves
raw comment text and only maps safe user `pk`, `name`, `username`, and
`is_active` fields; HTML, revisions, diffs, snapshots, and values are excluded.
No later page is fetched to fill a filtered page. `TaigaPagination` gained only
the shared safe next-page parser needed by this fallback.

Step 2 validation: focused `WorkItemCommentReadTests` passed 17/17, including
all four route tokens, exact query serialization, filtering, UUID-like IDs,
actor mapping, empty filtered pages with continuation, body/header pagination,
malformed/conflicting metadata, safe 403 handling, pre-cancellation, and
response disposal. A Debug build passed as part of that run. No source
deviations from the pinned history contract were found.

Step 3 implementation decisions: `WorkItemHistoryTools` is a thin MCP wrapper
over the concrete history API and returns `ToolResponseJson.SerializePage`.
The public signature is `list_work_item_comments(kind, id, page=1)`; only
`kind` and `id` are required in the generated schema, and `cancellationToken`
is not exposed. Existing `get_issue` still uses its original internal comment
reader and response shape. The reference, README, quickstart, inventory, and
batch index now describe 34 callable tools, with full history and comment
revision/edit/delete/restore still deferred.

Step 3 validation: the real `ProductionServer_ListsAllTools_InvokesReadTool_AndReportsUpstreamFailure`
MCP session passed. It verified the 34-name `tools/list` result, the new
`kind/id/page` schema and enum, a default-page `tools/call`, exact history query,
missing-required and explicit-null argument failures, and an invalid-ID safe
error without an HTTP request. The existing get-issue comment path remains
covered by the full suite.

Step 4 verification: the stateful `FakeTaigaHttpServer` records successful
comment-only PATCHes and serves the resulting history for all four route kinds.
The real MCP workflow submits and reads back Markdown/Unicode comments with
opaque IDs and safe actor identity. Focused/API fixtures cover hidden, deleted,
blank, whitespace-preserving, edited, inactive, missing-actor, UUID-like, and
filtered-empty pages; they also cover array/header pagination and the narrow
compatible header/body fallback,
last-page `next=null`, malformed/conflicting metadata, 403/404, invalid input,
pre-cancellation, response ownership, and no revision/full-page follow-up.
The existing `get_issue` path and comment-submission tests remain unchanged.

Final validation commands and results (2026-09-29): `dotnet restore` passed;
`dotnet build -c Debug` passed with 0 warnings/errors and output under
`bin/Debug/net8.0`; `dotnet test -c Debug` passed 511/511; `dotnet build -c
Release --no-restore` passed with 0 warnings/errors and output under
`bin/Release/net8.0`; `dotnet test -c Release --no-build --no-restore` passed
511/511; and `git diff --check` passed. Review follow-up validation added
mixed `x-paginated: true` plus body-continuation/final-page cases; all focused
and full suites passed. The pinned backend evidence was corrected to distinguish
its array-plus-header response from the optional compatible object-body fallback.
Generated outputs remain ignored and no credentials or live Taiga data were used.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Pinned source review; synthetic history fixtures; `dotnet test -c Debug` passed on 2026-09-29. | Specify list_work_item_comments contracts / `349e3b6` |
| 2 | Complete | Focused `WorkItemCommentReadTests`: 17 passed at checkpoint; Debug build passed; DI/API/transport behavior recorded above. | Implement list_work_item_comments API behavior / `20c08d3` |
| 3 | Complete | Real STDIO `tools/list`/`tools/call` integration passed; public docs and counts updated. | Expose list_work_item_comments MCP tool / `1e6d271` |
| 4 | Complete | Stateful four-kind MCP read-back plus final 511-test Debug/Release validation, review fixes, and `git diff --check` passed. | Verify list_work_item_comments workflows / `f152f44` + review fix pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
