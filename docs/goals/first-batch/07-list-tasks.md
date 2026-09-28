# Goal 07: list_tasks

Status: complete.

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

- [x] Verify task-specific filter names/encoding rather than copying every story filter.
- [x] Define list DTO fields: id/ref/project/subject/status_id/status/assigned_to/user_story/milestone/modified and optional version.
- [x] Add fixtures for standalone and story-linked tasks, including closed statuses and unavailable labels.
- [x] Validate this step: isolated Debug build passed after the pre-existing `JsonValueKind` using fix; focused contract fixture checks are recorded for Step 2.
- [x] Update documentation now: record verified contract/source decisions and planned reference examples.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify list_tasks contracts`.

## Step 2: Implement TaskApi and DI

- [x] Add TaskApi accepting TaigaTransport; register the concrete domain API in Hosting/ServiceCollectionExtensions.cs and pass CancellationToken through every call.
- [x] Reuse query/page helpers with positive-ID/page validation, authenticated requests, success checks, and response disposal.
- [x] Map parent and sprint IDs without treating null as zero; do not fetch every parent story for listing.
- [x] Validate this step: focused TaskListTests and isolated Debug test run passed (176 tests, zero failures).
- [x] Update documentation now: document implemented wire behavior, validation/errors, and any deviations.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement list_tasks API behavior`.

## Step 3: Expose task listing

- [x] Add TaskTools with McpServerToolType and list_tasks with informative parameter descriptions.
- [x] Return the page envelope consistently and preserve unknown pagination metadata as null.
- [x] Document story-only, sprint-only, and assigned-work examples with status precedence.
- [x] Validate this step: MCP tools/list and actual tools/call coverage passed for list_tasks, including required/optional argument binding.
- [x] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose list_tasks MCP interface`.

## Step 4: Verify task discovery and filtering

- [x] Resolve TaskApi from DI, discover list_tasks through MCP, and invoke it with each main filter combination.
- [x] Cover empty pages, standalone tasks, custom closed statuses, Unicode search, null fields, 403/404, and absent headers.
- [x] Check the tool introduces no per-item parent/detail requests and all prior tools remain discoverable.
- [x] Validate this step: root `dotnet restore`, `dotnet build -c Debug`, and `dotnet test` passed; focused isolated-output tests also passed.
- [x] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify list_tasks workflow`.

## Acceptance scenarios

- [x] The tool is discoverable without manual registration of individual methods.
- [x] Story and sprint filters map to the correct wire names.
- [x] Standalone and closed tasks are returned when the chosen filters allow them.
- [x] Pagination and errors follow the batch contract.
- [x] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [x] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [x] Users can find tasks in a project, story, or sprint with a stable paginated MCP response.
- [x] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [x] The emitted MCP schema and actual invocation agree with the documented interface.
- [x] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [x] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [x] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [x] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Taiga backend revision `4d11baef9027f5598f6341d6eb4261de2840688e` reviewed 2026-09-28; pinned [TaskViewSet filters](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/api.py#L36-L60) and [TaskListSerializer fields](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/serializers.py#L22-L57) recorded. DTO and standalone/story-linked/closed/unavailable-label fixtures added. Baseline root build/test initially exposed a pre-existing missing `System.Text.Json` using; isolated build passed after the narrow test-harness fix. | Specify list_tasks contracts / d83f993 |
| 2 | Complete | `TaskApi` and `TaskListQueryBuilder` request `GET tasks` with `project`, `page`, `status`, `status__is_closed`, `user_story`, `milestone`, `assigned_to`, `tags`, and `q` only as applicable; values are encoded and one page is requested. Null parent/sprint/assignee values remain null, inline `status_extra_info.name` supplies labels, and no parent/status lookup is made. Positive input validation, HTTP/safe transport errors, malformed-list rejection, response disposal, and pagination header parsing reuse the foundation contracts. Focused isolated-output test run: 176 passed. | Implement list_tasks API behavior / 758cbeb |
| 3 | Complete | Added assembly-discovered `list_tasks` with required `projectId`, optional `page`/filters, and an always-present page envelope. MCP integration verifies schema descriptions, required/optional binding, exact encoded query, parent/sprint mapping, null pagination values, and bearer authentication. Focused isolated-output test run: 176 passed. | Expose list_tasks MCP interface / ed5c0ca |
| 4 | Complete | Focused edge and MCP suite: 181 passed. Root `dotnet restore`, `dotnet build -c Debug`, and `dotnet test`: restore/build/test passed with 181 tests, zero failures/skips, and zero build warnings/errors. Mock-only validation; no live Taiga writes or credentials used. | Verify list_tasks workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
