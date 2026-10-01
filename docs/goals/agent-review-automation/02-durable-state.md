# Goal 02: Implement durable state and local ownership

Status: implemented offline; helper and recovery fixtures pass.

## Objective

Build a small PowerShell 7 helper that makes workflow progress recoverable across turns and rejects conflicting local updates.

## Prerequisites

Goal 01 complete. This helper performs local file operations only; the coordinator performs all desktop and Taiga calls.
Read [execution instructions](execution-instructions.md) and [shared contracts](contracts.md).

## Deliverables

workflow-state.ps1, a self-contained PowerShell test harness, synthetic session/ticket/PR/epic fixtures, and a recovery/state reference.

## Ordered steps

### Step 1: Implement validated state storage

- [ ] Implement session/run initialization and inspect operations using explicit JSON input files and schema-version validation; reject unknown critical fields and invalid transitions.
- [ ] Store runs outside worktrees under the configured canonical root. Validate run IDs and resolved paths to prevent traversal or unintended writes.
- [ ] Persist one host registry snapshot containing sessions, ticket claims, repository slots and the action/event journal using a same-directory temporary file and atomic replacement; preserve a recoverable prior valid snapshot.
- [ ] Keep credentials out of inputs/output/logs and surface malformed or unsupported state explicitly.
- [ ] **Validate:** Test clean initialization, paths with spaces, Unicode data, truncated state, invalid schemas, and interruption before/after replacement.
- [ ] **Update documentation:** Document state format, storage location, and restore behavior.
- [ ] **Commit before the next step:** `Add durable workflow state storage`.

### Step 2: Implement ownership and concurrency checks

- [ ] Acquire normalized ticket ownership (including owned story tasks) and repository capacity reservations atomically under a short registry lock. Never hold an exclusive repository ownership lock throughout coding.
- [ ] Require expected state revisions and coordinator identity/fencing generation on mutations.
- [ ] Add an injected clock for lease tests; never reclaim an uncertain in-flight action merely because its lease expired.
- [ ] Implement process-safe release/recovery, shared-story references, and separate host worker-turn reservations. Waiting for merge/dependencies consumes no execution slot while preserving ticket ownership; uncertain active work retains its reservation.
- [ ] **Validate:** Run two-process tests with controlled barriers: duplicate ticket by ref/ID, alternate worktree path, stale revision, crashed owner, two independent ticket claims, capacity overflow, and child-task/story duplicate claims.
- [ ] **Update documentation:** Document ownership scope and recovery rules without claiming distributed locking.
- [ ] **Commit before the next step:** `Prevent overlapping local ticket runs`.

### Step 3: Implement action journal and lifecycle transitions

- [ ] Add prepare-action and record-observation with durable IDs, targets, input digests, and pending/observed/uncertain states.
- [ ] Track last-consumed worker result/cursor and reject duplicate consumption or stale review receipts.
- [ ] Model queued/dependency, publishing/awaiting-merge, epic parent and session states now; unsupported dependent behavior must stay gated until goals 07–09 ship.
- [ ] Implement phase transitions including pause/cancel intent and needs_input; retain resume phase and unresolved actions.
- [ ] Return a reconciliation requirement for uncertain external outcomes; never issue a network/chat call from the helper.
- [ ] **Validate:** Exercise interruption at each action boundary, duplicate results, invalid transitions, terminal-state dispatch rejection, and ownership transfer during an uncertain action.
- [ ] **Update documentation:** Document operation inputs/results and correlation-marker limitations.
- [ ] **Commit before the next step:** `Track workflow actions and transitions`.

### Step 4: Validate recovery and finish the helper

- [ ] Add deterministic recovery fixtures covering partial snapshots, stale leases, uncertain messages, uncertain pushes/PR creation, and uncertain ticket writes.
- [ ] Verify a resumed run preserves worker IDs, review round, evidence, and pending finalization rather than restarting implementation.
- [ ] Add a documented command that runs the offline helper suite with a nonzero exit on failure; leave no runtime artifacts in Git.
- [ ] Inspect the staged diff and confirm root .NET projects and public tool schemas are untouched.
- [ ] **Validate:** Run the complete helper suite and git diff --check.
- [ ] **Update documentation:** Publish helper usage and recovery examples with actual test results.
- [ ] **Commit before the next step:** `Validate durable workflow recovery`.

## Definition of done

- [ ] Concurrent local attempts cannot both claim the same ticket or a story and its owned task; independent tickets can reserve capacity up to configured limits.
- [ ] Interrupted writes preserve a valid record or produce an explicit recovery condition.
- [ ] Uncertain external actions require observation rather than blind replay.
- [ ] Parent/child references and execution/worker-turn slots survive recovery without duplicate work.
- [ ] State and fixture tests are reproducible with PowerShell 7 and use no live services.
- [ ] Every completed step has its own focused commit with documentation and validation evidence.

## Execution record

Complete this table as work proceeds. Record each commit hash in the following step or final handoff.

| Step | Result and evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Versioned JSON registry, atomic replacement, backup recovery, path/secret/schema validation implemented. | State reference | `4e78975` |
| 2 | Per-ticket claims, repository/host slots, CAS revisions, and capacity guards implemented. | Ownership and concurrency rules | `4e78975` |
| 3 | Action journal, observations, cursor uniqueness, lifecycle, pause/cancel/resume implemented. | Operation and transition reference | `4e78975` |
| 4 | Truncation recovery and offline harness pass; state remains local one-host bookkeeping. | Recovery fixture documentation | `7d82733` |

Record deviations, blockers, and unverified behavior below; do not replace missing evidence with a checked box.
