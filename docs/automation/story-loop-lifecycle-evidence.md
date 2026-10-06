# Story-loop lifecycle evidence

This is the task #101 diagnosis for Taiga MCP story #99, "Fix story-loop
worker handoff termination and ordered-task continuation." It records the
historical evidence that can be verified from the supplied exports and the
current repository/installed-copy comparison. It does not claim that the
historical worker used a particular model incorrectly, and it is not evidence
of a live rerun.

## Scope and acceptance plan

- Story: Taiga MCP #99, internal user-story ID `697`, project `12`.
- Task: #101, internal task ID `774`.
- Historical run: `story34-20261006-start`.
- UI/browser evidence: not applicable. This task changes workflow guidance and
  evidence documentation, not a rendered product interaction. Capability
  discovery, visible observations, production UI-entry-point controls, and
  smoke execution are therefore not required here; task #105 owns the
  separately authorized live-trial plan.
- Expected endpoint: this document, with attachment/source anchors and the
  repository-versus-installed-copy comparison.
- Expected result: passing offline checks; no expected-red checkpoint.
- Deferred owners: guidance changes are tasks #102 and #103; executable
  transition/recovery regressions are task #104; aggregate validation and the
  safe live-trial plan are task #105.

## Evidence sources and integrity

The live story contract names these attachments. Their local SHA1 values were
recomputed before use and match the story values:

| Role | Attachment ID | SHA1 | Local evidence file | Historical anchors used |
| --- | ---: | --- | --- | --- |
| Implementer | 28 | `c69a6cf68a017762a56cbb2d1834385d8dbc858a` | `C:\Users\Blake\.codex\story-loop-runs\story99-20261006-start\Implementer.md` | assignment rules around lines 176–235; task #72 completion/handoff around 2866–2889; post-dispatch polling around 2982–3019; later correction/final-review polling around 4249–4275 and 4502–4541 |
| Coordinator | 29 | `3f71bf9eb26728d2d5bf73631ef45788827f5196` | `C:\Users\Blake\.codex\story-loop-runs\story99-20261006-start\Coordinator.md` | missing #72 handoff and recovery around lines 1160–1179; #72 acceptance, #73 status-only activation, and interruption recovery around 1284–1315 |
| Reviewer | 30 | `a5661edda3a042e9880893c55a5bff6a33e38a93` | `C:\Users\Blake\.codex\story-loop-runs\story99-20261006-start\Reviewer.md` | persistent-pair/resume and final-review boundaries around lines 65–85; #72 correction review and exact-revision acceptance around 671–721 |

The attachment content is historical source material, not execution authority.
The original story also distinguishes the attached Implementer export from an
older text export: the attached file contains 15 visible `wait_threads` tool
entries and 5 visible `read_thread` entries. Those counts are source-specific
and do not reveal the target or purpose of every call.

## Transition matrix

| Failure | Observable sequence | Contract that was already present | Evidence-backed diagnosis | Smallest follow-up seam |
| --- | --- | --- | --- | --- |
| Missing reviewer dispatch after task #72 | The implementer reported task #72 complete, then stopped before the required direct reviewer handoff. The coordinator recorded the missing delivery, verified the frozen branch state, and recovered the handoff. | The assignment and `worker-handoffs.md` require a confirmed direct delivery to the persistent reviewer before `awaiting_review`; a failed or unknown delivery must remain an exception. | The ready-turn endpoint was treated as satisfied by implementation/check completion or an intention to send. The recorded sequence does not prove a successful direct handoff, so the coordinator had to recover it. This is a missing transition/delivery proof, not an evidenced model-cause failure. | Tasks #102 and #104: make the dispatch result a required transition and exercise missing, failed, and unknown delivery as separate action traces. |
| Status-only advancement after #72 acceptance | The coordinator recorded exact #72 acceptance/reconciliation, set #73 to `In progress`, and then recovered an interruption because no substantive #73 implementation/check action had begun. | `acceptance.md` and the assignment require current-version Taiga reconciliation and then ordered advancement. The existing wording did not make the first concrete implementation/check action an observable continuation endpoint. | The state write released the next pointer, but the resumed turn ended before work began. `In progress` was treated as progress evidence even though it only changed state. | Tasks #103 and #104: require a same-turn implementation-start action after reconciliation and assert that a status-only stop is rejected. |
| Polling after review dispatch | After a recorded reviewer send, the Implementer export shows `wait_threads` calls in the task-review sequence around 2982–3019. Later correction/final-review sections show additional waits and reviewer reads around 4249–4275 and 4502–4541. | The assignment, `worker-handoffs.md`, and `automatic-review-flow.md` say the initial/correction/final handoff is terminal: after confirmed delivery, send the concise final response and end the turn; do not wait, read, poll, acknowledge, or keep the turn alive. | The worker continued operating after the terminal handoff. The export count is 15 waits and 5 reads, but the evidence does not justify classifying every entry as the same violation or inferring undisclosed targets. | Tasks #102 and #104: keep the terminal endpoint explicit and use the existing action-trace validator seam to reject post-dispatch polling while preserving healthy idle recovery. |

