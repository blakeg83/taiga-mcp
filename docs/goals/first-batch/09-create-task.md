# Goal 09: create_task

Status: in progress.

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

## Step 1 contract decisions

The contract was checked on 2026-09-28 against Taiga backend revision
`4d11baef9027f5598f6341d6eb4261de2840688e` (the source review revision already
recorded in the tool reference). `TaskViewSet` uses the normal `POST /tasks`
create path and `TaskSerializer`; its save hook copies the parent story's
milestone to the task, while its pre-save checks reject a parent from another
project and a sprint that differs from the parent. The relevant evidence is the
[task viewset source](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/api.py#L91-L122)
and [task serializer source](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/serializers.py#L22-L64).
This is pinned source evidence, not a claim about a particular deployed Taiga
version.

The approved behavior is:

- A standalone task may omit `milestoneId` (project defaults apply) or send a
  positive `milestoneId` as `milestone`.
- A story-linked task performs a parent story lookup before `POST`. The parent
  must belong to `projectId`; an explicit `milestoneId` must equal the parent's
  milestone, including the null case. A matching milestone is redundant and is
  omitted from the task request so Taiga remains authoritative. A parent sprint
  changing between the lookup and POST is still rejected by the server.
- Optional `description`, `status`, `assigned_to`, and `tags` are serialized
  only when supplied; empty strings and arrays remain explicit. No bulk,
  due-date, blocker, iocaine, or cross-project behavior is included.

The committed fixtures cover standalone-unscheduled, standalone-sprint, and
story-linked requests, plus sprinted/unsprinted parent stories and an
authoritative created task response. Planned focused cases include wrong
parent project, parent sprint mismatch, parent lookup denial, server status or
assignee rejection, transport failure, response mapping failure, and exactly
one task POST.

## Step 2 implementation notes

`TaskApi.CreateTaskAsync` validates positive IDs and nonblank subjects before
any HTTP call. It serializes `project`, `subject`, optional `description`,
`status`, `assigned_to`, `tags`, `user_story`, and the effective standalone
`milestone`, omitting nulls while preserving empty strings and arrays. A
story-linked call uses the injected `UserStoryApi` for the parent lookup, then
issues one `POST /api/v1/tasks` and maps the response with the existing
authoritative task-detail mapper. HTTP failures are safe transport errors;
ambiguous transport or response-mapping failures explicitly say the write may
already have applied and do not trigger a second create.

## Files and integration points

- `Api/TaskApi.cs`
- `Tools/TaskTools.cs`
- `Models/TaskCreateDto.cs`
- `tests/TaigaMCP.Tests/TaskCreateTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Define parent and sprint rules

- [x] Specify standalone-unscheduled, standalone-sprint, and story-linked creation fixtures.
- [x] If a parent is supplied, validate its project; if an explicit milestone differs from the parent's milestone, reject before POST.
- [x] When parent and milestone agree, omit the redundant milestone from creation and let the server inherit it; document races are still server-validated.
- [x] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [x] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify create_task contracts`.

## Step 2: Implement task creation

- [x] Add validated create payloads preserving omitted defaults and mapping parent/assignment/tag fields.
- [x] Reuse UserStoryApi for optional parent validation through DI or a focused domain helper; avoid calling MCP tools from other tools.
- [x] POST once and return authoritative task detail, including the resulting inherited milestone and version.
- [x] Report successful-write/failed-response cases accurately without retrying creation.
- [x] Validate this step: run domain request/response tests for this behavior and Debug build.
- [x] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
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

Baseline before Step 1: `dotnet restore`, `dotnet build -c Debug`, and
`dotnet test -c Debug` passed on 2026-09-28 (191 tests, 0 warnings/errors).
No live Taiga project was used.

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Pinned backend source reviewed; contract decisions and JSON fixtures recorded. Focused fixture tests passed (3); no failing production suite was introduced. | Specify create_task contracts / `b8d8937` |
| 2 | Complete | `TaskCreateTests` passed (16); `dotnet build -c Debug` passed with 0 warnings/errors. Added `TaskCreateDto`, injected `UserStoryApi` parent validation, one-POST creation, authoritative response mapping, and safe ambiguous-write errors. | Implement create_task API behavior / pending |
| 3 | Not started | — | Expose create_task MCP interface / pending |
| 4 | Not started | — | Verify create_task workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
