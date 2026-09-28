# Taiga MCP Quickstart Guide

## Overview
This guide shows how to connect **Codex CLI** to **Taiga.io** using a custom **C# MCP server**. The server exposes tools for reading, creating, updating issues, and listing projects.

---

## Prerequisites
- SDK selected by `global.json` (10.0.401 with latestPatch) and .NET 8 runtime
- Windows PowerShell or a Linux/WSL shell (the test contamination fixture currently requires Windows)
- Node.js (for MCP Inspector)
- Codex CLI installed
- A Taiga account

---

## 1. Build the existing server

Clone this repository and run from its root; do not recreate the project or
upgrade its pinned packages as part of setup.

```powershell
dotnet restore
dotnet build -c Debug
dotnet test -c Debug
```

`Program.cs` creates the host. `Hosting/ServiceCollectionExtensions.cs` registers
configuration, named HTTP clients, the shared transport, domain APIs, cache and
MCP tool discovery. Tool classes live in `Tools/` with file-scoped namespaces.
See the [implemented tool reference](taiga_tools_reference.md) for all 11 tools.

For long-running MCP use, publish to a separate versioned directory. Keeping the
published server apart from development outputs avoids executable/DLL locks.
See the [developer guide](development.md) for temporary-output validation when
an existing server already holds a build output open.

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
  --tool-arg member=6
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
Call the tool list_projects with member=6 and page=1
Call the tool list_issues with projectId=12345 and page=1
Call the tool list_issues with projectId=12345, statusIds=[8], and includePageInfo=true
Call the tool get_issue with issueId=67890
Call the tool list_issue_statuses with projectId=12345
Call the tool list_issue_severities with projectId=12345
Call the tool list_issue_types with projectId=12345
Call the tool list_issue_priorities with projectId=12345
Create a Taiga issue in project 12345 with subject "Bug"
Update Taiga issue 67890 setting subject "Fix title" with version 3
Update Taiga issue 67890 with version 4 and clearFields=["assigned_to"]
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
- Include the current `version` on updates. Taiga may report a version conflict as a 400 field-validation response or a 409 conflict, depending on the deployed version and overlap; inspect the returned validation details and do not blindly retry an ambiguous write.

---

## Outcome
You now have:
- A custom MCP server in C#
- Tools for Taiga projects and issues
- Verified connection via MCP Inspector
- Integrated Codex CLI for natural language interaction
- Troubleshooting steps for TOML parse errors, startup timeouts, and stdout logging


### Validated configuration and updates

`TAIGA__USERNAME` and `TAIGA__PASSWORD` must be nonblank. Optional
`TAIGA__BASEURL` is an absolute HTTP/HTTPS API URL without embedded credentials,
query, or fragment. Optional `TAIGA__METADATATTLSECONDS` is a positive integer
(default 300). Startup rejects invalid configuration.

Use positive internal project/entity IDs and pages >= 1. For an update of only
description/tags, omit `subject` and pass the current `version`; use
`description: ""` or `tags: []` to empty those fields. Null optional values
leave fields unchanged. To unassign explicitly, pass
`clearFields: ["assigned_to"]`; do not combine it with `assigned_to`. Empty
updates, unsupported clear fields, and negative versions are rejected before
HTTP.
A write error saying it may already have applied requires reading the entity
before deciding whether to retry. See [development conventions](development.md).

## Intentional list behavior changes

`list_projects` now defaults to `member=null` (no member filter). To retain the
previous account-specific selection, call `list_projects(member="6")`, or send
`{"member":"6"}` over MCP. Explicit member values remain URL-encoded.
Story lists use Taiga's `status__is_closed=false` and
`status__is_archived=false`; English labels such as Done/Archived no longer
exclude open statuses. Issue lists use `status__is_closed=false` only: unsupported
issue archive filtering and redundant status-exclusion requests were removed.
These are behavior corrections, not behavior-preserving refactoring.
