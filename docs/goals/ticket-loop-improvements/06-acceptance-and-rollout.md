# 06: Validate regressions and prepare a controlled rollout

Status: planned; all steps pending.
Prerequisites: 01–05 in this batch and [execution instructions](execution-instructions.md).

## Objective

Prove the improvements preserve correctness and recovery, then make a separately authorized real-host comparison straightforward.

## Expected touch points

tests/automation, docs/automation, README.md, existing goal indexes, and versioned compatibility notes.

Paths under scripts, references, and assets are relative to
`.agents/skills/taiga-ticket-loop/`. Keep changes within this goal's scope.

## Ordered steps

### Step 1: Replay the audited failures offline

- [ ] Build a sanitized scenario containing one real production finding, a docs correction, receipt enum mismatch, incorrect evidence attribution, intentional host exit, and a budget boundary.
- [ ] Run it through generated packets, validators, routing, and reports without live desktop/provider calls.
- [ ] Assert zero coordinator engineering actions, no full receipt copying in prompts, bounded repairs, stable worker IDs, and no publication with unresolved material evidence.
- [ ] Exercise repeated unchanged waits and prove they do not generate extra worker work.
- [ ] **Validate:** Run deterministic scenario assertions and full helper fixtures; report modeled behavior rather than claiming native host enforcement.
- [ ] **Update documentation:** Document the regression matrix and expected outcomes.
- [ ] **Commit before the next step:** `Replay ticket-loop audit regressions`.

### Step 2: Verify compatibility and migration

- [ ] Test existing schema-version-2 and other supported legacy records, including paused tickets and uncertain actions. If a new schema is needed, migrate a copy atomically with backup and explicit versioning.
- [ ] Preserve original receipts/evidence, external IDs, ownership generations, branches, PR identity, and user notification preferences.
- [ ] Test rollback/unsupported versions without silently resetting a run. Do not migrate or resume the actual audited run.
- [ ] Run concurrency, epic, Git/PR and .NET acceptance checks required by the execution instructions.
- [ ] **Validate:** Verify legacy/current fixture acceptance, corruption recovery, stale evidence rejection, and the repository validation matrix.
- [ ] **Update documentation:** Document supported versions, upgrade/rollback, and exact validation results.
- [ ] **Commit before the next step:** `Verify ticket-loop upgrade compatibility`.

### Step 3: Publish operator and local installation guidance

- [ ] Update the skill entry procedure, references, templates, operator guide, and root links to describe only delivered behavior.
- [ ] Document how to identify the repository skill version and installed personal copy, preserve local configuration, and deploy deliberately to a named machine.
- [ ] Keep machines independent; no shared coordination service, distributed claim, or installer framework is introduced.
- [ ] Provide a copyable future trial invocation that explicitly names the ticket/repository, ordinary chats, permitted external writes, heartbeat choice, model profiles, and stop conditions.
- [ ] **Validate:** Check links/examples and run a fixture-only packaged-skill validation; ensure no actual install, chat creation, or external action happens from reading docs.
- [ ] **Update documentation:** Complete deployment and trial preparation guidance.
- [ ] **Commit before the next step:** `Document improved ticket-loop operation`.

### Step 4: Assess an authorized comparison and report remaining gates

- [ ] Complete offline acceptance first. If a human explicitly authorizes a disposable actual-host trial, record the exact scope and run it with the same worker profiles and acceptance requirements.
- [ ] Observe coordinator role compliance, quiet waits, repair routing, verification quality, completion time, and available cost-aware measurements.
- [ ] Evaluate a cheaper coordinator profile only as an explicitly selected later comparison after the role boundary works; do not conflate a model change with workflow improvement.
- [ ] Mark actual-host behavior and any publish exercise unverified if not authorized or not available. Close the offline implementation with honest evidence and leave operational gates separately pending.
- [ ] **Validate:** Require offline gates green; for any authorized trial, verify native operations and source/PR receipts directly. No promised savings percentage or raw-token threshold.
- [ ] **Update documentation:** Update batch status, observed limitations, and a follow-up decision based on evidence.
- [ ] **Commit before the next step:** `Record ticket-loop improvement acceptance`.

## Definition of done

- [ ] Synthetic regressions demonstrate simpler coordination without weaker acceptance.
- [ ] Compatibility, concurrency, recovery, PR, and epic behavior remain verified.
- [ ] Operator docs distinguish delivered behavior from pending real-host validation.
- [ ] Any live comparison has explicit scope and honest quality/time/cost evidence.
- [ ] All 24 step commits and documentation checkpoints are recorded; unverified operational gates remain visibly pending.
- [ ] Each completed step has validation evidence, documentation updates, and its own commit.

## Execution record

Record a step's hash in the next checkpoint or final handoff. Leave incomplete
gates unchecked; record deviations and blockers below the table.

| Step | Result and validation evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Pending | Pending | Pending |
| 2 | Pending | Pending | Pending |
| 3 | Pending | Pending | Pending |
| 4 | Pending | Pending | Pending |
