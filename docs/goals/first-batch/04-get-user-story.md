# Goal 04: get_user_story

Status: in progress.

## Objective

Give agents complete story context and the authoritative version needed for safe updates.

## Scope and prerequisites

Read one story's core fields, assignment, status, tags, sprint, and returned epic/source relationships. Do not load comments, task lists, or unrelated resources automatically.

Prerequisites: [03-list-user-stories](03-list-user-stories.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

get_user_story(userStoryId) returns a detail object with id, ref, project, subject, description, status_id, status, assigned_to, tags, milestone, version, and available relationship metadata.

API mapping: GET userstories/{userStoryId}. The source evidence was checked on
2026-09-28 at the pinned [`taiga-doc` endpoint definition](https://github.com/taigaio/taiga-doc/blob/7455fd37cb164bbf80198c1517fd0ef414e2a7b9/api/user-stories/endpoints.adoc)
and the pinned [`taiga-back` user-story API](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/userstories/api.py).

The detail contract uses a separate DTO from the list result. `id` must be a
positive numeric response identity and `version` must be present, numeric, and
nonnegative; missing or malformed required fields are failures, never version
zero defaults. Other core fields remain nullable and are omitted from public
JSON when null, while an explicitly empty `tags` array remains `[]`. Taiga's
tag/color arrays and the `epics`, `origin_issue`, and `origin_task` relationship
objects are retained as response JSON so additive nested upstream fields are
not discarded. Unknown top-level fields are ignored.

Representative response fixture (relationship fields are optional):

```json
{
  "id": 102,
  "ref": 18,
  "project": 12,
  "subject": "Allow saved searches",
  "description": "**Acceptance:** preserve Markdown and Unicode — ✓",
  "status": 7,
  "status_extra_info": {"name": "Ready"},
  "assigned_to": null,
  "tags": [["search", "#336699"], ["backend", null]],
  "milestone": null,
  "modified_date": "2026-09-28T12:00:00Z",
  "version": 4,
  "origin_issue": null,
  "origin_task": null,
  "epics": []
}
```

Illustrative MCP arguments (IDs are placeholders):

```json
{"userStoryId":102}
```

Caller workflow: list stories for a placeholder project such as `12345`, take
the returned internal `id` (for example `102`, not displayed `#ref`), call
`get_user_story(userStoryId=102)`, and pass its returned `version` (for example
`4`) to the planned `update_user_story` command. The update command is outside
this goal and is not yet exposed.

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-doc/blob/main/api/user-stories/endpoints.adoc). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Api/UserStoryApi.cs`
- `Tools/UserStoryTools.cs`
- `Models/UserStoryDetailDto.cs`
- `tests/TaigaMCP.Tests/UserStoryDetailTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Define the detail response

- [x] Capture representative detail fixtures with null assignee/sprint, tags/colors, and optional relationships.
- [x] Keep a separate detail DTO or shared mapper that does not cause list calls to emit fabricated detail fields.
- [x] Specify required identity/version validation and additive unknown-field tolerance.
- [x] Validate this step: baseline restore/build/test passed; the representative fixture is valid JSON; focused detail behavior cases are recorded for step 4 without committing a failing suite.
- [x] Update documentation now: record verified contract/source decisions and planned reference examples.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify get_user_story contracts`.

## Step 2: Implement detail retrieval

- [x] Add `GetUserStoryAsync` with positive-ID validation, authentication, success validation, and response disposal.
- [x] Map status ID and label from returned extra information or a project-scoped lookup; preserve ID when label is unavailable.
- [x] Return description unchanged, preserve nullable fields and tags, and avoid implicit additional relation/history requests.
- [x] Validate this step: `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug` passed with 120 tests; `dotnet build -c Debug --no-restore` passed with 0 warnings/errors.
- [x] Update documentation now: the API uses the detail route, strict required identity/version parsing, optional status lookup, and safe transport errors; comments/tasks are not requested.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement get_user_story API behavior`.

## Step 3: Expose the detail tool

- [x] Add the `get_user_story` MCP method and descriptions distinguishing internal ID from displayed `#ref`.
- [x] Return a JSON detail object and keep `list_user_stories` behavior unchanged.
- [x] Document a list -> detail -> update example using placeholders rather than production IDs.
- [x] Validate this step: 6 MCP integration tests passed, covering `tools/list`, required schema binding, actual `tools/call`, exact detail URI, and returned version.
- [x] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose get_user_story MCP interface`.

## Step 4: Verify story detail behavior

- [ ] Invoke through MCP and assert exact URI, parsed detail fields, and returned version.
- [ ] Cover null fields, Unicode/Markdown description, absent optional relationships, unknown added properties, and malformed required fields.
- [ ] Verify 403/404 and transport failures are tool failures rather than empty story objects.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify get_user_story workflow`.

## Acceptance scenarios

- [ ] The result contains the exact server version and numeric status ID.
- [ ] Null parent/assignment values and Markdown are preserved.
- [ ] A missing story or invalid payload cannot masquerade as a valid version-zero story.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] An agent can read a story and obtain sufficient authoritative data for the planned update command.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline `dotnet restore`, `dotnet build -c Debug`, and `dotnet test -c Debug --no-build` passed on 2026-09-28: 112 tests, 0 warnings/errors. Pinned `taiga-doc` revision `7455fd37cb164bbf80198c1517fd0ef414e2a7b9` documents `GET /api/v1/userstories/{userStoryId}`; pinned backend revision `4d11baef9027f5598f6341d6eb4261de2840688e` confirms the detail serializer's tags, epics, and origin fields. | Specify get_user_story contracts / 70ece54 |
| 2 | Complete | `UserStoryDetailTests` cover exact detail routing, authentication, status-extra-info and project lookup labels, Markdown/Unicode, nulls, empty tags, raw relationships, malformed identity/version, and pre-HTTP ID validation. Focused Debug tests: 120 passed. Debug build: 0 warnings/errors. | Implement get_user_story API behavior / ce991dd |
| 3 | Complete | 6 MCP integration tests passed. They discover 12 tools, verify `get_user_story` requires only `userStoryId`, call it through STDIO, assert exact `/api/v1/userstories/90` routing, bearer auth, JSON detail, and version 4; list behavior remains covered. | Expose get_user_story MCP interface / pending |
| 4 | Not started | — | Verify get_user_story workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
