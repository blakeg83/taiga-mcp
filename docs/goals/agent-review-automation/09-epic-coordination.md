# Goal 09: Coordinate epics and validate the expanded release

Status: implemented offline; actual expanded chat/provider smoke is pending and was not authorized by this implementation request.

## Objective

Apply the correct workflow to each work type, coordinate all required epic stories through reviewed PRs, and close an epic only after verified integration and epic-level acceptance.

## Prerequisites

Goals 01–08 complete. Use the existing get_epic, list_epic_user_stories, get_user_story/list_tasks, status and update tools; no new Taiga endpoint is required.
Read [execution instructions](execution-instructions.md) and [shared contracts](contracts.md).

## Deliverables

Epic parent/session rules, work-type routing, integrated acceptance evidence, expanded offline/host validation, and final operator documentation.

## Ordered steps

### Step 1: Resolve epic membership and execution scope

- [ ] Read epic detail and every linked-story page, then story details, comments and tasks. Capture a required-story scope snapshot and epic acceptance criteria.
- [ ] Resolve cross-project stories to repositories/configuration; report unmapped scope. Empty or partially read membership is not proof of completion.
- [ ] Use one worker pair/branch/PR per story, reuse an existing claimed story run when appropriate, and keep its child tasks inside that story pipeline.
- [ ] Capture approved dependencies/priority and validate them with goal 08. Existing completed stories require historical review/integration or accepted existing-functionality evidence; never fabricate fresh PRs.
- [ ] **Validate:** Test multiple membership pages, no linked stories, cross-project mapping, shared stories between epics, story already executing independently, and unsupported historical completion claims.
- [ ] **Update documentation:** Document work-type routing, scope approval and existing-story evidence.
- [ ] **Commit before the next step:** `Capture epic scope and reuse story pipelines`.

### Step 2: Aggregate progress and dispatch eligible stories

- [ ] Track each required story's criteria, reviewed revision, PR delivery and integrated evidence independently of its displayed Taiga status.
- [ ] Dispatch ready stories using goal 08; allow independent siblings concurrently and wait for dependent merges. Do not create a giant shared epic feature branch.
- [ ] Report concise epic progress with unique story counts and PR links; a story referenced by two epics is implemented once.
- [ ] Keep parent controls scoped: cancelling/pausing one epic must not cancel a shared story still required by another approved scope. Require explicit authority before messaging a pre-existing unrelated worker chat.
- [ ] **Validate:** Test partial success, blocked sibling, dependency sequencing, shared-story reference counts, leaf PR-delivery policy inside a merge-required epic, and scoped cancellation.
- [ ] **Update documentation:** Document aggregation, partial progress and shared-story ownership.
- [ ] **Commit before the next step:** `Coordinate epic story delivery and progress`.

### Step 3: Verify integrated epic acceptance before closure

- [ ] Reread membership/criteria before closure; added/removed/reopened stories require scope reconciliation rather than automatic inclusion or omission.
- [ ] Require all required stories to have reviewed and merged evidence, then capture the actual integrated base revision(s) and verify combined epic behavior.
- [ ] Have the selected ordinary reviewer assess epic acceptance within the host worker budget. Use a dedicated verification checkout when tests require writes; no source edits to another ticket's worktree.
- [ ] Route integrated defects to an unmerged responsible story or a new explicitly scoped follow-up ticket/PR if the original already merged. Close the epic through update_epic only after acceptance and a confirmed status receipt.
- [ ] **Validate:** Test all stories merged but combined acceptance fails, closed-unmerged story PR, changed scope during acceptance, wrong integration base, missing checks, and failed final epic update.
- [ ] **Update documentation:** Document epic Done evidence, integrated defect handling and closure recovery.
- [ ] **Commit before the next step:** `Gate epic completion on integrated acceptance`.

### Step 4: Validate and document the full release

- [ ] Run the expanded offline matrix across issue, standalone task, story/tasks and epic; include two parallel stories, a merge-dependent third story, correction rounds, PR updates and interrupted recovery.
- [ ] Run required repository checks with fake services, reusing unchanged passing results where justified. Validate local Git fetch/branch/push with disposable bare remotes and provider interactions with fake GitHub/Taiga.
- [ ] When explicitly authorized, run the expanded ordinary-chat/scheduler smoke exercise below; verify worker models, no subagents, separate worktrees, reused conversations and heartbeat shutdown. Record actual-host gaps honestly.
- [ ] Update all nine goal records, operator guide, README, sources and release checklist. Provide operational examples for selected tickets and an epic, preserving no automatic merge and no live-write testing.
- [ ] **Validate:** Check full acceptance evidence, links/formatting and git diff --check. Distinguish offline, actual desktop and optional disposable GitHub-publish verification.
- [ ] **Update documentation:** Publish the expanded release handoff with commit hashes, results and unverified boundaries.
- [ ] **Commit before the next step:** `Validate and document parallel epic automation`.

## Definition of done

- [ ] Issues/standalone tasks have leaf PRs, story tasks share a story PR, and epics coordinate story pipelines.
- [ ] Required stories are fully enumerated, mapped, deduplicated and scheduled by approved dependencies.
- [ ] Epics cannot close merely because all chats ended, all story statuses are closed, or all PRs are open.
- [ ] Every required story is integrated and combined epic acceptance passes at recorded revisions before closure.
- [ ] All nine goals have evidence; actual-host/provider verification gaps remain explicit rather than being inferred from fixtures.
- [ ] Every completed step has its own focused commit with documentation and validation evidence.

## Execution record

Record each commit hash in the following step or final handoff. Leave incomplete gates unchecked.

| Step | Result and evidence | Documentation updated | Commit |
| --- | --- | --- | --- |
| 1 | Required-story scope, cross-project mapping, shared-story deduplication, and existing-evidence rules implemented. | Epic/scheduling references | `f89035b` |
| 2 | Independent story scheduling, dependency sequencing, and partial-progress rules implemented. | Epic/scheduling references | `f89035b` |
| 3 | Integrated acceptance requires all merged stories, current criteria, checks, and epic acceptance before Done. | Taiga finalization and operator guide | `f33e943` |
| 4 | Expanded offline fixture matrix passes; actual expanded host/provider smoke remains pending. | Release documentation | `62223a9` |

Record deviations, blockers and unverified behavior below.

## Explicit expanded local smoke invocation

This is a future user instruction, not authorization granted by the plan:

> Run goal 09's expanded local smoke exercise. Create ordinary gpt-5.6-luna/xhigh implementation and exact gpt-6.1-sol/high review chats for two independent synthetic stories and one dependent story in a disposable local Git project. Coordinate their messages and create a temporary session heartbeat. Use a local bare Git remote plus fake GitHub and Taiga adapters; simulate PR and merge observations without production writes. Verify concurrent isolated worktrees, one correction/re-review cycle, dependency release and epic acceptance, then disable the heartbeat and report evidence. Do not use subagents.

An optional real GitHub publish check requires a separately named disposable repository and explicit authorization. It is not required to mutate a production repository or live Taiga data to pass the automated suite.