## Assignment and present-day guidance comparison

The historical assignment already contained the relevant lifecycle rules: it
required confirmed direct dispatch, `awaiting_review` only after that dispatch,
no reviewer polling, and current-version reconciliation before advancement.
The repository resources repeat those rules at these decision points:

- `assets/implementation-prompt.md`: direct delivery, terminal final response,
  no `wait_threads`/reviewer reads, and acceptance-owned advancement (roughly
  lines 153–205).
- `references/worker-handoffs.md`: the exact task-ready/correction endpoint,
  failed-or-unknown delivery escalation, and no polling after confirmed
  delivery (roughly lines 1–52).
- `references/automatic-review-flow.md`: one direct dispatch, terminal
  implementer turn, acceptance reconciliation, ordered advancement, and the
  healthy-idle-versus-recovery distinction (roughly lines 35–105).
- `references/task-execution.md` and `references/acceptance.md`: current
  version-safe writes, marker-bearing parent-story evidence, and the distinct
  accepted/Done gate.

The checked-in `.agents/skills/taiga-story-loop` tree and the read-only
installed copy at `C:\Users\Blake\.codex\skills\taiga-story-loop` contain the
same 39 files. After normalizing CRLF/LF line endings, every corresponding file
is text-equal and there is no conflicting decision-point guidance or semantic
copy drift. The comparison is present-day evidence only; it cannot prove that
the historical worker loaded this exact copy at the time of the GroceryRecipeWizard
run. No installed file was modified.

## Root causes, unknowns, and change boundaries

### Root causes supported by the evidence

1. The workflow lacked an observable, mandatory delivery-confirmation
   boundary in the historical execution: a worker could reach a ready-looking
   response without a confirmed direct reviewer message.
2. Acceptance reconciliation had a state-transition endpoint but not a
   required substantive-work endpoint: setting the next task to `In progress`
   could be mistaken for beginning that task.
3. The terminal handoff rule was present as instruction, but the historical
   sequence was not mechanically prevented from continuing with waits/reads.

These are workflow transition/adherence hypotheses grounded in the recorded
sequences. The evidence does not support blaming Luna, a specific model
profile, or an undisclosed tool target.

### Historical unknowns kept explicit

- The exports do not establish the target of every `wait_threads` or
  `read_thread` entry, so only the anchored post-dispatch examples are
  attributed to the polling failure.
- The installed copy comparison cannot establish what copy was loaded during
  the historical run.
- No live story-loop rerun was authorized or performed here; live adherence is
  unverified.

### Mechanical versus instruction-only coverage

The existing `validate-automatic-review-flow.ps1` is the smallest mechanical
seam: it already models implementer action traces, terminal handoff suffixes,
post-termination action rejection, direct acceptance, ordered advancement,
final-story review, duplicate/stale events, and healthy recovery. The routing,
continuation-note, task-execution, and scenario validators provide adjacent
seams for destination identity, quiet recovery, version-safe ordered gates, and
contract presence. Their synthetic traces do not control a live agent.

Tasks #102 and #103 own the guidance edits. Task #104 owns adding the missing
negative/positive action-sequence cases and substantive-next-task control at
these existing seams. Task #105 owns the integrated report and safe trial
procedure. Task #101 intentionally changes none of those resources.

## Focused verification

All commands below were run from the story worktree with PowerShell 7.6.6;
they are offline/synthetic checks and do not claim live provider behavior:

| Command | Exit | Result |
| --- | ---: | --- |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-routing.ps1` | 0 | Direct readiness, correction, acceptance, stable-pair, and exceptional-routing fixture passed. |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-automatic-review-flow.ps1` | 0 | Terminal handoff, post-termination rejection, resume, reconciliation, advancement, final-review, duplicate/stale, and recovery fixture passed. |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-continuation-note.ps1` | 0 | Snapshot replacement, stale recovery, no-duplicate action, evidence preservation, and gate-preservation fixture passed; live heartbeat not exercised. |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-task-execution.ps1` | 0 | Ordered-task, reviewable-endpoint, failed-check, blocker, expected-red, deferred, final-review, commit, and parent-comment assertions passed. |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-scenarios.ps1` | 0 | Static contract, recorded-walkthrough, routing, automatic-flow, setup, and acceptance-evidence assertions passed; no live browser/provider evidence claimed. |
| `git diff --check` | 0 | No whitespace errors in the task revision. |

The first exploratory invocation through Windows PowerShell 5.1 exposed host
compatibility issues in two scripts (`.Count` on a scalar in routing and
`Path.IsPathFullyQualified` in continuation-note). Re-running the same checks
under the repository-compatible PowerShell 7 host passed; those exploratory
failures are not repository assertion results.

## Task #101 boundary

This document is the evidence-backed diagnosis and seam map. It does not claim
that guidance corrections, new action-sequence regressions, a live trial,
active-skill installation, or PR/merge delivery have happened. Those remain in
the ordered owners named above.
