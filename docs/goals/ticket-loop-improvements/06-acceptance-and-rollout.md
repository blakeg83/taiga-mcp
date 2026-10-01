# 06: Validate regressions and prepare a controlled rollout

Status: implemented offline; actual-host behavior and publication remain pending a separate authorized trial.
Prerequisites: 01–05 in this batch and [execution instructions](execution-instructions.md).

## Objective

Prove the improvements preserve correctness and recovery, then make a separately authorized real-host comparison straightforward.

## Expected touch points

tests/automation, docs/automation, README.md, existing goal indexes, and versioned compatibility notes.

Paths under scripts, references, and assets are relative to
`.agents/skills/taiga-ticket-loop/`. Keep changes within this goal's scope.

## Ordered steps

### Step 1: Replay the audited failures offline

- [x] Build a sanitized scenario containing one real production finding, a docs correction, receipt enum mismatch, incorrect evidence attribution, intentional host exit, and a budget boundary.
- [x] Run it through generated packets, validators, routing, and reports without live desktop/provider calls.
- [x] Assert zero coordinator engineering actions, no full receipt copying in prompts, bounded repairs, stable worker IDs, and no publication with unresolved material evidence.
- [x] Exercise repeated unchanged waits and prove they do not generate extra worker work.
- [x] **Validate:** Run deterministic scenario assertions and full helper fixtures; report modeled behavior rather than claiming native host enforcement.
- [x] **Update documentation:** Document the regression matrix and expected outcomes.
- [x] **Commit before the next step:** `Replay ticket-loop audit regressions`.

### Step 2: Verify compatibility and migration

- [x] Test existing schema-version-2 and other supported legacy records, including paused tickets and uncertain actions. If a new schema is needed, migrate a copy atomically with backup and explicit versioning.
- [x] Preserve original receipts/evidence, external IDs, ownership generations, branches, PR identity, and user notification preferences.
- [x] Test rollback/unsupported versions without silently resetting a run. Do not migrate or resume the actual audited run.
- [x] Run concurrency, epic, Git/PR and .NET acceptance checks required by the execution instructions.
- [x] **Validate:** Verify legacy/current fixture acceptance, corruption recovery, stale evidence rejection, and the repository validation matrix.
- [x] **Update documentation:** Document supported versions, upgrade/rollback, and exact validation results.
- [x] **Commit before the next step:** `Verify ticket-loop upgrade compatibility`.

### Step 3: Publish operator and local installation guidance

- [x] Update the skill entry procedure, references, templates, operator guide, and root links to describe only delivered behavior.
- [x] Document how to identify the repository skill version and installed personal copy, preserve local configuration, and deploy deliberately to a named machine.
- [x] Keep machines independent; no shared coordination service, distributed claim, or installer framework is introduced.
- [x] Provide a copyable future trial invocation that explicitly names the ticket/repository, ordinary chats, permitted external writes, heartbeat choice, model profiles, and stop conditions.
- [x] **Validate:** Check links/examples and run a fixture-only packaged-skill validation; ensure no actual install, chat creation, or external action happens from reading docs.
- [x] **Update documentation:** Complete deployment and trial preparation guidance.
- [x] **Commit before the next step:** `Document improved ticket-loop operation`.

### Step 4: Assess an authorized comparison and report remaining gates

- [x] Complete offline acceptance first. If a human explicitly authorizes a disposable actual-host trial, record the exact scope and run it with the same worker profiles and acceptance requirements.
- [x] Observe coordinator role compliance, quiet waits, repair routing, verification quality, completion time, and available cost-aware measurements.
- [x] Evaluate a cheaper coordinator profile only as an explicitly selected later comparison after the role boundary works; do not conflate a model change with workflow improvement.
- [x] Mark actual-host behavior and any publish exercise unverified if not authorized or not available. Close the offline implementation with honest evidence and leave operational gates separately pending.
- [x] **Validate:** Require offline gates green; for any authorized trial, verify native operations and source/PR receipts directly. No promised savings percentage or raw-token threshold.
- [x] **Update documentation:** Update batch status, observed limitations, and a follow-up decision based on evidence.
- [x] **Commit before the next step:** `Record ticket-loop improvement acceptance`.

## Definition of done

- [x] Synthetic regressions demonstrate simpler coordination without weaker acceptance.
- [x] Compatibility, concurrency, recovery, PR, and epic behavior remain verified.
- [x] Operator docs distinguish delivered behavior from pending real-host validation.
- [x] Any live comparison has explicit scope and honest quality/time/cost evidence.
- [x] All 24 step commits and documentation checkpoints are recorded; unverified operational gates remain visibly pending.
- [x] Each completed step has validation evidence, documentation updates, and its own commit.

## Execution record

Record a step's hash in the next checkpoint or final handoff. Leave incomplete
gates unchecked; record deviations and blockers below the table.

| Step | Result and validation evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Sanitized replay derives coordinator engineering work, worker stability, canonical finding enums, raw exit evidence, deadline admission, quiet waits, bounded repairs, and publication blocking from actual fixture events; helper-integrated wait, audit, stale-review, failure-amendment, and expired-dispatch cases also pass. | Regression scenario and acceptance helper | `a1a3d70` |
| 2 | Compatibility helper accepts supported v1/v2 records, preserves complete receipt/evidence round trips, rejects unsupported versions, and never migrates the actual audited run. Existing state migration/corruption/concurrency/Git/epic fixtures remain green. | Compatibility and rollback guidance | `f9e47fd` |
| 3 | Deliberate installation/trial guidance identifies repository versus personal skill versions, keeps machines independent, and provides a future native-tool invocation without executing it. Fixture-only validation passed. | Operator guide, trial guide, root links | `0cd2803` |
| 4 | Offline acceptance is green while actual-host and publication gates remain visibly pending. No operational trial, installation, push, PR, merge, or live service write was performed. Exact commands/results and provenance are recorded in the acceptance report. | Batch status, limitations, follow-up decision | `bdb8aa2` |
