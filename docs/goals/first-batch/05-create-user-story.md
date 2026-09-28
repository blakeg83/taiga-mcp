# Goal 05: create_user_story

Status: planned.

## Objective

Let users create delivery tickets with enough detail and assignment to enter the backlog or a sprint.

## Scope and prerequisites

Create one story with subject, description, status, primary assignee, tags, and optional milestone. Defer estimates, multiple assignees, swimlanes, epic links, bulk creation, and custom fields.

Prerequisites: [04-get-user-story](04-get-user-story.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

create_user_story(projectId, subject, description?, status?, assigned_to?, tags?, milestoneId?) returns the server-created story detail including id/ref/version.

API mapping: POST userstories; map milestoneId to milestone and projectId to project.

Illustrative MCP arguments (IDs are placeholders):

```json
{"projectId":12,"subject":"Allow saved searches","description":"Acceptance: saved searches can be reopened."}
```

Primary verification source: [Taiga validator at pinned revision](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/userstories/validators.py). The pinned backend revision `4d11baef9027f5598f6341d6eb4261de2840688e` and its user-story API/serializer were checked on 2026-09-28; this is source evidence, not a claim about the deployed Taiga version.

## Files and integration points

- `Api/UserStoryApi.cs`
- `Tools/UserStoryTools.cs`
- `Models/UserStoryCreateDto.cs`
- `tests/TaigaMCP.Tests/UserStoryCreateTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Specify creation defaults

- [x] Add minimal and populated request fixtures; verify project defaults apply when optional fields are omitted.
- [x] Validate positive IDs and nonblank subject without stripping meaningful description whitespace.
- [x] Specify tags wire representation from the API and avoid unintentionally sending empty values for omitted options.
- [x] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [x] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify create_user_story contracts`.

## Step 2: Implement story creation

- [ ] Add a create DTO and authenticated POST method; explicitly map public parameter names to Taiga JSON keys.
- [ ] Send only supported supplied fields; let the server validate status/assignee/milestone membership.
- [ ] Reuse detail mapping and return authoritative id/ref/version; never retry the POST after timeout or mapping failure.
- [ ] Validate this step: run domain request/response tests for this behavior and Debug build.
- [ ] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement create_user_story API behavior`.

## Step 3: Expose the creation tool

- [ ] Register the create_user_story MCP method in the existing tool class with required projectId/subject only.
- [ ] Document descriptions as the place for acceptance criteria in this batch.
- [ ] Add minimal-backlog and assigned-sprint examples, marking milestone/status IDs as project-specific.
- [ ] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [ ] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose create_user_story MCP interface`.

## Step 4: Verify creation and readback

- [ ] Through MCP, create a minimal story and a populated story against fake HTTP and read each returned ID with get_user_story.
- [ ] Assert omitted optional properties stay absent and sent text/tags are correctly serialized.
- [ ] Cover whitespace-only subjects, wrong-project milestone validation, 403, 400, and lost response after one POST.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify create_user_story workflow`.

## Acceptance scenarios

- [ ] Minimal creation preserves server defaults.
- [ ] Populated creation sends correct assignment/status/milestone keys.
- [ ] Successful results contain server-generated identity/version and can be read back.
- [ ] Failures never trigger duplicate create attempts.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Users can create backlog or sprint stories through MCP with accurate defaults, results, and failure reporting.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline `dotnet restore`, `dotnet build -c Debug --no-restore` (0 warnings/errors), and `dotnet test -c Debug --no-build --no-restore` (124 passed) passed on 2026-09-28. Added passing minimal/populated JSON fixtures and inventory contract scope. Pinned Taiga backend revision `4d11baef9027f5598f6341d6eb4261de2840688e` checked 2026-09-28: `UserStoryValidator` accepts optional `tags` with an empty-list default; `UserStoryViewSet` maps creation through `userstories` and enforces project membership for status/milestone values. Request decisions: `project` and nonblank `subject` are required; null optionals are omitted; empty description/tags remain explicit; status/assignee/milestone IDs are positive locally and membership remains server validation; no create retry. README/reference/quickstart remain current until the MCP method is exposed. | Specify create_user_story contracts / pending |
| 2 | Not started | — | Implement create_user_story API behavior / pending |
| 3 | Not started | — | Expose create_user_story MCP interface / pending |
| 4 | Not started | — | Verify create_user_story workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
