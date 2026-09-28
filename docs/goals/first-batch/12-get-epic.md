# Goal 12: get_epic

Status: in progress on `codex/get-epic`.

## Objective

Return the full epic context needed to understand and group related delivery work.

## Scope and prerequisites

Read one epic's description, status, assignment, color, tags, version, and server-supplied summary fields. Do not promise a complete linked-story collection or compute progress.

Prerequisites: [11-list-epics](11-list-epics.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

get_epic(epicId) returns one detail object with id/ref/project/subject/description/status_id/status/assigned_to/color/tags/version and available server summary data.

API mapping: GET epics/{epicId}.

Illustrative MCP arguments (IDs are placeholders):

```json
{"epicId":301}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/epics/serializers.py). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Api/EpicApi.cs`
- `Tools/EpicTools.cs`
- `Models/EpicDetailDto.cs`
- `tests/TaigaMCP.Tests/EpicDetailTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Define epic detail mapping

- [x] Capture fixtures with null assignee, rich description, color, tags, and required version.
- [x] Decide which verified server summary fields to expose without claiming they represent a fully fetched related-story list.
- [x] Define malformed required identity/version handling and optional-field tolerance.
- [x] Validate this step: baseline restore/build/test passed (`249` tests); the fixture/DTO contract test passed (`1` test); fixture JSON parsed successfully.
- [x] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify get_epic contracts`.

## Step 2: Implement epic retrieval

- [x] Add GetEpicAsync with validated ID, authentication, status checking, and disposed responses.
- [x] Reuse list mapping for common fields and add authoritative description/version.
- [x] Do not automatically call related_userstories or history; preserve numeric status if label lookup is unavailable.
- [x] Validate this step: focused domain tests passed (`8` tests); Debug build passed with zero warnings/errors.
- [x] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement get_epic API behavior`.

## Step 3: Expose epic detail

- [x] Register get_epic in EpicTools with the internal-ID description.
- [x] Document how to obtain an epic ID from list_epics and use it for linking an existing story.
- [x] Explicitly label returned server summary fields and document that linked-story listing is a later inventory goal.
- [x] Validate this step: real STDIO MCP tools/list and tools/call tests passed (`8` integration tests), including required argument binding and JSON output.
- [x] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose get_epic MCP interface`.

## Step 4: Verify detail and failures

- [ ] Invoke through MCP and assert full content/version and exact resource route.
- [ ] Test Unicode/Markdown, null fields, optional summary omission, and unknown server properties.
- [ ] Cover invalid ID, 403/404, missing required version, and no accidental relation fetching.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify get_epic workflow`.

## Acceptance scenarios

- [ ] Epic identity/version and description are authoritative.
- [ ] Unavailable optional summaries are not fabricated.
- [ ] A detail read makes no hidden write or full-tree traversal.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Agents can inspect an epic and obtain reliable identity/context for subsequent comments or story linking.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

Step 1 baseline on 2026-09-28: `dotnet restore`, `dotnet build -c Debug
--no-restore`, and `dotnet test -c Debug --no-build --no-restore` passed on
the clean prerequisite baseline (`249` tests, zero build warnings/errors).
Source verification used taiga-back revision
`4d11baef9027f5598f6341d6eb4261de2840688e` and taiga-doc revision
`7455fd37cb164bbf80198c1517fd0ef414e2a7b9`; neither is claimed as the
deployed version. The approved detail DTO requires positive `id`, `ref`, and
`project`, plus nonnegative `version`. `description`, status/assignment,
color, tags, modified timestamp, and server summary values are optional;
`user_stories_counts` is preserved as raw JSON when present. Inline status
labels are used without a metadata lookup, and no related-story traversal or
computed progress is part of this goal.

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline passed; pinned route/serializer evidence recorded; detail fixture and DTO contract added. | Specify get_epic contracts / `33f4f24` |
| 2 | Complete | Focused domain tests (`8`) and Debug build passed; exact route, mapping, validation, and no-relation-read behavior documented. | Implement get_epic API behavior / `32b2323` |
| 3 | In progress | Real STDIO `tools/list`/`tools/call` integration passed (`8` tests); schema, response example, internal-ID workflow, summaries, and deferred links documented. | Expose get_epic MCP interface / pending |
| 4 | Not started | — | Verify get_epic workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
