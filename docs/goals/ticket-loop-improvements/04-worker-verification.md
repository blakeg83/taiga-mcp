# 04: Put verification planning and execution with workers

Status: implemented offline; actual-host behavior remains pending an authorized trial.
Prerequisites: 01–03 in this batch and [execution instructions](execution-instructions.md).

## Objective

Keep required verification thorough while avoiding coordinator investigation, repeated setup discovery, and unnecessary re-execution.

## Expected touch points

Implementation/reviewer prompt assets, references/roles-and-handoffs.md, review evidence contracts, operator guide, and synthetic repository fixtures.

Paths under scripts, references, and assets are relative to
`.agents/skills/taiga-ticket-loop/`. Keep changes within this goal's scope.

See the [worker verification contract](../../../.agents/skills/taiga-ticket-loop/references/verification-contract.md)
for the plan and optional smoke-entry shape.

## Ordered steps

### Step 1: Delegate a verification plan to the implementer

- [x] Require the implementer to derive a brief verification plan from acceptance criteria and repository instructions, recording commands and required UI interactions in an evidence file.
- [x] Have the reviewer evaluate adequacy. The coordinator checks that required metadata exists and routes gaps; it does not select tests or reproduce failures.
- [x] Preserve mandatory full-suite, TDD, and visible-browser requirements where repository instructions require them. No generic shortcut may waive those requirements.
- [x] Batch independent reads/checks where safe; serialize builds sharing outputs and dependent operations to avoid compiler locks.
- [x] **Validate:** Use synthetic repositories with different verification requirements, conflicting instructions, missing UI evidence, and shared-output checks.
- [x] **Update documentation:** Document verification ownership and completion criteria.
- [x] **Commit before the next step:** `Delegate verification planning to ticket workers`.

### Step 2: Support existing repository smoke entry points

- [x] Allow repository configuration to reference an existing smoke/setup command and cleanup instructions, including disposable resources and supported capabilities.
- [x] Provide a small example contract using a synthetic application; keep app-specific Cozi, database, HTTPS, and static-assets details out of the generic skill.
- [x] If no entry point exists, the implementer handles necessary setup and records a blocker or reusable follow-up. The coordinator must not build the harness itself.
- [x] Do not implement GroceryRecipeWizard changes or start external services in this repository batch. Such application work is a separately scoped ticket.
- [x] **Validate:** Test existing/missing commands, unavailable capability, failed setup, required cleanup, and an unchanged application that reuses an existing harness.
- [x] **Update documentation:** Document optional repository verification configuration and scope boundaries.
- [x] **Commit before the next step:** `Support repository-owned smoke verification`.

### Step 3: Reuse evidence on unchanged inputs

- [x] Record which revision, files/configuration, environment, and dependencies each check covers. Let the reviewer approve reuse only when relevant inputs remain unchanged.
- [x] Use full relevant verification after production/base changes; documentation-only changes get focused documentation review without mechanically repeating unrelated builds or UI smoke.
- [x] Reference original browser/test evidence with its original action and timestamp. Never relabel reused evidence as freshly executed.
- [x] Route incorrect reporting to bounded evidence repair; a revealed coverage gap returns to actual verification and may invalidate acceptance.
- [x] **Validate:** Replay code change, docs-only change, environment drift, changed base, reused seeded UI evidence, and missing provenance.
- [x] **Update documentation:** Document reuse rules with positive and negative examples.
- [x] **Commit before the next step:** `Reuse verification evidence without changing its provenance`.

### Step 4: Validate an entire worker handoff

- [x] Exercise implementation, genuine reviewer defect, same-chat correction, accepted unchanged evidence, and documentation amendment through the new contracts.
- [x] Verify the coordinator performs no source/test operations throughout the scenario.
- [x] Keep meaningful technical findings blocking; do not reward a fast pass that skips required evidence.
- [x] Run the complete offline helper harness and record verification limitations.
- [x] **Validate:** Use the synthetic seeded-state versus actual-click reporting regression, expected host-stop exit, and compiler-output sequencing cases.
- [x] **Update documentation:** Update worker templates and the operator verification guide.
- [x] **Commit before the next step:** `Verify worker-owned validation end to end`.

## Definition of done

- [x] Implementer and reviewer own test planning, execution, and adequacy.
- [x] Required repository checks remain enforced.
- [x] Optional smoke entry points reduce repeated discovery without expanding this repository's scope.
- [x] Reused evidence remains truthful and traceable to its original execution.
- [x] Each completed step has validation evidence, documentation updates, and its own commit.

## Execution record

Record a step's hash in the next checkpoint or final handoff. Leave incomplete
gates unchecked; record deviations and blockers below the table.

| Step | Result and validation evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | `workflow-verification.ps1` creates immutable worker-owned plans, preserves mandatory full-suite/TDD/browser requirements, and marks shared-output checks for serialization. Planning/adequacy fixtures passed. | Verification plan contract and worker guidance | `631a1fa` |
| 2 | Optional smoke contracts validate existing commands, disposable setup/cleanup, and capabilities without executing services. Missing cleanup, capability, and failed setup fixtures block. | Smoke entry-point guidance | `169fade` |
| 3 | Evidence reuse requires immutable record hashes plus revision/base/environment/dependency provenance. Exact revision and unchanged docs-only reuse are labeled; code changes and missing provenance invalidate reuse. | Evidence reuse guidance | `aade2ef` |
| 4 | Worker handoff traces cover same-chat corrections, seeded UI versus actual interaction, intentional host-stop exits, and shared-output sequencing. The final 33-fixture harness and repository validation matrix are recorded in the acceptance report; actual host remains unverified. | Worker prompts, verification contract, regression fixture | `310fa0c` |
