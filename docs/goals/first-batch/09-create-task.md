# Goal 09: create_task

Status: planned.

## Objective

Create implementation tasks beneath a story or as standalone project work.

## Scope and prerequisites

Create one task with description, status, assignee, tags, optional parent story, and optional sprint. Defer bulk creation, due dates, blockers, iocaine, and cross-project creation.

Prerequisites: [04-get-user-story](04-get-user-story.md), [08-get-task](08-get-task.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

create_task(projectId, subject, userStoryId?, milestoneId?, description?, status?, assigned_to?, tags?) returns created task detail. When linked to a story, its sprint is authoritative.

API mapping: POST tasks; map userStoryId to user_story and milestoneId to milestone. GET the parent story for validation when supplied.

Illustrative MCP arguments (IDs are placeholders):

```json
{"projectId":12,"subject":"Implement saved-search endpoint","userStoryId":102}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/tasks/api.py). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Api/TaskApi.cs`
- `Tools/TaskTools.cs`
- `Models/TaskCreateDto.cs`
- `tests/TaigaMCP.Tests/TaskCreateTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Define parent and sprint rules

- [ ] Specify standalone-unscheduled, standalone-sprint, and story-linked creation fixtures.
- [ ] If a parent is supplied, validate its project; if an explicit milestone differs from the parent's milestone, reject before POST.
- [ ] When parent and milestone agree, omit the redundant milestone from creation and let the server inherit it; document races are still server-validated.
- [ ] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [ ] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify create_task contracts`.

## Step 2: Implement task creation

- [ ] Add validated create payloads preserving omitted defaults and mapping parent/assignment/tag fields.
- [ ] Reuse UserStoryApi for optional parent validation through DI or a focused domain helper; avoid calling MCP tools from other tools.
- [ ] POST once and return authoritative task detail, including the resulting inherited milestone and version.
- [ ] Report successful-write/failed-response cases accurately without retrying creation.
- [ ] Validate this step: run domain request/response tests for this behavior and Debug build.
- [ ] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement create_task API behavior`.

## Step 3: Expose create_task

- [ ] Add required projectId/subject plus optional arguments and describe inheritance in the public schema.
- [ ] Document a parent-linked example and a standalone example; explain that ordinary create does not inherit the native bulk-create sprint restriction.
- [ ] Keep TaskApi construction/DI consistent if a parent lookup dependency is added.
- [ ] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [ ] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose create_task MCP interface`.

## Step 4: Verify creation workflows

- [ ] Create a parent-linked task through MCP and read it back using get_task; verify inherited sprint in the returned object.
- [ ] Test standalone creation with and without a sprint, parent mismatch, wrong project, null parent sprint, and invalid subject.
- [ ] Cover server status/assignee validation, parent lookup denial, transport failure, and one-POST-only behavior.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify create_task workflow`.

## Acceptance scenarios

- [ ] Both story-linked and standalone tasks can be created.
- [ ] A mismatched parent project or explicit sprint causes no create request.
- [ ] Returned parent/sprint/version reflect server state.
- [ ] Minimal tasks use configured project defaults.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Users can break down stories or capture standalone tasks with unambiguous parent/sprint behavior.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Not started | — | Specify create_task contracts / pending |
| 2 | Not started | — | Implement create_task API behavior / pending |
| 3 | Not started | — | Expose create_task MCP interface / pending |
| 4 | Not started | — | Verify create_task workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
