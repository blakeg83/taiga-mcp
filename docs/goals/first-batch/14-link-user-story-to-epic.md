# Goal 14: link_user_story_to_epic

Status: planned.

## Objective

Associate an existing story with an epic without duplicating or moving the story.

## Scope and prerequisites

Create one epic/story relationship with optional order and safe already-linked handling. Permit cross-project links when Taiga permits them. Defer unlinking, reordering existing links, and batch linking.

Prerequisites: [04-get-user-story](04-get-user-story.md), [12-get-epic](12-get-epic.md), [13-create-epic](13-create-epic.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

link_user_story_to_epic(epicId, userStoryId, order?) returns { epic_id, user_story_id, order, created }. If already linked, created=false and the existing order is returned without changing it.

API mapping: GET epics/{epicId}/related_userstories/{userStoryId} for an existing link; POST epics/{epicId}/related_userstories with epic, user_story, and optional order.

Illustrative MCP arguments (IDs are placeholders):

```json
{"epicId":301,"userStoryId":102}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/epics/api.py). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Api/EpicApi.cs`
- `Tools/EpicTools.cs`
- `Models/EpicUserStoryLinkDto.cs`
- `tests/TaigaMCP.Tests/EpicStoryLinkTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Verify relationship endpoint semantics

- [ ] Confirm the nested lookup uses the story ID, not a separate link ID, and that creation needs epic/user_story keys.
- [ ] Record actual success, duplicate, missing-link, and permission response fixtures; do not treat every 400/404 as a duplicate or absent accessible link.
- [ ] Define existing-link behavior: ignore a new order request and report current order; changing order is outside this goal.
- [ ] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [ ] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify link_user_story_to_epic contracts`.

## Step 2: Implement linking and repeat-call behavior

- [ ] Validate positive IDs and verify epic/story access using existing domain readers as needed to disambiguate a missing link.
- [ ] Return an existing relationship unchanged; otherwise POST the relationship once with optional order.
- [ ] Handle a recognized concurrent duplicate by reading the relationship and returning created=false only if that read confirms it; propagate unrelated errors.
- [ ] Let Taiga determine cross-project eligibility; never patch the story's project or remove other epic links.
- [ ] Validate this step: run domain request/response tests for this behavior and Debug build.
- [ ] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement link_user_story_to_epic API behavior`.

## Step 3: Expose relationship creation

- [ ] Add the MCP method with clear existing-story and optional-order descriptions; do not require a story/epic version if the relationship API does not use one.
- [ ] Document a create_epic -> create_user_story -> link sequence and explain repeat-call behavior.
- [ ] Return actual relationship order from the server without inventing a link identifier.
- [ ] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [ ] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose link_user_story_to_epic MCP interface`.

## Step 4: Verify grouping workflows

- [ ] Exercise initial link, repeated link, repeated link with a different requested order, and a confirmed concurrent duplicate.
- [ ] Test allowed cross-project linking, denied access, missing parent/story, unknown validation errors, and transport ambiguity.
- [ ] Assert no story create/update/delete request, no alteration of other links, and no automatic POST retry.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify link_user_story_to_epic workflow`.

## Acceptance scenarios

- [ ] One call associates an existing story and epic using the correct nested route/payload.
- [ ] Repeated calls do not create duplicates or change existing order.
- [ ] Cross-project links are not blocked by a fabricated same-project rule.
- [ ] Failures preserve the story and its other associations.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Agents can organize existing stories under epics with explicit repeat-call and failure semantics.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Not started | — | Specify link_user_story_to_epic contracts / pending |
| 2 | Not started | — | Implement link_user_story_to_epic API behavior / pending |
| 3 | Not started | — | Expose link_user_story_to_epic MCP interface / pending |
| 4 | Not started | — | Verify link_user_story_to_epic workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
