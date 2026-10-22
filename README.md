# TaigaMCP

TaigaMCP is a .NET 8 Model Context Protocol (MCP) server that connects Codex CLI (and other MCP clients) to Taiga.io. Its 44 tools identify the current account, list projects, project members, points, roles, and sprints, resolve project and work-item references, discover story, task, and epic workflow statuses, manage issues, create/read/list/update user stories and tasks, safely update native story estimates, create/list/read/update/link/list/unlink epic relationships, and submit comments or read visible comments and field-change history on all four work-item kinds via Taiga’s REST API.

The repository-local `.agents/skills/taiga-story-loop-lite/` skill provides a
minimal, instruction-driven two-worker implementation/review workflow for one
selected story. It is separate from the .NET MCP server.

## Features
- `list_projects(member?, page)`: List projects without a member filter by default; pass an explicit numeric member ID to filter.
- `resolve_project(slug)`: Resolve a Taiga project slug to its numeric ID.
- `resolve_work_item(projectId, kind, ref)`: Resolve a numeric project-local `ref` for a known `issue`, `user_story`, `task`, or `epic` to its internal ID plus available subject/version. Use that ID with the matching `get_*` tool before editing; the ref is not the internal ID.
- `get_current_user()`: Identify the authenticated account and return its positive numeric ID plus available identity fields. Private profile fields are omitted.
- `list_project_members(projectId, page)`: List one page of project membership records. Use `user_id` from an active member as an assignee ID; `membership_id` identifies the membership record, and pending/inactive records remain visible without exposing email or invitation text.
- `list_sprints(projectId, page, closed?)`: List one page of Taiga milestones with date-only start/finish values and closure state. Omit or pass `null` for all sprints, `false` for open only, or `true` for closed only; use a returned `id` as `milestoneId` when scheduling a story or standalone task.
- `list_issues(projectId, page, statusIds?, assignedTo?, typeId?, priorityId?, severityId?, tags?, query?, includeClosed?, includePageInfo?)`: Triage one page of issues with allowlisted filters. It returns the legacy array by default and an opt-in pagination envelope with `includePageInfo=true`.
- `get_issue(issueId)`: Retrieve a single issue by its id.
- `create_issue(projectId, subject, …)`: Create a new issue.
- `update_issue(issueId, version, subject?, ..., clearFields?)`: Partially update an issue via PATCH; `subject` is optional, and `clearFields=["assigned_to"]` explicitly unassigns while omitted/null `assigned_to` leaves it unchanged.
- `add_work_item_comment(kind, id, version, text)`: Submit a Markdown/mention-preserving comment to an `issue`, `user_story`, `task`, or `epic` using the supplied version. Returns the server's resulting version and `comment_submitted=true`.
- `list_work_item_comments(kind, id, page?)`: Read one page of visible nonblank comments from a work-item history stream. Returns opaque history-entry IDs, raw Markdown/text, timestamps, safe actor identity, edit dates, and upstream pagination metadata; hidden/deleted comments are omitted without filling from later pages.
- `get_work_item_history(kind, id, page?)`: Read one page of visible field changes and comments from a work-item history stream. Returns opaque IDs, numeric event types, timestamps, safe actors, structured `diff`/`values_diff`, edit/delete metadata, and `is_snapshot`; hidden entries and deleted comment text are suppressed without filling from later pages.
- `list_issue_statuses(projectId)`: List available issue statuses for a project.
- `list_issue_severities(projectId)`: List available issue severities for a project.
- `list_issue_types(projectId)`: List available issue types for a project.
- `list_issue_priorities(projectId)`: List available issue priorities for a project.

Issue list filters use internal Taiga IDs. The default view is open issues;
provide nonempty `statusIds` or `includeClosed=true` to include closed work.
See the [implemented tool reference](docs/taiga_tools_reference.md) for the
wire filters and envelope fields, including the current-user identity contract.

