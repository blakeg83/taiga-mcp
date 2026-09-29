# Goal 03: resolve_work_item

Status: Step 4 complete; resolve_work_item is delivered.

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

## Step 1 contract evidence

The pinned source revision is `4d11baef9027f5598f6341d6eb4261de2840688e`,
reviewed 2026-09-29. `ByRefMixin.by_ref` requires a numeric `ref` query value
and either `project` or `project__slug`, then delegates to the resource's
permission-aware retrieve action. The four supported resource routes are
`issues`, `userstories`, `tasks`, and `epics`; all four viewsets include the
mixin. This implementation selects only the numeric `project` form and does
not parse slugs, URLs, or a leading `#`.

The contract layer now closes `WorkItemKind` to the four enum values and maps
those values to the four routes. A response must be an object with positive
`id`, `ref`, and `project`; its `ref` and `project` must equal the requested
values. `subject` and nonnegative `version` are optional and are preserved only
when present with the expected type. A displayed ref is kept separate from the
returned internal ID; for example, synthetic task ref `42` resolves to ID
`405`. The four source-shaped fixtures and project/ref mismatch cases are
covered without making an HTTP request. The response kind is supplied by the
closed request kind because Taiga's by-ref payload has no kind discriminator.

## Step 2 implementation evidence

`WorkItemResolverApi.ResolveAsync` validates positive `projectId` and `ref`,
selects the allowlisted relative route, and sends exactly one GET request with
`project` followed by `ref`. It owns the request and delegates response
disposal to `TaigaTransport`; the returned DTO is an owned immutable identity
receipt. No list scan, detail read, comment read, slug lookup, or write is
performed. The API is registered in dependency injection, but remains
unreachable from MCP until Step 3.

## Step 3 implementation evidence

The `resolve_work_item` MCP tool is now callable with the exact public
signature `resolve_work_item(projectId, kind, ref)`. The C# `@ref` parameter
emits the required schema property name `ref`; `cancellationToken` is not
public. The tool returns the resolver's JSON identity receipt and leaves the
existing `resolve_project` behavior unchanged. Documentation now distinguishes
the displayed ref from the internal ID and records the resolve -> get -> update
workflow. The real stdio MCP fixture discovers the new tool and calls all four
enum values against fake HTTP routes.

## Step 4 verification evidence

The final fake-HTTP and real-stdio coverage resolves all four kinds, preserves
the same ref independently in projects 12 and 99, and exercises a synthetic
task ref `42` resolving to internal ID `203` before `get_task` and a versioned
`update_task`. Invalid project/ref/kind inputs make no resolver HTTP request;
an unknown project returns a safe 404 lookup error, mismatched response
identity is rejected, and a 403 remains a safe permission error. The resolver
also replays only a received 401 through the existing authentication path.

Final required validation passed with `dotnet restore`, Debug build/test,
Release build/test, and `git diff --check`. Debug and Release test runs each
reported 381 passed and 0 failed. The Debug and Release assemblies were built
in `bin/Debug/net8.0` and `bin/Release/net8.0`; no generated output is tracked.

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

- [x] Verify ByRefMixin and each resource's route; reuse WorkItemKind with a closed mapping.
- [x] Validate positive project/ref and defined kind; specify numeric ref only, with no leading # in the public argument.
- [x] Add four response fixtures and cases for mismatched project/ref; do not treat a supplied ref as an internal ID.
- [x] Validate this step: record baseline/focused checks, confirm fixture JSON and source facts, and keep the existing suite runnable without future-behavior failures.
- [x] Update documentation during this step: record verified contract decisions/source revision and planned examples in this goal. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Specify resolve_work_item contracts`.

## Step 2: Implement reference resolution

- [x] Add a concrete resolver API over TaigaTransport and reconstruct relative routes from the allowlist.
- [x] Map a small identity DTO; require positive id/project/ref and enforce request/response agreement without inventing missing identity.
- [x] Register the API and propagate cancellation; do not scan paged lists or fetch comments/details automatically.
- [x] Validate this step: run focused API/request/response/error tests and a Debug build; include cancellation and ownership checks appropriate to the change.
- [x] Update documentation during this step: record implemented API semantics, source deviations, and test evidence; keep the public function labeled planned until exposed. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Implement resolve_work_item API behavior`.

