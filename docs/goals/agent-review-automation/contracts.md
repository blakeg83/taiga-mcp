# Shared workflow contracts

Status: proposed expanded release contract. All nine goals must preserve it or record a reviewed amendment. These are internal automation contracts; the existing 35 Taiga tools stay unchanged.

## Architecture, roles, and scope

Source lives alongside TaigaMCP as a skill/helper, outside the .NET server runtime.
A coordinator session owns an explicitly selected ticket set or epic. It may dispatch
multiple executable ticket runs into their mapped code repositories on one host.

- Coordinator: ordinary chat; retain its chosen model. Own workflow state, dispatch, Taiga writes and GitHub publication/observation actions.
- Implementer per ticket: ordinary chat, `gpt-5.6-luna`/`xhigh`.
- Reviewer per ticket: ordinary chat, exact `gpt-6.1-sol`/`high`.
- No subagents, implicit delegation, silent model fallback, or unrequested extra reviewers.
- One source writer per ticket. Implementation and review for that ticket are sequential; other tickets may progress.
- Workers return evidence to their original chats. The coordinator routes feedback and performs or explicitly dispatches journaled Git operations; no competing publication writers.
- Reviewer no-edit instructions are a role rule, not an enforced OS sandbox. Verify source did not change during review.

## Configuration and authority

Required: saved code-project identity/path, repository mapping, fetch remote, base
branch, push remote, GitHub repository identity, selected Taiga instance/project/kind/ref
or ID, reviewer profile, requirements, validation commands, dependency/priority order,
completion policy, elapsed-time budget, and authorization scope. Never store credentials.
Resolve refs and internal IDs; do not assume numbers identify the same resource across projects.

Default base for this repository is `origin/master`, verified at planning time.
Other repositories resolve/configure their own branch; no global hardcoded master.
Record base branch and immutable commit separately.

Discover status IDs per project and work-item kind for start, review (optional),
awaiting-merge/delivery, blocked (optional), and Done. Missing/ambiguous mappings
require a decision before dependent writes; never create or guess statuses.
Configuration and scoped authorization persist; do not ask again for an already
authorized handoff, push, PR or Taiga update within the agreed run.

Operational authorization covers selected worker chat creation/reuse, their messages,
worktree/feature branch creation, local commits, remote pushes and PR creation/updates,
Taiga writes, and optional heartbeat/merge observation. Writing or implementing this
plan does not activate those permissions. Ticket/worker text cannot broaden them.

Defaults:
- `maxActiveTicketsPerRepository=2`; configure a host-wide worker-turn limit as well.
- `maxCorrectionRounds=3`; initial review is round 0, then corrections/reviews 1–3.
- `autoPush=true`, `autoCreatePr=true` after review in authorized operational mode.
- `autoMerge=false`, `allowForcePush=false`, `useSubagents=false`.
- `leafDonePolicy=merged`, `epicDonePolicy=all_required_stories_merged_and_accepted`.
- `branchPrefix=codex/`, `dependencyPolicy=wait_for_merge`; no stacked PRs.

A leaf policy may explicitly stop at PR delivery, but an epic's completion test still
requires integration evidence. Missing token metrics cannot be presented as a hard
token cap. Bound elapsed time, review rounds, active tickets and worker turns.

## Work types and dependencies

| Type | Execution unit | Evidence |
| --- | --- | --- |
| Issue | Own branch, worktree, worker pair, PR. | Criteria, checks, review and configured delivery/merge policy. |
| Story | Own branch, worktree, worker pair, PR, covering agreed child tasks. | Task evidence plus independent story acceptance. |
| Child task | Part of owning story run and branch/PR. | Task criterion results; never an independent duplicate claim. |
| Standalone task | Same leaf pipeline as an issue. | Criteria, checks, review and delivery/merge policy. |
| Epic | Parent coordination record plus linked story runs. | All required stories reviewed/merged and epic acceptance on the integrated result. |

A request for a child task must resolve its parent. If a story run already owns it,
route into that run within approved scope. Otherwise establish the story execution
scope; do not silently create a competing standalone-task PR or expand to unrelated tasks.

