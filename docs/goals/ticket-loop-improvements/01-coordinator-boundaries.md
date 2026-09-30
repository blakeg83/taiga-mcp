# 01: Constrain the coordinator to orchestration

Status: implemented offline; actual-host behavior remains pending an authorized trial.
Prerequisites: None in this batch and [execution instructions](execution-instructions.md).

## Objective

Give the coordinator a clear, minimal job: collect ticket context, dispatch ordinary workers, relay results, and deliver accepted work. Engineering judgment stays with the implementer and reviewer.

## Expected touch points

SKILL.md, references/roles-and-handoffs.md, references/host-contract.md, worker prompt assets, and operator documentation under the existing skill directory.

Paths under scripts, references, and assets are relative to
`.agents/skills/taiga-ticket-loop/`. Keep changes within this goal's scope.

## Ordered steps

### Step 1: Define role permissions and escalation

- [x] Document the coordinator's allowed inputs: ticket requirements/relationships, repository instructions and configured commands, Git identity/status/SHAs, worker status/receipts, deadlines, and provider metadata.
- [x] Prohibit routine production-source reads, diff interpretation, test execution, diagnosis, technical findings, and smoke reproduction in the coordinator. Reading instructions/configuration for dispatch is permitted.
- [x] Route missing engineering evidence to its producing worker; route correctness disputes to the reviewer, then the user if unresolved. Never waive a required check or fabricate acceptance.
- [x] Preserve the user-selected coordinator profile and exact worker profiles. No cheaper-model switch is part of this step.
- [x] **Validate:** Exercised all seven scenarios in `references/coordinator-boundaries.md`; existing review fixtures cover failed checks and stale HEAD, and the role matrix routes missing evidence to its producer and epic combined verification to workers.
- [x] **Update documentation:** Added the boundary reference, linked it from the skill, updated worker prompts and operator documentation.
- [x] **Commit before the next step:** `Constrain ticket-loop coordinator responsibilities`.

### Step 2: Create a minimal assignment packet

- [x] Build one immutable, versioned scope packet with stable criterion IDs/text, ticket identity, full-context file reference/hash, repository/worktree/base, required repository commands, authority, and deadlines.
- [x] Keep the handoff prompt concise; workers can read the packet and relevant repository instructions. Exclude unrelated history and repeated policy text while preserving all material requirements.
- [x] Record unresolved product requirements for focused clarification; let the implementer investigate code rather than requiring coordinator confirmation of the defect.
- [x] Make the packet file available in the worker's actual checkout/host context; never rely on the initial chat cwd or a disappearing temporary path.
- [x] **Validate:** The packet fixture covers complete/missing scope, stable criterion ordering, long context, exact profiles/checkout, immutable contents, and inaccessible context/output paths. The full harness passed 14 fixtures.
- [x] **Update documentation:** Added the packet contract, linked it from the skill, updated both worker prompts and the operator guide.
- [x] **Commit before the next step:** `Build compact ticket assignment packets`.

### Step 3: Align entry preflight with actual integrations

- [x] Separate capability/configuration checks from code investigation. Verify named profiles and supported browser capability without requiring the coordinator to perform a browser smoke test.
- [x] Normalize supported Taiga pagination using documented authoritative evidence, including trustworthy totals where sufficient. Unknown or contradictory evidence remains incomplete; do not coerce null into false.
- [x] Preserve explicit scope authorization and ask only for genuinely missing scope, authority, or requirements. Avoid recurring compatibility exceptions when the adapter can decide safely.
- [x] Replace stale hard-coded host availability claims with dated historical evidence and per-run capability discovery.
- [x] **Validate:** `Test-Automation.ps1` passed 15 fixtures covering null has_more with complete/incomplete totals, duplicate pages, contradictory metadata, unavailable exact profile, an equivalent available browser, and missing operational authority. Skill validation and `git diff --check` passed.
- [x] **Update documentation:** Updated host preflight, troubleshooting, and resource pagination guidance. MCP response contracts were not changed.
- [x] **Commit before the next step:** `Resolve routine preflight compatibility locally`.

### Step 4: Verify coordinator-only scenarios

- [x] Add synthetic normal and blocked traces asserting that coordinator instructions/action plans never require code review or test execution.
- [x] Prove that the same implementation and reviewer IDs survive corrections, and that user-supplied changed requirements return through scope capture.
- [x] Keep request/wait/read/provider operations distinguishable from actual engineering actions; document that prompts are a behavioral boundary, not an OS sandbox.
- [x] Run the full helper harness and record any actual-host behavior as unverified until the final authorized trial.
- [x] **Validate:** Role traces and the full harness passed 16 fixtures; `quick_validate.py` and `git diff --check` passed. Exact worker profiles remain unchanged; no release gates were changed.
- [x] **Update documentation:** Added the operator role diagram and execution evidence.
- [x] **Commit before the next step:** `Verify coordinator role boundaries`.

## Definition of done

- [x] The coordinator contract and all handoff templates consistently delegate engineering work.
- [x] Compact packets preserve requirements and exact identities without repeated full context.
- [x] Preflight resolves supported integration metadata without inventing certainty.
- [x] Existing worker profiles, source ownership, and completion gates remain intact.
- [x] Each completed step has validation evidence, documentation updates, and its own commit.

## Execution record

Record a step's hash in the next checkpoint or final handoff. Leave incomplete
gates unchecked; record deviations and blockers below the table.

Starting Git revision: `d2a1999165d124d115be657f9ade37fa8c4dd3e7` (clean
worktree; no unrelated changes).

| Step | Result and validation evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Exercised all seven documented routing scenarios. `pwsh -NoProfile -File tests/automation/Test-Automation.ps1` passed 13 fixtures; skill `quick_validate.py` passed; `git diff --check` passed. Existing offline review fixtures cover stale SHA and failed checks. | Skill entrypoint, boundary reference, roles/handoffs, worker prompts, operator guide | `f9f3c69a9857b9a24cbd0c690d8b902fecff1ff0` |
| 2 | Packet fixture covers complete/missing criteria, stable order, long context, exact profiles and checkout, immutable/tamper detection, unresolved requirements, and inaccessible inputs. Full harness passed 14 fixtures; skill validation and `git diff --check` passed. | Skill entrypoint, packet contract, worker prompts, roles/handoffs, operator guide, fixture guide | `87a8acc9b337346ccc0d474a9f7f7322c91558a8` |
| 3 | Full harness passed 15 fixtures, including complete/incomplete totals with null flags, ambiguous null headers, duplicate/contradictory pages, exact profile, equivalent browser capability, and missing authority. Official Taiga pagination headers checked; skill validation and `git diff --check` passed. | Preflight helper, host/troubleshooting references, Taiga Git/PR guidance, operator guide, historical host record, fixture guide | `0189c70265c9ce710f97f22ecc5a33c51fb00504` |
| 4 | Synthetic normal and blocked traces verify coordinator-only orchestration, stable worker IDs through corrections, and new packet capture before changed-scope dispatch. Full harness passed 16 fixtures; skill validation and `git diff --check` passed. Actual-host behavior remains unverified. | Role trace fixture, coordinator boundary reference, operator role diagram, fixture guide | `36d5c91992c0336e6c508cc64fc1d2c393b5b2e3` |
