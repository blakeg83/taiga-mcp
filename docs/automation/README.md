# Taiga ticket-loop automation

This repository contains an explicitly invoked repo-local skill at
`.agents/skills/taiga-ticket-loop/`. It coordinates ordinary Codex chats
outside the .NET MCP server. It is not installed globally and it does not
start a chat, schedule a heartbeat, write Taiga, push a branch, create a PR,
merge, or deploy merely because the files exist.

The offline core is PowerShell 7:

```powershell
pwsh -NoProfile -File tests/automation/Test-Automation.ps1
```

The harness uses synthetic state and Taiga/provider observations plus a local
bare Git remote. It does not contact live Taiga or GitHub. Actual host and
provider smoke evidence remains separate from fixture success.

## Explicit operational start

Invoke the skill after selecting the exact issue, task, story, or epic and
authorizing the required actions. The coordinator discovers the current
workspace repository, Git common directory, repository instructions, Taiga
context, status mappings, and validation commands when they are available. For
TaigaMCP it verifies and uses freshly fetched `origin/master` automatically;
you do not need to repeat the repository path, remote, or base branch.

The shortest useful invocation is:

```text
Use $taiga-ticket-loop with the standard authorized-run profile for ticket/epic
42 in the GroceryRecipeWizard project.
```

The reusable profile authorizes the selected worker chats, worktree/branch,
Taiga progress updates, reviewed push/PR delivery, Codex PR attachment, and one
coordinator heartbeat for continuation/merge observation. It excludes automatic
merge, force-push, deployment, branch deletion, credentials, unrelated scope,
and writes outside the selected ticket/epic. Add dependencies, validation
commands, status choices, or a different repository mapping only when they are
not discoverable or differ from the defaults. Automatic merge and force-push
remain off. The full copyable template is in
`.agents/skills/taiga-ticket-loop/assets/operational-invocation-template.md`.

The implementer is exactly `gpt-5.6-luna` with `xhigh`. The reviewer is exactly
`gpt-6.1-sol` with `high`. The current planning host advertised
`gpt-5.6-luna/xhigh`, `gpt-6-sol/high`, and `gpt-6-astra/medium`, but not
`gpt-6.1-sol/high`; an operational run must therefore stop at preflight until
the requested reviewer identifier is available. No silent fallback is allowed.

## State and recovery

State is outside all worktrees at
`%LOCALAPPDATA%/TaigaMCP/agent-review-automation` by default. Use
`-StateRoot` for a disposable fixture. The registry contains a schema version,
CAS revision, sessions, ticket claims, repository/host reservations, actions,
worker cursors, evidence, and bounded events. Writes use an exclusive short
lock, a flushed same-directory temporary file, atomic replacement, and a valid
`.bak` snapshot. Inspect first after a crash; a pending or uncertain action is
reconciled against its target before another call. Do not free an uncertain
slot merely because its lease expired.

Ticket controls are scoped. Pause/cancel requests stop future dispatch and
record whether workers are actually quiescent; resume revalidates chat,
checkout, source, scope, and pending actions. Waiting for a dependency or merge
releases execution capacity but retains ownership. Duplicate ticks and stale
revisions are rejected.

## Branch, review, and PR evidence

Each executable ticket fetches its configured remote and records a fresh base
SHA before creating a unique `codex/<kind>-<ref>-<slug>-<run-suffix>` branch and
managed worktree. The reviewed `base..HEAD` revision must equal the pushed PR
head. Target movement, source edits, changed requirements, or new material PR
feedback invalidate approval and return through the same implementation/review
chats. The default review budget is initial round 0 plus three corrections.

One PR is created or reused per executable leaf/story ticket. PR delivery,
checks, merge provenance, and Taiga Done are separate facts. Default leaf Done
requires an observed merge; an epic additionally requires every required story
merged and combined acceptance at the integrated revision. Closed-unmerged PRs,
missing checks, response-lost writes, and ambiguous observations require
reconciliation or user input, never blind replay.

## Recovery commands

Inspect a run:

```powershell
pwsh -NoProfile -File .agents/skills/taiga-ticket-loop/scripts/workflow-state.ps1 `
  -Operation inspect
```

Use the exact configured root with `-StateRoot` when inspecting a non-default
run. The helper emits structured JSON and a nonzero exit code for malformed
input, stale revisions, invalid transitions, terminal dispatch, conflicts, or
missing recovery evidence. It never executes model output or ticket text.

The host coordinator must reconcile unresolved desktop, Taiga, Git, GitHub, and
heartbeat actions using their receipts. A pending `clientThreadId` is not a
usable worker ID. A timeout or commentary is not a completed result. A failed
final Taiga update preserves verified PR/merge evidence and remains in
`finalizing` or `needs_input` rather than restarting implementation.

## Scope and limitations

The helper is local and one-host: human interference and cross-host claims are
outside its locking guarantee. GitHub CLI/connector authentication, actual
chat/schedule availability, check providers, squash/rebase provenance, and
live Taiga permissions require a separately authorized smoke exercise. The
skill does not implement automatic board-priority discovery, automatic model
selection, automatic merging, stacked PRs, deployment, plugin distribution, or
an SDK runner.