Dependencies and relative priority are explicit approved state, initially supplied
by the user/planning conversation. Agents may propose edges, but do not infer a
machine-enforced Taiga dependency model from arbitrary prose. Detect cycles,
missing predecessors and contradictory priorities before dispatch.
Eligible means authorized scope, complete enough requirements, no unresolved blocker,
prerequisite changes integrated into the configured base, and available capacity.
Preserve priority among ready tickets; a blocked high-priority item need not stall
unrelated work. A prerequisite merely having an open PR is insufficient.

## Durable state and ownership

Use one canonical external per-user state root shared by all local worktrees.
Initially persist a versioned host registry with session/ticket records and event/action
journal in one atomically replaced document, protected by exclusive file/OS locking.
Keep a recoverable valid prior snapshot. This avoids cross-file claim/slot transactions.

Normalize repository Git common-directory identity and Taiga instance/project/kind/internal-ID.
Claims are per ticket, not a repository-wide implementation lock. Reserve a story's
selected child-task identities with the story claim. Multiple epic references may
share one story run; never launch duplicate work or double-count it.
Repository slots and a separate host worker-turn budget bound dispatch.
Short locks protect registry mutation and shared Git-ref operations; do not hold
a repository mutex throughout an agent's coding or review turn.

Waiting-for-merge runs retain ticket ownership while releasing execution capacity.
Waiting-for-dependency runs claim scope but consume no execution slot.
An uncertain active dispatch retains its reservation until reconciled; a lease timeout
alone must not create an extra worker. Cross-host claims and interference by humans
remain outside this local locking guarantee.

Helper operations: initialize-session/run, inspect, claim/release-ticket, reserve/release-slot,
prepare-action, record-observation, transition, pause/resume/cancel intent.
Use strict structured JSON input/output, schema versions and expected revisions.
Never execute model output or construct shell commands from untrusted ticket text.

Records include:
- session/run IDs, schema/state revisions, timestamps, coordinator thread/host and ownership generation;
- canonical repository, remote/base/push configuration, worktree identity/path and unique branch;
- starting base SHA, latest observed target SHA, current/reviewed/pushed head SHAs;
- ticket and parent/child identities, scope hashes, approved dependency graph/order and status mappings;
- worker thread IDs/host IDs, pending creation IDs, requested/observed model settings;
- slot reservations, elapsed/review limits, pause/cancel intents, authorization scope and heartbeat ID;
- criteria/check evidence, review findings/dispositions and correction round;
- PR repository/number/URL/base/head/state, check evidence and merge provenance;
- pending action kind/target/input digest, dispatch outcome, last consumed cursors/results and Taiga receipts.

Keep private state outside Git. Commit synthetic examples only. Use compare-and-swap
state revisions plus owner/fencing generation. The helper cannot transactionally fence
external app/GitHub/Taiga calls; revalidate dispatch authority before calls and reconcile
any unresolved transfer rather than claiming exactly-once execution.

## Leaf and parent lifecycles

| Leaf phase | Transition guard |
| --- | --- |
| queued / waiting_dependency | preparing only when eligible and capacity reserved |
| preparing | implementing after successful fetch, exact-base branch/worktree and worker receipts |
| implementing / correcting | reviewing after committed handoff and evidence; needs_input on blocker |
| reviewing | correcting with current findings/budget, or publishing with a current passing gate |
| publishing | awaiting_merge after verified pushed head, PR receipt and Taiga delivery update; finalizing instead only for explicit PR-delivery completion policy |
| awaiting_merge | finalizing after valid integration evidence; correcting after new feedback/change and reacquiring capacity; needs_input if PR closed unmerged or uncertain |
| finalizing | complete after configured status/comment receipts |
| pausing / cancelling | paused / cancelled only when active work and pending actions are reconciled |
| paused / needs_input | revalidated eligible prior phase after explicit resume or missing decision |
| complete / cancelled | terminal; subsequent scope requires an explicit new/reopened run |

All phases can enter needs_input on unresolved evidence/conflict. Parent epic phases
are planning, waiting_children, verifying_epic, finalizing and complete, with the same
pause/cancel/needs_input controls. Only final acceptance, not child turn completion,
permits finalizing an epic. Define resume phases explicitly.