- `list_user_stories(projectId, page, statusIds?, assignedTo?, milestoneId?, backlogOnly?, tags?, query?, includeClosed?, includeArchived?, includePageInfo?)`: List one page of backlog or sprint stories with explicit status/assignment/text filters; the default is an array and `includePageInfo` opts into pagination metadata.
- `list_user_story_statuses(projectId, page)`: List one page of every selectable story workflow status, including closed and archived choices, with project/resource-specific IDs and available order, color, and WIP metadata. Use a returned `id` with `create_user_story` or `update_user_story`.
- `list_task_statuses(projectId, page)`: List one page of every selectable task workflow status, including open and closed choices, with project/resource-specific IDs and available name, slug, order, color, and closure metadata. Use a returned `id` with `create_task` or `update_task`; task statuses do not include story-only archive or WIP fields.
- `list_tasks(projectId, page, userStoryId?, milestoneId?, statusIds?, assignedTo?, tags?, query?, includeClosed?)`: List one page of standalone or story-linked tasks. It always returns a pagination envelope; explicit status IDs override the default open-only filter.
- `list_epics(projectId, page, statusIds?, assignedTo?, tags?, query?, includeClosed?)`: List one page of project epics with verified status, assignee, tag, and text filters. It always returns a pagination envelope; explicit status IDs override the default open-only filter.
- `list_epic_statuses(projectId, page)`: List one page of every selectable epic workflow status, including open and closed choices, with project/resource-specific IDs and available name, slug, order, color, and closure metadata. Use a returned `id` with `create_epic` or `update_epic`; epic statuses do not expose story-only archive or WIP fields.
- `get_epic(epicId)`: Retrieve one epic by its positive internal ID, including authoritative identity/version, Markdown description, status, assignment, color, tags, and available server summaries. It does not fetch related stories or compute progress.
- `create_epic(projectId, subject, description?, status?, assigned_to?, color?, tags?)`: Create one epic and return its authoritative detail. Omitted optional fields use Taiga project defaults; story linking and requirement flags remain separate operations.
- `update_epic(epicId, version, subject?, description?, status?, assigned_to?, color?, tags?, comment?, clearFields?)`: Versioned epic edits for content, status, primary assignment, color, tags, and comments. Omitted fields stay unchanged; empty description/tags are explicit, and `clearFields=["assigned_to"]` unassigns. Use a status returned by `list_epic_statuses` to close or reopen an epic.
- `link_user_story_to_epic(epicId, userStoryId, order?)`: Associate an existing story with an epic. Repeated calls return the existing server order with `created=false` and do not change it; Taiga decides whether accessible cross-project links are permitted.
- `list_epic_user_stories(epicId, page)`: List one page of an epic's existing relationship identities and server order as `{ epic_id, user_story_id, order }`. Use `get_user_story` for selected full details; this does not create, modify, expand, or calculate progress for the epic.
- `unlink_user_story_from_epic(epicId, userStoryId)`: Remove exactly one epic/story relationship and return `{ epic_id, user_story_id, removed: true }` after Taiga confirms HTTP 204. This preserves both work items and other links; a repeated unlink may return a safe 404 and is not treated as already successful.
- `get_task(taskId)`: Retrieve one task detail object by its positive internal ID, including the authoritative version, Markdown description, status/assignment, parent story, sprint, tags, due-date, and blocking fields.
- `create_task(projectId, subject, userStoryId?, milestoneId?, description?, status?, assigned_to?, tags?)`: Create one standalone or story-linked task. A story-linked task validates its parent and inherits the parent's sprint; a matching `milestoneId` is redundant. Omitted optional fields use Taiga project defaults.
- `update_task(taskId, version, subject?, description?, status?, assigned_to?, tags?, isBlocked?, blockedNote?, comment?, clearFields?)`: Versioned task edits for content, status, primary assignment, tags, blocking, and comments. Omitted fields stay unchanged; empty values are explicit, `clearFields=["assigned_to"]` unassigns, and Taiga clears `blocked_note` whenever the saved task is unblocked.
- `get_user_story(userStoryId)`: Retrieve a story by its positive internal ID (not its displayed `#ref`), including its authoritative version, Markdown description, status/assignment, tags, sprint, and available epic/source relationships.
- `create_user_story(projectId, subject, description?, status?, assigned_to?, tags?, milestoneId?)`: Create one backlog or sprint story. Put acceptance criteria in `description`; omitted optional fields use Taiga project defaults, and the result includes the server-generated ID, ref, and version.
- `update_user_story(userStoryId, version, subject?, description?, status?, assigned_to?, tags?, milestoneId?, comment?, clearFields?)`: Versioned story update. Omitted fields stay unchanged; use `clearFields=["assigned_to"]` to unassign or `clearFields=["milestone"]` to return a story to the backlog. Empty description/tags are explicit clears.
- `set_user_story_estimates(userStoryId, version, rolePoints[{ roleId, pointId }])`: Versioned native story-point update. Sends only the supplied role-to-configured-point assignments and version, preserves omitted roles, supports configured unestimated point options, and returns authoritative estimate state without automatic conflict or ambiguous-write retries.

