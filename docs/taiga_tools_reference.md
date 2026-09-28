# Taiga MCP tool reference

This document describes the behavior that is implemented in the current
repository. It is deliberately separate from the larger command inventory:
the inventory contains proposed future coverage, while this page records what
clients can call today and the compatibility constraints that the first batch
will verify.

## Implemented versus planned

The current server exposes 11 tools:

- 2 project tools: `list_projects`, `resolve_project`.
- 8 issue tools: `list_issues`, `get_issue`, `create_issue`, `update_issue`,
  `list_issue_statuses`, `list_issue_severities`, `list_issue_types`, and
  `list_issue_priorities`.
- 1 user-story tool: `list_user_stories`.

The first-batch documents describe 15 additional or expanded functions. The
`list_issues` expansion is delivered; the remaining goal documents describe
planned work until their individual checklists are complete. Epic, task,
richer user-story, and cross-resource commands are not exposed by this server
yet. See the [command inventory](taiga_command_inventory.md) and [first-batch
plan index](goals/first-batch/README.md) for the remaining planned coverage.

All tool methods return a string whose contents are JSON. The examples below
show the JSON contents, not an MCP `content` wrapper.

## Current tool contracts

| Tool | Parameters and defaults | Current result |
| --- | --- | --- |
| `list_projects` | `member` string?, default `null`; `page` integer, default `1` | Array of `{ id, slug, name }` project objects. |
| `resolve_project` | `slug` string, required | `{ "project": 123 }`. |
| `list_issues` | `projectId` integer, required; `page` integer, default `1`; `statusIds`, `assignedTo`, `typeId`, `priorityId`, `severityId`, `tags`, `query`, `includeClosed=false`, `includePageInfo=false` optional | Bare array by default; when `includePageInfo=true`, `{ items, page, total, next_page, has_more }`. Classification IDs accompany labels. |
| `get_issue` | `issueId` integer, required | `{ "issue": <issue>, "comments": <visible comments> }`. |
| `create_issue` | `projectId`, `subject` required; `description`, `status`, `type`, `priority`, `severity`, `assigned_to`, and `tags` optional and default null | One issue object returned by Taiga after mapping metadata IDs to labels. |
| `update_issue` | `issueId` and `version` required; `subject`, `description`, `status`, `type`, `priority`, `severity`, `assigned_to`, `tags`, `comment`, and `clearFields` optional. `clearFields` accepts only `assigned_to`. | One issue object returned by Taiga after the PATCH. |
| `list_issue_statuses` | `projectId` integer, required | Array of `{ id, name, slug, is_closed }`. |
| `list_issue_severities` | `projectId` integer, required | Array of `{ id, name, slug, color }`. |
| `list_issue_types` | `projectId` integer, required | Array of `{ id, name, slug, color }`. |
| `list_issue_priorities` | `projectId` integer, required | Array of `{ id, name, slug, color }`. |
| `list_user_stories` | `projectId` integer, required; `page` integer, default `1` | Array of `{ id, ref, project?, subject, status_id?, status, assigned_to, modified, milestone?, version? }`. The current public signature is still the legacy two-argument form; the expanded filters and optional page envelope are delivered in the next interface step. |

Parameter names are the public names generated from the C# method signatures;
the issue update method intentionally retains the existing `assigned_to`
spelling for compatibility. The MCP SDK schema and runtime binding are
verified by the integration tests added by this foundation goal.

## Representative sanitized JSON

Project and lookup results:

```json
[{"id":123,"slug":"demo","name":"Demo"}]
{"project":123}
```

Issue list/detail results:

```json
[{
  "id":456,
  "ref":7,
  "project":123,
  "subject":"Fix login",
  "status":"Open",
  "status_id":1,
  "severity":"Normal",
  "severity_id":2,
  "type":"Bug",
  "type_id":3,
  "priority":"Normal",
  "priority_id":4,
  "modified":"2026-09-28T12:00:00Z",
  "version":3
}]
```

```json
{
  "items":[{"id":456,"ref":7,"project":123,"subject":"Fix login","status":"Open","status_id":1}],
  "page":1,
  "total":null,
  "next_page":null,
  "has_more":null
}
```

```json
{
  "issue":{"id":456,"ref":7,"project":123,"subject":"Fix login","version":3},
  "comments":[{
    "id":"history-entry",
    "comment":"Reproduced locally",
    "created_at":"2026-09-28T12:01:00Z",
    "user":{"name":"Example User"}
  }]
}
```

User-story and metadata results:

```json
[{"id":789,"ref":12,"subject":"Ship the fix","status":"Ready","assigned_to":42,"modified":"2026-09-28T12:02:00Z"}]
[{"id":1,"name":"Open","slug":"open","is_closed":false}]
[{"id":2,"name":"Bug","slug":"bug","color":"#cc0000"}]
```

## Compatibility notes observed in the current implementation

