# TaigaMCP

TaigaMCP is a .NET 8 [Model Context Protocol (MCP)](https://modelcontextprotocol.io/)
server that lets Codex and other local MCP clients work with
[Taiga](https://taiga.io/), an open-source project management tool for Scrum,
Kanban, and issue tracking. It connects to Taiga Cloud or a self-hosted Taiga
REST API over a local **stdio** connection.

New to Taiga? Visit the [Taiga homepage](https://taiga.io/) or browse its
[GitHub repositories](https://github.com/taigaio), including the
[docker build](https://github.com/taigaio/taiga-docker).

Use it to triage issues, plan epics and user stories, manage tasks and sprints,
assign work, set native story estimates, read history, post comments, and
upload or download attachments. The server exposes **44 tools**; the
[tool reference](docs/taiga_tools_reference.md#current-tool-contracts) lists
every signature and response shape.

## What it supports

| Area | Available operations |
| --- | --- |
| Discovery | Current account, projects and slugs, project members, roles, point options, sprints, and workflow statuses |
| Issues | List, read, create, and update; discover types, priorities, and severities |
| User stories | List, read, create, update, schedule in a sprint, and set role-based story estimates |
| Tasks | List, read, create, and update standalone or story-linked tasks, including blocking state |
| Epics | List, read, create, update, and link/list/unlink existing stories |
| Shared work-item tools | Resolve displayed references, add/read comments, read field-change history, and list/read/upload/download/update/delete attachments for issues, stories, tasks, and epics |

The server acts with your Taiga account's permissions. It includes write and
attachment-deletion tools, so give your MCP client clear instructions about
which changes you want. It does not implement the entire Taiga API; the
[command inventory](docs/taiga_command_inventory.md) separates delivered
features from proposed coverage.

## Requirements

- To build: the SDK selected by [global.json](global.json), currently
  **10.0.401 with `latestPatch` roll-forward** (10.0.4xx feature band).
- To run a framework-dependent build or the tests: the **.NET 8 runtime**.
  A self-contained published server includes its runtime.
- A Taiga account with username/password authentication and access to the
  target projects.
- An MCP client that supports local stdio servers. Codex setup is documented
  below; other clients can launch the same published executable with the same
  environment variables.

The Windows installer additionally needs PowerShell **7.3+** and Codex CLI on
`PATH`. Manual publish commands are provided for Windows and Linux/WSL in the
[quickstart](docs/taiga_mcp_quickstart.md). The complete test suite currently
requires Windows because one protocol-contamination test uses `cmd.exe`.

## Build and run

Clone this repository and open a terminal in its root directory.

### Windows: install into Codex

```powershell
pwsh -File .\scripts\Install-Codex.ps1
```

The script publishes the current checkout as a self-contained executable to a
new release under `%LOCALAPPDATA%\TaigaMCP`, registers the `taiga` MCP server,
and installs the two bundled Codex skills. It reuses the existing server's
environment values. On first setup, it uses `TAIGA__USERNAME` and
`TAIGA__PASSWORD` from the process environment or prompts for them (the
password prompt is hidden). Set `TAIGA__BASEURL` before first setup if you use
a self-hosted server. Restart Codex and open a new chat afterward.

Credentials are stored in the local Codex configuration. Existing config
backups also contain those values; keep both private. The script preserves
other Codex connections/settings, but re-registering `taiga` resets its custom
tool filters, timeouts, and other server options to Codex defaults. Values
previously inherited through `env_vars` are saved with their current values.
It does not contact Taiga or stop running servers. Old published releases
remain on disk. To change the install location:

```powershell
pwsh -File .\scripts\Install-Codex.ps1 -InstallRoot C:\Tools\TaigaMCP
```

Pull your desired repository version before running the script; it publishes
the current checkout without changing branches or pulling updates.

### Manual setup or other MCP clients

Follow the [quickstart](docs/taiga_mcp_quickstart.md) to publish an executable,
configure credentials, and verify the connection with read-only calls. For
local development in PowerShell:

```powershell
dotnet restore
dotnet build -c Debug
$env:TAIGA__USERNAME = 'your-user'
$env:TAIGA__PASSWORD = 'your-password'
dotnet run --no-build
```

The server waits for MCP messages on stdin; it is not an interactive shell or
an HTTP service. Configure your MCP client to launch it. Protocol messages go
to stdout and normal host logs go to stderr.

## Configuration

Set these variables in the **server process's environment**:

| Variable | Required | Default / meaning |
| --- | --- | --- |
| `TAIGA__USERNAME` | Yes | Nonblank Taiga login |
| `TAIGA__PASSWORD` | Yes | Nonblank Taiga password |
| `TAIGA__BASEURL` | No | `https://api.taiga.io/api/v1/`; include the API path for self-hosted Taiga |
| `TAIGA__METADATATTLSECONDS` | No | `300`; positive metadata-cache lifetime in seconds |
| `TAIGA__MAXATTACHMENTBYTES` | No | `10485760` (10 MiB); positive upload/download size limit |

Startup validates these settings. The base URL must be absolute HTTP/HTTPS
without embedded credentials, a query, or a fragment; a trailing slash is
normalized. Prefer HTTPS when sending credentials over a network.

TaigaMCP logs in to Taiga itself and keeps bearer/refresh tokens in process
memory. Application-token authentication is not implemented. Never commit
credentials or a populated client configuration to the repository.

Attachment paths refer to the filesystem visible to the **server process**.
Uploads require an explicit absolute file path. Downloads require an absolute
destination whose parent directory already exists and never overwrite an
existing file. Use the download tool to access file contents: metadata URLs
can contain expiring signed tokens and should be treated as sensitive.

## Using the tools

Start with a read-only request such as:

```text
Identify my Taiga account, then list the projects I belong to.
```

`get_current_user` returns your account ID. To filter `list_projects` to that
account, pass it as the `member` string; the default has no member filter.
Use `resolve_project` for a known slug and `resolve_work_item` for a displayed
project-local `#ref`. Detail and update tools take internal IDs, not `#ref`.

Before an edit, read the item and use its returned `version`. Status IDs are
specific to each project and work-item kind; discover them rather than guessing
from names. Ordinary omitted/null update fields stay unchanged. Supported
`clearFields` values deliberately clear assignment or a story's sprint.

Lists return one upstream page per call. Issue/story lists default to arrays
and offer `includePageInfo=true`; task/epic and most discovery lists return
page envelopes. Unknown pagination metadata stays `null`. Work-item lists
default to open work, with story lists also excluding archived work; use the
documented status filters or include flags when you need completed items.

Only a received HTTP 401 permits one authentication replay. Version conflicts
and ambiguous writes are not automatically retried. If an error says a change
may already have applied, inspect the item before deciding to repeat it.

## Optional Codex skills

The Windows installer copies both complete skill folders to
`%USERPROFILE%\.agents\skills`, or updates an existing copy under the Codex
home's `skills` directory. `CODEX_HOME` is respected for the latter location
and Codex configuration. These instruction-based workflows are separate from
the MCP server:

- [Taiga backlog publisher](.agents/skills/taiga-backlog-publisher/SKILL.md):
  turn a plan into an estimated backlog and publish it when explicitly requested.
- [Taiga story loop lite](.agents/skills/taiga-story-loop-lite/SKILL.md):
  coordinate implementation and review for one selected story using separate
  Codex chats.

### Example prompts

Replace the project slug, story reference, repository path, and base branch
below with your own values. Paste your approved implementation plan where
indicated.

**Backlog publisher — plan without publishing:**

```text
$taiga-backlog-publisher Turn the approved implementation plan below into an
ordered epic/story/task backlog for project my-project. Preserve its requirements
and acceptance criteria, and estimate stories using the project's configured
roles and point options. Do not write to Taiga.

[Paste the approved implementation plan here.]
```

**Backlog publisher — publish an approved plan:**

```text
$taiga-backlog-publisher Publish the approved implementation plan below to
project my-project. Create the required epics, stories, and ordered tasks,
assign new items to my authenticated account, and persist native story
estimates for each relevant configured role. Check for duplicates before
creating items and read back the results to verify publication.

[Paste the approved implementation plan here.]
```

**Backlog publisher — flesh out an existing story:**

```text
$taiga-backlog-publisher Flesh out user story #123 in project my-project.
Read its requirements and existing child tasks, derive and create only the
missing implementation tasks, and set native story estimates for the relevant
configured roles. Preserve existing task content and assignments, and verify
the completed task coverage. Keep the existing story as the target.
```

**Story loop lite — implement and review one story:**

```text
$taiga-story-loop-lite Implement user story #123 in project my-project using
repository C:\Projects\MyApp and base branch master. Use this chat as the
Coordinator and create the separate Implementer and Reviewer chats required
by the skill. Follow the story's linked epic requirements and ordered child
tasks, run the relevant checks, and maintain Taiga statuses and comments.
I authorize worker handoff and review messages between these chats. After
reviewer approval, commit the reviewed changes, push the story branch, and
create a PR against master. Do not merge it.
```

For manual skill discovery and client configuration, see the official
[Codex skills](https://learn.chatgpt.com/docs/build-skills) and
[MCP setup](https://learn.chatgpt.com/docs/extend/mcp) documentation.

## Documentation and contributing

- [Quickstart](docs/taiga_mcp_quickstart.md): publishing, client configuration,
  connection checks, and troubleshooting.
- [Work-item examples](docs/work_item_examples.md): discovery and editing workflows
  with sample tool arguments and responses.
- [Tool reference](docs/taiga_tools_reference.md): all implemented contracts.
- [Developer guide](docs/development.md): architecture, build/test commands,
  and contribution conventions.
- [Command inventory](docs/taiga_command_inventory.md): delivered versus proposed
  coverage; proposed commands are not promises of availability.

For bugs, include the tool name, sanitized arguments, expected/actual behavior,
and safe error text. Remove credentials, signed URLs, and private project
content before sharing logs or examples. For contributions, read the developer
guide and [AGENTS.md](AGENTS.md), keep changes focused, and run the relevant
fake-HTTP and MCP tests. No live Taiga credentials are needed for tests.

## License

Licensed under the [MIT License](LICENSE).
