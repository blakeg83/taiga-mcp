# TaigaMCP

TaigaMCP is a .NET 8 Model Context Protocol (MCP) server that connects Codex CLI (and other MCP clients) to Taiga.io. It exposes tools to list projects, resolve project IDs, and manage issues via Taiga’s REST API.

## Features
- `list_projects(member?, page)`: List projects (use `member=me` for your projects).
- `resolve_project(slug)`: Resolve a Taiga project slug to its numeric ID.
- `list_issues(projectId, page)`: Page through issues for a project.
- `create_issue(projectId, subject, …)`: Create a new issue.
- `update_issue(issueId, patch)`: Patch an issue; patch must include `version`.

## Requirements
- .NET 8 SDK
- Taiga account and credentials

## Build and Run
```bash
dotnet restore && dotnet build -c Release
TAIGA_USERNAME=you@example.com TAIGA_PASSWORD=secret \
  TAIGA_BASE_URL=https://api.taiga.io/api/v1/ \
  dotnet run
```

Publish a single-file binary (recommended for MCP clients):
```bash
dotnet publish -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true
# Binary: ./bin/Release/net8.0/linux-x64/publish/TaigaMCP
```

## Configuration
Set environment variables for the server process:
- `TAIGA_BASE_URL` (optional, default: `https://api.taiga.io/api/v1/`)
- `TAIGA_USERNAME`
- `TAIGA_PASSWORD`

For Codex CLI, point the MCP server `command` to the published binary and pass the env vars. See the quickstart for a full `config.toml` example.

## Codex CLI config.toml
Add an MCP server entry pointing to the published binary:

```toml
[mcp_servers.taiga]
command = "/home/you/src/taiga-mcp/bin/Release/net8.0/linux-x64/publish/TaigaMCP"
args = []
env = { TAIGA_BASE_URL = "https://api.taiga.io/api/v1/", TAIGA_USERNAME = "you@example.com", TAIGA_PASSWORD = "yourpass" }

# Optional: trust local projects for Codex (example paths)
[projects]
"/home/you/src/taiga-mcp" = { trust_level = "trusted" }
```

Notes:
- Keep the `env = { ... }` inline table on one line (TOML requirement).
- Use the absolute path to your published binary for `command`.

## Development Notes
 - Entry point and DI/live tools: `Program.cs` registers domain APIs and
   loads `[McpServerToolType]` classes from the `Tools/` folder.
- Transport: STDIO; logging via `Microsoft.Extensions.Logging` to stderr.
- HTTP: `HttpClient` with bearer auth token acquired via `/auth`.

## Quickstart & Examples
For end-to-end setup (Codex config, MCP Inspector, troubleshooting), see:

- docs/taiga_mcp_quickstart.md
