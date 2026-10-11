# Story and task contracts

Use these contracts to turn the selected Taiga pages into a bounded workflow.
They describe what must be known and evidenced; they do not invent product
acceptance criteria or grant permission to perform external writes.

## Story contract

```markdown
# Story: <project> #<ref> — <subject>

## Codex agent goal
<One actionable outcome stated in user/product terms.>

## Scope
- In scope: <work covered by this story>
- Out of scope: <nearby work deliberately excluded>
- Repository/workspace: <resolved repository and path>
- Related epic: <resolved epic or “none”>
- Branch topology: <standalone-story-direct-master, epic-shared-feature, or legacy-standalone-feature for an active resume>

## Dependencies and execution order
1. <task ref> — <subject> — depends on <none or prior task refs>
2. <task ref> — <subject> — depends on <prior task refs>

Unresolved requirements: <none, or the exact questions to resolve before work>

## Definition of done
- [ ] <observable story outcome>
- [ ] <observable verification or delivery outcome>

## Verification and delivery
- Checks: <commands or other evidence appropriate to the changed artifacts>
- Review/approval boundary: <exact story HEAD review and direct-to-master merge for a new standalone story, story integration and final epic/master gates, or the preserved legacy story-to-feature and final master gates>

## Branch topology

Use the selected scope, not a generic default, to choose the branch lineage:

- A standalone story has one managed story branch from the captured base SHA.
  Its story PR targets `master`; final story approval and the explicit merge
  decision are bound to that exact PR and HEAD.
- An epic has one shared feature branch from the captured base SHA. Each story
  receives a managed branch from the current feature HEAD and a PR targeting
  that feature branch. After all story PRs are verified merged, the exact
  integrated feature HEAD receives the final epic review and a separate
  feature-to-`master` PR/approval.
- An active legacy standalone run retains the feature branch and story PR base
  recorded by the older workflow. Its exact story review and story-to-feature
  merge gate are followed by the separate final feature-to-`master` delivery;
  it has no next story and is never a new-run topology.

Do not create a feature branch for a new standalone story. Do not use a
standalone story PR as evidence that an epic story was integrated. See
[scope-specific branch topology](branch-topology.md) for setup, continuation,
and active-run migration rules.
```

## Coordinator dispatch boundary

The same confirmed-dispatch contract applies to a story pair in either
`per_task` or `story_end_only` mode and to the fresh integrated epic-review
pair. Dispatch is not healthy until all of these facts are confirmed:

- both role- and worktree-matched workers have usable real `threadId` and
  `hostId` identities;
- both full scoped assignments have successful delivery results;
- the current continuation snapshot has been replaced with the pair identities,
  assignment-delivery references, branch receipt, authorization summary, and
  cursors; and
- the existing recovery automation is provider-confirmed `ACTIVE` for the
  ordered work it is meant to recover.

Pending creation, missing identity, failed or unknown delivery, an unconfirmed
continuation replacement, or a pending/failed/unknown schedule remains an
unresolved setup result. Reconcile its authoritative outcome before retrying;
preserve confirmed identities and sends, and never create duplicate workers or
replay a confirmed assignment. Setup identity resolution and unknown-outcome
reconciliation end when dispatch is confirmed; they do not authorize foreground
progress monitoring.

After confirmed dispatch, the coordinator immediately ends its foreground turn.
The same rule applies after an integration or exact-HEAD re-review redispatch.
There are no foreground waits, progress polls, keep-alive loops, or routine
transcript, ticket, source, or diff reads after that boundary. Only a current,
scope/revision-bound final approval, integration-ready epic correction, genuine
blocker, scope/revision/authorization conflict, explicit user input, or
evidenced recovery resumes coordinator work. Routine readiness, findings,
corrections, task acceptance, and ordinary re-review remain direct worker-pair
events and do not require a coordinator relay.

The goal must be actionable without prescribing an implementation. Scope is
the selected story's boundary, not a license to expand into neighboring work.
Dependencies are explicit and ordered by the story or by a clarified user
decision; never infer execution order from the order returned by an API. A
definition-of-done item is complete only when its observable evidence is
available.

## Right-sized design and scope

Across implementer, reviewer, and coordinator work, choose the simplest
adequate design that satisfies the acceptance criteria and existing project
contracts. Reuse suitable project patterns and preserve required correctness,
security, cancellation, and compatibility behavior. Routine in-scope choices
belong to the implementer and do not create an additional approval gate.

Major architectural expansion means introducing a new subsystem or persistent
state, materially changing a cross-cutting workflow or public contract, adding
a dependency, or undertaking a broad refactor beyond the approved work. Before
implementation, escalate such an expansion with the requirement, simpler
alternative, proposed approach, and tradeoff. The coordinator routes unresolved
requirement or architectural decisions to the user; agreement between the
implementer and reviewer does not authorize scope expansion.

