# Goal 05: Connect the loop to existing Taiga tools

Status: not started.

## Objective

Load complete ticket context and publish evidenced progress/status changes through the current MCP tools without changing their public contracts.

## Prerequisites

Goal 04 complete; expose context/reporting hooks now, then wire PR events in goal 07 and epic aggregation in goal 09. Use fake MCP/HTTP and synthetic credentials for tests. No live Taiga writes for testing.
Read [execution instructions](execution-instructions.md) and [shared contracts](contracts.md).

## Deliverables

Taiga adapter instructions, workflow-specific fixtures, status mapping and finalization behavior, and operator examples.

## Ordered steps

### Step 1: Capture ticket and child-task scope

- [ ] Resolve project/ref/kind, retrieve current detail, and read relevant comments; read all child-task pages including closed tasks for stories.
- [ ] Capture acceptance criteria, selected task IDs, dependencies/blockers described in context, and a stable requirements hash.
- [ ] Handle unknown pagination metadata as incomplete context unless documented behavior establishes exhaustion; do not infer an empty task set.
- [ ] Capture epic detail and every linked-story page plus each story's detail/tasks; resolve cross-project mappings without silently omitting stories. Goal 09 owns parent execution/closure. Route child tasks into the owning story pipeline.
- [ ] **Validate:** Test multiple pages, empty filtered comment pages with continuation, already-closed tasks, missing description, and wrong-project identities.
- [ ] **Update documentation:** Document scope capture and pagination behavior with current tool names.
- [ ] **Commit before the next step:** `Load complete Taiga execution context`.

### Step 2: Map statuses and report progress

- [ ] Resolve project/resource-specific statuses from existing tools and validate configured start/review/awaiting-merge/final IDs for issues, tasks, stories and epics.
- [ ] Keep Taiga assignment separate from agent ownership and preserve assignees unless explicitly requested.
- [ ] Have only the coordinator write milestones: started, ready for review, correction summary, PR delivered, blocker, merged, and completion; include run/action markers and concise revision references.
- [ ] Track authoritative returned versions and write receipts; never store credentials or full test logs in comments.
- [ ] **Validate:** Assert fake tool requests use correct internal IDs, versions and status types; test ambiguous status names, absent final status, and unchanged assignee.
- [ ] **Update documentation:** Document setup choices and progress comment examples.
- [ ] **Commit before the next step:** `Map Taiga workflow states and progress`.

### Step 3: Handle conflicts and uncertain writes

- [ ] Persist each planned comment/status action before the tool call and reconcile its response into the action journal.
- [ ] On version conflict, reread state and evaluate concurrent changes rather than automatically replaying with a new version.
- [ ] On an ambiguous outcome, inspect entity/history/comments for evidence; unresolved outcomes enter needs_input without duplicate submission.
- [ ] Preserve existing transport policy: only a received 401 permits its single authentication replay.
- [ ] **Validate:** Use fixtures for comment-applied/response-lost, status-applied/response-lost, conflicting human edits, and inconclusive history; assert no blind resends.
- [ ] **Update documentation:** Document reconciliation, write failure categories, and recovery decisions.
- [ ] **Commit before the next step:** `Reconcile Taiga conflicts and uncertain writes`.

### Step 4: Finalize tasks and the selected ticket

- [ ] Reread requirements and child scope before finalization; added tasks or changed criteria invalidate the old completion decision until reconciled.
- [ ] Advance only tasks with evidence; represent review-passed and PR-delivered separately. Apply final ticket state only after the configured delivery/merge gate, using goal-07 receipts.
- [ ] Default Done waits for observed merge; automatic merging stays disabled. An explicit leaf PR-delivery policy must not satisfy an epic's merge requirement. Epic closure belongs to goal 09.
- [ ] Record confirmed final receipts, keep finalizing/needs_input on reporting failure, and generate a clear handoff.
- [ ] **Validate:** Run the fake Taiga end-to-end scenario, including a late new child, PR-open versus merged mapping, closed-unmerged PR, and final PATCH failure. If server/test integration changed, run the required .NET matrix.
- [ ] **Update documentation:** Update the implemented automation guide; preserve the 35-tool count and existing MCP reference contracts.
- [ ] **Commit before the next step:** `Finalize reviewed Taiga work with evidence`.

## Definition of done

- [ ] The adapter supports current issue, story, task and epic context/status tools with complete captured scope; parent aggregation is gated until goal 09.
- [ ] All writes use project-specific statuses, authoritative versions, and documented conflict behavior.
- [ ] Task/story completion is evidence-based, distinguishes PR delivery from merge, and cannot implicitly close an epic.
- [ ] No live Taiga data was changed in tests and no public MCP schema changed.
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
