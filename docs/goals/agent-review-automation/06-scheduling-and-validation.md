# Goal 06: Add scheduled recovery and validate the core workflow

Status: implemented offline; actual host heartbeat/chat smoke is pending and was not authorized by this implementation request.

## Objective

Allow an existing coordinator run to resume safely, then validate the core implementation/review workflow with offline tests and a separately authorized local-chat smoke exercise.

## Prerequisites

Goals 01–05 complete. This goal distinguishes packaged readiness from verified operation on a specific host.
Read [execution instructions](execution-instructions.md) and [shared contracts](contracts.md).

## Deliverables

Heartbeat procedure, lifecycle controls, interruption tests, operator runbook, and core evidence. Full-release acceptance follows goals 07–09.

## Ordered steps

### Step 1: Add heartbeat continuation

- [ ] Define a durable scheduled prompt scoped to the coordinator thread and session ID with its child run IDs; check installed automation_update schema.
- [ ] Reuse/update the saved heartbeat instead of creating one per round or tick. Record pending schedule actions and reconcile uncertain creation.
- [ ] On wake, inspect state and existing chats before dispatch. Use stored cursors and bounded waits, not repeated full-transcript polling.
- [ ] Stay quiet for unchanged waits; notify only completion, actionable failure, blocker, or a required user decision.
- [ ] **Validate:** Simulate duplicate ticks, stale results, pending creation, missing heartbeat, and wake after completion; no extra worker or duplicate dispatch may result.
- [ ] **Update documentation:** Document cadence selection, host prerequisites, and schedule identity.
- [ ] **Commit before the next step:** `Add coordinator heartbeat continuation`.

### Step 2: Implement pause, cancel, and interrupted-run recovery

- [ ] Pause future dispatch and request active workers checkpoint/stop using supported host tools; distinguish requested from actually quiescent.
- [ ] Disable/pause continuation when the whole session is terminal/paused or all remaining work needs user input; one blocked or complete ticket must not stop siblings or PR/dependency observation. Reconcile shutdown failure independently.
- [ ] On resume, revalidate ownership, actual worker activity, pending actions, current source revision, and ticket scope before continuing.
- [ ] Preserve worktrees/commits and leave task status unchanged on cancel unless the user requests a specific transition.
- [ ] **Validate:** Exercise app unavailable, worker still active after pause, expired lease with uncertain send, lost result receipt, and terminal heartbeat shutdown failure.
- [ ] **Update documentation:** Publish pause/resume/cancel and manual recovery procedures.
- [ ] **Commit before the next step:** `Recover and stop ticket workflows safely`.

### Step 3: Run offline acceptance and an authorized host smoke exercise

- [ ] Run the full helper/fixture suite and the repository Debug/Release restore/build/test matrix using fake data.
- [ ] Prepare a disposable local Git fixture with a deterministic defect and stubbed Taiga adapter; record the exact worker prompts and expected correction cycle.
- [ ] When explicitly authorized, create ordinary implementation/reviewer chats, verify model/effort and checkout receipts, route one correction into the same implementation chat, and exercise one coordinator heartbeat.
- [ ] Verify the reviewed revision, pause/stop behavior, no subagents, and schedule cleanup. If authorization or host capability is absent, record the actual-host gate as unverified; do not label the release operationally verified.
- [ ] **Validate:** Record commands, exit codes, ordinary chat IDs/model receipts, reviewed SHA, schedule ID/shutdown receipt, and sanitized evidence. Never point this exercise at live Taiga.
- [ ] **Update documentation:** Publish offline versus actual-host acceptance results.
- [ ] **Commit before the next step:** `Validate the ticket automation core`.

### Step 4: Publish the operator handoff and deferred roadmap

- [ ] Document installation, explicit start/reuse authorization, model selection, status mapping, evidence inspection, ticket-versus-session recovery, and removal of a schedule.
- [ ] Provide an operational invocation for one real ticket, clearly separate from tests, and a read-only preflight procedure.
- [ ] Record all goal commit hashes, limitations, and observed token/time usage if available; do not promise hard token limits without measurements.
- [ ] Link the core guide from README; mark goals 07–09 as required remaining release work. Only estimation, automatic priority intake, merging and SDK-runner work remain outside the expanded release.
- [ ] **Validate:** Check documentation links, fixture artifact hygiene, git diff --check, and this core goal's definition-of-done evidence; do not mark the expanded release complete.
- [ ] **Update documentation:** Update project status and final handoff, retaining any unverified gate.
- [ ] **Commit before the next step:** `Document ticket automation operation and limits`.

## Definition of done

- [ ] Repeated wake-ups resume the same session and recorded runs without starting duplicate workers.
- [ ] Scoped pause/cancel/needs_input and terminal states suppress affected dispatch while preserving eligible sibling work and handling active workers honestly.
- [ ] Offline behavior and baseline tests pass with synthetic data.
- [ ] Actual host capability is either verified by an authorized smoke exercise or explicitly recorded as unverified.
- [ ] The core guide allows a user to inspect/stop/recover a ticket and its coordinator session; final concurrency/PR/epic behavior remains gated on goals 07–09.
- [ ] Every completed step has its own focused commit with documentation and validation evidence.

## Execution record

Complete this table as work proceeds. Record each commit hash in the following step or final handoff.

| Step | Result and evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Heartbeat identity/state contract and quiet unchanged-wait procedure documented; actual schedule not created. | Operator guide | `7d82733` |
| 2 | Pause/cancel/resume intents and interrupted-state recovery implemented and fixture-tested. | State and operator references | `4e78975` |
| 3 | Offline PowerShell/Git/Taiga/review harness passes 9 fixtures; authorized ordinary-chat smoke not run. | Offline acceptance record | `7d82733` |
| 4 | Installation, recovery, limits, and deferred provider/host boundaries published. | Operator guide and README | `62223a9` |

Record deviations, blockers, and unverified behavior below; do not replace missing evidence with a checked box.

## Explicit local smoke-exercise invocation

The following is a future user instruction, not authorization granted by this document:

> Run goal 06's local smoke exercise. Create ordinary implementation and reviewer chats using the configured gpt-5.6-luna/xhigh and exact gpt-6.1-sol/high profiles, in the disposable fixture project. You may coordinate messages between those chats and create a temporary heartbeat in this coordinator chat. Use only synthetic ticket data and the fake Taiga adapter. Exercise one correction/re-review cycle, then disable the heartbeat and report evidence. Do not use subagents or modify live Taiga data.
