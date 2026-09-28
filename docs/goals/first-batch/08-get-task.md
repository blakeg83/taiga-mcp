# Goal 08: get_task

Status: in progress.

## Objective

Provide task detail and its current version for editing and execution context.

## Scope and prerequisites

Read one task, including description, parent story, sprint, status, assignment, tags, and returned blocking/due-date information. Do not automatically load comments, attachments, or parent details.

Prerequisites: [07-list-tasks](07-list-tasks.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

get_task(taskId) returns one detail object with required id/ref/project/version and available content/workflow/parent fields.

API mapping: GET tasks/{taskId}.

Illustrative MCP arguments (IDs are placeholders):

```json
{"taskId":203}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-doc/blob/main/api/tasks/endpoints.adoc). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Api/TaskApi.cs`
- `Tools/TaskTools.cs`
- `Models/TaskDetailDto.cs`
- `tests/TaigaMCP.Tests/TaskDetailTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Define task detail fixtures

- [x] Add standalone and story-linked fixtures including null assignment/sprint and Markdown descriptions.
- [x] Define detail-only fields separately from optional list fields and preserve tags/colors.
- [x] Specify required identity/version failures and additive tolerance for unfamiliar server fields.
- [x] Validate this step: baseline restore/build/test passed; fixture JSON was reviewed for the planned cases without adding a failing suite.
- [x] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify get_task contracts`.

## Step 2: Implement task detail retrieval

- [x] Add GetTaskAsync with ID validation, auth, success validation, and response disposal.
- [x] Reuse list mapping where safe, add detail fields, and retain numeric status even when no label is available.
- [x] Return the server's parent/sprint values and current version without additional parent/history calls.
- [x] Validate this step: focused task-detail tests and Debug build passed.
- [x] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement get_task API behavior`.

## Step 3: Expose the detail tool

- [ ] Add get_task to TaskTools and describe internal taskId versus human reference.
- [ ] Document list_tasks -> get_task -> update_task, explicitly obtaining a fresh detail version.
- [ ] Ensure the returned JSON shape is a detail object and not a page envelope.
- [ ] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [ ] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose get_task MCP interface`.

## Step 4: Verify detail correctness

- [ ] Invoke via MCP and assert one task detail request plus required authentication/metadata work only.
- [ ] Cover standalone/null fields, rich text, optional blocking/due date, 404, 403, invalid IDs, and missing required version.
- [ ] Verify no task is returned on a malformed response and list_tasks behavior stays unchanged.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify get_task workflow`.

## Acceptance scenarios

- [ ] Task version and IDs match the server.
- [ ] Standalone tasks keep null story/sprint values.
- [ ] Errors cannot produce a fake empty task.
- [ ] Detail retrieval does not silently trigger unrelated data fetches.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Agents can inspect a task and obtain reliable context/version for a later update.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline `dotnet restore`, `dotnet build -c Debug --no-restore` (0 warnings/errors), and `dotnet test -c Debug --no-build --no-restore` (181 passed) passed before changes. Added standalone/story-linked fixture contracts, required identity/version malformed cases, and unknown-field tolerance. Verified 2026-09-28 against taiga-doc `7455fd37cb164bbf80198c1517fd0ef414e2a7b9` and taiga-back `4d11baef9027f5598f6341d6eb4261de2840688e`; no live Taiga calls. | Specify get_task contracts / pending |
| 2 | Complete | Focused `dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug --no-restore` passed (188 tests, 0 failures) and included standalone/story-linked mapping, null parent/sprint, Markdown/tags/colors, due-date/blocking fields, status-label absence, required-field rejection, invalid ID, malformed object, auth/request count, and no extra reads. Debug build passed with 0 warnings/errors. HTTP route is `GET tasks/{taskId}`; transport owns response disposal; no live calls. | Implement get_task API behavior / pending |
| 3 | Not started | — | Expose get_task MCP interface / pending |
| 4 | Not started | — | Verify get_task workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