## Task contract

The reviewable endpoint includes the [clean committed revision
contract](revision-freeze.md): expected repository/worktree and branch, full
committed SHA copied from Git, captured base and relevant diff range/paths, and
clean tracked-source state. A task endpoint that names only a file or behavior
without the revision input is incomplete.

```markdown
## Task <position>/<total>: <project> #<ref> — <subject>

### Objective
<The concrete outcome of this task and its parent-story boundary.>

### Execution position
- Depends on: <none or completed task refs>
- May start when: <prerequisite and status gate>
- Expected result: <artifact or behavior that can be inspected>

### Reviewable endpoint
- Artifact: <the file, fixture, contract, or behavior the reviewer can inspect>
- Review input: <repository/worktree, expected branch, base SHA, full reviewed SHA, diff range/paths, clean tracked-source state>
- Expected check outcome: <pass, or an expected-red checkpoint>
- Expected-red checkpoint: <each named behavior/test, its exact permitted observed failure reason, and safety checks that must pass; use “not applicable” when the expected outcome is pass>
- Deferred criteria: <criterion and its later task/story owner, or “none”>
- Advancement gate: <the evidence and review-mode condition that permits the next task or final story review>

### Completion checklist
- [ ] <observable implementation or documentation result>
- [ ] <focused check and evidence>
- [ ] <review/status/comment/commit handoff result, when applicable>
```

### Verification and acceptance-evidence intake

When a criterion involves a rendered UI, browser, wrapper, benchmark, or
smoke flow, add this evidence plan before implementation. For documentation-
only or non-UI work, record `UI/browser evidence: not applicable` and do not
invent viewport, focus, console, or visible-acceptance requirements.

```markdown
## Acceptance evidence plan
- UI/browser evidence: <not applicable, or the conditional criterion>
- Capability sources/probes: <documentation/tool schema, observed provider and result>
- Production path: <entry point and control proving it was reached>
- Preserved inputs: <required arguments, evidence hints, validation, result semantics>
- Metrics: <operation, counter, unit, sample, warm-up, conditions, baseline, limitations>
- Scenario matrix: <scenario, setup/action, expected/observed, automated|visible|unavailable>
- Smoke: <setup/start/actions/expected results/cleanup, working directory, disposable data>
- Limitations: <unavailable checks and their source, reason, owner, or next action>
```

The plan is conditional on the real story and repository. Read the applicable
installed skill/tool documentation before claiming a capability is missing;
host capability availability is not proof that a check succeeded. A wrapper
or fake must reach the production entry point and preserve the inputs that
matter. Cache hits, adjacent-stage counts, and incomparable timings are not
evidence of reuse or speedup. Scenario records distinguish automated
assertions, visible observations, and unavailable checks. Synthetic fixtures
may validate these rules but must never be reported as browser execution.

Keep each checklist item observable and specific enough to verify. The
reviewable endpoint is part of the assignment before implementation starts; a
missing or ambiguous artifact, expected outcome, deferred owner, or advancement
gate requires a narrow clarification before dependent work. A task is ready for
review when its implementation evidence and endpoint evidence are complete;
that is distinct from reviewer acceptance or a closed/done status.

For an authoritative test-first checkpoint, the expected-red entry names each
behavior/test and its exact permitted failure reason. The observed failure set
must match those declarations one-for-one: every declared test has its
permitted reason, and no undeclared test or alternate reason is accepted. The
entry also shows the relevant safety checks passing. A nonzero command exit by
itself is not evidence of a valid RED. Unexpected failures or missing
regression/safety coverage keep the task in progress and cannot release
dependent work.

Deferred criteria remain visible on the task until the named later task or
final story review supplies evidence. The advancement gate states whether the
selected `per_task` or `story_end_only` mode controls release; it never silently
waives a deferred criterion or invents an allowed failure.

## Discovery and clarification rules

1. Read the complete story page, its definition of done, and every associated
   task page before coding. Capture each task's internal ID, displayed ref,
   subject, description, status, version, parent story, and dependency cues.
2. Preserve the user's wording and the Taiga acceptance criteria. Translate
   them into the contract without silently weakening, broadening, or replacing
   them.
3. Use the story's ordered-task section when present. If order, repository,
   acceptance criteria, or a dependency is missing or materially ambiguous,
   ask the narrow clarification needed before starting the affected task. Do
   not fill the gap with broad speculative planning.
4. Keep setup permissions and engineering implementation separate: the
   contract records the intended scope and evidence, while the later setup
   confirmation records which external operations the user authorizes.
5. Keep the task status and checklist aligned with evidence. If a review finds
   a substantive defect, reopen the affected task and update the contract
   evidence rather than marking it done by momentum.
