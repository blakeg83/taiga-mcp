# Host contract

The coordinator must inspect the current host tools before an operational run.
The planning host exposes ordinary local/project chat creation, explicit model
and effort fields, follow-up messaging, bounded result waits, managed
worktrees, heartbeat updates, project lookup, and PR artifact attachment.
Those schemas establish availability, not successful execution.

The required profiles are exact:

| Role | Model | Effort |
| --- | --- | --- |
| implementer | `gpt-5.6-luna` | `xhigh` |
| reviewer | `gpt-6.1-sol` | `high` |

Record requested and observed settings separately. Do not substitute another
profile when one is missing. The current planning host exposes
`gpt-6-sol/high` and `gpt-6-astra/medium`, but not the requested
`gpt-6.1-sol/high`; until the host advertises the requested identifier, an
operational run must stop with an unavailable-profile report. `create_thread`
may return a pending
`clientThreadId`; only a resolved real `threadId` may be messaged or used as a
worker receipt. Use `wait_threads` cursors; timeout, commentary, and idle are
not completion.

Host preflight also records PowerShell, Git, the configured remote/base, and
GitHub CLI or connector access without printing credentials. A missing desktop,
schedule, worktree, or provider capability produces a capability report and
blocks only the dependent operation. No subagent or private app API is a
compatible fallback.

Authorization is scoped and durable for the run: selected chat creation/reuse
and messaging, worktree/branch creation, Taiga writes, push/PR creation or
updates, and optional heartbeat/merge observation. It never includes automatic
merge, force-push, deployment, or unrelated conversations.
