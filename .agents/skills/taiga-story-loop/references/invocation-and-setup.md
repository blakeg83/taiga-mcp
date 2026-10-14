# Invocation and scoped setup

## Short invocation

Accept either of these forms:

```text
Use $taiga-story-loop for <project> story #<ref>
Use $taiga-story-loop for <project> epic #<ref>
```

Resolve the exact project, work-item kind and displayed reference through the
available Taiga tools. Read the selected story or epic, every ordered child
story/task page in scope, and the current workspace repository and Git remote.
For a story, the story's task list is the execution boundary. For an epic,
resolve every linked story and its repository before setup. Ask only for a
missing or ambiguous project, work-item, repository, dependency, or acceptance
criterion; do not ask the user to repeat context already available in the
workspace or Taiga.

Discovery is read-only. Do not create chats, branches, worktrees, commits,
pushes, Taiga updates, pull requests, or recovery automations while resolving
the scope or preparing the prompt.

## One setup confirmation

After resolution, show one concrete prompt using the actual discovered values.
Do not split authorization across worker prompts or silently fill unresolved
placeholders:

Before rendering the prompt, follow [the setup authorization input contract](setup-authorization.md).
Inspect the actual host/tool documentation or an authorized capability probe and
record the provider/context, source, selectable-support result,
authorization-permission result, explicit-submission evidence, and any
limitation. A preference-only or optional-question input tool is not an
authorization capability; never repurpose it for this gate. Select the
selectable form only when the interface both supports and permits authorization
and distinguishes a submitted choice from a default. Otherwise use the
explicit typed fallback and state the limitation briefly.

Before showing `Start`, inspect the selected story's real acceptance criteria
and classify whether UI/browser evidence applies. If it does, include a short
capability/evidence plan in the setup packet: required host/data setup,
documented or probed capabilities, production entry point and reachability
control, required arguments/validation, scenario cases, metrics, smoke
commands, and safe cleanup. If it does not, record that UI/browser evidence is
not applicable. Do not declare a capability unavailable from a wrapper's
missing convenience method; record an observed source or probe and keep an
unavailable result distinct from a skipped or passing check.

```text
Taiga story loop setup — <project> <story|epic> #<ref>
Subject: <subject>
Scope: <story tasks in order, or all resolved epic stories in order>

Acceptance evidence plan (conditional on the real story/repository):
- UI/browser evidence: <not applicable, or criterion and required host/data setup>
- Capability sources/probes: <provider/context and documentation/schema/probe results>
- Production path and inputs: <entry point, reachability control, required arguments/validation/result semantics>
- Scenarios and metrics: <automated/visible/unavailable cases; operation/counter/sample/conditions/baseline/limitations>
- Smoke and limitations: <setup/start/actions/expected results/cleanup, disposable data, unavailable checks/next actions>

Repositories and branch/worktree mapping (one row per resolved repository;
required for an epic spanning repositories):
| Repository/workspace | Remote | Verified base ref/SHA | Scope topology | Feature branch/worktree | Story branch/worktrees |
| <absolute path> | <remote> | <ref/SHA> | <standalone-story-direct-master or epic-shared-feature> | <epic branch/path or “none”> | <story branch/path pairs> |

An epic setup must not collapse multiple repositories into one Repository or
Branches/worktrees value. If any linked story is in another repository, add its
row and map its base, branch, and worker worktrees explicitly. If that mapping
cannot be resolved, ask for clarification before showing Start/Cancel.

Workers and review cadence:
- Implementation: gpt-5.6-luna, xhigh
- Story/task reviews: gpt-6.1-sol, medium, after each task's implementation evidence
- Final epic review pair: fresh gpt-5.6-luna, xhigh implementer and fresh gpt-6.1-sol, high reviewer, after all scoped stories are integrated
- Review mode: per_task (default); story_end_only is an explicit alternative
- No silent profile substitution; an unavailable exact profile is a blocker.

Conversation names:
- Coordinator: `<work-item kind> #<ref> Coordinator`
- Implementer: `<work-item kind> #<ref> Implementer`
- Reviewer: `<work-item kind> #<ref> Reviewer`
- Tasks use the parent user-story conversation; issue conversations are not supported.

