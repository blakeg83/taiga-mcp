# Story #208 coordinator-idle validation

This report records the offline validation for Taiga user story #208,
“Coordinator waits to hear from workers by default.” It is the evidence
companion for ordered task #213 and the accepted implementation tasks #209–#212.
The fixtures use synthetic state; they do not demonstrate live worker-chat,
heartbeat, Taiga, GitHub, or browser behavior.

## Frozen scope and lineage

| Field | Value |
| --- | --- |
| Repository | `C:\Projects\TaigaMCP` |
| Managed worktree | `C:\Users\Blake\.codex\worktrees\story-208-coordinator-idle-20261011\TaigaMCP` |
| Branch | `codex/story-208-coordinator-idle-20261011` |
| Story base SHA | `43bcdfe0ad42ab98643ec7023566f96210fc2db5` |
| Accepted task #209 | `4e9a913b34d56bd02fbbe27e0b4bf338d400bb70` |
| Accepted task #210 | `d40c58f98eaf7d957b383d90e86cedaf317ba3ce` |
| Accepted task #211 | `f94a1c051c4eed877c85d75c50fbfac974ebb603` |
| Accepted task #212 | `0ba3dc184ece8744d2e63b5b9f5c45a9da5f82eb` |
| Documentation task | #213, verification and evidence-limit reconciliation |

The implementation range is the story base through the accepted task #212
revision. Task #213 adds this report and the cross-links described below. The
source checkout is kept separate from the original checkout, and generated
build/output directories are excluded.

## Contract-to-evidence map

| Story criterion | Reconciled contract | Offline evidence |
| --- | --- | --- |
| Confirmed dispatch ends the coordinator turn | `references/contracts.md`, `references/worker-pair.md`, and `references/invocation-and-setup.md` require confirmed identities, assignment delivery, continuation replacement, and an `ACTIVE` schedule before immediate `end_turn`. | `validate-coordinator-lifecycle.ps1` covers story pairs in `per_task` and `story_end_only`, plus the integrated epic pair. Its trace requires `confirmed_dispatch`, `persisted_continuation`, then `end_turn`. |
| Unconfirmed setup is reconciled | `references/continuation-note.md` and `references/invocation-and-setup.md` keep pending, failed, unknown, or missing setup outcomes out of healthy dispatch and forbid guessed replay. | Continuation and final-epic fixtures cover pending/unknown recovery, identity/host binding, and no duplicate assignment. |
| Routine work stays within the pair | `references/routing-and-escalation.md`, `references/automatic-review-flow.md`, and `references/worker-handoffs.md` route readiness, findings, corrections, and per-task acceptance directly. | `validate-routing.ps1`, `validate-automatic-review-flow.ps1`, and the lifecycle fixture assert no routine coordinator action or copy. |
| Integration remains coordinator-owned | `references/final-epic-review.md` and `assets/epic-fix-implementation-prompt.md` retain the integration-ready exception, exact reviewed/corrected revisions, resulting feature HEAD, and same-pair exact-HEAD re-review. | `validate-final-epic-review.ps1` and `validate-coordinator-lifecycle.ps1` cover the integrated correction path, stale-head guard, exact-head dispatch, and persisted redispatch continuation. |
| Healthy heartbeat is bounded and quiet | `references/continuation-note.md` reads the current snapshot first, uses at most one `wait_threads(timeoutMs: 0)` snapshot for eligible workers, retains changed cursors, excludes an `awaiting_review` implementer, and stays quiet when unchanged. | `validate-continuation-note.ps1` and the lifecycle fixture cover quiet, paused, pending, no-target, changed-cursor, missing-identity, failed, unknown, repeated, and blocking outcomes. |
| Resumption requires evidence | `references/automatic-review-flow.md` and `references/acceptance.md` bind resume/acceptance to current task, scope, worker identity, and exact revision; final approval and exceptional events remain coordinator-owned. | Automatic-flow, routing, final-epic, and lifecycle fixtures reject duplicate, stale, correction-only, and unresolved transitions. |
| Offline validation enforces behavior | The lifecycle validator uses state transitions and action ordering rather than keyword-only checks; `validate-scenarios.ps1` also verifies the fixture is wired into the aggregate run. | The complete focused matrix below passed with exit code 0. |
| Evidence states its limits | The report, existing walkthroughs, and fixture output label evidence as synthetic/offline and preserve the separately authorized live-trial boundary. | No live host, provider, browser, PR, merge, or deployment evidence is claimed. |

