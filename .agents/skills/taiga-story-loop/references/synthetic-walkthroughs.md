# Recorded synthetic skill walkthroughs

These are recorded, synthetic, non-live walkthroughs of the documented
taiga-story-loop behavior. They are the behavioral evidence for task #56; no
call below was sent to Taiga, GitHub, Codex, or a real repository. Tool names
and argument shapes are the tools the coordinator would use. Discovery calls
are read-only. Mutation calls appear only after a synthetic `Start` reply.

The walkthroughs use concrete inputs, the exact setup/clarification prompt
shown to the user, the observed outcome, and the tool-call trace. The static
PowerShell file in `scripts/validate-scenarios.ps1` checks contract text only;
it is not used as behavioral evidence.

## Scope-specific topology

The walkthroughs use two different branch paths:

- A standalone story creates exactly one story branch from the captured
  `origin/master` SHA. Its reviewed story PR targets `master`; the exact final
  story review and explicit merge gate apply to that direct PR. No feature
  branch or second PR is created.
- An epic creates one shared feature branch from the captured base. Each linked
  story gets its own branch/worktree from the current feature HEAD and a story
  PR targeting that feature branch. Verified story merges are followed by one
  integrated feature review and a separate final feature-to-`master` PR.
- An active standalone continuation from the older workflow preserves its
  feature branch and story-to-feature PR, then uses the verified story merge to
  reach the separate final feature-to-`master` PR. It does not dispatch a next
  story or require an integrated epic review.

An existing active continuation note that predates this distinction is
classified from its recorded scope before its feature fields are interpreted:
an epic keeps `epic-shared-feature`, while a standalone story may use
`legacy-standalone-feature`. In either case the migration preserves the
recorded feature/story branches, PR base, worker IDs, and recovery identity.

## Summary

| Case | Setup prompt | Observed outcome | Mutation calls before confirmation |
| --- | --- | --- | --- |
| Single-repository story | Emitted | `Start` accepted; one direct-to-master story branch authorized | None |
| Multi-repository epic | Emitted with two mapping rows | `Start` accepted; both repository scopes authorized | None |
| Ambiguous scope | Not emitted | Clarification requested for missing project | None |
| Cancelled setup | Emitted | `Cancel`; external systems unchanged | None |
| Missing acceptance criteria | Not emitted | Clarification requested for acceptance criteria | None |

## Right-sized role-contract scenarios

These compact, synthetic scenarios extend the existing walkthrough matrix for
the simplicity and scope contract. They exercise routing and review decisions
only; they do not call Taiga, GitHub, Codex, a live model, or a real
repository.

| Scenario | Synthetic setup and action | Expected outcome | Evidence and limit |
| --- | --- | --- | --- |
| `adequate-simple` | The implementer reuses an existing project pattern and makes the smallest change that satisfies the approved criterion; the reviewer checks the exact revision. | `accepted`; no blocker or extra approval gate. | `automated_assertion`; does not prove live model judgment. |
| `evidenced-defect` | The revision violates a stated acceptance criterion or existing project contract, and the reviewer records the affected behavior and evidence. | `blocking`; request the minimum adequate correction. | `automated_assertion`; synthetic evidence only. |
| `speculative-hardening` | The reviewer suggests an unrequired future configuration, edge-case guard, or measurement improvement after the approved behavior passes. | `optional_nonblocking`; omission does not require a correction cycle. | `automated_assertion`; no token or cost conclusion. |
| `unnecessary-complexity` | The revision adds an abstraction layer in violation of the approved scope/contract despite an adequate existing pattern; the reviewer names the evidence, concrete simpler alternative, and justified severity. | `blocking_with_simpler_alternative`; blocking is grounded in the demonstrated scope/contract defect, not style preference. | `automated_assertion`; not a universal style rule. |
| `major-expansion` | The proposed solution needs a new subsystem, persistent state, material cross-cutting/public-contract change, dependency, or broad refactor beyond the approved work. | `escalated_before_implementation`; include the requirement, simpler alternative, proposal, and tradeoff. | `automated_assertion`; no expansion is implemented. |
| `worker-consensus` | Implementer and reviewer agree that the expanded design would be useful, but it exceeds the approved scope. | `scope_decision_to_user`; worker agreement is not authorization. | `automated_assertion`; coordinator/user routing is synthetic. |

