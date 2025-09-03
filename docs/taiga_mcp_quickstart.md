# Taiga MCP Quickstart Guide

## Overview
This guide shows how to connect **Codex CLI** to **Taiga.io** using a custom **C# MCP server**. The server exposes tools for reading, creating, updating issues, and listing projects.

---

## Prerequisites
- .NET 8 SDK
- WSL Ubuntu environment
- Node.js (for MCP Inspector)
- Codex CLI installed
- A Taiga account

---

## 1. Create the MCP Server
```bash
dotnet new console -n TaigaMCP
cd TaigaMCP
dotnet add package ModelContextProtocol --prerelease
dotnet add package Microsoft.Extensions.Hosting
```

 Edit **Program.cs** to:
 - Set up an `HttpClient` for Taiga API
 - Register domain APIs for projects, issues, and user stories
 - Define MCP tools in `[McpServerToolType]` classes under `Tools/`:
  - `list_projects(member?, page)`
  - `resolve_project(slug)`
  - `list_issues(projectId, page)`
  - `create_issue(projectId, subject, …)`
  - `update_issue(issueId, patch)` (**requires version field** for OCC)
  - `list_issue_statuses(projectId)`

Build:
```bash
dotnet build
```

---

## 2. Configure Codex CLI
Edit **~/.codex/config.toml** in WSL. Example:

```toml
[projects]
"/home/bgauthier/src/TaskGame" = { trust_level = "trusted" }
"/home/bgauthier/src/grit-journal" = { trust_level = "trusted" }

[mcp_servers.taiga]
command = "/home/bgauthier/projects/TaigaMCP/bin/Release/net8.0/linux-x64/publish/TaigaMCP"
args = []
env = { TAIGA__BASEURL = "https://api.taiga.io/api/v1", TAIGA__USERNAME = "you@example.com", TAIGA__PASSWORD = "yourpass" }
```

> **Tip:** Inline tables (like `env = { ... }`) must all be on one line. Breaking across lines causes TOML parse errors.

---

## 3. Build a Self-Contained Binary
Running `dotnet run` inside Codex can time out. Publish a binary to avoid JIT delays:

```bash
dotnet publish -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true
```
Binary path:
```
./bin/Release/net8.0/linux-x64/publish/TaigaMCP
```
Update `command` in `config.toml` to point to that file.

---

## 4. Test with MCP Inspector
Before using Codex, test the server:

### GUI Mode
```bash
npx @modelcontextprotocol/inspector dotnet run --project ./TaigaMCP.csproj
```
- Transport: `STDIO`
- Command: `dotnet`
- Args: `run --project ./TaigaMCP.csproj`
- Env: TAIGA__BASEURL, TAIGA__USERNAME, TAIGA__PASSWORD

Click **Connect** → call tools interactively.

### CLI Mode
```bash
npx @modelcontextprotocol/inspector --cli ./bin/Release/net8.0/linux-x64/publish/TaigaMCP \
  --method tools/call \
  --tool-name list_projects \
  --tool-arg member=me
```

---

## 5. Use in Codex CLI
Launch Codex:
```bash
codex
```

### Check connection
```
/status
```
Look for `taiga` in the MCP servers list.

### Try tools
```
List projects I belong to
Call the tool list_projects with member=me and page=1
Call the tool list_issues with projectId=12345 and page=1
Call the tool list_issue_statuses with projectId=12345
Create a Taiga issue in project 12345 with subject "Bug"
Update Taiga issue 67890 with patch {"subject":"Fix title","version":3}
```

---

## 6. Troubleshooting

### TOML errors
- `newlines are unsupported in inline tables`: keep inline tables on one line.
- Use `[projects]` syntax instead of inline table if you have multiple trusted projects.

### MCP server timeout
- Build and point Codex at a published binary (`dotnet publish`).
- Ensure no `Console.WriteLine` writes to stdout. Use `ILogger` → stderr only.
- Verify binary runs cleanly with:
  ```bash
  ./bin/Release/net8.0/linux-x64/publish/TaigaMCP
  ```
  It should sit idle without output.

### Test outside Codex
- Use MCP Inspector GUI/CLI to confirm tools respond.
- Example CLI:
  ```bash
  npx @modelcontextprotocol/inspector --cli ./TaigaMCP --method tools/list
  ```

### Common mistakes
- Wrong binary path in `config.toml`
- Env vars not on one line in TOML
- Missing `version` field on updates → Taiga returns 409

---

## Outcome
You now have:
- A custom MCP server in C#
- Tools for Taiga projects and issues
- Verified connection via MCP Inspector
- Integrated Codex CLI for natural language interaction
- Troubleshooting steps for TOML parse errors, startup timeouts, and stdout logging

