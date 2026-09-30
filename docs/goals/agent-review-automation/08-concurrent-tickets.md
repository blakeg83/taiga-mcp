# Goal 08: Schedule independent tickets concurrently

Status: not started.

## Objective

Allow independent tickets to progress in separate ordinary chats and worktrees while enforcing ownership, dependencies, repository capacity and host limits.

## Prerequisites

Goals 01–07 complete. Goal 02 supplies claim/slot primitives; this goal implements dispatch behavior around them.
Read [execution instructions](execution-instructions.md) and [shared contracts](contracts.md).

## Deliverables

Session scheduler instructions/state decisions, scoped lifecycle handling, dependency readiness rules, and deterministic concurrency fixtures.

## Ordered steps

### Step 1: Build the selected-ticket queue and dependency graph

- [ ] Load only the user-selected scope and approved relative priority/dependency edges; do not treat arbitrary list order as board priority.
- [ ] Resolve ticket identities and parent relationships. Fold child tasks into their story pipeline and deduplicate shared/already-running work.
- [ ] Validate all repository mappings, missing prerequisites, cycles and incompatible scope before dispatch; preserve blockers explicitly.
- [ ] Compute eligible work from scope readiness, prerequisite integration, priority and available limits. An open prerequisite PR alone cannot unblock its dependent.
- [ ] **Validate:** Test cycles, missing dependencies, duplicate refs/IDs, a task selected alongside its story, ready lower-priority work behind a blocked item, and an unmapped repository.
- [ ] **Update documentation:** Document queue inputs, priority tie-breaks and dependency decisions.
- [ ] **Commit before the next step:** `Define eligible ticket scheduling`.

### Step 2: Dispatch with per-ticket ownership and bounded capacity

- [ ] Reserve normalized ticket claims plus repository capacity atomically, then start/reuse that ticket's ordinary worker pair and dedicated branch/worktree.
- [ ] Default to two active ticket pipelines per repository and enforce the separately configured host worker-turn cap across sessions/repositories.
- [ ] Count preparing, implementation, correction, review and publication toward pipeline capacity; waiting dependencies/merge release it while retaining claims.
- [ ] Hold no repository-wide lock across agent turns. Keep branch/worktree paths, test outputs and any service ports distinct between tickets.
- [ ] **Validate:** Use controlled barriers for two eligible tickets, a third at capacity, simultaneous coordinators, host-cap exhaustion, and the same ticket claimed through two worktrees.
- [ ] **Update documentation:** Document active-slot accounting and isolated workspace requirements.
- [ ] **Commit before the next step:** `Dispatch bounded concurrent ticket pipelines`.

### Step 3: Route results and integrate dependencies

- [ ] Correlate every result/message with its run/action/thread and reviewed SHA; never route ticket A's findings to ticket B.
- [ ] Process changed results fairly from one session heartbeat, without creating a scheduler or fresh workers per ticket tick.
- [ ] Observe prerequisite PRs merging, confirm required changes are in the dependent's configured base, then fetch that base afresh before starting the dependent.
- [ ] Detect shared-file/integration conflicts and serialize affected work when necessary. Worktrees isolate local edits but cannot guarantee conflict-free merges.
- [ ] **Validate:** Test out-of-order results, duplicate cursors, simultaneous review corrections, merge unlocking a dependent, wrong-base merge, and conflict resolution requiring a new review.
- [ ] **Update documentation:** Document result routing, merge readiness, and conflict recovery.
- [ ] **Commit before the next step:** `Coordinate parallel results and dependencies`.

### Step 4: Recover and control tickets independently

- [ ] Pause/cancel one ticket without stopping unrelated work; whole-session pause/cancel must reconcile every active worker and pending action.
- [ ] On restart, rebuild slot accounting from persisted reservations and actual chat activity. Never free an uncertain active slot solely because a lease expired.
- [ ] Ensure a blocked sibling does not disable the heartbeat while others or PR/dependency observations can progress.
- [ ] Exercise two independent tickets through review, PR delivery and merge observation, with a third dependent ticket starting afterward.
- [ ] **Validate:** Run the deterministic concurrency/recovery suite with fake external adapters and local Git remotes; assert capacity/ownership invariants and git diff --check.
- [ ] **Update documentation:** Publish concurrency configuration, scoped controls, recovery evidence and known one-host limits.
- [ ] **Commit before the next step:** `Validate concurrent ticket lifecycle recovery`.

## Definition of done

- [ ] At least two independent tickets can progress in distinct worker chats, feature branches and worktrees.
- [ ] Configured repository and host limits hold even across duplicate ticks or concurrent coordinator attempts.
- [ ] Ticket ownership prevents duplicate story/task execution; blocked work does not stall independent work.
- [ ] Dependencies start only from a base containing verified prerequisite integration.
- [ ] Pause/cancel/recovery preserve unrelated tickets and reconcile actual active workers.
- [ ] Every completed step has its own focused commit with documentation and validation evidence.

## Execution record

Record each commit hash in the following step or final handoff. Leave incomplete gates unchecked.

| Step | Result and evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Pending | Pending | Pending |
| 2 | Pending | Pending | Pending |
| 3 | Pending | Pending | Pending |
| 4 | Pending | Pending | Pending |

Record deviations, blockers and unverified behavior below.