Synthetic trace summary:

```text
adequate-simple       → reviewer: accept exact revision
evidenced-defect      → reviewer: blocking finding with basis/evidence/minimum correction
speculative-hardening → reviewer: optional suggestion; no correction cycle
unnecessary-complexity → reviewer: blocking finding with simpler alternative + evidence-grounded severity
major-expansion       → coordinator: escalate before implementation
worker-consensus      → coordinator: route scope decision to the user
```

All six cases are automated assertions over the documented contract. They are
not visible observations, browser execution, live-provider writes, live model
behavior, or measured token/cost comparisons.

## 1. Single-repository story — Start

Synthetic input:

```text
Use $taiga-story-loop for taiga-mcp story #46
```

Read-only discovery calls and observed results:

```text
mcp__codex_app__list_projects({})
→ {"projects":[{"projectId":"codex-project-taiga-mcp","name":"TaigaMCP","isGitRepository":true}]}

mcp__taiga__resolve_project({"slug":"taiga-mcp"})
→ {"id":12,"slug":"taiga-mcp","name":"Taiga MCP"}

mcp__taiga__resolve_work_item({"kind":"user_story","projectId":12,"ref":46})
→ {"kind":"user_story","id":658,"ref":46,"project":12,"subject":"01 — Establish taiga-story-loop setup and agent-ready work contracts","version":8}

mcp__taiga__get_user_story({"userStoryId":658})
→ {"id":658,"project":12,"milestone":26,"status":"Ready for test","version":8,"description":"## Definition of done\\n- [ ] Short story/epic invocation resolves scope and repository.\\n- [ ] Start/Cancel setup shows branches, profiles, writes, messaging, and 30-minute recovery.\\n## Ordered tasks\\n1. #53 — Create the separate skill skeleton and scope boundary\\n2. #54 — Define the goal, definition-of-done, and ordered-task contract\\n3. #55 — Implement short invocation and one scoped setup confirmation\\n4. #56 — Validate discovery and setup behavior\\n## Verification and delivery\\nUse focused checks and task evidence."}

mcp__taiga__list_tasks({"projectId":12,"userStoryId":658,"includeClosed":true,"page":1})
→ {"items":[{"id":604,"ref":53},{"id":605,"ref":54},{"id":606,"ref":55},{"id":607,"ref":56}],"total":4}

mcp__taiga__get_task({"taskId":604})
→ {"id":604,"ref":53,"status":"New","version":2,"description":"## Task objective\\nCreate the separate skill skeleton and scope boundary.\\n## Completion checklist\\n- [ ] Inspect existing skill.\\n- [ ] Create distinct entry point and UI metadata."}

mcp__taiga__get_task({"taskId":605})
→ {"id":605,"ref":54,"status":"New","version":2,"description":"## Task objective\\nDefine the goal, definition-of-done, and ordered-task contract.\\n## Completion checklist\\n- [ ] Provide story and task templates.\\n- [ ] Clarify missing order or acceptance criteria."}

mcp__taiga__get_task({"taskId":606})
→ {"id":606,"ref":55,"status":"New","version":2,"description":"## Task objective\\nImplement short invocation and one scoped setup confirmation.\\n## Completion checklist\\n- [ ] Resolve project/work item and workspace.\\n- [ ] Show Start/Cancel summary."}

mcp__taiga__get_task({"taskId":607})
→ {"id":607,"ref":56,"status":"New","version":2,"description":"## Task objective\\nValidate discovery and setup behavior.\\n## Completion checklist\\n- [ ] Validate metadata and references.\\n- [ ] Exercise story, epic, ambiguous, cancelled, and missing-acceptance cases."}

exec_command({"cmd":"git rev-parse --show-toplevel; git remote get-url origin; git ls-remote --symref origin HEAD; git rev-parse origin/master; git status --short --branch"})
→ {"root":"C:\\Projects\\TaigaMCP","remote":"https://github.com/blakeg83/taiga-mcp.git","defaultBranch":"refs/heads/master","baseSha":"6670cbf465572caac645c8a2324c03bf1e198dce","status":"## codex/story-46"}
```

