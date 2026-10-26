# Taiga MCP quickstart

This guide connects a local TaigaMCP stdio server to Codex by default. Other
MCP clients can use the same executable and environment variables, including
the configurable Streamable HTTP transport and a private OpenAI Secure MCP Tunnel
connection for ChatGPT Web. See the
[README](../README.md#requirements) for build/runtime requirements and the
[configuration table](../README.md#configuration) for all settings.

Framework-dependent launches and tests require both the .NET 8 runtime and the
ASP.NET Core 8 shared framework (`Microsoft.AspNetCore.App`), including for
STDIO because the HTTP companion package is part of the application.
Self-contained publishing includes both frameworks on the target.

## Windows installer

From the repository root, with PowerShell 7.3+, the SDK selected by
`global.json`, and Codex CLI on `PATH`:

```powershell
pwsh -File .\scripts\Install-Codex.ps1
```

This publishes the current checkout, registers `taiga`, and installs both
bundled skills. Existing credentials are reused; first setup prompts when
credentials are absent from the process environment. For self-hosted Taiga,
set `TAIGA__BASEURL` before first setup. Restart Codex and open a new chat.

Read the [installer notes](../README.md#windows-install-into-codex) for saved
credentials, backups, install paths, and the server settings reset during
registration. You can then skip to **Verify the connection** below.

## Manual setup

### 1. Publish the server

Clone the repository and run these commands from its root. Publish to a
versioned directory separate from development build outputs.

Windows x64, PowerShell:

```powershell
dotnet restore
dotnet publish .\TaigaMCP.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o C:\Tools\TaigaMCP\v1
```

Use `win-arm64` for Windows ARM64. The executable in this example is
`C:\Tools\TaigaMCP\v1\TaigaMCP.exe`.

Linux x64 / WSL, Bash:

```bash
dotnet restore
dotnet publish ./TaigaMCP.csproj -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true -o "$HOME/.local/share/TaigaMCP/v1"
```

Use `linux-arm64` for Linux ARM64. The executable in this example is
`~/.local/share/TaigaMCP/v1/TaigaMCP`. Other .NET-supported platforms need the
appropriate runtime identifier; this guide does not claim they were tested.

Self-contained publishing includes the runtime. It avoids building at MCP
startup; it does **not** eliminate .NET JIT compilation. The SDK pin does not
change the application's `net8.0` target or its package versions.

### STDIO / Codex (default)

STDIO is the default transport and preserves the existing Codex launch
behavior. No `MCP__*` variables are required. For a direct local smoke test,
set only the Taiga credentials in the server process and launch the published
executable; it waits for MCP JSON-RPC messages on stdin and writes protocol
messages to stdout:

```powershell
$env:TAIGA__USERNAME = 'your-user'
$env:TAIGA__PASSWORD = 'enter-locally-with-a-secret-store'
$env:TAIGA__BASEURL = 'https://api.taiga.io/api/v1/'
$env:MCP__TRANSPORT = 'stdio'
& C:\Tools\TaigaMCP\v1\TaigaMCP.exe
```

For Codex, use the same executable and server-process environment in the
[configuration example](#2-configure-codex) below. Do not add HTTP listener
settings to a STDIO registration; the default listener address, port, and path
apply only when `MCP__TRANSPORT=http`.

### Streamable HTTP mode

STDIO remains the default for Codex. To select Streamable HTTP on a private
loopback listener, configure the server process before starting it:

```powershell
$env:MCP__TRANSPORT = 'http'
$env:MCP__ADDRESS = '127.0.0.1'
$env:MCP__PORT = '3001'
$env:MCP__PATH = '/mcp'
dotnet run --no-build
```

The endpoint is then `http://127.0.0.1:3001/mcp`; address, port, and path are
validated at startup. For STDIO, omit the `MCP__*` variables (or set
`MCP__TRANSPORT=stdio`); no HTTP listener is started.

### Secure MCP Tunnel and ChatGPT Web

Use this path when ChatGPT must reach TaigaMCP without making Taiga or the MCP
listener public. Run `tunnel-client` in the same private trust boundary as the
MCP server. It needs outbound HTTPS to the OpenAI control plane and local
reachability to the configured MCP URL; it does not need inbound Internet
access. The tunnel identity, workspace association, and runtime key are
deployment inputs and are intentionally not included here.

Prerequisites:

- A current `tunnel-client` binary from the OpenAI Platform tunnel settings or
  the latest public release.
- A tunnel ID associated with the target ChatGPT workspace and an account with
  the required tunnel permissions. The ChatGPT operator needs tunnel use
  access; creating or editing a tunnel may require additional organization
  permissions.
- .NET 8 plus ASP.NET Core 8 when running a framework-dependent server, or a
  self-contained publish as described above.
- Taiga credentials available only to the TaigaMCP server process. Do not put
  `TAIGA__USERNAME`, `TAIGA__PASSWORD`, or a Taiga bearer token in ChatGPT,
  tunnel arguments, screenshots, or committed configuration.

Start the HTTP server in one terminal. This example uses the documented
loopback defaults; use a private interface address only when the tunnel client
runs on another host that cannot reach loopback:

```powershell
$env:TAIGA__USERNAME = 'your-user'
$env:TAIGA__PASSWORD = 'enter-locally-with-a-secret-store'
$env:TAIGA__BASEURL = 'https://api.taiga.io/api/v1/'
$env:MCP__TRANSPORT = 'http'
$env:MCP__ADDRESS = '127.0.0.1'
$env:MCP__PORT = '3001'
$env:MCP__PATH = '/mcp'
& C:\Tools\TaigaMCP\v1\TaigaMCP.exe
```

In a second terminal, enter the control-plane key locally and initialize a
named profile. The `sample_mcp_remote_no_auth` sample is the verified
no-client-auth shape for a TaigaMCP server whose Taiga credentials stay
server-side:

```powershell
$env:CONTROL_PLANE_API_KEY = '<enter-the-runtime-key-locally>'
tunnel-client init `
  --sample sample_mcp_remote_no_auth `
  --profile taiga-mcp `
  --tunnel-id '<tunnel_id_from_platform_settings>' `
  --mcp-server-url 'http://127.0.0.1:3001/mcp'
tunnel-client doctor --profile taiga-mcp --explain
tunnel-client run --profile taiga-mcp
```

Keep `tunnel-client run` and TaigaMCP running during discovery and tool calls.
Use the client's local `doctor` result and loopback health/readiness endpoints
to confirm that the private process is ready before testing ChatGPT. Do not
publish the admin endpoints. The official [Secure MCP Tunnel guide]
documents the `--mcp-server-url` form, outbound-only networking, profile
setup, and current client download location.

In ChatGPT Web, open Plugins, choose **Add custom MCP server**, select
**Connection: Tunnel**, and select or enter the same tunnel ID. For this
repository's no-client-auth setup, select the no-auth option for the MCP
endpoint; tunnel access and the server's private Taiga credentials are separate
boundaries. Accept the risk warning and create the plugin. Then exercise the
path in this order:

1. Call `get_current_user` and confirm a real, positive account ID without
   exposing password or token fields.
2. Call `list_projects` with `page=1` as a read-only discovery check.
3. For a write demonstration, select a disposable target, state the intended
   change, approve ChatGPT's confirmation prompt explicitly, and record the
   result. Do not perform a live write merely to test connectivity, and do not
   promise cleanup unless it is separately authorized.

The prerequisite verification for this repository reached 44 Taiga tools,
completed real read-only identity/project calls, and recorded a user-approved
controlled comment write. The sanitized run used a TaigaMCP listener on
`127.0.0.1:61060`, a loopback tunnel admin listener on `127.0.0.1:8081`, and
HTTP health/readiness responses of 200. It used tunnel-client v0.0.18 and
.NET/ASP.NET Core 8.0.33; those are evidence versions, not a pin for future
deployments. See the [developer guide's verification record](development.md#secure-mcp-tunnel-compatibility-and-access-record-checked-2026-10-26)
for the limits of that evidence.

[Secure MCP Tunnel guide]: https://developers.openai.com/api/docs/guides/secure-mcp-tunnels

### 2. Configure Codex

Edit `~/.codex/config.toml` (`%USERPROFILE%\.codex\config.toml` on Windows),
or `config.toml` under your custom `CODEX_HOME`. Replace the example path and
credentials with your own. For Windows, TOML literal strings keep backslashes
readable:

```toml
[mcp_servers.taiga]
command = 'C:\Tools\TaigaMCP\v1\TaigaMCP.exe'
args = []

[mcp_servers.taiga.env]
TAIGA__BASEURL = "https://api.taiga.io/api/v1/"
TAIGA__USERNAME = "your-user"
TAIGA__PASSWORD = "your-password"
```

On Linux/WSL, use an absolute executable path instead, such as
`command = "/home/you/.local/share/TaigaMCP/v1/TaigaMCP"`. Use paths and
credentials visible in the environment where Codex launches the server; a
Windows executable path is not a WSL Linux path.

This example stores credentials in your local configuration. Keep it and its
backups private. Alternatively, set the variables in the environment that
launches Codex and use `env_vars = ["TAIGA__USERNAME", "TAIGA__PASSWORD"]`
inside `[mcp_servers.taiga]`, omitting those two values from its `env` table.
Use `env` for any fixed base URL or optional settings. Do not register a Taiga
API URL as an MCP endpoint: TaigaMCP calls Taiga itself. If you select HTTP,
register the configured MCP endpoint or a separately secured tunnel endpoint,
not the Taiga API URL.

The official [Codex MCP documentation](https://learn.chatgpt.com/docs/extend/mcp)
also describes `codex mcp add`, environment forwarding, and configuration.
Restart Codex after changing the connection.

## Verify the connection

In a terminal, `codex mcp list` shows configured servers. In Codex CLI, `/mcp`
shows active MCP servers. Then ask for a read-only call:

```text
Call get_current_user, then use its returned ID as the member string in list_projects with page=1.
```

A successful identity result might be:

```json
{"id":42,"username":"example-user","full_name":"Example User","is_active":true}
```

`list_projects` defaults to no member filter. Use `resolve_project` with a
known slug if needed; it returns an object such as `{"project":123}`.
Next, list one page of work in that project:

```text
Call list_user_stories with projectId=123, page=1, and includePageInfo=true.
```

Replace `123` with an ID returned by your own project lookup. These checks read
live Taiga data but do not change it. See [work-item examples](work_item_examples.md)
for assignment, sprints, statuses, story/task/epic creation, updates, and history.

## Optional: MCP Inspector

[MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) currently
requires Node.js 22.19.0 or newer and npm. Set the server credentials in the
launching shell first, then
inspect the **published executable**, so build output cannot enter the protocol
stream. For example, in PowerShell:

```powershell
$env:TAIGA__USERNAME = 'your-user'
$env:TAIGA__PASSWORD = 'your-password'
npx @modelcontextprotocol/inspector C:\Tools\TaigaMCP\v1\TaigaMCP.exe
```

Or use its CLI mode for a read-only tool call:

```powershell
npx @modelcontextprotocol/inspector --cli C:\Tools\TaigaMCP\v1\TaigaMCP.exe --method tools/call --tool-name get_current_user
```

For Linux/WSL, substitute the absolute published Linux executable path. Select
stdio in the Inspector UI. The server environment must include your required
credentials; the Codex configuration does not configure Inspector.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| SDK not found | Install a non-preview SDK in the `10.0.4xx` feature band allowed by `global.json`. |
| Framework missing when running tests | Install both the .NET 8 runtime and ASP.NET Core 8 shared framework (`Microsoft.AspNetCore.App`); a newer SDK alone does not supply them. |
| Server fails at startup | Check nonblank credentials, the API base URL, and positive TTL/attachment-size settings. Inspect stderr. |
| Configured server is unavailable | Check the absolute executable path and environment in the client that launches it; restart the client after configuration changes. |
| TOML parse error | Use the nested `env` table above. If using an inline `env = { ... }` table, keep it on one line. |
| Protocol error or timeout | Launch the published executable directly, without build commands or shell startup messages on stdout. Logs belong on stderr. |
| 401 or 403 | Check the account credentials, project access, and permissions. TaigaMCP attempts one auth replay on a received 401; 403 does not trigger API reauthentication. |
| Missing closed or archived work | Lists default to open work; story lists also exclude archived work. Use the appropriate include flags or explicit status IDs. |
| Version conflict or uncertain write | Read the item again. Never blindly repeat a create/update/delete when the error says it may already have applied. |
| Attachment download fails | Use an absolute new destination with an existing parent directory, check the size limit, and use the download tool to obtain fresh media metadata. |
| Build output locked by a running server | Use a unique external output directory as shown in the [developer guide](development.md#build-and-test). |

The default STDIO server launched directly waits for MCP input on stdin; waiting
alone does not prove the credentials or connection work. HTTP mode listens on
the configured endpoint instead. Normal host logs can appear on stderr. Verify
using an actual read-only tool call.

Keep logging at Information or higher during stdio use. The current console
configuration routes Information and higher to stderr, but enabling Debug or
Trace can put diagnostic messages on stdout and break the MCP connection.
Sanitize logs and never share credentials or signed attachment URLs.

## Validated configuration

`TAIGA__USERNAME` and `TAIGA__PASSWORD` must be nonblank. Optional
`TAIGA__BASEURL` is an absolute HTTP/HTTPS API URL without embedded credentials,
query, or fragment. Optional `TAIGA__METADATATTLSECONDS` is a positive integer
(default 300). Startup rejects invalid configuration.

`MCP__TRANSPORT` is `stdio` by default and also accepts `http` for Streamable
HTTP. For HTTP, `MCP__ADDRESS` defaults to `127.0.0.1`, `MCP__PORT` to `3001`,
and `MCP__PATH` to `/mcp`; all three are validated at startup. The dated
official tunnel compatibility and access record is in the
[developer guide](development.md#secure-mcp-tunnel-compatibility-and-access-record-checked-2026-10-26).
