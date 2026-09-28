# Goal 11: list_epics

Status: planned.

## Objective

Make larger work groups discoverable by project, assignment, status, and text.

## Scope and prerequisites

Establish EpicApi/EpicTools and listing with statusIds, assignedTo, tags, query, includeClosed, and page. Defer progress aggregation, ordering changes, and all-page fetching.

Prerequisites: [00-foundation](00-foundation.md), [03-list-user-stories](03-list-user-stories.md). Read and follow [execution instructions](execution-instructions.md) and [shared contracts](contracts.md). Reuse prerequisite helpers and fixtures; do not implement unrelated inventory entries.

## Target interface and behavior

list_epics(projectId, page=1, statusIds?, assignedTo?, tags?, query?, includeClosed=false) returns the standard page envelope.

API mapping: GET epics with verified epic filters; use project epic-statuses metadata if needed for closed-state filtering.

Illustrative MCP arguments (IDs are placeholders):

```json
{"projectId":12,"includeClosed":true,"page":1}
```

Primary verification source: [Taiga source/API](https://github.com/taigaio/taiga-back/blob/main/taiga/projects/epics/api.py). Before implementing, record a pinned upstream revision or deployed-version evidence; a floating main branch is not a deployment guarantee.

## Files and integration points

- `Api/EpicApi.cs`
- `Tools/EpicTools.cs`
- `Models/EpicDto.cs`
- `Hosting/ServiceCollectionExtensions.cs`
- `tests/TaigaMCP.Tests/EpicListTests.cs`
- `docs/taiga_tools_reference.md`, `README.md`, and `docs/taiga_mcp_quickstart.md` for implemented behavior and examples.
- This goal and `docs/taiga_command_inventory.md` for progress, evidence, and remaining scope.

New filenames are proposed and may be consolidated with equivalent prerequisite files. Preserve the repository's concrete domain API/DI pattern and existing public tools.

## Step 1: Verify epic-specific list contracts

- [ ] Confirm supported query parameters in epic filters; do not assume every issue/task filter applies.
- [ ] Define list fields id/ref/project/subject/status_id/status/assigned_to/color/tags/modified and optional version.
- [ ] If closure requires metadata, resolve closed status IDs once per request/project and apply supported filtering; never infer closure from names.
- [ ] Validate this step: run baseline/focused contract checks; validate fixture JSON and record intended new cases without committing a failing suite.
- [ ] Update documentation now: record verified contract/source decisions and planned reference examples. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Specify list_epics contracts`.

## Step 2: Implement EpicApi and registration

- [ ] Create the authenticated domain API and register it with the existing named HttpClient and AuthClient.
- [ ] Reuse query/page logic and preserve numeric status IDs, color, tags, and nullable assignment.
- [ ] Keep one-page behavior and avoid related-story/detail lookups for every epic.
- [ ] Validate this step: run domain request/response tests for this behavior and Debug build.
- [ ] Update documentation now: document implemented wire behavior, validation/errors, and any deviations. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Implement list_epics API behavior`.

## Step 3: Expose epic discovery

- [ ] Add EpicTools and the list_epics MCP method with descriptions and correct optional defaults.
- [ ] Return the envelope and expose missing totals/next-page state as unknown.
- [ ] Document how a returned epic ID is used for get_epic and later story linking.
- [ ] Validate this step: run MCP tools/list and actual tools/call tests for this function, including required/optional argument binding.
- [ ] Update documentation now: publish the actual tool signature, defaults, response example, and caller workflow. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Expose list_epics MCP interface`.

## Step 4: Verify epic listing

- [ ] Test DI resolution and MCP discovery/invocation alongside all existing tools.
- [ ] Cover custom closed statuses, explicit statuses overriding the default, Unicode/tag encoding, pagination headers, and empty lists.
- [ ] Test a project with epics disabled or access denied without turning server errors into an empty success list.
- [ ] Validate this step: run root dotnet restore, dotnet build -c Debug, and dotnet test; verify the acceptance cases below.
- [ ] Update documentation now: finalize README/reference/quickstart examples and inventory coverage notes; keep deferred features explicitly planned. Update this goal's checklist and execution record with results.
- [ ] **Commit this step before starting the next one** with code, tests, and documentation together. Suggested subject: `Verify list_epics workflow`.

## Acceptance scenarios

- [ ] Epic tools are discovered through assembly scanning and DI resolves their dependencies.
- [ ] Open/closed filtering uses real project metadata or verified query flags.
- [ ] Returned IDs and pagination are sufficient for detail lookup.
- [ ] Listing does not calculate misleading progress from a partial related-story set.
- [ ] The tool's MCP result is valid JSON text on success and a recognizable failure on error; no credentials leak to output.
- [ ] Existing tools continue to pass the compatibility checks introduced in goal 00.

## Definition of done

- [ ] Users can find epics with predictable project-scoped filters and pagination.
- [ ] All four implementation steps and acceptance scenarios are complete with passing recorded validation.
- [ ] The emitted MCP schema and actual invocation agree with the documented interface.
- [ ] Failure/edge tests prove the goal-specific behavior, not merely that methods return non-null values.
- [ ] Documentation describes delivered scope, examples, compatibility decisions, and deferred inventory functionality.
- [ ] A separate local Git commit exists for every completed step; the final handoff lists all four hashes.
- [ ] Root solution build/tests pass; generated artifacts and unrelated changes are excluded from commits.

## Execution record

| Step | Status | Validation evidence and documentation updated | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Not started | — | Specify list_epics contracts / pending |
| 2 | Not started | — | Implement list_epics API behavior / pending |
| 3 | Not started | — | Expose list_epics MCP interface / pending |
| 4 | Not started | — | Verify list_epics workflow / pending |

Record baseline failures, source revision/date, approved contract changes, remaining blockers, and mock-versus-live verification here. Do not mark a step done on the strength of an unrun check.
