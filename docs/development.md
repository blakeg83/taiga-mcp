# Developer guide

## Project layout

The solution contains one `net8.0` executable at the repository root and one
xUnit project in `tests/TaigaMCP.Tests`. The server currently exposes 44 tools;
see the [tool reference](taiga_tools_reference.md#current-tool-contracts) for
signatures and the [command inventory](taiga_command_inventory.md) for
proposed extensions. The bundled `.agents/skills/` workflows are optional
instructions for Codex and have no runtime dependency in the server.

## MCP transport selection

`Program.cs` selects the server transport from the `Mcp` configuration section.
`stdio` is the default and preserves the existing Codex launch behavior. Set
`MCP__TRANSPORT=http` to use the SDK's Streamable HTTP transport. The default
listener is `http://127.0.0.1:3001/mcp`; `MCP__ADDRESS`, `MCP__PORT`, and
`MCP__PATH` configure the HTTP listener address, port, and endpoint path. The
loopback default is intentionally narrow. Taiga credentials remain in the
server process, and the shared Taiga services and tool registrations are used
by both transports.

The referenced `ModelContextProtocol` 0.3.0-preview.4 package supplies the
existing STDIO/stream hosting APIs. Its same-version
`ModelContextProtocol.AspNetCore` companion supplies `WithHttpTransport()` and
`MapMcp()` for Streamable HTTP on net8.0; the base SDK version remains
unchanged. The companion also adds the `Microsoft.AspNetCore.App` 8 shared
framework reference, including for STDIO launches and tests.

### Secure MCP Tunnel compatibility and access record (checked 2026-10-26)

The official [Secure MCP Tunnel guide](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)
states that a private MCP server can remain non-public: `tunnel-client` runs
inside the private network, opens outbound HTTPS to OpenAI, and must also reach
the configured private MCP server locally. It documents `api.openai.com:443`
over HTTPS by default (or `mtls.api.openai.com:443` when control-plane mTLS is
configured). For an HTTP MCP server, use
`--mcp-server-url http://private-host:3001/mcp` in place of
`--mcp-command`; the tunnel identity and private URL remain deployment inputs.

The prerequisite verification for story #271 exercised this shape with a
loopback-only TaigaMCP HTTP listener and tunnel-client v0.0.18. The verified
run used `127.0.0.1:61060` for MCP and a loopback tunnel admin listener on
`127.0.0.1:8081`; both `/healthz` and `/readyz` returned 200. The profile used
an environment-only `CONTROL_PLANE_API_KEY` reference and a loopback
`--mcp-server-url`; no Taiga credentials or key values were stored in the
profile or documentation. The client reported healthy/readiness state and
successful control-plane polling.

The official [MCP server deployment guide](https://developers.openai.com/plugins/build/mcp-server)
requires Streamable HTTP at a stable URL, typically ending in `/mcp`, for a
public plugin endpoint and explicitly distinguishes Secure MCP Tunnel as the
private-server path. The official [connect and test guide](https://developers.openai.com/plugins/deploy/connect-chatgpt)
states that a tunnel may reach a configured stdio or HTTP MCP server and that
the tunnel client must remain running for discovery and tool calls; it also
calls out workspace/tunnel access and authentication checks.

Runtime evidence recorded for #271 included discovery of all 44 Taiga tools,
real read-only `get_current_user` and `list_projects` calls, and a user-attested
ChatGPT Web comment write that followed an explicit confirmation prompt. The
write was not repeated by this story and its target is intentionally omitted
from repository documentation. The evidence verifies the integration shape;
it does not grant permission for future live writes or replace the operator's
workspace, tunnel, firewall, and account checks.

## Architecture and lifetimes

Tools inject concrete domain APIs. `ToolErrors` converts safe failures and
`ToolResponseJson` controls public JSON serialization. Domain APIs own requests
and returned `JsonDocument` instances; `TaigaTransport` owns response/stream
disposal, bounded safe errors, and JSON reads. The transport obtains and
disposes a named factory client per operation, allowing pooled handlers to
rotate. Do not retain a factory-created client in singleton state.

`AuthClient` holds in-memory bearer/refresh token state behind an async gate.
Concurrent initial logins and refreshes coalesce. Only a received 401 permits
one authenticated replay; rejected or malformed refresh responses fall back to
login. Bearer headers are attached per request, never mutated on a shared
client. Network failures and entity version conflicts do not replay writes. A
successful write followed by a response/mapping failure can already have
applied; preserve that uncertainty in the error.

The singleton metadata cache uses per-kind/project keys, frozen snapshots,
injected `TimeProvider`, per-key load coalescing, and TTL/idle eviction. The
default TTL is 300 seconds, and the idle-entry cap is 256. Cancellation flows
from an injected MCP `CancellationToken` through every asynchronous layer; it
must not appear as a user-facing tool argument.

Stdout is reserved for MCP JSON-RPC messages. Logging belongs on stderr; never
add startup banners or `Console.WriteLine` diagnostics. The integration suite
validates raw stdout and includes a deliberately contaminated launcher to check
that non-protocol output is rejected.

The current console provider's stderr threshold is Information. Keep that
minimum level during stdio use: enabling Debug/Trace can emit lower-level
messages on stdout. Supporting verbose protocol-safe diagnostics would require
changing the console routing and verifying the raw protocol stream.

## Project responsibilities

| Location | Responsibility |
| --- | --- |
| `Program.cs` | Select and host STDIO or Streamable HTTP |
| `Hosting/ServiceCollectionExtensions.cs` | Configuration validation, shared DI, named HTTP client, MCP tool discovery |
| `Tools/` | Public tool signatures/descriptions, safe error conversion, response serialization |
| `Api/` | Taiga routes, allowlisted queries, payloads, response mapping, validation, authentication, and transport |
| `Models/` | Explicit snake_case JSON DTO properties |
| `Config/` | Taiga connection/cache/attachment options and MCP transport options |
| `Caching/IssueMetadataCache.cs` | Project/resource metadata snapshots, TTL, eviction, and coalesced loads |
| `tests/TaigaMCP.Tests/` | Fake HTTP, contract tests, concurrency tests, and real stdio MCP sessions |
| `scripts/Install-Codex.ps1` | Windows self-contained publishing and local Codex installation |

## Build and test

Run from the repository root. `global.json` selects SDK 10.0.401 with
`latestPatch` roll-forward within its feature band and excludes prereleases.
The application and tests still target .NET 8. Framework-dependent builds,
tests, and launches require both the .NET 8 runtime and the ASP.NET Core 8
shared framework (`Microsoft.AspNetCore.App`); the HTTP companion package is
present even when the selected transport is STDIO. Self-contained publishing
includes the required runtimes and shared frameworks on the target.

The full test suite requires Windows because the deliberate stdout
contamination fixture uses `cmd.exe`. No hosted CI workflow is currently
tracked; local verification is the documented path.

```powershell
dotnet restore
dotnet build -c Debug
dotnet test -c Debug
dotnet build -c Release --no-restore
dotnet test -c Release --no-build --no-restore
```

Tests use synthetic credentials and fake HTTP, including real MCP sessions
against a local fake Taiga listener. They do not need a live Taiga account.
Integration tests launch `TaigaMCP.dll` from the **test output directory**, so
an isolated output build exercises the newly built application.

If a running MCP server locks normal outputs, leave it running and choose a
unique external output directory:

```powershell
dotnet test -c Debug -p:OutputPath=C:\Temp\TaigaMCP-validation-unique\ -p:UseAppHost=false
```

Use a fresh directory name for each independent run. Keep long-running servers
in separate, versioned publish directories; see the
[quickstart](taiga_mcp_quickstart.md#1-publish-the-server). For development
credentials and supported environment settings, see the
[README](../README.md#configuration). Never modify live Taiga data for tests.

## Contract conventions

Read the [tool reference](taiga_tools_reference.md) and the relevant
[attachment contracts](taiga_tools_reference.md#list_work_item_attachments-contract)
before changing public behavior. Preserve existing tool and parameter names,
defaults, response shapes, and supported clearing fields.

- Use positive IDs/pages, nonblank required text, and nonnegative update
  versions. Validate before HTTP. An update must supply a field change,
  explicit supported clear, or nonblank comment; it does not necessarily read
  the existing value to detect whether a supplied value is different.
- Preserve caller-supplied versions. Never automatically fetch a new version
  and retry an edit or retry an ambiguous write.
- Resource DTOs generally omit nulls. Native point-option `value` preserves
  meaningful explicit nulls. Pagination envelopes preserve unknown `total`,
  `next_page`, and `has_more` as explicit nulls.
- Upstream request serialization is separate from response serialization.
  Ordinary omitted/null optional fields stay omitted; supported `clearFields`
  emits explicit JSON null. Empty strings/arrays remain explicit values.
- Request one list page per call using allowlisted, encoded query names.
  Issue/story lists preserve arrays by default and support opt-in page
  envelopes; task/epic lists and most discovery lists always use envelopes.
- Use project- and resource-specific status IDs. Do not infer completion or
  archival from English labels.
- Safe HTTP errors expose status/category and allowlisted rejected field
  names, never raw response bodies. Error reads are bounded to 4096 bytes.
- Attachment operations support `issue`, `user_story`, `task`, and `epic`.
  Upload/download paths belong to the server filesystem and enforce
  `TAIGA__MAXATTACHMENTBYTES` (default 10 MiB). Downloads never overwrite files.

## Making a contribution

Follow [AGENTS.md](../AGENTS.md) and `.editorconfig`: four-space C#, UTF-8,
final newline, file-scoped `TaigaMCP.<Folder>` namespaces, PascalCase types and
methods, camelCase parameters, and `_camelCase` fields. Keep formatting and
implementation changes focused.

Add tools in `Tools/` with snake_case `[McpServerTool]` names and useful
human-readable descriptions. Extend the concrete domain API and DTOs as
needed, forward cancellation, and update the tool reference and inventory when
coverage changes. For attachment behavior, consult the individual
[list](attachment_list_contract.md), [detail](attachment_detail_contract.md),
[upload](attachment_upload_contract.md), [download](attachment_download_contract.md),
[update](attachment_update_contract.md), and [delete](attachment_delete_contract.md)
contracts.

Use the existing fake HTTP fixtures to verify meaningful request/response and
failure behavior. Use controlled barriers and `TimeProvider` for concurrency
and expiry tests rather than timing sleeps. Run relevant checks and the full
build/test cycle above for runtime changes. Do not add generated `bin/`, `obj/`,
`.vs/`, publish output, credentials, or live Taiga payloads to commits.

Use short imperative commit subjects. A contribution description should state
the concrete behavior change, relevant validation, and migration notes.

## Historical context

The [foundation cleanup record](history/foundation-cleanup.md) preserves the
September 2026 implementation diary and its validation evidence. Its old tool
and test totals are historical. Current tool behavior is documented in the
maintained reference; no absent batch-plan files are required to contribute.
