# 01: Constrain the coordinator to orchestration

Status: planned; all steps pending.
Prerequisites: None in this batch and [execution instructions](execution-instructions.md).

## Objective

Give the coordinator a clear, minimal job: collect ticket context, dispatch ordinary workers, relay results, and deliver accepted work. Engineering judgment stays with the implementer and reviewer.

## Expected touch points

SKILL.md, references/roles-and-handoffs.md, references/host-contract.md, worker prompt assets, and operator documentation under the existing skill directory.

Paths under scripts, references, and assets are relative to
`.agents/skills/taiga-ticket-loop/`. Keep changes within this goal's scope.

## Ordered steps

### Step 1: Define role permissions and escalation

- [ ] Document the coordinator's allowed inputs: ticket requirements/relationships, repository instructions and configured commands, Git identity/status/SHAs, worker status/receipts, deadlines, and provider metadata.
- [ ] Prohibit routine production-source reads, diff interpretation, test execution, diagnosis, technical findings, and smoke reproduction in the coordinator. Reading instructions/configuration for dispatch is permitted.
- [ ] Route missing engineering evidence to its producing worker; route correctness disputes to the reviewer, then the user if unresolved. Never waive a required check or fabricate acceptance.
- [ ] Preserve the user-selected coordinator profile and exact worker profiles. No cheaper-model switch is part of this step.
- [ ] **Validate:** Exercise a role/scenario matrix covering normal implementation, unclear requirements, failed tests, technical disagreement, changed HEAD, missing receipt, and epic combined acceptance. Route combined verification to a worker.
- [ ] **Update documentation:** Document coordinator and worker ownership with concrete examples.
- [ ] **Commit before the next step:** `Constrain ticket-loop coordinator responsibilities`.

### Step 2: Create a minimal assignment packet

- [ ] Build one immutable, versioned scope packet with stable criterion IDs/text, ticket identity, full-context file reference/hash, repository/worktree/base, required repository commands, authority, and deadlines.
- [ ] Keep the handoff prompt concise; workers can read the packet and relevant repository instructions. Exclude unrelated history and repeated policy text while preserving all material requirements.
- [ ] Record unresolved product requirements for focused clarification; let the implementer investigate code rather than requiring coordinator confirmation of the defect.
- [ ] Make the packet file available in the worker's actual checkout/host context; never rely on the initial chat cwd or a disappearing temporary path.
- [ ] **Validate:** Test complete versus missing scope, stable criterion ordering, long descriptions, exact model/checkout bindings, and inaccessible packet paths.
- [ ] **Update documentation:** Document packet fields, ownership, and the difference between a concise prompt and omitted requirements.
- [ ] **Commit before the next step:** `Build compact ticket assignment packets`.

### Step 3: Align entry preflight with actual integrations

- [ ] Separate capability/configuration checks from code investigation. Verify named profiles and supported browser capability without requiring the coordinator to perform a browser smoke test.
- [ ] Normalize supported Taiga pagination using documented authoritative evidence, including trustworthy totals where sufficient. Unknown or contradictory evidence remains incomplete; do not coerce null into false.
- [ ] Preserve explicit scope authorization and ask only for genuinely missing scope, authority, or requirements. Avoid recurring compatibility exceptions when the adapter can decide safely.
- [ ] Replace stale hard-coded host availability claims with dated historical evidence and per-run capability discovery.
- [ ] **Validate:** Cover null has_more with complete/incomplete totals, duplicate pages, contradictory metadata, unavailable exact profile, available equivalent browser capability, and missing operational authority.
- [ ] **Update documentation:** Update preflight troubleshooting and resource-specific pagination rules without changing MCP response contracts.
- [ ] **Commit before the next step:** `Resolve routine preflight compatibility locally`.

### Step 4: Verify coordinator-only scenarios

- [ ] Add synthetic normal and blocked traces asserting that coordinator instructions/action plans never require code review or test execution.
- [ ] Prove that the same implementation and reviewer IDs survive corrections, and that user-supplied changed requirements return through scope capture.
- [ ] Keep request/wait/read/provider operations distinguishable from actual engineering actions; document that prompts are a behavioral boundary, not an OS sandbox.
- [ ] Run the full helper harness and record any actual-host behavior as unverified until the final authorized trial.
- [ ] **Validate:** Run role routing scenarios, helper harness, and diff checks; confirm no worker defaults or release gates changed.
- [ ] **Update documentation:** Update the operator role diagram and this goal's execution record.
- [ ] **Commit before the next step:** `Verify coordinator role boundaries`.

## Definition of done

- [ ] The coordinator contract and all handoff templates consistently delegate engineering work.
- [ ] Compact packets preserve requirements and exact identities without repeated full context.
- [ ] Preflight resolves supported integration metadata without inventing certainty.
- [ ] Existing worker profiles, source ownership, and completion gates remain intact.
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
