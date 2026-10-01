# Goal 04: Implement revision-bound review and correction rules

Status: implemented offline; revision-bound review and correction fixtures pass.

## Objective

Make the coordinator iterate until a specific implementation revision satisfies requirements and independent review for PR publication, or reaches a clear escalation condition.

## Prerequisites

Goal 03 complete; use synthetic tickets until Taiga integration is added in goal 05.
Read [execution instructions](execution-instructions.md) and [shared contracts](contracts.md).

## Deliverables

Validated receipt/transition rules, findings tracking, completion gates, and end-to-end loop fixtures.

## Ordered steps

### Step 1: Validate implementation evidence and freeze review input

- [ ] Require the implementation receipt to identify current HEAD, base, checkout, requirements hash, tests and criterion/task coverage.
- [ ] Verify committed clean source state and actual revision before review; handle justified no-change work explicitly.
- [ ] Pause implementation dispatch for this ticket while reviewing; other tickets may progress in separate worktrees. Record pre-review checkout/source state and route test outputs externally where needed.
- [ ] Reject mismatched scope or revisions and request corrected evidence instead of asking the reviewer to guess.
- [ ] **Validate:** Test dirty source state, incorrect SHA, missing tests, legitimate no-change work, and a commit created after handoff.
- [ ] **Update documentation:** Document evidence requirements and stable-review procedure.
- [ ] **Commit before the next step:** `Bind implementation handoffs to commits`.

### Step 2: Track review verdicts and finding dispositions

- [ ] Validate pass, changes_requested, and blocked receipts against run, action, base, scope hash, and reviewed SHA.
- [ ] Track stable finding IDs, severity, evidence, requested change, and fixed/rejected/escalated dispositions.
- [ ] Require reviewer acceptance of justified rejections; unresolved blocking findings cannot coexist with a passing gate.
- [ ] Reject malformed, stale, or internally contradictory verdicts and request clarification.
- [ ] **Validate:** Test stale pass, unknown finding IDs, missing criterion coverage, unsupported verdicts, and rejected findings not accepted by the reviewer.
- [ ] **Update documentation:** Document reviewer output and findings resolution rules.
- [ ] **Commit before the next step:** `Validate review verdicts and findings`.

### Step 3: Drive bounded correction rounds

- [ ] Translate changes_requested into one action for the existing Luna chat with findings and the current revision.
- [ ] Count the initial review as round 0, then at most three correction/re-review rounds by default.
- [ ] Stop for blockers, exhausted elapsed-time budget, repeated unresolved disagreement, or unavailable worker; surface needs_input.
- [ ] Do not retry failed checks by inventing success, silently switch models, or start fresh workers to escape round limits.
- [ ] **Validate:** Exercise pass on first review, pass after two corrections, exhaustion after three corrections, blocked implementation, and duplicate review-result delivery.
- [ ] **Update documentation:** Document loop limits, escalation reports, and model preservation.
- [ ] **Commit before the next step:** `Implement bounded review correction cycle`.

### Step 4: Enforce final acceptance and invalidation

- [ ] Require all criteria, required successful checks, resolved blocking findings, unchanged scope, and current/reviewed SHA equality before publishing. Review pass alone cannot close a merged-policy ticket.
- [ ] Invalidate approval after human edits, new commits, source changes during review, or a changed integration base.
- [ ] Keep code-complete, PR-delivered, integrated, and ticket-finalized evidence separate so reporting failures do not restart coding. Goal 07 owns publication and merge observation.
- [ ] Add a review handoff listing exact revision, evidence, pending publication/integration steps, and completion policy. Branch updates and material PR feedback re-enter the same bounded correction/review cycle.
- [ ] **Validate:** Run the complete synthetic loop suite including requirements changing mid-review and an unexpected reviewer edit; run git diff --check.
- [ ] **Update documentation:** Publish acceptance examples and remaining verification limitations.
- [ ] **Commit before the next step:** `Enforce reviewed revision completion gate`.

## Definition of done

- [ ] A pass is accepted only for the current revision and requirement scope; publication/integration states remain distinct.
- [ ] Findings, rejections, correction rounds, and escalation outcomes are traceable.
- [ ] The default loop has one initial review and no more than three correction rounds.
- [ ] Completion requires evidence; a worker finishing a turn is insufficient.
- [ ] Every completed step has its own focused commit with documentation and validation evidence.

## Execution record

Complete this table as work proceeds. Record each commit hash in the following step or final handoff.

| Step | Result and evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Implementation receipt and clean committed revision requirements implemented. | Review reference | `bd6a212` |
| 2 | Verdict, stable findings, and blocking-disposition validation implemented. | Review reference and receipt validator | `d278883` |
| 3 | Initial round plus three bounded corrections with needs_input escalation implemented. | Review decision script | `d278883` |
| 4 | Stale SHA/scope/base invalidation and publish gate covered by fixtures. | Acceptance documentation | `7d82733` |

Record deviations, blockers, and unverified behavior below; do not replace missing evidence with a checked box.