## Step 3: Expose project reference lookup

- [x] Add the tool with public argument name ref (use C# @ref if needed); validate the emitted MCP schema uses ref.
- [x] Document same ref values across different projects and kinds, and the resolve -> get -> update sequence.
- [x] Keep resolve_project behavior unchanged and add discovery/actual-call tests for all enum values.
- [x] Validate this step: run real MCP tools/list and tools/call checks for this function, including required/default/null arguments and safe errors.
- [x] Update documentation during this step: publish the callable signature, response/default/error examples, update tool counts and inventory delivered scope, and add a quickstart workflow. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Expose resolve_work_item MCP tool`.

## Step 4: Verify references before edits

- [x] Resolve a synthetic task #42 whose internal ID is 203, read get_task(203), and update using its returned version.
- [x] Test all four kinds, same ref in different projects, wrong kind, missing ref, mismatched response identity, and permissions.
- [x] Assert invalid kinds/IDs cause no HTTP and that 404 is a lookup failure, not a fallback to another kind or project.
- [x] Validate this step: run the complete Debug and Release restore/build/test sequence plus git diff --check from execution-instructions.md; record exact results and output paths.
- [x] Update documentation during this step: reconcile the reference/README/quickstart/inventory and this batch index with final delivered scope; verify links and examples. Update this goal's checkboxes and execution record.
- [x] **Commit this completed step before starting the next**, including code, tests, and documentation. Suggested subject: `Verify resolve_work_item workflows`.

## Acceptance scenarios

- [x] All four supported kinds resolve through their by_ref endpoint.
- [x] Displayed reference and internal ID remain distinct through a subsequent detail/edit flow.
- [x] Invalid/mismatched identities fail instead of addressing an unintended item.
- [x] Public invocation returns documented JSON text on success and a safe MCP error on failure; cancellationToken is not a public argument.
- [x] Authentication replay occurs only under the existing received-401 rule; failures never cause an unrequested write or automatic entity-version refresh.
- [x] Existing resource null omission, explicit clearFields behavior, and unknown pagination metadata remain compatible.

## Definition of done

- [x] Agents can reliably open a project-local #ref without manual internal-ID lookup.
- [x] All four ordered steps and acceptance scenarios have passing recorded validation.
- [x] Schema inspection and real MCP calls agree with the documented interface.
- [x] Relevant malformed-data, permission, cancellation, pagination/concurrency, and transport cases are covered by meaningful tests.
- [x] Current documentation names only delivered functionality and preserves deferred scope.
- [x] Debug and Release build/test checks pass; generated artifacts, credentials, and unrelated changes are excluded.
- [x] Each completed step has a separate local commit; the handoff lists its hash and evidence.

## Execution record

Starting commit: `f26b534` (`master`, 2026-09-29). Source/deployment evidence:
pinned Taiga backend revision `4d11baef9027f5598f6341d6eb4261de2840688e`; this is
source evidence only and not a live deployment claim. The initial root
`dotnet test -c Debug --no-restore` run built successfully and reported 350
passed plus one pre-existing/environmental failure in the temporary-copy
stdout-contamination test while deleting a locked
`Microsoft.Extensions.Configuration.Abstractions.dll`.

| Step | Status | Validation and documentation evidence | Commit subject / hash |
| --- | --- | --- | --- |
| 1 | Complete | Contract tests passed; the full baseline retained the temporary-copy cleanup lock failure described above. | Specify resolve_work_item contracts / `a1283a5` |
| 2 | Complete | Focused resolver contract/API suite: 26 passed; Debug compilation passed; `git diff --check` passed. | Implement resolve_work_item API behavior / `c60f8a9` |
| 3 | Complete | Real stdio discovery/schema and four actual MCP calls passed in the integration fixture; docs/inventory updated. | Expose resolve_work_item MCP tool / `847f970` |
| 4 | Complete | Restore, Debug/Release builds and tests, focused 29-test resolver suite, resolve→get→update flow, and `git diff --check` all passed. | Verify resolve_work_item workflows / pending |

Record baseline failures, evidence-backed contract changes, previous step hashes,
exact commands/results, and remaining blockers as work proceeds. Leave unverified
boxes unchecked; a checkpoint commit is not a completed step.
