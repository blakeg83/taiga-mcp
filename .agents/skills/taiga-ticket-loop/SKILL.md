---
name: taiga-ticket-loop
description: Run an explicitly authorized, evidence-driven Taiga ticket or epic implementation and review loop across ordinary Codex chats, isolated worktrees, and pull requests.
---

# Taiga ticket loop

Use this skill only when the user explicitly invokes it for a selected Taiga
issue, task, story, or epic. It coordinates ordinary implementation and review
chats; it does not create subagents, use private desktop APIs, or infer
permission to write Taiga, push branches, create pull requests, or schedule a
heartbeat.

The coordinator owns the workflow and is the only writer to Taiga, GitHub, and
the local state helper. Workers return receipts to their original chats. Read
the relevant reference before each operation:

- [host contract](references/host-contract.md) for capability preflight,
  exact model profiles, and authorization boundaries;
- [state contract](references/state-contract.md) for the durable helper and
  recovery protocol;
- [roles and handoffs](references/roles-and-handoffs.md) for ordinary worker
  prompts and checkout receipts;
- [review loop](references/review-loop.md) for revision-bound findings and
  correction rounds;
- [Taiga, Git, and PR operations](references/taiga-git-pr.md) for context,
  status mapping, branch, provider, and merge evidence;
- [scheduling and epics](references/scheduling-and-epics.md) for concurrency,
  dependency, and parent acceptance rules.

## Entry procedure

1. Confirm the selected scope, repository mapping, dependency/priority order,
   status IDs, completion policy, worker limits, and explicit authorization.
   A plan or skill invocation alone does not authorize external writes.
2. Run the host preflight and record observed capabilities. If a requested
   capability or exact model/effort is unavailable, stop with a report; do not
   silently fall back to subagents, another model, or an SDK/private API.
3. Initialize or inspect the external state registry with
   `scripts/workflow-state.ps1`. The helper performs bookkeeping only. It never
   calls a desktop tool, Taiga, Git, GitHub, or a shell command from ticket
   text.
4. Resolve complete Taiga context and capture a scope hash. For a story, route
   selected child tasks into the story run. For an epic, enumerate every linked
   story and resolve every repository before dispatch.
5. Before each executable ticket, fetch the configured remote under a short
   ref lock, capture the immutable base SHA, create a unique
   `codex/<kind>-<ref>-<slug>-<run-suffix>` branch/worktree, and verify the
   receipt. Never reset the user checkout or reuse an unrelated branch.
6. Create or reuse one ordinary Luna `gpt-5.6-luna`/`xhigh` implementation
   chat and one ordinary `gpt-6.1-sol`/`high` reviewer chat. Preserve real
   thread IDs; a pending client ID is
   not usable. One ticket has one writer, while independent tickets may run in
   separate worktrees up to configured limits.
7. Freeze the committed implementation revision, dispatch the review, and route
   changes back to the same implementation chat. Initial review is round 0 and
   correction/re-review is limited to three rounds by default. A pass is not a
   PR or Done receipt.
8. After current review, push only the owned branch, reconcile the remote head,
   create or update one matching PR, attach it to the relevant Codex chat, and
   link the milestone in Taiga. Automatic merge and force-push are disabled.
9. Observe checks and merge provenance. Default leaf completion requires a
   verified merge and acceptance evidence. Epic completion additionally
   requires all required stories merged and combined acceptance at the actual
   integrated revision.
10. On every wake, inspect state and reconcile pending actions before dispatch.
    Keep unchanged waits quiet. Pause, cancel, resume, and uncertain outcomes
    are explicit states; never resolve them by blind replay.

Operational starts should state the selected scope, worker models, repository
and status mappings, and which chat/worktree, Taiga, push/PR, and heartbeat
actions are authorized. Tests use synthetic Taiga/GitHub data and local bare
remotes only. See `docs/automation/README.md` for installation, runbook, and
recovery examples.
