# Story-loop lifecycle evidence

This document began as the task #101 diagnosis for Taiga MCP story #99,
"Fix story-loop worker handoff termination and ordered-task continuation." It
now also closes the ordered task #105 evidence chain with the integrated
offline verification report and a separately authorized live-trial plan. It
does not claim that the historical worker used a particular model incorrectly,
and it is not evidence of a live rerun.

## Scope and acceptance plan

- Story: Taiga MCP #99, internal user-story ID `697`, project `12`.
- Ordered tasks: #101–#105, internal task IDs `774`–`778`.
- Historical run: `story34-20261006-start`.
- UI/browser evidence: not applicable. This task changes workflow guidance and
  evidence documentation, not a rendered product interaction. Capability
  discovery, visible observations, production UI-entry-point controls, and
  smoke execution are therefore not required here; task #105 owns the
  separately authorized live-trial plan.
- Expected endpoint: this document, with attachment/source anchors, the
  integrated criterion map, the complete offline validation matrix, and the
  safe live-trial procedure below.
- Expected result: passing offline checks; no expected-red checkpoint.
- Deferred boundary: live trial execution and active-skill installation remain
  separately authorized operations and are not performed by task #105.

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
| Status-only advancement after #72 acceptance | The implementer’s acceptance-reconciliation report records #72 Closed and #73 `In progress`; the coordinator then observed and recovered an interruption because no substantive #73 implementation/check action had begun. `Coordinator.md` lines 1284–1315 distinguish the implementer report from the coordinator’s recovery. | `acceptance.md` and the assignment require current-version Taiga reconciliation and then ordered advancement. The existing wording did not make the first concrete implementation/check action an observable continuation endpoint. | The implementer’s state write released the next pointer, but the resumed turn ended before work began. `In progress` was treated as progress evidence even though it only changed state. | Tasks #103 and #104: require a same-turn implementation-start action after reconciliation and assert that a status-only stop is rejected. |
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

## Historical task #101 boundary

The sections above preserve the evidence-backed diagnosis and seam map from
task #101. The integrated task #105 report below records what the ordered
implementation actually changed and verified; it does not retroactively claim
that the historical worker loaded the current guidance or that a live rerun
occurred.

## Integrated task #105 report

### Frozen scope and review lineage

The final offline evidence is for the one setup-confirmed story branch:

| Field | Value |
| --- | --- |
| Repository | `C:\Projects\TaigaMCP` |
| Managed worktree | `C:\Users\Blake\.codex\worktrees\story-99-lifecycle\TaigaMCP` |
| Branch | `codex/story-99-lifecycle` |
| PR base | `master` |
| Story base SHA | `837997f617fc99155f6266d3135610d6e7e47429` |
| Accepted task #101 SHA | `5ca9bd59557ee746aecfaa549ff129d7c2edaa35` |
| Accepted task #102 SHA | `3ff764fe375b18ab22288f8fc0952974afda81f4` |
| Accepted task #103 SHA | `a16ee8aa1e0627a4637053e74a9b5d51c9f44bea` |
| Accepted task #104 SHA | `3a11cf890d8970140ea12e19f9d4376577f9af9b` |
| Final task #105 SHA | copied from `git rev-parse HEAD` in the final review packet |
| Ignored verification output | `obj/` only; setup-generated and not part of source review |

The accepted task revisions are exact reviewer-bound endpoints. The final
task revision is intentionally copied from Git only after this report and its
validation evidence are committed; no revision is inferred from a Taiga or
chat identifier. The final packet records the resulting `base..HEAD` range,
changed paths, clean tracked/non-ignored source state, and this report path.

### Failure-to-fix mapping

| Observed failure | Integrated change | Observable evidence |
| --- | --- | --- |
| Missing reviewer dispatch | Ready-turn guidance requires one successful direct delivery before local `awaiting_review`; failed, unknown, and unconfirmed delivery remain coordinator escalations. | `validate-automatic-review-flow.ps1` has separate missing/failed/unknown delivery cases with no review turn, no review action, and explicit escalation. |
| Status-only next-task advancement | Acceptance/reconciliation activates only the next declared task and records a same-turn, current-task, nonblank `source_edit` or `scoped_check` before review-ready dispatch. | The fixture rejects premature `final_response`, rejects premature review dispatch, preserves write/dispatch counts and `In progress` state, rejects wrong-task/empty evidence, and accepts both edit and scoped-check continuations. |
| Polling after confirmed handoff | Initial, correction, and final-story handoffs end with direct dispatch followed immediately by `final_response`; post-termination polling, reads, acknowledgements, edits, and later work are forbidden. | Action traces require the terminal suffix and reject every prohibited post-dispatch action. Healthy idle recovery records no implementer wake. |
| Recovery conflated with healthy waiting | Unresolved delivery, response loss, version conflict, and interrupted reconciliation hold the flow for coordinator reconciliation; healthy `awaiting_review` and unanswered gates remain quiet. | Routing, continuation, task-execution, and automatic-flow fixtures assert separate escalation, reconciliation, and no-wake decisions. |

