# Taiga MCP Quickstart Guide

## Overview
This guide shows how to connect **Codex CLI** to **Taiga.io** using a custom **C# MCP server**. The server exposes tools for reading, creating, and updating issues; reading and creating user stories; creating, reading, and listing tasks; and creating, listing, reading, and linking epics and projects.

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
See the [implemented tool reference](taiga_tools_reference.md) for all 22 tools.

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

### Create a user story

Use the required arguments for a minimal backlog story:

```json
{"projectId":123,"subject":"Allow saved searches"}
```

Put acceptance criteria in `description`. To place the story in a sprint and
assign it, provide project-specific internal IDs:

```json
{"projectId":123,"subject":"Allow saved searches","description":"Acceptance: saved searches can be reopened.","status":7,"assigned_to":42,"tags":["search","saved"],"milestoneId":55}
```

Taiga applies project defaults for omitted optional fields. The returned JSON
contains the server-created story detail, including its `id`, `ref`, and
`version`. Status, assignee, and milestone membership are validated by Taiga.

### Create a task

Create a standalone task with project defaults, or select a sprint explicitly:

```json
{"projectId":123,"subject":"Capture deployment checklist"}
{"projectId":123,"subject":"Prepare release notes","milestoneId":55}
```

To break down a story, provide its internal ID. The server reads the parent,
validates the project, and returns the authoritative inherited sprint. Omit
`milestoneId` for inheritance; if supplied, it must match the parent's sprint
and is omitted from the wire request. Ordinary creation uses `POST /tasks`, so
it does not inherit the sprint-only restriction of Taiga's native bulk-create
endpoint:

```json
{"projectId":123,"subject":"Implement saved-search endpoint","userStoryId":102,"description":"Acceptance: preserve the search filters.","status":11,"assigned_to":42,"tags":["search"]}
```

The response is the created task detail with server-generated `id`, `ref`, and
`version`, plus the resulting parent and sprint.

### Read an epic

Use `list_epics` to obtain a project-scoped page. Pass an item's internal `id`
to `get_epic`; the displayed `ref` is not accepted as the detail identifier:

```json
{"projectId":123,"page":1,"includeClosed":false}
{"epicId":301}
```

The detail result preserves the server's description, status, assignment,
color, tags, version, and optional summary fields such as
`user_stories_counts`. It does not enumerate related stories or calculate
progress. Use the returned internal epic ID for later story-linking commands.

### Create an epic

Create one epic with Taiga's project defaults, then use its returned internal
ID for reads or a later story link:

```json
{"projectId":123,"subject":"Saved search experience"}
```

Optional values are project-specific status and assignee IDs. Color is passed
to Taiga for validation, while an omitted color lets Taiga generate its
default:

```json
{"projectId":123,"subject":"Saved search experience","description":"Group saved-search delivery work.","status":7,"assigned_to":42,"color":"#336699","tags":["search","saved"]}
```

This creates only the epic. It does not create stories or change project
settings. To organize an existing story under the new epic, call the separate
link tool:

```json
{"epicId":301,"userStoryId":102,"order":9001}
```

The response is `{"epic_id":301,"user_story_id":102,"order":9001,"created":true}`
when the relationship is new. A repeat call returns the existing order with
`created=false`, even if a different order is requested.

### Create a story and link it to an epic

Use the returned story `id` from `create_user_story`, not its displayed `ref`,
in the link call. The workflow is:

```json
{"projectId":123,"subject":"Allow saved searches"}
{"epicId":301,"userStoryId":102}
```

The link operation does not move or update the story. Cross-project links are
left to Taiga's permissions and validation.

### Update a user story

Read the story first and pass its returned `version` to the update. Omitted
fields remain unchanged; use exact wire names in `clearFields` for explicit
nulls:

```json
{"userStoryId":102,"version":4,"clearFields":["milestone"],"comment":"Move back to backlog."}
```

`milestoneId` places a story in a sprint, `clearFields=["milestone"]` returns
it to the backlog, and `clearFields=["assigned_to"]` unassigns it. Empty
`description` or `tags` values are explicit clears. The returned `version` and
other fields are authoritative; the server is not blindly retried after a
conflict or ambiguous write failure. `status` is a project-specific internal
status ID, so use an open or closed status ID from Taiga to reopen or close a
story. Only the primary assignee is supported; multiple assignees remain
planned.

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
Call the tool list_user_stories with projectId=12345 and backlogOnly=true
Call the tool list_user_stories with projectId=12345, milestoneId=678, and includePageInfo=true
Call the tool list_tasks with projectId=12345, userStoryId=102, and includeClosed=false
Call the tool list_tasks with projectId=12345, milestoneId=678, assignedTo=42
Call the tool list_epics with projectId=12345, includeClosed=false, and query="search"
Call the tool get_epic with epicId=301
Call the tool get_task with taskId=203
Call the tool update_task with taskId=203, version=2, status=11
Call the tool update_task with taskId=203, version=3, isBlocked=false, blockedNote="", comment="Dependency resolved."
Call the tool get_user_story with userStoryId=102
Call the tool get_issue with issueId=67890
Call the tool list_issue_statuses with projectId=12345
Call the tool list_issue_severities with projectId=12345
Call the tool list_issue_types with projectId=12345
Call the tool list_issue_priorities with projectId=12345
Create a Taiga issue in project 12345 with subject "Bug"
Update Taiga issue 67890 setting subject "Fix title" with version 3
Update Taiga issue 67890 with version 4 and clearFields=["assigned_to"]
```

For task edits, first use `list_tasks` to identify the internal task ID, then
call `get_task` and use its fresh `version` with `update_task`. `get_task`
accepts the internal ID, not the displayed `#ref`. Use
`clearFields=["assigned_to"]` to unassign, and pass
`isBlocked=false, blockedNote=""` when both the blocker and its note should be
cleared. The request keeps omitted fields absent, but Taiga clears
`blocked_note` on save whenever the task is unblocked, including if a nonempty
note is supplied.

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
`status__is_archived=false` by default; nonempty status IDs override both,
and include flags selectively remove them. `backlogOnly=true` uses
`milestone__isnull=true`, while `milestoneId` selects a sprint. English labels
such as Done/Archived never determine filtering. Issue lists use
`status__is_closed=false` only: unsupported issue archive filtering and
redundant status-exclusion requests were removed. These are behavior
corrections, not behavior-preserving refactoring.
