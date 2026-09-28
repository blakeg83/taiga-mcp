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

The first-batch documents describe 15 additional or expanded functions. They
are planned work until their individual goal checklists are complete. Epic,
task, richer user-story, pagination-envelope, and cross-resource commands are
not exposed by this server yet. See the [command inventory](taiga_command_inventory.md)
and [first-batch plan index](goals/first-batch/README.md) for that planned
coverage.

All tool methods return a string whose contents are JSON. The examples below
show the JSON contents, not an MCP `content` wrapper.

## Current tool contracts

| Tool | Parameters and defaults | Current result |
| --- | --- | --- |
| `list_projects` | `member` string?, default `"6"`; `page` integer, default `1` | Array of `{ id, slug, name }` project objects. |
| `resolve_project` | `slug` string, required | `{ "project": 123 }`. |
| `list_issues` | `projectId` integer, required; `page` integer, default `1` | Array of issue summary objects. The current API requests open, non-archived work. |
| `get_issue` | `issueId` integer, required | `{ "issue": <issue>, "comments": <visible comments> }`. |
| `create_issue` | `projectId`, `subject` required; `description`, `status`, `type`, `priority`, `severity`, `assigned_to`, and `tags` optional and default null | One issue object returned by Taiga after mapping metadata IDs to labels. |
| `update_issue` | `issueId`, `subject`, and `version` required by the current method signature; `description`, `status`, `type`, `priority`, `severity`, `assigned_to`, `tags`, and `comment` optional | One issue object returned by Taiga after the PATCH. |
| `list_issue_statuses` | `projectId` integer, required | Array of `{ id, name, slug, is_closed }`. |
| `list_issue_severities` | `projectId` integer, required | Array of `{ id, name, slug, color }`. |
| `list_issue_types` | `projectId` integer, required | Array of `{ id, name, slug, color }`. |
| `list_issue_priorities` | `projectId` integer, required | Array of `{ id, name, slug, color }`. |
| `list_user_stories` | `projectId` integer, required; `page` integer, default `1` | Array of `{ id, ref, subject, status, assigned_to, modified }`. The current API excludes closed and archived stories. |

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
  "severity":"Normal",
  "type":"Bug",
  "priority":"Normal",
  "assigned_to":null,
  "modified":"2026-09-28T12:00:00Z",
  "version":3
}]
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
- The current list methods return bare arrays and do not expose page metadata.
  The first-batch contract proposes an opt-in page envelope while preserving
  the array default; this is planned until the relevant goal implements it.
- Issue and story labels are derived from project metadata calls. The current
  DTOs preserve labels for compatibility and do not expose all source IDs.
- Nullable create/update fields are serialized with `WhenWritingNull`, so an
  omitted or null update value is currently indistinguishable from “leave it
  unchanged.” Explicit clearing is a planned contract change owned by the
  update goals. The current `tags` array is sent when non-null, including an
  empty array.
- `update_issue` sends the caller-supplied `version` in the PATCH body and
  does not refresh and retry on a version error. Non-success responses are
  surfaced as `HttpRequestException` by the current domain API; the current
  update message includes the HTTP status and response body. Future error
  handling must retain safe validation details without exposing credentials or
  unbounded response data.
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
fixture parses the returned text as JSON, which also proves that server logs do
not corrupt STDOUT protocol output. A separate test-only stream server probes
argument binding for explicit `false`, an empty array, an explicit null, and a
missing required integer; the probe type is compiled only in the test project.