### Story definition-of-done evidence

| Criterion | Evidence and limitation |
| --- | --- |
| Root cause and copy-drift analysis | Historical attachment anchors, present-day repository/installed-copy comparison, and bounded transition diagnosis above; no unsupported model attribution. |
| Confirmed dispatch before `awaiting_review` | Guidance plus the three separate delivery-outcome fixtures. Provider review status is not treated as message delivery. |
| Terminal initial/correction handoffs | `worker-handoffs.md`, `automatic-review-flow.md`, implementation/reviewer prompts, and action-trace terminal-suffix assertions. |
| Acceptance releases substantive next work | Version-safe task/story reconciliation, marker-bearing progress, `advance_next_task`, and required same-turn edit/check evidence. |
| Exactly one final-story review | Both `per_task` and `story_end_only` fixture paths assert one final review request and terminal response; correction review requires a changed HEAD. |
| Duplicate/stale/conflict safety | Identity, task, SHA, event deduplication, response-loss, version-conflict, and interrupted reconciliation cases preserve counts and holds. |
| Recovery distinction | Missing/interrupted operations escalate or resume only the missing authorized operation; healthy review/user/merge gates receive no wake. |
| Observable regression coverage | Synthetic action traces and state/count assertions reject bad sequences and accept valid ones; keyword presence alone is not used. |
| Existing contracts remain passing | The complete validator matrix below passed with exit code 0. |
| Live adherence disclosure | No live trial or active-skill installation was performed. Live adherence remains unverified and requires a separate explicit user decision. |

### Complete offline validation matrix

All commands were run from the story worktree with PowerShell 7 via
`pwsh -NoProfile -File`. Every validator below exited `0`; fixtures are
synthetic and do not control live agents.

| Command | Exit | Result |
| --- | ---: | --- |
| `.agents/skills/taiga-story-loop/scripts/validate-acceptance-evidence.ps1` | 0 | Capability discovery, production-path controls, metric provenance, scenario classification, honest limitation, and safe smoke-plan assertions passed. |
| `.agents/skills/taiga-story-loop/scripts/validate-automatic-review-flow.ps1` | 0 | Delivery uncertainty, terminal handoffs, post-dispatch rejection, acceptance/reconciliation, substantive edit/check start, final review, duplicate/stale, conflict, interruption, and quiet-recovery traces passed. |
| `.agents/skills/taiga-story-loop/scripts/validate-branch-scenarios.ps1` | 0 | Branch isolation, frozen clean revision, dirty/changed-HEAD guards, ignored output, correction review, PR base, merge failure, and continuation preservation passed. |
| `.agents/skills/taiga-story-loop/scripts/validate-continuation-note.ps1` | 0 | Snapshot replacement, setup persistence, stale recovery, missing/conflicting evidence holds, no-duplicate actions, evidence preservation, gate preservation, and invalid-input checks passed. |
| `.agents/skills/taiga-story-loop/scripts/validate-final-delivery.ps1` | 0 | Direct-master, preserved-feature, and epic final delivery plus exact-head and merge/approval separation passed. |
| `.agents/skills/taiga-story-loop/scripts/validate-final-epic-review.ps1` | 0 | Integrated epic review profile, ordered scope, stale-head guard, correction routing, and exact-head re-review passed. |
| `.agents/skills/taiga-story-loop/scripts/validate-merge-approval.ps1` | 0 | Yes/No merge gate, stale identity/HEAD, failed merge, correction routing, and quiet recovery passed. |
| `.agents/skills/taiga-story-loop/scripts/validate-pr-delivery.ps1` | 0 | Topology-specific PR preflight, dirty/stale/check guards, reuse/create identity, review evidence, and Taiga link evidence passed. |
| `.agents/skills/taiga-story-loop/scripts/validate-routing.ps1` | 0 | Direct readiness/correction/acceptance, stable pair, exceptional routing, and no routine coordinator relay passed. |
| `.agents/skills/taiga-story-loop/scripts/validate-scenarios.ps1` | 0 | Static contracts, walkthroughs, routing, automatic flow, setup, and acceptance-evidence assertions passed. |
| `.agents/skills/taiga-story-loop/scripts/validate-setup-authorization.ps1` | 0 | Selectable Start/Cancel, capability gates, duplicate/cancel, and scope-change authorization scenarios passed. |
| `.agents/skills/taiga-story-loop/scripts/validate-task-execution.ps1` | 0 | Ordered tasks, failed checks, blockers, review rejection, human edits, expected-red, deferred, final review, commit, and parent-comment assertions passed. |
| `git diff --check` | 0 | No whitespace errors in the final task range. |