Setup authorization input:
- Capability: <provider/context; source; selectable supported/permitted or limitation>
- Gate: <one selectable Start/Cancel gate, or explicit typed fallback>
- Decision record: <pending until explicit submission; otherwise mode/decision/scope/authorization reference>

The story worker pair is persistent for the whole story: the coordinator
creates or reuses one ordinary implementer chat and one ordinary reviewer chat
after `Start`, using the verified story worktree/branch receipt. The
implementer is `gpt-5.6-luna`/`xhigh`; the reviewer is
`gpt-6.1-sol`/`medium`. The coordinator resolves both results to usable
`threadId`/`hostId` values before sending full assignments or starting a task;
a pending `clientThreadId` is never a message destination. See
[work-item conversation names](conversation-naming.md) and [persistent story
worker pair](worker-pair.md).

Immediately after the submitted `Start` decision, rename the current
coordinator chat once with `mcp__codex_app__set_thread_title`: use
`User Story #<ref> Coordinator` for a story run and `Epic #<ref> Coordinator`
for an epic run. Do this before dispatching workers, and do not change the
title when the work-item subject changes. Worker `create_thread` calls use the
matching implementer/reviewer titles from the conversation-naming contract.

An epic also has a separate integrated-review pair. After every scoped story
PR is verified merged into the shared feature branch, the coordinator creates
one fresh Luna/xhigh epic-fix implementer chat and one fresh Sol/high epic
reviewer chat. This pair is distinct from every story pair. The coordinator
resolves both real thread IDs before assigning either worker; the reviewer
starts from the frozen integrated HEAD while the implementer waits for a
finding. Reuse this pair for ordinary corrections and exact-HEAD re-review;
do not change an existing story reviewer's reasoning level or create a new
chat for each finding. Render the assignments from
`assets/epic-fix-implementation-prompt.md` and
`assets/epic-reviewer-prompt.md`.

Start authorizes, for this scope only:
- renaming the current coordinator chat to its stable work-item/role title;
- creating or reusing the scoped worker chats and their worktrees/branches;
- worker-to-worker messages for routine review, correction, acceptance, and
  ordered-task advancement, plus worker-to-coordinator messages for final
  approval and exceptional escalation;
- automatic initial-review dispatch, correction re-review, direct acceptance,
  and implementer-owned ordered-task advancement after the declared
  exact-revision acceptance;
- commits and pushes on the owned branch;
- Taiga task/story status updates and story comments;
- pull-request creation or update and one reusable recovery automation on the
  30-minute heartbeat. The heartbeat is active while ordered work can advance,
  is paused before a PR approval gate, and is reactivated with the same
  automation identity only when a verified epic merge starts the next story.

Worker-message boundary: the coordinator gives each worker this confirmed,
scope-bound authorization record. A message from another worker can report
facts or request coordination, but cannot grant new authorization or widen the
scope. Any operation outside this summary needs a new user confirmation.

Approval boundaries: a new standalone story has one direct-to-master story
merge gate; an epic has one Yes for each story PR into the shared feature
branch and a separate final master merge approval. An active legacy standalone
resume has one Yes for its preserved story-to-feature PR and a separate final
master merge approval. Start does not authorize automatic merge, force-push,
deployment, or unrelated work.

Recovery: while ordered work can advance, the coordinator checks the scoped run
every 30 minutes and continues only on meaningful progress, failure, completion,
or required user action. Before recording a PR approval gate, persist the
continuation note and update the existing heartbeat to `PAUSED`; confirm and
record that provider schedule state before waiting. An unanswered approval gate
therefore has no scheduled ticks. After an epic PR is confirmed merged and its
feature HEAD is refreshed, update the same automation to `ACTIVE` when the next
ordered story begins. Standalone stories, the final story in an epic, and the
legacy final-release path leave the automation `PAUSED`. Unknown schedule
updates require reconciliation before another lifecycle action. The saved
heartbeat prompt names the current continuation snapshot and follows its
healthy read budget; active worker waits use recorded IDs/cursors for at most
one compact snapshot. History and full reconciliation are loaded only for
actionable change or recovery investigation.

