# Goal 06: update_user_story

Status: planned.

## Objective

Support routine story progress, reassignment, content, tagging, and sprint changes with explicit field clearing.

## Scope and prerequisites

Update subject, description, status, primary assignee, tags, milestone, and optional comment. Defer estimates, multiple assignees, swimlanes, due dates, blocking, and project moves.

Prerequisites: [02-update-issue](02-update-issue.md), [04-get-user-story](04-get-user-story.md), [05-create-user-story](05-create-user-story.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

update_user_story(userStoryId, version, subject?, description?, status?, assigned_to?, tags?, milestoneId?, comment?, clearFields?). Allowed clearFields: assigned_to, milestone. Return updated detail.

API mapping: PATCH userstories/{userStoryId}; public milestoneId maps to milestone.

Illustrative MCP arguments (IDs are placeholders):

```json
{"userStoryId":102,"version":3,"clearFields":["milestone"],"comment":"Move back to backlog."}
```

Primary verification source: [Taiga source/API at pinned revision `4d11baef9027f5598f6341d6eb4261de2840688e`](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/userstories/api.py), verified 2026-09-28. This is upstream source evidence, not a claim about the deployed version.

## Files and integration points

- `Api/UserStoryApi.cs`
- `Tools/UserStoryTools.cs`
- `Models/UserStoryUpdateDto.cs`
- `tests/TaigaMCP.Tests/UserStoryUpdateTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Define partial-update semantics

- [x] Reuse goal 02's presence-aware approach; define wire-key clear names rather than mixing milestone and milestoneId.
- [x] Add fixtures for unassignment, sprint removal, empty description/tags, comment-only updates, and untouched omissions.
- [x] Document that a story sprint change can affect its child tasks through server behavior; do not separately patch every child.
- [x] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [x] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify update_user_story contracts`.

## Step 2: Implement versioned story edits

- [ ] Build minimal PATCH bodies with the supplied version and allowed fields; validate set/clear collisions and empty changes.
- [ ] Reuse detail mapping and safe error translation, keeping returned server version authoritative.
- [ ] Do not refresh versions, replay writes, or attempt to update read-only fields after server validation failures.
- [ ] Validate this step: run domain request/response tests for this behavior and Debug build.
- [ ] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement update_user_story API behavior`.

## Step 3: Expose story edits through MCP

- [ ] Add update_user_story with required userStoryId/version and explicit descriptions for clearing/unassignment.
- [ ] Document closure/reopening by status ID and examples for returning a story to the backlog.
- [ ] Keep create/list/detail schemas compatible and document the primary-assignee-only limit.
- [ ] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [ ] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose update_user_story MCP interface`.

## Step 4: Verify read-modify-read flows

- [ ] Read version, patch status/assignment, then read back using a stateful fake; assert version forwarding and server result handling.
- [ ] Verify milestone removal sends null, omitted milestone stays absent, and unrelated story fields are not sent.
- [ ] Exercise false assumptions about every stale version failing: test both an accepted server response and a version rejection, plus 403/404 and no-retry behavior.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify update_user_story workflow`.

## Acceptance scenarios

- [ ] Status and assignment updates preserve unrelated fields.
- [ ] Explicit sprint clear differs from no sprint argument.
- [ ] Server concurrency decisions are honored without blind replay.
- [ ] MCP invocation and readback return the updated authoritative detail.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Agents can maintain story state and scheduling through narrow, versioned MCP updates.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline `dotnet restore`, `dotnet build -c Debug`, and `dotnet test -c Debug` passed on 2026-09-28: 141 tests, 0 warnings/errors. Contract fixtures validate omitted fields, explicit assignment/sprint nulls, empty description/tags, and comment-only payloads. Taiga source verified at pinned revision `4d11baef9027f5598f6341d6eb4261de2840688e` on 2026-09-28: `UserStoryViewSet.update` routes through the standard update at `PATCH userstories/{id}`; the serializer exposes `subject`, `description`, `status`, `assigned_to`, `tags`, `milestone`, `comment`, and `version`; OCC permits non-overlapping stale edits and rejects overlapping conflicts through field validation. Source: https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/userstories/api.py | Specify update_user_story contracts / pending |
| 2 | Not started | — | Implement update_user_story API behavior / pending |
| 3 | Not started | — | Expose update_user_story MCP interface / pending |
| 4 | Not started | — | Verify update_user_story workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