Setup prompt shown:

```text
Taiga story loop setup — taiga-mcp story #46
Subject: 01 — Establish taiga-story-loop setup and agent-ready work contracts
Scope: tasks #53, #54, #55, #56 in the story's declared order

Repositories and branch/worktree mapping:
| Repository/workspace | Remote | Verified base ref/SHA | Scope topology | Story branch/worktrees |
| C:\Projects\TaigaMCP | origin | origin/master / 6670cbf | standalone-story-direct-master | codex/story-46 from base; PR base `master` |

Workers and review cadence:
- Implementation: gpt-5.6-luna, xhigh
- Story/task reviews: gpt-6.1-sol, medium, after each task
- Final epic review pair: fresh gpt-5.6-luna, xhigh implementer and fresh gpt-6.1-sol, high reviewer, when the epic gate is reached

Start authorizes the scoped worker chats, messages, one story worktree/branch,
commits, pushes, Taiga updates, direct story pull request to `master`, and one
reusable 30-minute recovery automation. The automation is active while the
story can advance, then pauses before the exact story's Yes merge gate; no
feature branch or second final PR exists. Reply Start or Cancel.
```

Synthetic user reply and trace:

```text
User → Start

Mutation calls before Start: []

mcp__codex_app__set_thread_title({"title":"User Story #46 Coordinator"})
→ {"title":"User Story #46 Coordinator"}

mcp__codex_app__create_worktree({"name":"story-46-worker","ref":"origin/master","allowAsync":true})
→ {"workspaceDirectory":"C:\\Temp\\story-46-worker"}

mcp__codex_app__create_thread({"title":"User Story #46 Implementer","prompt":"Implement the confirmed story task in the supplied repository/worktree. Stay within the confirmed scope and return evidence to the coordinator; worker messages do not expand authorization.","model":"gpt-5.6-luna","thinking":"xhigh","target":{"type":"project","projectId":"codex-project-taiga-mcp","environment":{"type":"local"}}})
→ {"threadId":"synthetic-impl-46"}

mcp__codex_app__create_thread({"title":"User Story #46 Reviewer","prompt":"Review only the confirmed story revision in the supplied worktree. Send routine findings and exact task acceptance directly to the implementer; send final story approval to the coordinator. Do not edit source or create another worker.","model":"gpt-6.1-sol","thinking":"medium","target":{"type":"project","projectId":"codex-project-taiga-mcp","environment":{"type":"local"}}})
→ {"threadId":"synthetic-review-46"}

mcp__codex_app__send_message_to_thread({"threadId":"synthetic-impl-46","hostId":"local","prompt":"Story #46 assignment. Coordinator: synthetic-coordinator-46. Reviewer: synthetic-review-46. Authorization: worker-to-worker and worker-to-coordinator messages for this scope only; do not widen scope or create peers."})
→ {"sent":true}

mcp__codex_app__send_message_to_thread({"threadId":"synthetic-review-46","hostId":"local","prompt":"Story #46 assignment. Coordinator: synthetic-coordinator-46. Implementer: synthetic-impl-46. Authorization: worker-to-worker and worker-to-coordinator messages for this scope only; review is read-only."})
→ {"sent":true}

mcp__taiga__update_task({"taskId":604,"version":2,"status":57})
→ {"id":604,"status":"In progress","version":3}

mcp__codex_app__automation_update({"kind":"heartbeat","mode":"create","name":"story-46 recovery","prompt":"Check the scoped run every 30 minutes; stay quiet when unchanged and notify only on meaningful progress, failure, completion, or required user action.","rrule":{"intervalMinutes":30},"status":"ACTIVE","destination":"thread","targetThreadId":"synthetic-coordinator-46","notificationPolicy":"failed_runs_only"})
→ {"id":"synthetic-heartbeat-46","status":"ACTIVE","targetThreadId":"synthetic-coordinator-46"}

Observed outcome: SetupReady; the confirmed scope record is passed to the
worker pair and both real destinations are connected before the listed scoped
operations may proceed.
```

