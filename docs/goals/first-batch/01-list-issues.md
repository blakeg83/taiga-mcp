# Goal 01: list_issues

Status: planned.

## Objective

Let daily triage find open or completed issues with useful filters while preserving existing callers' default array response.

## Scope and prerequisites

Extend the existing tool. Support statusIds, assignedTo, typeId, priorityId, severityId, tags, query, includeClosed, page, and includePageInfo. Defer date filters, sort controls, sprint filtering, and all-page exports.

Prerequisites: [00-foundation](00-foundation.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

list_issues(projectId, page=1, statusIds?, assignedTo?, typeId?, priorityId?, severityId?, tags?, query?, includeClosed=false, includePageInfo=false). Return the existing issue array unless page metadata is requested; add numeric metadata IDs alongside existing labels.

API mapping: GET issues with project/page and verified filter parameters; issue metadata endpoints remain read-only lookup sources.

Illustrative MCP arguments (IDs are placeholders):

```json
{"projectId":12,"statusIds":[8],"page":1,"includePageInfo":true}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/issues/api.py). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Tools/IssueTools.cs`
- `Api/IssueApi.cs`
- `Models/IssueDto.cs`
- `tests/TaigaMCP.Tests/IssueListTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Specify filters and compatibility

- [x] Capture the current array result and open-only query in baseline fixtures; make the intended corrected query explicit.
- [x] Verify each public filter's wire name and multi-value encoding from issue filter source; reject invalid IDs/pages before HTTP.
- [x] Define explicit-status precedence and missing-header behavior with tests; retain the cleanup's removal of unsupported status__is_archived issue filtering.
- [x] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [x] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify list_issues contracts`.

## Step 2: Implement filtered paged retrieval

- [x] Add an internal list-options model and encoded query builder; retain a forwarding overload for current domain callers.
- [x] Remove unconditional closed-status exclusions when includeClosed=true or explicit statuses are supplied; retain the default open-only view.
- [x] Capture pagination headers before disposing the response; add metadata IDs to mapping without changing existing label properties.
- [x] Implement an internal page result shared by array and envelope modes; do not issue one detail request per issue.
- [x] Validate this step: run domain request/response tests for this behavior and Debug build.
- [x] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement list_issues API behavior`.

## Step 3: Expose the extended MCP tool

- [x] Append optional arguments without renaming projectId/page or changing existing defaults.
- [x] Add tool/parameter descriptions explaining filters, internal IDs, status precedence, and opt-in pagination.
- [x] Serialize the existing array by default and the envelope only when includePageInfo=true; keep unknown metadata explicit null.
- [x] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [x] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose list_issues MCP interface`.

## Step 4: Verify triage workflows

- [ ] Invoke through MCP with only legacy arguments, then with a closed-status filter and includePageInfo=true.
- [ ] Assert request encoding for spaces, Unicode, ampersands, and multiple tags/statuses; verify filters cannot escape their query values.
- [ ] Cover empty pages, later pages, missing/malformed headers, null assignment, unknown status labels, 403, and malformed server responses.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify list_issues workflow`.

## Acceptance scenarios

- [ ] Legacy projectId/page invocation still returns an array.
- [ ] A custom-named closed status is retrievable without hardcoded names or contradictory exclusions.
- [ ] Array and envelope modes contain identical items; missing total/continuation is not misreported as zero/complete.
- [ ] Numeric classification IDs survive even when a display label is unavailable.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Users can find both active and completed issues and reuse returned IDs for updates without breaking the original list interface.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

Step 1 evidence: the clean baseline `dotnet test -c Debug` passed 74 tests.
The legacy fixture in `IssueListTests` confirms a bare JSON array and the
corrected default query `project`, `page`, and
`status__is_closed=false`. The filter contract was verified against Taiga
revision `4d11baef9027f5598f6341d6eb4261de2840688e` on 2026-09-28:
`AssignedToFilter`, `StatusesFilter`, `IssueTypesFilter`, `PrioritiesFilter`,
`SeveritiesFilter`, `TagsFilter`, and `QFilter` use `assigned_to`, `status`,
`type`, `priority`, `severity`, `tags`, and `q`; related IDs and tags are
comma-separated values decoded by Taiga. Values will be percent-encoded by
the client. `includeClosed=false` adds only `status__is_closed=false` when no
explicit status IDs are supplied; explicit status IDs take precedence, and
`includeClosed=true` removes the automatic restriction. Unsupported
`status__is_archived` remains omitted. Missing or malformed pagination headers
will produce explicit `null` metadata rather than fabricated zero or false
values. No live Taiga requests were made.

Step 2 evidence: commit `4281680` was the Step 1 base. The internal
`IssueListOptions` and query builder now map the public filters to Taiga's
allowlisted wire names and encode values. Empty status/tag collections are
treated as no filter; nonempty explicit statuses suppress the default
open-only flag. `TaigaTransport` snapshots response headers before disposing
the response, and `IssueListPage` is shared by the future array/envelope tool
paths. Classification IDs are nullable so absent upstream fields do not
become zero. The focused `IssueListTests` run passed 6 tests and
`dotnet build -c Debug --no-restore` passed with zero warnings/errors. The
implementation does not fetch issue details per list item. No live Taiga
requests were made.

Step 3 evidence: commit `1097f1b` provided the page API. `IssueTools.ListIssues`
now appends `statusIds`, `assignedTo`, `typeId`, `priorityId`, `severityId`,
`tags`, `query`, `includeClosed`, and `includePageInfo` after the preserved
`projectId` and `page` parameters. The default remains a bare array. The
envelope contains `items`, `page`, `total`, `next_page`, and `has_more`, with
unknown metadata serialized as explicit `null`. The MCP tools/list schema and
an actual STDIO tools/call were verified by
`ProductionServer_ListsAllTools_InvokesReadTool_AndReportsUpstreamFailure`,
and the focused issue-list suite passed 8 tests. No live Taiga requests were
made.

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline `dotnet test -c Debug`: 74 passed. Contract/source decisions recorded above; legacy array fixture added. | Specify list_issues contracts / pending |
| 2 | Complete | `IssueListTests`: 6 passed; `dotnet build -c Debug --no-restore`: passed with 0 warnings/errors. Filter, ID, validation, and pagination-header behavior documented above. | Implement list_issues API behavior / pending |
| 3 | Complete | MCP discovery and real STDIO call passed; `IssueListTests`: 8 passed. README, quickstart, reference, and inventory now document the delivered interface. | Expose list_issues MCP interface / pending |
| 4 | Not started | — | Verify list_issues workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
