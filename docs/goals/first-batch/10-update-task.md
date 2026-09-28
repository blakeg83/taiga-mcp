# Goal 10: update_task

Status: in progress.

## Objective

Support frequent task progress, assignment, content, tagging, and blocking changes.

## Scope and prerequisites

Update subject, description, status, primary assignee, tags, isBlocked/blockedNote, and optional comment. Defer reparenting, sprint moves, dates, iocaine, and project changes.

Prerequisites: [02-update-issue](02-update-issue.md), [08-get-task](08-get-task.md), [09-create-task](09-create-task.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

update_task(taskId, version, subject?, description?, status?, assigned_to?, tags?, isBlocked?, blockedNote?, comment?, clearFields?). Only assigned_to is clearable; blockedNote="" clears the note. Return updated task detail.

API mapping: PATCH tasks/{taskId}; map isBlocked to is_blocked and blockedNote to blocked_note after verifying support.

Illustrative MCP arguments (IDs are placeholders):

```json
{"taskId":203,"version":2,"isBlocked":false,"blockedNote":"","comment":"Dependency resolved."}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/tasks/models.py). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Api/TaskApi.cs`
- `Tools/TaskTools.cs`
- `Models/TaskUpdateDto.cs`
- `tests/TaigaMCP.Tests/TaskUpdateTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Define task edit cases

- [x] Reuse presence-aware PATCH conventions with fixtures for omitted fields, explicit unassignment, false isBlocked, and empty tags/description.
- [x] Define blocking behavior: setting/unsetting the boolean does not implicitly overwrite the note; callers explicitly clear it when desired.
- [x] Validate version, at least one actual change, and assignment set/clear conflicts before HTTP.
- [x] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [x] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify update_task contracts`.

## Step 2: Implement task PATCH

- [ ] Build a minimal body with the caller's version, whitelisted edits, and exact mapped blocking keys.
- [ ] Ensure nullable bool false is serialized and omitted bool is absent; never infer completion from an English status label.
- [ ] Reuse detail mapping and safe error handling; do not implicitly patch parent story or sprint.
- [ ] Validate this step: run domain request/response tests for this behavior and Debug build.
- [ ] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement update_task API behavior`.

## Step 3: Expose task edits

- [ ] Add update_task to TaskTools with required taskId/version and clear blocking/unassignment descriptions.
- [ ] Document a read -> status update example and an unblock call that explicitly clears the note.
- [ ] Ensure omission and explicit false bind correctly through the installed MCP SDK.
- [ ] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [ ] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose update_task MCP interface`.

## Step 4: Verify progress and failure paths

- [ ] Invoke assignment, status change, unassignment, block, unblock, and comment-only calls through MCP against fake state.
- [ ] Assert exact PATCH bodies and unchanged parent/sprint fields.
- [ ] Test server version rejection, successful server acceptance, invalid input, 403/404, and ambiguous transport failure with no retries.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify update_task workflow`.

## Acceptance scenarios

- [ ] Task state/assignment edits send only selected changes.
- [ ] isBlocked=false reaches the API; omission leaves blocking untouched.
- [ ] Unassignment and empty collections/text preserve intentional clearing semantics.
- [ ] The server result/version is returned without automatic parent changes or write retries.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Users can manage daily task progress through narrow, reliable MCP updates.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline restore passed; baseline test run passed 214 tests. The concurrent baseline build hit a SourceLink output lock, so a serial build rerun is required. Contract payload tests passed. Taiga backend revision `4d11baef9027f5598f6341d6eb4261de2840688e` was checked on 2026-09-28; task model fields, versioned update path, and detail serializer support the scoped PATCH. No deployed-version claim; no live Taiga writes. Goal/reference docs updated with omitted-vs-explicit semantics and planned examples. | Specify update_task contracts / pending |
| 2 | Not started | — | Implement update_task API behavior / pending |
| 3 | Not started | — | Expose update_task MCP interface / pending |
| 4 | Not started | — | Verify update_task workflow / pending |

### Step 1 decisions and planned examples

- `TaskUpdateDto` builds a presence-aware PATCH body. Omitted nullable inputs are absent; `description=""`, `tags=[]`, `is_blocked=false`, and `blocked_note=""` are explicit values.
- `assigned_to` is the only clearable field. `clearFields=["assigned_to"]` emits JSON `null`; supplying an assignee and clearing it together is invalid.
- Changing `is_blocked` never changes `blocked_note`. Callers clear the note explicitly with `blocked_note=""`.
- The version is always included unchanged and updates require at least one selected field or a nonblank comment. No write retry or parent/sprint mutation is planned.

Pinned source evidence used for this contract: [task model at revision 4d11baef9027f5598f6341d6eb4261de2840688e](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/models.py), [task viewset](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/api.py), and [task serializers](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/tasks/serializers.py), verified 2026-09-28. These are upstream source references, not deployment evidence.

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
