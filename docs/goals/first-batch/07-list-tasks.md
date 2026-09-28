# Goal 07: list_tasks

Status: planned.

## Objective

Expose actionable task lists by project, story, sprint, assignment, and status.

## Scope and prerequisites

Create the TaskApi/TaskTools foundation and one-page task listing. Support userStoryId, milestoneId, statusIds, assignedTo, tags, query, includeClosed, and page. Defer standalone-only filters, date ranges, and sorting.

Prerequisites: [00-foundation](00-foundation.md), [03-list-user-stories](03-list-user-stories.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

list_tasks(projectId, page=1, userStoryId?, milestoneId?, statusIds?, assignedTo?, tags?, query?, includeClosed=false) returns the standard page envelope.

API mapping: GET tasks with verified filters; map userStoryId to user_story and milestoneId to milestone.

Illustrative MCP arguments (IDs are placeholders):

```json
{"projectId":12,"userStoryId":102,"includeClosed":true,"page":1}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/tasks/api.py). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Api/TaskApi.cs`
- `Tools/TaskTools.cs`
- `Models/TaskDto.cs`
- `Hosting/ServiceCollectionExtensions.cs`
- `tests/TaigaMCP.Tests/TaskListTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Specify task query and response contracts

- [ ] Verify task-specific filter names/encoding rather than copying every story filter.
- [ ] Define list DTO fields: id/ref/project/subject/status_id/status/assigned_to/user_story/milestone/modified and optional version.
- [ ] Add fixtures for standalone and story-linked tasks, including closed statuses and unavailable labels.
- [ ] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [ ] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify list_tasks contracts`.

## Step 2: Implement TaskApi and DI

- [ ] Add TaskApi accepting configured HttpClient and AuthClient; register using the same named-client pattern as existing domains.
- [ ] Reuse query/page helpers with positive-ID/page validation, authenticated requests, success checks, and response disposal.
- [ ] Map parent and sprint IDs without treating null as zero; do not fetch every parent story for listing.
- [ ] Validate this step: run domain request/response tests for this behavior and Debug build.
- [ ] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement list_tasks API behavior`.

## Step 3: Expose task listing

- [ ] Add TaskTools with McpServerToolType and list_tasks with informative parameter descriptions.
- [ ] Return the page envelope consistently and preserve unknown pagination metadata as null.
- [ ] Document story-only, sprint-only, and assigned-work examples with status precedence.
- [ ] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [ ] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose list_tasks MCP interface`.

## Step 4: Verify task discovery and filtering

- [ ] Resolve TaskApi from DI, discover list_tasks through MCP, and invoke it with each main filter combination.
- [ ] Cover empty pages, standalone tasks, custom closed statuses, Unicode search, null fields, 403/404, and absent headers.
- [ ] Check the tool introduces no per-item parent/detail requests and all prior tools remain discoverable.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify list_tasks workflow`.

## Acceptance scenarios

- [ ] The tool is discoverable without manual registration of individual methods.
- [ ] Story and sprint filters map to the correct wire names.
- [ ] Standalone and closed tasks are returned when the chosen filters allow them.
- [ ] Pagination and errors follow the batch contract.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Users can find tasks in a project, story, or sprint with a stable paginated MCP response.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Not started | — | Specify list_tasks contracts / pending |
| 2 | Not started | — | Implement list_tasks API behavior / pending |
| 3 | Not started | — | Expose list_tasks MCP interface / pending |
| 4 | Not started | — | Verify list_tasks workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
