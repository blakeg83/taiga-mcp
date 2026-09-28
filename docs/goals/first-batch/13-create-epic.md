# Goal 13: create_epic

Status: complete on `codex/create-epic`.

## Objective

Create an epic to group a larger feature or initiative.

## Scope and prerequisites

Create one epic with subject, description, status, assignee, color, and tags. Defer requirement flags, related-story creation, bulk operations, and custom fields.

Prerequisites: [12-get-epic](12-get-epic.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

create_epic(projectId, subject, description?, status?, assigned_to?, color?, tags?) returns the created epic detail with id/ref/version.

API mapping: POST epics.

Illustrative MCP arguments (IDs are placeholders):

```json
{"projectId":12,"subject":"Saved search experience","description":"Group saved-search delivery work."}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/epics/validators.py). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Api/EpicApi.cs`
- `Tools/EpicTools.cs`
- `Models/EpicCreateDto.cs`
- `tests/TaigaMCP.Tests/EpicCreateTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Specify epic creation defaults

- [x] Add minimal and populated payload fixtures and verify optional color/status can be omitted for server defaults.
- [x] Validate required project/subject and supplied IDs; verify accepted color formats before imposing local validation.
- [x] Document that linking stories is a separate operation and this call creates only one epic.
- [x] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [x] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify create_epic contracts`.

## Step 2: Implement epic POST

- [x] Add a create DTO and authenticated method that sends only supplied optional fields.
- [x] Reuse detail mapping for the returned server identity, version, and generated/default color.
- [x] Preserve project-module/permission validation and do not retry non-idempotent creation on errors.
- [x] Validate this step: run domain request/response tests for this behavior and Debug build.
- [x] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement create_epic API behavior`.

## Step 3: Expose create_epic

- [x] Add the MCP method with required projectId/subject and descriptions for project-specific status/assignee IDs.
- [x] Document minimal and customized examples and a follow-up link_user_story_to_epic call.
- [x] Ensure no implicit project configuration change enables epics behind the user's request.
- [x] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [x] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose create_epic MCP interface`.

## Step 4: Verify epic creation and readback

- [x] Create through MCP against fake HTTP and read returned epicId with get_epic.
- [x] Assert omitted defaults stay omitted; confirm provided description, color, tags, and assignment reach Taiga.
- [x] Cover disabled epics, invalid status/color responses, permissions, malformed success response, and ambiguous timeout without replay.
- [x] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [x] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify create_epic workflow`.

## Acceptance scenarios

- [x] Minimal creation uses server defaults and returns generated identity/version.
- [x] Populated creation maps optional fields correctly.
- [x] No stories or project settings are modified as a side effect by the client.
- [x] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [x] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [x] Users can create an epic through MCP and use its returned ID for grouping work.
- [x] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [x] The emitted MCP schema and actual invocation agree with the documented interface.
- [x] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [x] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [x] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [x] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline `dotnet restore`, Debug build, and 261 tests passed. Pinned taiga-back `4d11baef9027f5598f6341d6eb4261de2840688e` and taiga-doc `7455fd37cb164bbf80198c1517fd0ef414e2a7b9` checked on 2026-09-28; fixture tests verify minimal omission and populated wire keys. Color format is delegated to Taiga because the model accepts a string up to 32 characters. Linking stories and requirement flags remain planned. | Specify create_epic contracts / b86376e |
| 2 | Complete | `EpicCreateTests` cover minimal/default omission, populated serialization and mapping, explicit empty values, invalid inputs before HTTP, safe 400/403 failures, ambiguous transport failure without retry, and malformed success response. `dotnet test` focused create suite and Debug build passed. | Implement create_epic API behavior / cd8ff9a |
| 3 | Complete | MCP integration verifies `tools/list` exposes `create_epic` with required `projectId`/`subject` and optional fields, plus minimal and populated `tools/call` requests and returned identity/version. README, quickstart, reference, and inventory now describe the implemented scope and planned separate linking. | Expose create_epic MCP interface / 4ad326c |
| 4 | Complete | Focused Step 4 tests passed (12), including MCP create/readback, omitted/populated requests, no story/project side effects, disabled/invalid status/color validation, permission denial, malformed success, and no replay after ambiguous transport failure. Root restore passed; Debug and Release builds completed with 0 warnings/errors; Debug and Release test runs each passed 275 tests. | Verify create_epic workflow |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
