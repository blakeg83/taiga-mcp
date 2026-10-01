# Host contract

Inspect current host tool schemas and configuration before an operational run.
Record the requested and observed coordinator profile, exact worker profiles,
ordinary chat creation/messaging, bounded waits, managed worktrees, any required
browser capability, heartbeat support, Git, and the selected Taiga/GitHub
providers. Tool schemas establish capability availability, not successful
execution. This preflight is metadata/configuration work; it does not include
source investigation or a browser smoke test by the coordinator.

The required worker profiles are exact:

| Role | Model | Effort |
| --- | --- | --- |
| implementer | `gpt-5.6-luna` | `xhigh` |
| reviewer | `gpt-6.1-sol` | `high` |

Preserve the user's selected coordinator profile. Verify both worker
combinations from the current host's advertised model/effort options. If an
exact profile is unavailable, report that blocker and stop the dependent worker
dispatch; do not substitute a similar model or effort. `create_thread` may
return a pending `clientThreadId`; only a resolved `threadId` can be messaged or
used as a worker receipt. Use `wait_threads` cursors; timeout, commentary, and
idle are not completion.

Earlier records are dated snapshots, not current capabilities: the planning
host did not advertise the requested reviewer on 2026-09-29, while the
2026-09-30 trial record reports it on a different host. Re-check the actual
host for every run. See [preflight troubleshooting](preflight-troubleshooting.md)
for capability, profile, and authorization routes.

For a browser-dependent repository check, require a supported visible browser
provider from the actual host. Any equivalent supported provider such as the
in-app browser, Chrome, or Edge satisfies the capability check; the worker then
performs the required interaction and returns evidence. The coordinator does
not open pages or claim a smoke test merely because the provider is available.

The local `workflow-preflight.ps1` helper evaluates a coordinator-supplied
snapshot of observed profiles/capabilities, repository requirements, selected
ticket, and explicit user authorization. It does not query private desktop
APIs, call providers, or authorize actions. Missing optional capabilities block
only operations that require them. Missing ticket scope, user authority, or
material product requirements remain focused user questions.

Authorization is scoped to the selected run and ticket/epic. The standard
profile may authorize selected worker chats, worktree/branch creation, Taiga
writes, reviewed push/PR delivery, PR attachment, and one coordinator
heartbeat. It never authorizes automatic merge, force-push, deployment, or
unrelated conversations.