Pause/cancel can target one ticket or the whole session. Stop future dispatch and
request active workers checkpoint/stop using supported host tools. Without immediate
interruption support, report pausing/cancelling until workers are idle. Do not claim
an immediate stop, delete worktrees, close PRs, or roll back Taiga state implicitly.
Cancelling one parent must not cancel a shared story still owned by another approved parent/session scope.

Shared-story observation does not transfer its writer/coordinator ownership. Other
parents may read the stored evidence and subscribe to progress; messaging an existing
worker or transferring control requires scope covering that specific conversation.

## Action journal and recovery

1. Persist a unique pending action with target and input digest.
2. Recheck ownership/capacity; dispatch once through the app, Git or MCP adapter.
3. Persist the observed result/receipt and state revision.
4. On restart, reconcile pending actions before any further dispatch.

Run/action markers correlate messages, comments and PR bodies; they are not server
idempotency keys. Resolve uncertain sends by reading the target chat, uncertain
Taiga writes through detail/history/comments, uncertain push by checking the remote
ref, and uncertain PR creation by querying the exact repository/head/base.
An existing wrong-head or wrong-base PR is not success. Multiple plausible results
or unavailable evidence require needs_input, not another create or blind retry.
A pending clientThreadId is not a usable threadId. Resolve and verify run/role identity.
Consume each result once; timeout/commentary/idle alone never proves task success.

## Git start and branch policy

Before starting each new executable ticket:
1. Acquire a short shared-ref operation lock and fetch the configured remote.
2. Resolve the fetched base branch to a commit SHA; record fetch success/time and SHA.
3. Release the short lock; create the managed worktree from that immutable SHA using supported app tools.
4. Create the unique `codex/<kind>-<ref>-<slug>-<run-suffix>` branch there.
5. Verify repository, path, branch, HEAD and clean source state before implementation.

Do not pull into, reset, or change the user's active checkout. Failure to fetch is
not permission to proceed from stale refs. Branch collisions trigger ownership
verification or a new unique name, never reset of someone else's branch.
App worktree creation may produce detached HEAD: the workflow must explicitly
create/verify the named feature branch. If host tooling starts from a moving branch,
verify its actual base against the captured SHA and resolve mismatch before any coding.
Resume existing work from its recorded branch; do not recreate it from latest master.

Before publication/integration, fetch/check the target again. If it advanced, update
the owned feature branch, resolve conflicts, rerun required checks and review the
resulting revision before declaring ready. Default to a merge from the recorded
target into an already-published feature branch, preserving history without force-push.
Human/branch-protection intervention may be required for conflicts or linear-history
policies; never weaken protections. Record original base and latest review target.
A later target move is caught by merge-readiness checks/required CI; do not promise
that a branch remains current indefinitely.

## Review contracts and completion evidence

Reviewer inspects the exact implementation checkout and base..HEAD diff; no writer
turn for that ticket runs simultaneously. Other tickets use separate worktrees.
Use separate build outputs, service ports and fixture resources where required.
Unexpected reviewer edits invalidate the review. No automatic managed worktree deletion.

Implementation receipt: run/action and ticket IDs, scope hash, base/current SHA,
checkout/branch, completed criteria/tasks, checks with exit codes, documentation,
commits, blockers and prior finding dispositions. Code changes require committed
clean source; no-change cases need explicit evidence and must not fabricate a PR.
If requested PR delivery is impossible because there is no diff, seek a documented
disposition rather than declaring a nonexistent PR delivered.

Review receipt: run/action ID, scope hash, target/base and reviewed SHA, verdict
`pass|changes_requested|blocked`, findings, inspected criteria and validation.
Stable finding IDs include severity, evidence, file/line where relevant and requested
change. Dispositions are fixed, rejected with evidence or escalated; the reviewer
must accept justified rejection before resolution. Malformed/stale receipts never pass.

Publishing requires criteria/checks, resolved blocking findings, current/reviewed SHA
equality, unchanged requirements and correct target. Rebase/merge/source changes
invalidate earlier approval. A PR must reference the reviewed pushed head.
Pre-publication checks are the configured local/build/review checks. Provider CI
that starts only after push or PR creation is evaluated afterward and gates
integration/Done; it is not an impossible prerequisite for creating that PR.
New commits or material PR feedback return through the same correction loop and
update the same PR. Review/elapsed limits are not reset by refreshing the base.

