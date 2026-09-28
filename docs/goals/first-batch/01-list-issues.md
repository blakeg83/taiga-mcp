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

- [ ] Capture the current array result and open-only query in baseline fixtures; make the intended corrected query explicit.
- [ ] Verify each public filter's wire name and multi-value encoding from issue filter source; reject invalid IDs/pages before HTTP.
- [ ] Define explicit-status precedence and missing-header behavior with tests; retain the cleanup's removal of unsupported status__is_archived issue filtering.
- [ ] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [ ] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify list_issues contracts`.

## Step 2: Implement filtered paged retrieval

- [ ] Add an internal list-options model and encoded query builder; retain a forwarding overload for current domain callers.
- [ ] Remove unconditional closed-status exclusions when includeClosed=true or explicit statuses are supplied; retain the default open-only view.
- [ ] Capture pagination headers before disposing the response; add metadata IDs to mapping without changing existing label properties.
- [ ] Implement an internal page result shared by array and envelope modes; do not issue one detail request per issue.
- [ ] Validate this step: run domain request/response tests for this behavior and Debug build.
- [ ] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement list_issues API behavior`.

## Step 3: Expose the extended MCP tool

- [ ] Append optional arguments without renaming projectId/page or changing existing defaults.
- [ ] Add tool/parameter descriptions explaining filters, internal IDs, status precedence, and opt-in pagination.
- [ ] Serialize the existing array by default and the envelope only when includePageInfo=true; keep unknown metadata explicit null.
- [ ] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [ ] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose list_issues MCP interface`.

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

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Not started | — | Specify list_issues contracts / pending |
| 2 | Not started | — | Implement list_issues API behavior / pending |
| 3 | Not started | — | Expose list_issues MCP interface / pending |
| 4 | Not started | — | Verify list_issues workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
