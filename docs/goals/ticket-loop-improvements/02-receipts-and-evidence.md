# 02: Make receipts deterministic and evidence durable

Status: planned; all steps pending.
Prerequisites: 01 in this batch and [execution instructions](execution-instructions.md).

## Objective

Eliminate schema disagreement and evidence rewriting while keeping technical acceptance explicit and tied to the reviewed revision.

## Expected touch points

scripts/workflow-state.ps1, scripts/workflow-review.ps1, prompt assets, a shared receipt schema/validator, and synthetic receipt fixtures.

Paths under scripts, references, and assets are relative to
`.agents/skills/taiga-ticket-loop/`. Keep changes within this goal's scope.

## Ordered steps

### Step 1: Unify the receipt contract

- [ ] Replace duplicated receipt validation with one versioned contract used by both helpers and generated worker templates. Include exact verdict, severity, disposition, criterion, run/action, SHA, and profile fields.
- [ ] Choose canonical disposition values; support legacy resolved as an explicitly documented alias for fixed only when no contradictory unresolved evidence exists. Preserve the original receipt and record normalization.
- [ ] Validate the entire expected criterion set and stable meaning/order. A structurally valid but incomplete receipt must not become a pass.
- [ ] Return compact field-level errors. Require no source inspection from the coordinator to diagnose a format problem.
- [ ] **Validate:** Reproduce the audited resolved/fixed failure synthetically; test unknown aliases, missing criteria, wrong model, stale SHA, contradiction, and both helper entry points.
- [ ] **Update documentation:** Publish one schema reference and compatibility examples.
- [ ] **Commit before the next step:** `Unify ticket-loop receipt validation`.

### Step 2: Capture evidence once and generate metadata

- [ ] Provide constructors that fill run/action IDs, criterion IDs, branch/base/head, profile, and timestamps from trusted run metadata rather than model transcription.
- [ ] Store evidence as immutable records with IDs, hashes, origin action, checked revision, command/working directory, actual exit, outcome, and log reference. Keep large outputs outside the registry.
- [ ] Represent expected-red failures, passing assertions, and intentional host shutdown separately; retain raw exit codes. An intentional stop never converts a failing test to a pass.
- [ ] Generate test counts from structured results when available. Preserve unknown or reported-only values with provenance instead of inventing precise totals.
- [ ] **Validate:** Test actual exit 1 during intentional host stop, genuine test failure, expected-red fixture failure versus behavior failure, tampered evidence, missing files, and metadata generation.
- [ ] **Update documentation:** Document evidence storage/lifetime and outcome classification.
- [ ] **Commit before the next step:** `Generate receipts from preserved verification evidence`.

### Step 3: Separate format repair from engineering correction

- [ ] Route schema errors to a local deterministic repair where lossless, otherwise to the original receipt author. Default to at most two format/evidence repair attempts per result within the existing wall-clock budget.
- [ ] Do not increment production correction rounds for metadata-only repair. Track repairs separately; exhaustion or ambiguous content becomes needs_input rather than an infinite loop.
- [ ] Do not automatically accept semantic changes to evidence. The reviewer verifies evidence amendments that affect acceptance; a truthful correction may invalidate an earlier pass.
- [ ] Distinguish documentation edits from receipt edits. Documentation changes need a new commit and reviewer assessment of that delta; unchanged code checks may be reused with explicit justification.
- [ ] **Validate:** Replay one production correction, one documentation amendment, one metadata repair, an evidence contradiction, and repair exhaustion; prove no review or budget bypass.
- [ ] **Update documentation:** Document routing, counters, and the default two-attempt limit.
- [ ] **Commit before the next step:** `Bound receipt repairs separately from code corrections`.

### Step 4: Verify compatibility and file-based ingestion

- [ ] Consume receipt/evidence files through validated paths and hashes; never require the coordinator to embed a complete receipt in a shell command.
- [ ] Preserve supported legacy inputs through explicit adapters and fixtures. Reject missing evidence, unsafe paths, stale review bindings, and conflicting run ownership.
- [ ] Archive prior receipts by action/revision and reference reused evidence; never regenerate old narrative to carry it forward.
- [ ] Run the full helper harness with representative legacy and new receipts.
- [ ] **Validate:** Confirm both validators agree, cumulative evidence remains immutable, and a passed result with a genuinely open high finding still blocks.
- [ ] **Update documentation:** Update examples and recovery guidance to use file references.
- [ ] **Commit before the next step:** `Verify receipt compatibility and evidence reuse`.

## Definition of done

- [ ] One authoritative contract drives validation and templates.
- [ ] The audited enum mismatch is handled without a coding round or false acceptance.
- [ ] Metadata and prior results are preserved rather than repeatedly rewritten.
- [ ] Bounded repairs cannot evade technical review, deadlines, or correction limits.
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