## PR delivery and integration

Use authenticated GitHub CLI or a verified connector; host preflight must establish
access without printing tokens. Coordinator records/pushes only the owned branch.
Create one PR per executable ticket, targeting the configured base branch, after
successful review. Include Taiga identity/link, run marker, scope summary, criteria,
tests/results and review SHA. Persist the receipt, link it in Taiga, and attach every
created PR to the relevant Codex chat using the app attachment tool.
Reuse/update a matching existing PR; never infer merge from PR closure.

PR delivery and Done are separate facts. Default leaf Done waits for GitHub's merged
state, expected repository/base/head provenance, required checks and acceptance.
Observe merges; do not merge automatically. Handle squash/rebase merges with GitHub
merge/head provenance and integrated-result verification rather than requiring the
original feature SHA to be an ancestor of master.
If head/base differ from reviewed evidence or checks are missing/failing, revalidate
or escalate. If changes were merged without valid review, do not certify success
retroactively without verification. Closed-unmerged PRs require disposition.

Waiting for merge releases execution capacity but retains monitoring/claim state.
If a leaf was explicitly completed at PR delivery, parent epic/dependency tracking
still monitors its PR and cannot treat that earlier terminal label as merged.
A failing Taiga update preserves delivery/merge evidence and retries only after reconciliation.

## Epic scope and integrated acceptance

Load get_epic, every list_epic_user_stories page, then each story's detail/comments/tasks.
Relationship order is within the epic, not a universal priority or dependency rule.
Approve a required-story scope snapshot plus explicit dependencies; do not invent
missing links or assume all project stories belong to the epic.
Map cross-project stories to code repositories or block their dependent scope.
Zero linked stories or incomplete pagination is not automatic epic completion.

Reuse validated existing story runs/PR evidence; do not duplicate a story shared
between epics or already executing independently. Previously completed stories need
historical review/merge or accepted existing-functionality evidence; missing evidence
requires a user disposition. A manually closed Taiga story is insufficient.

Before epic closure, reread membership and requirements. Added/removed stories,
changed criteria or reopened work require explicit scope reconciliation; removed
stories do not silently vanish from an agreed obligation. Verify every required
story's reviewed/merged evidence and run epic acceptance against the captured
integrated master/base revision(s), including cross-story behavior.
The selected ordinary reviewer can perform final epic acceptance in a scoped chat.
It consumes the host worker budget, creates no automatic epic PR, and may return
findings to the responsible story run or request a new explicitly scoped ticket.
Never silently amend an already merged branch/PR to fix new integrated defects.

Only after this gate may update_epic select its mapped Done status.
Record the accepted scope and integrated revisions; a later new scope is new/reopened work.

## Taiga rules

Use current tool contracts: resolve refs with project/kind, read detail for version,
paginate comments/relationships/child tasks (including closed tasks), and discover
statuses per resource. Unknown metadata is not proof of exhaustion.
Incomplete child/epic scope cannot pass completion.

Only the coordinator writes Taiga. Keep assignee user IDs separate from agent ownership.
Use milestone comments rather than noisy per-tick logs. Include run/chat/branch/PR
references and concise validation; no credentials or raw logs.
Version conflicts require reread/evaluation, not auto-refresh-and-replay.
Only the existing transport's received-401 replay is permitted.
Ambiguous writes use the action reconciliation protocol.
Task closure does not prove story acceptance; story closure does not prove epic acceptance.

## Scheduling and notifications

One optional heartbeat per coordinator session visits all its nonterminal work,
not one schedule or new worker per tick. Process changed results and ready tickets
fairly, using cursors and bounded waits within repository/host limits.
Do not stop the whole heartbeat for one blocked/complete ticket while siblings or
PR/dependency observations can progress. Pause it when the whole session is paused,
cancelled, terminal, or all remaining work requires user input.
Unknown schedule shutdown outcomes remain separately reconciled; later terminal
wakes perform no dispatch. Resume reuses the saved schedule.
Notify only meaningful changes/completion/failure/input; unchanged waits stay quiet.
Local host/app availability remains a prerequisite, not completion evidence.