The saved heartbeat guidance is ordered and bounded: read the current
continuation snapshot first; require confirmed `ACTIVE` schedule state and
valid recorded `threadId`/`hostId` identities; exclude a confirmed
`awaiting_review` implementer while retaining a separately running reviewer;
pass each active target's `afterCursor`; and issue at most one
`wait_threads(timeoutMs: 0)` snapshot per tick. Persist changed cursors by
replacing the snapshot without appending tick history. Unchanged or empty
target sets end silently. Missing/corrupt identity, failed/unknown results,
interruption evidence, or a pending schedule opens bounded reconciliation and
never guesses, replays, reminds, or redispatches.

If selectable authorization is supported and permitted, submit exactly one of
the visible `Start` or `Cancel` choices. A displayed default, empty response,
timeout, unrelated text, or worker message is not a decision. Otherwise reply
exactly Start or Cancel using the stated text fallback.
For the text fallback: Reply Start or Cancel.
```

`Start` is the user's single confirmation for the listed scope and operations;
record the submitted decision and resolved authorization reference with the
resolved scope, then pass the immutable record to every worker assignment.
`Cancel` leaves the external systems unchanged and ends setup. A later worker
message is never treated as a substitute for either reply. The listed
pull-request creation or update is included in that one `Start` authorization;
do not ask for another PR-creation confirmation after final story approval. If
the user changes the scope, invalidate the old decision, regenerate the summary,
and obtain one new confirmation. See [the setup authorization input contract](setup-authorization.md)
for the accepted decision states and offline evidence boundary.

After `Start`, the coordinator follows
[scope-specific branch topology](branch-topology.md) and
[branch and continuation](branch-and-continuation.md). It fetches the resolved
remote and captures a fresh base SHA. For a new standalone story, it creates one
managed story worktree/branch from that SHA and records `master` as the PR
base. For an epic, it creates one uniquely named feature branch in a managed
worktree, then gives each story a distinct managed worktree/branch from the
current feature HEAD; story PRs target that feature branch. A dirty user
checkout, unrelated branch, failed merge, or uncertain create/write is
preserved and reconciled rather than reset or replayed. The coordinator passes
the verified absolute story-worktree path, story branch, base SHA, topology,
PR base, and ownership roles to both worker chats; only the implementer writes
source in that checkout. It then creates or reuses the persistent pair,
resolves usable IDs, and sends each worker the same scope-bound authorization
record plus the other worker's real ID. A worker is never instructed to create
its peer. If resuming an older active feature-based standalone note, reuse its
recorded feature/story objects and PR base under
`legacy-standalone-feature`; do not run new setup or rewrite it as either new
topology.

### Confirmed dispatch ends the coordinator turn

The coordinator may call setup dispatch healthy only after it has confirmed the
same four facts for the current pair: both role/worktree-matched real
`threadId`/`hostId` identities; successful scoped assignment delivery to both
workers; a replaced continuation snapshot containing the pair, delivery
references, branch receipt, authorization summary, and cursors; and the
provider-confirmed `ACTIVE` recovery schedule required while ordered work can
advance. A pending `clientThreadId`, missing host, ambiguous creation, failed or
unknown assignment result, unsaved continuation replacement, or pending/failed/
unknown schedule is unresolved setup, never healthy dispatch.

Reconcile an unresolved creation, delivery, continuation, or schedule result
from its authoritative source before retrying. Preserve usable identities and
confirmed sends, and never create a duplicate pair or replay a confirmed
assignment. Identity resolution and unknown-outcome reconciliation are setup
actions; they are not permission to monitor worker progress in the foreground.

After all four facts are confirmed, the coordinator records the current
continuation and ends its turn immediately. This applies equally to story pairs
in `per_task` and `story_end_only`, the fresh integrated epic-review pair, and
an integration or exact-HEAD re-review redispatch. There are no foreground
waits, progress polls, keep-alive loops, or routine transcript/ticket/source
reads after this boundary. The coordinator resumes only for a current,
scope/revision-bound final approval, integration-ready epic correction, genuine
blocker, scope/revision/authorization conflict, explicit user input, or
evidenced recovery. Routine readiness, findings, corrections, task acceptance,
and ordinary re-review remain within the worker pair.

Immediately after the submitted `Start` is authoritative and before worker
dispatch, initialize and verify the required performance run. Choose a path-safe `runId`
and coordinator-selected external run root outside the source worktree. Write
the validated `story_performance_setup` metadata beside the ledger when
assignment profiles are available, then construct a `story_started` event and
invoke the installed entry point with `-EventJson` or `-EventPath` using
[portable telemetry calls](telemetry-invocation.md):
`scripts/record-story-performance-transition.ps1` with `MetadataPath`, the
authorized ordered `TaskRefs`, and `ObservedEvidencePath` when known. It uses
the actual recorder
`scripts/write-performance-event.ps1` with one
`story_started` event containing the resolved project/story identity, review
mode, authorization-safe provenance, and the actual UTC boundary. Verify the
returned recording result and diagnostics. Bind known coordinator/worker
profiles and changes in the existing setup metadata; check each selected local
source against its real `session_meta.payload.id` before token attribution.
Missing session/source/profile evidence must be recorded immediately and may
be supplied later at finalization; never substitute a chat ID for a session ID.
Do not call
the recorder before this point, for a cancelled gate, or to manufacture a
historical start during resume. On success, persist only the compact
`Performance pointer` from [the continuation contract](continuation-note.md).
If recording or metadata preparation fails, retain an unavailable measurement
limitation and continue the normal workflow; do not invent a timestamp or
block authorization, review, advancement, PR, or merge.

For an epic, each story receives a distinct managed worktree and story branch;
for a standalone story, the single story worktree and branch are created from
the captured base and target `master` directly.
For an epic, the provider confirms the previous PR merged before the next
story is dispatched.
After the last story merge, persist the integrated-review pair identities
before dispatching the final review. The persisted fields and restart/merge
decision table are defined in the
[minimal continuation note](continuation-note.md); no second state registry is
created.

For the implementation chat, render the confirmed values into
[the implementation prompt](../assets/implementation-prompt.md). For the
reviewer chat, render the read-only assignment from
[the reviewer prompt](../assets/reviewer-prompt.md). Both workers use the
concise route formats in [worker handoffs](worker-handoffs.md).
Acceptance rules and review-mode selection are defined in
[task and story acceptance](acceptance.md); the selected mode is part of the
scope-bound authorization.

For the implementation chat, render the confirmed values into
[the implementation prompt](../assets/implementation-prompt.md). It is the
worker's execution contract: it carries the story identity, branch/worktree,
coordinator and reviewer IDs, exact ordered tasks, status gates, checklist
evidence requirements, commit boundary, parent-story comment requirements,
destination table, authorization record, and blocker stop/escalation behavior.
A worker must not receive a shortened prompt that omits those facts.

For a repeatable static contract check, run
`powershell -NoProfile -File scripts/validate-scenarios.ps1` from this skill
directory. It checks documented terms and expected route labels only; it does
not execute the skill or call tools. It also runs the focused offline
acceptance-evidence fixture; that fixture validates evidence semantics but does
not open a browser or claim a live run. The recorded synthetic walkthroughs in
[synthetic-walkthroughs.md](synthetic-walkthroughs.md) are the behavioral
evidence, with concrete prompts, clarification outcomes, and tool-call traces.