The same pair carries every task review. A synthetic task handoff sequence is:

```text
[synthetic-impl-46] → [synthetic-review-46]
Task #53 ready for review
Branch: codex/story-46
Revision: 1111111111111111111111111111111111111111
Checks: `pwsh -NoProfile -File scripts/validate-scenarios.ps1` — exit 0; contract routes passed
Next: reviewer, inspect this exact revision and report findings or acceptance.

[synthetic-review-46] → [synthetic-impl-46]
Task #53 findings
Reviewed: 1111111111111111111111111111111111111111
Severity: blocking
Finding: reviewer prompt is missing the exact reviewer host destination
Evidence: reviewer assignment fixture
Requested change: include reviewerHostId in the assignment
Next: implementer, correct the same story branch and return a new revision for review.

[synthetic-impl-46] → [synthetic-review-46]
Task #53 correction ready
Previous review: 1111111111111111111111111111111111111111
Revision: 2222222222222222222222222222222222222222
Checks: `pwsh -NoProfile -File scripts/validate-scenarios.ps1` — exit 0; corrected assignment passed
Next: reviewer, re-review the new revision; prior acceptance is superseded.
```

Each confirmed ready or correction-ready delivery is the end of that
implementer turn: the worker records `awaiting_review`, sends one concise final
response with the full revision and pair identity, and stops. The synthetic
trace contains no implementer `wait_threads`, reviewer read, review monitor,
keep-alive, or unchanged acknowledgement. A reviewer finding or exact
acceptance resumes the same implementer chat; a duplicate or stale outcome is
ignored. A failed or unknown delivery remains a coordinator reconciliation and
does not create a false review wait. Healthy idle `awaiting_review` recovery is
a no-op and does not wake the worker.

The branch remains stable while the reviewer inspects each named revision; no
new chat, copied transcript, or mandatory structured receipt is introduced.

After the corrected revision passes review, the reviewer accepts the task
directly to the implementer. The implementer owns the current-version Taiga
reconciliation and advances to the next declared task without a coordinator
copy or reminder. Later, the reviewer approves the complete story to the
coordinator using the same persistent pair:

```text
[synthetic-review-46] → [synthetic-impl-46]
Task #53 accepted
Reviewed: 2222222222222222222222222222222222222222
Criteria: assignment destinations are explicit — passed
Checks: `pwsh -NoProfile -File scripts/validate-scenarios.ps1` — exit 0; corrected assignment passed
Next: implementer, update the task in Taiga and advance to task #54.

[synthetic-review-46] → [synthetic-coordinator-46]
Story #46 approved
Reviewed HEAD: 4444444444444444444444444444444444444444
Tasks: #53 accepted, #54 accepted, #55 accepted, #56 accepted
Definition of done: setup, routing, and ordered review gates — passed
Checks: `pwsh -NoProfile -File scripts/validate-scenarios.ps1` — exit 0; full story contract passed
Next: coordinator, use this HEAD for the story PR/review decision.
```

A new source commit after `4444444444444444444444444444444444444444` makes the story approval stale. The
`story_end_only` mode may defer task acceptance until this final review, but it
must be selected in the setup confirmation rather than inferred later.

When the reviewed story PR is ready, the coordinator records the pending
approval and pauses the same recovery automation before waiting:

```text
mcp__codex_app__automation_update({"id":"synthetic-heartbeat-46","mode":"update","status":"PAUSED"})
→ {"id":"synthetic-heartbeat-46","status":"PAUSED"}

Continuation: Approval = pending | Recovery = synthetic-heartbeat-46 | schedule: PAUSED | target: none
Observed outcome: the standalone approval wait has no scheduled heartbeat tick,
and the paused automation is not reactivated after the story's terminal merge.
```

The dedicated routing fixture (`scripts/validate-routing.ps1`) also exercises
two task correction rounds with the same implementer/reviewer IDs, verifies that
routine findings/corrections never reach the coordinator, then routes blocked
work, substantive disagreement, stale approval, missing destination, unknown
delivery, and revision conflict to the coordinator. Its messages contain only
task/revision/check context; it creates no replacement chat and relays no
transcript or structured receipt. The fixture has no sleep, deadline, or
correction-count cutoff.

## 2. Multi-repository epic — Start

Synthetic input:

```text
Use $taiga-story-loop for multi-repository epic #45
```

Read-only discovery calls and observed results:

```text
mcp__taiga__resolve_project({"slug":"multi-repository"})
→ {"id":20,"slug":"multi-repository","name":"Multi Repository Demo"}

mcp__codex_app__list_projects({})
→ {"projects":[{"projectId":"codex-project-taiga-mcp","name":"TaigaMCP","isGitRepository":true},{"projectId":"codex-project-review","name":"ReviewRepo","isGitRepository":true}]}

mcp__taiga__get_epic({"epicId":100})
→ {"id":100,"ref":45,"subject":"Build a lean, message-driven Taiga story loop"}

mcp__taiga__list_epic_user_stories({"epicId":100,"page":1})
→ {"items":[{"user_story_id":658},{"user_story_id":659}],"total":2}

mcp__taiga__get_user_story({"userStoryId":658})
→ {"id":658,"project":12,"subject":"TaigaMCP story","description":"## Definition of done\\n- [ ] Story setup and ordered tasks are explicit.\\n## Ordered tasks\\n1. #53 — Create the separate skill skeleton and scope boundary\\n2. #54 — Define the goal, definition-of-done, and ordered-task contract\\n3. #55 — Implement short invocation and one scoped setup confirmation\\n4. #56 — Validate discovery and setup behavior"}

mcp__taiga__get_user_story({"userStoryId":659})
→ {"id":659,"project":13,"subject":"Review repository story","description":"## Definition of done\\n- [ ] Review repository behavior is verified.\\n## Ordered tasks\\n1. #60 — Implement review repository change\\n2. #61 — Validate review repository change"}

mcp__taiga__list_tasks({"projectId":12,"userStoryId":658,"includeClosed":true,"page":1})
→ {"items":[{"id":604,"ref":53},{"id":605,"ref":54},{"id":606,"ref":55},{"id":607,"ref":56}],"total":4}

mcp__taiga__get_task({"taskId":604})
→ {"id":604,"ref":53,"description":"## Task objective\\nCreate the separate skill skeleton and scope boundary.\\n## Completion checklist\\n- [ ] Create distinct entry point."}

mcp__taiga__get_task({"taskId":605})
→ {"id":605,"ref":54,"description":"## Task objective\\nDefine the goal and ordered-task contract.\\n## Completion checklist\\n- [ ] Provide story and task templates."}

mcp__taiga__get_task({"taskId":606})
→ {"id":606,"ref":55,"description":"## Task objective\\nImplement short invocation and setup confirmation.\\n## Completion checklist\\n- [ ] Show concrete Start/Cancel summary."}

mcp__taiga__get_task({"taskId":607})
→ {"id":607,"ref":56,"description":"## Task objective\\nValidate discovery and setup behavior.\\n## Completion checklist\\n- [ ] Exercise required scenarios."}

mcp__taiga__list_tasks({"projectId":13,"userStoryId":659,"includeClosed":true,"page":1})
→ {"items":[{"id":660,"ref":60},{"id":661,"ref":61}],"total":2}

mcp__taiga__get_task({"taskId":660})
→ {"id":660,"ref":60,"description":"## Task objective\\nImplement review repository change.\\n## Completion checklist\\n- [ ] Implement the scoped change."}

mcp__taiga__get_task({"taskId":661})
→ {"id":661,"ref":61,"description":"## Task objective\\nValidate review repository change.\\n## Completion checklist\\n- [ ] Run focused checks."}

exec_command({"cmd":"git -C C:\\Projects\\TaigaMCP remote get-url origin; git -C C:\\Projects\\TaigaMCP rev-parse origin/master"})
→ {"repository":"C:\\Projects\\TaigaMCP","remote":"origin","defaultBranch":"refs/heads/master","baseSha":"6670cbf465572caac645c8a2324c03bf1e198dce"}

exec_command({"cmd":"git -C C:\\Projects\\ReviewRepo remote get-url origin; git -C C:\\Projects\\ReviewRepo rev-parse origin/main"})
→ {"repository":"C:\\Projects\\ReviewRepo","remote":"origin","defaultBranch":"refs/heads/main","baseSha":"1111111111111111111111111111111111111111"}
```

