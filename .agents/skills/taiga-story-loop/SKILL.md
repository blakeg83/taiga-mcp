---
name: taiga-story-loop
description: Run an explicitly authorized, scoped Taiga story or epic workflow from concise agent-ready contracts and setup confirmation.
---

# Taiga story loop

Use this skill when a user selects a Taiga user story or epic and wants a
focused, independently invocable workflow. Resolve the selected project,
work-item scope, repository, and ordered child work before requesting approval
for execution.

This skill owns the story-level workflow contract and setup confirmation. It
does not replace `taiga-ticket-loop`, import its helper framework, or alter its
installed copy. Keep story/epic-specific guidance and supporting resources in
this skill directory; generic agent advice and the legacy PowerShell
state-machine machinery remain out of this path.

External writes require an explicit confirmation for the resolved scope. Until
that confirmation, discovery is read-only and the workflow must not create
worker chats, branches, worktrees, commits, pushes, pull requests, Taiga
updates, or recovery automations.

Before setup, read [contracts](references/contracts.md). Use its story and task
templates to preserve the selected requirements, task order, and observable
completion evidence; ask for clarification when those inputs are missing or
ambiguous.

Before showing the setup gate, read [setup authorization](references/setup-authorization.md).
It defines capability intake, the selectable Start/Cancel decision, the
explicit typed fallback, and the authorization record passed to assignments.
Preference-only input must never be repurposed as permission.

After `Start`, pass the confirmed values and ordered task list to the Luna
implementation worker using [the implementation prompt](assets/implementation-prompt.md).
The worker processes one task at a time in the declared order, records direct
checklist evidence, commits each task before advancing, and distinguishes
ready-for-review from reviewer acceptance and merge. A blocked prerequisite or
ambiguous order stops dependent work and is reported to the coordinator and
parent story.

Use [ordered task execution and truthful Taiga updates](references/task-execution.md)
for the project-specific story/task status mapping, Markdown checklist merge,
current-version writes, uncertain-result reconciliation, selective reopening,
and blocker evidence protocol.

Use [work-item conversation names](references/conversation-naming.md),
[persistent story worker pair](references/worker-pair.md), [direct worker
handoffs](references/worker-handoffs.md), and [task and story acceptance](references/acceptance.md)
for coordinator-owned chat creation, concise worker-pair routing, review-mode
gates, and exact-revision acceptance. Use [routing and substantive escalation](references/routing-and-escalation.md)
and `scripts/validate-routing.ps1` for direct routine corrections, stale-
approval, blocker, disagreement, missing-destination, unknown-delivery, and
revision-conflict scenarios. These checks do not create chats or perform live
writes.

Use [automatic review and ordered-task flow](references/automatic-review-flow.md)
and `scripts/validate-automatic-review-flow.ps1` for the scoped event-driven
handoffs. A ready-for-review event dispatches the persistent reviewer once;
current findings, correction-ready handoffs, and exact-revision acceptance stay
direct within the same pair. The implementer owns the current-version Taiga
reconciliation and next-task advancement allowed by the declared review mode;
the coordinator receives only final story approval and exceptional escalation.
Duplicate, stale, idle, scope-changing, and uncertain outcomes remain
coordinator-owned.

The ready-turn endpoint is one successful direct delivery to the assigned
reviewer, followed by the worker-local `awaiting_review` state and one concise
final response. For an initial or correction-ready task handoff, the
implementation-complete Taiga review-ready status (or documented fallback) and
story progress write are already confirmed and frozen in the revision packet;
that provider mapping is not delivery confirmation. For final-story review,
the selected review-mode endpoint is already confirmed instead: per-task review
has exact accepted task closures and progress, while story-end-only has final
implementation-ready evidence, status, and progress. Final-story dispatch
does not rewrite a task or story provider status merely to request review. A
failed or unknown delivery is an exception: it is not worker-local
`awaiting_review`, does not release ordered work, and is not blindly retried;
the coordinator must reconcile it first. After confirmed delivery, the final
response is the last implementer action, with no polling, reviewer read,
keep-alive, source edit, or next-task work.