No application code changed, so the repository Debug/Release build/test cycle
was not required by task #105. No selectable UI/browser evidence is relevant
to this documentation and workflow change.

### Separately authorized live-trial plan

This is a plan only. It is not permission to execute the trial, install over
the active skill copy, message historical workers, modify active automations,
create a PR, merge, or write live product data. A future explicit user
decision must authorize the exact disposable scope and cleanup.

#### Prerequisites and safety gate

1. Obtain a fresh explicit `Start` authorization for story #99's selected
   disposable project/story, repository, worker pair, review mode, branch,
   worktree, base SHA, and allowed external operations. Historical attachments
   and worker chats are evidence only.
2. Use a disposable two-task story with synthetic credentials or an isolated
   provider area. Confirm the task/status mapping, persistent implementer and
   reviewer identities, direct destination, and repository clean state before
   any provider write.
3. Capture event IDs, provider versions, exact Git SHAs, message-delivery
   results, and action timestamps in a separate trial record. Stop and escalate
   on identity mismatch, unknown delivery, dirty source, version conflict,
   response loss, or ambiguous scope; do not blindly retry an uncertain write.

#### Ordered trial actions and expected evidence

| Phase | Authorized action | Expected ordered evidence |
| --- | --- | --- |
| Initial handoff | Complete disposable task #1, commit, confirm current-version task/progress writes, then send one direct ready-for-review message. | `send_review_handoff` succeeds to the assigned reviewer, local state becomes `awaiting_review`, and the final implementer action is `final_response`; no wait/read/poll follows. |
| Induced correction | Have the same reviewer send one exact-revision finding; make a scoped correction and rerun checks. | `reviewer_message_resume`, correction work, one correction handoff to the same reviewer, then terminal `final_response`; no coordinator relay or polling. |
| Acceptance and continuation | Have the reviewer accept the exact corrected SHA; reconcile task closure/checklist and the parent marker with current versions; activate only task #2. | `taiga_reconcile`, `advance_next_task`, then a same-turn task-bound `source_edit` or nonblank `scoped_check`; a status-only response is rejected and task #2 remains held until evidence exists. |
| Final review | Complete task #2, commit, confirm its task/progress state, and request the final story review once. | Exactly one `send_final_story_review` followed by `final_response`; a correction must use a changed final HEAD and exactly one new final-review dispatch. |
| Uncertainty/recovery controls | Separately exercise missing/failed/unknown delivery, response-loss, version conflict, and interrupted reconciliation using only disposable records. | Exceptional cases escalate/hold and require the coordinator's exact reconciliation; a healthy `awaiting_review` or unanswered user/merge gate remains quiet. Resume only the missing authorized operation. |
| Cleanup | Stop after evidence capture, restore/close the disposable work-item scope according to the explicit authorization, and leave PR/merge untouched. | Cleanup record proves no historical worker, active skill, active automation, unrelated Taiga item, PR, or merge was changed. |

#### Trial success and stop conditions

Success requires the exact ordered action traces above, one review dispatch per
ready endpoint, no post-dispatch polling, substantive next-task work in the
same resumed turn, current-version Taiga evidence, and clean final Git
preflight. Stop immediately for an unconfirmed destination, uncertain write,
stale revision, unexpected later-task action, missing final response, or any
attempt to cross the separate user/merge gate. The trial report must classify
each observation as live, synthetic, or unverified and retain the exact
provider/Git/message evidence.

Remaining limitation: until that separate authorization and disposable trial
occur, the implementation proves offline contract behavior only; it does not
prove live adherence by an active worker or installed skill copy.
