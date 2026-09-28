# Goal 02: update_issue

Status: planned.

## Objective

Make issue assignment, status changes, and content edits reliable, including explicit unassignment and version-related failures.

## Scope and prerequisites

Preserve all existing update fields and add clearFields for assigned_to. Make subject genuinely optional in the MCP schema while retaining required version. Defer due dates, sprint changes, new blocking fields, and project moves.

Prerequisites: [00-foundation](00-foundation.md), [01-list-issues](01-list-issues.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

update_issue(issueId, version, subject?, description?, status?, type?, priority?, severity?, assigned_to?, tags?, comment?, clearFields?). Preserve existing parameter names and issue response shape. Allow clearFields=["assigned_to"] only in this goal.

API mapping: PATCH issues/{issueId}, sending the caller's version and only selected changes.

Illustrative MCP arguments (IDs are placeholders):

```json
{"issueId":81,"version":4,"clearFields":["assigned_to"],"comment":"Returned to triage."}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/occ/mixins.py). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Tools/IssueTools.cs`
- `Api/IssueApi.cs`
- `Models/IssueUpdateDto.cs`
- `Api/ITaigaApi.cs`
- `Api/TaigaApi.cs`
- `tests/TaigaMCP.Tests/IssueUpdateTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Define presence and compatibility cases

- [ ] Add fixtures for assignment omitted, assignment set, and explicit assignment clear; distinguish null omission from a JSON null in the wire body.
- [ ] Specify conflict rules for set-and-clear and unknown clearFields names; reject empty updates unless a nonblank comment is supplied.
- [ ] Plan an overload/reordering that makes subject optional in C# and the MCP schema without breaking facade callers.
- [ ] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [ ] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify update_issue contracts`.

## Step 2: Implement versioned partial updates

- [ ] Replace null-omitting DTO construction for PATCH with a presence-aware payload while keeping create serialization unchanged.
- [ ] Include assigned_to:null only when explicitly cleared; preserve description="", tags=[], and exact caller version.
- [ ] Preserve HTTP status and safe field errors, call success validation consistently, and do not retry rejected or ambiguous writes.
- [ ] Map returned data using the existing issue mapper and preserve IDs added by goal 01.
- [ ] Validate this step: run domain request/response tests for this behavior and Debug build.
- [ ] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement update_issue API behavior`.

## Step 3: Expose compatible tool arguments

- [ ] Ensure MCP lists issueId/version as required and subject as optional; retain snake_case assigned_to and all old argument names.
- [ ] Thread clearFields through IssueApi and any affected facade overloads without widening unrelated APIs.
- [ ] Document a read-current-version then update flow and how callers resolve version rejection.
- [ ] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [ ] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose update_issue MCP interface`.

## Step 4: Verify issue editing end to end

- [ ] Invoke through MCP a status-only update with no subject, an unassignment, tag clearing, and a comment-only update.
- [ ] Assert exact PATCH bodies and no accidental clearing of omitted fields.
- [ ] Cover 400 version errors, 409, ordinary validation errors, 403, 404, malformed success bodies, and a transport failure with exactly one write attempt.
- [ ] Retain regression coverage for get_issue returning visible comments.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify update_issue workflow`.

## Acceptance scenarios

- [ ] Omitted assignee leaves it unchanged; clearFields emits a literal JSON null; conflicting input makes no HTTP request.
- [ ] A status-only MCP call requires no subject argument.
- [ ] The supplied version reaches Taiga unchanged; no server rejection triggers a blind retry.
- [ ] Existing callers and create_issue serialization remain compatible.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Issue edits and unassignment work through MCP with compatible inputs and truthful conflict/error results.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Not started | — | Specify update_issue contracts / pending |
| 2 | Not started | — | Implement update_issue API behavior / pending |
| 3 | Not started | — | Expose update_issue MCP interface / pending |
| 4 | Not started | — | Verify update_issue workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
