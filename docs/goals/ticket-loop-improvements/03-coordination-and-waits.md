# 03: Script bookkeeping and keep waits quiet

Status: step 1 implemented offline; steps 2–4 pending. Actual-host behavior remains pending an authorized trial.
Prerequisites: 01–02 in this batch and [execution instructions](execution-instructions.md).

## Objective

Replace model-authored low-level state sequences with compact local operations while retaining native desktop handoffs and recovery guarantees.

## Expected touch points

scripts/workflow-state.ps1, scripts/workflow-review.ps1, a small coordination facade if needed, references/state-contract.md, references/scheduling-and-epics.md, and tests/automation.

Paths under scripts, references, and assets are relative to
`.agents/skills/taiga-ticket-loop/`. Keep changes within this goal's scope.

## Ordered steps

### Step 1: Add compact coordination operations

- [x] Define high-level local requests for accepting a worker result, deciding its next route, preparing a dispatch/publication, recording the external outcome, and returning run status.
- [x] Use file inputs for packet/receipt data. Return only phase, decision/reason, action ID, worker ID, required arguments/references, and changed fields by default.
- [x] Reuse schema validation, CAS revisions, owner generation, and journal logic. Do not teach the coordinator to inspect helper source or reconstruct payloads during each run.
- [x] Keep preparation before the external action and observation afterward; never pretend local and external operations form one atomic transaction.
- [x] **Validate:** Test normal progression, malformed results, stale revision/generation, duplicate result, partial local failure, and bounded output size.
- [x] **Update documentation:** Document the small facade and supported diagnostic expansion.
- [x] **Commit before the next step:** `Add compact coordination operations`.

### Step 2: Preserve dispatch and recovery correctness

- [x] Construct worker prompts from templates and files; emit an action descriptor for the coordinator's native create/message tools. The helper itself must not call private desktop APIs.
- [x] Distinguish message accepted, worker running, worker completed, receipt valid, and review accepted. Keep pending client IDs separate from real thread IDs.
- [x] Reconcile uncertain creates/messages/pushes/PRs before reuse; never blindly redispatch. Record enough correlation data without copying the entire chat.
- [x] Enforce wall-clock and correction/repair limits before new work, including publication. Permit bounded observation of already-running work and safe pause reconciliation after expiry.
- [x] **Validate:** Inject interruption before/after external completion, duplicate observations, boundary-time expiry, pending IDs, and response loss. Verify one blocked ticket does not stop siblings.
- [x] **Update documentation:** Update action lifecycle, recovery, and limit semantics.
- [x] **Commit before the next step:** `Preserve recovery across compact handoffs`.

### Step 3: Define observation and heartbeat behavior

- [x] Prefer native bounded wait_threads with saved cursors over repeated full read_thread. Use immediate snapshots only for a concrete reconciliation need; respect actual host time limits and interruption behavior.
- [x] On an unchanged timeout, continue the bounded wait or yield to the single authorized session heartbeat. Do not read source, re-open completed evidence, message workers, or mutate unchanged state.
- [x] Fetch detailed output only for a completed result, reported blocker, changed state, or missing receipt. Keep genuine user-input/approval needs visible.
- [x] Use one heartbeat for the coordinator session with quiet unchanged behavior; no nested schedules, hidden daemon, or timer per ticket. Preserve user notification preferences.
- [x] **Validate:** Replay repeated unchanged waits and wakeups, worker completion, missing result, new user input, paused heartbeat, and two concurrent tickets. Assert zero worker messages/source reads/state mutations for unchanged observations.
- [x] **Update documentation:** Document polling choices and resumable cursor behavior.
- [x] **Commit before the next step:** `Keep unchanged worker waits quiet`.

### Step 4: Verify pause and multi-ticket regressions

- [ ] Run traces for two independent tickets, a dependent ticket, and an epic observer; preserve capacity and ownership rules.
- [ ] Prove pause/cancel intent stops new dispatch and requires observed quiescence before releasing reservations.
- [ ] Confirm result/publication recovery never restarts completed implementation solely because a final Taiga write failed.
- [ ] Record operation counts for the synthetic workflow without treating fewer operations as sufficient proof of correctness.
- [ ] **Validate:** Run the full helper harness, local Git/provider fixtures, and diff checks.
- [ ] **Update documentation:** Update recovery examples and execution evidence.
- [ ] **Commit before the next step:** `Verify efficient coordination and recovery`.

## Definition of done

- [ ] Routine coordination no longer needs hand-written repeated state payloads.
- [ ] Unchanged observations cause no engineering work or needless redispatch.
- [ ] External action uncertainty, capacity, pause, and ownership guarantees remain intact.
- [ ] Helpers remain local logic; native desktop tools own chats and schedules.
- [ ] Each completed step has validation evidence, documentation updates, and its own commit.

## Execution record

Record a step's hash in the next checkpoint or final handoff. Leave incomplete
gates unchecked; record deviations and blockers below the table.

| Step | Result and validation evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Added `workflow-coordinate.ps1` with file/hash-bound dispatch, publication preparation, result acceptance/routing, external observation, and compact status operations. It delegates mutations to the existing CAS/fencing/journal state helper and returns native action descriptors without invoking desktop APIs. Synthetic progression, durable prompt/result references, malformed input, duplicate/partial state paths, and compact output passed; skill validation and `git diff --check` passed. | Coordination facade reference and operator guide | Recorded in final handoff |
| 2 | The facade returns `reconcile` for an existing action ID, blocks new dispatch at an expired budget, and treats a provider `clientThreadId` without a real `threadId` as uncertain. External state is stored as a small hashed correlation summary; no blind redispatch or full chat copy is performed. Focused recovery fixtures, skill validation, and `git diff --check` passed. | State/recovery contract and operator guidance | Recorded in final handoff |
| 3 | Added quiet `observe-wait` and `heartbeat-plan` operations. Unchanged observations return a bounded `wait_threads` request with the saved cursor and no registry mutation; completions/blockers request one detailed read. Heartbeat planning reuses one session heartbeat, keeps notification policy visible, and stays quiet for unchanged state. Focused wait/heartbeat fixtures, skill validation, and `git diff --check` passed. | State/recovery contract and operator polling guidance | Recorded in final handoff |
| 4 | Pending | Pending | Pending |
