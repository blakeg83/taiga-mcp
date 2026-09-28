# Goal 03: list_user_stories

Status: in progress.

## Objective

Expose usable backlog and sprint lists without hiding work through English status-name assumptions.

## Scope and prerequisites

Extend listing with statusIds, assignedTo, milestoneId, backlogOnly, tags, query, includeClosed, includeArchived, and includePageInfo. Defer ordering controls, estimates, swimlane filters, and epic filters.

Prerequisites: [00-foundation](00-foundation.md), [01-list-issues](01-list-issues.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

list_user_stories(projectId, page=1, statusIds?, assignedTo?, milestoneId?, backlogOnly=false, tags?, query?, includeClosed=false, includeArchived=false, includePageInfo=false). milestoneId and backlogOnly=true are mutually exclusive. Default output remains an array.

API mapping: GET userstories plus project userstory-statuses metadata where necessary; verify the API's null-milestone filter.

Illustrative MCP arguments (IDs are placeholders):

```json
{"projectId":12,"backlogOnly":true,"includeClosed":true,"includeArchived":true,"includePageInfo":true}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/userstories/api.py). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Tools/UserStoryTools.cs`
- `Api/UserStoryApi.cs`
- `Models/UserStoryDto.cs`
- `tests/TaigaMCP.Tests/UserStoryListTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Specify story list cases

- [x] Record current DTO fields and default array behavior before extending them.
- [x] Create status fixtures with localized/custom names and actual is_closed/is_archived flags; ensure names never determine filtering.
- [x] Verify backlog null filtering and define milestone/backlog conflict validation.
- [x] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [x] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify list_user_stories contracts`.

Step 1 decisions and evidence (2026-09-28): the current `UserStoryDto` exposes
`id`, `ref`, `subject`, `status`, `assigned_to`, and `modified`, and the public
tool returns a bare JSON array by default. The baseline fixture uses localized
and custom status names alongside their actual `is_closed` and `is_archived`
flags; filtering is asserted against the wire flags, not names. The pinned
Taiga source revision
[`4d11baef9027f5598f6341d6eb4261de2840688e`](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/userstories/api.py#L69-L75)
allowlists `milestone`, `milestone__isnull`, `status__is_archived`, and
`status__is_closed`. `backlogOnly=true` will therefore map to
`milestone__isnull=true`; supplying both `milestoneId` and `backlogOnly=true`
is invalid before HTTP. No deployed Taiga version was claimed.

Baseline validation passed: `dotnet test -c Debug --no-restore` ran 103 tests.
The new `UserStoryListTests` records the compatible array/default-flag contract
and positive project/page validation without introducing a failing test suite.

## Step 2: Implement filters and page mapping

- [x] Reuse goal 01 query/page helpers and add story-specific options; retain the cleanup's flag-based filtering (Done/Archived string matching is already removed).
- [x] Apply closed/archive restrictions only when not overridden by explicit statuses; omit those restrictions when corresponding include flags are enabled.
- [x] Add project, status_id, milestone, and a nullable version when present to list mapping; do not invent version when the list response omits it.
- [x] Keep existing DTO JSON fields and domain callers compatible.
- [x] Validate this step: run domain request/response tests for this behavior and Debug build.
- [x] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement list_user_stories API behavior`.

Step 2 implementation and validation (2026-09-28): the API now uses the shared
pagination parser from the issue-list prerequisite and one encoded
`userstories` request per call. Nonempty `statusIds` maps to `status` and
suppresses both automatic status-flag restrictions. Otherwise
`includeClosed` controls `status__is_closed=false` and `includeArchived`
controls `status__is_archived=false`. `assignedTo`, `milestoneId`, `tags`, and
`query` map to `assigned_to`, `milestone`, `tags`, and `q`; `backlogOnly` maps
to `milestone__isnull=true`. Invalid IDs and the milestone/backlog conflict
fail before metadata or story HTTP requests.

List mapping retains the existing fields and adds nullable `project`,
`status_id`, `milestone`, and `version`. A missing or nonnumeric upstream
version remains null and is omitted by the public serializer; version zero is
preserved when explicitly returned. Status labels are metadata labels only and
never participate in filtering. Unknown or unsafe pagination continuation
URLs remain unknown through the shared parser. Focused story tests passed 6,
`dotnet build -c Debug --no-restore` passed with 0 warnings/errors, and the
full suite passed 109 tests. Step 1 commit: `7c2d584`.

## Step 3: Wire the public story list

- [x] Expose optional parameters through UserStoryTools with descriptions for backlog selection and status precedence.
- [x] Keep legacy array output and add the opt-in envelope; do not fetch all stories or individual details automatically.
- [x] Document that get_user_story supplies a reliable current version for updates.
- [x] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [x] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [x] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose list_user_stories MCP interface`.

Step 3 interface and validation (2026-09-28): the public signature is
`list_user_stories(projectId, page=1, statusIds?, assignedTo?, milestoneId?,
backlogOnly=false, tags?, query?, includeClosed=false, includeArchived=false,
includePageInfo=false)`. It returns the legacy array unless
`includePageInfo=true`, which returns `{ items, page, total, next_page,
has_more }` with unknown pagination values represented as JSON null. The tool
does not aggregate pages or fetch individual story details. `get_user_story`
will be the authoritative source for a current version before a later update.

The real MCP integration test validates the generated schema, required
`projectId`, optional/default argument binding, an encoded backlog query, and
the page envelope. The previous API commit is `9b82294`.

## Step 4: Verify backlog and sprint workflows

- [ ] Invoke legacy listing and an explicit closed/archived status query through MCP.
- [ ] Cover backlogOnly, a sprint filter, invalid combinations, encoded tags/text, and server-order preservation.
- [ ] Verify custom status names, empty/later pages, unknown headers, missing optional version, and inaccessible projects.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify list_user_stories workflow`.

## Acceptance scenarios

- [ ] Closed and archived stories are accessible on explicit request, independent of translated names.
- [ ] Backlog and sprint queries have unambiguous validated semantics.
- [ ] Legacy output remains compatible; opt-in metadata is accurate.
- [ ] Optional missing list versions are not emitted as usable version zero.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Users can inspect both current and historical backlog/sprint work with predictable filtering and pagination.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Baseline `dotnet test -c Debug --no-restore`: 103 passed. Pinned source revision and status/backlog decisions recorded above; baseline fixtures added. | Specify list_user_stories contracts / completed locally |
| 2 | Complete | Focused story tests: 6 passed. `dotnet build -c Debug --no-restore`: passed with 0 warnings/errors. Full Debug suite: 109 passed. Wire behavior and nullable mapping documented above; previous step `7c2d584`. | Implement list_user_stories API behavior / completed locally |
| 3 | Complete | MCP `tools/list` schema and real STDIO `tools/call` validation pass, including optional filters, `backlogOnly`, encoded values, and the opt-in envelope. Previous step `9b82294`. | Expose list_user_stories MCP interface / completed locally |
| 4 | Not started | — | Verify list_user_stories workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