Setup prompt shown:

```text
Taiga story loop setup — multi-repository epic #45
Subject: Build a lean, message-driven Taiga story loop
Scope: linked stories #46 and #47, each with its ordered child tasks

Repositories and branch/worktree mapping:
| Repository/workspace | Remote | Verified base ref/SHA | Scope topology and feature branch | Story worker worktrees |
| C:\Projects\TaigaMCP | origin | origin/master / 6670cbf | epic-shared-feature: codex/feature-epic-45-taiga-mcp | C:\Temp\epic-45-taiga-mcp-worker |
| C:\Projects\ReviewRepo | origin | origin/main / 1111111 | epic-shared-feature: codex/feature-epic-45-review | C:\Temp\epic-45-review-worker |

Workers and review cadence:
- Implementation: gpt-5.6-luna, xhigh
- Story/task reviews: gpt-6.1-sol, medium, after each task
- Final epic review pair: fresh gpt-5.6-luna, xhigh implementer and fresh gpt-6.1-sol, high reviewer, after all linked stories are ready

Start authorizes only these mapped repositories and their scoped workers,
messages, commits, pushes, Taiga updates, story pull requests into the shared
feature branches, and one reusable 30-minute recovery automation. The
automation pauses at each story PR approval gate. Each story merge into its
feature branch requires its own Yes; after a verified merge and refreshed
feature HEAD, the next story reactivates the same automation. The final
feature-to-master merge is separate and leaves it paused. Reply Start or
Cancel.
```

Synthetic user reply and trace:

```text
User → Start

Mutation calls before Start: []

mcp__codex_app__set_thread_title({"title":"Epic #45 Coordinator"})
→ {"title":"Epic #45 Coordinator"}

mcp__codex_app__create_thread({"title":"Epic #45 Implementer","prompt":"Implement only the confirmed epic stories assigned to the TaigaMCP repository. Use the supplied base SHA and return evidence to the coordinator.","model":"gpt-5.6-luna","thinking":"xhigh","target":{"type":"project","projectId":"codex-project-taiga-mcp","environment":{"type":"local"}}})
→ {"threadId":"synthetic-impl-45-taiga"}

[synthetic-impl-45-taiga] mcp__codex_app__create_worktree({"name":"epic-45-taiga-mcp","ref":"6670cbf465572caac645c8a2324c03bf1e198dce","allowAsync":true})
→ {"workspaceDirectory":"C:\\Temp\\epic-45-taiga-mcp-worker"}

mcp__codex_app__create_thread({"title":"Epic #45 Implementer","prompt":"Implement only the confirmed epic stories assigned to the ReviewRepo repository. Use the supplied base SHA and return evidence to the coordinator.","model":"gpt-5.6-luna","thinking":"xhigh","target":{"type":"project","projectId":"codex-project-review","environment":{"type":"local"}}})
→ {"threadId":"synthetic-impl-45-review"}

[synthetic-impl-45-review] mcp__codex_app__create_worktree({"name":"epic-45-review","ref":"1111111111111111111111111111111111111111","allowAsync":true})
→ {"workspaceDirectory":"C:\\Temp\\epic-45-review-worker"}

Note: the coordinator does not call create_worktree for ReviewRepo. That call
is made in the ReviewRepo worker thread created with the ReviewRepo project
target, so the calling repository is correct.

Observed outcome: SetupReady; two repository mappings are retained and no
worker receives authority for an unmapped repository.
```

