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
- [coordinator boundaries](references/coordinator-boundaries.md) for allowed
  inputs, prohibited engineering work, and result routing;
- [review loop](references/review-loop.md) for revision-bound findings and
  correction rounds;
- [Taiga, Git, and PR operations](references/taiga-git-pr.md) for context,
  status mapping, branch, provider, and merge evidence;
- [scheduling and epics](references/scheduling-and-epics.md) for concurrency,
  dependency, and parent acceptance rules.

## Entry procedure

1. Discover the current Codex workspace repository and its Git common directory.
   For TaigaMCP, verify `origin/master` and use it as the default base. For
   another repository, resolve its configured remote/base mapping. The user
   does not need to repeat repository path, remote, or base when the workspace
   and mapping are unambiguous.
2. Confirm the selected ticket or epic scope and explicit authorization. Infer
   safe defaults for the rest: two active pipelines per repository, a
   120-minute elapsed budget, three correction rounds, `origin/master` for
   TaigaMCP, `leafDonePolicy=merged`, no automatic merge, no force-push, and no
   subagents. Ask only for missing ticket scope, dependency decisions,
   validation commands, status mappings, or authorization that cannot be
   discovered safely. A plan or skill invocation alone does not authorize
   external writes.
   Keep the coordinator within the [role boundaries](references/coordinator-boundaries.md):
   it reads dispatch context and provider/Git metadata, but leaves source
   investigation, diff review, checks, diagnosis, and technical findings to
   workers.
3. Run the host preflight and record observed capabilities. If a requested
   capability or exact model/effort is unavailable, stop with a report; do not
   silently fall back to subagents, another model, or an SDK/private API.
4. Initialize or inspect the external state registry with
   `scripts/workflow-state.ps1`. The helper performs bookkeeping only. It never
   calls a desktop tool, Taiga, Git, GitHub, or a shell command from ticket
   text.
5. Resolve complete Taiga context and capture a scope hash. For a story, route
   selected child tasks into the story run. For an epic, enumerate every linked
   story and resolve every repository before dispatch.
6. Before each executable ticket, fetch the configured remote under a short
   ref lock, capture the immutable base SHA, create a unique
   `codex/<kind>-<ref>-<slug>-<run-suffix>` branch/worktree, and verify the
   receipt. Never reset the user checkout or reuse an unrelated branch.
7. Create or reuse one ordinary Luna `gpt-5.6-luna`/`xhigh` implementation
   chat and one ordinary `gpt-6.1-sol`/`high` reviewer chat. Preserve real
   thread IDs; a pending client ID is
   not usable. One ticket has one writer, while independent tickets may run in
   separate worktrees up to configured limits.
8. Freeze the committed implementation revision, dispatch the review, and route
   changes back to the same implementation chat. Initial review is round 0 and
   correction/re-review is limited to three rounds by default. A pass is not a
   PR or Done receipt.
9. After current review, push only the owned branch, reconcile the remote head,
   create or update one matching PR, attach it to the relevant Codex chat, and
   link the milestone in Taiga. Automatic merge and force-push are disabled.
10. Observe checks and merge provenance. Default leaf completion requires a
   verified merge and acceptance evidence. Epic completion additionally
   requires all required stories merged and combined acceptance at the actual
   integrated revision.
11. On every wake, inspect state and reconcile pending actions before dispatch.
    Keep unchanged waits quiet. Pause and cancel are intent-then-reconcile
    controls: quiesce workers, prove no pending/uncertain actions, then record
    the terminal phase and release the slot. Resume and uncertain outcomes are
    explicit states; never resolve them by blind replay.

## Standard authorized-run profile

You may use the phrase `standard authorized-run profile` as a reusable explicit
authorization. It authorizes the coordinator, for the selected ticket or epic
only, to create or reuse the implementation/reviewer chats, message those
chats, create managed worktrees and feature branches, write Taiga milestone
comments/statuses, push the owned reviewed branch, create or update its PR,
attach the PR to the relevant Codex chat, and create or reuse one coordinator
heartbeat for continuation and merge observation.

It does not authorize automatic merge, force-push, deployment, branch deletion,
unrelated chats or tickets, credentials, or live writes outside the selected
scope. The exact worker profiles remain `gpt-5.6-luna`/`xhigh` and
`gpt-6.1-sol`/`high`; an unavailable profile is a preflight blocker.

The shortest valid operational start is: "Use `$taiga-ticket-loop` with the
standard authorized-run profile for Taiga issue/story/task/epic X in project Y."
The
coordinator should discover the current repo, verify the fresh base, load
status mappings and repository instructions, and ask focused questions only
when discovery cannot resolve them. The user must still state the selected
scope; the named profile supplies the scoped operational permissions, but those
permissions cannot be inferred from the working directory alone.

Tests use synthetic Taiga/GitHub data and local bare remotes only. See
`docs/automation/README.md` for installation, runbook, and recovery examples.