## Operational walkthrough

1. The coordinator confirms both real worker/host identities, both scoped
   assignment deliveries, a replaced continuation snapshot, and the provider-
   confirmed `ACTIVE` recovery schedule.
2. It records the confirmed dispatch and persisted continuation in order, then
   ends its foreground turn. It does not wait, poll, read transcripts, send a
   keep-alive, or relay routine progress after that boundary.
3. The implementer and reviewer keep routine readiness, findings, correction,
   and task-acceptance messages within the persistent pair. In `per_task`, exact
   task acceptance permits current-version reconciliation and ordered
   advancement. In `story_end_only`, implementation-ready evidence advances
   order without per-task acceptance or review.
4. The coordinator resumes only for a current actionable event, such as final
   story approval, a genuine blocker, an unresolved delivery, or an
   integration-ready epic correction. For integration, it captures the
   resulting feature HEAD, sends exact-head re-review to the same pair, replaces
   continuation with that HEAD and confirmed delivery, and ends the resumed
   turn.
5. A scheduled recovery reads the saved continuation first. It takes at most
   one compact snapshot for eligible running workers and otherwise ends
   silently; an unknown or failed result requires reconciliation rather than a
   replay or reminder.

## Focused offline validation

Commands were run from the managed worktree with PowerShell 7. They use
synthetic fixtures and do not write live Taiga or provider data.

| Command | Exit | Coverage |
| --- | ---: | --- |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-coordinator-lifecycle.ps1` | 0 | Story/epic dispatch termination, both review modes, ordered action traces, direct routes, integration exact-head re-review, approval pause, duplicate/stale guards, and continuation-boundary negatives. |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-continuation-note.ps1` | 0 | Snapshot replacement, bounded heartbeat, cursor retention, paused/pending schedule, missing identity, unknown/failed result, and no-duplicate recovery. |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-automatic-review-flow.ps1` | 0 | Terminal handoffs, direct reviewer resume, acceptance reconciliation, ordered advancement, quiet recovery, and post-dispatch action rejection. |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-routing.ps1` | 0 | Direct readiness, findings, corrections, acceptance, stable pair, and coordinator escalation routes. |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-final-epic-review.ps1` | 0 | Fresh epic pair, reviewer-first dispatch, integrated scope, stale-head guard, isolated correction, and exact-head re-review. |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-setup-authorization.ps1` | 0 | Start/Cancel, capability, duplicate, cancellation, and scope-change authorization gates. |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-merge-approval.ps1` | 0 | Approval gate, stale identity/HEAD, failed merge, correction routing, and quiet recovery. |
| `pwsh -NoProfile -File .agents/skills/taiga-story-loop/scripts/validate-scenarios.ps1` | 0 | Aggregate static contract, walkthrough, lifecycle, routing, automatic-flow, setup, and acceptance-evidence assertions. |
| `git diff --check` | 0 | No whitespace errors in the reviewed source range. |

Task #212 also ran two read-only in-memory mutation controls: removing the
duplicate-dispatch guard and removing integration continuation persistence each
caused the lifecycle fixture to fail at the corresponding assertion, while the
checked-out source remained unchanged. These are synthetic regression controls,
not live-host observations.

## Remaining limits and deferred verification

The validators prove that the documented state machine rejects the targeted
bad action sequences and accepts the bounded healthy sequences. They do not
prove that an active worker, desktop heartbeat, or installed skill copy will
follow those instructions in a live run. No browser evidence is relevant to
this documentation/workflow change. A future live trial would require a new
explicit authorization, disposable Taiga scope, isolated worktree/skill copy,
and exact stop conditions for unknown delivery, version conflict, response
loss, dirty source, and unexpected later-task activity.

No .NET application code changed in this task, so the repository build/test
cycle is not evidence required for this documentation-only revision. Push,
PR creation, merge, deployment, and live Taiga testing remain separate gates.