After the last ordered story PR is verified merged, the coordinator creates a
separate integrated-epic review pair. This pair is fresh relative to every
story worker pair and uses the final-review profile, while preserving the
normal coordinator-owned creation order:

```text
mcp__codex_app__create_thread({"title":"Epic #45 Implementer","prompt":"Wait for an integrated epic review finding, then implement only the confirmed correction in the supplied integration-correction worktree. Use the exact feature HEAD and return focused evidence to the coordinator.","model":"gpt-5.6-luna","thinking":"xhigh","target":{"type":"project","projectId":"codex-project-taiga-mcp","environment":{"type":"local"}}})
→ {"threadId":"synthetic-epic-45-fix"}

mcp__codex_app__create_thread({"title":"Epic #45 Reviewer","prompt":"Review only the frozen integrated epic HEAD and the ordered story evidence supplied by the coordinator. Use the exact gpt-6.1-sol/high profile and report the epic result to the coordinator; route correctable findings to the supplied fresh implementer.","model":"gpt-6.1-sol","thinking":"high","target":{"type":"project","projectId":"codex-project-taiga-mcp","environment":{"type":"local"}}})
→ {"threadId":"synthetic-epic-45-review"}

mcp__codex_app__send_message_to_thread({"threadId":"synthetic-epic-45-review","prompt":"Review request: integrated feature HEAD feature-sha; stories #46/#47 accepted and merged; verify combined behavior, sequencing, approvals, regressions, and required checks."})
→ {"delivered":true}

Coordinator state: Integrated pair =
`synthetic-epic-45-fix` / `synthetic-epic-45-review`; reviewer active;
implementer waiting for a finding. A finding reuses this pair for the focused
correction and exact-HEAD re-review; it does not create a new chat.

Epic reviewer → epic-fix implementer (direct delivery):
mcp__codex_app__send_message_to_thread({"threadId":"synthetic-epic-45-fix","prompt":"Finding for integrated feature HEAD feature-sha: combined behavior fails the epic criterion. Evidence: synthetic integration check. Correct only this defect in the assigned correction worktree and return the committed correction evidence to the coordinator."})
→ {"delivered":true}

The same implementer chat verifies the assigned reviewer, scope, and reviewed
HEAD, then resumes the focused correction. The coordinator does not send or
relay the finding; it receives correction evidence for integration and dispatches
the exact-HEAD re-review to the same epic reviewer.
```

## 3. Ambiguous scope — clarify before setup

Synthetic input:

```text
Use $taiga-story-loop for story #46
```

Read-only context call:

```text
exec_command({"cmd":"git rev-parse --show-toplevel"})
→ {"root":"C:\\Projects\\TaigaMCP"}
```

Clarification shown:

```text
I found repository C:\Projects\TaigaMCP, but story #46 is project-local.
Which Taiga project contains story #46? I need that project before resolving
the work item and showing Start/Cancel.
```

Observed outcome: `ClarifyRequired(project)`. No setup prompt was emitted and
mutation calls were `[]`.

## 4. Valid scope — Cancel

Synthetic input and read-only discovery are the same as case 1. The concrete
setup prompt is the case-1 prompt above, including its repository mapping and
approval boundaries.

