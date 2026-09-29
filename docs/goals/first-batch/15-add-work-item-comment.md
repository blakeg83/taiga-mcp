# Goal 15: add_work_item_comment

Status: in progress.

## Objective

Provide one discoverable command for recording decisions and progress on issues, stories, tasks, and epics.

## Scope and prerequisites

Submit a nonblank comment to one item using its current version. Defer history listing/editing/deletion, attachments, and watcher management.

Prerequisites: [02-update-issue](02-update-issue.md), [06-update-user-story](06-update-user-story.md), [10-update-task](10-update-task.md), [12-get-epic](12-get-epic.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

add_work_item_comment(kind, id, version, text), where kind is issue, user_story, task, or epic. Return { kind, id, version, comment_submitted: true } on confirmed success; version is the returned resource version.

API mapping: PATCH issues/{id}, userstories/{id}, tasks/{id}, or epics/{id} with only version and comment.

Illustrative MCP arguments (IDs are placeholders):

```json
{"kind":"task","id":203,"version":3,"text":"Implementation complete; ready for review."}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/history/mixins.py). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Tools/WorkItemCommentTools.cs`
- `Api/IssueApi.cs`
- `Api/UserStoryApi.cs`
- `Api/TaskApi.cs`
- `Api/EpicApi.cs`
- `tests/TaigaMCP.Tests/WorkItemCommentTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Specify comment dispatch and output

- [ ] Define a closed enum/allowlist for kind and ensure it appears clearly in the MCP schema.
- [ ] Validate positive ID, nonnegative version, and nonblank text; preserve original Markdown/mentions after validation.
- [ ] Record per-kind PATCH fixtures and define the returned submission receipt without a fabricated history-entry ID.
- [ ] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [ ] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify add_work_item_comment contracts`.

## Step 2: Implement comment-only writes

- [ ] Reuse domain update paths where they can send only version/comment without forcing unrelated properties; add a narrow epic comment method rather than a public generic epic update tool.
- [ ] Map each kind explicitly to its domain API/route; never concatenate arbitrary kind values into URLs.
- [ ] Use the supplied version, return the actual resulting version, and avoid fetching history after a successful write just to identify the comment.
- [ ] Preserve safe failure details and do not automatically retry comments after any ambiguous response.
- [ ] Validate this step: run domain request/response tests for this behavior and Debug build.
- [ ] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement add_work_item_comment API behavior`.

## Step 3: Expose the shared comment tool

- [ ] Add WorkItemCommentTools with injected domain services and a single snake_case MCP tool name.
- [ ] Document where to get each resource's version, Markdown/mention preservation, and what comment_submitted confirms.
- [ ] Keep update_issue's existing comment parameter compatible and avoid requiring callers to migrate.
- [ ] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [ ] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose add_work_item_comment MCP interface`.

## Step 4: Verify comments across all kinds

- [ ] Invoke through MCP for all four kinds and assert only version/comment are written to the correct endpoint.
- [ ] Test line breaks, Unicode, Markdown and mention text, invalid kind, blank text, invalid IDs/versions, and existing issue comment visibility.
- [ ] Cover version-related 400, 409, permissions, missing items, malformed success, and lost response with one PATCH attempt.
- [ ] Run the batch fake-HTTP workflow from epic/story creation and linking to task/issue updates and comments.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify add_work_item_comment workflow`.

## Acceptance scenarios

- [ ] All four resource kinds accept comment-only writes with correct routing.
- [ ] The result exposes the actual returned version and does not pretend to contain a history-entry ID.
- [ ] Invalid input makes no write request; ambiguous failures never duplicate comments.
- [ ] Existing issue comment behavior is preserved.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Users can record progress on every selected work-item kind through one reliable MCP command.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline restore/build passed; baseline test run had 295 passed and one pre-existing contaminated-copy cleanup failure. Pinned Taiga backend revision `4d11baef9027f5598f6341d6eb4261de2840688e` was reviewed on 2026-09-28. Added the closed `issue`/`user_story`/`task`/`epic` vocabulary and `{ kind, id, version, comment_submitted }` receipt contract; focused contract tests pass. | Specify add_work_item_comment contracts / `1fbcba1` |
| 2 | Complete | Added explicit PATCH methods for all four domain APIs. Each sends only `comment` and the supplied `version`, parses the authoritative returned version, performs no history/read-after-write request, and preserves safe HTTP failures. Focused domain tests pass: 14 tests, including all four routes, Markdown/Unicode preservation, invalid-input no-write checks, and safe version-error propagation without retry. | Implement add_work_item_comment API behavior / `5a3e959` |
| 3 | Complete | Added `WorkItemCommentTools` with the closed enum in the generated schema and explicit per-kind dispatch. MCP schema and a real STDIO `tools/call` test cover all four kinds, required arguments, receipt shape, exact PATCH bodies, and Markdown/Unicode preservation. Public README, reference, quickstart, and inventory now document the delivered command. | Expose add_work_item_comment MCP interface / pending |
| 4 | Not started | — | Verify add_work_item_comment workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
