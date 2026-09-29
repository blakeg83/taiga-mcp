# Goal 03: resolve_work_item

Status: planned; not implemented by this document.

## Objective

Translate a human-facing project #ref into the correct internal issue, story, task, or epic ID.

## Scope and prerequisites

Resolve one known kind/reference in a numeric project. Return identity and available subject/version, not full resource details. Defer slug/URL parsing, kind guessing, cross-project search, and history reads.

Prerequisites: the implemented first-batch baseline; no new function dependency.
Read [execution instructions](execution-instructions.md), [contracts](contracts.md),
[AGENTS.md](../../../AGENTS.md), and the [current tool reference](../../taiga_tools_reference.md).
Execute only assigned scope. Reuse current domain APIs, transport, and test fixtures.

## Target contract

- Signature: `resolve_work_item(projectId, kind, ref)`.
- Result: { kind, id, ref, project, subject?, version? }. The response ref/project must agree with the requested values; callers use an existing get_* tool for full detail before editing.
- API operation: GET {issues|userstories|tasks|epics}/by_ref?project={projectId}&ref={ref}.
- Source evidence: the Reference lookup rows in [pinned sources](sources.md).
  Record revision/version and any verified deviations before implementation.

Illustrative MCP arguments (synthetic IDs):

```json
{
  "projectId": 12,
  "kind": "task",
  "ref": 42
}
```

## Files and integration points

- `Api/WorkItemResolverApi.cs`
- `Tools/WorkItemResolverTools.cs`
- `Models/ResolvedWorkItemDto.cs`
- `Models/WorkItemComment.cs (reuse WorkItemKind)`
- `Hosting/ServiceCollectionExtensions.cs`
- `tests/TaigaMCP.Tests/WorkItemResolverTests.cs`
- `tests/TaigaMCP.Tests/McpIntegrationTests.cs`, `FakeTaigaHttpServer.cs`, and existing protocol fixtures for actual calls/discovery.
- `docs/taiga_tools_reference.md`, `README.md`, `docs/taiga_mcp_quickstart.md`, `docs/taiga_command_inventory.md`, and this batch's index for delivered scope.

New filenames are proposed. Reuse equivalent existing files; avoid unrelated
refactors, package changes, or new generic frameworks. Tools stay thin and use
ToolErrors/ToolResponseJson; concrete APIs use TaigaTransport with cancellation.

## Step 1: Specify four-kind lookup

- [ ] Verify ByRefMixin and each resource's route; reuse WorkItemKind with a closed mapping.
- [ ] Validate positive project/ref and defined kind; specify numeric ref only, with no leading # in the public argument.
- [ ] Add four response fixtures and cases for mismatched project/ref; do not treat a supplied ref as an internal ID.
- [ ] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [ ] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify resolve_work_item contracts`.

## Step 2: Implement reference resolution

- [ ] Add a concrete resolver API over TaigaTransport and reconstruct relative routes from the allowlist.
- [ ] Map a small identity DTO; require positive id/project/ref and enforce request/response agreement without inventing missing identity.
- [ ] Register the API and propagate cancellation; do not scan paged lists or fetch comments/details automatically.
- [ ] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [ ] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement resolve_work_item API behavior`.

## Step 3: Expose project reference lookup

- [ ] Add the tool with public argument name ref (use C# @ref if needed); validate the emitted MCP schema uses ref.
- [ ] Document same ref values across different projects and kinds, and the resolve -> get -> update sequence.
- [ ] Keep resolve_project behavior unchanged and add discovery/actual-call tests for all enum values.
- [ ] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [ ] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose resolve_work_item MCP tool`.

## Step 4: Verify references before edits

- [ ] Resolve a synthetic task #42 whose internal ID is 203, read get_task(203), and update using its returned version.
- [ ] Test all four kinds, same ref in different projects, wrong kind, missing ref, mismatched response identity, and permissions.
- [ ] Assert invalid kinds/IDs cause no HTTP and that 404 is a lookup failure, not a fallback to another kind or project.
- [ ] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [ ] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [ ] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify resolve_work_item workflows`.

## Acceptance scenarios

- [ ] All four supported kinds resolve through their by_ref endpoint.
- [ ] Displayed reference and internal ID remain distinct through a subsequent detail/edit flow.
- [ ] Invalid/mismatched identities fail instead of addressing an unintended item.
- [ ] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [ ] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [ ] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [ ] Agents can reliably open a project-local #ref without manual internal-ID lookup.
- [ ] All four ordered steps and acceptance scenarios have passing recorded validation.
- [ ] Schema inspection and real MCP calls agree with the documented interface.
- [ ] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [ ] Current documentation names only delivered functionality and preserves deferred scope.
- [ ] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [ ] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: pending. Source/deployment evidence: pending; do not claim a live
deployment version from upstream source alone.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Not started | — | Specify resolve_work_item contracts / pending |
| 2 | Not started | — | Implement resolve_work_item API behavior / pending |
| 3 | Not started | — | Expose resolve_work_item MCP tool / pending |
| 4 | Not started | — | Verify resolve_work_item workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