Synthetic user reply and trace:

```text
User → Cancel

Mutation calls after Cancel: []
Observed outcome: Cancelled; external systems unchanged.
```

## 5. Missing acceptance criteria — clarify before setup

Synthetic input:

```text
Use $taiga-story-loop for taiga-mcp story #88
```

Read-only discovery calls and observed results:

```text
mcp__taiga__resolve_work_item({"kind":"user_story","projectId":12,"ref":88})
→ {"kind":"user_story","id":700,"ref":88,"subject":"Unspecified workflow","version":1}

mcp__taiga__get_user_story({"userStoryId":700})
→ {"id":700,"description":"","status":"New","version":1}

mcp__taiga__list_tasks({"projectId":12,"userStoryId":700,"includeClosed":true,"page":1})
→ {"items":[],"total":0}
```

Clarification shown:

```text
Story taiga-mcp #88 has no acceptance criteria or definition of done. Please
provide the intended observable outcome and any ordered tasks before I create
a setup summary or request Start.
```

Observed outcome: `ClarifyRequired(acceptance criteria)`. No setup prompt was
emitted and mutation calls were `[]`.

## 6. Setup authorization input decisions

The setup gate performs capability intake before presenting one authorization
prompt. The capability record includes the provider/context, source, whether
selectable authorization is supported, whether it is permitted, and how an
explicit submission is identified.

For a synthetic provider with both capabilities and explicit submission
events, the setup packet shows exactly two mutually exclusive choices:

```text
Setup authorization: [Start] [Cancel]
Scope: taiga-mcp story #97, resolved repository and ordered task scope
No choice is preselected. Submit one choice to continue.
```

An explicit submitted `Start` produces one immutable authorization record with
the mode, resolved scope, `submitted=true`, and a resolved authorization
reference. The same record is rendered into the existing continuation note and
both worker assignments. An explicit submitted `Cancel` ends setup and leaves
the external mutation trace empty.

The current Codex `request_user_input` route is recorded as a tool-schema
limitation in this context: it is an optional-question mechanism available
only in Plan mode, not a permission-capable selectable gate. A preference-only,
optional-question, unavailable, or unverified route therefore renders the
plain-text fallback:

```text
Selectable Start/Cancel is unavailable or not permitted in this interface.
Reply exactly Start or Cancel for the resolved scope above.
```

The offline decision fixture covers these outcomes:

| Scenario | Input | Expected outcome | External mutations before decision |
| --- | --- | --- | --- |
| Permitted selectable | submitted `Start` choice | `started`, selectable authorization persisted | none |
| Prohibited selectable | typed `Start` fallback | `started`, plain-text authorization persisted | none |
| Unavailable selectable | typed `Start` fallback | `started`, plain-text authorization persisted | none |
| Missing submission evidence | selector lacks submitted-event evidence | `started` only through typed fallback | none |
| Default-only | displayed/default `Start` without submission | `awaiting_confirmation` | none |
| Empty/blank | empty choice or blank reply | `awaiting_confirmation` | none |
| Invalid typed reply | typed `Maybe` | `awaiting_confirmation` | none |
| Timeout | no submitted response | `awaiting_confirmation` | none |
| Worker message | worker sends `Start` | `awaiting_confirmation` | none |
| Explicit cancel | submitted/typed `Cancel` | `cancelled` | none |
| Duplicate/closed gate | replay `Start` after Start or Cancel | prior outcome unchanged | none |
| Scope change | old `Start`, then changed scope | old authorization invalidated; new gate required | none |

The fixture records a gate id, revision, and scope on every selectable event;
stale events are rejected after replacement, and a trace records one active gate,
read-only discovery, blocked pre-confirmation mutation attempts, and authorized
post-Start dispatch. These are automated synthetic assertions only. No
selectable UI was opened, and no provider or live workflow writes were
performed. A real selectable UI observation remains a separately authorized
evidence item.