In per-task review, initial and correction-ready handoffs end the implementer
turn in `awaiting_review`. Authorized reviewer messages resume the same chat;
the implementer never polls the reviewer. Follow the identity/revision and
deduplication checks in [message-driven resume](references/worker-handoffs.md#message-driven-resume).

After exact current-task acceptance and version-safe Taiga reconciliation, use
the [acceptance-to-next-task resume](references/worker-handoffs.md#acceptance-to-next-task-resume)
sequence. It activates only the next declared task and requires concrete
implementation or check evidence in that same resumed turn; a status-only
write, plan, or intention is not advancement. A final task skips activation
and proceeds to one separate whole-story review at the frozen current HEAD.

Use [per-task commits and parent-story progress comments](references/commit-and-progress.md)
for commit boundaries, exact SHA/no-change evidence, completion and blocker
comment markers, resume deduplication, and the distinction between worker
completion, review acceptance, PR approval, and merge.

Use [scope-specific branch topology](references/branch-topology.md) when
creating branches or deciding a PR base. A new standalone story has one story
branch and a direct-to-`master` PR. An epic has one shared feature branch,
per-story branches/PRs targeting that feature, and a final integrated review.
An active standalone run from the older feature-based workflow uses the
documented `legacy-standalone-feature` compatibility path and preserves its
feature branch through final delivery; that value is never selected for a new
run.

Use [reviewed story PR delivery](references/pr-delivery.md) when the complete
story is approved. It defines the coordinator's exact-HEAD preflight, the
topology-specific PR reuse/create identity, review evidence, Taiga/chat
linkage, and the pending approval state. Run
`scripts/validate-pr-delivery.ps1` for its offline fixture; it never performs
provider writes.

Use [the Yes/No story merge gate](references/merge-approval.md) after a PR is
ready. It keeps explicit user authorization separate from PR review and merge
verification, preserves quiet waits, routes changes back to the same worker
pair, and blocks next-story dispatch until the provider confirms the merge.
Run `scripts/validate-merge-approval.ps1` for its offline decision fixture.

For an epic run after all stories are integrated, use [the final integrated epic
review](references/final-epic-review.md). The coordinator creates a fresh
epic-review pair: `gpt-6.1-sol`/`high` reviews the frozen integrated HEAD and
`gpt-5.6-luna`/`xhigh` waits as the correction implementer. The pair is reused
for isolated corrections and exact-HEAD re-review; story-level chats are not
reused and no new chat is created for each ordinary finding. Use the dedicated
[epic reviewer prompt](assets/epic-reviewer-prompt.md) and [epic-fix
implementation prompt](assets/epic-fix-implementation-prompt.md), and run
`scripts/validate-final-epic-review.ps1` for its offline fixture.

Use [final feature-to-master delivery](references/final-delivery.md) for an
epic after its integrated review or for an active legacy standalone resume
after its preserved story merge. A new standalone story merges its reviewed
story PR directly to `master` through the story merge gate. The contract keeps
the approval paths distinct and preserves the exact reviewed HEAD in each.
Run `scripts/validate-final-delivery.ps1` for its offline fixture.

The synthetic ordered-task, failed-check, blocker, review-rejection, and
human-edit scenarios are recorded in
[task-execution-walkthroughs.md](references/task-execution-walkthroughs.md) and
exercised by `scripts/validate-task-execution.ps1`. They are offline evidence,
not a claim of live-provider execution.

Use [acceptance evidence and capability intake](references/acceptance-evidence.md)
for UI/browser criteria and any acceptance harness that wraps production code.
It requires capability discovery before an unavailable claim, a production-path
control that preserves required arguments and validation, provenance-aware
metrics, classified scenario evidence, and executable safe smoke instructions.
The five-case synthetic fixture in
`assets/acceptance-evidence-scenarios.json` is exercised by
`scripts/validate-acceptance-evidence.ps1`; it is not browser or live-provider
evidence.

For authorized execution, read [scope-specific branch topology](references/branch-topology.md),
[branch and continuation](references/branch-and-continuation.md), and
[minimal continuation note](references/continuation-note.md). They define the
fresh-base standalone story branch or epic feature branch, per-story managed
worktrees, topology-specific PR base, merge gates, and compact resume note.
The note is deliberately smaller than a state registry; existing Git, Taiga,
Codex, and pull-request records remain authoritative.

Persist current state by replacing the continuation snapshot, not appending
milestones. Healthy recovery ticks read that snapshot and take at most one
compact wait for an actively running worker; they never wake an
`awaiting_review` implementer. Unanswered user gates stay silent. Follow the
replacement and heartbeat read budget in [minimal continuation note](references/continuation-note.md)
and run `scripts/validate-continuation-note.ps1` for offline persistence and
stale-snapshot recovery checks.

For the shortest entry, use `Use $taiga-story-loop for <project> story #<ref>`
or `Use $taiga-story-loop for <project> epic #<ref>`. Read
[invocation and setup](references/invocation-and-setup.md) before resolving the
scope and showing the single Start/Cancel gate.