- List methods request one Taiga page per call. `projectId` and `page` are
  inserted as numeric query values. `member` and project slugs are escaped
  with `Uri.EscapeDataString`; the existing issue and story filters are fixed
  query names assembled by the domain APIs, not arbitrary caller-provided
  query fragments.
- Issue list requests use Taiga's verified `status`, `assigned_to`, `type`,
  `priority`, `severity`, `tags`, and `q` filters. ID and tag collections are
  comma-separated in the wire value and then percent-encoded. The default
  `status__is_closed=false` restriction is omitted when nonempty explicit
  statuses or `includeClosed=true` are selected. Invalid positive-ID/page
  inputs fail before HTTP. The expanded MCP arguments and opt-in page
  envelope are documented here once the tool exposure step is complete.
- Current list methods request one page and return bare arrays. `list_issues`
  additionally supports the opt-in page envelope; missing or malformed
  pagination headers remain explicit `null` values rather than being treated
  as zero totals or a completed result.
- Issue and story labels are derived from project metadata calls. Story list
  results additionally preserve `project` and `status_id`, and expose
  `milestone` and `version` only when the list response supplies them. A
  missing list version is not fabricated as zero.
- The public tool serializers use `JsonIgnoreCondition.WhenWritingNull`, so
  null-valued response properties such as an unassigned issue's `assigned_to`
  are omitted from current tool JSON. This response omission is distinct from
  the page envelope, whose missing pagination values are explicit JSON `null`.
- Nullable create/update fields use separate request policies. Create fields
  still omit nulls so project defaults apply. For `update_issue`, omitted or
  null optional values leave fields unchanged; `description=""` and `tags=[]`
  remain explicit values; and `clearFields=["assigned_to"]` deliberately
  emits JSON `"assigned_to":null` to unassign. Supplying an assignee and
  clearing it in the same call, or naming another clear field, is rejected
  before HTTP.
- `update_issue` requires a nonnegative caller-supplied `version`, sends it
  unchanged in the PATCH body, and does not refresh and retry on a version
  error. An update must select a real field change, an explicit clear, or a
  nonblank comment. Non-success responses retain HTTP status/category and
  allowlisted rejected field names through safe MCP errors. Arbitrary upstream
  text is not echoed; at most 4096 error bytes are read. Writes whose responses
  cannot be mapped report that they may already have applied. Cancellation
  propagates separately.
- The isolated contract suite includes version-related fixtures for both a
  400 field-validation response and a 409 conflict response. These fixtures
  verify propagation of each status; they do not claim that every stale
  version is rejected, because Taiga can accept non-overlapping stale edits.
- Issue history filtering currently omits hidden entries, entries without a
  string comment, and empty comments. The dedicated comment command described
  in the plans is not implemented.
- Authentication is performed against `/auth`, cached in memory per process,
  and attached as `Authorization: Bearer <token>` to Taiga requests. Tests use
  synthetic credentials and a fake `/auth` response; no live credentials are
  required.

## Verified external and package contracts

The following sources were checked on 2026-09-28:

