# Goal 01: Verify host capabilities and define run configuration

Status: not started.

## Objective

Establish an executable contract for the installed Codex desktop host before building dependent workflow behavior.

## Prerequisites

None. Read the project overview, shared contracts, sources, and execution instructions.
Read [execution instructions](execution-instructions.md) and [shared contracts](contracts.md).

## Deliverables

A capability matrix, versioned run configuration, example worker receipts, and offline fixture boundaries. This goal does not start an operational workflow.

## Ordered steps

### Step 1: Inspect the host and record compatibility

- [ ] Read the currently exposed app tool schemas and record support for project lookup, ordinary chat creation, explicit model/effort, follow-up messaging, result reads/waits, managed worktrees, heartbeat updates, and PR artifact attachment. Verify Git fetch/branch/push plus an authenticated GitHub CLI or connector for PR create/read/update/checks; do not expose credentials.
- [ ] Verify the installed host advertises gpt-5.6-luna/xhigh, gpt-6-sol/high, and gpt-6-astra/medium. Record requested versus observable settings; identify anything that still requires the later smoke exercise.
- [ ] Record PowerShell 7 availability, canonical repository path, existing instructions, and source baseline. Do not inspect credentials or private conversations unrelated to the assignment.
- [ ] Define unsupported-host behavior: stop with a capability report instead of switching to subagents or an SDK/private API.
- [ ] **Validate:** Validate the matrix against actual schemas; use fixtures for unsupported models, absent tools, and unavailable scheduling.
- [ ] **Update documentation:** Document host capabilities and model-selection rules.
- [ ] **Commit before the next step:** `Add automation host capability contract`.

### Step 2: Specify configuration and authority

- [ ] Define required run inputs, exact model profiles, status mappings, completion policy by work type, fetch/base/push configuration, maximum correction rounds, elapsed-time limit, repository ticket capacity, and host worker-turn limit.
- [ ] Define separate fixture and operational modes, and explicit authorization fields for creating/reusing chats, messaging them, feature branches/worktrees, ticket writes, operational push/PR creation, and optional scheduling/merge observation; automatic merging remains disabled.
- [ ] Define repository/ticket identity normalization and an external state-root path shared across worktrees.
- [ ] Write a complete synthetic configuration and invalid examples for unmapped cross-project stories, missing completion statuses, dependency cycles, branch collisions, unknown settings, and forbidden subagents.
- [ ] **Validate:** Validate examples against the documented contract; ensure ordinary model effort is not represented as a guaranteed token allotment.
- [ ] **Update documentation:** Document inputs, defaults, validation errors, and one complete synthetic run.
- [ ] **Commit before the next step:** `Define ticket workflow configuration`.

### Step 3: Define observations and handoff fixtures

- [ ] Specify implementation/review receipt formats and unique run/action correlation fields.
- [ ] Define fake desktop observations for immediate versus pending chat creation, completion, timeout, missing thread, and uncertain send outcome.
- [ ] Define fake Taiga observations for paginated context, epic membership, conflict, ambiguous write, and confirmed update.
- [ ] Define Git/local-bare-remote and fake GitHub observations for fresh versus stale base, push outcome, duplicate PR lookup, head changes, checks, merge and closed-unmerged state; include concurrent and epic fixtures.
- [ ] Separate helper-test decisions from agent-executed host actions; fixture results must not claim a working desktop integration.
- [ ] **Validate:** Check fixture consistency and the reviewed-SHA/scope-hash fields; reject incomplete pass examples.
- [ ] **Update documentation:** Document each fixture's purpose and the actual-host evidence still required.
- [ ] **Commit before the next step:** `Add workflow handoff and failure fixtures`.

### Step 4: Close the design gate

- [ ] Trace every v1 requirement to a goal and fixture; resolve contract inconsistencies before downstream work.
- [ ] Define a host smoke checklist for goal 06, including exact worker settings, canonical worktree receipt, correction follow-up into the same chat, and heartbeat reuse; goal 09 adds the full parallel/PR/epic acceptance matrix.
- [ ] Record unverified capabilities as pending; if a core capability is missing, block only dependent goals and describe the smallest compatible design change.
- [ ] Verify local documentation links and git diff whitespace.
- [ ] **Validate:** Run configuration/fixture checks available at this point; review the design against all shared contracts.
- [ ] **Update documentation:** Update project status and the goal execution record with verified versus pending evidence.
- [ ] **Commit before the next step:** `Finalize automation compatibility gate`.

## Definition of done

- [ ] The host capability matrix is accurate and separates observed schemas from tested operations.
- [ ] Run configuration and handoff formats are complete, with valid/invalid synthetic examples.
- [ ] The no-subagent and exact-model requirements appear in every role contract.
- [ ] Downstream goals have explicit dependencies and verification gates, including goals 07–09.
- [ ] Defaults preserve two active tickets per repository, fresh configured base, automatic authorized push/PR, and no automatic merge.
- [ ] Every completed step has its own focused commit with documentation and validation evidence.

## Execution record

Complete this table as work proceeds. Record each commit hash in the following step or final handoff.

| Step | Result and evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Pending | Pending | Pending |
| 2 | Pending | Pending | Pending |
| 3 | Pending | Pending | Pending |
| 4 | Pending | Pending | Pending |

Record deviations, blockers, and unverified behavior below; do not replace missing evidence with a checked box.
