# Sources and capability evidence

Reviewed 2026-09-29. Documentation and tool schemas establish a design basis;
they do not prove an installed skill, active schedule, or live Taiga permissions.

## Official documentation

- [Build skills](https://learn.chatgpt.com/docs/build-skills): a skill contains SKILL.md plus optional scripts, assets, and references; repo-local skills are discovered under .agents/skills. Use explicit invocation for this operational workflow.
- [Scheduled tasks](https://learn.chatgpt.com/docs/automations): a scheduled task can revisit an existing chat to continue a review loop; local work requires an available computer and running app.
- [Worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees): independent chats use separate checkouts; worktrees may start detached, so create/verify the feature branch. Each review identifies the implementation checkout/revision.
- [Local environments and Git controls](https://learn.chatgpt.com/docs/environments/local-environment): desktop Git controls support commit, push and PR creation. Actual CLI/connector permissions and receipt fields still require host verification.
- [Codex SDK](https://learn.chatgpt.com/docs/codex-sdk): start, continue, and resume threads for a later standalone runner. That is outside v1 and does not establish desktop sidebar attachment.
- [App Server](https://learn.chatgpt.com/docs/app-server): deeper client integration is a separate route; do not build against private desktop databases or assumed local HTTP endpoints.
- [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents): a distinct delegation facility; this workflow explicitly excludes it.

Recheck installed schemas before implementing host-dependent instructions. The
specific chat tool behavior below comes from the tools exposed in the planning
session, not from a promise that every Codex client has them.

## Observed desktop tool surface

| Tool | Use and limitation |
| --- | --- |
| list_projects | Obtain real saved-project IDs and Git capability before creating project chats. |
| create_thread | Ordinary local/project chats; explicit model and reasoning settings; worktree mode available for a Git project. Requires user request for a new chat. May return a pending clientThreadId; this is not a usable threadId. |
| list_threads / read_thread | Resolve identities and inspect status/results without opening a chat. Titles are not unique workflow IDs. |
| wait_threads | Wait using stored cursors; timeout:0 gives a compact snapshot. A timeout or commentary is not completion. |
| send_message_to_thread | Continue an existing ordinary chat; explicit model/effort fields are supported. Requires user authorization for messaging or the ongoing coordination workflow. |
| list_artifacts / worktree tools | Inspect/reuse suitable managed checkouts and manage their lifecycle. list_artifacts is scoped to the calling chat; have the worker report its own checkout/artifact identity. |
| automation_update | Create/update one heartbeat per coordinator session for its ticket set; inspect its installed schema. No cron replacement for a heartbeat by default. |
| attach_artifact | Attach each created PR to the relevant Codex chat. This does not create or merge the PR. |

Model identifiers observed on the planning host: `gpt-5.6-luna` supports `xhigh`,
`gpt-6-sol` supports `high`, and `gpt-6-astra` supports `medium`.
Resolve support again on the destination host and preserve these exact choices.

## Repository evidence

- [Tool reference](../../taiga_tools_reference.md): 35 current tools, including ticket reads/updates, comments, statuses, and reference resolution.
- [Development guide](../../development.md): fake HTTP/MCP tests, transport/auth/version rules, and output-lock guidance.
- [User-story tools](../../../Tools/UserStoryTools.cs) and [task tools](../../../Tools/TaskTools.cs): current status mutation and parent/task contracts.
- [History tools](../../../Tools/WorkItemHistoryTools.cs): explicit paginated discussion/history.
- Source baseline: `3f047a5`; planning working tree initially clean.
- Planning shell: PowerShell `7.6.6`. Other hosts must be checked.
- Repository origin: `https://github.com/blakeg83/taiga-mcp.git`; local remote-default reference is `origin/master`. This is not evidence that a fetch or authenticated GitHub operation was performed. Other code repositories must supply/verify their own configuration.

## Verification boundary

Goal 01 records discovered capabilities and unresolved assumptions. Goal 06
provides the core local handoff/scheduler exercise; goal 09 verifies the expanded
parallel/epic workflow using local Git remotes and fake external adapters.
Automated tests use fake Taiga/GitHub only. GitHub CLI or connector authentication,
PR receipt fields, check results and squash/rebase merge provenance must be verified
during implementation from the installed interface and provider documentation. Unavailable host tools must be reported;
do not substitute subagents, UI automation, or a private app API to make a demo pass.