- The [official Taiga REST API documentation](https://docs.taiga.io/api.html)
  documents `x-paginated`, `x-paginated-by`, `x-pagination-count`,
  `x-pagination-current`, `x-pagination-next`, and `x-pagination-prev`, plus
  the `x-disable-pagination` request header. It also documents optimistic
  concurrency through a required version for modifying requests, including the
  possibility that non-overlapping stale changes can be accepted.
- Taiga backend main was pinned for source review at
  [`4d11baef9027f5598f6341d6eb4261de2840688e`](https://github.com/taigaio/taiga-back/tree/4d11baef9027f5598f6341d6eb4261de2840688e),
  the `main` ref observed on the date above. The OCC mixin is at
  [`taiga/projects/occ/mixins.py`](https://github.com/taigaio/taiga-back/blob/4d11baef9027f5598f6341d6eb4261de2840688e/taiga/projects/occ/mixins.py).
- The installed C# MCP package is `ModelContextProtocol`
  `0.3.0-preview.4`. Its local package README/XML metadata provides
  `WithStdioServerTransport`, `WithToolsFromAssembly`,
  `McpClientFactory.CreateAsync`, `StdioClientTransport`, `ListToolsAsync`,
  and `CallToolAsync`. The matching SDK tag was observed at
  [`15f8e89ac3aedb2bb4fa9232f6093f092b2ce956`](https://github.com/modelcontextprotocol/csharp-sdk/tree/15f8e89ac3aedb2bb4fa9232f6093f092b2ce956).

## Foundation baseline

Commands run before adding the test harness on 2026-09-28:

| Command | Result |
| --- | --- |
| `dotnet restore` | Passed; packages were already restored. |
| `dotnet build -c Debug` | Blocked by four pre-existing `TaigaMCP.exe` processes locking `bin/Debug/net8.0/TaigaMCP.exe`; the compiler was not reached for a clean apphost copy. A lock-free build property is used during development validation. |
| `dotnet test` | Passed with no test project/tests discovered. |

The foundation fixture conventions are: fake HTTP at the `HttpMessageHandler`
boundary, a queued/route-based response handler that records each request, a
synthetic auth response, and no live endpoint access. Later goals should add
only fixtures that assert their actual serialized request, response mapping,
pagination, or error behavior.

The reusable fixture lives in `tests/TaigaMCP.Tests/FakeHttpMessageHandler.cs`.
It matches method and path, captures headers/body/query strings, and can return
JSON/text responses, response headers, HTTP failures, or transport exceptions.
`TaigaTestClient` registers a synthetic `/auth` route and creates the real
`AuthClient` with synthetic credentials. The focused command is:

```text
dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug
```

If a local TaigaMCP server process holds the normal output files, use a
temporary output directory without stopping that process:

```text
dotnet test tests/TaigaMCP.Tests/TaigaMCP.Tests.csproj -c Debug -p:OutputPath=C:\Temp\TaigaMCP-validation\ -p:UseAppHost=false
```

The MCP integration fixture launches the built application with
`StdioClientTransport`, points its configured base URL at a local fake HTTP
listener, and uses `McpClientFactory.CreateAsync` with the installed
`0.3.0-preview.4` SDK. It verifies the complete 11-name `tools/list` result,
the required/optional schema entries, a real `list_projects` `tools/call`, and
that a fake HTTP 500 is returned as a tool result with `IsError=true`. The
fixture also tees the child process's raw STDOUT before the SDK sees it and
validates every nonblank line as a JSON-RPC 2.0 request, notification, or
response. A separate negative test rejects blank lines, plain-text logs, and
JSON values that are not MCP messages. The end-to-end contamination test runs
a temporary copied application behind a launcher that writes a plain-text
startup line; the strict fixture fails before the SDK can accept the session.
A separate test-only stream server probes argument binding for explicit
`false`, an empty array, an explicit null, and a missing required integer; the
probe type is compiled only in the test project.

The original foundation validation on 2026-09-28 used the repository root and
an explicit temporary output directory because pre-existing `TaigaMCP.exe`
processes held the default apphost file:

```text
dotnet restore
dotnet build TaigaMCP.sln -c Debug -p:OutputPath=C:\Temp\TaigaMCP-validation-final\ -p:UseAppHost=false --no-restore
dotnet test TaigaMCP.sln -c Debug -p:OutputPath=C:\Temp\TaigaMCP-validation-final\ -p:UseAppHost=false --no-restore
```

Restore passed; the alternate-output solution build passed with 0 warnings and
the solution test run passed all 8 tests. The default commands were also run
and stopped before compilation/test execution when MSBuild could not replace
the locked default apphost. No server process was stopped, and no generated
`bin/`, `obj/`, `.vs/`, credential, or live Taiga payload was added to the
foundation commits.

The corrected review validation reran the root commands after the output lock
was no longer present:

```text
dotnet restore
dotnet build -c Debug
dotnet test
```

All three commands passed; the Debug build had 0 warnings and the solution
test run passed all 13 tests. The focused strict STDIO run also passed its 5
integration tests, including the expected failure of the contaminated
temporary-copy experiment. The nullable issue contract was verified through
the real `IssueTools.GetIssue` path, with `assigned_to` absent from the public
JSON when the upstream value is null.

Cleanup compatibility: production C# types now live in `TaigaMCP.Api`,
`TaigaMCP.Tools`, and other folder namespaces. The unused aggregate facade is
removed; internal consumers use domain APIs. MCP signatures, defaults, JSON
property names and response omission are unchanged at this stage.

## Input validation and configuration

Positive internal IDs and pages >= 1 are required. Slugs and supplied subjects
must be nonblank. Update versions must be >= 0; an update needs a real change
or nonblank comment. Empty description/tag arrays remain valid. These are
intentional validation changes: invalid calls now fail before contacting Taiga.
`update_issue.subject` is optional and nullable; omit it for other edits.
`clearFields=["assigned_to"]` explicitly unassigns the issue, while a missing
or null `assigned_to` leaves it unchanged. The supplied version is always sent
unchanged and version failures are not retried.
Cancellation is injected by MCP and is not a tool argument.

Credentials must be nonblank. `TAIGA__BASEURL` accepts an absolute HTTP/HTTPS URL
without credentials/query/fragment and normalizes a trailing slash.
`TAIGA__METADATATTLSECONDS` is positive, defaults to 300, and controls metadata
refresh. See [development](development.md) for lifetimes and future contracts.

## Intentional list behavior changes

`list_projects` now defaults to `member=null` (no member filter). To retain the
previous account-specific selection, call `list_projects(member="6")`, or send
`{"member":"6"}` over MCP. Explicit member values remain URL-encoded.
Story lists use Taiga's `status__is_closed=false` and
`status__is_archived=false`; English labels such as Done/Archived no longer
exclude open statuses. Issue lists use `status__is_closed=false` only: unsupported
issue archive filtering and redundant status-exclusion requests were removed.
These are behavior corrections, not behavior-preserving refactoring.
