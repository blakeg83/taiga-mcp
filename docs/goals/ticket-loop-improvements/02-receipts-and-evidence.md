# 02: Make receipts deterministic and evidence durable

Status: implemented offline; actual-host behavior remains pending an authorized trial.
Prerequisites: 01 in this batch and [execution instructions](execution-instructions.md).

## Objective

Eliminate schema disagreement and evidence rewriting while keeping technical acceptance explicit and tied to the reviewed revision.

## Expected touch points

scripts/workflow-state.ps1, scripts/workflow-review.ps1, prompt assets, a shared receipt schema/validator, and synthetic receipt fixtures.

Paths under scripts, references, and assets are relative to
`.agents/skills/taiga-ticket-loop/`. Keep changes within this goal's scope.

## Ordered steps

### Step 1: Unify the receipt contract

- [x] Replace duplicated review receipt validation with one versioned contract used by both helpers and the reviewer handoff template. Include exact verdict, severity, disposition, criterion, run/action, SHA, and profile fields.
- [x] Choose canonical disposition values; support legacy resolved as an explicitly documented alias for fixed only when no contradictory unresolved evidence exists. Preserve the original receipt and record normalization.
- [x] Validate the entire expected criterion set and stable meaning/order. A structurally valid but incomplete receipt must not become a pass.
- [x] Return compact field-level errors. Require no source inspection from the coordinator to diagnose a format problem.
- [x] **Validate:** Reproduced the resolved/fixed mismatch; tested unknown aliases, missing/unbound/reordered criteria, wrong model, stale SHA, contradictory status, and both helper entry points. The full harness passed 17 fixtures.
- [x] **Update documentation:** Published the v1 JSON Schema, shared compatibility reference, prompt and operator updates.
- [x] **Commit before the next step:** `Unify ticket-loop receipt validation`.

### Step 2: Capture evidence once and generate metadata

- [x] Provide constructors that fill run/action IDs, criterion IDs/text, branch/base/head, profile, and timestamps from validated packets, prepared actions, and committed Git metadata rather than model transcription.
- [x] Store evidence as immutable records with IDs, hashes, origin action, checked revision, command/working directory, actual exit, outcome, and log reference. Keep large outputs outside the registry.
- [x] Represent expected-red failures, passing assertions, and intentional host shutdown separately; retain raw exit codes. An intentional stop never converts a failing test to a pass.
- [x] Generate test counts from structured results when available. Preserve unknown or reported-only values with provenance instead of inventing precise totals.
- [x] **Validate:** Tested actual exit 1 during intentional host stop, genuine test failure, expected-red fixture failure versus behavior failure, record/log tampering, missing record/log files, metadata generation, and reported-only counts. Evidence fixtures pass.
- [x] **Update documentation:** Documented evidence storage/lifetime, trusted metadata sources, validation, and outcome classification.
- [x] **Commit before the next step:** `Generate receipts from preserved verification evidence`.

### Step 3: Separate format repair from engineering correction

- [x] Route schema errors to a local deterministic repair where lossless, otherwise to the original receipt author. Default to at most two format/evidence repair attempts per result within the existing wall-clock budget.
- [x] Do not increment production correction rounds for metadata-only repair. Track repairs separately; exhaustion or ambiguous content becomes needs_input rather than an infinite loop.
- [x] Do not automatically accept semantic changes to evidence. The reviewer verifies evidence amendments that affect acceptance; a truthful correction may invalidate an earlier pass.
- [x] Distinguish documentation edits from receipt edits. Documentation changes need a new commit and reviewer assessment of that delta; unchanged code checks may be reused with explicit justification.
- [x] **Validate:** The focused review and repair fixtures passed. The full harness passed 19 fixtures, including correction routing, a documentation amendment, justified check reuse, local metadata repair, contradictory evidence, wall-clock exhaustion, and the two-attempt limit. Skill validation and `git diff --check` passed.
- [x] **Update documentation:** Documented routing, the separate repair ledger and counter, delta assessments, new documentation commits, and justified check reuse.
- [x] **Commit before the next step:** `Bound receipt repairs separately from code corrections`.

### Step 4: Verify compatibility and file-based ingestion

- [x] Consume receipt/evidence files through validated paths and hashes; never require the coordinator to embed a complete receipt in a shell command.
- [x] Preserve supported legacy inputs through explicit adapters and fixtures. Reject missing evidence, unsafe paths, stale review bindings, and conflicting run ownership.
- [x] Archive prior receipts by action/revision and reference reused evidence; never regenerate old narrative to carry it forward.
- [x] Run the full helper harness with representative legacy and new receipts.
- [x] **Validate:** Confirm both validators agree, cumulative evidence remains immutable, and a passed result with a genuinely open high finding still blocks.
- [x] **Update documentation:** Update examples and recovery guidance to use file references.
- [x] **Commit before the next step:** `Verify receipt compatibility and evidence reuse`.

## Definition of done

- [x] One authoritative contract drives validation and templates.
- [x] The audited enum mismatch is handled without a coding round or false acceptance.
- [x] Metadata and prior results are preserved rather than repeatedly rewritten.
- [x] Bounded repairs cannot evade technical review, deadlines, or correction limits.
- [x] Each completed step has validation evidence, documentation updates, and its own commit.

## Execution record

Record a step's hash in the next checkpoint or final handoff. Leave incomplete
gates unchecked; record deviations and blockers below the table.

| Step | Result and validation evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | The shared v1 validator reproduced the legacy enum mismatch and covers alias normalization, contradiction rejection, exact profile, complete ordered criteria, failed evidence, and stale SHA. `Test-Automation.ps1` passed 17 fixtures; skill validator and `git diff --check` passed. | Review receipt schema/reference, both helper entry points, reviewer prompt, review loop, skill entry, operator guide | `f41cf10` |
| 2 | Trusted metadata and structured evidence fixtures cover raw exit 1 on intentional shutdown, genuine failures, expected-red outcomes, assertions, external log hashes, tampering/missing files, generated counts, and reported-only provenance. `Test-Automation.ps1` passed 18 fixtures; skill validation and `git diff --check` passed. | Evidence helper/state action context, storage/classification reference, worker handoffs, operator guide, fixture guide | `8b99623` |
| 3 | The bounded route keeps lossless normalization local, sends other format/evidence repairs to the original receipt author, and requires a fresh independent review for evidence amendments. Per-result attempts are fenced in state, capped at two, budget-aware, and do not increment code correction rounds. Documentation deltas bind prior/current revisions, require a reviewer assessment, and require reasons for reused checks. Focused fixtures and the full 19-fixture harness passed. | Receipt schema and compatibility reference, state/review loop contracts, reviewer prompt, skill, operator guide, fixture guide | Recorded in step 4 |
| 4 | Receipt and evidence references are read from immutable files, checked against SHA-256 values, and rejected when missing or tampered. Both helper entry points still use the same validator; the open-high and legacy fixtures remain blocking. Focused file-ingestion and full helper harness passed; skill validation and `git diff --check` passed. | Receipt compatibility reference, evidence guidance, operator guide, fixture coverage | Recorded in final handoff |