## Requirements
- SDK selected by `global.json` (10.0.401, latest patch within that feature band) and .NET 8 runtime
- Taiga account and credentials

## Build and Run
```bash
dotnet restore && dotnet build -c Release
TAIGA__USERNAME=you@example.com TAIGA__PASSWORD=secret \
  TAIGA__BASEURL=https://api.taiga.io/api/v1/ \
  dotnet run
```

Publish a single-file binary (recommended for MCP clients):
```bash
dotnet publish -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true
# Binary: ./bin/Release/net8.0/linux-x64/publish/TaigaMCP
```

## Configuration
Set environment variables for the server process:
- `TAIGA__BASEURL` (optional, default: `https://api.taiga.io/api/v1/`)
- `TAIGA__USERNAME`
- `TAIGA__PASSWORD`
- `TAIGA__METADATATTLSECONDS` (optional positive integer, default 300)

For Codex CLI, point the MCP server `command` to the published binary and pass the env vars. See the quickstart for a full `config.toml` example.

## Codex CLI config.toml
Add an MCP server entry pointing to the published binary:

```toml
[mcp_servers.taiga]
command = "/home/you/src/taiga-mcp/bin/Release/net8.0/linux-x64/publish/TaigaMCP"
args = []
env = { TAIGA__BASEURL = "https://api.taiga.io/api/v1/", TAIGA__USERNAME = "you@example.com", TAIGA__PASSWORD = "yourpass" }

# Optional: trust local projects for Codex (example paths)
[projects]
"/home/you/src/taiga-mcp" = { trust_level = "trusted" }
```

Notes:
- Keep the `env = { ... }` inline table on one line (TOML requirement).
- Use the absolute path to your published binary for `command`.

## Development Notes

`Program.cs` creates the host; `Hosting/ServiceCollectionExtensions.cs` registers
options, APIs and tools. Tools use concrete domain APIs and a shared transport
with cancellation, safe errors and explicit disposal. Auth token state and the
expiring metadata cache are singleton services; named HTTP clients are obtained
per operation. STDIO carries MCP messages only; logging goes to stderr.

See the [developer guide](docs/development.md) for current architecture and the
historical foundation cleanup record, and the [completed first batch](docs/goals/first-batch/README.md) for delivered scope.

Windows PowerShell:

```powershell
dotnet restore
dotnet build -c Debug
dotnet test -c Debug
$env:TAIGA__USERNAME = 'your-user'
$env:TAIGA__PASSWORD = 'your-password'
dotnet run --no-build
```

Tests use fake HTTP and synthetic credentials. Run the local build and test
commands from the [development guide](docs/development.md). Publish long-running MCP servers to a separate versioned
directory, for example `dotnet publish TaigaMCP.csproj -c Release -o C:\TaigaMCP\published\v1`.
If a server locks normal outputs, use a unique external output directory for
build/tests; do not stop that server. See the developer guide for the exact command.

## Reference documentation

- [Implemented tool reference](docs/taiga_tools_reference.md): current tool names, signatures, JSON shapes, and compatibility notes.
- [Command inventory](docs/taiga_command_inventory.md): proposed coverage for issues, epics, user stories, and tasks.

## Debug Logging
- Enable debug logs to stderr by setting: `Logging__LogLevel__Default=Debug`.
- Example:
  - `Logging__LogLevel__Default=Debug TAIGA__USERNAME=you@example.com TAIGA__PASSWORD=secret dotnet run`
- These logs include auth refresh/relogin breadcrumbs without exposing secrets.

## Quickstart & Examples
For end-to-end setup (Codex config, MCP Inspector, troubleshooting), see:

- docs/taiga_mcp_quickstart.md

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
